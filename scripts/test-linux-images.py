#!/usr/bin/env python3
"""Synthetic Pillow boundary checks; no real chats, accounts or providers."""
import base64, importlib.util, io, pathlib
from PIL import Image

root = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('image_helper', root / 'Resources/Linux/image-helper.py')
helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)

def encoded(image, format='PNG', **kwargs):
    stream = io.BytesIO(); image.save(stream, format=format, **kwargs)
    return base64.b64encode(stream.getvalue()).decode()

def run(image, mode, **options):
    return helper.process({'image': image, 'mode': mode, 'options': options})

def reject(image, mode, **options):
    try: run(image, mode, **options)
    except Exception: return
    raise AssertionError('Expected rejection')

static = encoded(Image.new('RGBA', (512, 768), (0, 0, 255, 0)))
assert len(run(static, 'frames')) == 1
assert len(run(static, 'sticker')) == 1
assert len(run(static, 'generated')) == 1
assert len(run(static, 'search')) == 1
assert len(run(static, 'artwork', minLongEdge=700, minShortEdge=500)) == 1
reject(static, 'artwork', minLongEdge=1000, minShortEdge=500)
frames = [Image.new('RGB', (80, 60), color) for color in ['red', 'blue', 'green', 'yellow', 'purple', 'white', 'black', 'orange']]
gif = encoded(frames[0], 'GIF', save_all=True, append_images=frames[1:], duration=[30, 2000, 30, 30, 30, 30, 100, 30], loop=0)
assert 2 <= len(run(gif, 'frames', maxFrames=6)) <= 6
assert len(run(gif, 'frames', maxFrames=1)) == 1
reject(gif, 'sticker'); reject(gif, 'generated'); reject(gif, 'artwork', minLongEdge=1, minShortEdge=1)
reject(base64.b64encode(b'not an image').decode(), 'frames')
reject(encoded(Image.new('RGB', (4097, 1))), 'generated')
result = Image.open(io.BytesIO(base64.b64decode(run(static, 'frames')[0])))
assert result.getpixel((0, 0))[0] > 240  # Transparency was composited on white.
assert not result.getexif()
print('PASS: static, GIF sampling/budget, transparency, resolution, oversized dimensions, malformed data, metadata')
