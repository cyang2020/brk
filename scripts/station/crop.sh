#!/bin/zsh
# usage: crop.sh <in.png> <out.png> <x_pt> <y_pt> <w_pt> <h_pt>   (window-point rectangle, 2x pixels)
python3 - "$@" <<'PY'
import sys, subprocess
i, o, x, y, w, h = sys.argv[1:7]
x, y, w, h = [int(float(v) * 2) for v in (x, y, w, h)]
subprocess.run(['sips', '-c', str(h), str(w), '--cropOffset', str(y), str(x), i, '--out', o], check=True, capture_output=True)
print(o)
PY
