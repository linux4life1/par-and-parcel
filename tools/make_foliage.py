#!/usr/bin/env python3
"""Paints the foliage atlas used by trees, bushes and grass.

Four 512 px cells in a 1024 px image, each a cluster on a clear background:
  top left      a spray of broad leaves
  top right     a conifer bough
  bottom left   a palm frond
  bottom right  a tuft of grass

Colours are kept near neutral green so each plant can tint its own leaves.
Pure standard library; run from anywhere:  python3 tools/make_foliage.py
"""
import math
import os
import random
import struct
import zlib
from array import array

CELL = 512
SIZE = CELL * 2
PAD = 5

R = array("f", [0.0]) * (SIZE * SIZE)
G = array("f", [0.0]) * (SIZE * SIZE)
B = array("f", [0.0]) * (SIZE * SIZE)
A = array("f", [0.0]) * (SIZE * SIZE)


def put(i, r, g, b, a):
    """Lay colour over what is already there."""
    da = A[i]
    oa = a + da * (1.0 - a)
    if oa <= 0.0:
        return
    k = da * (1.0 - a)
    R[i] = (r * a + R[i] * k) / oa
    G[i] = (g * a + G[i] * k) / oa
    B[i] = (b * a + B[i] * k) / oa
    A[i] = oa


def leaf(cell, x, y, angle, length, width, color, lobes=0.0, rib=0.22):
    """A pointed leaf. Position and sizes are fractions of the cell."""
    cx, cy = cell
    ca, sa = math.cos(angle), math.sin(angle)
    px, py = x * CELL, y * CELL
    ln, wd = length * CELL, width * CELL
    ex, ey = px + ca * ln, py + sa * ln
    x0 = int(max(PAD, min(px, ex) - wd))
    x1 = int(min(CELL - PAD, max(px, ex) + wd + 1))
    y0 = int(max(PAD, min(py, ey) - wd))
    y1 = int(min(CELL - PAD, max(py, ey) + wd + 1))
    cr, cg, cb = color
    for iy in range(y0, y1):
        row = (cy * CELL + iy) * SIZE + cx * CELL
        dy = iy + 0.5 - py
        for ix in range(x0, x1):
            dx = ix + 0.5 - px
            u = (dx * ca + dy * sa) / ln
            if u <= 0.0 or u >= 1.0:
                continue
            v = -dx * sa + dy * ca
            shape = min(1.0, u * 4.5) ** 0.7 * (1.0 - u) ** 0.55 * 1.25
            if lobes > 0.0:
                shape *= 1.0 - lobes * (0.5 + 0.5 * math.cos(u * 31.0))
            half = wd * 0.5 * shape
            a = half - abs(v) + 0.5
            if a <= 0.0:
                continue
            if a > 1.0:
                a = 1.0
            t = abs(v) / (half + 0.001)
            tone = (0.74 + 0.3 * u) * (1.0 - 0.16 * t)
            tone += rib * math.exp(-((v / (wd * 0.07 + 0.5)) ** 2))
            # side veins: faint lighter streaks
            tone += 0.022 * math.cos(u * 40.0 + abs(v) * 0.9)
            put(row + ix, cr * tone, cg * tone, cb * tone, a)


def stroke(cell, x0, y0, x1, y1, w0, w1, c0, c1):
    """A tapering line with round ends, for twigs, needles and blades."""
    cx, cy = cell
    ax, ay, bx, by = x0 * CELL, y0 * CELL, x1 * CELL, y1 * CELL
    r0, r1 = w0 * CELL * 0.5, w1 * CELL * 0.5
    rm = max(r0, r1) + 1.0
    lx0 = int(max(PAD, min(ax, bx) - rm))
    lx1 = int(min(CELL - PAD, max(ax, bx) + rm + 1))
    ly0 = int(max(PAD, min(ay, by) - rm))
    ly1 = int(min(CELL - PAD, max(ay, by) + rm + 1))
    vx, vy = bx - ax, by - ay
    vv = vx * vx + vy * vy + 1e-6
    for iy in range(ly0, ly1):
        row = (cy * CELL + iy) * SIZE + cx * CELL
        dy = iy + 0.5 - ay
        for ix in range(lx0, lx1):
            dx = ix + 0.5 - ax
            t = (dx * vx + dy * vy) / vv
            if t < 0.0:
                t = 0.0
            elif t > 1.0:
                t = 1.0
            ex = dx - vx * t
            ey = dy - vy * t
            d = math.sqrt(ex * ex + ey * ey)
            a = r0 + (r1 - r0) * t - d + 0.5
            if a <= 0.0:
                continue
            if a > 1.0:
                a = 1.0
            put(row + ix, c0[0] + (c1[0] - c0[0]) * t, c0[1] + (c1[1] - c0[1]) * t, c0[2] + (c1[2] - c0[2]) * t, a)


