#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:---plan}"
EXPECTED_HOST="${EXPECTED_HOST:-}"
WORKSPACE_ID="${WORKSPACE_ID:-}"
APPLICATION_NAMESPACES="${APPLICATION_NAMESPACES:-}"
PLATFORM_NAMESPACES="${PLATFORM_NAMESPACES:-}"

OPENSEARCH_URL="${OPENSEARCH_URL:-https://127.0.0.1:9200}"
DASHBOARDS_URL="${DASHBOARDS_URL:-http://127.0.0.1:5601}"
OPENSEARCH_USERNAME="${OPENSEARCH_USERNAME:-admin}"

LOG_INDEX_PATTERN="${LOG_INDEX_PATTERN:-logs-v2-*}"
SOURCE_DATASET_TITLE="${SOURCE_DATASET_TITLE:-logs-v2-*}"
SOURCE_DATASET_ID="${SOURCE_DATASET_ID:-}"
APPLICATION_ALIAS="${APPLICATION_ALIAS:-logs-application}"
PLATFORM_ALIAS="${PLATFORM_ALIAS:-logs-platform}"
APPLICATION_DATASET_ID="${APPLICATION_DATASET_ID:-std-logs-application-dataset}"
PLATFORM_DATASET_ID="${PLATFORM_DATASET_ID:-std-logs-platform-dataset}"
DEFAULT_LOG_DATASET_ID="${DEFAULT_LOG_DATASET_ID:-$APPLICATION_DATASET_ID}"
ALIAS_TEMPLATE_NAME="${ALIAS_TEMPLATE_NAME:-observability-log-aliases-v1}"
TIME_FIELD="${TIME_FIELD:-time}"

ok()   { printf '[OK] %s\n' "$*"; }
info() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die()  { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ "$MODE" == "--plan" || "$MODE" == "--apply" ]] || die "Usage: $0 [--plan|--apply]"
[[ "${EUID}" -eq 0 ]] || die "Run as root."
[[ -n "$EXPECTED_HOST" ]] || die "EXPECTED_HOST is required."
[[ "$(hostname -s)" == "$EXPECTED_HOST" ]] || die "Expected host '$EXPECTED_HOST', found '$(hostname -s)'."
[[ -n "$WORKSPACE_ID" ]] || die "WORKSPACE_ID is required."
[[ -n "$APPLICATION_NAMESPACES" ]] || die "APPLICATION_NAMESPACES is required (comma-separated)."
[[ -n "$PLATFORM_NAMESPACES" ]] || die "PLATFORM_NAMESPACES is required (comma-separated)."

for cmd in curl jq python3; do
  command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: $cmd"
done

if [[ -z "${OBSERVABILITY_ADMIN_PASSWORD:-}" ]]; then
  read -rsp 'OpenSearch/Dashboards admin password: ' OBSERVABILITY_ADMIN_PASSWORD
  echo
fi
PASS="$OBSERVABILITY_ADMIN_PASSWORD"

os_curl() {
  curl -skS -u "$OPENSEARCH_USERNAME:$PASS" "$@"
}

dash_curl() {
  curl -sS -u "$OPENSEARCH_USERNAME:$PASS" -H 'osd-xsrf: true' "$@"
}

csv_to_json() {
  jq -Rn --arg csv "$1" '$csv | split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length>0))'
}

APP_JSON="$(csv_to_json "$APPLICATION_NAMESPACES")"
PLATFORM_JSON="$(csv_to_json "$PLATFORM_NAMESPACES")"
[[ "$(jq 'length' <<<"$APP_JSON")" -gt 0 ]] || die "No application namespaces parsed."
[[ "$(jq 'length' <<<"$PLATFORM_JSON")" -gt 0 ]] || die "No platform namespaces parsed."

APP_FILTER="$(jq -cn --argjson ns "$APP_JSON" '{terms:{"kubernetes.namespace_name.keyword":$ns}}')"
PLATFORM_FILTER="$(jq -cn --argjson ns "$PLATFORM_JSON" '{
  bool:{
    filter:[{terms:{"kubernetes.namespace_name.keyword":$ns}}],
    must_not:[{
      bool:{
        filter:[
          {term:{serviceName:"fluent-bit"}},
          {bool:{should:[
            {wildcard:{"message.keyword":"*HTTP status=200*"}},
            {term:{"message.keyword":"200 OK"}}
          ],minimum_should_match:1}}
        ]
      }
    }]
  }
}')"

