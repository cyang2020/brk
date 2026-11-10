#!/bin/bash
# dis.sh start [len]: disassemble Arc's arm64 slice from a function start (len bytes, default to function size)
A=$1; L=${2:-$(python3 -c "
import sys; sys.path.insert(0,'/tmp/cbr/tools'); from macho import *
print(func_of(int('$A',16))[1])")}
E=$(printf '0x%x' $(( A + L )))
/opt/homebrew/opt/llvm/bin/llvm-objdump -d --no-show-raw-insn --print-imm-hex --start-address=$A --stop-address=$E ${ARC_BIN:-/tmp/cbr/arc} | tail -n +3
