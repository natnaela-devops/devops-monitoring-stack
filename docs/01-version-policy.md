# Version and Lifecycle Policy

**Baseline date:** 2026-09-23  
**Scope:** RKE2 application cluster and the dedicated OpenSearch observability platform.

## Objective

This repository pins exact, validated component versions so that the lab, UAT, and production environments can be reproduced and audited. Version selection favors operational stability, security support, and cross-component compatibility over adopting the newest release immediately.

## Selection policy

1. Only stable releases are eligible; release candidates, beta, and nightly builds are excluded.
2. The default long-term selection target is the latest stable minor release minus two minor releases (**N-2**), but the current v1 qualification deliberately reproduces the operated UAT reference stack exactly before any upgrade is attempted.
3. Exact patch versions and container tags are pinned. Floating tags such as `latest` are prohibited.
4. An actively supported LTS release takes precedence over N-2.
5. Compatibility, security, or missing-distribution constraints may override N-2.
6. Every exception must be documented in the baseline table.
7. Versions do not change automatically. Each upgrade is tested in the lab, then UAT, before production.
8. OpenSearch and OpenSearch Dashboards must always use the same version.
9. Configuration, dashboards, and validation evidence must be committed with the version they were tested against.

## Validated and production baseline

The dedicated observability-host entries below were verified directly from the current UAT reference environment on 2026-09-23. Kubernetes-side entries remain separately pinned and must be revalidated before they are changed.

| Component | Current pinned version | Scope / rationale |
|---|---:|---|
| Ubuntu Server | 22.04 LTS | Existing operating-system baseline |
| RKE2 / Kubernetes | v1.35.7+rke2r1 / v1.35.7 | Existing cluster-side repository baseline; not changed by the dedicated-host parity test |
| OpenSearch | 3.6.0 | Exact UAT reference version for v1 parity qualification |
| OpenSearch Dashboards | 3.6.0 | Must exactly match OpenSearch |
| Data Prepper | 2.16.0 | Exact UAT reference version |
| Prometheus | 3.14.0 | Exact UAT reference version |
| Alertmanager | 0.31.1 | Exact UAT reference version |
| node_exporter | 1.12.1 | Exact verified exporter version; deployed on monitored Linux hosts as required |
| process-exporter | 0.8.7 | Exact UAT observability-host version |
| OpenTelemetry Collector Contrib | 0.156.0 | Existing cluster-side pin; revalidate separately against the reference cluster |
| OpenTelemetry Operator | 0.154.0 | Existing cluster-side pin; revalidate separately against the reference cluster |
| OpenTelemetry Operator Helm chart | 0.119.0 | Existing chart pin |
| OpenTelemetry Java agent | 2.30.0 | Current application instrumentation baseline used by the reference implementation |
| Java runtime | 17.0.19 | Existing repository baseline; application runtime remains independently managed |
| Helm client | 3.20.0 | Existing repository baseline |

## Documented exceptions

### Reference-UAT parity for v1

The v1 qualification intentionally pins the exact versions already operating in the current UAT reference environment rather than introducing version changes while deployment automation, backup/restore, idempotency, RBAC, dashboards, and alerting are still being qualified. Version modernization will be handled as a separate, later change with the full validation lifecycle.

### Dedicated-host OpenTelemetry Collector

No standalone OpenTelemetry Collector service is installed on the reference observability host. Collector/Operator components are cluster-side concerns and remain independently versioned.

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
