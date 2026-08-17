# Kubernetes Telemetry Onboarding

**Validation date:** 2026-08-17
**Environment:** Functional RKE2 lab
**Decision:** PASS for reusable application onboarding

## Purpose

This stage provides one cluster-level telemetry path for a large application fleet. Applications send OTLP traces, logs, and metrics to a central in-cluster Collector. The Collector enriches all three signals with Kubernetes metadata and forwards them to the external observability services.

The manifests are sanitized examples. Replace the endpoint examples, environment name, cluster name, namespaces, registry, and capacity values before deployment.

## Validated versions

| Component | Version |
|---|---:|
| OpenTelemetry Collector Contrib | 0.156.0 |
| OpenTelemetry Operator | 0.154.0 |
| OpenTelemetry Operator Helm chart | 0.119.0 |
| OpenTelemetry Java agent | 2.28.1 |
| Fluent Bit | 4.1.0 |
| Data Prepper | 2.14.1 |
| OpenSearch and Dashboards | 3.7.0 |

## Cluster-level flow

1. A Java application uses exactly one OpenTelemetry Java agent.
2. The agent sends OTLP signals to `otel-collector.monitoring.svc.cluster.local`.
3. The Collector adds namespace, pod, workload, node, container, and image identity.
4. Traces and correlated logs are sent to Data Prepper.
5. Metrics are sent to the Prometheus remote-write endpoint.
6. Data Prepper creates trace documents and v2 service-map relationships in OpenSearch.

One Operator installation serves the Kubernetes cluster. It is not installed once per node or once per application.

## Mandatory instrumentation decision

Every Java workload must use exactly one of these modes.

| Image state | Required mode | Injection annotation |
|---|---|---|
| Image already starts Java with `-javaagent` | Embedded-agent mode | Must be absent |
| Image contains no Java agent | Operator-injected mode | `instrumentation.opentelemetry.io/inject-java: monitoring/platform-java` |

Never enable Operator injection on an image that already starts an embedded agent. A double agent can duplicate signals, increase memory and CPU use, or prevent application startup.

## Embedded-agent onboarding

Use [java-embedded-agent.yaml](../kubernetes/examples/java-embedded-agent.yaml) for the current application fleet whose images already include the Java agent.

For each workload:

1. confirm that the Java command contains one `-javaagent` argument;
2. configure the central OTLP endpoint and exporters;
3. assign stable `service.name`, `service.namespace`, `service.version`, and environment identity;
4. add `fluentbit.io/exclude: "true"` when OTLP log export is enabled;
5. do not add an Operator injection annotation.

## Operator-injected onboarding

Use [java-operator-injected.yaml](../kubernetes/examples/java-operator-injected.yaml) only for an agentless application image. The Operator injects the pinned Java agent through an init container and supplies the standard OTLP environment.

The shared [Instrumentation](../kubernetes/instrumentation/java.yaml) resource is opt-in. No application is mutated until its pod template carries the explicit injection annotation.

The lab validation deliberately bypassed the sample image's embedded-agent entrypoint before enabling injection. Inspection confirmed one injected init container and one `JAVA_TOOL_OPTIONS` agent argument.

## Duplicate-log policy

Fluent Bit collects container stdout cluster-wide. Java auto-instrumentation can also export the same application records through OTLP with trace and span context.

For applications using `OTEL_LOGS_EXPORTER=otlp`, add this pod-template annotation:

```yaml
fluentbit.io/exclude: "true"
```

The Fluent Bit Kubernetes filter must have `K8S-Logging.Exclude On`. System workloads and applications that do not export OTLP logs remain collected through Fluent Bit.

## Collector security and metadata

The Collector uses a dedicated ServiceAccount and read-only `get`, `list`, and `watch` permissions. It cannot create, update, patch, or delete Kubernetes resources.

The `k8s_attributes` processor enriches telemetry with:

- namespace, pod, pod UID, and pod start time;
- Deployment, ReplicaSet, DaemonSet, or StatefulSet identity;
- node and container identity;
- container image name and tag.

The Collector container runs as non-root, drops all Linux capabilities, prevents privilege escalation, uses a read-only root filesystem, and applies the runtime-default seccomp profile.

## Deployment order

1. Install the Operator with chart `0.119.0` and [values.yaml](../kubernetes/operator/values.yaml).
2. Customize the external endpoints and cluster name.
3. Validate the Collector configuration using the pinned Collector image.
4. Apply [kubernetes/collector](../kubernetes/collector).
5. Apply the shared Java `Instrumentation` resource.
6. Select exactly one instrumentation mode per workload.
7. validate one application before enabling additional namespaces.

## Validation evidence

The lab produced the following results:

- Collector configuration validation succeeded before rollout.
- Collector rollout completed without warnings or errors.
- Dedicated Collector RBAC returned `yes` for required reads and no write permissions were granted.
- A newly Operator-instrumented Java service exported traces, logs, and metrics.
- The reporting rules discovered the new service automatically.
- Kubernetes metadata existed in both log and span resource attributes.
- Four business log records shared one trace across the gateway and payment services.
- Fluent Bit exclusion removed the two duplicate, uncorrelated gateway log records.
- The v2 service map created the expected gateway-to-payment relationship.

No internal addresses, hostnames, credentials, tokens, trace identifiers, transaction identifiers, or pod identifiers are retained in this public evidence.

## Rollback

If a Collector rollout fails:

1. restore the previous ConfigMap;
2. restart the Collector Deployment;
3. wait for rollout completion;
4. verify Collector logs and application OTLP connectivity.

If Operator injection causes an application failure, remove only the injection annotation and roll back the application Deployment. Do not remove the cluster-wide Operator while unrelated instrumented applications are running.

## Production scale boundary

This commit validates the onboarding model, not final production capacity. Production must separately add Collector high availability, disruption budgets, topology spread, autoscaling or capacity-tested replicas, TLS, credential management, network policies, alerting, and disaster-recovery procedures.
