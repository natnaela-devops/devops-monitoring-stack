#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="${1:-}"
ENV_FILE="${2:-$REPO_ROOT/config/reference.env.example}"
TARGETS_FILE="${3:-$REPO_ROOT/config/prometheus-targets.example.json}"
OUTPUT_DIR="${4:-}"

info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

case "$MODE" in
  --plan|--render) ;;
  *) die "Usage: $0 --plan [ENV_FILE TARGETS_JSON] | --render ENV_FILE TARGETS_JSON OUTPUT_DIR" ;;
esac

[[ -f "$ENV_FILE" ]] || die "environment file not found: $ENV_FILE"
[[ -f "$TARGETS_FILE" ]] || die "Prometheus targets file not found: $TARGETS_FILE"

if [[ "$MODE" == "--plan" ]]; then
  cat <<PLAN
===== REFERENCE CONFIGURATION RENDER GATE =====
Environment file: $ENV_FILE
Target inventory: $TARGETS_FILE

This gate renders private deployment configuration into a staging directory.
It does NOT copy files into /etc or /opt, initialize OpenSearch security,
start/restart/reload services, or modify live data.

Rendered contract:
  - OpenSearch secured single-node configuration + 2 GiB default heap
  - OpenSearch Dashboards workspace/data-source/Explore feature configuration
  - Data Prepper trace 21890 + HTTP log 2021 + Prometheus service-map sink
  - Prometheus 30s scrape/evaluation configuration
  - Alertmanager Telegram routing/template configuration
  - process-exporter process grouping configuration

Private inputs required for --render:
  - Dashboards service-account password file
  - Data Prepper ingest password file
  - target-specific environment parameters

PKI generation, OpenSearch security initialization, installation into live
paths, and service activation are later qualification gates.
===============================================
PLAN
  exit 0
fi

[[ -n "$OUTPUT_DIR" ]] || die "--render requires OUTPUT_DIR as the fourth argument"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

required_vars=(
  ENVIRONMENT
  OBSERVABILITY_NODE_LABEL
  OBSERVABILITY_NODE_IP
  OPENSEARCH_CLUSTER_NAME
  OPENSEARCH_NODE_NAME
  OPENSEARCH_BIND_ADDRESS
  OPENSEARCH_HEAP_SIZE
  OPENSEARCH_NODE_DN
  OPENSEARCH_ADMIN_DN
  OPENSEARCH_HTTPS_ENDPOINT
  OPENSEARCH_CA_CERTIFICATE
  DASHBOARDS_SERVER_NAME
  DASHBOARDS_BIND_ADDRESS
  DASHBOARDS_SERVICE_USERNAME
  DASHBOARDS_SERVICE_PASSWORD_FILE
  DASHBOARDS_ADMIN_USERNAME
  OPENSEARCH_INGEST_USERNAME
  OPENSEARCH_INGEST_PASSWORD_FILE
  DATA_PREPPER_CA_CERTIFICATE
  ALERTMANAGER_TELEGRAM_CHAT_ID
  ALERTMANAGER_TELEGRAM_TOKEN_FILE
  KUBELET_BEARER_TOKEN_FILE
)
for var in "${required_vars[@]}"; do
  [[ -n "${!var:-}" ]] || die "required variable is empty: $var"
done

[[ "$ALERTMANAGER_TELEGRAM_CHAT_ID" =~ ^-?[0-9]+$ ]] || die "ALERTMANAGER_TELEGRAM_CHAT_ID must be an integer"
[[ -s "$DASHBOARDS_SERVICE_PASSWORD_FILE" ]] || die "Dashboards password file missing/empty: $DASHBOARDS_SERVICE_PASSWORD_FILE"
[[ -s "$OPENSEARCH_INGEST_PASSWORD_FILE" ]] || die "Data Prepper ingest password file missing/empty: $OPENSEARCH_INGEST_PASSWORD_FILE"

export DASHBOARDS_SERVICE_PASSWORD
DASHBOARDS_SERVICE_PASSWORD="$(tr -d '\r\n' < "$DASHBOARDS_SERVICE_PASSWORD_FILE")"
export OPENSEARCH_INGEST_PASSWORD
OPENSEARCH_INGEST_PASSWORD="$(tr -d '\r\n' < "$OPENSEARCH_INGEST_PASSWORD_FILE")"
[[ -n "$DASHBOARDS_SERVICE_PASSWORD" ]] || die "Dashboards password resolved empty"
[[ -n "$OPENSEARCH_INGEST_PASSWORD" ]] || die "Data Prepper ingest password resolved empty"

python3 - "$TARGETS_FILE" <<'PY'
import json, sys
p=sys.argv[1]
with open(p, encoding="utf-8") as f:
    data=json.load(f)
for key in ("node_exporter","kube_state_metrics","kubelet_cadvisor"):
    value=data.get(key, [])
    if not isinstance(value, list):
        raise SystemExit(f"{key} must be a JSON array")
    for i,item in enumerate(value):
        if not isinstance(item, dict) or not item.get("target"):
            raise SystemExit(f"{key}[{i}] must be an object with non-empty target")
PY

rm -rf "$OUTPUT_DIR"
install -d -m 0700 \
  "$OUTPUT_DIR/opensearch/jvm.options.d" \
  "$OUTPUT_DIR/opensearch-dashboards" \
  "$OUTPUT_DIR/data-prepper/config" \
  "$OUTPUT_DIR/data-prepper/pipelines" \
  "$OUTPUT_DIR/prometheus/rules" \
  "$OUTPUT_DIR/alertmanager/templates" \
  "$OUTPUT_DIR/process-exporter"

