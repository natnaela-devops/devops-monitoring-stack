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

check_identity() {
  local unit="$1" expected_user="$2" expected_group="$3"
  local actual_user actual_group
  actual_user="$(systemctl show "$unit" -p User --value 2>/dev/null || true)"
  actual_group="$(systemctl show "$unit" -p Group --value 2>/dev/null || true)"
  [[ "$actual_user" == "$expected_user" ]] || die "$unit user mismatch: expected=$expected_user actual=$actual_user"
  [[ "$actual_group" == "$expected_group" ]] || die "$unit group mismatch: expected=$expected_group actual=$actual_group"
}

check_identity opensearch opensearch opensearch
check_identity opensearch-dashboards opensearch opensearch
check_identity data-prepper dataprepper dataprepper
check_identity prometheus prometheus prometheus
check_identity alertmanager alertmanager alertmanager
check_identity node_exporter node_exporter node_exporter
check_identity process-exporter root root
ok "reference service identity contract present"

prom_exec="$(systemctl show prometheus -p ExecStart --value 2>/dev/null || true)"
[[ "$prom_exec" == *"--storage.tsdb.retention.time=5d"* ]] || die "Prometheus effective retention time mismatch"
[[ "$prom_exec" == *"--storage.tsdb.retention.size=3GB"* ]] || die "Prometheus effective retention size mismatch"
[[ "$prom_exec" == *"--web.enable-remote-write-receiver"* ]] || die "Prometheus remote-write receiver is not enabled"

node_exec="$(systemctl show node_exporter -p ExecStart --value 2>/dev/null || true)"
[[ "$node_exec" == *"--web.listen-address=0.0.0.0:9115"* ]] || die "node_exporter listen contract mismatch"

process_exec="$(systemctl show process-exporter -p ExecStart --value 2>/dev/null || true)"
[[ "$process_exec" == *"-web.listen-address=127.0.0.1:9256"* ]] || die "process-exporter listen contract mismatch"

java -version 2>&1 | head -1 | grep -q '17\.' || die "Java 17 runtime missing"
ok "reference effective service arguments present"

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
