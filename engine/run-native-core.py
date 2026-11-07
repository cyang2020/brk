#!/usr/bin/env python3
"""Runs e2e scenarios on BrkCore: dist-core/Brk.app (engine/assemble-app.sh) with this checkout's release brk-e2e, under the native lock,
bounded in time. Evidence goes to verify/chromium/<name>/ and must be a new name.

    engine/run-native-core.py m3-1 --only N1,N2,N3,N4,BB1,BB2,BB3,BB4
"""
import argparse, os, pathlib, subprocess, sys, tempfile

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('name')
parser.add_argument('--only')
parser.add_argument('--run-timeout', type=float, default=1800)
args = parser.parse_args()
evidence = root / 'verify/chromium' / args.name
if evidence.exists():
    parser.error('Evidence name already exists')
evidence.mkdir(parents=True)
app = root / 'dist-core/Brk.app'
command = [str(root / '.build/release/brk-e2e'), '--app', str(app), '--site', str(root / 'Tests/E2ESite'), '--out', str(evidence), '--engine', 'core']
if args.only:
    command += ['--only', args.only]
bounded = [sys.executable, str(root / 'verify/completion/browser-basic-parent/bounded-phase.py'), '--timeout', str(args.run_timeout), '--owned-app', str(app), '--'] + command
locked = [sys.executable, str(root / 'scripts/with-batch-locks.py'), '--lock', '/tmp/brk-core-native.lock', '--'] + bounded
env = os.environ.copy()
env['BRK_E2E_DATA_ROOT'] = tempfile.mkdtemp(prefix='brk-core-', dir='/tmp')
env['BRK_TEST_NO_GLOBAL_SHORTCUT'] = '1'
with (evidence / 'run.log').open('x') as log:
    result = subprocess.run(locked, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
print('exit', result.returncode, 'evidence', evidence)
sys.exit(result.returncode)
