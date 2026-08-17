# Lab Preflight Validation

**Validation date:** 2026-08-17  
**Environment:** Functional lab  
**Decision:** PASS for the next lab implementation stage

## Purpose

This record confirms that the RKE2 lab was stable and had sufficient capacity before continuing with reusable OpenTelemetry instrumentation. It is sanitized for a public repository: hostnames, addresses, credentials, tokens, and raw configuration are excluded.

This result validates the functional lab only. It is not a production readiness approval.

## Validated component state

| Component | Version | Result |
|---|---:|---|
| RKE2 | v1.35.7+rke2r1 | PASS |
| Kubernetes | v1.35.7 | PASS |
| Canal | RKE2-managed | PASS |
| OpenTelemetry Collector Contrib | 0.156.0 | PASS |
| OpenTelemetry Operator | 0.154.0 | PASS |
| OpenTelemetry Operator Helm chart | 0.119.0 | PASS |
| Helm client | 3.20.0 | PASS |

## Cluster health evidence

The following conditions were observed:

- Kubernetes API readiness returned `ok`.
- The lab node remained `Ready`.
- Canal reported both containers ready.
- Every Deployment reported its desired replica ready and available.
- The OpenTelemetry Operator Deployment reported one ready replica.
- The existing Collector Deployment reported one ready replica.
- The sample gateway and payment Deployments both reported one ready replica.
- RKE2 remained active and running throughout a five-minute observation window.
- The RKE2 systemd restart counter remained unchanged at zero during that window.

Historical container restart counters were retained as evidence of earlier lab instability. No new restart occurred during the validation window.

## Remediation performed

### Terminal pod cleanup

Earlier unclean RKE2/containerd restarts had left failed, succeeded, and `ContainerStatusUnknown` pod objects visible in the API. Their owning Deployments already had healthy replacement pods.

Only terminal pod records were removed. Deployments, active pods, Services, ConfigMaps, and persistent application state were not deleted. Kubernetes controllers remained responsible for the desired replicas.

After cleanup:

- all listed application, monitoring, system, and Operator pods were running;
- all Deployments were ready and available;
- no required workload needed manual recreation.

### Disk-capacity remediation

The root filesystem initially exceeded the lab threshold. Unrelated obsolete workstation artifacts were removed; RKE2 data and active virtual-machine disks were not modified.

| Measurement | Before | After |
|---|---:|---:|
| Root filesystem use | 92% | 84% |
| Available root capacity | 25 GiB | 45 GiB |
| RKE2 data footprint | 5.6 GiB | Unchanged |

The retained free space is acceptable for continued functional lab work. Production must follow the higher capacity and headroom requirements in [Infrastructure Prerequisites](03-infrastructure-prerequisites.md).

## Lab capacity observation

| Resource | Observed result | Assessment |
|---|---:|---|
| Memory | 15 GiB total; 4.7 GiB available | Acceptable for functional testing; not a production sizing result |
| Swap | 2 GiB configured; limited use observed | Lab exception; production settings must follow the approved RKE2 and OpenSearch standards |
| Root filesystem | 84% used after remediation | PASS for the next lab stage; continue monitoring |
| RKE2 storage | 5.6 GiB | Not the source of the earlier disk pressure |

## OpenTelemetry installation state

One Operator installation exists for the cluster. The Operator is a Kubernetes controller and is not installed once per node.

Current lab state:

- Operator chart: `0.119.0`
- Operator application: `0.154.0`
- Operator Deployment: ready and available
- Instrumentation and Collector CRDs: installed
- Existing Collector: manually managed Deployment, version `0.156.0`
- Sample Java services: currently use an embedded Java agent

The existing sample services must not also receive Operator-based Java-agent injection. A clean test workload, or images rebuilt without the embedded agent, will be used to validate automatic instrumentation.

## Gate result

| Lab gate | Result |
|---|---|
| Version baseline recorded | PASS |
| RKE2 node and API healthy | PASS |
| Canal healthy | PASS |
| Current Deployments available | PASS |
| Terminal pod records remediated | PASS |
| Five-minute RKE2 stability check | PASS |
| Lab disk threshold | PASS |
| Operator installation healthy | PASS |
| Secrets excluded from evidence | PASS |
| Production TLS, HA, recovery and capacity approval | DEFERRED |

## Next stage

The next implementation stage will:

1. preserve sanitized Operator and Collector configuration in Git;
2. add a dedicated Collector ServiceAccount and least-privilege RBAC;
3. add Kubernetes resource enrichment consistently to traces, metrics, and logs;
4. define a reusable, opt-in `Instrumentation` resource;
5. validate automatic instrumentation without double-instrumenting existing services;
6. record end-to-end trace, log, metric, and service-map evidence.
