#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-}"
REFERENCE_HOST="${REFERENCE_HOST:-}"
ALLOW_INACTIVE_REFERENCE="${ALLOW_INACTIVE_REFERENCE:-0}"

info() { printf '\n=== %s ===\n' "$*"; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

case "$MODE" in
  --plan|--capture) ;;
  *) die "Usage: $0 --plan|--capture" ;;
esac

[[ "${EUID}" -eq 0 ]] || die "Run as root so protected configuration can be inspected safely."

if [[ "$MODE" == "--capture" ]]; then
  [[ -n "$REFERENCE_HOST" ]] || die "Set REFERENCE_HOST to the expected reference hostname before capture."
  [[ "$(hostname -s)" == "$REFERENCE_HOST" ]] || die "Refusing capture: expected reference host '$REFERENCE_HOST', found '$(hostname -s)'."

  if [[ "$ALLOW_INACTIVE_REFERENCE" != "1" ]]; then
    inactive=()
    for service in opensearch opensearch-dashboards data-prepper prometheus alertmanager process-exporter; do
      state="$(systemctl is-active "$service" 2>/dev/null || true)"
      [[ "$state" == "active" ]] || inactive+=("$service:$state")
    done
    if (( ${#inactive[@]} > 0 )); then
      die "Reference services are not all active: ${inactive[*]}. Set ALLOW_INACTIVE_REFERENCE=1 only for an intentional exceptional capture."
    fi
  fi
fi

redact_stream() {
  sed -E \
    -e 's#^([[:space:]]*[^#[:space:]]*password[^:]*:[[:space:]]*).*$#\1<redacted>#I' \
    -e 's#^([[:space:]]*[^#[:space:]]*passwd[^:]*:[[:space:]]*).*$#\1<redacted>#I' \
    -e 's#^([[:space:]]*[^#[:space:]]*token[^:]*:[[:space:]]*).*$#\1<redacted>#I' \
    -e 's#^([[:space:]]*[^#[:space:]]*secret[^:]*:[[:space:]]*).*$#\1<redacted>#I' \
    -e 's#^([[:space:]]*bot_token:[[:space:]]*).*$#\1<redacted>#I' \
    -e 's#^([[:space:]]*chat_id:[[:space:]]*).*$#\1<redacted>#I' \
    -e 's#^([[:space:]]*authorization:[[:space:]]*).*$#\1<redacted>#I'
}

show_file() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  printf '\n--- FILE: %s ---\n' "$path"
  redact_stream < "$path"
}

show_glob() {
  local pattern="$1"
  local found=0
  shopt -s nullglob
  local matches=( $pattern )
  shopt -u nullglob
  for path in "${matches[@]}"; do
    found=1
    show_file "$path"
  done
  return 0
}

if [[ "$MODE" == "--plan" ]]; then
  cat <<'PLAN'
REFERENCE RUNTIME CAPTURE PLAN

Read-only capture. No service is restarted, reloaded, enabled, disabled, or modified.

Capture safety gates:
  - REFERENCE_HOST must be set and must match the current short hostname
  - core reference services must be active by default
  - ALLOW_INACTIVE_REFERENCE=1 is an explicit exceptional override

The report includes:
  - exact installed component versions
  - systemd unit definitions and ExecStart lines
  - listening observability ports
  - OpenSearch runtime configuration and JVM options
  - OpenSearch Dashboards runtime configuration
  - Data Prepper configuration/pipeline candidates
  - Prometheus configuration
  - Alertmanager configuration
  - process-exporter configuration
  - OpenSearch security/certificate file inventory only (no key/cert contents)

Lines containing passwords, tokens, secrets, Telegram bot tokens/chat IDs, or
authorization values are redacted before printing.

The report may still contain environment names, hostnames, IP addresses,
certificate file paths, and distinguished names. Do not commit raw output to
the public repository.
PLAN
  exit 0
fi

info "HOST"
hostnamectl 2>/dev/null || hostname
printf 'Primary addresses: '
hostname -I 2>/dev/null || true

info "VERSIONS"
/opt/opensearch/bin/opensearch --version 2>&1 || true
if [[ -f /opt/opensearch-dashboards/package.json ]]; then
  printf 'OpenSearch Dashboards: '
  jq -r '.version' /opt/opensearch-dashboards/package.json
fi
if [[ -d /opt/data-prepper/lib ]]; then
  dp_marker="$(find /opt/data-prepper/lib -maxdepth 1 -type f -name 'data-prepper-pipeline-parser-*.jar' -printf '%f\n' 2>/dev/null | head -1 || true)"
  if [[ -n "$dp_marker" ]]; then
    printf 'Data Prepper marker: %s\n' "$dp_marker"
  else
    printf 'Data Prepper marker: not found\n'
  fi
fi
/opt/prometheus/prometheus --version 2>&1 | head -2 || true
/opt/alertmanager/alertmanager --version 2>&1 | head -2 || true
/usr/local/bin/node_exporter --version 2>&1 | head -2 || true
/usr/local/bin/process-exporter --version 2>&1 | head -2 || true

info "SYSTEMD SERVICE CONTRACT"
for service in opensearch opensearch-dashboards data-prepper prometheus alertmanager process-exporter; do
  printf '\n--- %s ---\n' "$service"
  systemctl show "$service" \
    -p LoadState -p ActiveState -p FragmentPath -p User -p Group -p WorkingDirectory -p ExecStart \
    --no-pager 2>/dev/null || true
  printf '%s\n' "--- unit file ---"
  systemctl cat "$service" --no-pager 2>/dev/null | redact_stream || true
done

info "LISTENING OBSERVABILITY PORTS"
ss -lntp 2>/dev/null | grep -E ':(4317|4318|4900|5601|9090|9093|9100|9115|9200|9256|9300|9600|21890|21891)\b' || true

info "OPENSearch CONFIGURATION"
show_file /opt/opensearch/config/opensearch.yml
show_file /opt/opensearch/config/jvm.options
show_glob '/opt/opensearch/config/jvm.options.d/*.options'

printf '\n--- OpenSearch config/security file inventory (contents not printed) ---\n'
find /opt/opensearch/config -maxdepth 3 -type f \
  -printf '%m %u:%g %p\n' 2>/dev/null | sort || true

info "OPENSearch DASHBOARDS CONFIGURATION"
show_file /opt/opensearch-dashboards/config/opensearch_dashboards.yml
show_file /etc/opensearch-dashboards/opensearch_dashboards.yml

info "DATA PREPPER CONFIGURATION"
show_file /opt/data-prepper/config/data-prepper-config.yaml
show_file /opt/data-prepper/config/pipelines.yaml
show_file /opt/data-prepper/pipelines/pipelines.yaml
show_file /etc/data-prepper/data-prepper-config.yaml
show_file /etc/data-prepper/pipelines.yaml
show_file /etc/data-prepper/pipelines/pipelines.yaml

printf '\n--- Data Prepper YAML inventory ---\n'
find /opt/data-prepper /etc/data-prepper -maxdepth 4 -type f \
  \( -name '*.yaml' -o -name '*.yml' \) -printf '%m %u:%g %p\n' 2>/dev/null | sort || true

info "PROMETHEUS CONFIGURATION"
show_file /etc/prometheus/prometheus.yml
printf '\n--- Prometheus rule inventory ---\n'
find /etc/prometheus/rules -maxdepth 2 -type f -printf '%m %u:%g %p\n' 2>/dev/null | sort || true

info "ALERTMANAGER CONFIGURATION"
show_file /etc/alertmanager/alertmanager.yml
printf '\n--- Alertmanager template inventory ---\n'
find /etc/alertmanager/templates -maxdepth 2 -type f -printf '%m %u:%g %p\n' 2>/dev/null | sort || true

info "PROCESS EXPORTER CONFIGURATION"
show_file /etc/process-exporter/process-exporter.yml
show_file /etc/process-exporter/process-exporter.yaml

info "STATE / OWNERSHIP CONTRACT"
for path in /opt/opensearch /opt/opensearch-dashboards /opt/data-prepper /opt/prometheus /opt/alertmanager /data/prometheus /data/alertmanager /var/lib/opensearch /var/log/opensearch /var/lib/data-prepper /var/log/data-prepper; do
  [[ -e "$path" ]] && stat -c '%A %U:%G %n' "$path"
done

printf '\n=== END REFERENCE RUNTIME CAPTURE ===\n'
