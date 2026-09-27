# Explore Logs dataset separation

OpenSearch Dashboards Explore Logs uses Logs datasets, not only classic saved
searches. This package keeps the existing raw `logs-v2-*` storage and exposes
two filtered OpenSearch aliases as real Logs datasets:

- **Application Logs** -> `logs-application`
- **Kubernetes Platform Logs** -> `logs-platform`

The application/platform namespace lists are runtime inputs and are not
committed to this public repository.

The platform alias suppresses routine Fluent Bit HTTP 200 success chatter while
leaving those records in the raw backing indexes. The existing raw Logs dataset
is retained for troubleshooting.

Run `scripts/standardize-explore-log-datasets.sh --plan` first. The script
refuses to apply if a composable index template already matches future
`logs-v2-*` indexes, because an alias-only legacy template could be shadowed.
When safe, `--apply`:

1. backs up current templates, aliases, and dataset saved objects;
2. installs an alias-only legacy template for future daily log indexes;
3. attaches the filtered aliases to existing `logs-v2-*` indexes;
4. clones the current raw Logs dataset metadata into two canonical Logs
   datasets;
5. verifies namespace exclusivity and confirms routine Fluent Bit success
   chatter is absent from the platform alias.

The source raw dataset is not deleted or renamed.
