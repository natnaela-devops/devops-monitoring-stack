#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_HOST="${EXPECTED_HOST:-vm-3}"

ok()   { printf '[OK] %s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; failures=$((failures + 1)); }

[[ "${EUID}" -eq 0 ]] || {
  printf '[ERROR] Run as root.\n' >&2
  exit 1
}

[[ "$(hostname -s)" == "$EXPECTED_HOST" ]] || {
  printf '[ERROR] Expected host %s, found %s.\n' "$EXPECTED_HOST" "$(hostname -s)" >&2
  exit 1
}

failures=0

echo "=== CLEAN LAB VERIFICATION ==="
echo "Host: $(hostname -s)"
echo

info "Checking observability services are not active"
services=(
  opensearch
  opensearch-dashboards
  prometheus
  alertmanager
  data-prepper
  node-exporter
  prometheus-node-exporter
  process-exporter
  otelcol
  otelcol-contrib
  opensearch-exporter
)

for service in "${services[@]}"; do
  state="$(systemctl is-active "$service" 2>/dev/null || true)"
  if [[ "$state" == "active" || "$state" == "activating" ]]; then
    fail "$service is $state"
  else
    ok "$service is not active"
  fi
done

echo
info "Checking observability ports are not listening"
ports='5601|9090|9093|9100|9115|9200|9256|9300|9600|21890|21891|4317|4318|4900'
if listeners="$(ss -lntpH 2>/dev/null | grep -E ":($ports)\\b" || true)" && [[ -n "$listeners" ]]; then
  printf '%s\n' "$listeners"
  fail "one or more observability ports are still listening"
else
  ok "no observability ports are listening"
fi

echo
info "Checking OpenSearch packages are absent"
for package in opensearch opensearch-dashboards; do
  status="$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)"
  if [[ "$status" == *"install ok installed"* ]]; then
    fail "$package is still installed"
  else
    ok "$package is absent"
  fi
done

echo
info "Checking primary observability paths are absent"
paths=(
  /opt/opensearch
  /opt/opensearch-dashboards
  /opt/data-prepper
  /opt/prometheus
  /opt/alertmanager
  /etc/opensearch
  /etc/opensearch-dashboards
  /etc/data-prepper
  /etc/prometheus
  /etc/alertmanager
  /data/prometheus
  /data/alertmanager
)

for path in "${paths[@]}"; do
  if [[ -e "$path" ]]; then
    fail "path still exists: $path"
  else
    ok "absent: $path"
  fi
done

echo
info "Checking reset-sensitive binaries are absent on vm-3"
for binary in /usr/local/bin/node_exporter /usr/local/bin/process-exporter; do
  if [[ -e "$binary" ]]; then
    fail "binary still exists: $binary"
  else
    ok "absent: $binary"
  fi
done

echo
info "Checking base host capabilities remain available"
for cmd in ssh curl tar jq systemctl ss; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd available"
  else
    fail "$cmd missing"
  fi
done

echo
if (( failures == 0 )); then
  ok "Clean lab verification passed"
  exit 0
fi

printf '[FAIL] Clean lab verification failed with %d issue(s).\n' "$failures" >&2
exit 1
