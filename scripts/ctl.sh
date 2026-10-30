#!/bin/bash
# Sends one control request to a running app and prints the reply line (debugging; the runner uses BrkControl).
# The wire format is BrkControl/Protocol.swift's Codable: each op is {"<case>": {<labelled values>}}, unlabelled
# associated values are "_0", optional ones may be left out.
#
#   BRK_CONTROL_SOCKET=/tmp/brk.sock BRK_ENGINE=stub swift run Brk &
#   scripts/ctl.sh /tmp/brk.sock '{"id":1,"op":{"hello":{}}}'
#   scripts/ctl.sh /tmp/brk.sock '{"id":2,"op":{"press":{"chord":"cmd+t"}}}'
#   scripts/ctl.sh /tmp/brk.sock '{"id":3,"op":{"native":{}}}'
#   scripts/ctl.sh /tmp/brk.sock '{"id":4,"op":{"screenshot":{"path":"/tmp/brk.png"}}}'
#   scripts/ctl.sh /tmp/brk.sock '{"id":5,"op":{"dispatch":{"command":{"sidebar":{"_0":{"toggle":{}}}}}}}'
set -euo pipefail
sock="${1:?usage: ctl.sh <socket> '<json request>'}"; shift
exec /usr/bin/env python3 -I -c '
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(60); s.connect(sys.argv[1])
s.sendall((sys.argv[2] + "\n").encode())
buf = b""
while not buf.endswith(b"\n"):
    chunk = s.recv(65536)
    if not chunk: break
    buf += chunk
if not buf:
    sys.exit("ctl.sh: no reply (the app closed the connection)")
sys.stdout.write(buf.decode(errors="replace"))
' "$sock" "$1"
