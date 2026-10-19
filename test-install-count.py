from datetime import datetime, timezone
import json
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent
SCRIPT = ROOT / 'update-install-count.py'
snapshot = runpy.run_path(str(SCRIPT))['snapshot']
HTML = (ROOT / 'index.html').read_text()
COUNTED_AT = datetime(2026, 10, 19, 23, 0, tzinfo=timezone.utc)


class InstallCountTests(unittest.TestCase):
    def test_packages_and_kst_date_rollover(self):
        assets = [dict(name=name, download_count=count) for name, count in (
            ('flowmux.deb', 32), ('flowmux.tar.gz', 63), ('flowmux.dmg', 1000),
            ('flowmux.deb.sha256', 78), ('overview.png', 2),
        )]
        html = snapshot(HTML, assets, COUNTED_AT)
        self.assertIn('<strong id="install-count">1,095</strong>', html)
        self.assertIn('datetime="2026-10-20T08:00:00+09:00">2026-10-20 08:00 KST</time>', html)

    def test_rejects_invalid_counts(self):
        for count in (-1, 1.5, True, '5', None):
            with self.subTest(count=count), self.assertRaises(ValueError):
                snapshot(HTML, [dict(name='flowmux.deb', download_count=count)], COUNTED_AT)

    def test_zero_downloads_are_valid_when_program_assets_exist(self):
        html = snapshot(HTML, [dict(name='flowmux.deb', download_count=0)], COUNTED_AT)
        self.assertIn('<strong id="install-count">0</strong>', html)

    def test_missing_or_duplicate_markers(self):
        assets = [dict(name='flowmux.deb', download_count=0)]
        for marker in ('install-count', 'install-count-updated'):
            with self.subTest(marker=marker), self.assertRaises(ValueError):
                snapshot(HTML.replace(f'id="{marker}"', 'id="missing"'), assets, COUNTED_AT)
        with self.assertRaises(ValueError):
            snapshot(HTML + HTML, assets, COUNTED_AT)

    def test_invalid_input_leaves_previous_snapshot_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            page = root / 'index.html'
            previous = snapshot(HTML, [dict(name='flowmux.deb', download_count=144)], COUNTED_AT)
            payloads = ('', 'not json', json.dumps(dict(name='flowmux.deb', download_count=-1)),
                        json.dumps(dict(name='flowmux.deb.sha256', download_count=1)),
                        json.dumps(dict(name='flowmux.deb')), json.dumps(dict(download_count=1)))
            for payload in payloads:
                with self.subTest(payload=payload):
                    page.write_text(previous)
                    assets = root / 'assets.jsonl'
                    assets.write_text(payload)
                    result = subprocess.run([sys.executable, str(SCRIPT), str(assets), str(page)], capture_output=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(page.read_text(), previous)


if __name__ == '__main__':
    unittest.main()
