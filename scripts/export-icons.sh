#!/bin/bash
# Export all app icon styles and the standalone brand marks.
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT="${1:-artifacts/brk-icon-pack}"
mkdir -p .build "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
swiftc -O -o .build/brk-app-icon scripts/app-icon/main.swift Sources/BrkSettings/AppIconArt.swift
swiftc -O -o .build/brk-icon-verify scripts/app-icon/VerifyIcons.swift Sources/BrkSettings/AppIconArt.swift
.build/brk-app-icon --all "$OUTPUT" "$PWD/Sources/BrkSettings/Resources/AppIcons"
mkdir -p "$OUTPUT/icns" "$OUTPUT/logos"
for ICONSET in "$OUTPUT"/iconsets/*.iconset; do
  VARIANT="$(basename "$ICONSET" .iconset)"
  iconutil -c icns -o "$OUTPUT/icns/$VARIANT.icns" "$ICONSET"
done
cp assets/branding/logo-*.png "$OUTPUT/logos/"
cp "$OUTPUT/png/original/1024.png" assets/icon.png
.build/brk-icon-verify "$OUTPUT"
python3 - "$OUTPUT" <<'PY'
from pathlib import Path
import sys
import zipfile

root = Path(sys.argv[1])
archive = root.parent / (root.name + '.zip')
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as output:
    for path in sorted(root.rglob('*')):
        if path.is_file():
            info = zipfile.ZipInfo(str(Path(root.name) / path.relative_to(root)), (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            output.writestr(info, path.read_bytes())
print(f'Icon pack: {archive}')
PY
