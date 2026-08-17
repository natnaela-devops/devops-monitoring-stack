#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/validate-platform.sh

Required environment:
  PROMETHEUS_URL                 Prometheus base URL
  OPENSEARCH_URL                 OpenSearch base URL

Private OpenSearch access:
  OPENSEARCH_CURL_CONFIG         Path to a chmod-600 curl config with auth and CA
  OPENSEARCH_INSECURE=true       Lab only: disable TLS certificate validation

Optional Kubernetes names:
  COLLECTOR_NAMESPACE            Default: monitoring
  COLLECTOR_DEPLOYMENT           Default: otel-collector
  OPERATOR_NAMESPACE             Default: opentelemetry-operator-system
  OPERATOR_DEPLOYMENT            Default: opentelemetry-operator

Optional end-to-end test:
  E2E_TEST_URL                   Safe endpoint returning JSON transactionId
  E2E_SOURCE_SERVICE            Expected source service name
  E2E_TARGET_SERVICE            Expected target service name
  E2E_WAIT_SECONDS              Default: 75
  E2E_SERVICE_MAP_LOOKBACK      Default: 10m
  E2E_EXPECTED_LOG_COUNT        Exact count for duplicate-log detection

Output:
  EVIDENCE_OUTPUT_DIR           Default: evidence/generated/<UTC timestamp>
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT_DIR="${EVIDENCE_OUTPUT_DIR:-${REPO_ROOT}/evidence/generated/${RUN_TIMESTAMP}}"
RESULTS_FILE="$(mktemp)"
trap 'rm -f "${RESULTS_FILE}"' EXIT

COLLECTOR_NAMESPACE="${COLLECTOR_NAMESPACE:-monitoring}"
COLLECTOR_DEPLOYMENT="${COLLECTOR_DEPLOYMENT:-otel-collector}"
OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE:-opentelemetry-operator-system}"
OPERATOR_DEPLOYMENT="${OPERATOR_DEPLOYMENT:-opentelemetry-operator}"
E2E_WAIT_SECONDS="${E2E_WAIT_SECONDS:-75}"
E2E_SERVICE_MAP_LOOKBACK="${E2E_SERVICE_MAP_LOOKBACK:-10m}"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

record() {
  local status="$1"
  local check="$2"
  local detail="$3"

  jq -cn \
    --arg status "${status}" \
    --arg check "${check}" \
    --arg detail "${detail}" \
    '{status: $status, check: $check, detail: $detail}' >>"${RESULTS_FILE}"

  printf '%-4s  %-34s %s\n' "${status}" "${check}" "${detail}"

  case "${status}" in
    PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
    FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
    SKIP) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;
  esac
}

prometheus_get() {
  curl --fail --silent --show-error \
    --connect-timeout 10 --max-time 30 \
    "${PROMETHEUS_URL%/}$1"
}

opensearch_curl() {
  local args=(
    --fail --silent --show-error
    --connect-timeout 10 --max-time 30
  )

  if [[ -n "${OPENSEARCH_CURL_CONFIG:-}" ]]; then
    args+=(--config "${OPENSEARCH_CURL_CONFIG}")
  fi

  if [[ "${OPENSEARCH_INSECURE:-false}" == "true" ]]; then
    args+=(--insecure)
  fi

  curl "${args[@]}" "$@"
}

opensearch_get() {
  opensearch_curl "${OPENSEARCH_URL%/}$1"
}

opensearch_search() {
  local index="$1"
  local body="$2"

  opensearch_curl \
    --header 'Content-Type: application/json' \
    --request POST \
    --data "${body}" \
    "${OPENSEARCH_URL%/}/${index}/_search"
}

for command_name in kubectl curl jq git; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf 'FAIL: required command is unavailable: %s\n' "${command_name}" >&2
    exit 2
  fi
done

for command_name in kubectl curl jq git; do
  record PASS "dependency:${command_name}" "command is available"
done

if api_ready="$(kubectl get --raw='/readyz' 2>/dev/null)" && [[ "${api_ready}" == "ok" ]]; then
  record PASS kubernetes-api "readiness endpoint returned ok"
