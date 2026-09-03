# Version and Lifecycle Policy

**Baseline date:** 2026-09-03  
**Scope:** Verified Enat UAT2 RKE2 application cluster and dedicated OpenSearch observability platform.

## Objective

This repository pins the exact component versions that were verified in the running UAT2 environment so the implementation can be reproduced, audited, and promoted deliberately. Version selection favors tested compatibility and operational stability over automatic upgrades.

## Selection and promotion policy

1. Exact patch versions and container tags are pinned; floating tags such as `latest` are prohibited.
2. Versions do not change automatically.
3. OpenSearch and OpenSearch Dashboards must use the same version.
4. Collector configuration must be validated against the exact Collector image that will run it.
5. Kubernetes CRDs and Operator configuration must remain compatible with the pinned Operator release.
6. Application workloads must use exactly one Java-agent instrumentation path; embedded and Operator-injected agents must never be enabled simultaneously.
7. Configuration, dashboards, and validation evidence are updated with the versions against which they were tested.
8. Every upgrade is tested outside production first, then validated in UAT before promotion.
9. Security fixes or compatibility constraints may justify a version change, but the change still follows the same validation lifecycle.

## Verified UAT2 baseline

| Component | Verified UAT2 version | Notes |
|---|---:|---|
| Ubuntu Server | 24.04.4 LTS | Observability and RKE2 hosts |
| Linux kernel | 6.8.0-138-generic | Verified on sampled hosts |
| RKE2 | v1.34.5+rke2r1 | Running cluster distribution |
| Kubernetes | v1.34.5 | Bundled with verified RKE2 release |
| kubectl | v1.34.5+rke2r1 | RKE2 client |
| Kustomize | v5.7.1 | kubectl bundled version |
| containerd | v2.1.5-k3s1 | RKE2 container runtime |
| crictl | v1.34.0 | CRI client |
| Helm | v3.20.1 | Deployment client |
| OpenSearch | 3.6.0 | Verified running datastore |
| OpenSearch Dashboards | 3.6.0 | Kept aligned with OpenSearch |
| Lucene | 10.4.0 | Reported by OpenSearch 3.6.0 |
| Data Prepper | 2.16.0 | Trace/log processing pipeline |
| Prometheus | 3.14.0 | Native systemd service on observability host |
| Node Exporter | 1.12.1 | Host metrics |
| kube-state-metrics | v2.18.0 | Kubernetes state metrics |
| Fluent Bit | 5.1.1 | Kubernetes stdout log collection |
| OpenTelemetry Collector K8s | 0.158.0 | Central OTLP gateway |
| OpenTelemetry Operator | 0.157.0 | Cluster instrumentation management |
| OpenTelemetry Java agent | 2.30.0 | Verified across instrumented running services |
| telemetrygen | 0.158.0 | Validation/test workload |
| Java runtime on observability host | 17.0.20 | Data Prepper/runtime host baseline |

The authoritative machine-readable version list is [`versions.env`](../versions.env).

## Compatibility invariants

- OpenSearch Dashboards version equals OpenSearch version.
- Application pods use one instrumentation method only.
- A business identifier never substitutes for a real OpenTelemetry traceId.
- The Collector configuration is validated against the pinned Collector build before rollout.
- Data Prepper pipeline syntax is validated before service restart.
- Kubernetes CRDs/configuration remain compatible with the pinned Operator version.
- No credential, private key, token, internal environment address, real customer identifier, or real transaction data is committed.

## Upgrade lifecycle

1. Review release notes, security advisories, support status, and breaking changes.
2. Confirm cross-component compatibility.
3. Update `versions.env` in a feature branch.
4. Validate configuration syntax before rollout.
5. Deploy to a non-production environment.
6. Run ingestion, trace-correlation, Kafka propagation, log normalization, metrics, dashboard, and failure-recovery checks.
7. Record evidence and rollback instructions.
8. Promote the exact tested versions to UAT.
9. Observe the agreed soak period and review resource usage.
10. Obtain production change approval, back up stateful components, and perform a controlled rollout.
11. Verify health, telemetry continuity, retention, alerting, and rollback readiness after deployment.

## Current production-readiness status

The UAT2 functional baseline is established. Production promotion remains gated by RBAC, alerting, tuning/capacity, TLS/authentication, secret management, backup/restore validation, explicit service-map retention, and representative failure/soak testing.

See [`08-uat2-implementation-status.md`](08-uat2-implementation-status.md) for the implementation evidence and remaining gates.
