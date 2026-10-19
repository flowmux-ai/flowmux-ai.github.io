from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import re
import sys


def snapshot(html, assets, counted_at):
    counts = []
    for asset in assets:
        if not re.search(r'\.(?:deb|rpm|dmg|pkg|msi|exe|AppImage|zip|tar\.(?:gz|xz|zst))$', asset['name'], re.I):
            continue
        count = asset['download_count']
        if type(count) is not int or count < 0:
            raise ValueError('Invalid download count')
        counts.append(count)
    if not counts:
        raise ValueError('No program download assets returned')
    counted_at = counted_at.astimezone(timezone(timedelta(hours=9)))
    replacements = (
        (r'<strong id="install-count"[^>]*>[^<]*</strong>',
         f'<strong id="install-count">{sum(counts):,}</strong>'),
        (r'<time id="install-count-updated"[^>]*>[^<]*</time>',
         f'<time id="install-count-updated" datetime="{counted_at.isoformat(timespec="seconds")}">{counted_at:%Y-%m-%d %H:%M} KST</time>'),
    )
    for pattern, replacement in replacements:
        html, changed = re.subn(pattern, lambda _: replacement, html)
        if changed != 1:
            raise ValueError('Install count and timestamp must each appear exactly once')
    return html


if __name__ == '__main__':
    assets_path, html_path = map(Path, sys.argv[1:])
    assets = [json.loads(line) for line in assets_path.read_text().splitlines()]
    html_path.write_text(snapshot(html_path.read_text(), assets, datetime.now(timezone.utc)))
