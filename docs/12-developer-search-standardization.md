# Developer Observability Search standardization

The custom developer search UI is standardized as a reusable observability
component rather than a customer-named host customization.

## Canonical runtime layout

```text
/opt/observability-search/
└── app.py

/etc/observability-search/
├── observability-search.env
├── root-ca.pem
└── credentials/
    └── opensearch-password

/etc/systemd/system/
└── observability-search.service
```

The previous customer/environment-specific names are removed only after the new
service passes syntax, startup and HTTP verification. A rollback copy is retained
under `/root/observability-search-migration-<timestamp>`.

## Runtime identity

The UI must not hard-code a customer name. Runtime configuration supplies:

- `OBSERVABILITY_ENVIRONMENT` — machine-friendly environment value;
- `OBSERVABILITY_ENV_LABEL` — displayed environment label, for example
  `UAT2` or `Production`;
- `DASHBOARDS_BASE` — browser-facing Dashboards base URL;
- listener address/port;
- workspace, dashboard and data-view identifiers;
- the secured OpenSearch endpoint, reader username and CA.

The year in the footer is generated at runtime.

The standard visible identity is:

```text
ENVIRONMENT  [<environment>]

Developer Observability Search

© <year> · <environment> Developer Observability Search · Developed by nhxttx
```

The developer attribution `nhxttx` is intentional.

## Remote-access behavior

For the current VPN + SSH local-forward workflow, `DASHBOARDS_BASE` remains
`http://localhost:5601`. Redirects are executed by the operator's browser and
resolved through the local SSH tunnel. Do not replace it with a private server
address unless the supported access model changes.

## Migration

Preview:

```bash
bash scripts/migrate-developer-search.sh --plan
```

Apply on the intended live host only:

```bash
EXPECTED_HOST=<hostname> \
OBSERVABILITY_ENVIRONMENT=uat2 \
OBSERVABILITY_ENV_LABEL=UAT2 \
bash scripts/migrate-developer-search.sh --apply
```

The migration preserves the existing OpenSearch HTTPS reader identity and
systemd credential, copies the CA and password into standardized paths, validates
the new application, cuts over port 8088, verifies the rendered identity, then
retires the legacy paths/service.
