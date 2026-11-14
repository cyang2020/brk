#!/usr/bin/env python3
"""Assemble the Swift shell and BrkCore, including Chromium's helpers inside its framework."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
from release import Release, build_number, updater_metadata

p = argparse.ArgumentParser(description=__doc__)
for name in ('bin', 'core', 'arch', 'product', 'bundle-id'):
    p.add_argument('--' + name, required=True)
a = p.parse_args()
root = Path(__file__).resolve().parent.parent
release = Release.load(root)
if os.environ.get('BRK_VERSION', release.version) != release.version:
    p.error('BRK_VERSION must agree with VERSION')
build = build_number(os.environ.get('BRK_BUILD_NUMBER', '1'))
bin_dir, core = Path(a.bin), Path(a.core)
framework = core / 'BrkCore.framework'
early = core / 'libBrkCoreEarly.dylib'
for binary in (bin_dir / a.product, framework / 'BrkCore', early):
    subprocess.run(['lipo', str(binary), '-verify_arch', a.arch], check=True)
with (framework / 'Resources/Info.plist').open('rb') as f:
    engine_info = plistlib.load(f)
dest = Path('dist') / (a.product + '.app')
dest.parent.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='brk-bundle-', dir=dest.parent) as tmp:
    app = Path(tmp) / dest.name
    contents = app / 'Contents'
    for folder in ('MacOS', 'Frameworks', 'Resources'):
        (contents / folder).mkdir(parents=True)
    shutil.copy2(bin_dir / a.product, contents / 'MacOS' / a.product)
    subprocess.run(['cp', '-cR', str(framework), str(contents / 'Frameworks')], check=True)
    shutil.copy2(early, contents / 'Frameworks' / early.name)
    for bundle in bin_dir.glob('*.bundle'):
        shutil.copytree(bundle, contents / 'Resources' / bundle.name, symlinks=True)
    info = dict(CFBundleName=a.product, CFBundleDisplayName=a.product, CFBundleExecutable=a.product,
                CFBundleIdentifier=a.bundle_id, CFBundlePackageType='APPL', CFBundleInfoDictionaryVersion='6.0',
                CFBundleShortVersionString=release.version,
                CFBundleVersion=build, LSMinimumSystemVersion='14.0',
                NSHighResolutionCapable=True, NSSupportsAutomaticGraphicsSwitching=True,
                NSPrincipalClass='NSApplication', LSEnvironment={'MallocNanoZone': '0'},
                BrkChromiumVersion=engine_info['CFBundleShortVersionString'], **updater_metadata(root, a.arch))
    with (contents / 'Info.plist').open('wb') as f:
        plistlib.dump(info, f)
    (contents / 'PkgInfo').write_bytes(b'APPL????')
    subprocess.run([sys.executable, str(root / 'scripts/embed-sparkle.py'), str(bin_dir), str(app)], check=True)
    if dest.exists():
        shutil.rmtree(dest)
    app.rename(dest)
print('[bundle]', dest, a.arch, 'BrkCore', engine_info['CFBundleShortVersionString'])
