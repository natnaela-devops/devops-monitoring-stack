# Ubuntu 24.04 Clean-Room Qualification

**Qualification date:** 2026-09-27  
**Scope:** Dedicated observability-host runtime qualification on a fresh Ubuntu 24.04 LTS virtual machine.

## Result

The clean-room host-runtime qualification passed.

The test host was rebuilt from a fresh Ubuntu 24.04 LTS installation, prepared through the repository bootstrap path, configured with private lab-only PKI and credentials, and then activated with the repository-defined OpenSearch observability stack.

No customer credentials, production addresses, private certificate material, or telemetry payloads are recorded here.

## Qualified host baseline

The qualification host used:

- Ubuntu 24.04.5 LTS;
- x86_64;
- swap disabled;
- `vm.max_map_count=262144`;
- repository commit `e58fbe6`;
- OpenSearch 3.6.0;
- OpenSearch Dashboards 3.6.0;
- Data Prepper 2.16.0;
- Prometheus 3.14.0;
- Alertmanager 0.31.1;
- node_exporter 1.12.1;
- process-exporter 0.8.7.

The host was intentionally resource-constrained for functional qualification rather than capacity validation.

## Configuration and security checks

Before activation:

- the repository clean-room preflight passed;
- pinned artifacts were verified and installed;
- private lab PKI was generated outside Git;
- node and administrator certificates validated against the private CA;
- rendered configuration contained no unresolved placeholders;
- Prometheus configuration passed `promtool`;
- all rendered Prometheus rule files passed `promtool`;
- Alertmanager configuration and the Telegram template passed `amtool`;
- OpenSearch Security was initialized through the administrator certificate;
- secured HTTPS authentication to OpenSearch was verified.

The lab Data Prepper account used an intentionally broad role only for isolated qualification. Production remains required to use a dedicated least-privilege ingest role.

## Runtime result

All seven dedicated-host services remained active throughout the five-minute soak:

- OpenSearch;
- OpenSearch Dashboards;
- Data Prepper;
- Prometheus;
- Alertmanager;
- node_exporter;
- process-exporter.

The qualification also confirmed:

- Prometheus readiness healthy;
- Alertmanager readiness healthy;
- OpenSearch Dashboards reachable;
- all configured Prometheus scrape targets UP;
- 16 standardized alerting rules loaded;
- 13 optional recording/reporting rules loaded for this qualification run;
- zero unhealthy Prometheus rules;
- no failed systemd units;
- no OOM-killer activity during the soak;
- no qualifying Data Prepper failures during the soak;
- sufficient memory remained available for the functional test;
- root filesystem usage remained below the configured warning threshold.

## OpenSearch single-node health

OpenSearch remained `yellow` with all primary shards active and only replica shards unassigned.

This is acceptable for the repository's single-node functional qualification. It is not a production-HA claim. Production requires the separately documented multi-node topology and capacity/recovery gates.

## Scope boundary

This qualification proves the dedicated observability-host runtime can be rebuilt and operated successfully on Ubuntu 24.04 LTS using the repository-defined component baseline.

It does **not** by itself close the separate production-promotion requirements for representative load, multi-node OpenSearch, external secret management, backup/restore testing, network hardening, or Kubernetes-side telemetry revalidation.

Those items remain production-hardening gates rather than blockers for the completed UAT implementation.
