#!/usr/bin/env python3
"""Run a Chromium build so it does not disturb anything else on this machine.

    paced-build.py --log FILE -- ninja -C out/Brk -j 6 chrome

The build command runs at low priority. Two things pause it, by sending SIGSTOP to the build tool only (its running
compilers finish what they are doing, no new ones start) and SIGCONT once the reason is gone:

- someone holds /tmp/brk-core-native.lock. Other agents' native checks are timing-sensitive. This script never takes
  that lock for more than the instant of a probe, and never waits in its queue.
- the machine is short of memory (memory_pressure reports less than --min-free-percent free, or swap is growing fast).

It writes one line per state change to the log and refreshes a status file next to the log, so an unattended build can
be read later. It survives the shell that started it (start it with nohup). Exit status is the build's.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

NATIVE_LOCK = '/tmp/brk-core-native.lock'
HOLDER_RECORD = Path('/tmp/brk-lock-queue/holder-brk-core-native.lock.json')
POLL_SECONDS = 2.0


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def native_lock_holder():
    """A description of who holds the native lock, or None when it is free."""
    try:
        record = json.loads(HOLDER_RECORD.read_text())
        if alive(record.get('pid', -1)):
            return f"pid {record['pid']}: {' '.join(record.get('command', []))[:80]}"
    except (OSError, ValueError):
        pass
    # A holder that went round the queue script has no record. A shared-lock probe taken and dropped at once finds it;
    # a waiter that tries in the same instant retries 0.2 s later, as it does for any busy lock.
    try:
        with open(NATIVE_LOCK, 'a') as handle:
            fcntl.flock(handle, fcntl.LOCK_SH | fcntl.LOCK_NB)
            fcntl.flock(handle, fcntl.LOCK_UN)
    except BlockingIOError:
        return 'unknown holder (no queue record)'
    except OSError:
        return None
    return None


def free_memory_percent():
    try:
        output = subprocess.run(['memory_pressure', '-Q'], capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    match = re.search(r'free percentage:\s*(\d+)%', output)
    return int(match.group(1)) if match else None


def swap_used_mb():
    try:
        output = subprocess.run(['sysctl', '-n', 'vm.swapusage'], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    match = re.search(r'used = ([0-9.]+)M', output)
    return float(match.group(1)) if match else None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--log', required=True)
    parser.add_argument('--min-free-percent', type=int, default=12)
    parser.add_argument('--resume-free-percent', type=int, default=22)
    parser.add_argument('--swap-growth-mb-per-min', type=float, default=1500)
    parser.add_argument('--nice', type=int, default=15)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('Give the build command after --')

    log_path = Path(args.log)
    state_path = log_path.with_suffix('.pace.json')
    pace_log = log_path.with_suffix('.pace.log')

    def note(message):
        with pace_log.open('a') as handle:
            handle.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}\n")

    with log_path.open('ab') as out:
        process = subprocess.Popen(['nice', '-n', str(args.nice)] + command, stdout=out, stderr=subprocess.STDOUT,
                                   start_new_session=True)
    note(f'started pid {process.pid}: {" ".join(command)}')

    # `nice` execs the build tool, so process.pid is the tool itself: signals reach it alone, never its compilers.
    def forward(signum, frame):
        try:
            os.kill(process.pid, signal.SIGCONT)
            os.killpg(process.pid, signum)
        except ProcessLookupError:
            pass
    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, forward)

    paused_for = None
    paused_seconds = 0.0
    started = time.time()
    last_memory_check = 0.0
    memory_short = False
    swap_samples = []

    while True:
        code = process.poll()
        if code is not None:
            break
        now = time.time()
        if now - last_memory_check >= 20:
            last_memory_check = now
            free = free_memory_percent()
            swap = swap_used_mb()
            if swap is not None:
                swap_samples.append((now, swap))
                swap_samples = [s for s in swap_samples if now - s[0] <= 120]
            growth = 0.0
            if len(swap_samples) >= 2 and swap_samples[-1][0] > swap_samples[0][0]:
                growth = (swap_samples[-1][1] - swap_samples[0][1]) / ((swap_samples[-1][0] - swap_samples[0][0]) / 60)
            if free is not None:
                if memory_short:
                    memory_short = free < args.resume_free_percent
                else:
                    memory_short = free < args.min_free_percent or growth > args.swap_growth_mb_per_min
            state_path.write_text(json.dumps(dict(pid=process.pid, paused=paused_for, freePercent=free, swapMB=swap,
                                                  swapGrowthMBPerMinute=round(growth), pausedSeconds=round(paused_seconds),
                                                  elapsedSeconds=round(now - started), updated=time.strftime('%F %T'))))
        holder = native_lock_holder()
        reason = f'native lock held by {holder}' if holder else ('memory short' if memory_short else None)
        if reason and not paused_for:
            os.kill(process.pid, signal.SIGSTOP)
            paused_for = reason
            paused_at = now
            note(f'paused: {reason}')
        elif not reason and paused_for:
            os.kill(process.pid, signal.SIGCONT)
            paused_seconds += now - paused_at
            note(f'resumed after {now - paused_at:.0f} s ({paused_for})')
            paused_for = None
        time.sleep(POLL_SECONDS)

    total = time.time() - started
    note(f'finished exit {code}; {total:.0f} s total, {paused_seconds:.0f} s paused')
    state_path.write_text(json.dumps(dict(pid=process.pid, exit=code, elapsedSeconds=round(total), pausedSeconds=round(paused_seconds), updated=time.strftime('%F %T'))))
    return code if code >= 0 else 128 - code


if __name__ == '__main__':
    sys.exit(main())
