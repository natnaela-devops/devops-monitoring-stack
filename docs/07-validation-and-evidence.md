# Validation and Evidence

## Purpose

This stage turns the manual lab checks into one repeatable acceptance command. It validates
the Kubernetes control plane, OpenTelemetry path, Prometheus reporting rules, OpenSearch
indices, and—when a safe test endpoint is supplied—a complete transaction across logs,
spans, and the v2 service map.

The script is read-only except for the optional HTTP request to the configured test
application. It never changes Kubernetes or observability configuration.

## 1. What the validator proves

The checks align directly with the implementation report:

| Report section | Automated evidence |
|---|---|
| Platform health | API readiness, Ready nodes, available Deployments |
| Telemetry collection | Collector availability and recent error scan |
| Metrics and SLOs | Prometheus readiness, recording-rule health, discovered report services |
| Logs | OTLP log index availability and optional correlated-log count |
| Traces | Span index availability and optional trace span count |
| Application map | v2 service-map index availability and optional dependency relationship |
| Kubernetes context | Namespace, pod, node, container, and workload metadata on test logs |
| Security | Credentials loaded only from a private curl config; identifiers excluded from reports |

These checks prove functional continuity. They do not replace load, soak, recovery, TLS,
capacity, or high-availability testing.

## 2. Prerequisites

Run the validator from an administrative workstation that can reach both the Kubernetes API
and the dedicated observability host. Required commands are `kubectl`, `curl`, and `jq`.

Set non-secret endpoints in the shell:

```bash
export PROMETHEUS_URL='https://prometheus.example.internal'
export OPENSEARCH_URL='https://opensearch.example.internal:9200'
```

Create a private curl configuration outside the repository for OpenSearch authentication and
CA verification:

```text
user = "validation-reader:replace-with-private-password"
cacert = "/private/path/observability-ca.pem"
```

```bash
chmod 600 /private/path/opensearch-validation.curlrc
export OPENSEARCH_CURL_CONFIG='/private/path/opensearch-validation.curlrc'
```

Use a read-only OpenSearch role limited to cluster health and the required telemetry indices.
Do not use the administrator account in production evidence jobs. The lab-only escape hatch
`OPENSEARCH_INSECURE=true` disables certificate verification and must not be used for UAT or
production acceptance.

## 3. Platform-only validation

This mode makes no application request:

```bash
./scripts/validate-platform.sh
```

It checks:

- Kubernetes API, nodes, and Deployments;
- Collector and Operator availability;
- Collector errors or forbidden RBAC messages;
- Prometheus readiness and unhealthy recording rules;
- automatically discovered `apm_report_*` services;
- OpenSearch cluster health and log, span, and v2 service-map indices.

## 4. End-to-end validation

Use a non-destructive test route that returns JSON with a `transactionId` field:

```bash
export E2E_TEST_URL='https://test-gateway.example.internal/api/transfers?amount=20001'
export E2E_SOURCE_SERVICE='bank-demo-gateway'
export E2E_TARGET_SERVICE='bank-demo-payment'
export E2E_WAIT_SECONDS=75
export E2E_SERVICE_MAP_LOOKBACK='10m'
export E2E_EXPECTED_LOG_COUNT=4

./scripts/validate-platform.sh
```

The validator sends one request, keeps the transaction and trace identifiers only in memory,
and records counts rather than identifiers. It then checks:

- correlated logs exist and share a trace ID;
- Kubernetes metadata is present on those logs;
- the trace contains multiple spans;
- the v2 service map contains a recent expected source-to-target relationship;
- the source service is automatically represented by Prometheus reporting metrics.

Unset `E2E_EXPECTED_LOG_COUNT` for applications whose correct log count is not fixed. For
applications exporting OTLP logs directly, a precise expected count is useful for detecting a
duplicate Fluent Bit copy.

## 5. Output and exit status

By default, results are written beneath `evidence/generated/<UTC timestamp>/`:

- `report.md` for reviewers and the implementation report;
- `report.json` for CI or a private evidence pipeline.

The console and reports contain check names, PASS/FAIL/SKIP status, and sanitized details.
They do not contain URLs, credentials, pod names, trace IDs, transaction IDs, or raw payloads.

Exit status is zero only when every executed check passes. Optional components that are not
configured are marked `SKIP`; a failed required dependency or API check returns non-zero.

Set `EVIDENCE_OUTPUT_DIR` to a private location when generated evidence must never touch the
repository working tree.

## 6. Change-record workflow

For every release candidate:

1. record the Git commit and `versions.env` baseline;
2. run platform-only validation;
3. run one end-to-end transaction per representative instrumentation mode;
4. review the generated reports for sensitive data;
5. attach reviewed evidence to the private change record;
6. execute the separate load, soak, failure, rollback, and recovery plans;
7. obtain the required technical and business approvals.

Never copy live credentials, raw OpenSearch documents, kubeconfigs, or complete environment
configuration into the public repository.
