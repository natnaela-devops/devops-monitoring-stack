# Sanitized dashboard reference

This directory is generated from the final operated saved-object snapshot and is safe for public reference after the checks described below.

## Included objects

- 6 dashboards
- 74 dashboard-referenced Explore panels
- 4 data views
- 2 saved searches used by Developer Investigation

Unreferenced legacy Explore objects from the live workspace are intentionally excluded.

## Sanitization map

Private deployment identity is replaced before publication:

- Prometheus source identity -> `reference-prometheus`;
- workspace metadata -> removed;
- environment label -> `reference`;
- application workload namespace selector -> `^application-.*$`;
- channel deployment namespaces -> `channel-mobile` and `channel-ussd`;
- host names -> `host-01`, `host-02`, `host-03`, and `observability-host-01`;
- internal host addresses -> TEST-NET-1 documentation addresses;
- customer/environment display text -> generic reference terminology;
- transient saved-object metadata (`updated_at`, `version`, workspace/namespace/score fields) -> removed;
- data-view field caches -> removed so fields can be refreshed after import.

The public artifacts retain the generic Mobile and USSD channel concepts because they are part of the dashboard design, but deployment-specific namespace and host identity is removed.

## Prometheus source mapping

The operated workspace did not contain a normal `index-pattern` saved object with the live Prometheus connection name. Instead, metric Explore objects referenced the Prometheus `data-connection` connection identifier through the saved-object reference field.

For that reason `reference-prometheus` is intentionally a placeholder, not a complete Prometheus connection definition. Before import/rendering, map it to the target OpenSearch Dashboards Prometheus connection identifier.

## Import notes

These files are sanitized reference collections rather than raw live exports. Before importing into another environment:

1. create or select the target Prometheus data connection;
2. replace `reference-prometheus` with that connection identifier;
3. replace `environment="reference"` with the target telemetry environment;
4. adapt `^application-.*$`, `channel-mobile`, and `channel-ussd` selectors to the target namespace policy;
5. map the documentation host identities/addresses to the target host inventory;
6. import data views and saved searches before dashboards;
7. refresh data-view fields and validate every dashboard panel.

No raw workspace ID, private IP address, customer hostname, customer name, credential, token, trace ID, or transaction payload is retained in these files.
