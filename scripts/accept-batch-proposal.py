#!/usr/bin/env python3
"""Apply a parent acceptance decision for one batch slice to docs/completion/features.json with provenance.

The parent runs this after integrating a delivered branch into main and re-verifying it. It is the
reusable form of verify/completion/ledger-reconciliation-20261031/reconcile.py.

Rules:
  - A row is never promoted above the worker's proposal; the parent may hold it lower with a reason.
  - verified needs every required check kind passing on repository-local evidence, and the native
    scenarios the parent names for the row (--rely) must PASS in the parent's native report.
  - Scenarios recorded as failing (--fail) must actually FAIL in that report.
  - Proposal identity fields (id, section, feature, description, acceptance, ...) must match the ledger.
  - scripts/check-completion.py must report no problems after the change, or nothing is written.

Example:
  python3 scripts/accept-batch-proposal.py --slice browser-ops \
    --delivered <sha> --integrated <sha> \
    --build-log verify/completion/batch2-parent/browser-ops/build.log --build-scope "Full signed build on main <sha>: N tests, 3 known skips, 0 failures." \
    --native-report verify/completion/browser-basic-parent/batch2-browser-ops/REPORT.md \
    --native-manifest verify/completion/browser-basic-parent/batch2-browser-ops-manifest.json \
    --review verify/completion/batch2-parent/browser-ops/REVIEW.md \
    --rely A048=T1,T2,T13 --decision A044=partial:"Cast has no receiver on this host" --apply
"""
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "docs/completion/features.json"
ORDER = ["missing", "partial", "implemented", "verified"]
IDENTITY = ("id", "section", "feature", "arc_evidence", "description", "historical_status", "acceptance")


def lower_or_equal(status, ceiling):
    if status == ceiling: return True  # blocked, excluded and deferred compare only to themselves
    return status in ORDER and ceiling in ORDER and ORDER.index(status) <= ORDER.index(ceiling)


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def native_results(report):
    text = (ROOT / report).read_text()
    results, messages = {}, {}
    for m in re.finditer(r"^- (PASS|FAIL|SKIPPED) (\S+) (.*)$", text, re.M):
        results[m.group(2)] = m.group(1)
        if m.group(1) != "PASS":
            msg = re.search(r" — ([^·]*) ·", m.group(3))
            messages[m.group(2)] = msg.group(1).strip() if msg else ""
    head = re.search(r"^(\d{4}-\d\d-\d\dT[^·]*) · .* · (\d+) scenarios in [^·]* · (.*)$", text, re.M)
    return results, messages, (head.group(3).strip() if head else "")


