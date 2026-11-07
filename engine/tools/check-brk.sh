#!/bin/bash
# Compiles brk/ files with the flags of a neighbouring Chromium file, syntax only: a type check while the tree's own build is still running
# and before brk/ is part of the build graph. Generated headers appear as the build goes, so early runs can report them missing.
#   engine/tools/check-brk.sh [file relative to src/brk ...]
source "$(dirname "$0")/../config.sh"
ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
"$ENGINE_DIR/sync-header.sh"
cd "$BRK_SRC/$BRK_OUT_BRK"
template="$(../../third_party/ninja/ninja -t commands -s obj/chrome/browser/ui/ui/browser_native_widget_mac.o)"
files=("$@")
if [ "${#files[@]}" -eq 0 ]; then
  files=($(cd ../../brk && ls browser/*.mm browser/*.cc embedding/*.cc))
fi
status=0
for file in "${files[@]}"; do
  echo "== $file"
  command="$(python3 -I - "$template" "../../brk/$file" <<'PY'
import re, shlex, sys
template, source = sys.argv[1:3]
args = shlex.split(template)
out, skip = [], False
for a in args:
    if skip:
        skip = False
        continue
    if a in ('-MF', '-o', '-c'):
        skip = True
        continue
    if a == '-MMD':
        continue
    out.append(a)
print(shlex.join(out + ['-fsyntax-only', '-ferror-limit=30', '-fno-color-diagnostics', source]))
PY
)"
  output="$(nice -n 15 bash -c "$command" 2>&1)" || status=1
  printf '%s\n' "$output" | { grep -E "error:|fatal error" || true; } | cut -c1-220 | head -40
done
exit $status
