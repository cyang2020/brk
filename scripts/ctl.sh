#!/bin/bash
# Sends one control request to a running app and prints the reply (debugging; the runner uses BrkControl).
#
#   BRK_CONTROL_SOCKET=/tmp/brk.sock BRK_ENGINE=stub swift run Brk &
#   scripts/ctl.sh /tmp/brk.sock '{"id":1,"op":{"press":{"chord":"cmd+t"}}}'
#   scripts/ctl.sh /tmp/brk.sock '{"id":2,"op":{"view":{}}}'
set -euo pipefail
sock="${1:?usage: ctl.sh <socket> '<json request>'}"; shift
exec /usr/bin/env python3 -I -c '
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(30); s.connect(sys.argv[1])
s.sendall((sys.argv[2] + "\n").encode())
buf = b""
while not buf.endswith(b"\n"):
    chunk = s.recv(65536)
    if not chunk: break
    buf += chunk
sys.stdout.write(buf.decode(errors="replace"))
' "$sock" "$1"
