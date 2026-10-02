# Live Observability Closeout

**Status:** Passed  
**Closeout date:** 2026-10-02

This document records the sanitized final verification of the operated UAT observability environment. Customer names, internal hostnames, private addresses, credentials, certificate identities, tokens, workspace identifiers, and telemetry payloads are intentionally excluded.

## Final verification result

The operated environment passed the final naming, alerting, telemetry, dashboard, and rollback checks.

### Services and telemetry paths

The final architecture uses:

- OpenTelemetry Java instrumentation for application telemetry;
- one in-cluster OpenTelemetry Collector path for OTLP reception, Kubernetes enrichment, and signal routing;
- Fluent Bit for Kubernetes/container log collection where OTLP log export is not used;
- node_exporter on monitored Linux hosts for host CPU, memory, filesystem, disk, network, load, and uptime metrics;
- kube-state-metrics and kubelet/cAdvisor for Kubernetes state and workload resource metrics;
- Data Prepper for trace/log processing, v2 service-map generation, and service-derived RED metric output;
- Prometheus for metric storage, alert evaluation, and remote-write ingestion;
- Alertmanager for grouping, inhibition, routing, and Telegram notification delivery;
- OpenSearch and OpenSearch Dashboards for logs, traces, service maps, dashboards, and investigation.

### Prometheus rule state

The final live rule baseline is:

- 9 rule groups;
- 16 alerting rules;
- 0 recording rules;
- 0 unhealthy rules after evaluation.

The live RED metrics used by application dashboards and alert rules are supplied by the Data Prepper service-map Prometheus sink. The repository keeps optional recording/reporting rules as a reusable alternative, but they are not required by this operated live path.

The standardized live rule files are:

- `application-alerts.yml`;
- `platform-alerts.yml`;
- `infrastructure-alerts.yml`.

The standardized rule groups use the reusable `observability-*` naming contract. Alert names remain stable PascalCase identifiers and were not renamed during the standardization.

### Alertmanager standard

The final live naming contract is:

- receiver: `telegram-observability`;
- template: `telegram.observability.message`;
- template file: `telegram.tmpl`.

Operational behavior remains:

- `group_wait: 30s`;
- `group_interval: 5m`;
- `repeat_interval: 4h`;
- `send_resolved: true`;
- four warning-to-critical inhibition rules for CPU, memory, filesystem, and application P99 latency.

### Log and APM presentation

Application and platform logs are deliberately separated:

- `Application Logs`;
- `Kubernetes Platform Logs`.

Application logs retain trace/span/service/time correlation metadata. Platform logs remain separate from application trace correlation.

The APM data-view display names are standardized as:

- `APM Traces`;
- `APM Service Map`.

### Dashboard presentation

The final dashboard set is:

- Infrastructure Health;
- Deployment & Workload Health;
- Application Performance;
- Developer Investigation;
- Real-Time Channel Performance;
- Kubernetes Platform Health.

Kubernetes panel titles use consistent Title Case. Infrastructure cards use consistent CPU, Memory, and Filesystem terminology.

Dashboard color thresholds are immediate visual indicators. Prometheus alert thresholds may intentionally be higher and require a sustained `for:` duration before notification.

## Change safety and rollback

Final standardization followed a backup-first operating procedure.

Before every live configuration or saved-object mutation, a timestamped backup of the affected files or objects was created. Rollback material was retained before applying changes, and post-change validation was required before accepting the new baseline.

The final backend naming change preserved full Prometheus and Alertmanager configuration directories plus a rollback script. The final UI naming change preserved every targeted saved object plus a rollback script.

Two earlier backend-standardization attempts intentionally triggered automatic rollback because validation gates failed. Subsequent verification confirmed that the previous configuration was restored and all 16 Prometheus rules returned to healthy state. This provides tested rollback evidence rather than relying only on the existence of backups.

## Closeout decision

The operated UAT observability environment is functionally complete for the current scope:

- core observability services are running;
- OpenTelemetry, logs, metrics, traces, service maps, dashboards, RBAC, and alerting dependencies are in place;
- Linux host metrics are collected from monitored hosts through node_exporter;
- application and platform telemetry are separated where appropriate;
- all 16 live alerts use the standardized naming and metadata contract;
- backup and rollback controls were exercised during final standardization;
- the public repository contains only sanitized reusable configuration and documentation.

Production HA, capacity engineering, TLS hardening, secret-management integration, retention/snapshot policy, and disaster recovery remain separate production-promotion concerns.
