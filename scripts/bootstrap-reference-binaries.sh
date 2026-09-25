#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSIONS_FILE="$REPO_ROOT/versions.env"
LOCK_FILE="$REPO_ROOT/observability-host/artifacts.lock.env"
MODE="${1:-}"

info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ -f "$VERSIONS_FILE" ]] || die "versions.env not found: $VERSIONS_FILE"
[[ -f "$LOCK_FILE" ]] || die "artifact lock file not found: $LOCK_FILE"

set -a
source "$VERSIONS_FILE"
source "$LOCK_FILE"
set +a

required_vars=(
  OPENSEARCH_VERSION
  OPENSEARCH_DASHBOARDS_VERSION
  DATA_PREPPER_VERSION
  PROMETHEUS_VERSION
  ALERTMANAGER_VERSION
  NODE_EXPORTER_VERSION
  PROCESS_EXPORTER_VERSION
  PROMETHEUS_SHA256
  ALERTMANAGER_SHA256
  NODE_EXPORTER_SHA256
  DATA_PREPPER_SHA256
)
for var in "${required_vars[@]}"; do
  [[ -n "${!var:-}" ]] || die "required variable is empty: $var"
done

[[ "$OPENSEARCH_VERSION" == "$OPENSEARCH_DASHBOARDS_VERSION" ]] \
  || die "OpenSearch and Dashboards versions must match"

case "$MODE" in
  --plan|--apply) ;;
  *) die "Usage: $0 --plan|--apply" ;;
esac

ARCH="$(uname -m)"
[[ "$ARCH" == "x86_64" ]] || die "reference bootstrap currently supports x86_64 only; found $ARCH"

OS_ID="$(. /etc/os-release && printf '%s' "$ID")"
OS_VERSION="$(. /etc/os-release && printf '%s' "$VERSION_ID")"
[[ "$OS_ID" == "ubuntu" ]] || die "reference bootstrap currently supports Ubuntu only; found $OS_ID"

OS_ARCHIVE="opensearch-${OPENSEARCH_VERSION}-linux-x64.tar.gz"
OS_URL="https://artifacts.opensearch.org/releases/bundle/opensearch/${OPENSEARCH_VERSION}/${OS_ARCHIVE}"
OS_SIG_URL="${OS_URL}.sig"

OSD_ARCHIVE="opensearch-dashboards-${OPENSEARCH_DASHBOARDS_VERSION}-linux-x64.tar.gz"
OSD_URL="https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/${OPENSEARCH_DASHBOARDS_VERSION}/${OSD_ARCHIVE}"
OSD_SIG_URL="${OSD_URL}.sig"

DP_ARCHIVE="opensearch-data-prepper-jdk-${DATA_PREPPER_VERSION}-linux-x64.tar.gz"
DP_URL="https://artifacts.opensearch.org/data-prepper/${DATA_PREPPER_VERSION}/${DP_ARCHIVE}"

PROM_ARCHIVE="prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${PROM_ARCHIVE}"

AM_ARCHIVE="alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz"
AM_URL="https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/${AM_ARCHIVE}"

NODE_ARCHIVE="node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
NODE_URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${NODE_ARCHIVE}"

PROC_ARCHIVE="process-exporter-${PROCESS_EXPORTER_VERSION}.linux-amd64.tar.gz"
PROC_URL="https://github.com/ncabatoff/process-exporter/releases/download/v${PROCESS_EXPORTER_VERSION}/${PROC_ARCHIVE}"
PROC_CHECKSUMS_URL="https://github.com/ncabatoff/process-exporter/releases/download/v${PROCESS_EXPORTER_VERSION}/checksums.txt"

cat <<PLAN
===== REFERENCE OBSERVABILITY BINARY BOOTSTRAP =====
Host:                       $(hostname -s)
OS:                         ${OS_ID} ${OS_VERSION}
Architecture:               ${ARCH}
OpenSearch:                 ${OPENSEARCH_VERSION}
OpenSearch Dashboards:      ${OPENSEARCH_DASHBOARDS_VERSION}
Data Prepper:               ${DATA_PREPPER_VERSION}
Prometheus:                 ${PROMETHEUS_VERSION}
Alertmanager:               ${ALERTMANAGER_VERSION}
node_exporter:               ${NODE_EXPORTER_VERSION}
process-exporter:            ${PROCESS_EXPORTER_VERSION}

