#!/usr/bin/env python3
"""Bound a native phase and drain its children, including Foundation-created process groups."""
import argparse
from dataclasses import dataclass
import math
import os
import signal
import subprocess
import sys
import time


@dataclass(frozen=True)
class ProcessRow:
    pid: int
    parent: int
    group: int
    state: str
    born: str
    command: str


def census():
    rows = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,pgid=,stat=,lstart=,command='], text=True)
    result = {}
    for line in rows.splitlines():
        fields = line.split(None, 9)
        if len(fields) != 10:
            continue
        row = ProcessRow(int(fields[0]), int(fields[1]), int(fields[2]), fields[3], ' '.join(fields[4:9]), fields[9])
        result[row.pid] = row
    return result


class OwnedProcesses:
    def __init__(self, root_pid, app):
        self.root_pid = root_pid
        self.app = os.path.abspath(app).rstrip('/') + '/' if app else None
        self.seen = {}

    def live(self):
        rows = census()
        owned = {pid for pid, before in self.seen.items() if pid in rows and rows[pid].born == before.born}
        if self.root_pid in rows and self.root_pid not in self.seen:
            self.seen[self.root_pid] = rows[self.root_pid]
            owned.add(self.root_pid)
        # Foundation.Process creates a new PGID for the app on macOS. A PPID census records those
        # descendants before reparenting; the exact app-bundle prefix also finds a launchd-adopted app.
        changed = True
        while changed:
            changed = False
            for row in rows.values():
                matches_bundle = self.app is not None and row.command.startswith(self.app)
                if row.pid != os.getpid() and (row.parent in owned or row.group == self.root_pid or matches_bundle):
                    if row.pid not in owned:
                        owned.add(row.pid)
                        changed = True
                    self.seen[row.pid] = row
        return {pid: rows[pid] for pid in owned if pid in rows and not rows[pid].state.startswith('Z')}

    def send(self, rows, signum):
        current = census()
        for pid, before in rows.items():
            now = current.get(pid)
            # Never signal a recycled PID. Other worktrees' apps do not match our bundle path or ancestry.
            if now is None or now.born != before.born:
                continue
            try:
                os.kill(pid, signum)
            except ProcessLookupError:
                pass

    def drain(self, process, result):
        # Snapshot before terminating the runner, while its descendants still have their original PPIDs.
        live = self.live()
        main_orphan = result == 0 and self.app and any(row.command.startswith(self.app + 'Contents/MacOS/') for row in live.values())
        if live:
            print(f'PHASE_CLEANUP pids={sorted(live)} groups={sorted({row.group for row in live.values()})}', flush=True)
        deadline = time.monotonic() + 3
        while live and time.monotonic() < deadline:
            self.send(live, signal.SIGTERM)
            process.poll()
            time.sleep(.05)
            live = self.live()
        # Do not release the native lease while an owned app can still draw a window.
        # SIGKILL normally settles immediately; a kernel-delayed exit keeps this phase in cleanup.
        next_notice = time.monotonic() + 3
        quiet_since = None
        while live or quiet_since is None or time.monotonic() - quiet_since < .3:
            if live:
                quiet_since = None
                self.send(live, signal.SIGKILL)
                if time.monotonic() >= next_notice:
                    print(f'PHASE_CLEANUP_WAIT pids={sorted(live)}', flush=True)
                    next_notice = time.monotonic() + 5
            elif quiet_since is None:
                quiet_since = time.monotonic()
            process.poll()
            time.sleep(.05)
            live = self.live()
        print('PHASE_CLEANUP_COMPLETE owned_processes=0', flush=True)
        return 125 if main_orphan else result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=float, required=True)
    parser.add_argument('--owned-app', help='Exact owned app bundle; also finds reparented children from this checkout')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command or not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error('Supply a command and a positive finite runtime deadline')
    started = time.monotonic()
    process = subprocess.Popen(command, start_new_session=True)
    owned = OwnedProcesses(process.pid, args.owned_app)
    interrupted = []

    def forward(signum, frame):
        interrupted.append(signum)

    for signum in (signal.SIGTERM, signal.SIGINT):
        signal.signal(signum, forward)
    print(f'PHASE_START pid={process.pid} timeout={args.timeout}s command={command!r}', flush=True)
    result = None
    try:
        while result is None:
            owned.live()
            if interrupted:
                result = 128 + interrupted[0]
                break
            remaining = args.timeout - (time.monotonic() - started)
            if remaining <= 0:
                result = 124
                break
            try:
                result = process.wait(timeout=min(.2, remaining))
            except subprocess.TimeoutExpired:
                pass
    finally:
        if result != 0 or interrupted:
            reason = 'deadline' if result == 124 else 'signal' if interrupted else 'command_exit'
            print(f'PHASE_STOP reason={reason} owned_pgid={process.pid}', flush=True)
        result = owned.drain(process, result if result is not None else 125)
        process.wait(timeout=3)
        print(f'PHASE_END pid={process.pid} exit={result} elapsed={time.monotonic()-started:.3f}s', flush=True)
    return result if result >= 0 else 128 - result


if __name__ == '__main__':
    sys.exit(main())