else
  record FAIL kubernetes-api "readiness endpoint failed"
fi

if node_json="$(kubectl get nodes -o json 2>/dev/null)"; then
  node_total="$(jq '.items | length' <<<"${node_json}")"
  node_ready="$(jq '[.items[] | select(any(.status.conditions[]; .type == "Ready" and .status == "True"))] | length' <<<"${node_json}")"
  if [[ "${node_total}" -gt 0 && "${node_ready}" -eq "${node_total}" ]]; then
    record PASS kubernetes-nodes "${node_ready}/${node_total} nodes Ready"
  else
    record FAIL kubernetes-nodes "${node_ready}/${node_total} nodes Ready"
  fi
else
  record FAIL kubernetes-nodes "node query failed"
fi

if deployment_json="$(kubectl get deployments --all-namespaces -o json 2>/dev/null)"; then
  deployment_total="$(jq '.items | length' <<<"${deployment_json}")"
  deployment_ready="$(jq '[.items[] | select((.status.availableReplicas // 0) >= (.spec.replicas // 1))] | length' <<<"${deployment_json}")"
  if [[ "${deployment_total}" -gt 0 && "${deployment_ready}" -eq "${deployment_total}" ]]; then
    record PASS kubernetes-deployments "${deployment_ready}/${deployment_total} Deployments available"
  else
    record FAIL kubernetes-deployments "${deployment_ready}/${deployment_total} Deployments available"
  fi
else
  record FAIL kubernetes-deployments "Deployment query failed"
fi

if collector_json="$(kubectl -n "${COLLECTOR_NAMESPACE}" get deployment "${COLLECTOR_DEPLOYMENT}" -o json 2>/dev/null)"; then
  collector_desired="$(jq '.spec.replicas // 1' <<<"${collector_json}")"
  collector_ready="$(jq '.status.availableReplicas // 0' <<<"${collector_json}")"
  if [[ "${collector_ready}" -ge "${collector_desired}" ]]; then
    record PASS otel-collector "${collector_ready}/${collector_desired} replicas available"
  else
    record FAIL otel-collector "${collector_ready}/${collector_desired} replicas available"
  fi

  collector_errors="$(kubectl -n "${COLLECTOR_NAMESPACE}" logs deployment/"${COLLECTOR_DEPLOYMENT}" --since=10m 2>/dev/null | /usr/bin/grep -Eic 'error|failed|forbidden|exception' || true)"
  if [[ "${collector_errors}" -eq 0 ]]; then
    record PASS otel-collector-errors "no recent error indicators"
  else
    record FAIL otel-collector-errors "${collector_errors} recent error indicators"
  fi
else
  record FAIL otel-collector "Deployment was not found"
  record SKIP otel-collector-errors "Collector Deployment unavailable"
fi

if operator_json="$(kubectl -n "${OPERATOR_NAMESPACE}" get deployment "${OPERATOR_DEPLOYMENT}" -o json 2>/dev/null)"; then
  operator_desired="$(jq '.spec.replicas // 1' <<<"${operator_json}")"
  operator_ready="$(jq '.status.availableReplicas // 0' <<<"${operator_json}")"
  if [[ "${operator_ready}" -ge "${operator_desired}" ]]; then
    record PASS otel-operator "${operator_ready}/${operator_desired} replicas available"
  else
    record FAIL otel-operator "${operator_ready}/${operator_desired} replicas available"
  fi
else
  record SKIP otel-operator "Operator is not installed or not required"
fi

if [[ -z "${PROMETHEUS_URL:-}" ]]; then
  record FAIL prometheus "PROMETHEUS_URL is not configured"
  record SKIP prometheus-rules "Prometheus is not configured"
  record SKIP prometheus-reporting "Prometheus is not configured"