Canonical paths:
  /opt/opensearch
  /opt/opensearch-dashboards
  /opt/data-prepper
  /opt/prometheus
  /opt/alertmanager
  /usr/local/bin/node_exporter
  /usr/local/bin/process-exporter

This stage installs exact binaries and systemd unit files only.
It does NOT start OpenSearch, Dashboards, Data Prepper, Prometheus,
Alertmanager, or exporters. Configuration/activation is a separate gate.
==================================================
PLAN

[[ "$MODE" == "--plan" ]] && exit 0
[[ "$EUID" -eq 0 ]] || die "--apply must run as root"

info "Installing explicit prerequisite packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl tar gzip jq gnupg openjdk-17-jre-headless

for cmd in curl tar sha256sum gpg awk grep find systemctl; do
  command -v "$cmd" >/dev/null 2>&1 || die "required command missing after prerequisite installation: $cmd"
done

ensure_user() {
  local user="$1" home="$2"
  if id "$user" >/dev/null 2>&1; then
    ok "user exists: $user"
  else
    useradd --system --home-dir "$home" --shell /usr/sbin/nologin "$user"
    ok "created user: $user"
  fi
}

ensure_user opensearch /var/lib/opensearch
ensure_user dataprepper /var/lib/data-prepper
ensure_user prometheus /var/lib/prometheus
ensure_user alertmanager /var/lib/alertmanager
ensure_user node_exporter /var/lib/node_exporter

install -d -o opensearch -g opensearch -m 0750 /var/lib/opensearch /var/log/opensearch
install -d -o opensearch -g opensearch -m 0750 /data/opensearch /data/logs/opensearch
install -d -o dataprepper -g dataprepper -m 0750 /var/lib/data-prepper /var/log/data-prepper
install -d -o prometheus -g prometheus -m 0750 /data/prometheus
install -d -o alertmanager -g alertmanager -m 0750 /data/alertmanager
install -d -o root -g root -m 0755 /etc/prometheus/rules /etc/alertmanager/templates /etc/process-exporter

cat > /etc/sysctl.d/99-opensearch.conf <<'SYSCTL'
vm.max_map_count=262144
SYSCTL
sysctl -q -w vm.max_map_count=262144 >/dev/null
[[ "$(sysctl -n vm.max_map_count)" -ge 262144 ]] || die "vm.max_map_count did not apply"
ok "vm.max_map_count configured"

WORK="$(mktemp -d /tmp/reference-observability-bootstrap.XXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

fetch() {
  local url="$1" dest="$2"
  info "Downloading $(basename "$dest")"
  curl --fail --location --silent --show-error --retry 3 --retry-delay 2 "$url" -o "$dest"
  [[ -s "$dest" ]] || die "download is empty: $url"
}

verify_sha256() {
  local file="$1" expected="$2"
  local actual
  actual="$(sha256sum "$file" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || die "SHA256 mismatch for $(basename "$file"): expected=$expected actual=$actual"
  ok "SHA256 verified: $(basename "$file")"
}

extract_to() {
  local archive="$1" dest="$2"
  local stage="$WORK/extract-$(basename "$dest")"
  rm -rf "$stage"
  mkdir -p "$stage"
  tar -xzf "$archive" -C "$stage"

  mapfile -t roots < <(find "$stage" -mindepth 1 -maxdepth 1 -print)
  [[ "${#roots[@]}" -gt 0 ]] || die "archive extracted no files: $archive"

  [[ ! -e "$dest" ]] || die "destination already exists: $dest"
  if [[ "${#roots[@]}" -eq 1 && -d "${roots[0]}" ]]; then
    mv "${roots[0]}" "$dest"
  else
    mkdir -p "$dest"
    cp -a "$stage/." "$dest/"
  fi
}

info "Preparing OpenSearch release-key verification"
fetch "https://artifacts.opensearch.org/publickeys/opensearch-release.pgp" "$WORK/opensearch-release.pgp"
GPG_HOME="$WORK/gnupg"
mkdir -m 0700 "$GPG_HOME"
gpg --batch --homedir "$GPG_HOME" --import "$WORK/opensearch-release.pgp" >/dev/null 2>&1

if [[ -e /opt/opensearch ]]; then
  [[ -x /opt/opensearch/bin/opensearch ]] || die "partial OpenSearch installation detected at /opt/opensearch"
  /opt/opensearch/bin/opensearch --version 2>&1 | grep -q "Version: ${OPENSEARCH_VERSION}" \
    || die "existing OpenSearch installation is not ${OPENSEARCH_VERSION}"
  ok "OpenSearch ${OPENSEARCH_VERSION} already installed; skipping artifact extraction"
