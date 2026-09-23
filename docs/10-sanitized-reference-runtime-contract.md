# Sanitized Reference Runtime Contract

**Captured:** 2026-09-23  
**Scope:** Dedicated observability host runtime contract used for clean-room qualification.

This document records the operational shape of the currently operated UAT
reference without customer identifiers, internal addresses, credentials,
certificate contents, tokens, or telemetry payloads.

## Host and component contract

The reference host runs Ubuntu 24.04.4 LTS on x86_64. The currently pinned
observability components are:

| Component | Version |
|---|---:|
| OpenSearch | 3.6.0 |
| OpenSearch Dashboards | 3.6.0 |
| Data Prepper | 2.16.0 |
| Prometheus | 3.14.0 |
| Alertmanager | 0.31.1 |
| node_exporter | 1.12.1 |
| process-exporter | 0.8.7 |

## Service identities and ownership

The reference runtime uses:

- OpenSearch: `opensearch:opensearch`
- OpenSearch Dashboards: `opensearch:opensearch`
- Data Prepper: `dataprepper:dataprepper`
- Prometheus: `prometheus:prometheus`
- Alertmanager: `alertmanager:alertmanager`
- node_exporter: `node_exporter:node_exporter`
- process-exporter: `root:root`

Important reference ownership:

- `/opt/opensearch` -> `opensearch:opensearch`
- `/opt/opensearch-dashboards` -> `opensearch:opensearch`
- `/opt/data-prepper` -> `dataprepper:dataprepper`
- `/opt/prometheus` -> `prometheus:prometheus`
- `/opt/alertmanager` -> `root:root`
- `/data/prometheus` -> `prometheus:prometheus`
- `/data/alertmanager` -> `alertmanager:alertmanager`

## OpenSearch runtime

The reference node is a secured single-node deployment.

- data path: `/data/opensearch`
- log path: `/data/logs/opensearch`
- HTTP: 9200
- transport: 9300
- security plugin enabled
- HTTP TLS enabled
- transport TLS enabled
- private PKI supplies node, CA, and administrator identities
- effective heap: 2 GiB min / 2 GiB max
- `bootstrap.memory_lock: false`

Private PKI material and distinguished names are environment inputs and are
never stored in this public repository.

## OpenSearch Dashboards runtime

The reference Dashboards process listens on 5601 and connects to OpenSearch
over verified HTTPS. The functional feature contract is:

- workspace enabled
- multiple data source support enabled
- Explore enabled
- trace discovery enabled
- metric discovery enabled
- dataset management enabled
- saved-object permissions enabled
- OpenSearch Security enabled
- multitenancy disabled
- usage telemetry disabled

The service runs as the same operating-system identity as OpenSearch.

## Data Prepper runtime

The reference Data Prepper process uses Java 17 and a 512 MiB initial / 1 GiB
maximum JVM allocation.

Listener and pipeline contract:

- core API: 4900
- OTLP trace ingestion: 21890
- HTTP log ingestion: 2021
- trace entry pipeline fans out to raw trace and service-map pipelines
- raw traces use the OpenSearch trace-analytics index type
- service-map events use the OpenSearch APM service-map index type
- service-derived metrics are sent to Prometheus remote write
- log events are normalized and written to daily OpenSearch log indices
- environment name is a rendered deployment parameter, not a repository literal

OpenSearch ingest credentials and CA material are private deployment inputs.

## Prometheus runtime

- scrape interval: 30s
- evaluation interval: 30s
- external environment label: deployment parameter
- Alertmanager target: loopback 9093
- rule directory: `/etc/prometheus/rules/*.yml`
- TSDB: `/data/prometheus`
- retention time: 5d
- retention size: 3GB
- remote-write receiver enabled

Reference scrape categories include:

- Prometheus self-monitoring
- Linux node exporters
- kube-state-metrics
- kubelet/cAdvisor
- local process-exporter

Target addresses, node names, bearer-token paths, and environment labels are
deployment parameters.

## Alertmanager runtime

- listen address: 0.0.0.0:9093
- storage: `/data/alertmanager`
- resolve timeout: 5m
- grouping: alert name, severity, environment
- group wait: 10s
- group interval: 5m
- repeat interval: 4h
- notification delivery uses Telegram through a token file
- resolved notifications are enabled

The bot token and chat ID are secrets and must never be committed.

## Exporter runtime

node_exporter:

- binary: `/usr/local/bin/node_exporter`
- service user: `node_exporter`
- listen address: `0.0.0.0:9115`

process-exporter:

- binary: `/usr/local/bin/process-exporter`
- runs as root in the reference environment
- configuration: `/etc/process-exporter/process-exporter.yml`
- listen address: `127.0.0.1:9256`
- smaps disabled
- thread collection disabled
- child aggregation enabled

The reference process groups include OpenSearch, Data Prepper, OpenSearch
Dashboards, Prometheus, and an optional Grafana process definition.

## Alert rule contract

The captured application rules include:

- sustained 4xx rate above 10% with traffic/error volume gates;
- sustained 5xx rate above 5% with traffic/fault volume gates;
- application availability below 99% with traffic/fault volume gates;
- P99 warning above 3 seconds and at or below 5 seconds;
- P99 critical above 5 seconds;
- Kubernetes CrashLoopBackOff detection;
- Prometheus/Alertmanager availability detection.

The captured infrastructure rules include:

- Kubernetes node NotReady;
- Prometheus target down;
- filesystem warning above 80%;
- filesystem critical above 90%;
- memory warning above 85%;
- memory critical above 95%;
- CPU warning above 85%;
- CPU critical above 95%;
- RKE2 image-filesystem threshold at 85%.

Environment labels and customer-specific rule-group names must be rendered from
deployment parameters.

## Qualification implication

The clean-room installer must reproduce this functional runtime contract while
keeping all organization-specific names, addresses, certificate identities,
credentials, and tokens external to the repository.

The lab may use its own generated PKI and lab credentials, but it must exercise
the same secured HTTPS/TLS path and service relationships rather than disabling
security for convenience.
