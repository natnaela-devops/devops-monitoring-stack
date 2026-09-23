# Reference Runtime Capture

Use `scripts/capture-reference-runtime.sh` on the currently operated reference
observability host before implementing a clean-room configuration/activation
stage.

The script is read-only. It captures exact version, service, path, port, and
configuration contracts while redacting lines containing passwords, tokens,
secrets, Telegram bot tokens/chat IDs, and authorization values.

Run:

```bash
bash scripts/capture-reference-runtime.sh --plan
bash scripts/capture-reference-runtime.sh --capture
```

The output is operational evidence, not a public-repository artifact. It may
still contain environment names, hostnames, addresses, certificate paths, and
distinguished names. Use it to update sanitized templates; do not commit the raw
capture.

The configuration/activation installer must not be implemented from assumptions
when a runtime contract can be measured from the reference environment.