else
  fetch "$OS_URL" "$WORK/$OS_ARCHIVE"
  fetch "$OS_SIG_URL" "$WORK/$OS_ARCHIVE.sig"
  gpg --batch --homedir "$GPG_HOME" --verify "$WORK/$OS_ARCHIVE.sig" "$WORK/$OS_ARCHIVE" >/dev/null 2>&1 \
    || die "OpenSearch signature verification failed"
  ok "OpenSearch signature verified"
  extract_to "$WORK/$OS_ARCHIVE" /opt/opensearch
  chown -R opensearch:opensearch /opt/opensearch
fi

if [[ -e /opt/opensearch-dashboards ]]; then
  [[ -f /opt/opensearch-dashboards/package.json ]] || die "partial Dashboards installation detected at /opt/opensearch-dashboards"
  [[ "$(jq -r '.version' /opt/opensearch-dashboards/package.json)" == "$OPENSEARCH_DASHBOARDS_VERSION" ]] \
    || die "existing Dashboards installation is not ${OPENSEARCH_DASHBOARDS_VERSION}"
  ok "OpenSearch Dashboards ${OPENSEARCH_DASHBOARDS_VERSION} already installed; skipping artifact extraction"
else
  fetch "$OSD_URL" "$WORK/$OSD_ARCHIVE"
  fetch "$OSD_SIG_URL" "$WORK/$OSD_ARCHIVE.sig"
  gpg --batch --homedir "$GPG_HOME" --verify "$WORK/$OSD_ARCHIVE.sig" "$WORK/$OSD_ARCHIVE" >/dev/null 2>&1 \
    || die "OpenSearch Dashboards signature verification failed"
  ok "OpenSearch Dashboards signature verified"
  extract_to "$WORK/$OSD_ARCHIVE" /opt/opensearch-dashboards
  chown -R opensearch:opensearch /opt/opensearch-dashboards
fi

DATA_PREPPER_OBSERVED_SHA256="$DATA_PREPPER_SHA256"
if [[ -e /opt/data-prepper ]]; then
  find /opt/data-prepper/lib -maxdepth 1 -type f -name "data-prepper-pipeline-parser-${DATA_PREPPER_VERSION}.jar" -print -quit | grep -q . \
    || die "existing Data Prepper installation is not ${DATA_PREPPER_VERSION}"
  ok "Data Prepper ${DATA_PREPPER_VERSION} already installed; skipping artifact extraction"
else
  fetch "$DP_URL" "$WORK/$DP_ARCHIVE"
  DATA_PREPPER_OBSERVED_SHA256="$(sha256sum "$WORK/$DP_ARCHIVE" | awk '{print $1}')"
  info "Data Prepper observed SHA256: $DATA_PREPPER_OBSERVED_SHA256"
  verify_sha256 "$WORK/$DP_ARCHIVE" "$DATA_PREPPER_SHA256"
  extract_to "$WORK/$DP_ARCHIVE" /opt/data-prepper
  chown -R dataprepper:dataprepper /opt/data-prepper
fi

if [[ -e /opt/prometheus ]]; then
  [[ -x /opt/prometheus/prometheus ]] || die "partial Prometheus installation detected at /opt/prometheus"
  /opt/prometheus/prometheus --version 2>&1 | head -1 | grep -q "version ${PROMETHEUS_VERSION}" \
    || die "existing Prometheus installation is not ${PROMETHEUS_VERSION}"
  ok "Prometheus ${PROMETHEUS_VERSION} already installed; skipping artifact extraction"
else
  fetch "$PROM_URL" "$WORK/$PROM_ARCHIVE"
  verify_sha256 "$WORK/$PROM_ARCHIVE" "$PROMETHEUS_SHA256"
  extract_to "$WORK/$PROM_ARCHIVE" /opt/prometheus
  chown -R prometheus:prometheus /opt/prometheus
fi

if [[ -e /opt/alertmanager ]]; then
  [[ -x /opt/alertmanager/alertmanager ]] || die "partial Alertmanager installation detected at /opt/alertmanager"
  /opt/alertmanager/alertmanager --version 2>&1 | head -1 | grep -q "version ${ALERTMANAGER_VERSION}" \
    || die "existing Alertmanager installation is not ${ALERTMANAGER_VERSION}"
  ok "Alertmanager ${ALERTMANAGER_VERSION} already installed; skipping artifact extraction"
