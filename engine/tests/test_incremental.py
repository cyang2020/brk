"""Exercise the build entry point with real Ninja and C++ compilation."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


ENGINE = Path(__file__).resolve().parents[1]


class IncrementalBuildTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='brk-incremental-')
        self.root = Path(self.temporary.name)
        self.repo = self.root / 'repo'
        self.engine = self.repo / 'engine'
        self.source = self.root / 'chromium-root/chromium/src'
        self.engine.mkdir(parents=True)
        self.source.mkdir(parents=True)
        for name in ('config.sh', 'configure.sh', 'sync-header.sh', 'incremental.py'):
            shutil.copy2(ENGINE / name, self.engine / name)
        (self.engine / 'args').mkdir()
        (self.engine / 'args/brk.gn').write_text('fixture_offset = 0\n')
        (self.engine / 'args/release.gn').write_text('fixture_offset = 0\nis_official_build = true\n')
        self.header = self.repo / 'Sources/CBrkCore/include/BrkCore.h'
        self.header.parent.mkdir(parents=True)
        self.header.write_text('#define HEADER_VALUE 2\n')
        (self.source / 'main.cc').write_text('#include <cstdio>\n#include "brk/public/BrkCore.h"\nint value();\nint main(){std::printf("%d\\n", value()+HEADER_VALUE+OFFSET);}\n')
        (self.source / 'value.cc').write_text('int value(){return 5;}\n')
        ninja = shutil.which('ninja')
        compiler = shutil.which('clang++')
        if not ninja or not compiler:
            self.skipTest('Requires ninja and clang++ on PATH')
        binary = self.source / 'third_party/ninja/ninja'
        binary.parent.mkdir(parents=True)
        binary.symlink_to(ninja)
        depot = self.root / 'chromium-root/depot_tools'
        depot.mkdir()
        self.executable(depot / 'gn', '''#!/usr/bin/env python3
from pathlib import Path
import re,sys
out=Path(sys.argv[2]); args=(out/'args.gn').read_text()
calls=Path('configure-calls'); calls.write_text(calls.read_text()+'gen\\n' if calls.exists() else 'gen\\n')
if Path('fail-gn').exists(): sys.exit(1)
offset=re.search(r'fixture_offset = (\\d+)',args).group(1)
compiler=Path('compiler-path').read_text().strip()
manifest=f"""rule compile
  command = {compiler} -MMD -MF $out.d -DOFFSET={offset} -I../.. -c $in -o $out
  depfile = $out.d
  deps = gcc
rule link
  command = {compiler} $in -o $out
rule hold
  command = python3 ../../hold.py
