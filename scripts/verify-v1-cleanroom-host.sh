#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_HOST="${EXPECTED_HOST:-}"
EXPECTED_UBUNTU_VERSION="${EXPECTED_UBUNTU_VERSION:-24.04}"

ok()   { printf '[OK] %s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; failures=$((failures + 1)); }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Run as root."
[[ -n "$EXPECTED_HOST" ]] || die "EXPECTED_HOST is required."
[[ "$(hostname -s)" == "$EXPECTED_HOST" ]] || die "Expected host '$EXPECTED_HOST', found '$(hostname -s)'."
[[ -r /etc/os-release ]] || die "/etc/os-release is not readable."

# shellcheck disable=SC1091
source /etc/os-release

failures=0

echo "=== V1 CLEAN-ROOM HOST PREFLIGHT ==="
echo "Host: $(hostname -s)"
echo "OS: ${PRETTY_NAME:-unknown}"
echo "Architecture: $(uname -m)"
echo "Kernel: $(uname -r)"
echo

info "Checking formal v1 operating-system target"
if [[ "${ID:-}" == "ubuntu" ]]; then
  ok "Ubuntu detected"
else
  fail "expected Ubuntu, found ID=${ID:-unknown}"
fi

if [[ "${VERSION_ID:-}" == "$EXPECTED_UBUNTU_VERSION" ]]; then
  ok "Ubuntu VERSION_ID=$EXPECTED_UBUNTU_VERSION"
else
  fail "expected Ubuntu VERSION_ID=$EXPECTED_UBUNTU_VERSION, found ${VERSION_ID:-unknown}"
fi

if [[ "$(uname -m)" == "x86_64" ]]; then
  ok "x86_64 architecture"
else
  fail "expected x86_64 architecture, found $(uname -m)"
fi

echo
info "Host capacity (reported, not release-blocking)"
printf 'CPU threads: %s\n' "$(nproc)"
free -h
df -h /

echo
info "Checking required base utilities"
for cmd in bash curl tar jq systemctl ss openssl python3; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd available"
  else
    fail "$cmd missing"
  fi
done

echo
info "Running clean-lab state verification"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if EXPECTED_HOST="$EXPECTED_HOST" bash "$SCRIPT_DIR/verify-clean-lab.sh"; then
  ok "Clean-lab state verification passed"
else
  fail "Clean-lab state verification failed"
fi

echo
if (( failures == 0 )); then
  ok "Ubuntu 24.04 v1 clean-room preflight passed"
  exit 0
fi

printf '[FAIL] v1 clean-room preflight failed with %d issue(s).\n' "$failures" >&2
exit 1
