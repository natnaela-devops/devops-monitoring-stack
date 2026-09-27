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

Run `scripts/standardize-explore-log-datasets.sh --plan` first. If exactly
one composable index template already matches future `logs-v2-*` indexes,
`--apply` backs it up and patches that template in place, preserving its
existing settings/mappings while adding only the two filtered aliases. If no
composable template matches, the script installs an alias-only legacy template.
If multiple composable templates match, apply stops so template precedence can
be resolved explicitly.

When safe, `--apply`:

1. backs up current templates, aliases, and dataset saved objects;
2. persists the aliases for future daily indexes by patching the single active
   composable template or, when none exists, installing an alias-only legacy
   template;
3. attaches the filtered aliases to existing `logs-v2-*` indexes;
4. clones the current raw Logs dataset metadata into two canonical Logs
   datasets;
5. verifies namespace exclusivity and confirms routine Fluent Bit success
   chatter is absent from the platform alias.

The source raw dataset is not deleted or renamed.
