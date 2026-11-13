#!/usr/bin/env python3
"""Run native scenarios against this checkout's dist/Brk.app under the native lock.

    python3 scripts/run-native.py <name> --set smoke,ai          # the groups in scripts/native-sets.txt
    python3 scripts/run-native.py <name> --only N1,PB1R          # chosen scenario ids
    python3 scripts/run-native.py <name> --set real --agent claude   # real agents: spends the user's quota

Needs dist/Brk.app (scripts/build.sh, or a station's bundle refreshed with scripts/station/refresh-app.sh) and
.build/release/brk-e2e (swift build -c release --product brk-e2e). Takes /tmp/brk-core-native.lock itself: never wrap
it in another with-batch-locks.py call for that lock. The report, logs and pictures go outside the repository, to
~/brk-evidence/native/<name>/ (or --out); nothing of a run is committed (docs/testing-policy.md).

brk-e2e skips an id it does not know without a word, so this script compares the report with the ids asked for and
fails when one is missing.
"""
import argparse, hashlib, json, os, pathlib, re, subprocess, sys, tempfile

root = pathlib.Path(__file__).resolve().parents[1]
sets_file = root / 'scripts/native-sets.txt'
REAL_SWITCH = {'AIRealUI-': 'BRK_E2E_REAL_UI_AGENT', 'AIRealUIBasic-': 'BRK_E2E_REAL_BASIC_AGENT', 'AIRealRightPanel-': 'BRK_E2E_REAL_RIGHT_AGENT'}


def read_sets():
    sets = {}
    for line in sets_file.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if line and not line.startswith('#'):
            group, scenario = line.split()
            sets.setdefault(group, []).append(scenario)
    return sets


parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('name', help='a new name for this run')
parser.add_argument('--set', help='comma-separated groups from scripts/native-sets.txt')
parser.add_argument('--only', help='comma-separated scenario ids')
parser.add_argument('--agent', default='claude', help='real agent for the real group (claude or codex)')
parser.add_argument('--out', help='evidence folder; default ~/brk-evidence/native/<name>')
parser.add_argument('--wait', type=float, default=float('inf'), help='ceiling in seconds for the lock wait; default: wait as long as it takes')
parser.add_argument('--run-timeout', type=float, default=1800)
args = parser.parse_args()
if not args.name.replace('-', '').isalnum():
    parser.error('use a simple name: letters, digits and dashes')
sets = read_sets()
wanted = []
for group in filter(None, (args.set or '').split(',')):
    if group not in sets:
        parser.error(f'no group {group} in {sets_file.relative_to(root)}; groups: {", ".join(sets)}')
    wanted += sets[group]
wanted += [s.strip() for s in (args.only or '').split(',') if s.strip()]
wanted = [s.replace('-claude', '-' + args.agent) if s.startswith(tuple(REAL_SWITCH)) else s for s in dict.fromkeys(wanted)]
if not wanted:
    parser.error('name scenarios with --set or --only')

out = pathlib.Path(args.out).expanduser() if args.out else pathlib.Path.home() / 'brk-evidence/native' / args.name
if out.exists():
    parser.error(f'{out} already exists; pick a new name')
out.mkdir(parents=True)
app = root / 'dist/Brk.app'
runner = root / '.build/release/brk-e2e'
for needed in (app, runner):
    if not needed.exists():
        sys.exit(f'missing {needed.relative_to(root)}; see the top of this script')

env = os.environ.copy()
env['BRK_E2E_DATA_ROOT'] = tempfile.mkdtemp(prefix='brk-rn-', dir='/tmp')   # short: the control socket path has a length limit
env['BRK_TEST_NO_GLOBAL_SHORTCUT'] = '1'   # test instances leave ⌥⌘N to the user's apps; R36-LittleEntry takes it back itself
for scenario in wanted:
    for prefix, switch in REAL_SWITCH.items():
        if scenario.startswith(prefix):
            env[switch] = scenario[len(prefix):]
    if scenario.startswith('AIRealLocal-'):
        env['BRK_E2E_REAL_LOCAL'] = '1'

command = [str(runner), '--app', str(app), '--site', str(root / 'Tests/E2ESite'), '--out', str(out), '--only', ','.join(wanted)]
bounded = [sys.executable, str(root / 'scripts/bounded-phase.py'), '--timeout', str(args.run_timeout), '--owned-app', str(app), '--'] + command
locked = [sys.executable, str(root / 'scripts/with-batch-locks.py'), '--lock', '/tmp/brk-core-native.lock', '--timeout', str(args.wait), '--'] + bounded


def sha(path):
    with open(path, 'rb') as handle:
        return hashlib.file_digest(handle, 'sha256').hexdigest()


head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
dirty = subprocess.check_output(['git', 'status', '--porcelain', '--', 'Sources', 'Tests', 'Package.swift'], cwd=root, text=True).strip()
manifest = dict(head=head, uncommittedSourceChanges=bool(dirty), scenarios=wanted, command=locked,
                app=sha(app / 'Contents/MacOS/Brk'), runner=sha(runner))
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
with (out / 'run.log').open('x') as log:
    result = subprocess.run(locked, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)

report = (out / 'REPORT.md').read_text(encoding='utf-8') if (out / 'REPORT.md').exists() else ''
ran = {scenario: outcome for outcome, scenario in re.findall(r'^- (PASS|FAIL|SKIPPED) (\S+) ', report, re.M)}
missing = [s for s in wanted if s not in ran]
summary = dict(exit=result.returncode, report=str(out / 'REPORT.md'), asked=len(wanted), ran=len(ran),
               failed=[s for s, outcome in ran.items() if outcome == 'FAIL'], missing=missing)
manifest.update(summary)
(out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(summary, indent=1))
if missing:
    print('these ids were asked for but not run (unknown to brk-e2e, or a real-agent switch is missing): ' + ', '.join(missing), file=sys.stderr)
sys.exit(result.returncode or (3 if missing else 0))
