# OpenSearch Dashboards exports

This directory is reserved for sanitized OpenSearch Dashboards saved-object exports created from the validated observability workspace.

The former Grafana sample was removed because Grafana is not part of the current platform.

Before committing an export:

1. remove data-source identifiers that are environment-specific;
2. remove internal addresses, hostnames, usernames, and credentials;
3. remove customer, account, transaction, trace, span, pod, and node identifiers;
4. confirm that the object imports into a clean lab workspace;
5. record its required index patterns and minimum OpenSearch Dashboards version.

Planned exports include the Kubernetes platform overview, application SLO report, service health overview, and ingestion pipeline health.
