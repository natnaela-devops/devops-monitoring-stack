#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="${1:---plan}"

info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK] %s\n' "$*"; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

case "$MODE" in
  --plan|--apply) ;;
  *) die "Usage: $0 [--plan|--apply]" ;;
esac

# shellcheck disable=SC1091
source "$REPO_ROOT/versions.env"
# shellcheck disable=SC1091
source "$REPO_ROOT/observability-host/artifacts.lock.env"

: "${NODE_EXPORTER_VERSION:?missing NODE_EXPORTER_VERSION}"
: "${NODE_EXPORTER_SHA256:?missing NODE_EXPORTER_SHA256}"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCHIVE_ARCH="linux-amd64" ;;
  *) die "unsupported architecture: $ARCH" ;;
esac

ARCHIVE="node_exporter-${NODE_EXPORTER_VERSION}.${ARCHIVE_ARCH}.tar.gz"
URL="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${ARCHIVE}"
UNIT_SRC="$REPO_ROOT/observability-host/systemd/node_exporter.service"

[[ -f "$UNIT_SRC" ]] || die "missing repository unit: $UNIT_SRC"

cat <<PLAN
===== NODE EXPORTER HOST ONBOARDING =====
Version:      $NODE_EXPORTER_VERSION
Architecture: $ARCHIVE_ARCH
Binary:       /usr/local/bin/node_exporter
Unit:         /etc/systemd/system/node_exporter.service
Listener:     0.0.0.0:9115
Mode:         $MODE

This script does not modify Prometheus target inventory.
Keep real host addresses in the private target file used by the renderer.
========================================
PLAN

[[ "$MODE" == "--plan" ]] && exit 0
[[ "$EUID" -eq 0 ]] || die "--apply must run as root"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/root/node-exporter-before-$STAMP"
WORK="$(mktemp -d /tmp/node-exporter-install.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$BACKUP"
chmod 700 "$BACKUP"

if [[ -f /usr/local/bin/node_exporter ]]; then
  cp -a /usr/local/bin/node_exporter "$BACKUP/node_exporter"
fi

if [[ -f /etc/systemd/system/node_exporter.service ]]; then
  cp -a /etc/systemd/system/node_exporter.service "$BACKUP/node_exporter.service"
fi

systemctl is-enabled node_exporter >"$BACKUP/enabled-state.txt" 2>&1 || true
systemctl is-active node_exporter >"$BACKUP/active-state.txt" 2>&1 || true

info "Downloading pinned node_exporter artifact"
curl -fL "$URL" -o "$WORK/$ARCHIVE"

printf '%s  %s\n' "$NODE_EXPORTER_SHA256" "$WORK/$ARCHIVE" | sha256sum -c -

getent group node_exporter >/dev/null 2>&1 || groupadd --system node_exporter
id node_exporter >/dev/null 2>&1 ||   useradd --system --no-create-home --shell /usr/sbin/nologin --gid node_exporter node_exporter

mkdir -p "$WORK/extract"
tar -xzf "$WORK/$ARCHIVE" -C "$WORK/extract"

NODE_BIN="$(find "$WORK/extract" -type f -name node_exporter -perm -u+x | head -1)"
[[ -n "$NODE_BIN" ]] || die "node_exporter binary not found after extraction"

install -o root -g root -m 0755 "$NODE_BIN" /usr/local/bin/node_exporter
install -o root -g root -m 0644 "$UNIT_SRC" /etc/systemd/system/node_exporter.service

/usr/local/bin/node_exporter --version 2>&1 | head -1 |   grep -q "version $NODE_EXPORTER_VERSION" || die "installed version mismatch"

systemd-analyze verify /etc/systemd/system/node_exporter.service
systemctl daemon-reload
systemctl enable --now node_exporter

systemctl is-active --quiet node_exporter || die "node_exporter is not active"
curl -fsS http://127.0.0.1:9115/metrics >/dev/null || die "local metrics endpoint failed"

cat > "$BACKUP/rollback.sh" <<ROLLBACK
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -f "$BACKUP/node_exporter" ]]; then
  install -o root -g root -m 0755 "$BACKUP/node_exporter" /usr/local/bin/node_exporter
fi

if [[ -f "$BACKUP/node_exporter.service" ]]; then
  install -o root -g root -m 0644 "$BACKUP/node_exporter.service" /etc/systemd/system/node_exporter.service
fi

systemctl daemon-reload

if [[ -f "$BACKUP/active-state.txt" ]] && grep -qx active "$BACKUP/active-state.txt"; then
  systemctl restart node_exporter
else
  systemctl stop node_exporter || true
fi

if [[ -f "$BACKUP/enabled-state.txt" ]] && grep -qx enabled "$BACKUP/enabled-state.txt"; then
  systemctl enable node_exporter
else
  systemctl disable node_exporter || true
fi

echo "Restored node_exporter state from $BACKUP"
ROLLBACK

chmod 700 "$BACKUP/rollback.sh"

ok "node_exporter $NODE_EXPORTER_VERSION installed and active"
ok "metrics endpoint: http://127.0.0.1:9115/metrics"
ok "backup: $BACKUP"
ok "rollback: $BACKUP/rollback.sh"
