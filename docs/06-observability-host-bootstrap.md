# Dedicated Observability Host Bootstrap

## Purpose

This stage prepares the separate machine that receives telemetry from the RKE2 Collector and runs OpenSearch, OpenSearch Dashboards, Data Prepper, and Prometheus. It records a repeatable baseline without publishing environment secrets.

This document covers a functional single-host installation. It does not convert a single host into a highly available production platform.

## 1. Frozen versions

Use `versions.env` as the source of truth. The current dedicated-host baseline is synchronized to the operated UAT reference environment: OpenSearch/Dashboards 3.6.0, Data Prepper 2.16.0, Prometheus 3.14.0, Alertmanager 0.31.1, node_exporter 1.12.1, and process-exporter 0.8.7. These exact versions remain pinned until a later upgrade is separately qualified.

Do not substitute floating tags, unverified archives, or a newer version during an installation window.

## 2. Required private inputs

Prepare these outside Git:

- host and service DNS names;
- organization-issued TLS certificates and private keys;
- OpenSearch administrator and least-privilege ingest credentials;
- private artifact mirror URLs and SHA-256 checksums;
- retention and storage limits approved from measured ingestion;
- snapshot repository details;
- firewall source networks;
- Prometheus and Dashboards access-control configuration.

## 3. Host gate

Complete `docs/03-infrastructure-prerequisites.md` first. Stop if time synchronization, storage, DNS, memory, or recovery prerequisites fail.

Apply the OpenSearch kernel requirement:

```bash
sudo install -m 0644 /dev/stdin /etc/sysctl.d/99-opensearch.conf <<'EOF'
vm.max_map_count=262144
EOF

sudo sysctl --system
test "$(sysctl -n vm.max_map_count)" -ge 262144
```

Disable swap according to the approved operating-system standard and verify `swapon --show` is empty before starting OpenSearch.

## 4. Service identities and storage

The clean-room bootstrap creates the service identities observed on the reference host:

- OpenSearch and OpenSearch Dashboards: `opensearch:opensearch`;
- Data Prepper: `dataprepper:dataprepper`;
- Prometheus: `prometheus:prometheus`;
- Alertmanager: `alertmanager:alertmanager`;
- node_exporter: `node_exporter:node_exporter`;
- process-exporter: `root:root` on the currently operated reference.

Persistent reference paths include `/data/opensearch`, `/data/logs/opensearch`,
`/data/prometheus`, and `/data/alertmanager`. The binary bootstrap creates
these paths and verifies the ownership contract before the configuration gate.

Mount and verify the approved data volumes before installing binaries. Never use NFS for OpenSearch or Prometheus active storage.

## 5. Artifact installation

Download artifacts only from the approved mirror or official release location. Verify every checksum before extraction.

Install versioned directories beneath `/opt` and keep configuration in `/etc`:

```text
/opt/opensearch
/opt/opensearch-dashboards
/opt/data-prepper
/opt/prometheus
/opt/alertmanager
```

The current UAT reference uses stable canonical `/opt/<component>` paths. Exact artifact versions are pinned in `versions.env`, verified before activation, and changed only through the documented lab -> UAT -> production lifecycle.

## 6. OpenSearch

Render `observability-host/opensearch/opensearch.yml.example` into the package configuration directory. Render `heap.options.example` into `jvm.options.d/heap.options`.

For a single functional host, `discovery.type: single-node` is valid. It must be removed and replaced with an approved multi-node discovery configuration for production HA.

Requirements:

- equal `Xms` and `Xmx`; the captured reference uses 2 GiB;
- `bootstrap.memory_lock: false` for reference parity;
- node and HTTP certificates supplied by a private PKI;
- no demo certificates or default credentials;
- a dedicated Data Prepper ingest role instead of administrator access;
- index lifecycle/retention policies and snapshot repository configured before full ingestion.

## 7. Data Prepper

Render the templates in `observability-host/data-prepper/` into `/etc/data-prepper`. Replace every `{{ ... }}` token from a private rendering process.

The captured reference topology is:

```text
OTLP traces -> 21890 -> raw spans + v2 service map -> OpenSearch
HTTP logs   -> 2021  -> normalized daily log indices -> OpenSearch
service-map metric events -> Prometheus remote write -> :9090/api/v1/write
Data Prepper core API -> 4900
```

The reference enables Data Prepper's experimental Prometheus sink and uses it
for service-derived metrics. The public repository keeps credentials and CA
material as private render inputs.

## 8. OpenSearch Dashboards