else
  if prometheus_ready="$(prometheus_get '/-/ready' 2>/dev/null)"; then
    record PASS prometheus "readiness endpoint responded"
  else
    record FAIL prometheus "readiness endpoint failed"
  fi

  if rules_json="$(prometheus_get '/api/v1/rules?type=record' 2>/dev/null)"; then
    unhealthy_rules="$(jq '[.data.groups[].rules[] | select(.health != "ok")] | length' <<<"${rules_json}")"
    rule_total="$(jq '[.data.groups[].rules[]] | length' <<<"${rules_json}")"
    if [[ "${unhealthy_rules}" -eq 0 && "${rule_total}" -gt 0 ]]; then
      record PASS prometheus-rules "${rule_total} recording rules healthy"
    else
      record FAIL prometheus-rules "${unhealthy_rules}/${rule_total} recording rules unhealthy"
    fi
  else
    record FAIL prometheus-rules "recording-rule query failed"
  fi

  report_query='count by (service) ({__name__=~"apm_report_.*_24h",service!=""})'
  if report_json="$(curl --fail --silent --show-error --get --connect-timeout 10 --max-time 30 "${PROMETHEUS_URL%/}/api/v1/query" --data-urlencode "query=${report_query}" 2>/dev/null)"; then
    report_services="$(jq '.data.result | length' <<<"${report_json}")"
    if [[ "${report_services}" -gt 0 ]]; then
      record PASS prometheus-reporting "${report_services} services automatically discovered"
    else
      record FAIL prometheus-reporting "no services expose 24-hour report metrics"
    fi
  else
    record FAIL prometheus-reporting "reporting-metric query failed"
  fi
fi

if [[ -z "${OPENSEARCH_URL:-}" ]]; then
  record FAIL opensearch "OPENSEARCH_URL is not configured"
  record SKIP telemetry-indices "OpenSearch is not configured"
else
  if [[ -n "${OPENSEARCH_CURL_CONFIG:-}" && ! -r "${OPENSEARCH_CURL_CONFIG}" ]]; then
    record FAIL opensearch-auth "private curl configuration is unreadable"
  elif [[ -n "${OPENSEARCH_CURL_CONFIG:-}" ]]; then
    config_mode="$(stat -c '%a' "${OPENSEARCH_CURL_CONFIG}" 2>/dev/null || true)"
    if [[ "${config_mode}" == "600" || "${config_mode}" == "400" ]]; then
      record PASS opensearch-auth "private curl configuration permissions are restricted"
    else
      record FAIL opensearch-auth "private curl configuration must use mode 600 or 400"
    fi
  else
    record SKIP opensearch-auth "no private curl configuration supplied"
  fi

  if cluster_json="$(opensearch_get '/_cluster/health' 2>/dev/null)"; then
    cluster_status="$(jq -r '.status // "unknown"' <<<"${cluster_json}")"
    if [[ "${cluster_status}" == "green" || "${cluster_status}" == "yellow" ]]; then
      record PASS opensearch "cluster health is ${cluster_status}"
    else
      record FAIL opensearch "cluster health is ${cluster_status}"
    fi
  else
    record FAIL opensearch "cluster-health query failed"
  fi

  for index_spec in \
    'logs:otel-logs-*' \
    'spans:otel-v1-apm-span*' \
    'service-map:otel-v2-apm-service-map*'
  do
    index_label="${index_spec%%:*}"
    index_pattern="${index_spec#*:}"
    if index_json="$(opensearch_get "/_cat/indices/${index_pattern}?format=json&h=index" 2>/dev/null)" && [[ "$(jq 'length' <<<"${index_json}")" -gt 0 ]]; then
      record PASS "index:${index_label}" "telemetry index is available"
    else
      record FAIL "index:${index_label}" "telemetry index is unavailable"
    fi
  done
fi

if [[ -z "${E2E_TEST_URL:-}" ]]; then
  record SKIP e2e-transaction "E2E_TEST_URL is not configured"
