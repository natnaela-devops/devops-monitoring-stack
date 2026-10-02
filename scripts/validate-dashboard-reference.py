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

PRIVATE_PATTERNS = {
    "live private subnet": re.compile(r"\b10\.1\.22\.\d+\b"),
    "workspace id": re.compile(r"Wbvl8L"),
    "customer name": re.compile(r"\bEnat\b", re.I),
    "customer hostname": re.compile(r"\bebuat[a-z0-9.-]*\b", re.I),
    "live environment name": re.compile(r"\buat2\b", re.I),
    "live Prometheus connection UUID": re.compile(
        r"a76653e0-9c1a-11f1-97a4-c15765a0dbb6", re.I
    ),
    "private application namespace": re.compile(
        r"app-hub|backoffice|inquiry|internet-banking|taf-app|taf-flink|"
        r"transferhub|ussd-push-payment|wallet",
        re.I,
    ),
}

TRANSIENT_KEYS = {"updated_at", "version", "workspaces", "namespaces", "score"}

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
        objects[key] = obj
        scan_transient(obj, f"{filename}:{obj['id']}")

combined = "\n".join(texts)

for label, pattern in PRIVATE_PATTERNS.items():
    if pattern.search(combined):
        die(f"private deployment identity remains: {label}")

ipv4_values = sorted(set(re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", combined)))
for value in ipv4_values:
    try:
        ip = ipaddress.ip_address(value)
    except ValueError:
        continue
    if ip.version == 4 and not ip in ipaddress.ip_network("192.0.2.0/24"):
        die(f"unexpected IPv4 address remains in dashboard reference: {value}")

allowed_placeholder = ("index-pattern", "reference-prometheus")
missing = []

for source, obj in objects.items():
    for ref in obj.get("references", []):
        target = (ref.get("type"), ref.get("id"))
        if target not in objects and target != allowed_placeholder:
            missing.append((source, target, ref.get("name")))

if missing:
    for source, target, name in missing:
        print(f"[ERROR] unresolved reference: {source} -> {target} ({name})", file=sys.stderr)
    raise SystemExit(1)

for source, obj in objects.items():
    if source[0] != "dashboard":
        continue
    for ref in obj.get("references", []):
        target = (ref.get("type"), ref.get("id"))
        if target not in objects:
            die(f"dashboard {source[1]} has unresolved panel/search reference {target}")

if "reference-prometheus" not in combined:
    die("Prometheus placeholder reference is missing")

print(
    "[OK] dashboard reference validated: "
    "6 dashboards, 74 Explore panels, 4 data views, 2 saved searches"
)
print("[OK] all dashboard dependencies resolve")
print("[OK] only reference-prometheus remains as an intentional external mapping")
print("[OK] no known private deployment identifiers remain")