probe_index="logs-v2-2099.12.31"
INDEX_TEMPLATES="$(os_curl "$OPENSEARCH_URL/_index_template")"
matching_composable=()
while IFS=$'\t' read -r name pattern; do
  [[ -n "$name" && -n "$pattern" ]] || continue
  if [[ "$probe_index" == $pattern ]]; then
    matching_composable+=("$name")
  fi
done < <(jq -r '.index_templates[]? as $t | $t.index_template.index_patterns[]? | [$t.name,.] | @tsv' <<<"$INDEX_TEMPLATES")

DATASETS="$(dash_curl "$DASHBOARDS_URL/w/$WORKSPACE_ID/api/saved_objects/_find?type=index-pattern&per_page=10000")"

# Prefer an explicitly supplied source, then the already-standardized Application Logs
# dataset, and only then the legacy/raw logs-v2-* dataset. This makes the raw saved
# dataset removable after the initial bootstrap while keeping the script reusable.
if [[ -n "$SOURCE_DATASET_ID" ]]; then
  SOURCE_ID="$(jq -r --arg id "$SOURCE_DATASET_ID" '
    [.saved_objects[] | select(.id==$id and (.attributes.signalType=="logs" or .attributes.signalType==null))][0].id // empty
  ' <<<"$DATASETS")"
  [[ -n "$SOURCE_ID" ]] || die "SOURCE_DATASET_ID '$SOURCE_DATASET_ID' was not found as a compatible Logs dataset."
else
  SOURCE_ID="$(jq -r --arg id "$APPLICATION_DATASET_ID" '
    [.saved_objects[] | select(.id==$id and (.attributes.signalType=="logs" or .attributes.signalType==null))][0].id // empty
  ' <<<"$DATASETS")"

  if [[ -z "$SOURCE_ID" ]]; then
    SOURCE_ID="$(jq -r --arg t "$SOURCE_DATASET_TITLE" '
      [.saved_objects[] | select(.attributes.title==$t and (.attributes.signalType=="logs" or .attributes.signalType==null))]
      | (map(select(.attributes.signalType=="logs")) + map(select(.attributes.signalType==null)))[0].id // empty
    ' <<<"$DATASETS")"
  fi
fi

[[ -n "$SOURCE_ID" ]] || die "Could not find a source Logs dataset. Set SOURCE_DATASET_ID explicitly or retain a '$SOURCE_DATASET_TITLE' bootstrap dataset."

SOURCE_OBJECT="$(dash_curl "$DASHBOARDS_URL/w/$WORKSPACE_ID/api/saved_objects/index-pattern/$SOURCE_ID")"
SOURCE_DISPLAY="$(jq -r '.attributes.displayName // .attributes.title' <<<"$SOURCE_OBJECT")"

CURRENT_INDICES="$(os_curl "$OPENSEARCH_URL/_cat/indices/$LOG_INDEX_PATTERN?format=json&h=index,status")"
INDEX_COUNT="$(jq 'length' <<<"$CURRENT_INDICES")"
[[ "$INDEX_COUNT" -gt 0 ]] || die "No current indexes match $LOG_INDEX_PATTERN."

echo "===== EXPLORE LOG DATASET STANDARDIZATION ====="
echo "Host:                 $(hostname -s)"
echo "Workspace:            $WORKSPACE_ID"
echo "Source dataset:       $SOURCE_DISPLAY ($SOURCE_ID)"
echo "Backing pattern:      $LOG_INDEX_PATTERN"
echo "Current indexes:      $INDEX_COUNT"
echo "Application alias:    $APPLICATION_ALIAS"
echo "Platform alias:       $PLATFORM_ALIAS"
echo "Application dataset:  Application Logs ($APPLICATION_DATASET_ID)"
echo "Platform dataset:     Kubernetes Platform Logs ($PLATFORM_DATASET_ID)"
echo "Default Logs dataset: $DEFAULT_LOG_DATASET_ID"
echo "Composable templates matching future $LOG_INDEX_PATTERN: ${#matching_composable[@]}"
if (("${#matching_composable[@]}" > 0)); then
  printf '  - %s\n' "${matching_composable[@]}"