Render `observability-host/dashboards/opensearch_dashboards.yml.example` into the package configuration directory. Supply a dedicated Dashboards service account, not the OpenSearch administrator account.

For strict reference parity, Dashboards listens on port 5601 without browser-side
TLS and validates the OpenSearch CA with `verificationMode: full`. Workspaces,
data sources, Explore traces/metrics, dataset management, and saved-object
permissions are enabled; Security multitenancy is disabled. Production
hardening may place Dashboards behind an approved TLS reverse proxy without
changing the OpenSearch-side trust contract.

## 9. Prometheus

Render the Prometheus configuration from the sanitized target inventory and install
the qualified alert rules under `/etc/prometheus/rules`. Validate them before reload:

```bash
/opt/prometheus/promtool check config /etc/prometheus/prometheus.yml
/opt/prometheus/promtool check rules /etc/prometheus/rules/*.yml
```

The captured reference listens on `0.0.0.0:9090`, evaluates and scrapes every
30 seconds, stores TSDB blocks in `/data/prometheus`, retains 5 days / 3 GB,
and enables the remote-write receiver. Network controls must restrict access
to approved sources.

## 10. Service installation order

After rendering and validating all private configuration:

1. OpenSearch;
2. Prometheus;
3. Alertmanager;
4. Data Prepper;
5. OpenSearch Dashboards;
6. process-exporter;
7. node_exporter;
8. RKE2/cluster scrape targets;
9. application onboarding.

Install the provided systemd units only after confirming their binary paths and versions:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now opensearch
sudo systemctl enable --now opensearch-dashboards
sudo systemctl enable --now data-prepper
sudo systemctl enable --now prometheus
sudo systemctl enable --now alertmanager
sudo systemctl enable --now process-exporter
sudo systemctl enable --now node_exporter
```

## 11. Network policy

Permit only the flows documented in `docs/03-infrastructure-prerequisites.md`. In particular:

- telemetry sources may reach Data Prepper 21890 for traces and 2021 for HTTP logs;
- Data Prepper and Dashboards may reach OpenSearch 9200;
- OpenSearch 9300 is only for OpenSearch nodes;
- administrative APIs and Dashboards are reachable only from approved management networks;
- no ingest or database port is internet-facing.

## 12. Validation

Validate services before sending workload traffic:

```bash
systemctl --failed
systemctl is-active opensearch opensearch-dashboards data-prepper prometheus alertmanager process-exporter node_exporter
ss -lntp
curl --fail --cacert <ca-file> -u <read-only-user> https://<opensearch-fqdn>:9200/_cluster/health
curl --fail http://127.0.0.1:9090/-/ready
journalctl -u opensearch -u data-prepper -u prometheus --since '10 minutes ago' --no-pager
```

Then send one uniquely identifiable test transaction and prove:

- the complete parent/child trace is indexed;
- the expected correlated logs share its trace ID;
- the v2 service map contains the dependency relationship;
- request, error, fault, and latency metrics exist;
- Kubernetes resource attributes are present;
- no duplicate stdout/OTLP application logs are indexed.

## 13. Rollback

Before every change, back up configuration and record the active binary version. If validation fails:

1. stop new application onboarding;
2. restore the prior configuration files;
3. point systemd back to the prior immutable binary directory;
4. reload systemd and restart only the affected service;
5. confirm ingestion, query, and dashboard health;
6. preserve failed logs and configuration diffs for the change record.

Never delete OpenSearch data, Prometheus blocks, or snapshots as part of an application rollback.

## 14. Production promotion gates

Production approval requires all of the following:

- representative UAT load and soak results for 100–150 workloads;
- tested TLS and credential rotation;
- tested snapshots and restore;
- documented retention, shard sizing, watermarks, and capacity alerts;
- Collector and ingestion backpressure tests;
- defined alert routing, escalation, and ownership;
- a multi-node OpenSearch design or explicit acceptance of the single-host failure domain;
- signed implementation, validation, and rollback evidence.


## 15. Non-mutating render gate

Before PKI/security initialization or service activation, render the private
configuration into a staging directory:

```bash
bash scripts/render-reference-config.sh --plan
bash scripts/render-reference-config.sh --render /path/to/private.env /path/to/private-targets.json /root/observability-rendered
```

The render command never writes to live `/etc` or `/opt` configuration
locations and never starts or reloads a service. It validates the rendered
reference semantics and, when the pinned binaries are present, also runs
`promtool` and `amtool` against the staged configuration.
