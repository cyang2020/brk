#!/usr/bin/env python3
"""Runs e2e scenarios on BrkCore: dist-core/Brk.app (engine/assemble-app.sh) with this checkout's release brk-e2e, under the native lock,
bounded in time. The report goes to ~/brk-evidence/chromium/<name>/ (run records are not committed, docs/testing-policy.md)
and must be a new name.

    engine/run-native-core.py m3-1 --set smoke,sites        # groups from scripts/native-sets.txt
    engine/run-native-core.py m3-2 --only N1,N2,BB2
"""
import argparse, os, pathlib, subprocess, sys, tempfile

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('name')
parser.add_argument('--only')
parser.add_argument('--set', help='comma-separated groups from scripts/native-sets.txt')
parser.add_argument('--run-timeout', type=float, default=1800)
args = parser.parse_args()
evidence = pathlib.Path.home() / 'brk-evidence/chromium' / args.name
if evidence.exists():
    parser.error('Evidence name already exists')
evidence.mkdir(parents=True)
app = root / 'dist-core/Brk.app'
command = [str(root / '.build/release/brk-e2e'), '--app', str(app), '--site', str(root / 'Tests/E2ESite'), '--out', str(evidence), '--engine', 'core']
groups = {}
for line in (root / 'scripts/native-sets.txt').read_text(encoding='utf-8').splitlines():
    if line.strip() and not line.startswith('#'):
        group, scenario = line.split()
        groups.setdefault(group, []).append(scenario)
wanted = [s for g in filter(None, (args.set or '').split(',')) for s in groups[g]] + [s for s in (args.only or '').split(',') if s]
if wanted:
    command += ['--only', ','.join(dict.fromkeys(wanted))]
bounded = [sys.executable, str(root / 'scripts/bounded-phase.py'), '--timeout', str(args.run_timeout), '--owned-app', str(app), '--'] + command
locked = [sys.executable, str(root / 'scripts/with-batch-locks.py'), '--lock', '/tmp/brk-core-native.lock', '--'] + bounded
env = os.environ.copy()
env['BRK_E2E_DATA_ROOT'] = tempfile.mkdtemp(prefix='brk-core-', dir='/tmp')
env['BRK_TEST_NO_GLOBAL_SHORTCUT'] = '1'
with (evidence / 'run.log').open('x') as log:
    result = subprocess.run(locked, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
print('exit', result.returncode, 'evidence', evidence)
sys.exit(result.returncode)