def green(rng, light=1.0):
    """A leaf colour: mostly neutral, drifting a little yellow or blue."""
    v = (0.62 + rng.random() * 0.36) * light
    warm = rng.random() * 0.14
    return (v * (0.86 + warm), v, v * (0.74 - warm * 0.6))


# ------------------------------------------------------------- broad leaves

def broad(cell, rng):
    twig = (0.42, 0.36, 0.26)
    sprays = []
    for k in range(9):
        ang = k / 9.0 * math.tau + rng.uniform(-0.25, 0.25)
        ln = rng.uniform(0.3, 0.45)
        sprays.append((ang, ln))
    # three layers, darkest first, so the cluster has depth
    for layer, light in ((0, 0.6), (1, 0.8), (2, 1.0)):
        for ang, ln in sprays:
            a = ang + (layer - 1) * 0.22
            l = ln * (1.0 - 0.1 * (2 - layer))
            bend = rng.uniform(-0.5, 0.5)
            steps = int(l / 0.034)
            px, py = 0.5, 0.5
            for s in range(steps):
                f = (s + 1) / steps
                aa = a + bend * f
                nx = px + math.cos(aa) * l / steps
                ny = py + math.sin(aa) * l / steps
                if layer == 2:
                    stroke(cell, px, py, nx, ny, 0.007 * (1.2 - f), 0.007 * (1.1 - f), twig, twig)
                px, py = nx, ny
                side = 1 if s % 2 == 0 else -1
                la = aa + side * rng.uniform(0.7, 1.2)
                leaf(cell, px, py, la, rng.uniform(0.075, 0.105), rng.uniform(0.034, 0.048), green(rng, light), lobes=0.12)
            leaf(cell, px, py, a + bend, rng.uniform(0.08, 0.11), 0.045, green(rng, light), lobes=0.12)
    # a few bright leaves on top, facing the light
    for _ in range(70):
        rr = math.sqrt(rng.random()) * 0.4
        aa = rng.random() * math.tau
        leaf(cell, 0.5 + math.cos(aa) * rr, 0.5 + math.sin(aa) * rr, rng.random() * math.tau,
             rng.uniform(0.07, 0.1), rng.uniform(0.034, 0.046), green(rng, 1.06), lobes=0.12)


# ------------------------------------------------------------ conifer bough

def needles(cell, rng, x0, y0, x1, y1, length, light):
    dx, dy = x1 - x0, y1 - y0
    seg = math.hypot(dx, dy)
    if seg < 1e-5:
        return
    base = math.atan2(dy, dx)
    n = max(2, int(seg / 0.0065))
    for i in range(n):
        f = i / n
        px, py = x0 + dx * f, y0 + dy * f
        for side in (-1, 1):
            a = base + side * rng.uniform(0.55, 1.0)
            ln = length * rng.uniform(0.7, 1.15)
            c = green(rng, light)
            dark = (c[0] * 0.62, c[1] * 0.7, c[2] * 0.72)
            stroke(cell, px, py, px + math.cos(a) * ln, py + math.sin(a) * ln, 0.0066, 0.0026, dark, c)


def bough(cell, rng):
    twig = (0.36, 0.28, 0.2)
    for layer, light in ((0, 0.62), (1, 1.0)):
        shift = 0.012 if layer == 0 else 0.0
        steps = 34
        for s in range(steps):
            f = s / steps
            y = 0.97 - f * 0.9
            reach = (0.34 * (1.0 - f) ** 0.8 + 0.03) * (0.9 if layer == 0 else 1.0)
            for side in (-1, 1):
                if (s + (0 if side < 0 else 1)) % 2 == layer and layer == 0:
                    continue
                a = -math.pi / 2 + side * rng.uniform(0.75, 1.0)
                ex = 0.5 + math.cos(a) * reach + shift * side
                ey = y + math.sin(a) * reach * 0.8 - 0.02
                mx = 0.5 + (ex - 0.5) * 0.5
                my = y + (ey - y) * 0.5 + 0.012
                needles(cell, rng, 0.5, y, mx, my, 0.036, light)
                needles(cell, rng, mx, my, ex, ey, 0.032, light)
                if layer == 1:
                    stroke(cell, 0.5, y, mx, my, 0.006, 0.004, twig, twig)
                    stroke(cell, mx, my, ex, ey, 0.004, 0.002, twig, twig)
                    # side shoots
                    if reach > 0.08:
                        for q in (0.3, 0.5, 0.7, 0.86):
                            sx = 0.5 + (ex - 0.5) * q
                            sy = y + (ey - y) * q
                            for turn in (-0.75, 0.75):
                                ta = a + turn
                                tl = reach * 0.34 * (1.15 - q)
                                needles(cell, rng, sx, sy, sx + math.cos(ta) * tl, sy + math.sin(ta) * tl, 0.03, light)
        if layer == 1:
            needles(cell, rng, 0.5, 0.97, 0.5, 0.05, 0.03, 1.0)
            stroke(cell, 0.5, 0.985, 0.5, 0.06, 0.012, 0.003, twig, twig)


# --------------------------------------------------------------- palm frond