fi
echo
echo "Application namespaces:"
jq -r '.[] | "  - " + .' <<<"$APP_JSON"
echo "Platform namespaces:"
jq -r '.[] | "  - " + .' <<<"$PLATFORM_JSON"
echo
echo "The existing raw dataset is retained. Routine Fluent Bit HTTP 200 chatter is"
echo "excluded only from the platform alias/dataset, not deleted from OpenSearch."

if [[ "$MODE" == "--plan" ]]; then
  if (("${#matching_composable[@]}" == 0)); then
    ok "Plan is safe for alias-only legacy template persistence."
  elif (("${#matching_composable[@]}" == 1)); then
    ok "Plan is safe: apply will patch composable template '${matching_composable[0]}' in place, preserving its existing settings/mappings and adding only the two filtered aliases."
  else
    warn "Multiple composable templates match future log indexes. Apply will stop because the active winner is ambiguous: ${matching_composable[*]}"
  fi
  exit 0
fi

if (("${#matching_composable[@]}" > 1)); then
  die "Refusing apply: multiple matching composable templates detected: ${matching_composable[*]}. Resolve template precedence first."
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/root/explore-log-datasets-before-$STAMP"
mkdir -p "$BACKUP"
printf '%s\n' "$INDEX_TEMPLATES" > "$BACKUP/index-templates.json"
os_curl "$OPENSEARCH_URL/_template" > "$BACKUP/legacy-templates.json"
os_curl "$OPENSEARCH_URL/_alias/$APPLICATION_ALIAS,$PLATFORM_ALIAS" > "$BACKUP/aliases.json" 2>/dev/null || true
printf '%s\n' "$SOURCE_OBJECT" > "$BACKUP/source-dataset.json"
dash_curl "$DASHBOARDS_URL/w/$WORKSPACE_ID/api/saved_objects/index-pattern/$APPLICATION_DATASET_ID" > "$BACKUP/application-dataset.json" 2>/dev/null || true
dash_curl "$DASHBOARDS_URL/w/$WORKSPACE_ID/api/saved_objects/index-pattern/$PLATFORM_DATASET_ID" > "$BACKUP/platform-dataset.json" 2>/dev/null || true
dash_curl "$DASHBOARDS_URL/w/$WORKSPACE_ID/api/opensearch-dashboards/settings" > "$BACKUP/workspace-ui-settings.json" 2>/dev/null || true
ok "Backup created: $BACKUP"

