#!/usr/bin/env python3
"""Run a command once it holds every requested batch lock, waiting in a fair queue.

    python3 scripts/with-batch-locks.py --lock /tmp/brk-core-native.lock --lock /tmp/brk-batch-build.lock -- scripts/build.sh
    python3 scripts/with-batch-locks.py --status

Waiting is dynamic: the command starts the moment the locks are free and it is this process's turn.
Turns are first come, first served through tickets in /tmp/brk-lock-queue, so seven waiters cannot
starve one. While waiting it prints, every 30 seconds, its position, who holds the locks and for how
long. Tickets and holder records of dead processes are cleaned up by whoever notices them; the
operating system releases a dead holder's flock by itself. There is no default give-up time;
`--timeout` is an optional ceiling in seconds after which it exits 75 without running the command.
"""
import argparse
from contextlib import contextmanager
import fcntl
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

QUEUE = Path('/tmp/brk-lock-queue')
REPORT_EVERY = 30.0
POLL = 0.2


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def tickets():
    """Live tickets in queue order; stale ones (dead pids, unreadable) are removed."""
    QUEUE.mkdir(exist_ok=True)
    live = []
    for path in sorted(QUEUE.glob('ticket-*.json')):
        data = read_json(path)
        if not data or not alive(data.get('pid', -1)):
            path.unlink(missing_ok=True)
            continue
        live.append((path, data))
    return live


def holders():
    out = {}
    for path in QUEUE.glob('holder-*.json'):
        data = read_json(path)
        if not data or not alive(data.get('pid', -1)):
            path.unlink(missing_ok=True)
            continue
        out[data['lock']] = data
    return out


def describe(data, now):
    minutes = (now - data['since']) / 60
    cmd = ' '.join(data.get('command', []))[:90]
    return f"pid {data['pid']} for {minutes:.0f} min: {cmd}"


def status():
    now = time.time()
    held = holders()
    if held:
        for lock, data in sorted(held.items()):
            print(f"held   {lock}  {describe(data, now)}")
    else:
        print('held   nothing')
    queue = tickets()
    for i, (_, data) in enumerate(queue, 1):
        waited = (now - data['since']) / 60
        print(f"queue  #{i} waiting {waited:.0f} min for {', '.join(Path(l).name for l in data['locks'])}: pid {data['pid']}: {' '.join(data['command'])[:80]}")
    if not queue:
        print('queue  empty')


@contextmanager
def acquire(paths, timeout, command):
    paths = sorted({str(Path(path).resolve()) for path in paths})
    QUEUE.mkdir(exist_ok=True)
    me = os.getpid()
    started = time.time()
    ticket = QUEUE / f"ticket-{started:017.6f}-{me}.json"
    ticket.write_text(json.dumps(dict(pid=me, since=started, locks=paths, command=command, cwd=os.getcwd())))
    deadline = started + timeout if math.isfinite(timeout) else None
    last_report = 0.0
    held = []
    try:
        while True:
            queue = tickets()
            my_turn = bool(queue) and queue[0][0] == ticket
            if not any(p == ticket for p, _ in queue):  # someone cleaned us up; re-register at the back
                ticket.write_text(json.dumps(dict(pid=me, since=time.time(), locks=paths, command=command, cwd=os.getcwd())))
            if my_turn:
                try:
                    for path in paths:
                        handle = open(path, 'a')
                        held.append(handle)
                        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    for handle in reversed(held):
                        handle.close()
                    held = []
                else:
                    break
            now = time.time()
            if now - last_report >= REPORT_EVERY:
                last_report = now
                position = next((i for i, (p, _) in enumerate(queue, 1) if p == ticket), len(queue))
                owners = holders()
                who = '; '.join(f"{Path(l).name} {describe(d, now)}" for l, d in sorted(owners.items())) or 'nobody (a waiter ahead of you is about to take them)'
                print(f"[locks] waiting {(now - started) / 60:.0f} min, position {position} of {len(queue)}; held by: {who}", flush=True)
            if deadline is not None and now >= deadline:
                raise TimeoutError(f'Gave up after {timeout:.0f} s waiting for batch locks')
            time.sleep(POLL)
        since = time.time()
        for path in paths:
            (QUEUE / f"holder-{Path(path).name}.json").write_text(json.dumps(dict(pid=me, lock=path, since=since, command=command, cwd=os.getcwd())))
        ticket.unlink(missing_ok=True)
        try:
            yield (since - started)
        finally:
            for path in paths:
                record = QUEUE / f"holder-{Path(path).name}.json"
                data = read_json(record)
                if data and data.get('pid') == me:
                    record.unlink(missing_ok=True)
            for handle in reversed(held):
                handle.close()
    finally:
        ticket.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--lock', action='append', default=[])
    parser.add_argument('--timeout', type=float, default=math.inf, help='optional ceiling in seconds; default: wait as long as it takes')
    parser.add_argument('--status', action='store_true', help='print the current holders and queue, then exit')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.status:
        status()
        return 0
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command or not args.lock or math.isnan(args.timeout) or args.timeout < 0:
        parser.error('Supply at least one --lock, a command, and (optionally) a nonnegative timeout')
    try:
        with acquire(args.lock, args.timeout, command) as waited:
            print(f'Acquired batch locks after {waited:.0f} s: ' + ', '.join(args.lock), flush=True)
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
