#!/usr/bin/env python3
"""Build changed Core targets using a persistent development or release cache."""
import argparse
import fcntl
import os
from pathlib import Path
import shlex
import subprocess
import sys


def settings(engine):
    names = ('BRK_SRC', 'BRK_OUT_BRK', 'BRK_OUT_RELEASE_ARM64', 'BRK_OUT_RELEASE_X64')
    command = 'source "$1"; printf "%s\\0" ' + ' '.join('"$' + name + '"' for name in names)
    values = subprocess.check_output(['bash', '-c', command, '_', str(engine / 'config.sh')], text=True)
    return dict(zip(names, values.rstrip('\0').split('\0')))


def running_build(source):
    directory = (source / 'third_party/ninja').resolve()
    listing = subprocess.check_output(['ps', '-axo', 'pid=,command='], text=True)
    for line in listing.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) != 2:
            continue
        try:
            command = shlex.split(fields[1])
        except ValueError:
            continue
        if command and Path(command[0]).name == 'ninja' and Path(command[0]).parent.resolve() == directory:
            return fields[0]
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', choices=['arm64', 'x64'], help='Use the official cache for one architecture')
    parser.add_argument('--target', default='chrome', help='Ninja target, default: chrome')
    args = parser.parse_args()
    engine = Path(__file__).resolve().parent
    config = settings(engine)
    source = Path(config['BRK_SRC'])
    if not source.is_dir():
        parser.error('Chromium source is missing; run engine/fetch.sh and engine/apply-patches.sh first')
    key = 'BRK_OUT_BRK' if args.release is None else 'BRK_OUT_RELEASE_' + ('ARM64' if args.release == 'arm64' else 'X64')
    out = config[key]
    output_root = source / 'out'
    output_root.mkdir(exist_ok=True)
    with (output_root / '.brk-incremental.lock').open('a') as lock:
        print('[incremental] Using ' + str(source / out), flush=True)
        fcntl.flock(lock, fcntl.LOCK_EX)
        pid = running_build(source)
        if pid:
            print('[incremental] Chromium build pid ' + pid + ' is already running; leaving its files and process unchanged', file=sys.stderr)
            return 75
        subprocess.run([str(engine / 'sync-header.sh')], check=True)
        mode = ['dev'] if args.release is None else ['release', args.release]
        subprocess.run([str(engine / 'configure.sh'), *mode], check=True)
        environment = dict(os.environ, BRK_OUT=out)
        return subprocess.run([str(engine / 'build.sh'), args.target], env=environment).returncode


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode)