else
  if transaction_response="$(curl --fail --silent --show-error --connect-timeout 10 --max-time 30 "${E2E_TEST_URL}" 2>/dev/null)" && transaction_id="$(jq -er '.transactionId | strings | select(length > 0)' <<<"${transaction_response}" 2>/dev/null)"; then
    record PASS e2e-transaction "test request returned a transaction identifier"
    sleep "${E2E_WAIT_SECONDS}"

    if [[ -z "${OPENSEARCH_URL:-}" ]]; then
      record SKIP e2e-logs "OpenSearch is not configured"
      record SKIP e2e-spans "OpenSearch is not configured"
      record SKIP e2e-service-map "OpenSearch is not configured"
    else
      log_body="$(jq -cn --arg tx "${transaction_id}" '{size: 100, query: {match_phrase: {body: $tx}}}')"
      if log_json="$(opensearch_search 'otel-logs-*' "${log_body}" 2>/dev/null)"; then
        log_count="$(jq '.hits.total.value // 0' <<<"${log_json}")"
        trace_count="$(jq '[.hits.hits[]._source.traceId // empty | select(length > 0)] | unique | length' <<<"${log_json}")"
        trace_id="$(jq -r '[.hits.hits[]._source.traceId // empty | select(length > 0)][0] // empty' <<<"${log_json}")"

        if [[ -n "${E2E_EXPECTED_LOG_COUNT:-}" ]]; then
          if [[ "${log_count}" -eq "${E2E_EXPECTED_LOG_COUNT}" && "${trace_count}" -eq 1 ]]; then
            record PASS e2e-logs "${log_count} correlated logs share one trace"
          else
            record FAIL e2e-logs "expected ${E2E_EXPECTED_LOG_COUNT} logs; found ${log_count} across ${trace_count} traces"
          fi
        elif [[ "${log_count}" -gt 0 && "${trace_count}" -eq 1 ]]; then
          record PASS e2e-logs "${log_count} correlated logs share one trace"
        else
          record FAIL e2e-logs "correlated logs were absent or split across traces"
        fi

        metadata_count="$(jq '[.hits.hits[]._source.resource.attributes | select(."k8s.namespace.name" and ."k8s.pod.name" and ."k8s.node.name" and ."k8s.container.name")] | length' <<<"${log_json}")"
        if [[ "${metadata_count}" -eq "${log_count}" && "${log_count}" -gt 0 ]]; then
          record PASS e2e-kubernetes-metadata "all correlated logs contain required Kubernetes context"
        else
          record FAIL e2e-kubernetes-metadata "${metadata_count}/${log_count} correlated logs contain required Kubernetes context"
        fi
      else
        trace_id=''
        record FAIL e2e-logs "correlated-log query failed"
        record SKIP e2e-kubernetes-metadata "correlated logs unavailable"
      fi

      if [[ -n "${trace_id}" ]]; then
        span_body="$(jq -cn --arg trace "${trace_id}" '{size: 0, query: {term: {traceId: $trace}}}')"
        if span_json="$(opensearch_search 'otel-v1-apm-span*' "${span_body}" 2>/dev/null)"; then
          span_count="$(jq '.hits.total.value // 0' <<<"${span_json}")"
          if [[ "${span_count}" -ge 2 ]]; then
            record PASS e2e-spans "${span_count} spans found for the trace"
          else
            record FAIL e2e-spans "only ${span_count} spans found for the trace"
          fi
        else
          record FAIL e2e-spans "trace query failed"
        fi
      else
        record SKIP e2e-spans "trace identifier unavailable"
      fi

      if [[ -n "${E2E_SOURCE_SERVICE:-}" && -n "${E2E_TARGET_SERVICE:-}" ]]; then
        map_body="$(jq -cn \
          --arg source "${E2E_SOURCE_SERVICE}" \
          --arg target "${E2E_TARGET_SERVICE}" \
          --arg lookback "now-${E2E_SERVICE_MAP_LOOKBACK}" \
          '{size: 0, query: {bool: {filter: [
            {term: {"sourceNode.keyAttributes.name": $source}},
            {term: {"targetNode.keyAttributes.name": $target}},
            {range: {timestamp: {gte: $lookback, lte: "now"}}}
          ]}}}')"
        if map_json="$(opensearch_search 'otel-v2-apm-service-map*' "${map_body}" 2>/dev/null)" && [[ "$(jq '.hits.total.value // 0' <<<"${map_json}")" -gt 0 ]]; then
          record PASS e2e-service-map "expected dependency relationship is indexed"
        else
          record FAIL e2e-service-map "expected dependency relationship was not found"
        fi
      else
        record SKIP e2e-service-map "source and target service names are not configured"
      fi
    fi

    if [[ -n "${PROMETHEUS_URL:-}" && -n "${E2E_SOURCE_SERVICE:-}" ]]; then
      source_report_query="count({__name__=~\"apm_report_.*_24h\",service=\"${E2E_SOURCE_SERVICE}\"})"
      if source_report_json="$(curl --fail --silent --show-error --get --connect-timeout 10 --max-time 30 "${PROMETHEUS_URL%/}/api/v1/query" --data-urlencode "query=${source_report_query}" 2>/dev/null)" && [[ "$(jq -r '.data.result[0].value[1] // "0"' <<<"${source_report_json}")" -gt 0 ]]; then
        record PASS e2e-reporting "source service is automatically represented in reporting metrics"
      else
        record FAIL e2e-reporting "source service reporting metrics were not found"
      fi
    else
      record SKIP e2e-reporting "Prometheus or source service is not configured"
    fi
  else
    record FAIL e2e-transaction "test request failed or returned no transactionId"
  fi
