#!/usr/bin/env python3
"""Export only explicitly shareable catalog entries, never runtime state or credentials."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
from urllib.parse import urlsplit
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EMOTIONS = {'neutral', 'joy', 'smug', 'annoyed', 'sad', 'sleepy', 'flustered', 'teasing'}


def export(output, directories):
    if output.exists():
        raise ValueError('Output must be a new directory; refusing to mix with an old release')
    selected, hashes, ids = [], set(), set()
    for directory in directories:
        manifest = directory / 'manifest.json'
        if manifest.is_symlink() or directory.is_symlink() or manifest.stat().st_size > 1_000_000:
            raise ValueError('Unsafe catalog')
        items = json.loads(manifest.read_text())
        if not isinstance(items, list) or len(items) > 500:
            raise ValueError('Invalid catalog')
        for item in items:
            if item.get('publicSharing') is not True:
                continue
            digest, name = item['sha256'], item['file']
            if not re.fullmatch('[a-f0-9]{64}', digest) or Path(name).name != name:
                raise ValueError('Unsafe image identity')
            path = directory / name
            if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= 3_000_000:
                raise ValueError('Unsafe image')
            if path.suffix.lower() not in {'.png', '.jpg', '.jpeg', '.webp'}:
                raise ValueError('Unsupported image type')
            data = path.read_bytes()
            if hashlib.sha256(data).hexdigest() != digest:
                raise ValueError('Image hash mismatch')
            source = urlsplit(item.get('source', ''))
            if source.scheme != 'https' or not source.hostname or source.username or source.password or source.query or source.fragment:
                raise ValueError('A public HTTPS source without credentials or query is required')
            if not item.get('author') or not item.get('license') or item.get('emotion') not in EMOTIONS:
                raise ValueError('Missing attribution, license or emotion')
            if digest in hashes:
                continue
            if item['id'] in ids:
                raise ValueError('Duplicate catalog ID')
            hashes.add(digest); ids.add(item['id'])
            record = {key: item.get(key, '') for key in ('id', 'title', 'emotion', 'context', 'source', 'author', 'license', 'sha256')}
            record['file'] = 'images/' + digest + path.suffix.lower()
            selected.append((record, data))
    output.mkdir(parents=True)
    (output / 'images').mkdir()
    for name in ('index.html', 'gallery.css', 'gallery.js'):
        shutil.copyfile(ROOT / 'Resources' / 'PhotoGallery' / name, output / name)
    shutil.copyfile(ROOT / 'Resources' / 'QQStickers' / 'neutral.png', output / 'favicon.png')
    records = [record for record, _ in selected]
    credits = ['大肥鱼表情画廊 · 素材与署名', '', '代码许可不覆盖第三方图片。请按每张图片标注的许可使用。', 'Pysio Chibi：署名-非商业-相同方式共享 4.0，https://creativecommons.org/licenses/by-nc-sa/4.0/', '图片保留原文件，不裁剪、不去水印。仅为检索补充中文标题与情境说明。', '']
    for item, data in selected:
        (output / item['file']).write_bytes(data)
        credits.extend([item['title'], '作者：' + item['author'], '许可：' + item['license'], item['source'], ''])
    (output / 'stickers.json').write_text(json.dumps(records, ensure_ascii=False, indent=2) + '\n')
    (output / 'CREDITS.txt').write_text('\n'.join(credits))
    license_file = ROOT / 'Resources' / 'QQStickers' / 'PYSIO-LICENSE.txt'
    if license_file.exists():
        shutil.copyfile(license_file, output / 'PYSIO-LICENSE.txt')
    with zipfile.ZipFile(output / 'stickers.zip', 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for item, _ in selected:
            archive.write(output / item['file'], item['file'])
        for name in ('stickers.json', 'CREDITS.txt', 'PYSIO-LICENSE.txt'):
            if (output / name).exists():
                archive.write(output / name, name)
    return len(records)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--include-local', type=Path, action='append', default=[], help='Explicitly include reviewed local catalogs; entries still need publicSharing=true and attribution')
    args = parser.parse_args()
    print('Exported public images:', export(args.output, [ROOT / 'Resources' / 'QQStickers'] + args.include_local))
