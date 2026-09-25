#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${1:-}"
[[ -n "$ROOT" ]] || { echo "Usage: $0 RENDERED_DIR" >&2; exit 1; }

ok()  { printf '[OK] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

required=(
  opensearch/opensearch.yml
  opensearch/jvm.options.d/heap.options
  opensearch-dashboards/opensearch_dashboards.yml
  data-prepper/config/data-prepper-config.yaml
  data-prepper/pipelines/pipelines.yaml
  prometheus/prometheus.yml
  alertmanager/alertmanager.yml
  alertmanager/templates/observability-telegram.tmpl
  process-exporter/process-exporter.yml
)
for rel in "${required[@]}"; do
  [[ -s "$ROOT/$rel" ]] || die "required rendered file missing/empty: $rel"
done
ok "required rendered files present"

if grep -RInE '\{\{[[:space:]]*[A-Z][A-Z0-9_]*[[:space:]]*\}\}' "$ROOT" --exclude='*.tmpl'; then
  die "unresolved configuration placeholders remain"
fi
ok "no unresolved configuration placeholders"

grep -qE '^path\.data:[[:space:]]+/data/opensearch$' "$ROOT/opensearch/opensearch.yml" || die "OpenSearch data path mismatch"
grep -qE '^path\.logs:[[:space:]]+/data/logs/opensearch$' "$ROOT/opensearch/opensearch.yml" || die "OpenSearch log path mismatch"
grep -qE '^plugins\.security\.ssl\.http\.enabled:[[:space:]]+true$' "$ROOT/opensearch/opensearch.yml" || die "OpenSearch HTTP TLS not enabled"
grep -qE '^bootstrap\.memory_lock:[[:space:]]+false$' "$ROOT/opensearch/opensearch.yml" || die "OpenSearch memory-lock reference setting mismatch"
ok "OpenSearch reference semantics present"

grep -qE '^workspace\.enabled:[[:space:]]+true$' "$ROOT/opensearch-dashboards/opensearch_dashboards.yml" || die "Dashboards workspace feature missing"
grep -qE '^data_source\.enabled:[[:space:]]+true$' "$ROOT/opensearch-dashboards/opensearch_dashboards.yml" || die "Dashboards data-source feature missing"
grep -qE '^explore\.discoverTraces\.enabled:[[:space:]]+true$' "$ROOT/opensearch-dashboards/opensearch_dashboards.yml" || die "Dashboards trace discovery missing"
grep -qE '^explore\.discoverMetrics\.enabled:[[:space:]]+true$' "$ROOT/opensearch-dashboards/opensearch_dashboards.yml" || die "Dashboards metric discovery missing"
grep -qE '^opensearch_security\.multitenancy\.enabled:[[:space:]]+false$' "$ROOT/opensearch-dashboards/opensearch_dashboards.yml" || die "Dashboards multitenancy reference setting mismatch"
ok "Dashboards reference feature contract present"

grep -qE '^[[:space:]]+port:[[:space:]]+21890$' "$ROOT/data-prepper/pipelines/pipelines.yaml" || die "Data Prepper trace listener 21890 missing"
grep -qE '^[[:space:]]+port:[[:space:]]+2021$' "$ROOT/data-prepper/pipelines/pipelines.yaml" || die "Data Prepper HTTP log listener 2021 missing"
grep -qE '^[[:space:]]+- prometheus:$' "$ROOT/data-prepper/pipelines/pipelines.yaml" || die "Data Prepper Prometheus sink missing"
grep -q 'index_type: trace-analytics-raw' "$ROOT/data-prepper/pipelines/pipelines.yaml" || die "raw trace sink missing"
grep -q 'index_type: otel-v2-apm-service-map' "$ROOT/data-prepper/pipelines/pipelines.yaml" || die "service-map sink missing"
ok "Data Prepper reference topology present"

grep -qE '^[[:space:]]+scrape_interval:[[:space:]]+30s$' "$ROOT/prometheus/prometheus.yml" || die "Prometheus scrape interval mismatch"
grep -qE '^[[:space:]]+evaluation_interval:[[:space:]]+30s$' "$ROOT/prometheus/prometheus.yml" || die "Prometheus evaluation interval mismatch"
grep -q '127.0.0.1:9256' "$ROOT/prometheus/prometheus.yml" || die "process-exporter scrape missing"
ok "Prometheus reference baseline present"

grep -q 'repeat_interval: 4h' "$ROOT/alertmanager/alertmanager.yml" || die "Alertmanager repeat interval mismatch"
grep -q 'send_resolved: true' "$ROOT/alertmanager/alertmanager.yml" || die "Alertmanager resolved notifications disabled"
ok "Alertmanager reference routing present"

if [[ -x /opt/prometheus/promtool ]]; then
  /opt/prometheus/promtool check config "$ROOT/prometheus/prometheus.yml" >/dev/null || die "promtool rejected rendered Prometheus config"
  ok "promtool accepted rendered Prometheus config"
fi

if [[ -x /opt/alertmanager/amtool ]]; then
  /opt/alertmanager/amtool check-config "$ROOT/alertmanager/alertmanager.yml" >/dev/null || die "amtool rejected rendered Alertmanager config"
  ok "amtool accepted rendered Alertmanager config"
fi

ok "Rendered reference configuration validation passed"
