#!/usr/bin/env python3
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('photo_gallery', ROOT / 'scripts' / 'build-photo-gallery.py')
gallery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gallery)


class PhotoGalleryTests(unittest.TestCase):
    def test_only_public_records_and_allowlisted_fields_leave_machine(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder) / 'input'; directory.mkdir()
            data = (ROOT / 'Resources' / 'QQStickers' / 'neutral.png').read_bytes()
            (directory / 'test.png').write_bytes(data)
            record = dict(id='fixture', title='hello', emotion='neutral', context='greeting', author='fixture',
                license='CC0-1.0', source='https://example.com/art', file='test.png',
                sha256=hashlib.sha256(data).hexdigest(), publicSharing=True, character='deepseek-whale-maid', privateNote='must not export')
            private = dict(record, id='private', publicSharing=False)
            (directory / 'manifest.json').write_text(json.dumps([private, record]))
            output = Path(folder) / 'output'
            self.assertEqual(gallery.export(output, [directory]), 1)
            exported = json.loads((output / 'stickers.json').read_text())
            self.assertEqual(len(exported), 1)
            self.assertNotIn('privateNote', exported[0])
            with zipfile.ZipFile(output / 'stickers.zip') as archive:
                self.assertNotIn('manifest.json', archive.namelist())
                self.assertIn('CREDITS.txt', archive.namelist())
                self.assertEqual(archive.read(exported[0]['file']), data)
            with self.assertRaises(ValueError):
                gallery.export(output, [directory])

    def test_tampering_traversal_symlinks_and_secret_sources_fail_closed(self):
        for invalid in ('hash', 'traversal', 'symlink', 'source', 'character'):
            with self.subTest(invalid=invalid), tempfile.TemporaryDirectory() as folder:
                directory = Path(folder) / 'input'; directory.mkdir()
                data = b'test image fixture'
                (directory / 'test.png').write_bytes(data)
                record = dict(id='fixture', title='hello', emotion='joy', context='greeting', author='fixture',
                    license='CC0-1.0', source='https://example.com/art', file='test.png',
                    sha256=hashlib.sha256(data).hexdigest(), publicSharing=True, character='deepseek-whale-maid')
                if invalid == 'hash': record['sha256'] = '0' * 64
                if invalid == 'traversal': record['file'] = '../test.png'
                if invalid == 'source': record['source'] = 'https://example.com/art?token=synthetic'
                if invalid == 'character': record['character'] = 'unrelated-character'
                if invalid == 'symlink':
                    (directory / 'link.png').symlink_to(directory / 'test.png'); record['file'] = 'link.png'
                (directory / 'manifest.json').write_text(json.dumps([record]))
                output = Path(folder) / 'output'
                with self.assertRaises(ValueError): gallery.export(output, [directory])
                self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
