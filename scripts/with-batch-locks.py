#!/usr/bin/env python3
"""Run a command after acquiring all requested batch locks without holding a partial set."""
import argparse
from contextlib import contextmanager
import fcntl
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


@contextmanager
def acquire(paths, timeout):
    deadline = time.monotonic() + timeout
    paths = sorted({str(Path(path).resolve()) for path in paths})
    while True:
        held = []
        try:
            for path in paths:
                handle = open(path, 'a')
                held.append(handle)
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            for handle in reversed(held):
                handle.close()
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('Timed out waiting for batch locks')
            time.sleep(min(0.1, remaining))
            continue
        except BaseException:
            for handle in reversed(held):
                handle.close()
            raise
        try:
            yield
        finally:
            for handle in reversed(held):
                handle.close()
        return


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lock', action='append', required=True)
    parser.add_argument('--timeout', type=float, default=55)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command or not math.isfinite(args.timeout) or args.timeout < 0:
        parser.error('Supply a command and a finite nonnegative timeout')
    try:
        with acquire(args.lock, args.timeout):
            print('Acquired batch locks: ' + ', '.join(args.lock), flush=True)
            process = subprocess.Popen(command, start_new_session=True)
            def forward(signum, frame):
                try:
                    os.killpg(process.pid, signum)
                except ProcessLookupError:
                    pass
            previous = {s: signal.signal(s, forward) for s in (signal.SIGTERM, signal.SIGINT)}
            try:
                result = process.wait()
            finally:
                for sig, handler in previous.items():
                    signal.signal(sig, handler)
            return result if result >= 0 else 128 - result
    except TimeoutError as error:
        print(str(error), file=sys.stderr)
        return 75


if __name__ == '__main__':
    raise SystemExit(main())
