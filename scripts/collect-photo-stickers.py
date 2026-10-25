#!/usr/bin/env python3
"""Restore reviewed DeepSeek-only Photos originals from the manifest; never scrape new entries."""
import hashlib
import io
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
from urllib.parse import urlsplit
from PIL import Image

DIRECTORY = Path(__file__).resolve().parents[1] / 'Resources' / 'PhotoStickers'


def restore(item):
    url = urlsplit(item['downloadURL'])
    if item.get('character') != 'deepseek-whale-maid' or url.scheme != 'https' or url.hostname not in {'i1.hdslb.com', 'raw.githubusercontent.com'} or url.query or url.fragment or url.username or url.password:
        raise ValueError('Unreviewed image source or character')
    name = item['file']
    if Path(name).name != name or Path(name).suffix not in {'.png', '.webp', '.jpg'}:
        raise ValueError('Unsafe image path')
    result = subprocess.run(['curl', '--fail', '--silent', '--show-error', '--location', '--max-time', '30', '--max-filesize', '3000000', '--referer', 'https://www.bilibili.com/', item['downloadURL']], check=True, capture_output=True)
    data = result.stdout
    if not 0 < len(data) <= 3_000_000 or hashlib.sha256(data).hexdigest() != item['sha256']:
        raise ValueError('Image changed; review the source before updating its hash')
    with Image.open(io.BytesIO(data)) as image:
        if getattr(image, 'n_frames', 1) != 1 or max(image.size) > 4096 or image.width * image.height > 8_000_000:
            raise ValueError('Unsupported static image')
        image.verify()
    (DIRECTORY / name).write_bytes(data)


if __name__ == '__main__':
    records = json.loads((DIRECTORY / 'manifest.json').read_text())
    with ThreadPoolExecutor(max_workers=4) as executor:
        list(executor.map(restore, records))
    print('Restored', len(records), 'reviewed DeepSeek images; bot built-in pack unchanged')