else
  fetch "$AM_URL" "$WORK/$AM_ARCHIVE"
  verify_sha256 "$WORK/$AM_ARCHIVE" "$ALERTMANAGER_SHA256"
  extract_to "$WORK/$AM_ARCHIVE" /opt/alertmanager
  chown -R root:root /opt/alertmanager
fi

if [[ -x /usr/local/bin/node_exporter ]]; then
  /usr/local/bin/node_exporter --version 2>&1 | head -1 | grep -q "version ${NODE_EXPORTER_VERSION}" \
    || die "existing node_exporter installation is not ${NODE_EXPORTER_VERSION}"
  ok "node_exporter ${NODE_EXPORTER_VERSION} already installed; skipping artifact extraction"
else
  fetch "$NODE_URL" "$WORK/$NODE_ARCHIVE"
  verify_sha256 "$WORK/$NODE_ARCHIVE" "$NODE_EXPORTER_SHA256"
  mkdir -p "$WORK/node"
  tar -xzf "$WORK/$NODE_ARCHIVE" -C "$WORK/node"
  NODE_BIN="$(find "$WORK/node" -type f -name node_exporter -perm -u+x | head -1)"
  [[ -n "$NODE_BIN" ]] || die "node_exporter binary not found after extraction"
  install -o root -g root -m 0755 "$NODE_BIN" /usr/local/bin/node_exporter
fi

chown -R opensearch:opensearch /opt/opensearch
chown -R opensearch:opensearch /opt/opensearch-dashboards
chown -R dataprepper:dataprepper /opt/data-prepper
install -d -o dataprepper -g dataprepper -m 0750 /opt/data-prepper/data /opt/data-prepper/data/otel-apm-service-map
chown -R prometheus:prometheus /opt/prometheus
chown -R root:root /opt/alertmanager

if [[ -x /usr/local/bin/process-exporter ]]; then
  /usr/local/bin/process-exporter --version 2>&1 | head -1 | grep -q "version ${PROCESS_EXPORTER_VERSION}" \
    || die "existing process-exporter installation is not ${PROCESS_EXPORTER_VERSION}"
  ok "process-exporter ${PROCESS_EXPORTER_VERSION} already installed; skipping artifact extraction"
else
  fetch "$PROC_URL" "$WORK/$PROC_ARCHIVE"
  fetch "$PROC_CHECKSUMS_URL" "$WORK/process-exporter-checksums.txt"
  PROC_EXPECTED="$(awk -v name="$PROC_ARCHIVE" '$2 == name {print $1}' "$WORK/process-exporter-checksums.txt")"
  [[ -n "$PROC_EXPECTED" ]] || die "process-exporter checksum not found in upstream checksums.txt"
  verify_sha256 "$WORK/$PROC_ARCHIVE" "$PROC_EXPECTED"
  mkdir -p "$WORK/process"
  tar -xzf "$WORK/$PROC_ARCHIVE" -C "$WORK/process"
  PROC_BIN="$(find "$WORK/process" -type f -name process-exporter -perm -u+x | head -1)"
  [[ -n "$PROC_BIN" ]] || die "process-exporter binary not found after extraction"
  install -o root -g root -m 0755 "$PROC_BIN" /usr/local/bin/process-exporter
fi

info "Installing systemd unit definitions without starting services"
for unit in opensearch.service opensearch-dashboards.service data-prepper.service prometheus.service alertmanager.service node_exporter.service process-exporter.service; do
  src="$REPO_ROOT/observability-host/systemd/$unit"
  [[ -f "$src" ]] || die "missing unit in repository: $src"
  install -o root -g root -m 0644 "$src" "/etc/systemd/system/$unit"
done

install -d -o root -g root -m 0755 /etc/systemd/system/prometheus.service.d
install -o root -g root -m 0644   "$REPO_ROOT/observability-host/systemd/prometheus.service.d/apm-remote-write.conf"   /etc/systemd/system/prometheus.service.d/apm-remote-write.conf

systemctl daemon-reload

bash "$REPO_ROOT/scripts/verify-reference-binaries.sh"

ok "Reference binary bootstrap completed"
echo "DATA_PREPPER_OBSERVED_SHA256=$DATA_PREPPER_OBSERVED_SHA256"
echo "Next gate: render and activate configuration; services were intentionally not started."
