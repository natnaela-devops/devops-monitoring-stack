# Alerting Standard

## Purpose

This repository keeps alert detection, routing, presentation, and secrets separate so the same alerting design can be reused across lab, UAT, and production environments.

The standardized contract was validated against the operated UAT reference environment and then sanitized for repository use.

## Responsibility split

- **Exporters / application telemetry** provide metrics.
- **Prometheus** evaluates alert rules and determines when a condition is firing or recovered.
- **Alertmanager** groups, routes, and delivers notifications.
- **Telegram** is a notification destination only.

Telegram messages therefore identify Prometheus as the detector and Alertmanager as the notification component. When a metric has a useful source label such as `job=node-exporter`, the template exposes that as the metric source.

## Alert labels

Every operational alert should provide:

- `severity`: normally `warning` or `critical`;
- `team`: for example `infrastructure` or `application`;
- `environment`: rendered from the target deployment environment.

Additional category labels may be used when useful.

## Alert annotations

Use the following operator-facing annotation contract where semantically meaningful:

- `summary`: short human-readable problem statement;
- `description`: what condition has persisted and for how long;
- `observed`: current measured value when the alert expression produces a meaningful numeric value;
- `threshold`: configured trigger condition;
- `impact`: likely operational or user impact;
- `action`: first investigation or remediation step;
- `recovery`: factual statement describing what condition is no longer being reported.

Do not invent an `observed` value for binary conditions such as NotReady or CrashLoopBackOff.

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

The standard template prefers human-readable resource identity:

- Service
- Node
- plain IP address
- Namespace / Pod / Container
- Resource / mountpoint

It intentionally does **not** show Prometheus scrape-target `instance=IP:port` when a cleaner node/IP identity is already available.

A recovery notification means that Prometheus no longer reports the configured alert condition. It does not claim whether recovery was automatic or operator-driven.

## Repository files

- `prometheus/rules/infrastructure-alerts.yml.example` — standardized infrastructure alerts;
- `prometheus/rules/application-alerts.yml.example` — standardized application and supplemental platform alerts;
- `observability-host/alertmanager/telegram.tmpl` — common Telegram presentation template;
- `observability-host/alertmanager/alertmanager.yml.example` — sanitized routing example.

The reference configuration renderer converts the environment-aware rule examples into deployable `.yml` rule files and validates them with `promtool`.

## Secret handling

Never commit:

- Telegram bot tokens;
- real Telegram chat IDs used by a customer environment;
- OpenSearch passwords;
- private keys;
- kubeconfigs or bearer tokens.

The bot token is read from a private file. On the validated reference host the token-file access model is equivalent to owner/group read only for the service account that needs it.

A chat ID is an identifier rather than an authentication credential, but real deployment-specific IDs should still remain outside the public repository.

## Recovery and delivery notes

`send_resolved: true` remains enabled so operators receive recovery notifications.

A Prometheus rule such as `PrometheusAlertmanagerUnavailable` is still useful for Prometheus-side visibility, but if the only Alertmanager instance is actually unavailable it cannot deliver its own Telegram notification. An independent watchdog is a future hardening option and is not required for the current functional baseline.
