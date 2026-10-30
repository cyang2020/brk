#!/usr/bin/env python3
"""Validate independent assessments and apply them without overwriting later work."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "docs/completion/features.json"
PROVENANCE = ("id", "section", "feature", "arc_evidence", "description", "historical_status")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("proposals", nargs="+", type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    catalog = json.loads(CATALOG.read_text())
    current = {row["id"]: row for row in catalog["features"]}
    replacements = {}
    for path in args.proposals:
        path = path.resolve()
        relative = str(path.relative_to(ROOT))
        payload = path.read_bytes()
        proposal = json.loads(payload)
        require(proposal.get("base_commit") and proposal.get("method"), relative)
        assessment = {"proposal": relative, "sha256": hashlib.sha256(payload).hexdigest(),
                      "base_commit": proposal["base_commit"]}
        for row in proposal["features"]:
            ident = row["id"]
            require(ident in current and ident not in replacements, f"Unknown or duplicate ID: {ident}")
            before = current[ident]
            require(all(row.get(key) == before[key] for key in PROVENANCE), f"Changed feature identity: {ident}")
            require(row["status"] != "unreviewed" and row.get("owner") and row.get("acceptance"), ident)
            require(row.get("implementation"), f"Missing source pointers: {ident}")
            for pointer in row["implementation"]:
                source = (ROOT / pointer.split(":")[0]).resolve()
                require(source.is_relative_to(ROOT) and source.is_file(), f"Bad source: {pointer}")
            for check in row.get("verification", []):
                artifact = (ROOT / check["artifact"]).resolve()
                require(artifact.is_relative_to(ROOT) and artifact.is_file(), f"Bad evidence: {ident}")
            if row["status"] in {"excluded", "deferred"}:
                require(ident in {"A123", "A124", "A126", "A127", "A128"} and row.get("decision"), ident)
            updated = dict(row, assessment=assessment)
            require(before["status"] == "unreviewed" or before == updated, f"Refusing to overwrite an existing assessment: {ident}")
            replacements[ident] = updated
    catalog["features"] = [replacements.get(row["id"], row) for row in catalog["features"]]
    spec = importlib.util.spec_from_file_location("completion_check", ROOT / "scripts/check-completion.py")
    checker = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checker)
    counts, problems = checker.validate(catalog, False)
    require(not problems, problems)
    encoded = json.dumps(catalog, indent=2, ensure_ascii=False) + "\n"
    changed = encoded != CATALOG.read_text()
    if args.apply and changed:
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", dir=CATALOG.parent, prefix=".features-", delete=False) as f:
                temporary = Path(f.name)
                f.write(encoded)
            temporary.replace(CATALOG)
        finally:
            if temporary is not None: temporary.unlink(missing_ok=True)
    print(json.dumps({"assessed_rows": len(replacements), "applied": args.apply and changed,
                      "statuses": dict(sorted(counts.items()))}))


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, AttributeError, KeyError, OSError, TypeError, ValueError) as error:
        print(f"Proposal rejected: {error}", file=sys.stderr)
        raise SystemExit(1)
