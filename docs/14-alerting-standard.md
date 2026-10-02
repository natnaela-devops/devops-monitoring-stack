# Alerting Standard

## Purpose

This repository keeps alert detection, routing, presentation, and secrets separate so the same alerting design can be reused across lab, UAT, and production environments.

The final live contract was validated against the operated UAT reference environment and sanitized for repository use.

## Responsibility split

- **Exporters / application telemetry** provide metrics.
- **Prometheus** evaluates alert rules and determines when a condition is pending, firing, or recovered.
- **Alertmanager** groups, inhibits, routes, and delivers notifications.
- **Telegram** is a notification destination only.

Telegram messages identify Prometheus as the detector and Alertmanager as the notification component. When a metric has a useful source label such as `job=node-exporter`, the template exposes that as the metric source.

## Naming contract

Prometheus rule files use functional, environment-neutral names:

- `application-alerts.yml`;
- `platform-alerts.yml`;
- `infrastructure-alerts.yml`.

Rule groups use lowercase kebab-case and the `observability-` prefix:

- `observability-application-errors`;
- `observability-application-latency`;
- `observability-platform-health`;
- `observability-kubernetes-availability`;
- `observability-monitoring-targets`;
- `observability-node-cpu`;
- `observability-node-memory`;
- `observability-node-filesystem`;
- `observability-rke2-storage`.

Alert names are stable PascalCase identifiers such as `NodeDiskUsageHigh` and `ApplicationP99LatencyCritical`. Customer names and environment names do not belong in alert or rule-group identifiers; deployment scope belongs in labels such as `environment`.

## Alert labels

Every operational alert provides:

- `severity`: normally `warning` or `critical`;
- `team`: for example `infrastructure` or `application`;
- `environment`: rendered from the target deployment environment.

Additional category labels are used where useful.

## Alert annotations

Use the following operator-facing annotation contract where semantically meaningful:

- `summary`;
- `description`;
- `observed` when the expression produces a meaningful numeric value;
- `threshold`;
- `impact`;
- `action`;
- `recovery`.

Do not invent an `observed` value for binary conditions such as NotReady or CrashLoopBackOff.

## Alertmanager contract

The reusable naming contract is:

- receiver: `telegram-observability`;
- template: `telegram.observability.message`;
- template file: `telegram.tmpl`.

The validated routing timing is:

- `group_wait: 30s`;
- `group_interval: 5m`;
- `repeat_interval: 4h`;
- `send_resolved: true`.

The final configuration inhibits a warning when the matching critical alert is firing for the same resource:

- node filesystem usage: match by environment, node, and mountpoint;
- node CPU usage: match by environment and node;
- node memory usage: match by environment and node;
- application P99 latency: match by environment and service.

## Telegram presentation

Firing notifications use severity-aware headings such as:

```text
🚨 ALERT — CRITICAL
⚠️ ALERT — WARNING
```

Recovered notifications use:

```text
✅ RECOVERED
```

The presentation is grouped and compact. Common threshold, impact, and action context should not be repeated unnecessarily for every resource in the same notification group.

The template prefers human-readable resource identity and does not expose a raw scrape-target `IP:port` when cleaner node/IP labels are available.

A recovery notification means that Prometheus no longer reports the configured alert condition. It does not claim whether recovery was automatic or operator-driven.

## Live rule architecture versus optional recording rules

The operated UAT baseline uses 16 alerting rules and 0 recording rules. Its live `span_derived` RED metrics are produced by the Data Prepper service-map Prometheus sink.

The repository may retain optional recording/reporting rule examples for environments that derive or precompute those metrics differently. Such optional rules must not be assumed to be active in the live baseline.

## Repository files

- `prometheus/rules/infrastructure-alerts.yml.example`;
- `prometheus/rules/application-alerts.yml.example`;
- `prometheus/rules/platform-alerts.yml.example`;
- `observability-host/alertmanager/telegram.tmpl`;
- `observability-host/alertmanager/alertmanager.yml.example`.

The reference renderer substitutes deployment-specific environment values and validates generated rule files with `promtool`.

## Change safety

Operational changes follow:

`backup -> stage -> validate -> apply/reload -> verify -> retain rollback`.

A configuration change is not accepted merely because the service reloads. Prometheus rules must complete evaluation without `health="err"` or `lastError`, and Alertmanager must pass configuration validation.

## Secret handling

Never commit Telegram bot tokens, real deployment chat IDs, OpenSearch passwords, private keys, kubeconfigs, bearer tokens, internal hostnames, or private addresses.

The Telegram bot token is read from a private file. Deployment-specific chat IDs remain outside the public repository.

## Delivery limitation

`PrometheusAlertmanagerUnavailable` is useful for Prometheus-side visibility, but an unavailable sole Alertmanager instance cannot deliver its own Telegram notification. Independent watchdog delivery is a production-hardening option.
