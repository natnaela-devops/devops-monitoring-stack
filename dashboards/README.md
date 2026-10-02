# OpenSearch Dashboards reference exports

This directory contains the sanitized saved-object reference captured from the final validated observability workspace.

The former Grafana sample was removed because Grafana is not part of the current platform.

## Final dashboard set

The reference contains six dashboards:

1. Infrastructure Health
2. Deployment & Workload Health
3. Application Performance
4. Developer Investigation
5. Real-Time Channel Performance
6. Kubernetes Platform Health

The complete sanitized dependency set is under [reference/](reference/):

- `dashboards.json` — 6 dashboard objects;
- `explore-panels.json` — 74 Explore objects actually referenced by the six dashboards;
- `data-views.json` — 4 standardized log/APM data views;
- `saved-searches.json` — 2 saved searches used by Developer Investigation;
- `SANITIZATION.md` — mapping and import requirements;
- `SHA256SUMS` — checksums for the captured sanitized reference files.

Unreferenced legacy Explore objects from the live workspace are intentionally excluded.

## Privacy and sanitization

The public reference does not retain the live workspace ID, customer identity, private hostnames, private addresses, deployment-specific application namespaces, credentials, tokens, trace IDs, transaction payloads, or the live Prometheus connection identity.

The Prometheus source is represented by the placeholder `reference-prometheus`. Host identities use documentation labels and TEST-NET-1 addresses.

Run:

```bash
python3 scripts/validate-dashboard-reference.py
```

to verify object counts, reference integrity, the intentional Prometheus placeholder, and the private-identity guardrails.

## Import / adaptation

These files are sanitized reference collections, not a blind production restore. Before using them in another environment:

1. create/select the target Prometheus data connection;
2. map `reference-prometheus` to that connection identifier;
3. replace the `reference` telemetry environment label;
4. adapt the generic application/channel namespace selectors;
5. map the documentation host inventory to the target hosts;
6. import/restore data views and saved searches before dashboards;
7. refresh data-view fields;
8. validate every query and visualization against the target telemetry.

See [reference/SANITIZATION.md](reference/SANITIZATION.md) for the exact mapping contract.
