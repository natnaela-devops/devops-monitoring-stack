# Reference Runtime Capture

Use `scripts/capture-reference-runtime.sh` on the currently operated reference
observability host before implementing a clean-room configuration/activation
stage.

The script is read-only. It captures exact version, service, path, port, and
configuration contracts while redacting lines containing passwords, tokens,
secrets, Telegram bot tokens/chat IDs, and authorization values.

Run on the intended reference host:

```bash
bash scripts/capture-reference-runtime.sh --plan
REFERENCE_HOST="$(hostname -s)" bash scripts/capture-reference-runtime.sh --capture
```

The capture refuses to run if `REFERENCE_HOST` does not match the current host.
It also requires OpenSearch, Dashboards, Data Prepper, Prometheus, Alertmanager,
and process-exporter to be active by default. This prevents an inactive lab host
from being mistaken for the operated reference environment.

The output is operational evidence, not a public-repository artifact. It may
still contain environment names, hostnames, addresses, certificate paths, and
distinguished names. Use it to update sanitized templates; do not commit the raw
capture.

The configuration/activation installer must not be implemented from assumptions
when a runtime contract can be measured from the reference environment.


## Completeness checks

Before configuration rendering is implemented, the reference capture must include:
- the node_exporter unit if the reference host exposes node metrics;
- Data Prepper trace, log, and internal API listener ports;
- the actual Prometheus rule contents, not only filenames;
- the actual Alertmanager message templates, with secret-bearing lines redacted.

This avoids reproducing only the core services while silently omitting alerting,
host-metrics, or log-ingestion behavior.