if (("${#matching_composable[@]}" == 1)); then
  ACTIVE_TEMPLATE="${matching_composable[0]}"
  ACTIVE_TEMPLATE_OBJECT="$(os_curl "$OPENSEARCH_URL/_index_template/$ACTIVE_TEMPLATE")"
  printf '%s\n' "$ACTIVE_TEMPLATE_OBJECT" > "$BACKUP/composable-template-$ACTIVE_TEMPLATE.json"

  [[ "$(jq -r '.index_templates | length' <<<"$ACTIVE_TEMPLATE_OBJECT")" -eq 1 ]] || die "Could not read composable template '$ACTIVE_TEMPLATE'."
  [[ "$(jq -r '.index_templates[0].index_template | has("data_stream")' <<<"$ACTIVE_TEMPLATE_OBJECT")" == "false" ]] || die "Template '$ACTIVE_TEMPLATE' is a data-stream template; refusing in-place alias patch."

  ACTIVE_TEMPLATE_BODY="$(jq -c     --arg app "$APPLICATION_ALIAS"     --arg platform "$PLATFORM_ALIAS"     --argjson af "$APP_FILTER"     --argjson pf "$PLATFORM_FILTER"     '.index_templates[0].index_template
     | .template = (.template // {})
     | .template.aliases = ((.template.aliases // {}) + {
         ($app):{filter:$af},
         ($platform):{filter:$pf}
       })' <<<"$ACTIVE_TEMPLATE_OBJECT")"

  ACK="$(os_curl -H 'Content-Type: application/json' -X PUT     "$OPENSEARCH_URL/_index_template/$ACTIVE_TEMPLATE"     --data-binary "$ACTIVE_TEMPLATE_BODY")"
  [[ "$(jq -r '.acknowledged // false' <<<"$ACK")" == "true" ]] || die "OpenSearch did not acknowledge composable template update: $ACK"

  VERIFY_TEMPLATE="$(os_curl "$OPENSEARCH_URL/_index_template/$ACTIVE_TEMPLATE")"
  [[ "$(jq -r --arg a "$APPLICATION_ALIAS" '.index_templates[0].index_template.template.aliases | has($a)' <<<"$VERIFY_TEMPLATE")" == "true" ]] || die "Application alias missing from patched template."
  [[ "$(jq -r --arg a "$PLATFORM_ALIAS" '.index_templates[0].index_template.template.aliases | has($a)' <<<"$VERIFY_TEMPLATE")" == "true" ]] || die "Platform alias missing from patched template."
  ok "Future-index aliases added to composable template: $ACTIVE_TEMPLATE"
else
  TEMPLATE_BODY="$(jq -cn     --arg p "$LOG_INDEX_PATTERN"     --arg app "$APPLICATION_ALIAS"     --arg platform "$PLATFORM_ALIAS"     --argjson af "$APP_FILTER"     --argjson pf "$PLATFORM_FILTER"     '{index_patterns:[$p],order:1000,aliases:{($app):{filter:$af},($platform):{filter:$pf}}}')"

  ACK="$(os_curl -H 'Content-Type: application/json' -X PUT     "$OPENSEARCH_URL/_template/$ALIAS_TEMPLATE_NAME"     --data-binary "$TEMPLATE_BODY")"
  [[ "$(jq -r '.acknowledged // false' <<<"$ACK")" == "true" ]] || die "OpenSearch did not acknowledge legacy alias template update: $ACK"
  ok "Future-index alias-only legacy template installed"
fi

ALIASES_BODY="$(jq -cn   --arg idx "$LOG_INDEX_PATTERN"   --arg app "$APPLICATION_ALIAS"   --arg platform "$PLATFORM_ALIAS"   --argjson af "$APP_FILTER"   --argjson pf "$PLATFORM_FILTER"   '{actions:[
    {add:{index:$idx,alias:$app,filter:$af}},
    {add:{index:$idx,alias:$platform,filter:$pf}}
  ]}')"

os_curl -H 'Content-Type: application/json' -X POST   "$OPENSEARCH_URL/_aliases"   --data-binary "$ALIASES_BODY" >/dev/null
ok "Filtered aliases attached to current log indexes"

make_dataset_body() {
  local alias="$1" display="$2" description="$3"
  jq -c     --arg title "$alias"     --arg display "$display"     --arg desc "$description"     --arg time "$TIME_FIELD"     '{
      attributes:(.attributes
        | .title=$title
        | .displayName=$display
        | .description=$desc
        | .timeFieldName=$time
        | .signalType="logs"),
      references:(.references // [])
    }' <<<"$SOURCE_OBJECT"
}

upsert_dataset() {
  local id="$1" body="$2"
  local code
  code="$(dash_curl -o /dev/null -w '%{http_code}'     "$DASHBOARDS_URL/w/$WORKSPACE_ID/api/saved_objects/index-pattern/$id")"
  if [[ "$code" == "200" ]]; then
    dash_curl -H 'Content-Type: application/json' -X PUT       "$DASHBOARDS_URL/w/$WORKSPACE_ID/api/saved_objects/index-pattern/$id"       --data-binary "$body" >/dev/null
  elif [[ "$code" == "404" ]]; then
    dash_curl -H 'Content-Type: application/json' -X POST       "$DASHBOARDS_URL/w/$WORKSPACE_ID/api/saved_objects/index-pattern/$id"       --data-binary "$body" >/dev/null
  else
    die "Unexpected HTTP $code while checking dataset $id"
  fi
}

APP_DATASET_BODY="$(make_dataset_body "$APPLICATION_ALIAS" "Application Logs" "Application and deployment workload logs only.")"
PLATFORM_DATASET_BODY="$(make_dataset_body "$PLATFORM_ALIAS" "Kubernetes Platform Logs" "RKE2, Kubernetes, Rancher, Longhorn and observability platform logs; routine Fluent Bit success chatter hidden.")"

upsert_dataset "$APPLICATION_DATASET_ID" "$APP_DATASET_BODY"
upsert_dataset "$PLATFORM_DATASET_ID" "$PLATFORM_DATASET_BODY"
ok "Explore Logs datasets created/updated"

