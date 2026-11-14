"""Release boundaries that prevent broken notes, downgrades, and overwritten versions."""
import base64
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release

ROOT = Path(__file__).resolve().parents[2]


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'releases').mkdir()
        self.write_release('0.0.1', '- Downloads keep their progress.\n- Keep <web> & colors safe.')
        (self.root / 'VERSION').write_text('0.0.1\n')

    def write_release(self, version, text):
        (self.root / 'releases' / (version + '.md')).write_text('# Brk ' + version + '\n\n' + text)

    def cli(self, *args):
        return subprocess.run([sys.executable, str(ROOT / 'scripts/release.py'), '--root', str(self.root), *args],
                              capture_output=True, text=True)

    def test_invalid_or_missing_release_authority_stops_before_output(self):
        self.assertNotEqual(self.cli('validate', '--tag', 'v0.0.2').returncode, 0)
        for version in ('00.0.1', '0.1', '../0.0.1', '0.0.1-beta'):
            with self.subTest(version=version):
                (self.root / 'VERSION').write_text(version)
                result = self.cli('version')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, '')
        (self.root / 'VERSION').write_text('0.0.1')
        for notes in ('', '# Brk 0.0.1\n\n## Fixes', '# Brk 0.0.1\n\n- ', '# Brk 0.0.2\n\n- Fix downloads.'):
            (self.root / 'releases/0.0.1.md').write_text(notes)
            self.assertNotEqual(self.cli('validate').returncode, 0)
        (self.root / 'releases/0.0.1.md').unlink()
        self.assertNotEqual(self.cli('validate').returncode, 0)

    def test_github_and_help_keep_curated_changes_and_sorted_version_history(self):
        current = release.Release.load(self.root)
        markdown = current.markdown(True, '43', 'abc1234')
        self.assertIn(current.notes, markdown)
        self.write_release('0.0.0', '- Older release stays available offline.')
        self.write_release('0.0.2', '- Future release must stay hidden.')
        page = release.history_html(self.root, current, True)
        self.assertIn('Downloads keep their progress.', page)
        self.assertIn('Keep &lt;web&gt; &amp; colors safe.', page)
        self.assertLess(page.index('id="v0.0.1"'), page.index('id="v0.0.0"'))
        self.assertNotIn('Future release', page)

    def test_appcast_uses_monotonic_build_and_signed_immutable_architecture_assets(self):
        current = release.Release.load(self.root)
        ns = {'sparkle': release.SPARKLE}
        signature = base64.b64encode(bytes(range(64))).decode()
        for arch in ('arm64', 'x86_64'):
            with self.subTest(arch=arch):
                archive = self.root / ('Brk-' + arch + '.dmg')
                archive.write_bytes(b'final stapled archive')
                xml = release.appcast(current, 'owner/repo', arch, '43', archive, signature,
                                      datetime.now(timezone.utc))
                item = ET.fromstring(xml).find('./channel/item')
                self.assertGreater(int(item.findtext('sparkle:version', namespaces=ns)), 42)
                self.assertEqual(item.findtext('sparkle:shortVersionString', namespaces=ns), '0.0.1')
                self.assertEqual(item.find('enclosure').get('url'),
                                 'https://github.com/owner/repo/releases/download/v0.0.1/' + archive.name)
                self.assertEqual(item.find('enclosure').get('length'), str(archive.stat().st_size))
                self.assertEqual(item.find('enclosure').get('{' + release.SPARKLE + '}edSignature'), signature)
                self.assertIn('/v0.0.1/release-notes.html', item.findtext('sparkle:releaseNotesLink', namespaces=ns))
                for invalid in ('', base64.b64encode(b'short').decode(), 'not base64'):
                    with self.assertRaises(ValueError):
                        release.appcast(current, 'owner/repo', arch, '43', archive, invalid, datetime.now(timezone.utc))
        with self.assertRaises(ValueError):
            release.build_number('0')

    def test_published_version_cannot_be_reused_for_another_commit(self):
        ref = {'object': {'type': 'commit', 'sha': 'one'}}
        with patch.object(release, 'github_json', side_effect=[ref, {'draft': False}]):
            self.assertTrue(release.published_release('owner/repo', '0.0.1', 'one'))
        with patch.object(release, 'github_json', side_effect=[ref, {'draft': False}]):
            with self.assertRaisesRegex(ValueError, 'different code'):
                release.published_release('owner/repo', '0.0.1', 'two')
        with patch.object(release, 'github_json', side_effect=[ref, {'draft': True}]):
            self.assertFalse(release.published_release('owner/repo', '0.0.1', 'one'))
        with patch.object(release, 'github_json', side_effect=[None, None]):
            self.assertFalse(release.published_release('owner/repo', '0.0.1', 'one'))
        with patch.object(release, 'github_json', side_effect=[{'object': {'type': 'tag', 'sha': 'tag'}},
                                                             {'draft': False}, {'object': ref['object']}]):
            self.assertTrue(release.published_release('owner/repo', '0.0.1', 'one'))
        with patch.object(subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'HTTP 403')):
            with self.assertRaisesRegex(ValueError, 'preflight failed'):
                release.github_json('owner/repo', 'releases/tags/v0.0.1')

    def test_actual_publisher_orders_assets_and_never_overwrites_a_public_version(self):
        workflow = (ROOT / '.github/workflows/release.yml').read_text()
        publisher = textwrap.dedent(workflow.split("python3 - <<'PUBLISH'\n")[1].split('          PUBLISH')[0])
        out = self.root / 'out'
        out.mkdir()
        (out / 'release.json').write_text(json.dumps({'version': '0.0.1', 'build': 43, 'commit': 'one', 'signed': True}))
        for name in ('notes.md', 'release-notes.html'):
            (out / name).write_text('Curated notes')
        current = release.Release.load(self.root)
        for arch in ('arm64', 'x86_64'):
            archive = out / ('Brk-' + arch + '.dmg')
            archive.write_bytes(b'signed archive fixture')
            (out / ('appcast-' + arch + '.xml')).write_text(release.appcast(
                current, 'owner/repo', arch, '43', archive, base64.b64encode(bytes(64)).decode(), datetime.now(timezone.utc)))

        def run_publisher(kind, published, target='one', latest_build=None):
            calls = []
            def fake_run(command, **kwargs):
                calls.append(command)
                result = {}
                if command[1] == 'api':
                    endpoint = command[2].removeprefix('repos/owner/repo/')
                    if endpoint == 'git/ref/tags/v0.0.1':
                        result = {'object': {'type': 'commit', 'sha': target}}
                    elif endpoint == 'releases/tags/v0.0.1':
                        if not published:
                            return subprocess.CompletedProcess(command, 1, '', 'HTTP 404')
                        result = {'draft': False}
                    elif endpoint == 'releases/tags/latest' and latest_build is not None:
                        result = {'assets': [{'name': 'release.json'}]}
                    elif endpoint in ('releases/tags/latest', 'git/ref/tags/latest'):
                        return subprocess.CompletedProcess(command, 1, '', 'HTTP 404')
                elif command[1:4] == ['release', 'download', 'latest']:
                    (self.root / 'current-release.json').write_text(json.dumps({'build': latest_build}))
                return subprocess.CompletedProcess(command, 0, json.dumps(result), '')
            previous = Path.cwd()
            try:
                os.chdir(self.root)
                with patch.dict(os.environ, {'GH_REPO': 'owner/repo', 'VERSION': '0.0.1', 'GITHUB_SHA': 'one', 'KIND': kind}), \
                     patch.object(subprocess, 'run', side_effect=fake_run):
                    try:
                        exec(compile(publisher, 'release-workflow-publisher', 'exec'), {})
                    except SystemExit as error:
                        if error.code not in (None, 0):
                            raise
            finally:
                os.chdir(previous)
            return calls

        calls = run_publisher('release', False)
        stable = next(i for i, call in enumerate(calls) if call[1:4] == ['release', 'edit', 'v0.0.1'])
        feed = next(i for i, call in enumerate(calls) if call[1:4] == ['release', 'upload', 'latest'])
        self.assertLess(stable, feed)
        self.assertIn('out/appcast-arm64.xml', calls[-1])
        self.assertFalse(any('--clobber' in call and 'v0.0.1' in call for call in calls))
        rerun = run_publisher('existing', True)
        self.assertFalse(any(call[1] == 'release' and 'v0.0.1' in call for call in rerun))
        with self.assertRaisesRegex(SystemExit, 'different code'):
            run_publisher('release', False, target='other')
        with self.assertRaisesRegex(SystemExit, 'became public'):
            run_publisher('release', True)
        older = run_publisher('release', False, latest_build=44)
        stable = next(call for call in older if call[1:4] == ['release', 'edit', 'v0.0.1'])
        self.assertIn('--latest=false', stable)
        self.assertNotIn('--latest', stable)
        self.assertFalse(any(call[1:4] == ['release', 'upload', 'latest'] for call in older))

    @unittest.skipUnless(sys.platform == 'darwin', 'bundle declaration uses macOS PlistBuddy')
    def test_real_bundle_help_and_plist_agree_with_version_authority(self):
        app = self.root / 'Fixture.app'
        contents = app / 'Contents'
        contents.mkdir(parents=True)
        plist = contents / 'Info.plist'
        plist.write_bytes(plistlib.dumps({'CFBundleName': 'Brk', 'CFBundleVersion': '42',
                                         'CFBundleShortVersionString': '0.1.0'}))
        current = release.Release.load(ROOT)
        result = subprocess.run(['bash', str(ROOT / 'scripts/declare-scripting.sh'), str(app)],
                                cwd=ROOT, env={**os.environ, 'BRK_BUILD_NUMBER': '43', 'BRK_VERSION': current.version},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        metadata = plistlib.loads(plist.read_bytes())
        self.assertEqual(metadata['CFBundleShortVersionString'], current.version)
        self.assertEqual(metadata['CFBundleVersion'], '43')
        self.assertIn('<h2>Brk ' + current.version + '</h2>', (contents / 'Resources/Help/release-notes.html').read_text())
        self.assertIn('install this release from the disk image once', (contents / 'Resources/Help/release-notes.html').read_text())
        configured = subprocess.run([sys.executable, str(ROOT / 'scripts/release.py'), 'configure-updates',
                                     '--app', str(app), '--arch', 'arm64'], capture_output=True, text=True)
        self.assertEqual(configured.returncode, 0, configured.stderr)
        metadata = plistlib.loads(plist.read_bytes())
        self.assertEqual(metadata['CFBundleVersion'], '43')
        self.assertTrue(metadata['SUFeedURL'].endswith('/appcast-arm64.xml'))
        self.assertEqual(len(base64.b64decode(metadata['SUPublicEDKey'])), 32)
        self.assertTrue(metadata['SUVerifyUpdateBeforeExtraction'])
        self.assertIn('Sparkle updater', (contents / 'Resources/Help/credits.html').read_text())


if __name__ == '__main__':
    unittest.main()