def parse_kv(items, split=","):
    out = {}
    for item in items or []:
        ident, _, value = item.partition("=")
        out[ident] = [v for v in value.split(split) if v] if split else value
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--slice", required=True, help="slice id; proposal at verify/completion/batch2-<slice>/proposal.json")
    ap.add_argument("--proposal", help="override the proposal path")
    ap.add_argument("--delivered", required=True, help="worker's final commit")
    ap.add_argument("--integrated", required=True, help="main commit after integration and parent repairs")
    ap.add_argument("--build-log", required=True)
    ap.add_argument("--build-scope", required=True)
    ap.add_argument("--native-report", required=True)
    ap.add_argument("--native-manifest", required=True)
    ap.add_argument("--native-cmd", default=None)
    ap.add_argument("--review", required=True, help="parent/reviewer report path (repo-local)")
    ap.add_argument("--visual", help="parent visual inspection file for verified rows that require visual")
    ap.add_argument("--rely", action="append", help="ID=scen1,scen2 scenarios the row relies on (must PASS)")
    ap.add_argument("--fail", action="append", help="ID=scen1,scen2 scenarios recorded as failing (must FAIL)")
    ap.add_argument("--decision", action="append", help="ID=status[:reason] parent override (never above proposal)")
    ap.add_argument("--extra", action="append", help="ID=remaining text appended to the row")
    ap.add_argument("--out", help="directory for decisions.json/summary.json; default verify/completion/batch2-parent/<slice>")
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    proposal_path = a.proposal or f"verify/completion/batch2-{a.slice}/proposal.json"
    proposal = json.loads((ROOT / proposal_path).read_text())
    prows = {r["id"]: r for r in proposal["features"]}
    catalog = json.loads(CATALOG.read_text())
    rows = {r["id"]: r for r in catalog["features"]}
    results, messages, headline = native_results(a.native_report)
    manifest = json.loads((ROOT / a.native_manifest).read_text())
    assert manifest["start"] == a.integrated, f"native manifest start {manifest['start']} is not the integrated commit"
    assert manifest["sourceUnchanged"] and manifest["binariesUnchanged"], "native run source/binaries changed during the run"
    native_cmd = a.native_cmd or " ".join(manifest["command"][-6:]) if isinstance(manifest.get("command"), list) else (a.native_cmd or "run-native.py")
    for p in (a.build_log, a.native_report, a.native_manifest, a.review) + ((a.visual,) if a.visual else ()):
        assert (ROOT / p).is_file(), f"missing evidence file {p}"
    rely, fails = parse_kv(a.rely), parse_kv(a.fail)
    decisions = {}
    for item in a.decision or []:
        ident, _, rest = item.partition("=")
        status, _, reason = rest.partition(":")
        decisions[ident] = (status, reason)
    extras = parse_kv(a.extra, split=None)
    out_dir = Path(a.out) if a.out else ROOT / f"verify/completion/batch2-parent/{a.slice}"
    out_dir.mkdir(parents=True, exist_ok=True)

    out, before = [], {}
    for ident, prop in prows.items():
        row = rows[ident]
        for key in IDENTITY:
            assert prop.get(key) == row.get(key), f"{ident}: proposal changed {key}"
        status, reason = decisions.get(ident, (prop["status"], "Proposal accepted after independent review and parent re-verification."))
        assert lower_or_equal(status, prop["status"]), f"{ident}: {status} is above the proposal's {prop['status']}"
        for s in rely.get(ident, []):
            assert results.get(s) == "PASS", f"{ident} relies on {s} which is {results.get(s)}"
        for s in fails.get(ident, []):
            assert results.get(s) == "FAIL", f"{ident} records {s} failing but it is {results.get(s)}"
        if status == "verified":
            assert rely.get(ident), f"{ident}: verified needs --rely scenarios that PASS"
        before[ident] = row["status"]
        new = dict(row)
        new["status"] = status
        if prop.get("implementation"):
            new["implementation"] = prop["implementation"]
        if prop.get("current_behavior"):
            new["current_behavior"] = prop["current_behavior"]
        if prop.get("required_checks") and not row.get("required_checks"):
            new["required_checks"] = prop["required_checks"]
        rem = prop.get("remaining", [])
        remaining = [rem] if isinstance(rem, str) else list(rem)
        if ident in extras:
            remaining.append(extras[ident])
        new["remaining"] = remaining
        assert new.get("implementation"), f"{ident}: no source pointers"
        for pointer in new["implementation"]:
            assert (ROOT / pointer.split(":")[0]).exists(), f"{ident}: missing source {pointer}"
        verification = list(row.get("verification", []))
        seen = {(v.get("kind"), v.get("artifact"), v.get("command")) for v in verification}
        for v in prop.get("verification", []):
            key = (v.get("kind"), v.get("artifact"), v.get("command"))
            if key not in seen and (ROOT / v.get("artifact", "")).is_file():
                verification.append(v); seen.add(key)
        verification.append(dict(kind="unit", result="pass", artifact=a.build_log, scope=a.build_scope,
                                 command="python3 scripts/with-batch-locks.py --lock /tmp/brk-core-native.lock --lock /tmp/brk-batch-build.lock --timeout 55 -- scripts/build.sh"))
        if rely.get(ident):
            verification.append(dict(kind="native", result="pass", command=native_cmd, artifact=a.native_report,
                                     scope=f"Parent native run on main {a.integrated[:7]} ({headline}; source and binaries unchanged per {a.native_manifest}). This row relies on {', '.join(rely[ident])}, all PASS."))
        for s in fails.get(ident, []):
            verification.append(dict(kind="native", result="fail", command=native_cmd, artifact=a.native_report,
                                     scope=f"{s} FAIL on main {a.integrated[:7]}: {messages.get(s, '')}"))
        if status == "verified" and "visual" in new.get("required_checks", []):
            assert a.visual, f"{ident}: verified with a visual requirement needs --visual"
            verification.append(dict(kind="visual", result="pass", command=f"Read {Path(a.native_report).parent}/shots/<capture>.png", artifact=a.visual,
                                     scope="Parent inspected the named captures for layout and readability. No authenticated Arc pixel comparison; A148 remains blocked."))
        new["verification"] = verification
        new["owner"] = "parent-batch2-acceptance" if status == "verified" else prop.get("owner", row.get("owner"))
        assessment = dict(row.get("assessment", {}))
        assessment["parent_update"] = dict(accepted=str(date.today()), slice=a.slice, reason=reason, commit=a.integrated,
                                           delivered_commit=a.delivered, review=a.review, proposal=proposal_path,
                                           proposal_sha256=sha(proposal_path), native_run=a.native_report)
        new["assessment"] = assessment
        rows[ident] = new
        out.append(dict(id=ident, feature=row["feature"], before=before[ident], after=status, proposal_status=prop["status"],
                        rely=rely.get(ident, []), fails=fails.get(ident, []), reason=reason))

    catalog["features"] = [rows[r["id"]] for r in catalog["features"]]
    spec = importlib.util.spec_from_file_location("cc", ROOT / "scripts/check-completion.py")
    cc = importlib.util.module_from_spec(spec); spec.loader.exec_module(cc)
    counts, problems = cc.validate(catalog, False)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    summary = dict(slice=a.slice, integrated=a.integrated, delivered=a.delivered,
                   rows_changed=sum(1 for x in out if x["before"] != x["after"]), rows_touched=len(out),
                   statuses=dict(sorted(counts.items())),
                   transitions=sorted({f"{x['id']} {x['before']}->{x['after']}" for x in out if x["before"] != x["after"]}))
    (out_dir / "decisions.json").write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    if a.apply:
        CATALOG.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