render_template() {
  local src="$1" dst="$2"
  python3 - "$src" "$dst" <<'PY'
import os, re, sys
src,dst=sys.argv[1:3]
text=open(src, encoding="utf-8").read()
pat=re.compile(r"\{\{\s*([A-Z][A-Z0-9_]*)\s*\}\}")
def repl(m):
    key=m.group(1)
    if key not in os.environ:
        raise SystemExit(f"missing render variable: {key}")
    value=os.environ[key]
    if "\n" in value or "\r" in value:
        raise SystemExit(f"render variable contains newline: {key}")
    return value.replace("\\","\\\\").replace('"','\\\"')
out=pat.sub(repl,text)
open(dst,"w",encoding="utf-8").write(out)
PY
}

render_template "$REPO_ROOT/observability-host/opensearch/opensearch.yml.example" "$OUTPUT_DIR/opensearch/opensearch.yml"
render_template "$REPO_ROOT/observability-host/opensearch/heap.options.example" "$OUTPUT_DIR/opensearch/jvm.options.d/heap.options"
render_template "$REPO_ROOT/observability-host/dashboards/opensearch_dashboards.yml.example" "$OUTPUT_DIR/opensearch-dashboards/opensearch_dashboards.yml"
render_template "$REPO_ROOT/observability-host/data-prepper/data-prepper-config.yaml" "$OUTPUT_DIR/data-prepper/config/data-prepper-config.yaml"
render_template "$REPO_ROOT/observability-host/data-prepper/pipelines.example.yaml" "$OUTPUT_DIR/data-prepper/pipelines/pipelines.yaml"
render_template "$REPO_ROOT/observability-host/alertmanager/alertmanager.yml.example" "$OUTPUT_DIR/alertmanager/alertmanager.yml"
install -m 0640 "$REPO_ROOT/observability-host/alertmanager/telegram.tmpl" "$OUTPUT_DIR/alertmanager/templates/observability-telegram.tmpl"
install -m 0640 "$REPO_ROOT/observability-host/process-exporter/process-exporter.yml" "$OUTPUT_DIR/process-exporter/process-exporter.yml"

python3 - "$REPO_ROOT/observability-host/prometheus/prometheus.yml.example" "$TARGETS_FILE" "$OUTPUT_DIR/prometheus/prometheus.yml" <<'PY'
import json, os, re, sys
template_path, targets_path, output_path=sys.argv[1:4]
template=open(template_path, encoding="utf-8").read()
data=json.load(open(targets_path, encoding="utf-8"))

def q(v):
    return json.dumps(str(v), ensure_ascii=False)

def static_configs(items):
    lines=[]
    for item in items:
        lines.append(f"      - targets: [{q(item['target'])}]")
        labels={k:item[k] for k in ("node","ip","role") if item.get(k) not in (None,"")}
        if labels:
            lines.append("        labels:")
            for k,v in labels.items():
                lines.append(f"          {k}: {q(v)}")
    return lines

node=data.get("node_exporter", [])
if node:
    lines=["  - job_name: node-exporter","    static_configs:"] + static_configs(node)
    node_block="\n".join(lines)
else:
    node_block=""

ksm=data.get("kube_state_metrics", [])
if ksm:
    lines=["  - job_name: kube-state-metrics","    static_configs:"] + static_configs(ksm)
    ksm_block="\n".join(lines)
else:
    ksm_block=""

cad=data.get("kubelet_cadvisor", [])
if cad:
    lines=[
        "  - job_name: kubelet-cadvisor",
        "    scheme: https",
        "    metrics_path: /metrics/cadvisor",
        f"    bearer_token_file: {q(os.environ['KUBELET_BEARER_TOKEN_FILE'])}",
        "    tls_config:",
        "      insecure_skip_verify: true",
        "    static_configs:",
    ] + static_configs(cad)
    cad_block="\n".join(lines)
else:
    cad_block=""

template=template.replace("{{ NODE_EXPORTER_JOB_BLOCK }}", node_block)
template=template.replace("{{ KUBE_STATE_METRICS_JOB_BLOCK }}", ksm_block)
template=template.replace("{{ KUBELET_CADVISOR_JOB_BLOCK }}", cad_block)
pat=re.compile(r"\{\{\s*([A-Z][A-Z0-9_]*)\s*\}\}")
def repl(m):
    key=m.group(1)
    if key not in os.environ:
        raise SystemExit(f"missing render variable: {key}")
    return os.environ[key].replace("\\","\\\\").replace('"','\\\"')
template=pat.sub(repl,template)
open(output_path,"w",encoding="utf-8").write(template)
PY

chmod 0600 \
  "$OUTPUT_DIR/opensearch-dashboards/opensearch_dashboards.yml" \
  "$OUTPUT_DIR/data-prepper/pipelines/pipelines.yaml" \
  "$OUTPUT_DIR/alertmanager/alertmanager.yml"
chmod 0640 \
  "$OUTPUT_DIR/opensearch/opensearch.yml" \
  "$OUTPUT_DIR/opensearch/jvm.options.d/heap.options" \
  "$OUTPUT_DIR/data-prepper/config/data-prepper-config.yaml" \
  "$OUTPUT_DIR/prometheus/prometheus.yml"

bash "$REPO_ROOT/scripts/validate-rendered-reference-config.sh" "$OUTPUT_DIR"
ok "Reference configuration rendered: $OUTPUT_DIR"
echo "Next gate: generate/verify lab PKI and OpenSearch security identities before live installation."
