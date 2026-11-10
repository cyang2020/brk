#!/bin/bash
# dec.sh addr...: decompile function starts with Ghidra headless (no analysis) into /tmp/cbr/dec/<addr>.c
printf '%s\n' "$@" > /tmp/cbr/addrs.txt
~/.local/ghidra/ghidra_12.1.4_PUBLIC/support/analyzeHeadless /tmp/cbr/gh arc -process arc -noanalysis -readOnly -scriptPath /tmp/cbr/tools -postScript Dec.java /tmp/cbr/addrs.txt /tmp/cbr/dec 2>&1 | grep -E 'Dec.java>|ERROR' 
