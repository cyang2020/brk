#!/usr/bin/env python3
"""Download and verify the exact BrkCore archive recorded in artifacts.json (used by CI)."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('arch', choices=['arm64', 'x86_64'])
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
lock = root / 'engine/artifacts.json'
if not lock.is_file():
    p.error('No release engine pinned yet; finish and upload both release builds before enabling CI')
spec = json.loads(lock.read_text())
record = spec['artifacts'][a.arch]
if hashlib.sha256((root / 'Sources/CBrkCore/include/BrkCore.h').read_bytes()).hexdigest() != record['interfaceSHA256']:
    p.error('Pinned engine does not match the checked-in interface; build and pin a new engine')
if a.out.exists():
    p.error('Extraction destination already exists: ' + str(a.out))
with tempfile.TemporaryDirectory(prefix='brkcore-download-') as tmp:
    stage = Path(tmp)
    subprocess.run(['gh', 'release', 'download', spec['release'], '--repo', spec['repository'],
                    '--pattern', record['file'], '--dir', str(stage)], check=True)
    archive = stage / record['file']
    with archive.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest != record['sha256']:
        p.error('BrkCore checksum mismatch')
    a.out.mkdir(parents=True)
    with tarfile.open(archive) as tar:
        tar.extractall(a.out, filter='data')
    metadata = json.loads((a.out / 'metadata.json').read_text())
    for key in ('architecture', 'chromiumCommit', 'interfaceSHA256'):
        if metadata[key] != record[key]:
            p.error('Engine metadata mismatch: ' + key)
print(a.out.resolve())
