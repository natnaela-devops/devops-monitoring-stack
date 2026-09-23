#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/versions.env"

ok()  { printf '[OK] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ -x /opt/opensearch/bin/opensearch ]] || die "OpenSearch binary missing"
/opt/opensearch/bin/opensearch --version 2>&1 | grep -q "Version: ${OPENSEARCH_VERSION}" || die "OpenSearch version mismatch"
ok "OpenSearch ${OPENSEARCH_VERSION}"

[[ -f /opt/opensearch-dashboards/package.json ]] || die "Dashboards package metadata missing"
[[ "$(jq -r '.version' /opt/opensearch-dashboards/package.json)" == "$OPENSEARCH_DASHBOARDS_VERSION" ]] || die "Dashboards version mismatch"
ok "OpenSearch Dashboards ${OPENSEARCH_DASHBOARDS_VERSION}"

find /opt/data-prepper/lib -maxdepth 1 -type f -name "data-prepper-pipeline-parser-${DATA_PREPPER_VERSION}.jar" -print -quit | grep -q . || die "Data Prepper ${DATA_PREPPER_VERSION} marker jar missing"
ok "Data Prepper ${DATA_PREPPER_VERSION}"

/opt/prometheus/prometheus --version 2>&1 | head -1 | grep -q "version ${PROMETHEUS_VERSION}" || die "Prometheus version mismatch"
ok "Prometheus ${PROMETHEUS_VERSION}"

/opt/alertmanager/alertmanager --version 2>&1 | head -1 | grep -q "version ${ALERTMANAGER_VERSION}" || die "Alertmanager version mismatch"
ok "Alertmanager ${ALERTMANAGER_VERSION}"

/usr/local/bin/node_exporter --version 2>&1 | head -1 | grep -q "version ${NODE_EXPORTER_VERSION}" || die "node_exporter version mismatch"
ok "node_exporter ${NODE_EXPORTER_VERSION}"

/usr/local/bin/process-exporter --version 2>&1 | head -1 | grep -q "version ${PROCESS_EXPORTER_VERSION}" || die "process-exporter version mismatch"
ok "process-exporter ${PROCESS_EXPORTER_VERSION}"

for unit in opensearch opensearch-dashboards data-prepper prometheus alertmanager node_exporter process-exporter; do
  systemctl cat "$unit" >/dev/null 2>&1 || die "systemd unit missing: $unit"
done
ok "systemd unit definitions present"

[[ "$(stat -c '%U:%G' /opt/opensearch)" == "opensearch:opensearch" ]] || die "OpenSearch ownership mismatch"
[[ "$(stat -c '%U:%G' /opt/opensearch-dashboards)" == "opensearch:opensearch" ]] || die "Dashboards ownership mismatch"
[[ "$(stat -c '%U:%G' /opt/data-prepper)" == "dataprepper:dataprepper" ]] || die "Data Prepper ownership mismatch"
[[ "$(stat -c '%U:%G' /opt/prometheus)" == "prometheus:prometheus" ]] || die "Prometheus ownership mismatch"
[[ "$(stat -c '%U:%G' /opt/alertmanager)" == "root:root" ]] || die "Alertmanager ownership mismatch"
ok "reference ownership contract present"

unexpected_active=0
for unit in opensearch opensearch-dashboards data-prepper prometheus alertmanager node_exporter process-exporter; do
  state="$(systemctl is-active "$unit" 2>/dev/null || true)"
  if [[ "$state" == "active" || "$state" == "activating" ]]; then
    printf '[ERROR] service unexpectedly active during binary-only bootstrap: %s (%s)\n' "$unit" "$state" >&2
    unexpected_active=1
  fi
done
[[ "$unexpected_active" -eq 0 ]] || exit 1
ok "services remain inactive pending configuration gate"

ok "Reference binary verification passed"
