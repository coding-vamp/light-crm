#!/usr/bin/env python3
"""Render the original four-tile Light CRM mark; uses only the Python standard library."""
from pathlib import Path
import json
import struct
import zlib

root = Path(__file__).resolve().parents[1] / 'Light CRM/Assets.xcassets/AppIcon.appiconset'
root.mkdir(parents=True, exist_ok=True)

def inside(x, y, left, top, right, bottom, radius):
    if not (left <= x <= right and top <= y <= bottom):
        return False
    cx = min(max(x, left + radius), right - radius)
    cy = min(max(y, top + radius), bottom - radius)
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2

def pixel(x, y):
    if not inside(x, y, 72, 72, 952, 952, 180):
        return (0, 0, 0, 0)
    color = (243, 244, 246, 255)
    for left, top, fill in [(244, 244, (29, 78, 216, 255)), (540, 244, (59, 130, 246, 255)),
                            (244, 540, (29, 78, 216, 255)), (540, 540, (16, 185, 129, 255))]:
        if inside(x, y, left, top, left + 240, top + 240, 32):
            return fill
    return color

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)

for size in [16, 32, 64, 128, 256, 512, 1024]:
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            samples = [pixel((x + dx) * 1024 / size, (y + dy) * 1024 / size)
                       for dx, dy in [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]]
            rows.extend(round(sum(p[c] for p in samples) / 4) for c in range(4))
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(bytes(rows), 9)) + chunk(b'IEND', b'')
    (root / f'icon-{size}.png').write_bytes(png)
images = [{'idiom': 'mac', 'size': f'{size}x{size}', 'scale': f'{scale}x', 'filename': f'icon-{size * scale}.png'}
          for size in [16, 32, 128, 256, 512] for scale in [1, 2]]
(root / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
