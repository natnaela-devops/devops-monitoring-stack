#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_HOST="${EXPECTED_HOST:-vm-3}"
MODE="${1:-}"

info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root."
[[ "$(hostname -s)" == "$EXPECTED_HOST" ]] || die "Refusing destructive reset: expected host '$EXPECTED_HOST', found '$(hostname -s)'."

if [[ "$MODE" != "--apply" ]]; then
  cat <<EOF
This script removes the observability stack from $EXPECTED_HOST so the host can be
requalified from a clean state.

It removes:
  - OpenSearch and OpenSearch Dashboards packages/files
  - Prometheus
  - Alertmanager
  - Data Prepper
  - node_exporter from this lab host
  - process-exporter
  - observability-specific systemd units and state
  - local qualification/render/backup files

It does NOT remove:
  - SSH
  - host networking
  - Docker itself
  - unrelated user files
  - node_exporter on any other machine

Run explicitly with:
  $0 --apply
EOF
  exit 0
fi

info "Stopping observability services"
services=(
  opensearch
  opensearch-dashboards
  prometheus
  alertmanager
  data-prepper
  node-exporter
  prometheus-node-exporter
  process-exporter
  otelcol
  otelcol-contrib
  opensearch-exporter
)

for service in "${services[@]}"; do
  systemctl disable --now "$service" >/dev/null 2>&1 || true
done

info "Removing custom systemd units and overrides"
rm -f   /etc/systemd/system/opensearch.service   /etc/systemd/system/opensearch-dashboards.service   /etc/systemd/system/prometheus.service   /etc/systemd/system/alertmanager.service   /etc/systemd/system/data-prepper.service   /etc/systemd/system/node-exporter.service   /etc/systemd/system/process-exporter.service   /etc/systemd/system/otelcol.service   /etc/systemd/system/otelcol-contrib.service   /etc/systemd/system/opensearch-exporter.service

rm -rf   /etc/systemd/system/opensearch.service.d   /etc/systemd/system/opensearch-dashboards.service.d

systemctl daemon-reload

info "Unholding and purging packaged OpenSearch components when present"
apt-mark unhold opensearch opensearch-dashboards >/dev/null 2>&1 || true

export DEBIAN_FRONTEND=noninteractive
packages=()
for package in opensearch opensearch-dashboards prometheus prometheus-alertmanager prometheus-node-exporter; do
  if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
    packages+=("$package")
  fi
done

if (( ${#packages[@]} > 0 )); then
  apt-get purge -y "${packages[@]}"
  apt-get autoremove -y
fi

info "Removing OpenSearch repository metadata"
rm -f   /etc/apt/sources.list.d/opensearch*.list   /etc/apt/keyrings/opensearch*.gpg

info "Removing observability binaries, configuration, logs, and state"
rm -rf   /etc/opensearch   /usr/share/opensearch   /var/lib/opensearch   /var/log/opensearch   /opt/opensearch   /etc/opensearch-dashboards   /usr/share/opensearch-dashboards   /var/lib/opensearch-dashboards   /var/log/opensearch-dashboards   /opt/opensearch-dashboards   /opt/prometheus   /etc/prometheus   /var/lib/prometheus   /data/prometheus   /opt/alertmanager   /etc/alertmanager   /var/lib/alertmanager   /data/alertmanager   /opt/data-prepper   /etc/data-prepper   /var/lib/data-prepper   /var/log/data-prepper   /opt/node_exporter   /opt/node-exporter   /opt/process-exporter   /etc/process-exporter   /opt/otelcol   /opt/otelcol-contrib   /etc/otelcol   /etc/otelcol-contrib   /opt/opensearch-exporter   /etc/opensearch-exporter

rm -f   /usr/local/bin/node_exporter   /usr/local/bin/process-exporter   /usr/local/bin/otelcol   /usr/local/bin/otelcol-contrib

info "Removing local qualification state"
rm -rf   /root/opensearch-observability-standard-v1   /root/opensearch-observability-backups   /root/vm3-observability-rendered   /tmp/observability-install-*

rm -f   /root/vm3-observability-parameters.env   /root/vm3-observability-install.env   /root/vm3-prometheus-targets.json   /root/.opensearch-dashboards-admin-password   /home/vm3/opensearch-observability-standard-v1-lab.tar.gz   /etc/sysctl.d/99-opensearch.conf

systemctl daemon-reload
systemctl reset-failed

ok "Observability lab reset completed"

echo
echo "Verification:"
echo "  systemctl --failed"
echo "  ss -lntp | grep -E ':(5601|9090|9093|9100|9115|9200|9256|9600|21890|21891)\\b' || true"
echo "  dpkg-query -W opensearch opensearch-dashboards 2>/dev/null || true"
