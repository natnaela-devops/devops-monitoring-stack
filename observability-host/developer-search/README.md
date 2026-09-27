# Runtime-standardized settings for the custom Developer Observability Search.
# These are supplied by /etc/observability-search/observability-search.env.
#
# Expected application-side variables:
#   OBSERVABILITY_ENVIRONMENT
#   OBSERVABILITY_ENV_LABEL
#   DASHBOARDS_BASE
#   OPENSEARCH_URL
#   OPENSEARCH_USERNAME
#   OPENSEARCH_CA
#
# The OpenSearch password remains a systemd credential named:
#   opensearch-password
