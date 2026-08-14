# Version and Lifecycle Policy

**Baseline date:** 2026-08-14  
**Scope:** RKE2 application cluster and the dedicated OpenSearch observability platform.

## Objective

This repository pins exact, validated component versions so that the lab, UAT, and production environments can be reproduced and audited. Version selection favors operational stability, security support, and cross-component compatibility over adopting the newest release immediately.

## Selection policy

1. Only stable releases are eligible; release candidates, beta, and nightly builds are excluded.
2. The default target is the latest stable minor release minus two minor releases (**N-2**).
3. Exact patch versions and container tags are pinned. Floating tags such as `latest` are prohibited.
4. An actively supported LTS release takes precedence over N-2.
5. Compatibility, security, or missing-distribution constraints may override N-2.
6. Every exception must be documented in the baseline table.
7. Versions do not change automatically. Each upgrade is tested in the lab, then UAT, before production.
8. OpenSearch and OpenSearch Dashboards must always use the same version.
9. Configuration, dashboards, and validation evidence must be committed with the version they were tested against.

## Validated and production baseline

| Component | Validated lab version | Production target | Selection rationale |
|---|---:|---:|---|
| Ubuntu Server | 22.04 LTS | 22.04 LTS | Long-term support operating-system baseline |
| RKE2 / Kubernetes | v1.35.7+rke2r1 | v1.35 supported patch | N-2 Kubernetes minor strategy; patch must be validated before rollout |
| OpenSearch | 3.7.0 | 3.7.x | Validated compatibility baseline; one stable release behind 3.8 |
| OpenSearch Dashboards | 3.7.0 | Same as OpenSearch | Required product-version alignment |
| Data Prepper | 2.14.1 | 2.14.1 | N-2 line and validated pipeline behavior |
| Prometheus | 3.10.0 | 3.13.2 LTS | Production uses the supported LTS line rather than an expired short-lived minor |
| OpenTelemetry Collector Contrib | 0.156.0 | 0.156.0 | Exact N-2 selection from 0.158.0 |
| OpenTelemetry Operator | Not installed yet | 0.154.0 | Numeric N-2 is 0.155.0, but no corresponding official Helm chart is available; nearest older charted version selected |
| OpenTelemetry Operator Helm chart | Not installed yet | 0.119.0 | Official chart mapping for Operator 0.154.0 |
| OpenTelemetry Java agent | 2.28.1 | 2.28.1 | N-2 line and already validated with the Spring Boot services |
| Java runtime | 17.0.19 | Java 17 LTS | Application and agent compatibility |
| Helm client | 3.20.0 | 3.20.x | Deployment client pinned for reproducible Helm rendering |

## Documented exceptions

### OpenSearch 3.7

OpenSearch 3.8 was released on 2026-08-04. Strict N-2 would now point to 3.6, but the complete observability pipeline has already been validated on 3.7. Downgrading a working datastore merely to satisfy a numeric rule would introduce migration risk without improving supportability. Version 3.7 is therefore retained as an explicit, reviewed stability exception.

### Prometheus 3.13 LTS

Prometheus minor releases normally have short maintenance periods. Prometheus 3.13 is an LTS line supported through July 2027. Production therefore targets 3.13.2 LTS instead of retaining the lab's 3.10.0 release. The upgrade remains pending lab and UAT validation.

### OpenTelemetry Operator 0.154

Operator 0.155.0 is the numerical N-2 target, but the official Helm repository does not provide a chart mapping to that application version. Chart 0.119.0 / Operator 0.154.0 is the nearest older available and compatible pairing.

## Upgrade lifecycle

1. Review upstream release notes, support status, CVEs, and breaking changes.
2. Confirm compatibility between OpenSearch, Dashboards, Data Prepper, OpenTelemetry, Prometheus, Kubernetes, and Java.
3. Update `versions.env` in a feature branch.
4. Deploy to the lab and run health, ingestion, correlation, RED-metric, SLO, and failure-recovery tests.
5. Record evidence and rollback instructions.
6. Promote the same immutable versions to UAT.
7. Observe UAT for the agreed stability period.
8. Obtain production change approval.
9. Back up stateful components and deploy through a controlled rollout.
10. Verify service health and keep the previous supported version available for rollback.

## Compatibility invariants

- OpenSearch Dashboards version equals OpenSearch version.
- Application pods use one instrumentation method only; an embedded Java agent and Operator injection must never be enabled together.
- The Collector configuration must be validated against the pinned Collector build.
- Kubernetes CRDs must match the pinned Operator/chart release.
- No credential, private key, token, internal production address, or real customer data may be committed.

## Authoritative release references

- [OpenSearch release schedule and maintenance policy](https://opensearch.org/releases/)
- [OpenSearch artifacts by version](https://opensearch.org/artifacts/by-version/)
- [Prometheus downloads](https://prometheus.io/download/)
- [Prometheus LTS policy](https://prometheus.io/docs/introduction/release-cycle/)
- [OpenTelemetry Collector releases](https://github.com/open-telemetry/opentelemetry-collector-releases/releases)
- [OpenTelemetry Operator releases](https://github.com/open-telemetry/opentelemetry-operator/releases)
- [OpenTelemetry Operator Helm chart](https://github.com/open-telemetry/opentelemetry-helm-charts/tree/main/charts/opentelemetry-operator)