case "$DEFAULT_LOG_DATASET_ID" in
  "$APPLICATION_DATASET_ID"|"$PLATFORM_DATASET_ID"|"$SOURCE_ID") ;;
  *) die "DEFAULT_LOG_DATASET_ID '$DEFAULT_LOG_DATASET_ID' is not one of the managed Logs dataset IDs." ;;
esac

DEFAULT_RESPONSE="$(dash_curl -H 'Content-Type: application/json' -X POST   "$DASHBOARDS_URL/w/$WORKSPACE_ID/api/opensearch-dashboards/settings/defaultIndex"   --data-binary "$(jq -cn --arg value "$DEFAULT_LOG_DATASET_ID" '{value:$value}')")"
[[ "$(jq -r '.settings.defaultIndex.userValue // empty' <<<"$DEFAULT_RESPONSE")" == "$DEFAULT_LOG_DATASET_ID" ]] ||   die "Failed to set workspace default dataset to '$DEFAULT_LOG_DATASET_ID': $DEFAULT_RESPONSE"
ok "Workspace default dataset set to: $DEFAULT_LOG_DATASET_ID"

APP_COUNT="$(os_curl "$OPENSEARCH_URL/$APPLICATION_ALIAS/_count" | jq -r '.count')"
PLATFORM_COUNT="$(os_curl "$OPENSEARCH_URL/$PLATFORM_ALIAS/_count" | jq -r '.count')"
[[ "$APP_COUNT" -gt 0 ]] || die "Application alias returned zero documents."
[[ "$PLATFORM_COUNT" -gt 0 ]] || die "Platform alias returned zero documents."

BAD_APP="$(os_curl -H 'Content-Type: application/json' -X POST "$OPENSEARCH_URL/$APPLICATION_ALIAS/_search"   --data-binary '{"size":0,"aggs":{"namespaces":{"terms":{"field":"kubernetes.namespace_name.keyword","size":100}}}}'   | jq -r --argjson allowed "$APP_JSON" '.aggregations.namespaces.buckets[].key | select(($allowed|index(.))==null)' || true)"
[[ -z "$BAD_APP" ]] || die "Unexpected namespace(s) in Application Logs alias: $BAD_APP"

BAD_PLATFORM="$(os_curl -H 'Content-Type: application/json' -X POST "$OPENSEARCH_URL/$PLATFORM_ALIAS/_search"   --data-binary '{"size":0,"aggs":{"namespaces":{"terms":{"field":"kubernetes.namespace_name.keyword","size":100}}}}'   | jq -r --argjson allowed "$PLATFORM_JSON" '.aggregations.namespaces.buckets[].key | select(($allowed|index(.))==null)' || true)"
[[ -z "$BAD_PLATFORM" ]] || die "Unexpected namespace(s) in Platform Logs alias: $BAD_PLATFORM"

FLUENT_NOISE="$(os_curl -H 'Content-Type: application/json' -X POST "$OPENSEARCH_URL/$PLATFORM_ALIAS/_count"   --data-binary '{"query":{"bool":{"filter":[{"term":{"serviceName":"fluent-bit"}},{"bool":{"should":[{"wildcard":{"message.keyword":"*HTTP status=200*"}},{"term":{"message.keyword":"200 OK"}}],"minimum_should_match":1}}]}}}'   | jq -r '.count')"
[[ "$FLUENT_NOISE" -eq 0 ]] || die "Platform alias still exposes $FLUENT_NOISE routine Fluent Bit success records."

for id in "$APPLICATION_DATASET_ID" "$PLATFORM_DATASET_ID"; do
  obj="$(dash_curl "$DASHBOARDS_URL/w/$WORKSPACE_ID/api/saved_objects/index-pattern/$id")"
  [[ "$(jq -r '.attributes.signalType' <<<"$obj")" == "logs" ]] || die "$id is not a Logs dataset."
done

ok "Application Logs documents: $APP_COUNT"
ok "Kubernetes Platform Logs documents: $PLATFORM_COUNT"
ok "Routine Fluent Bit success chatter hidden from platform dataset"
ok "Default Logs dataset: $DEFAULT_LOG_DATASET_ID"
ok "Explore Logs dataset standardization complete"
echo "Backup: $BACKUP"
echo "Refresh Discover > Logs in the browser and open the dataset selector."
