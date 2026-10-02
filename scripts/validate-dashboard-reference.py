#!/usr/bin/env python3
import ipaddress
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
REF = ROOT / "dashboards" / "reference"

EXPECTED = {
    "dashboards.json": ("dashboard", 6),
    "explore-panels.json": ("explore", 74),
    "data-views.json": ("index-pattern", 4),
    "saved-searches.json": ("search", 2),
}

TRANSIENT_KEYS = {"updated_at", "version", "workspaces", "namespaces", "score"}
PROMETHEUS_PLACEHOLDER = ("index-pattern", "reference-prometheus")

ALLOWED_NAMESPACE_SELECTORS = {
    "span_derived",
    "^application-.*$",
    "channel-mobile",
    "channel-ussd",
    "^(cattle-capi-system|cattle-fleet-local-system|cattle-fleet-system|"
    "cattle-system|cattle-turtles-system|cert-manager|fleet-default|"
    "kube-system|longhorn-system|monitoring)$",
}

ALLOWED_NODE_SELECTORS = {
    "host-01",
    "host-02",
    "host-03",
    "observability-host-01",
}

UUID_PATTERN = re.compile(
    r"\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-"
    r"[89ab][0-9a-f]{3}-[0-9a-f]{12}\b",
    re.I,
)

TOKEN_PATTERN = re.compile(r"\b\d{6,}:[A-Za-z0-9_-]{20,}\b")
PRIVATE_KEY_PATTERN = re.compile(r"BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY")

def die(message: str) -> None:
    print(f"[ERROR] {message}", file=sys.stderr)
    raise SystemExit(1)

def load_collection(name: str, expected_type: str, expected_count: int):
    path = REF / name
    if not path.is_file():
        die(f"missing dashboard reference file: {path}")

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        die(f"invalid JSON in {path}: {exc}")

    objects = data.get("saved_objects")
    if not isinstance(objects, list):
        die(f"{path} must contain saved_objects array")

    if len(objects) != expected_count:
        die(f"{path}: expected {expected_count} objects, found {len(objects)}")

    for obj in objects:
        if obj.get("type") != expected_type:
            die(f"{path}: unexpected object type {obj.get('type')!r}")

    return objects

def scan_transient(value, where="root"):
    if isinstance(value, dict):
        for key, child in value.items():
            if key in TRANSIENT_KEYS:
                die(f"transient saved-object key {key!r} remains at {where}")
            scan_transient(child, f"{where}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            scan_transient(child, f"{where}[{index}]")

def validate_query_object(obj):
    meta = obj.get("attributes", {}).get("kibanaSavedObjectMeta", {})
    raw = meta.get("searchSourceJSON")
    if not raw:
        return

    try:
        source = json.loads(raw)
    except Exception as exc:
        die(f"{obj['id']}: invalid searchSourceJSON: {exc}")

    query = source.get("query", {})
    text = query.get("query", "")
    language = query.get("language", "")

    if language == "PROMQL":
        dataset = query.get("dataset")
        if not isinstance(dataset, dict):
            die(f"{obj['id']}: PROMQL query has no dataset object")

        if dataset.get("id") != "reference-prometheus":
            die(f"{obj['id']}: unexpected Prometheus dataset id")
        if dataset.get("title") != "reference-prometheus":
            die(f"{obj['id']}: unexpected Prometheus dataset title")

        env_values = set(
            re.findall(r'environment\s*=\s*"([^"]*)"', text)
        )
        if env_values - {"reference"}:
            die(f"{obj['id']}: non-reference environment selector: {sorted(env_values)}")

        namespace_values = set(
            value
            for _, value in re.findall(
                r'namespace\s*(=|=~)\s*"([^"]*)"',
                text,
            )
        )
        unexpected_namespaces = namespace_values - ALLOWED_NAMESPACE_SELECTORS
        if unexpected_namespaces:
            die(
                f"{obj['id']}: unexpected namespace selector: "
                f"{sorted(unexpected_namespaces)}"
            )

        node_values = set(
            value
            for _, value in re.findall(
                r'node\s*(=|=~)\s*"([^"]*)"',
                text,
            )
            if value
        )
        unexpected_nodes = node_values - ALLOWED_NODE_SELECTORS
        if unexpected_nodes:
            die(f"{obj['id']}: unexpected node selector: {sorted(unexpected_nodes)}")

objects = {}
texts = []

for filename, (expected_type, count) in EXPECTED.items():
    collection = load_collection(filename, expected_type, count)
    text = (REF / filename).read_text(encoding="utf-8")
    texts.append(text)

    for obj in collection:
        key = (obj["type"], obj["id"])
        if key in objects:
            die(f"duplicate saved object: {key}")

        if not obj["id"].startswith("std-"):
            die(f"non-standard saved-object id: {obj['id']}")

        objects[key] = obj
        scan_transient(obj, f"{filename}:{obj['id']}")
        validate_query_object(obj)

combined = "\n".join(texts)

if UUID_PATTERN.search(combined):
    die("opaque UUID remains in sanitized dashboard reference")
if TOKEN_PATTERN.search(combined):
    die("token-like value remains in sanitized dashboard reference")
if PRIVATE_KEY_PATTERN.search(combined):
    die("private-key material remains in sanitized dashboard reference")

ipv4_values = sorted(set(re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", combined)))
for value in ipv4_values:
    try:
        ip = ipaddress.ip_address(value)
    except ValueError:
        continue

    if ip.version == 4 and ip not in ipaddress.ip_network("192.0.2.0/24"):
        die(f"unexpected IPv4 address remains in dashboard reference: {value}")

missing = []

for source, obj in objects.items():
    for ref in obj.get("references", []):
        target = (ref.get("type"), ref.get("id"))
        if target not in objects and target != PROMETHEUS_PLACEHOLDER:
            missing.append((source, target, ref.get("name")))

if missing:
    for source, target, name in missing:
        print(
            f"[ERROR] unresolved reference: {source} -> {target} ({name})",
            file=sys.stderr,
        )
    raise SystemExit(1)

for source, obj in objects.items():
    if source[0] != "dashboard":
        continue

    for ref in obj.get("references", []):
        target = (ref.get("type"), ref.get("id"))
        if target not in objects:
            die(
                f"dashboard {source[1]} has unresolved panel/search reference "
                f"{target}"
            )

prometheus_refs = 0
for obj in objects.values():
    for ref in obj.get("references", []):
        if (ref.get("type"), ref.get("id")) == PROMETHEUS_PLACEHOLDER:
            prometheus_refs += 1

if prometheus_refs == 0:
    die("Prometheus placeholder reference is missing")

print(
    "[OK] dashboard reference validated: "
    "6 dashboards, 74 Explore panels, 4 data views, 2 saved searches"
)
print("[OK] all dashboard dependencies resolve")
print(
    f"[OK] {prometheus_refs} metric references use the intentional "
    "reference-prometheus placeholder"
)
print("[OK] environment, namespace, node, address, UUID, and secret guardrails passed")
