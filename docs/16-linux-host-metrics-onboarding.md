# Linux Host Metrics Onboarding

**Scope:** Monitored Linux hosts, including RKE2 nodes and the dedicated observability host  
**Exporter:** Prometheus node_exporter 1.12.1  
**Reference listen port:** 9115  
**Design goal:** Provide reusable host CPU, memory, filesystem, disk, network, load, and uptime telemetry without embedding customer-specific addresses in Git.

## Purpose

The observability platform uses node_exporter on Linux hosts that require host-level monitoring. In the validated UAT pattern, Prometheus scrapes node_exporter directly and attaches stable inventory labels such as node, IP, and role through the rendered target configuration.

This is separate from Kubernetes workload telemetry:

- OpenTelemetry Collector handles OTLP application telemetry and selected Kubernetes metrics.
- kube-state-metrics provides Kubernetes object state.
- cAdvisor/kubelet metrics provide container and pod resource usage.
- node_exporter provides Linux host and filesystem metrics.

## Installation contract

The reusable repository pins node_exporter in `versions.env`. Install the exact pinned release and the repository-provided systemd unit rather than relying on a distribution package with an uncontrolled version.

Expected binary path:

```text
/usr/local/bin/node_exporter
```

Expected service identity:

```text
user:  node_exporter
group: node_exporter
```

Expected listener:

```text
0.0.0.0:9115
```

The reference unit is:

```text
observability-host/systemd/node_exporter.service
```

## Generic host installation

Run the equivalent procedure on each approved Linux host. Keep environment-specific addresses outside Git.

```bash
set -Eeuo pipefail

VERSION="1.12.1"
ARCH="linux-amd64"
TMP="$(mktemp -d)"

getent group node_exporter >/dev/null 2>&1 || groupadd --system node_exporter
id node_exporter >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin --gid node_exporter node_exporter

curl -fL   "https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/node_exporter-${VERSION}.${ARCH}.tar.gz"   -o "$TMP/node_exporter.tar.gz"

tar -xzf "$TMP/node_exporter.tar.gz" -C "$TMP"

install -o root -g root -m 0755   "$TMP/node_exporter-${VERSION}.${ARCH}/node_exporter"   /usr/local/bin/node_exporter

install -o root -g root -m 0644   observability-host/systemd/node_exporter.service   /etc/systemd/system/node_exporter.service

systemctl daemon-reload
systemctl enable --now node_exporter

/usr/local/bin/node_exporter --version
systemctl is-active node_exporter
ss -ltnp | grep ':9115'
curl -fsS http://127.0.0.1:9115/metrics >/dev/null

rm -rf "$TMP"
```

For production use, download verification must use the repository's pinned checksum workflow or an equivalently controlled artifact-verification process.

## Prometheus target inventory

Do not commit real host addresses. Put monitored hosts in the private target inventory consumed by `scripts/render-reference-config.sh`.

Sanitized example:

```json
{
  "node_exporter": [
    {
      "target": "192.0.2.10:9115",
      "node": "rke2-node-01",
      "ip": "192.0.2.10",
      "role": "rke2"
    },
    {
      "target": "192.0.2.20:9115",
      "node": "observability-node-01",
      "ip": "192.0.2.20",
      "role": "observability"
    }
  ]
}
```

The renderer converts this inventory into the `node-exporter` Prometheus scrape job. The committed example inventory remains non-sensitive; customized target files stay outside Git.

## Validation

A host is considered onboarded only when all of the following pass:

```bash
systemctl is-enabled node_exporter
systemctl is-active node_exporter
/usr/local/bin/node_exporter --version
curl -fsS http://127.0.0.1:9115/metrics >/dev/null
```

From Prometheus, validate that the target is UP and that core metrics are present:

```promql
up{job="node-exporter"}
```

```promql
node_cpu_seconds_total{job="node-exporter"}
```

```promql
node_memory_MemAvailable_bytes{job="node-exporter"}
```

```promql
node_filesystem_avail_bytes{job="node-exporter"}
```

The Infrastructure Health dashboard and node resource alerts consume these metrics.

## Firewall and exposure

Port 9115 should be reachable only from the Prometheus/observability network path required for scraping. Do not expose node_exporter to untrusted networks.

## Change safety and rollback

Before replacing an existing node_exporter binary or unit:

1. capture the current binary version;
2. back up the current systemd unit;
3. preserve the private Prometheus target inventory;
4. validate the replacement binary and unit;
5. restart or reload only after validation;
6. confirm the Prometheus target returns to UP.

If the replacement fails, restore the previous binary/unit from the timestamped backup, reload systemd, restart node_exporter, and verify the target again.

No production hostnames, addresses, credentials, certificates, or tokens belong in this repository.
