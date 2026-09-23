# Reference UAT Observability Baseline

**Captured:** 2026-09-23  
**Purpose:** Freeze the currently operated dedicated-observability-host component versions and runtime layout before reusable-installation qualification.

This document is intentionally sanitized. It records versions, executable paths, and service roles only. It contains no customer names, internal addresses, credentials, certificates, tokens, or telemetry data.

## Verified component matrix

| Component | Version | Verified runtime path / state |
|---|---:|---|
| OpenSearch | 3.6.0 | `/opt/opensearch/bin/opensearch` |
| OpenSearch Dashboards | 3.6.0 | `/opt/opensearch-dashboards/bin/opensearch-dashboards` |
| Data Prepper | 2.16.0 | `/opt/data-prepper/bin/data-prepper` |
| Prometheus | 3.14.0 | `/opt/prometheus/prometheus` |
| Alertmanager | 0.31.1 | `/opt/alertmanager/alertmanager` |
| node_exporter | 1.12.1 | `/usr/local/bin/node_exporter`; installed where Linux host scraping is required |
| process-exporter | 0.8.7 | `/usr/local/bin/process-exporter` |
| OpenTelemetry Collector on the dedicated host | Not installed | Collector responsibilities remain cluster-side |
| OpenTelemetry Java agent | 2.30.0 | Application instrumentation baseline |

## Verified service layout

The reference dedicated host runs these systemd-managed services:

- OpenSearch
- OpenSearch Dashboards
- Data Prepper
- Prometheus
- Alertmanager
- process-exporter

The Prometheus reference process uses:

- configuration: `/etc/prometheus/prometheus.yml`
- TSDB: `/data/prometheus`
- retention time: `5d`
- retention size: `3GB`
- listen address: `0.0.0.0:9090`
- remote-write receiver enabled

The Alertmanager reference process uses:

- configuration: `/etc/alertmanager/alertmanager.yml`
- storage: `/data/alertmanager`
- listen address: `0.0.0.0:9093`

The process-exporter reference process uses:

- configuration: `/etc/process-exporter/process-exporter.yml`
- listen address: `127.0.0.1:9256`
- `gather-smaps=false`
- `threads=false`
- `children=true`

## v1 qualification rule

The first reusable release must reproduce this verified baseline before any component version modernization is attempted.

The release is not qualified until a clean lab machine passes:

1. clean host bootstrap;
2. exact-version verification;
3. configuration render and validation;
4. first apply;
5. second apply without duplicate or destructive changes;
6. backup;
7. intentional non-production damage;
8. restore;
9. post-restore verification.

Future upgrades must be performed as separate changes and must repeat the same qualification sequence.
