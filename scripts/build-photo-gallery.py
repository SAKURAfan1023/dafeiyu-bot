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
            if item.get('character') != 'deepseek-whale-maid':
                raise ValueError('Photos only accepts reviewed DeepSeek whale-maid images')
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
            record = {key: item.get(key, '') for key in ('id', 'title', 'emotion', 'context', 'source', 'author', 'license', 'sha256', 'character')}
            record['collection'] = item.get('collection') or ('DeepSeek 鲸鱼娘' if item.get('character') == 'deepseek-whale-maid' else '公开素材')
            tags = item.get('tags', ['可爱'])
            if not isinstance(tags, list) or len(tags) > 12 or not all(isinstance(tag, str) and 0 < len(tag) <= 30 for tag in tags):
                raise ValueError('Invalid public tags')
            record['tags'] = tags
            record['bytes'] = len(data)
            record['file'] = 'images/' + digest + path.suffix.lower()
            selected.append((record, data))
    output.mkdir(parents=True)
    (output / 'images').mkdir()
    for name in ('index.html', 'gallery.css', 'gallery.js'):
        shutil.copyfile(ROOT / 'Resources' / 'PhotoGallery' / name, output / name)
    shutil.copyfile(ROOT / 'Resources' / 'QQStickers' / 'neutral.png', output / 'favicon.png')
    records = [record for record, _ in selected]
    credits = ['大肥鱼表情画廊 · 素材与署名', '', '图库只收录 DeepSeek 娘；网页供用户自主挑选，不代表机器人默认安装全部图片。代码许可不覆盖第三方图片。', '请按每张图片标注的作者、来源与许可使用；完整声明见 LICENSES.txt。', 'YunYueSama 图集经过独立帧拆分、透明留白裁剪与无损 WebP 编码，未重绘角色；其他社区图片保留原始文件。', '角色原作：上善无形；DeepSeek 女仆元素二次设计：ZipZipPipe。形象遵循 CC BY-NC-SA 4.0，单图权利以具体声明为准。', '']
    for item, data in selected:
        (output / item['file']).write_bytes(data)
        credits.extend([item['title'], '作者：' + item['author'], '许可：' + item['license'], item['source'], ''])
    (output / 'stickers.json').write_text(json.dumps(records, ensure_ascii=False, indent=2) + '\n')
    (output / 'CREDITS.txt').write_text('\n'.join(credits))
    license_file = ROOT / 'Resources' / 'QQStickers' / 'WHALE-LICENSE.txt'
    if license_file.exists():
        shutil.copyfile(license_file, output / 'WHALE-LICENSE.txt')
    notices = [license_file.read_text()] if license_file.exists() else []
    (output / 'licenses').mkdir()
    for directory in directories:
        license_directory = directory / 'licenses'
        if license_directory.is_symlink():
            raise ValueError('Unsafe license directory')
        for notice in license_directory.glob('*.txt'):
            if notice.is_symlink() or not notice.is_file() or notice.stat().st_size > 100_000:
                raise ValueError('Unsafe license file')
            destination = output / 'licenses' / notice.name
            if destination.exists() and destination.read_bytes() != notice.read_bytes():
                raise ValueError('Conflicting license names')
            shutil.copyfile(notice, destination)
            notices.append(notice.name + '\n\n' + notice.read_text())
    (output / 'LICENSES.txt').write_text('\n\n'.join(notices))
    with zipfile.ZipFile(output / 'stickers.zip', 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for item, _ in selected:
            archive.write(output / item['file'], item['file'])
        for name in ('stickers.json', 'CREDITS.txt', 'WHALE-LICENSE.txt', 'LICENSES.txt'):
            if (output / name).exists():
                archive.write(output / name, name)
    return len(records)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--include-local', type=Path, action='append', default=[], help='Explicitly include reviewed local catalogs; entries still need publicSharing=true and attribution')
    args = parser.parse_args()
    print('Exported public images:', export(args.output, [ROOT / 'Resources' / 'QQStickers', ROOT / 'Resources' / 'PhotoStickers'] + args.include_local))
