# Validation Evidence

`scripts/validate-platform.sh` writes sanitized Markdown and JSON reports beneath
`evidence/generated/`. Generated reports are intentionally ignored by Git because even
sanitized operational evidence can reveal environment timing, scale, or service names.

Before attaching evidence to a change record:

1. review it for addresses, hostnames, credentials, tokens, certificates, trace IDs,
   transaction IDs, pod UIDs, and customer data;
2. store the reviewed copy in the approved private evidence system;
3. record the Git commit and frozen component baseline that were validated;
4. never commit raw API responses or live configuration to this public repository.

The repository should contain the reusable procedure and empty evidence policy only—not
environment-specific results.
