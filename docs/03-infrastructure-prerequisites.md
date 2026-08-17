# Infrastructure Prerequisites and Preflight Checks

**Purpose:** Validate infrastructure, capacity, networking, security, and recovery readiness before installing or changing observability components.  
**Rule:** A failed mandatory check blocks the deployment until it is resolved and recorded.

## 1. Scope and deployment gates

This checklist applies to:

- the RKE2 server and worker nodes;
- the OpenTelemetry Operator and Collector;
- the dedicated observability platform running OpenSearch, OpenSearch Dashboards, Data Prepper, and Prometheus;
- lab, UAT, and production environments.

The preflight is read-only unless a command is explicitly identified as a remediation command in a later installation document.

## 2. Capacity planning baseline

The following values are **starting planning floors**, not guaranteed production sizing. Final sizing depends on requests per second, spans per transaction, log volume, metric cardinality, retention, sampling, and replication.

| Environment/component | Starting CPU | Starting memory | Starting usable storage | Notes |
|---|---:|---:|---:|---|
| Functional lab RKE2 | 4 vCPU | 8–16 GiB | 100 GiB | Combined server/worker; validates function, not HA or scale |
| Functional lab observability host | 8 vCPU | 16 GiB preferred | 200 GiB SSD | An 8 GiB host can demonstrate the stack but has little safety margin |
| UAT RKE2 node | 8–16 vCPU | 32–64 GiB | 300–500 GiB SSD | Combined roles are acceptable where UAT policy permits |
| Production RKE2 server | 8 vCPU | 16–32 GiB | 200 GiB enterprise SSD | Three dedicated server/etcd nodes; no general workloads |
| Production RKE2 worker | 16 vCPU | 64 GiB | 500 GiB+ SSD | Minimum three workers; capacity must exceed total pod requests plus failure headroom |
| UAT observability host | 12–16 vCPU | 64 GiB | 1 TiB NVMe/SSD | Representative ingestion and retention testing |
| Production single observability host | 24 vCPU | 128 GiB | 2 TiB+ NVMe/SSD | Constrained single-host starting point; not HA |
| Production HA OpenSearch data node | 16 vCPU | 64 GiB | 1–2 TiB NVMe/SSD each | Three or more eligible nodes preferred; size from measured ingestion |

Maintain at least:

- 30% CPU and memory headroom during expected peak load;
- 30% free disk before enabling production ingestion;
- enough worker capacity to lose one worker without evicting critical workloads;
- enough observability storage for retention plus segment merges, watermarks, and recovery operations.

## 3. Storage layout principles

Binaries may be installed beneath `/opt`, while mutable state belongs on dedicated data paths.

| Path | Purpose | Requirement |
|---|---|---|
| `/opt` | Versioned application binaries | Root-owned; application users read/execute only |
| `/var/lib/rancher/rke2` | RKE2 and containerd state | Fast local SSD; monitored capacity |
| `/var/lib/opensearch` | OpenSearch indices | Dedicated fast volume preferred |
| `/var/lib/prometheus` | Prometheus TSDB | Local SSD/NVMe; not a shared NFS filesystem |
| `/var/lib/data-prepper` | Data Prepper state and service-map database | Persistent local storage |
| `/var/log` | System and service logs | Rotation and retention configured |
| External snapshot repository | OpenSearch backups | Must not share the OpenSearch host failure domain |

Production acceptance requires documented volume sizes, filesystem type, mount options, ownership, backup target, and disk alerts.

## 4. Operating-system prerequisites

Apply the organization-approved Ubuntu LTS hardening baseline before application installation.

Mandatory checks on every Linux host:

```bash
hostnamectl
timedatectl
timedatectl show -p NTPSynchronized --value

uname -r
lscpu
free -h
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
df -hT
df -ih

swapon --show
systemctl --failed
```

Required conditions:

- unique and stable hostname;
- unique node identity and network address;
- synchronized time;
- supported kernel and container runtime;
- no failed critical systemd units;
- adequate file descriptors and process limits;
- predictable DNS resolution;
- approved package repositories or an internal artifact mirror;
- swap disabled for OpenSearch and aligned with the Kubernetes/RKE2 operating standard.

OpenSearch hosts require:

```bash
sysctl vm.max_map_count
cat /proc/sys/vm/max_map_count
```

The value must be at least:

```text
vm.max_map_count = 262144
```

OpenSearch production hosts must also disable paging/swapping and set JVM heap explicitly. A common starting point is approximately half of available service memory, while preserving substantial memory for the operating-system page cache. Heap selection must be validated against the deployed OpenSearch version and workload.

## 5. DNS and time prerequisites

All nodes and services require consistent forward and reverse resolution where organizational DNS supports it.

Validate:

```bash
getent hosts <rke2-api-fqdn>
getent hosts <observability-fqdn>
resolvectl status 2>/dev/null || cat /etc/resolv.conf
timedatectl status
```

Required DNS names should include:

- RKE2 API/load-balancer name;
- RKE2 registration endpoint;
- OpenSearch Dashboards name;
- Data Prepper ingest name;
- Prometheus remote-write name;
- OpenSearch internal endpoint names;
- snapshot repository endpoint where applicable.

Certificates must contain the DNS names used by clients. IP-only certificates are not accepted for the final production design.

## 6. RKE2 internal network requirements

Restrict these ports to trusted cluster networks. VXLAN ports must never be exposed publicly.

| Port | Protocol | Source | Destination | Purpose |
|---:|---|---|---|---|
| 6443 | TCP | RKE2 nodes and approved administrators | RKE2 server/load balancer | Kubernetes API |
| 9345 | TCP | RKE2 nodes | RKE2 server/load balancer | RKE2 supervisor and registration |
| 10250 | TCP | RKE2 nodes and approved monitoring | All RKE2 nodes | Kubelet API/metrics |
| 2379 | TCP | RKE2 server nodes | RKE2 server nodes | etcd client |
| 2380 | TCP | RKE2 server nodes | RKE2 server nodes | etcd peer |
| 2381 | TCP | RKE2 server nodes | RKE2 server nodes | etcd metrics |
| 8472 | UDP | RKE2 nodes | RKE2 nodes | Canal VXLAN |
| 9099 | TCP | RKE2 nodes | RKE2 nodes | Canal health |
| 30000–32767 | TCP | Approved clients only | RKE2 nodes | NodePort range, only when required |

Also permit controlled access to internal DNS, NTP, image registries, package repositories, backup systems, and certificate services.

