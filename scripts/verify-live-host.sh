#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_HOST="${EXPECTED_HOST:-}"
EXPECTED_ENVIRONMENT="${EXPECTED_ENVIRONMENT:-}"

ok()   { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; failures=$((failures + 1)); }

[[ "${EUID}" -eq 0 ]] || {
  printf '[ERROR] Run as root.\n' >&2
  exit 1
}

[[ -n "$EXPECTED_HOST" ]] || {
  printf '[ERROR] Set EXPECTED_HOST to the intended live observability hostname.\n' >&2
  exit 1
}

[[ "$(hostname -s)" == "$EXPECTED_HOST" ]] || {
  printf '[ERROR] Refusing verification: expected %s, found %s.\n' "$EXPECTED_HOST" "$(hostname -s)" >&2
  exit 1
}

failures=0

echo "=== LIVE OBSERVABILITY CLOSEOUT VERIFICATION ==="
echo "Host: $(hostname -s)"
[[ -n "$EXPECTED_ENVIRONMENT" ]] && echo "Expected environment: $EXPECTED_ENVIRONMENT"
echo

check_service() {
  local service="$1"
  local state
  state="$(systemctl is-active "$service" 2>/dev/null || true)"
  if [[ "$state" == "active" ]]; then
    ok "$service active"
  else
    fail "$service is $state"
  fi
}

echo "=== SERVICES ==="
for service in opensearch opensearch-dashboards data-prepper prometheus alertmanager process-exporter node_exporter; do
  check_service "$service"
done

echo
echo "=== LISTENERS ==="
declare -A ports=(
  [2021]="Data Prepper HTTP logs"
  [4900]="Data Prepper core API"
  [5601]="OpenSearch Dashboards"
  [9090]="Prometheus"
  [9093]="Alertmanager"
  [9115]="node_exporter"
  [9200]="OpenSearch HTTP"
  [9256]="process-exporter"
  [9300]="OpenSearch transport"
  [21890]="Data Prepper OTLP traces"
)
for port in "${!ports[@]}"; do
  if ss -lntH | awk '{print $4}' | grep -Eq "(^|:)$port$"; then
    ok "${ports[$port]} listening on $port"
  else
    fail "${ports[$port]} is not listening on $port"
  fi
done

echo
echo "=== HTTP READINESS ==="
http_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:9090/-/ready || true)"
[[ "$http_code" == "200" ]] && ok "Prometheus ready" || fail "Prometheus readiness HTTP $http_code"

http_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:9093/-/ready || true)"
[[ "$http_code" == "200" ]] && ok "Alertmanager ready" || fail "Alertmanager readiness HTTP $http_code"

http_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:9256/metrics || true)"
[[ "$http_code" == "200" ]] && ok "process-exporter metrics reachable" || fail "process-exporter metrics HTTP $http_code"

http_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:9115/metrics || true)"
[[ "$http_code" == "200" ]] && ok "node_exporter metrics reachable" || fail "node_exporter metrics HTTP $http_code"

http_code="$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 5 https://127.0.0.1:9200/ || true)"
case "$http_code" in
  200|401|403) ok "OpenSearch HTTPS reachable (HTTP $http_code)" ;;
  *) fail "OpenSearch HTTPS unexpected HTTP $http_code" ;;
esac

http_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:5601/api/status || true)"
case "$http_code" in
  200|302|401|403) ok "OpenSearch Dashboards reachable (HTTP $http_code)" ;;
  *) fail "OpenSearch Dashboards unexpected HTTP $http_code" ;;
esac

echo
echo "=== CONFIGURATION VALIDATION ==="
if [[ -x /opt/prometheus/promtool ]]; then
  /opt/prometheus/promtool check config /etc/prometheus/prometheus.yml >/dev/null     && ok "Prometheus config valid"     || fail "Prometheus config invalid"
  if compgen -G '/etc/prometheus/rules/*.yml' >/dev/null; then
    /opt/prometheus/promtool check rules /etc/prometheus/rules/*.yml >/dev/null       && ok "Prometheus rules valid"       || fail "Prometheus rules invalid"
  else
    fail "No Prometheus rule files found"
  fi
else
  fail "promtool missing"
fi

if [[ -x /opt/alertmanager/amtool ]]; then
  /opt/alertmanager/amtool check-config /etc/alertmanager/alertmanager.yml >/dev/null     && ok "Alertmanager config valid"     || fail "Alertmanager config invalid"
else
  fail "amtool missing"
fi

echo
echo "=== PROMETHEUS RULE STATE ==="
rules_json="$(curl -fsS --max-time 10 http://127.0.0.1:9090/api/v1/rules 2>/dev/null || true)"
if [[ -n "$rules_json" ]] && jq -e '.status == "success"' >/dev/null 2>&1 <<<"$rules_json"; then
  group_count="$(jq '[.data.groups[]] | length' <<<"$rules_json")"
  alert_count="$(jq '[.data.groups[].rules[] | select(.type == "alerting")] | length' <<<"$rules_json")"
  recording_count="$(jq '[.data.groups[].rules[] | select(.type == "recording")] | length' <<<"$rules_json")"
  ok "Prometheus rules API healthy: groups=$group_count alerting=$alert_count recording=$recording_count"
  (( alert_count > 0 )) || fail "No alerting rules loaded"
else
  fail "Prometheus rules API unavailable"
fi

echo
echo "=== TELEMETRY PRESENCE ==="
query='count(request{namespace="span_derived"})'
if [[ -n "$EXPECTED_ENVIRONMENT" ]]; then
  query="count(request{namespace=\"span_derived\",environment=\"$EXPECTED_ENVIRONMENT\"})"
fi
metric_json="$(curl -fsS --get http://127.0.0.1:9090/api/v1/query --data-urlencode "query=$query" 2>/dev/null || true)"
if [[ -n "$metric_json" ]] && jq -e '.status == "success"' >/dev/null 2>&1 <<<"$metric_json"; then
  series_value="$(jq -r '.data.result[0].value[1] // "0"' <<<"$metric_json")"
  if awk "BEGIN {exit !($series_value > 0)}"; then
    ok "span-derived request metric present: $series_value series"
  else
    warn "No current span-derived request series matched; core platform health still validated"
  fi
else
  warn "Could not query span-derived request metric"
fi

echo
if (( failures == 0 )); then
  ok "LIVE OBSERVABILITY CLOSEOUT VERIFICATION PASSED"
  exit 0
fi

printf '[FAIL] Live closeout verification failed with %d issue(s).\n' "$failures" >&2
exit 1