build main.o: compile ../../main.cc
build value.o: compile ../../value.cc
build app: link main.o value.o
build chrome: phony app
build hold: hold
default chrome
"""
(out/'build.ninja').write_text(manifest)
''')
        (self.source / 'compiler-path').write_text(compiler)
        self.executable(self.engine / 'build.sh', '''#!/bin/bash
source "$(dirname "$0")/config.sh"
cd "$BRK_SRC"
exec "$BRK_SRC/third_party/ninja/ninja" -C "$BRK_OUT" "$1"
''')
        for relative in ('tools/update_pgo_profiles.py', 'v8/tools/builtins-pgo/download_profiles.py'):
            path = self.source / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("from pathlib import Path\np=Path('profile-calls'); p.write_text(p.read_text()+'fetch\\n' if p.exists() else 'fetch\\n')\n")
        self.environment = dict(os.environ, BRK_CHROMIUM_ROOT=str(self.root / 'chromium-root'))

    def tearDown(self):
        self.temporary.cleanup()

    @staticmethod
    def executable(path, text):
        path.write_text(text)
        path.chmod(0o755)

    def build(self, *arguments, expected=0):
        result = subprocess.run([sys.executable, str(self.engine / 'incremental.py'), *arguments],
                                env=self.environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def app_value(self, out='Brk'):
        return subprocess.check_output([str(self.source / 'out' / out / 'app')], text=True).strip()

    def modified_times(self):
        out = self.source / 'out/Brk'
        return {name: (out / name).stat().st_mtime_ns
                for name in ('args.gn', 'build.ninja', 'main.o', 'value.o', 'app')}

    def test_second_run_has_no_work_and_preserves_cache(self):
        self.build()
        self.assertEqual(self.app_value(), '7')
        before = self.modified_times()
        result = self.build()
        self.assertIn('no work to do', result.stdout)
        self.assertEqual(self.modified_times(), before)
        self.assertEqual((self.source / 'configure-calls').read_text(), 'gen\n')

    def test_source_edit_rebuilds_only_its_object(self):
        self.build()
        before = self.modified_times()
        (self.source / 'value.cc').write_text('int value(){return 9;}\n')
        self.build()
        self.assertEqual(self.app_value(), '11')
        after = self.modified_times()
        self.assertEqual(after['main.o'], before['main.o'])
        self.assertNotEqual(after['value.o'], before['value.o'])
        self.assertEqual(after['build.ninja'], before['build.ninja'])

    def test_existing_cache_survives_first_configuration_record(self):
        self.build()
        before = self.modified_times()
        (self.source / 'out/Brk/.brk-configured-args.gn').unlink()
        result = self.build()
        self.assertEqual(self.app_value(), '7')
        self.assertIn('no work to do', result.stdout)
        after = self.modified_times()
        for name in ('args.gn', 'main.o', 'value.o', 'app'):
            self.assertEqual(after[name], before[name], name)

    def test_header_edit_rebuilds_its_dependents(self):
        self.build()
        before = self.modified_times()
        self.header.write_text('#define HEADER_VALUE 4\n')
        self.build()
        self.assertEqual(self.app_value(), '9')
        after = self.modified_times()
        self.assertNotEqual(after['main.o'], before['main.o'])
        self.assertEqual(after['value.o'], before['value.o'])

    def test_changed_build_arguments_regenerate_and_retry_after_failure(self):
        self.build()
        (self.engine / 'args/brk.gn').write_text('fixture_offset = 10\n')
        (self.source / 'fail-gn').touch()
        self.build(expected=1)
        (self.source / 'fail-gn').unlink()
        self.build()
        self.assertEqual(self.app_value(), '17')
        self.assertEqual((self.source / 'configure-calls').read_text(), 'gen\ngen\ngen\n')
        self.assertIn('no work to do', self.build().stdout)

    def test_release_uses_separate_cache_and_does_not_refetch_profiles(self):
        self.build()
        before = self.modified_times()
        self.build('--release', 'arm64')
        self.assertEqual(self.app_value('BrkRelease-arm64'), '7')
        self.assertIn('target_cpu = "arm64"', (self.source / 'out/BrkRelease-arm64/args.gn').read_text())
        self.assertIn('no work to do', self.build('--release', 'arm64').stdout)
        self.assertEqual((self.source / 'profile-calls').read_text(), 'fetch\nfetch\n')
        self.assertEqual(self.modified_times(), before)

    def test_running_ninja_is_not_modified_or_stopped(self):
        self.build()
        self.assertEqual(self.app_value(), '7')
        before = self.modified_times()
        (self.source / 'hold.py').write_text("from pathlib import Path\nimport time\nPath('holding').touch()\ntime.sleep(30)\n")
        process = subprocess.Popen([str(self.source / 'third_party/ninja/ninja'), '-C', 'out/Brk', 'hold'],
                                   cwd=self.source, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   start_new_session=True)
        try:
            deadline = time.monotonic() + 5
            while not (self.source / 'out/Brk/holding').exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue((self.source / 'out/Brk/holding').exists())
            self.header.write_text('#define HEADER_VALUE 99\n')
            self.build(expected=75)
            self.assertIsNone(process.poll())
            self.assertEqual(self.modified_times(), before)
            self.assertEqual((self.source / 'brk/public/BrkCore.h').read_text(), '#define HEADER_VALUE 2\n')
        finally:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait()

    def test_new_release_profile_reference_is_fetched(self):
        profile = self.source / 'chrome/build/mac-arm.pgo.txt'
        profile.parent.mkdir(parents=True)
        profile.write_text('first.profdata\n')
        self.build('--release', 'arm64')
        profile.write_text('second.profdata\n')
        self.build('--release', 'arm64')
        self.assertEqual(self.app_value('BrkRelease-arm64'), '7')
        self.assertEqual((self.source / 'profile-calls').read_text(), 'fetch\nfetch\nfetch\nfetch\n')
        self.assertIn('no work to do', self.build('--release', 'arm64').stdout)


if __name__ == '__main__':
    unittest.main()
