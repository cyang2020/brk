#!/usr/bin/env python3
"""Package a completed release engine. Prints the SHA-256 record to pin in artifacts.json."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--build', type=Path, required=True)
p.add_argument('--arch', choices=['arm64', 'x86_64'], required=True)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
a.build = a.build.resolve()
args = (a.build / 'args.gn').read_text()
if 'is_official_build = true' not in args:
    p.error('Only an official release build may be packaged for distribution')
source = a.build.parents[1]
ninja = source / 'third_party/ninja/ninja'
check = subprocess.run([str(ninja), '-C', str(a.build), '-n', 'chrome'], capture_output=True, text=True, check=True)
if 'no work to do.' not in check.stdout:
    p.error('The engine has pending build steps; finish building before packaging')
if subprocess.check_output(['git', 'status', '--porcelain'], cwd=source, text=True).strip():
    p.error('Commit the Chromium patch changes before packaging')
root = Path(__file__).resolve().parents[1]
header = root / 'Sources/CBrkCore/include/BrkCore.h'
if header.read_bytes() != (source / 'brk/public/BrkCore.h').read_bytes():
    p.error('The Chromium public interface is not synchronized with the app header')
metadata = dict(architecture=a.arch,
                chromiumCommit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip(),
                interfaceSHA256=hashlib.sha256(header.read_bytes()).hexdigest())
a.out.mkdir(parents=True, exist_ok=True)
archive = a.out / ('BrkCore-' + a.arch + '.tar.xz')
if archive.exists():
    p.error('Output already exists: ' + str(archive))
with tempfile.TemporaryDirectory(prefix='brkcore-package-') as tmp:
    stage = Path(tmp)
    for name in ('BrkCore.framework', 'libBrkCoreEarly.dylib'):
        subprocess.run(['cp', '-cR', str(a.build / name), str(stage / name)], check=True)
    for binary in (stage / 'BrkCore.framework/BrkCore', stage / 'libBrkCoreEarly.dylib'):
        subprocess.run(['lipo', str(binary), '-verify_arch', a.arch], check=True)
    shutil.copy2(source / 'LICENSE', stage / 'LICENSE')
    (stage / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    subprocess.run(['tar', '-cJf', str(archive.resolve()), '-C', str(stage), '.'], check=True)
with archive.open('rb') as stream:
    digest = hashlib.file_digest(stream, 'sha256').hexdigest()
print(json.dumps(dict(file=archive.name, sha256=digest, **metadata), indent=2))
