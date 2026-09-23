# Dedicated observability host templates

These files are sanitized deployment templates for the machine that runs OpenSearch, OpenSearch Dashboards, Data Prepper, Prometheus, Alertmanager, and host-level process monitoring outside the RKE2 application cluster.

They intentionally contain no addresses, credentials, certificates, or environment-specific names. Render every `{{ ... }}` value from a private environment overlay or approved secrets manager before installation.

| Path | Destination | Purpose |
|---|---|---|
| `artifacts.lock.env` | Installer input | Integrity metadata for pinned binary artifacts |
| `opensearch/opensearch.yml.example` | OpenSearch configuration directory | Node, storage, discovery, and security baseline |
| `opensearch/heap.options.example` | `jvm.options.d/heap.options` | Explicit equal minimum and maximum heap |
| `dashboards/opensearch_dashboards.yml.example` | Dashboards configuration directory | HTTPS UI and OpenSearch connection baseline |
| `data-prepper/data-prepper-config.yaml` | `/etc/data-prepper/data-prepper-config.yaml` | Data Prepper core API and circuit breaker |
| `data-prepper/pipelines.example.yaml` | `/etc/data-prepper/pipelines/pipelines.yaml` | Logs, traces, and v2 service-map pipelines |
| `systemd/opensearch.service` | `/etc/systemd/system/opensearch.service` | Canonical `/opt/opensearch` service definition |
| `systemd/opensearch-dashboards.service` | `/etc/systemd/system/opensearch-dashboards.service` | Canonical `/opt/opensearch-dashboards` service definition |
| `systemd/data-prepper.service` | `/etc/systemd/system/data-prepper.service` | Pinned Data Prepper process definition |
| `systemd/prometheus.service` | `/etc/systemd/system/prometheus.service` | Pinned Prometheus process definition |
| `systemd/alertmanager.service` | `/etc/systemd/system/alertmanager.service` | Pinned Alertmanager process definition |
| `systemd/node_exporter.service` | `/etc/systemd/system/node_exporter.service` | Reference node_exporter definition on port 9115 |
| `systemd/process-exporter.service` | `/etc/systemd/system/process-exporter.service` | Pinned process-exporter definition |
| `systemd/prometheus.service.d/apm-remote-write.conf` | `/etc/systemd/system/prometheus.service.d/apm-remote-write.conf` | Effective 5d/3GB Prometheus retention and remote-write receiver |
| `systemd/data-prepper.service.d/snappy-glibc.conf.example` | Optional Data Prepper drop-in | Reference native Snappy override; enable only after the native library is installed and validated |

Do not copy a template into service without first following [Dedicated Observability Host Bootstrap](../docs/06-observability-host-bootstrap.md).

The exact currently operated reference versions are documented in [Reference UAT Observability Baseline](../docs/08-reference-uat-baseline.md).

## Clean-room binary bootstrap

After `scripts/verify-clean-lab.sh` passes, use the Git-tracked binary bootstrap in two gates:

```bash
bash scripts/bootstrap-reference-binaries.sh --plan
bash scripts/bootstrap-reference-binaries.sh --apply
```

The bootstrap installs the exact versions pinned in `versions.env`, verifies signed/checksummed artifacts where upstream verification material is available, installs canonical systemd unit definitions, and deliberately leaves all observability services stopped. Configuration and service activation are a separate qualification stage.

## Runtime identity parity

The reference runtime intentionally uses shared ownership for OpenSearch and
Dashboards (`opensearch:opensearch`), `dataprepper:dataprepper` for Data
Prepper, `prometheus:prometheus` for Prometheus, `alertmanager:alertmanager`
for Alertmanager, `node_exporter:node_exporter` for node_exporter, and root for
process-exporter. The binary bootstrap enforces these identities and leaves all
services stopped until configuration validation is complete.
