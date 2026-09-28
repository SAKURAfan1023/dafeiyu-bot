#!/usr/bin/env python3
"""Bounded local ImageIO replacement. No network, paths, or image metadata in the protocol."""
import base64, io, json, math, resource, sys, warnings
from PIL import Image, ImageOps


def process(payload):
    mode = payload['mode']
    limits = {'frames': (8_000_000, 12000, 40_000_000), 'artwork': (20_000_000, 12000, 40_000_000),
              'sticker': (3_000_000, 4096, 4096 * 4096), 'generated': (8_000_000, 4096, 8_000_000),
              'search': (3_000_000, 4096, 8_000_000)}
    byte_limit, edge, pixels = limits[mode]
    raw = base64.b64decode(payload['image'], validate=True)
    if len(raw) > byte_limit:
        raise ValueError('size')
    image = Image.open(io.BytesIO(raw))
    width, height = image.size
    count = getattr(image, 'n_frames', 1)
    if not (1 <= width <= edge and 1 <= height <= edge and width * height <= pixels and 1 <= count <= 1000):
        raise ValueError('dimensions')
    if mode != 'frames' and count != 1:
        raise ValueError('static required')
    options = payload.get('options', {})
    if mode == 'artwork' and (max(width, height) < options['minLongEdge'] or min(width, height) < options['minShortEdge']):
        raise ValueError('resolution')
    indexes = [0]
    if mode == 'frames':
        budget = min(count, max(1, min(6, int(options.get('maxFrames', 6)))))
        elapsed, ends = 0., []
        for i in range(count):
            image.seek(i)
            delay = float(image.info.get('duration', 100)) / 1000
            elapsed += min(10., max(.02, delay)) if math.isfinite(delay) else .1
            ends.append(elapsed)
        selected = {0}
        if budget > 1:
            selected.add(count - 1)
            for step in range(1, budget - 1):
                selected.add(next((i for i, end in enumerate(ends) if end >= elapsed * step / (budget - 1)), count - 1))
            for step in range(budget):
                if len(selected) < budget:
                    selected.add(step * (count - 1) // (budget - 1))
        indexes = sorted(selected)
    outputs = []
    for i in indexes:
        image.seek(i)
        frame = ImageOps.exif_transpose(image.copy())
        frame.load()
        if mode in ('sticker', 'generated'):
            return [base64.b64encode(raw).decode('ascii')]
        frame = frame.convert('RGBA')
        if mode in ('frames', 'artwork'):
            frame.thumbnail((1280, 1280) if mode == 'frames' else (2048, 2048))
            # Composite transparency onto white, rather than misreading it as a black background.
            background = Image.new('RGB', frame.size, 'white')
            background.paste(frame, mask=frame.getchannel('A'))
            frame = background
        output = io.BytesIO()
        frame.save(output, format='PNG' if mode == 'search' else 'JPEG', quality=80 if mode == 'frames' else 88)
        encoded = output.getvalue()
        if len(encoded) > (2_000_000 if mode == 'frames' else 3_000_000):
            raise ValueError('output size')
        outputs.append(base64.b64encode(encoded).decode('ascii'))
    return outputs


if __name__ == '__main__':
    resource.setrlimit(resource.RLIMIT_AS, (768 * 1024**2, 768 * 1024**2))
    resource.setrlimit(resource.RLIMIT_CPU, (15, 15))
    resource.setrlimit(resource.RLIMIT_FSIZE, (20_000_000, 20_000_000))
    Image.MAX_IMAGE_PIXELS = 40_000_000
    warnings.simplefilter('error', Image.DecompressionBombWarning)
    try:
        data = sys.stdin.buffer.read(28_000_001)
        if len(data) > 28_000_000:
            raise ValueError('input size')
        print(json.dumps(process(json.loads(data)), separators=(',', ':')))
    except Exception:
        sys.exit(1)
