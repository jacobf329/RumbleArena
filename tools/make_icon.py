#!/usr/bin/env python3
"""Rasterises the shuriken mark into icon.png and icon.ico.

Written by hand with zlib rather than an image library, so the icon can be
regenerated anywhere the project builds without adding a dependency.
"""
import struct
import zlib
from pathlib import Path

SIZE = 256
BACKGROUND = (0x16, 0x15, 0x1C, 255)
BLADE = (0xE8, 0x44, 0x3A, 255)
CORNER_RADIUS = SIZE * 0.16

# The shuriken from icon.svg, in a -64..64 space centred on the icon.
STAR = [(0, -46), (11, -11), (46, 0), (11, 11), (0, 46), (-11, 11), (-46, 0), (-11, -11)]
HUB_OUTER = 9.0
HUB_INNER = 4.0


def inside_polygon(x, y, polygon):
    hit = False
    count = len(polygon)
    for i in range(count):
        ax, ay = polygon[i]
        bx, by = polygon[(i + 1) % count]
        if (ay > y) != (by > y):
            if x < (bx - ax) * (y - ay) / (by - ay) + ax:
                hit = not hit
    return hit


def inside_rounded_square(x, y, half, radius):
    dx = abs(x) - (half - radius)
    dy = abs(y) - (half - radius)
    if dx <= 0 or dy <= 0:
        return abs(x) <= half and abs(y) <= half
    return dx * dx + dy * dy <= radius * radius


def render():
    scale = SIZE / 128.0
    half = SIZE / 2.0
    star = [(px * scale, py * scale) for px, py in STAR]
    rows = []
    for py in range(SIZE):
        row = bytearray()
        for px in range(SIZE):
            # Sample the centre of each pixel, offset to the icon's own origin.
            x = px + 0.5 - half
            y = py + 0.5 - half
            if not inside_rounded_square(x, y, half, CORNER_RADIUS * scale / (SIZE / 128.0)):
                row += bytes((0, 0, 0, 0))
                continue
            colour = BACKGROUND
            if inside_polygon(x, y, star):
                colour = BLADE
            distance = (x * x + y * y) ** 0.5
            if distance <= HUB_OUTER * scale:
                colour = BACKGROUND
            if distance <= HUB_INNER * scale:
                colour = BLADE
            row += bytes(colour)
        rows.append(bytes(row))
    return rows


def write_png(rows, path):
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(tag, payload):
        body = tag + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    Path(path).write_bytes(png)
    return png


def write_ico(png, path):
    # A 256px icon records its size as 0, and Vista onward accepts a PNG payload.
    header = struct.pack("<HHH", 0, 1, 1)
    entry = struct.pack("<BBBBHHII", 0, 0, 0, 0, 1, 32, len(png), 6 + 16)
    Path(path).write_bytes(header + entry + png)


if __name__ == "__main__":
    rows = render()
    png = write_png(rows, "icon.png")
    write_ico(png, "icon.ico")
    print("icon.png %d bytes, icon.ico %d bytes" % (
        Path("icon.png").stat().st_size, Path("icon.ico").stat().st_size))