Reference: [RKE2 requirements and inbound network rules](https://docs.rke2.io/install/requirements).

## 7. Observability network requirements

Use DNS names in production configuration. Replace lab plaintext connections with TLS and authentication.

| Port | Protocol | Source | Destination | Purpose |
|---:|---|---|---|---|
| 4317 | TCP | Instrumented application pods | Collector Service | OTLP gRPC |
| 4318 | TCP | Instrumented application pods | Collector Service | OTLP HTTP |
| 21890 | TCP | Collector worker nodes | Data Prepper | Trace ingest |
| 21891 | TCP | Collector worker nodes | Data Prepper | Log ingest |
| 9090 | TCP/HTTPS target | Collector worker nodes and approved administrators | Prometheus/reverse proxy | Remote write and controlled API access |
| 9200 | TCP/HTTPS | Data Prepper, Dashboards, and approved administrators | OpenSearch | REST API |
| 9300 | TCP | OpenSearch nodes only | OpenSearch nodes | Cluster transport when multi-node |
| 9600 | TCP | Approved monitoring only | OpenSearch nodes | Performance Analyzer |
| 5601 | TCP/HTTPS via proxy | Approved users | Dashboards | User interface |

Production rules:

- applications communicate only with the in-cluster Collector Service;
- only Collector nodes communicate with off-cluster ingestion endpoints;
- OpenSearch and Prometheus APIs are not publicly exposed;
- administrative UI access uses HTTPS, identity controls, and audit logging;
- firewall rules use the narrowest practical source and destination sets.

## 8. RKE2 cluster preflight

Run from an administrative workstation with the correct kubeconfig:

```bash
echo '=== Context ==='
kubectl config current-context

echo '=== Nodes ==='
kubectl get nodes -o wide
kubectl get nodes   -o custom-columns='NAME:.metadata.name,ROLES:.metadata.labels,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory,PODS:.status.capacity.pods'

echo '=== Node conditions and taints ==='
kubectl describe nodes |
sed -n '/^Name:/p;/^Taints:/p;/^Conditions:/,/^Addresses:/p'

echo '=== Cluster workloads ==='
kubectl get pods -A -o wide
kubectl get deployments,statefulsets,daemonsets -A

echo '=== API health ==='
kubectl get --raw='/readyz?verbose'

echo '=== Resource usage ==='
kubectl top nodes 2>/dev/null || true
kubectl top pods -A --containers 2>/dev/null || true

echo '=== Events ==='
kubectl get events -A   --sort-by='.metadata.creationTimestamp' |
tail -100

echo '=== Helm ==='
helm version
helm list -A
```

Mandatory pass conditions:

- every intended node is `Ready`;
- server/worker roles and taints match the approved topology;
- API readiness checks pass;
- no unresolved crash loops, scheduling failures, CNI failures, or certificate errors;
- Canal is fully ready;
- sufficient allocatable CPU, memory, ephemeral storage, and pod capacity remain;
- metrics are available or an alternative capacity measurement is documented;
- RKE2 has remained stable during the observation window.

## 9. OpenTelemetry preflight

Before installing the Operator:

```bash
echo '=== Existing OpenTelemetry resources ==='
kubectl get crd |
grep -E 'opentelemetry|instrumentation' || true

kubectl get deployments,daemonsets,services,configmaps   -A |
grep -Ei 'otel|opentelemetry|fluent-bit' || true

echo '=== Existing instrumentation ==='
kubectl get deployments -A -o yaml |
grep -nE 'javaagent|instrumentation.opentelemetry.io|OTEL_' || true

echo '=== Operator releases ==='
helm list -A |
grep -i opentelemetry || true
```

Resolve these decisions before installation:

- use cert-manager or the chart's generated self-signed webhook certificate;
- choose the pinned Operator/chart version from `versions.env`;
- define Operator resource requests and limits;
- define worker-node scheduling and topology policy;
- identify every workload already containing an embedded agent;
- choose namespace opt-in policy;
- prepare Collector ServiceAccount and least-privilege RBAC;
- confirm the Collector distribution contains every configured component.

The official Helm chart can generate a self-signed webhook certificate when cert-manager is not available. Production must use an organization-approved certificate lifecycle.

References:

- [OpenTelemetry Operator Helm chart](https://opentelemetry.io/docs/platforms/kubernetes/helm/operator/)
- [OpenTelemetry automatic instrumentation](https://opentelemetry.io/docs/platforms/kubernetes/operator/automatic/)

## 10. Dedicated observability-host preflight

Run on the observability host without printing credentials:

```bash
echo '=== Host capacity ==='
hostnamectl
uptime
free -h
df -hT
df -ih
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS

echo '=== Kernel settings ==='
sysctl vm.max_map_count
swapon --show

echo '=== Service state ==='
systemctl is-active   opensearch   opensearch-dashboards   data-prepper   prometheus

echo '=== Failed services ==='
systemctl --failed

echo '=== Listening ports ==='
ss -lntp |
grep -E ':(5601|9090|9200|9300|9600|21890|21891)\b' || true

echo '=== Prometheus configuration ==='
/opt/prometheus-3.10.0/promtool   check config /etc/prometheus/prometheus.yml

echo '=== Data Prepper recent errors ==='
journalctl -u data-prepper   --since '30 minutes ago'   --no-pager |
grep -Ei 'error|failed|exception|rejected' |
tail -100 || true
```

Health checks must use the secured local endpoints and must not echo passwords, tokens, certificate private keys, or complete environment files.

OpenSearch host requirements reference: [OpenSearch installation settings](https://docs.opensearch.org/latest/install-and-configure/install-opensearch/index/).

## 11. Security prerequisites

The following must exist before production telemetry is enabled:

- organization-approved server certificates;
- trusted CA distribution to Collectors and platform services;
- separate identities for ingestion, dashboards, administration, snapshots, and monitoring;
- least-privilege OpenSearch roles and index permissions;
- Kubernetes Secrets or a secrets manager for credentials;
- NetworkPolicies around Collector ingestion;
- host firewall rules;
- audit logging;
- credential rotation process;
- secret-scanning in CI;
- sanitized example configuration committed to Git.

Default passwords, plaintext credentials, disabled certificate verification, and `tls.insecure: true` are lab-only conditions and must be removed before production acceptance.

## 12. Backup and recovery prerequisites

Before changing stateful or cluster-level components:

### RKE2

- create and list a fresh etcd snapshot;
- verify snapshot location and retention;
- document the restore command and required RKE2 version;
- store a protected copy outside the node failure domain.

### OpenSearch

- configure an off-host snapshot repository;
- create a test snapshot;
- restore a non-production test index;
- record recovery time and snapshot status.

### Prometheus

- preserve configuration and rule files in Git;
- document TSDB retention and storage size;
- use the supported snapshot/backup method;
- verify rules can be rebuilt from Git if metric history is lost.

### Data Prepper and Dashboards

- preserve sanitized configuration in Git;
- export required Dashboards saved objects;
- protect service-map state where operationally necessary;
- document which data is reproducible and which requires backup.

## 13. Evidence collection

Save sanitized evidence for each environment:

```text
evidence/
  lab/
    preflight/
  uat/
    preflight/
  production/
    preflight/
```

Evidence must include:

- execution date and operator;
- component versions;
- node and host capacity;
- service health;
- rule validation results;
- snapshot identifiers without credentials;
- pass/fail decision;
- approved exceptions;
- remediation owner and due date.

Do not commit raw kubeconfigs, Kubernetes Secrets, tokens, passwords, private keys, unredacted environment files, or customer data.

## 14. Final go/no-go checklist

Deployment may proceed only when all mandatory items are **PASS**:

| Check | Required result |
|---|---|
| Version baseline approved | PASS |
| Architecture approved | PASS |
| RKE2 nodes and API healthy | PASS |
| CNI healthy | PASS |
| Capacity headroom available | PASS |
| DNS and NTP validated | PASS |
| Required ports tested | PASS |
| TLS and identities prepared | PASS for production |
| Existing agents inventoried | PASS |
| Double-instrumentation risk resolved | PASS |
| Collector RBAC reviewed | PASS |
| OpenSearch host settings validated | PASS |
| Backup and restore evidence available | PASS |
| Rollback owner and procedure assigned | PASS |
| Secrets excluded from Git | PASS |

Any failed production security, recovery, or capacity check is a deployment blocker.