def frond(cell, rng):
    rib = (0.6, 0.62, 0.36)
    n = 44
    for layer, light in ((0, 0.7), (1, 1.0)):
        for i in range(n):
            if i % 2 != layer:
                continue
            f = i / n
            y = 0.95 - f * 0.9
            ln = 0.3 * math.sin(min(1.0, f * 2.2 + 0.15) * math.pi * 0.5) * (1.0 - f * 0.72) + 0.03
            for side in (-1, 1):
                a = -math.pi / 2 + side * (1.12 - f * 0.5 + rng.uniform(-0.07, 0.07))
                leaf(cell, 0.5, y, a, ln * rng.uniform(0.9, 1.08), 0.03, green(rng, light), rib=0.3)
    stroke(cell, 0.5, 0.985, 0.5, 0.04, 0.016, 0.003, rib, rib)


# --------------------------------------------------------------- grass tuft

def tuft(cell, rng):
    blades = 46
    order = [rng.random() for _ in range(blades)]
    for i in range(blades):
        back = i < blades // 2
        bx = 0.5 + rng.uniform(-0.22, 0.22)
        lean = (bx - 0.5) * 1.6 + rng.uniform(-0.28, 0.28)
        h = rng.uniform(0.45, 0.93) * (0.85 if back else 1.0)
        w = rng.uniform(0.016, 0.026)
        v = rng.uniform(0.74, 1.0) * (0.82 if back else 1.0)
        dry = rng.random() < 0.16
        tip = (v * 1.02, v * 0.98, v * 0.6) if dry else (v * 0.92, v, v * 0.7)
        root = (tip[0] * 0.74, tip[1] * 0.78, tip[2] * 0.72)
        segs = 9
        px, py = bx, 0.985
        for s in range(segs):
            f0 = s / segs
            f1 = (s + 1) / segs
            nx = bx + lean * h * f1 * f1
            ny = 0.985 - h * f1 * (1.0 - 0.18 * abs(lean) * f1)
            c0 = tuple(root[k] + (tip[k] - root[k]) * f0 for k in range(3))
            c1 = tuple(root[k] + (tip[k] - root[k]) * f1 for k in range(3))
            stroke(cell, px, py, nx, ny, w * (1.0 - f0 * 0.85), w * (1.0 - f1 * 0.85) + 0.0005, c0, c1)
            px, py = nx, ny
    del order


def write_png(path):
    # Clear pixels take the average colour of their cell, so the edges of
    # leaves do not pick up a dark fringe when the image is scaled down.
    for cy in range(2):
        for cx in range(2):
            sr = sg = sb = sw = 0.0
            for iy in range(CELL):
                row = (cy * CELL + iy) * SIZE + cx * CELL
                for ix in range(CELL):
                    a = A[row + ix]
                    if a > 0.0:
                        sr += R[row + ix] * a
                        sg += G[row + ix] * a
                        sb += B[row + ix] * a
                        sw += a
            if sw <= 0.0:
                continue
            mr, mg, mb = sr / sw, sg / sw, sb / sw
            for iy in range(CELL):
                row = (cy * CELL + iy) * SIZE + cx * CELL
                for ix in range(CELL):
                    if A[row + ix] <= 0.0:
                        R[row + ix], G[row + ix], B[row + ix] = mr, mg, mb
    raw = bytearray()
    for iy in range(SIZE):
        raw.append(0)
        row = iy * SIZE
        for ix in range(SIZE):
            i = row + ix
            raw.append(max(0, min(255, int(R[i] * 255.0 + 0.5))))
            raw.append(max(0, min(255, int(G[i] * 255.0 + 0.5))))
            raw.append(max(0, min(255, int(B[i] * 255.0 + 0.5))))
            raw.append(max(0, min(255, int(A[i] * 255.0 + 0.5))))

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


def main():
    rng = random.Random(1907)
    broad((0, 0), rng)
    bough((1, 0), rng)
    frond((0, 1), rng)
    tuft((1, 1), rng)
    cover = []
    for cy in range(2):
        for cx in range(2):
            s = 0.0
            for iy in range(CELL):
                row = (cy * CELL + iy) * SIZE + cx * CELL
                for ix in range(CELL):
                    s += A[row + ix]
            cover.append(round(s / (CELL * CELL), 2))
    print("coverage", cover)
    for cy in range(2):
        for cx in range(2):
            sr = sg = sb = sw = 0.0
            for iy in range(CELL):
                row = (cy * CELL + iy) * SIZE + cx * CELL
                for ix in range(CELL):
                    a = A[row + ix]
                    sr += R[row + ix] * a
                    sg += G[row + ix] * a
                    sb += B[row + ix] * a
                    sw += a
            print("cell", cx, cy, "mean", round(sr / sw, 3), round(sg / sw, 3), round(sb / sw, 3))
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "textures", "foliage_atlas.png")
    write_png(os.path.normpath(out))
    print("wrote", os.path.normpath(out))


if __name__ == "__main__":
    main()