fi

mkdir -p "${OUTPUT_DIR}"

GIT_COMMIT="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || printf 'unknown')"
BASELINE_DATE="$(sed -n 's/^BASELINE_DATE="\([^"]*\)"/\1/p' "${REPO_ROOT}/versions.env" 2>/dev/null || true)"
VERSIONS_JSON="$(
  sed -n 's/^\([A-Z][A-Z0-9_]*\)="\([^"]*\)"$/\1\t\2/p' "${REPO_ROOT}/versions.env" |
    jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add'
)"

jq -s \
  --arg generated_at "${RUN_TIMESTAMP}" \
  --arg git_commit "${GIT_COMMIT}" \
  --arg baseline_date "${BASELINE_DATE:-unknown}" \
  --argjson versions "${VERSIONS_JSON}" \
  --argjson pass "${PASS_COUNT}" \
  --argjson fail "${FAIL_COUNT}" \
  --argjson skip "${SKIP_COUNT}" \
  '{
    generatedAt: $generated_at,
    gitCommit: $git_commit,
    baselineDate: $baseline_date,
    versions: $versions,
    summary: {pass: $pass, fail: $fail, skip: $skip},
    results: .
  }' "${RESULTS_FILE}" >"${OUTPUT_DIR}/report.json"

{
  printf '# Observability Platform Validation\n\n'
  printf -- '- Generated (UTC): `%s`\n' "${RUN_TIMESTAMP}"
  printf -- '- Git commit: `%s`\n' "${GIT_COMMIT}"
  printf -- '- Version baseline: `%s`\n' "${BASELINE_DATE:-unknown}"
  printf -- '- Result: **%s PASS / %s FAIL / %s SKIP**\n\n' "${PASS_COUNT}" "${FAIL_COUNT}" "${SKIP_COUNT}"
  printf '## Frozen versions\n\n'
  printf '| Component variable | Version |\n'
  printf '|---|---|\n'
  jq -r 'to_entries[] | "| `\(.key)` | `\(.value)` |"' <<<"${VERSIONS_JSON}"
  printf '\n## Checks\n\n'
  printf '| Status | Check | Detail |\n'
  printf '|---|---|---|\n'
  jq -r '. | "| \(.status) | `\(.check)` | \(.detail | gsub("\\|"; "\\\\|")) |"' "${RESULTS_FILE}"
  printf '\nGenerated output is sanitized but must still be reviewed before private evidence submission.\n'
} >"${OUTPUT_DIR}/report.md"

printf '\nEvidence written to:\n  %s\n  %s\n' \
  "${OUTPUT_DIR}/report.md" \
  "${OUTPUT_DIR}/report.json"

if ((FAIL_COUNT > 0)); then
  exit 1
fi
