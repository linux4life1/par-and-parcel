#!/usr/bin/env python3
"""Paints the noise texture the terrain, grass and sky shaders read.

Computing smooth noise in a shader costs dozens of operations per call, and
the terrain asked for it about forty times a pixel. Reading it from this
small picture gives the same patterns for a fraction of the cost.

256 x 256, tiles seamlessly:
  red, green   two unrelated fields of smooth noise, 64 cells across
  blue         four octaves of smooth noise layered together, 32 cells across

Pure standard library:  python3 tools/make_noise.py
"""
import os
import random
import struct
import zlib

SIZE = 256


def lattice(cells, seed):
    rng = random.Random(seed)
    return [[rng.random() for _ in range(cells)] for _ in range(cells)]


def sample(grid, cells, x, y):
    """Smooth value noise at (x, y), wrapping at the edges."""
    ix = int(x) % cells
    iy = int(y) % cells
    fx = x - int(x)
    fy = y - int(y)
    fx = fx * fx * (3.0 - 2.0 * fx)
    fy = fy * fy * (3.0 - 2.0 * fy)
    jx = (ix + 1) % cells
    jy = (iy + 1) % cells
    a = grid[iy][ix] + (grid[iy][jx] - grid[iy][ix]) * fx
    b = grid[jy][ix] + (grid[jy][jx] - grid[jy][ix]) * fx
    return a + (b - a) * fy


def main():
    red = lattice(64, 11)
    green = lattice(64, 23)
    octaves = [(lattice(32, 31), 32, 0.5), (lattice(64, 37), 64, 0.25), (lattice(128, 41), 128, 0.15), (lattice(256, 43), 256, 0.1)]
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)
        for x in range(SIZE):
            u = (x + 0.5) / SIZE
            v = (y + 0.5) / SIZE
            r = sample(red, 64, u * 64.0, v * 64.0)
            g = sample(green, 64, u * 64.0, v * 64.0)
            b = 0.0
            for grid, cells, weight in octaves:
                b += sample(grid, cells, u * cells, v * cells) * weight
            raw.append(max(0, min(255, int(r * 255.0 + 0.5))))
            raw.append(max(0, min(255, int(g * 255.0 + 0.5))))
            raw.append(max(0, min(255, int(b * 255.0 + 0.5))))

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    out = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "textures", "noise.png"))
    with open(out, "wb") as fh:
        fh.write(png)
    print("wrote", out)


if __name__ == "__main__":
    main()
