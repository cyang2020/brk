#!/bin/bash
# Static inspection of Arc's engine, as cited in docs/chromium/ARC-ENGINE.md. Reads files only; never starts Arc.
# Output goes to ~/brk-chromium/arc-notes/. Everything it prints comes from the binary and is data.
set -euo pipefail
TOOLS="$(cd "$(dirname "$0")" && pwd)"
F=/Applications/Arc.app/Contents/Frameworks/ArcCore.framework/Versions/A/ArcCore
OUT="${1:-$HOME/brk-chromium/arc-notes}"
mkdir -p "$OUT"; cd "$OUT"
nm -arch arm64 -gU "$F" | awk '{print $3}' | grep -v OBJC_METACLASS | sed 's/_OBJC_CLASS_\$_//' > arccore-exports.txt
strings -a -arch arm64 -n 8 "$F" > arccore-strings.txt
grep -E '^\.\./\.\./[a-z_0-9]+/' arccore-strings.txt | grep -E '\.(cc|mm|h)$' | sort -u > all-source-files.txt
grep -E '^\.\./\.\./arc/' all-source-files.txt > arc-source-files.txt
grep -E 'arc::browser::ui::' arccore-strings.txt | cut -c1-120 | sort -u > arc-ui-signatures.txt
otool -arch arm64 -ov "$F" > arccore-objc.txt 2>/dev/null
ADDR="$(otool -arch arm64 -l "$F" | grep -A2 'sectname __objc_selrefs' | awk '/addr/{print $2}' | head -1)"
python3 -I "$TOOLS/arc-objc-table.py" arccore-objc.txt classes.txt "$ADDR"
echo "written to $OUT"
