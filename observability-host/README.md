# Dedicated observability host templates

These files are sanitized deployment templates for the machine that runs OpenSearch, OpenSearch Dashboards, Data Prepper, and Prometheus outside the RKE2 application cluster.

They intentionally contain no addresses, credentials, certificates, or environment-specific names. Render every `{{ ... }}` value from a private environment overlay or approved secrets manager before installation.

| Path | Destination | Purpose |
|---|---|---|
| `opensearch/opensearch.yml.example` | OpenSearch configuration directory | Node, storage, discovery, and security baseline |
| `opensearch/heap.options.example` | `jvm.options.d/heap.options` | Explicit equal minimum and maximum heap |
| `dashboards/opensearch_dashboards.yml.example` | Dashboards configuration directory | HTTPS UI and OpenSearch connection baseline |
| `data-prepper/data-prepper-config.yaml` | `/etc/data-prepper/data-prepper-config.yaml` | Data Prepper core API and circuit breaker |
| `data-prepper/pipelines.example.yaml` | `/etc/data-prepper/pipelines/pipelines.yaml` | Logs, traces, and v2 service-map pipelines |
| `systemd/data-prepper.service` | `/etc/systemd/system/data-prepper.service` | Pinned Data Prepper process definition |
| `systemd/prometheus.service` | `/etc/systemd/system/prometheus.service` | Pinned Prometheus process definition |

Do not copy a template into service without first following [Dedicated Observability Host Bootstrap](../docs/06-observability-host-bootstrap.md).
