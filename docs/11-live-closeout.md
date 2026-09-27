# Live Observability Closeout

**Status:** Passed  
**Closeout date:** 2026-09-27

This document records the sanitized final verification of the operated UAT
observability environment. Customer names, internal hostnames, private
addresses, credentials, certificate identities, tokens, and telemetry payloads
are intentionally excluded.

## Final verification result

The Git-tracked live closeout verifier completed successfully against the
operated environment.

### Services

All expected services were active:

- OpenSearch
- OpenSearch Dashboards
- Data Prepper
- Prometheus
- Alertmanager
- process-exporter
- node_exporter

### Listener contract

All expected listener ports were present:

- Data Prepper HTTP logs: 2021
- Data Prepper core API: 4900
- OpenSearch Dashboards: 5601
- Prometheus: 9090
- Alertmanager: 9093
- node_exporter: 9115
- OpenSearch HTTPS: 9200
- process-exporter: 9256
- OpenSearch transport: 9300
- Data Prepper OTLP traces: 21890

### Readiness and reachability

The final verification confirmed:

- Prometheus readiness endpoint healthy;
- Alertmanager readiness endpoint healthy;
- node_exporter metrics reachable;
- process-exporter metrics reachable;
- OpenSearch HTTPS reachable and protected by authentication;
- OpenSearch Dashboards reachable and protected by authentication.

### Configuration validation

The live configuration passed:

- Prometheus configuration validation;
- Prometheus alert-rule validation;
- Alertmanager configuration validation.

### Loaded Prometheus rule state

The live Prometheus API reported:

- 9 rule groups;
- 16 alerting rules;
- 0 recording rules.

### Alerting standardization

The final alerting pass preserved every validated PromQL expression and every
`for:` duration while standardizing operator-facing metadata. The live rule
set uses consistent severity, team, and environment labels plus summary,
description, threshold, impact, action, and recovery annotations. Numeric
`observed` annotations are included only when the rule value is meaningful.

Telegram notifications use a shared Alertmanager template with explicit ALERT
and RECOVERED states, Prometheus identified as the detector, Alertmanager as
the notification component, and plain node/IP identity rather than exposing a
scrape-target `IP:port` when cleaner labels are available.

### Telemetry presence

The final verification confirmed that the derived request metric used by the
application-observability dashboards was present for the target UAT environment.

## Closeout decision

The operated UAT observability environment is considered functionally complete
for the current scope:

- core observability services are running;
- metrics, traces, logs, dashboards, RBAC, and alerting dependencies are in place;
- alerting configuration is loaded and valid;
- host and application telemetry are present;
- the reusable repository reproduces the pinned component baseline and captures
  the reference runtime contract.

Remaining repository hardening work, including full disaster/restore
qualification and any later operating-system/version modernization, is tracked
separately and does not block this environment closeout.
