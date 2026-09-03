# Kubernetes Telemetry Onboarding

**Validation date:** 2026-09-03  
**Environment:** Enat UAT2 RKE2 cluster  
**Decision:** PASS for the current reusable application-onboarding model

## Purpose

This stage provides one cluster-level telemetry path for a large application fleet. Instrumented applications send OTLP traces to a central in-cluster Collector, while Fluent Bit collects Kubernetes container stdout logs. The telemetry pipeline enriches and processes those signals before storage in the dedicated observability platform.

The manifests in this repository are sanitized examples. Replace endpoint examples, environment names, cluster names, namespaces, registries, credentials, and capacity values before deployment.

## Verified UAT2 versions

| Component | Version |
|---|---:|
| OpenTelemetry Collector K8s | 0.158.0 |
| OpenTelemetry Operator | 0.157.0 |
| OpenTelemetry Java agent | 2.30.0 |
| Fluent Bit | 5.1.1 |
| kube-state-metrics | v2.18.0 |
| Data Prepper | 2.16.0 |
| OpenSearch / OpenSearch Dashboards | 3.6.0 |
| RKE2 / Kubernetes | v1.34.5+rke2r1 / v1.34.5 |

The exact running image tags and host binaries were verified from the UAT2 environment. See [`versions.env`](../versions.env).

## Cluster-level flow

1. A Java workload uses exactly one OpenTelemetry Java agent where instrumentation is enabled.
2. The agent sends OTLP trace data to the central in-cluster Collector.
3. The Collector adds Kubernetes resource identity and routes trace telemetry toward the processing layer.
4. Fluent Bit collects container stdout logs cluster-wide and sends them to the log-ingestion path.
5. Data Prepper parses/normalizes telemetry and writes trace/log documents to OpenSearch.
6. kube-state-metrics and Node Exporter expose Kubernetes/host metrics scraped by Prometheus.

One Operator installation serves the Kubernetes cluster. It is not installed once per node or once per application.

## Mandatory instrumentation decision

Every Java workload must use exactly one instrumentation mode.

| Image state | Required mode | Injection rule |
|---|---|---|
| Image already starts Java with `-javaagent` | Embedded-agent mode | Operator Java injection must be absent |
| Image contains no Java agent | Operator-injected mode | Enable the approved `inject-java` annotation |

Never enable Operator injection on an image that already starts an embedded agent. A double agent can duplicate telemetry, increase memory/CPU use, or prevent application startup.

## Current embedded-agent validation

The UAT2 cluster was inspected directly and multiple running services across application namespaces reported:

```text
opentelemetry-javaagent - version: 2.30.0
```

This provides runtime evidence that the current instrumented service fleet is consistently using the pinned Java-agent version rather than relying only on image-build assumptions.

## Trace-context behavior

The platform uses OpenTelemetry `traceId`, `spanId`, and parent relationships as the authoritative distributed-tracing context.

Validation includes:

- HTTP service-to-service trace propagation;
- Kafka producer/consumer trace propagation;
- the same traceId across asynchronous message boundaries;
- a new spanId for each producer/consumer operation;
- parentSpanId relationships connecting downstream consumer spans back to the producing span where expected.

Application/business identifiers such as phone or account values are lookup/correlation keys only. They never replace or synthesize a real OpenTelemetry traceId.

## Log collection and normalization

Fluent Bit collects Kubernetes stdout logs and Data Prepper performs processing before OpenSearch indexing. The validated UAT2 processing includes known-format trace/span extraction, field normalization, ANSI escape removal, and additive business-correlation fields where the source log actually contains the value.

Services without OpenTelemetry trace context remain searchable in Logs but cannot be represented as part of a distributed trace until real trace context exists.

## Collector security and metadata

The Collector should use a dedicated ServiceAccount and read-only Kubernetes permissions required for metadata enrichment. Production promotion must retain least privilege and add the final NetworkPolicy/firewall and authenticated transport controls.

Expected enriched identity includes namespace, pod, workload, node, container, and image attributes when available from the Kubernetes metadata processor.

## Deployment order

1. Install the pinned OpenTelemetry Operator release.
2. Configure the approved Collector endpoints, cluster identity, resources, and security settings.
3. Validate the Collector configuration against image `otel/opentelemetry-collector-k8s:0.158.0` before rollout.
4. Deploy the Collector and verify readiness.
5. Deploy Fluent Bit 5.1.1 and verify log ingestion.
6. Deploy/verify kube-state-metrics v2.18.0 for Kubernetes state metrics.
7. Select exactly one Java-agent instrumentation mode per workload.
8. Validate one service end-to-end before enabling additional applications.
9. Confirm trace, log, metric, and resource/capacity behavior before wider rollout.

## Validation evidence

The current UAT2 implementation has demonstrated:

- Collector 0.158.0 running in the monitoring namespace;
- Operator 0.157.0 running in the monitoring namespace;
- Java agent 2.30.0 confirmed from running application logs;
- Kubernetes metadata present in trace resource attributes;
- distributed context propagation through HTTP and Kafka operations;
- centralized logs through Fluent Bit 5.1.1;
- Data Prepper 2.16.0 normalization and trace/log ingestion;
- OpenSearch 3.6.0 trace/log storage and Dashboards investigation;
- broad log searching separated from strict real-trace correlation.

No internal addresses, hostnames, credentials, customer identifiers, or real transaction/trace values are retained in this public evidence.

## Rollback

If a Collector rollout fails, restore the previous validated configuration/image, restart or roll back the Deployment, and verify application OTLP connectivity and Collector health before continuing.

If Operator injection causes an application failure, remove the injection annotation from the affected workload and roll back that application Deployment. Do not remove the cluster-wide Operator merely to recover one workload.

If a Fluent Bit update disrupts logging, restore the previous DaemonSet/configuration and verify fresh log arrival before resuming rollout.

## Production scale boundary

This UAT validation proves the functional onboarding and correlation model, not final production capacity. Production still requires RBAC/access-control completion, alerting and runbooks, resource/capacity tuning, TLS/authentication, credential management, NetworkPolicies/firewalls, backup/recovery testing, and representative load/soak/failure testing.
