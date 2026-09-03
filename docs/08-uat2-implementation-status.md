# UAT2 Implementation Status

**Validated date:** 2026-09-03  
**Environment:** Enat UAT2  
**Purpose:** Record the implementation that is actually running and separate completed work from the remaining production-hardening phase.

## Verified component baseline

| Component | Version |
|---|---:|
| Ubuntu Server | 24.04.4 LTS |
| Linux kernel | 6.8.0-138-generic |
| RKE2 | v1.34.5+rke2r1 |
| Kubernetes / kubectl | v1.34.5 / v1.34.5+rke2r1 |
| containerd | v2.1.5-k3s1 |
| crictl | v1.34.0 |
| Helm | v3.20.1 |
| Kustomize | v5.7.1 |
| OpenSearch | 3.6.0 |
| OpenSearch Dashboards | 3.6.0 |
| Lucene | 10.4.0 |
| Data Prepper | 2.16.0 |
| Prometheus | 3.14.0 |
| Node Exporter | 1.12.1 |
| kube-state-metrics | v2.18.0 |
| Fluent Bit | 5.1.1 |
| OpenTelemetry Collector K8s | 0.158.0 |
| OpenTelemetry Operator | 0.157.0 |
| OpenTelemetry Java agent | 2.30.0 |
| telemetrygen | 0.158.0 |
| Java on observability host | 17.0.20 |

## Running topology

### RKE2 cluster

- Java workloads use OpenTelemetry Java agent 2.30.0 where instrumented.
- OpenTelemetry Collector runs as the central in-cluster OTLP gateway.
- OpenTelemetry Operator manages cluster instrumentation resources.
- Fluent Bit collects Kubernetes container stdout logs.
- kube-state-metrics exposes Kubernetes object/state metrics.

### Dedicated observability host

- OpenSearch stores trace and log documents.
- OpenSearch Dashboards provides workspaces, Discover/Explore, dashboards, and trace investigation.
- Data Prepper receives/processes telemetry and writes to OpenSearch.
- Prometheus runs as a systemd service with a 5-day / 3-GB TSDB retention limit in UAT.
- Node Exporter provides host metrics.
- A lightweight developer-search helper provides intent-based endpoint, trace, account/phone-assisted, and log search workflows.

## Trace validation

Distributed context propagation has been verified across both synchronous and asynchronous paths.

For Kafka-backed flows, producer and consumer spans retain the same OpenTelemetry traceId while receiving their own spanId values. Consumer parentSpanId values point back to producer spans where expected. This confirms that asynchronous message handling remains part of the original distributed trace rather than creating unrelated traces.

## Log normalization and correlation

Data Prepper now performs additive normalization for logs before indexing. The validated behavior includes:

- extracting structured traceId/spanId from known gateway log formats;
- preserving the canonical log timestamp while removing a parsed timestamp field that conflicted with the OpenSearch mapping;
- normalizing known phone values into `correlation.msisdn` when present in the supported message pattern;
- stripping ANSI terminal escape sequences from newly ingested message fields;
- retaining broad message search for logs while keeping trace correlation strict.

A business identifier is never treated as a trace ID. If a log contains a phone/account value but no real trace context, it is searchable as a log but is not promoted into a distributed trace.

## Developer investigation workflow

The current search experience is intentionally split into two layers:

1. **Native OpenSearch Dashboards** for Discover/Explore, dashboards, DQL/PPL filtering, trace inspection, and correlated logs.
2. **Developer Observability Search** for common investigation inputs where developers should not need to know the underlying OpenSearch field names.

The helper currently supports:

- endpoint discovery and trace-oriented filtering;
- exact 32-character OpenTelemetry trace ID lookup;
- account lookup through existing trace attributes;
- phone-assisted lookup through structured correlation fields and real trace IDs;
- broad Log Search across structured phone fields and message content;
- service, level, message, time-range, and trace filtering.

The helper does not fabricate trace context and does not silently redirect a trace-oriented query into unrelated logs.

## Dashboard work

A Developer Investigation dashboard combines HTTP/trace investigation and centralized Kubernetes logs. Shared fields such as `serviceName` and, when present in both datasets, `traceId` are suitable for global filtering. Dataset-specific fields such as HTTP route, log level, or message are naturally panel-specific.

A future refinement is a master-detail investigation flow where the upper trace/request result identifies a traceId and the lower log panel shows only logs related to the selected trace.

## Retention and storage observations

UAT log indices and raw span indices are attached to seven-day ISM policies and currently report no policy failures. Delete behavior still needs to be observed after indices actually cross the configured age threshold.

The service-map policy currently rolls indices but does not include a delete transition. The indices are small in UAT, but production should define an explicit retention decision.

The UAT observability data filesystem was measured at roughly 78% utilization during validation. Production sizing must therefore be based on measured ingest volume and retention rather than copied directly from this constrained UAT host.

## Remaining production gates

The current implementation is functionally validated, but the production-hardening phase is still open in these areas:

- OpenSearch/OpenSearch Dashboards RBAC and role separation;
- alerting routes, ownership, runbooks, and escalation;
- OpenSearch, Data Prepper, Collector, Fluent Bit, and Prometheus tuning;
- TLS/authentication and network-policy/firewall hardening;
- secrets management and credential rotation;
- snapshots/backups and restore testing;
- retention proof after the first real expiry cycle;
- representative load/soak/failure testing;
- capacity planning for production storage, memory, CPU, and HA topology.

## Publication rule

This document deliberately excludes internal IP addresses, hostnames, credentials, customer identifiers, and real trace/transaction values. Public Git history must remain sanitized even when the operational environment contains those values.
