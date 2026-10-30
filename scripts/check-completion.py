#!/usr/bin/env python3
"""Validate the full Arc inventory and refuse completion without per-feature evidence."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
STATES = {"unreviewed", "missing", "partial", "implemented", "verified", "blocked", "excluded", "deferred"}
CHECKS = {"unit", "native", "visual", "manual", "static"}


def validate(inventory, require_complete):
    problems = []
    features = inventory["features"]
    expected = {f"A{i:03}" for i in range(1, inventory["baseline_feature_count"] + 1)}
    ids = [row["id"] for row in features]
    if len(ids) != len(set(ids)) or set(ids) != expected:
        problems.append("Feature IDs must cover the original inventory exactly once.")
    counts = Counter(row["status"] for row in features)
    for row in features:
        identity, state = row["id"], row["status"]
        if state not in STATES:
            problems.append(f"{identity}: unknown status {state}")
        if state in {"excluded", "deferred"} and not row.get("decision"):
            problems.append(f"{identity}: a user decision is required for {state}")
        if state != "verified":
            continue
        checks = row.get("verification", [])
        if not row.get("acceptance") or not checks:
            problems.append(f"{identity}: verified needs acceptance criteria and passing evidence")
        kinds = set()
        for check in checks:
            kind = check.get("kind")
            kinds.add(kind)
            if kind not in CHECKS or check.get("result") != "pass" or not check.get("command"):
                problems.append(f"{identity}: invalid or non-passing verification")
            artifact = (ROOT / check.get("artifact", "")).resolve()
            if not artifact.is_relative_to(ROOT) or not artifact.is_file():
                problems.append(f"{identity}: evidence must be a file in this repository")
        if not set(row.get("required_checks", [])) <= kinds:
            problems.append(f"{identity}: a required verification kind is missing")
    if require_complete:
        pending = [row["id"] for row in features if row["status"] not in {"verified", "excluded", "deferred"}]
        if pending:
            problems.append(f"{len(pending)} features remain unverified: {', '.join(pending[:12])}")
        actions = (ROOT / "Sources/BrkDomain/Actions.swift").read_text()
        later = set(re.findall(r"\.later\s*\(\s*\.(\w+)\s*\)", actions))
        waivers = inventory.get("deferred_later_features", {})
        if any(not reason for reason in waivers.values()):
            problems.append("Deferred action groups need a user decision.")
        remaining = later - waivers.keys()
        if remaining:
            problems.append("Menu actions remain unimplemented: " + ", ".join(sorted(remaining)))
    return counts, problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inventory", type=Path, default=ROOT / "docs/completion/features.json")
    parser.add_argument("--require-complete", action="store_true")
    args = parser.parse_args()
    try:
        inventory = json.loads(args.inventory.read_text())
        counts, problems = validate(inventory, args.require_complete)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Invalid inventory: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"features": sum(counts.values()), "statuses": dict(sorted(counts.items()))}, ensure_ascii=False))
    for problem in problems:
        print(problem, file=sys.stderr)
    return int(bool(problems))


if __name__ == "__main__":
    raise SystemExit(main())
