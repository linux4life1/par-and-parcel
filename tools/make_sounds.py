#!/usr/bin/env python3
"""Makes the game's sound effects, background ambience and voices.

Each sound is built from what physically makes it: a struck object rings at
a few frequencies that die away (see `ring`), impacts add a short burst of
noise, wind and rain are noise shaped by filters, birds and crickets are
swept or pulsed tones, and a voice is a buzz shaped by a moving mouth (see
`utter`). Nothing is sampled.

Every sound is worked out as plain 16-bit audio and then written as Ogg
Vorbis by the reference encoder, `oggenc`, into assets/sounds:

    brew install vorbis-tools        # once, for oggenc and oggdec
    python3 tools/make_sounds.py

It prints each sound's length, peak level, loudness and brightness so a
change can be checked without listening. Sounds that loop are decoded again
and their join is measured. `python3 tools/make_sounds.py voices` remakes
only the voices and the other sounds added after the first set (those have
their own random numbers, so remaking them never changes the rest).
"""
import math
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
import zlib

SR = 44100
OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds"))
TAU = math.tau


# ------------------------------------------------------------- building blocks

def silence(seconds):
    return [0.0] * int(seconds * SR)


def noise(seconds, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(int(seconds * SR))]


def biquad(x, kind, freq, q=0.707, gain_db=0.0):
    """One pass of a standard two-pole filter: lowpass, highpass or bandpass."""
    w = TAU * min(freq, SR * 0.45) / SR
    cw, sw = math.cos(w), math.sin(w)
    alpha = sw / (2.0 * q)
    if kind == "lp":
        b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
    elif kind == "hp":
        b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
    else:  # bandpass, peak gain 1
        b0, b1, b2 = alpha, 0.0, -alpha
    a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    out = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, y
        out[i] = y
    return out


def sweep_filter(x, kind, f0, f1, q=1.0):
    """A filter whose frequency glides from f0 to f1 over the sound."""
    out = [0.0] * len(x)
    n = max(len(x), 1)
    lo = band = 0.0
    for i, v in enumerate(x):
        f = f0 * (f1 / f0) ** (i / n)
        k = 2.0 * math.sin(math.pi * min(f, SR * 0.2) / SR)
        hi = v - lo - band / q
        band += k * hi
        lo += k * band
        out[i] = lo if kind == "lp" else (hi if kind == "hp" else band)
    return out


def ring(modes, seconds, attack=0.0005):
    """A struck object: each mode is (frequency, decay time, loudness)."""
    n = int(seconds * SR)
    out = [0.0] * n
    for freq, decay, amp in modes:
        step = TAU * freq / SR
        for i in range(n):
            t = i / SR
            out[i] += amp * math.exp(-t / decay) * math.sin(step * i) * min(1.0, t / attack)
    return out


def shaped(x, attack, decay):
    """A fast rise and an exponential fall."""
    out = [0.0] * len(x)
    for i, v in enumerate(x):
        t = i / SR
        out[i] = v * min(1.0, t / max(attack, 1e-5)) * math.exp(-max(0.0, t - attack) / decay)
    return out


def gain(x, g):
    return [v * g for v in x]


def mix(*parts):
    """Add sounds together. Each part is a sound, or (sound, start time)."""
    spans = []
    for p in parts:
        snd, at = p if isinstance(p, tuple) else (p, 0.0)
        spans.append((snd, int(at * SR)))
    n = max(len(s) + a for s, a in spans)
    out = [0.0] * n
    for snd, at in spans:
        for i, v in enumerate(snd):
            out[at + i] += v
    return out


def fade(x, fade_in=0.002, fade_out=0.01):
    n = len(x)
    a = int(fade_in * SR)
    b = int(fade_out * SR)
    out = list(x)
    for i in range(min(a, n)):
        out[i] *= i / a
    for i in range(min(b, n)):
        out[n - 1 - i] *= i / b
    return out


def normal(x, peak_db=-3.0):
    top = max(1e-9, max(abs(v) for v in x))
    g = 10 ** (peak_db / 20.0) / top
    return [v * g for v in x]


def looped(x, overlap):
    """Make a sound repeat without a seam by folding its tail into its head."""
    k = int(overlap * SR)
    n = len(x) - k
    out = list(x[:n])
    for i in range(k):
        a = math.sin(0.5 * math.pi * i / k)
        b = math.cos(0.5 * math.pi * i / k)
        out[i] = x[i] * a + x[n + i] * b
    return out


def tone(freq_at, seconds, amp_at=None):
    """A pure tone whose pitch (and loudness) can change over time."""
    n = int(seconds * SR)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / SR
        phase += TAU * freq_at(t) / SR
        out[i] = math.sin(phase) * (amp_at(t) if amp_at else 1.0)
    return out


def click(rng, seconds=0.003, bright=3500.0):
    return shaped(biquad(noise(seconds * 4, rng), "hp", bright), 0.0002, seconds)


def whoosh(rng, seconds, f0, f1, level):
    """A club through the air: noise whose pitch rises as the head speeds up."""
    body = sweep_filter(noise(seconds, rng), "bp", f0, f1, 1.4)
    n = len(body)
    return [v * level * (i / n) ** 2.2 for i, v in enumerate(body)]


# -------------------------------------------------------------------- golf

def strike(rng, kind):
    if kind == "drive":
        air = whoosh(rng, 0.22, 500, 2600, 0.5)
        hit = mix(click(rng, 0.004, 4000), ring([(3150, 0.030, 1.0), (4620, 0.022, 0.7), (6240, 0.014, 0.5), (2010, 0.045, 0.45)], 0.3),
                  gain(shaped(biquad(noise(0.1, rng), "lp", 260), 0.001, 0.03), 0.9))
        return mix(air, (hit, 0.21))
    if kind == "iron":
        air = whoosh(rng, 0.18, 450, 2000, 0.4)
        hit = mix(click(rng, 0.003, 3000), ring([(2240, 0.018, 1.0), (3420, 0.012, 0.6), (1180, 0.03, 0.4)], 0.2),
                  gain(shaped(biquad(noise(0.16, rng), "lp", 420), 0.001, 0.055), 1.3))
        return mix(air, (hit, 0.17))
    if kind == "chip":
        air = whoosh(rng, 0.12, 400, 1300, 0.22)
        hit = mix(gain(click(rng, 0.003, 2500), 0.7), ring([(1820, 0.014, 0.7), (980, 0.025, 0.4)], 0.15),
                  gain(shaped(biquad(noise(0.16, rng), "lp", 520), 0.001, 0.05), 1.2))
        return mix(air, (hit, 0.11))
    # putt: a soft tock
    return mix(gain(click(rng, 0.002, 2500), 0.35), ring([(1120, 0.022, 1.0), (1930, 0.014, 0.45), (640, 0.03, 0.35)], 0.16))


def landing(rng, kind):
    if kind == "soft":
        return mix(shaped(biquad(noise(0.22, rng), "lp", 300), 0.002, 0.05), gain(ring([(92, 0.05, 1.0), (150, 0.035, 0.5)], 0.22), 0.9))
    if kind == "sand":
        return shaped(biquad(biquad(noise(0.4, rng), "hp", 900), "lp", 5200), 0.008, 0.09)
    # hard ground, path or rock
    return mix(click(rng, 0.003, 3000), ring([(1620, 0.02, 1.0), (2710, 0.014, 0.6), (4130, 0.01, 0.35)], 0.16),
               gain(shaped(biquad(noise(0.08, rng), "lp", 500), 0.001, 0.02), 0.5))


def splash(rng):
    body = shaped(sweep_filter(noise(0.9, rng), "lp", 7000, 700, 0.8), 0.004, 0.22)
    parts = [body]
    for k in range(7):
        f0 = rng.uniform(350, 900)
        d = rng.uniform(0.03, 0.07)
        blip = tone(lambda t, f0=f0, d=d: f0 * (1.0 + 1.6 * t / d), d, lambda t, d=d: math.sin(math.pi * min(t / d, 1.0)) * 0.22)
        parts.append((blip, 0.12 + rng.uniform(0.0, 0.55)))
    return mix(*parts)


def sizzle(rng):
    hiss = shaped(biquad(biquad(noise(1.3, rng), "hp", 2400), "lp", 8000), 0.01, 0.42)
    parts = [hiss, gain(shaped(biquad(noise(0.3, rng), "lp", 300), 0.002, 0.06), 0.8)]
    for k in range(14):
        parts.append((gain(click(rng, 0.002, 2500), rng.uniform(0.2, 0.6)), rng.uniform(0.02, 0.9)))
    return mix(*parts)


def cup(rng):
    def knock(level):
        return gain(mix(gain(click(rng, 0.002, 2800), 0.5), ring([(910, 0.03, 1.0), (1530, 0.022, 0.6), (2410, 0.015, 0.35), (330, 0.06, 0.5)], 0.25)), level)
    return mix(knock(1.0), (knock(0.55), 0.075), (knock(0.3), 0.132), (knock(0.16), 0.176))


def leaves(rng):
    parts = []
    for k in range(9):
        burst = shaped(biquad(biquad(noise(0.12, rng), "hp", 2600), "lp", 9000), 0.01, rng.uniform(0.02, 0.05))
        parts.append((gain(burst, rng.uniform(0.3, 1.0)), rng.uniform(0.0, 0.42)))
    parts.append(gain(ring([(310, 0.03, 1.0), (520, 0.02, 0.5)], 0.12), 0.25))
    return mix(*parts)


def ricochet(rng, mat):
    if mat == "wood":
        return mix(click(rng, 0.003, 2200), ring([(420, 0.05, 1.0), (790, 0.04, 0.7), (1260, 0.028, 0.45), (2100, 0.016, 0.25)], 0.3))
    if mat == "timber":
        return mix(gain(click(rng, 0.003, 1800), 0.7), ring([(260, 0.06, 1.0), (540, 0.045, 0.6), (930, 0.03, 0.35)], 0.3))
    if mat == "stone":
        return mix(click(rng, 0.004, 3500), ring([(1900, 0.016, 1.0), (3120, 0.012, 0.7), (4700, 0.008, 0.45)], 0.14),
                   gain(shaped(biquad(noise(0.06, rng), "bp", 2400, 0.8), 0.0005, 0.012), 0.8))
    if mat == "metal":
        return mix(gain(click(rng, 0.002, 4000), 0.6), ring([(820, 0.55, 0.6), (1373, 0.42, 1.0), (2212, 0.3, 0.7), (3140, 0.22, 0.5), (4385, 0.14, 0.35), (5870, 0.08, 0.2)], 1.3))
    if mat == "wall":
        return mix(gain(click(rng, 0.003, 1500), 0.5), shaped(biquad(noise(0.22, rng), "lp", 380), 0.001, 0.045), gain(ring([(138, 0.06, 1.0), (245, 0.04, 0.5)], 0.25), 0.9))
    if mat == "roof":
        def tile(level):
            return gain(mix(click(rng, 0.003, 3000), ring([(1480, 0.02, 1.0), (2630, 0.014, 0.6), (3900, 0.01, 0.3)], 0.14)), level)
        return mix(tile(1.0), (tile(0.6), 0.09), (tile(0.4), 0.21), (tile(0.22), 0.3))
    # cactus: a soft, damp thup
    return mix(shaped(biquad(noise(0.16, rng), "lp", 600), 0.003, 0.03), gain(ring([(170, 0.04, 1.0)], 0.15), 0.7))


def bonk(rng):
    """A ball meeting a person: a dull knock and a short falling tone."""
    drop = tone(lambda t: 520 - 900 * t, 0.16, lambda t: math.exp(-t / 0.06) * 0.5)
    return mix(shaped(biquad(noise(0.12, rng), "lp", 700), 0.001, 0.03), ring([(210, 0.05, 1.0), (460, 0.03, 0.5)], 0.2), (drop, 0.01))


def glass(rng):
    parts = [shaped(biquad(noise(0.5, rng), "hp", 2500), 0.001, 0.07)]
    for k in range(34):
        f = rng.uniform(2200, 9500)
        parts.append((gain(ring([(f, rng.uniform(0.02, 0.12), 1.0), (f * 1.52, 0.03, 0.4)], 0.3), rng.uniform(0.08, 0.3)), rng.uniform(0.0, 0.55) ** 1.6))
    return mix(*parts)


def applause(rng, seconds, hands):
    """Many pairs of hands: each clap is a tiny burst of mid-range noise."""
    n = int(seconds * SR)
    out = [0.0] * n
    one = [shaped(biquad(noise(0.05, rng), "bp", f, 1.2), 0.0005, 0.012) for f in (1100, 1500, 1900, 2400, 2900)]
    for k in range(hands):
        # the crowd swells quickly and tails away
        u = rng.random()
        t = seconds * (0.04 + 0.9 * (u ** 1.5))
        g = rng.uniform(0.25, 1.0) * (1.0 - 0.6 * u)
        src = rng.choice(one)
        at = int(t * SR)
        for i, v in enumerate(src):
            if at + i < n:
                out[at + i] += v * g
    return out


# ------------------------------------------------------- interface and money

def bell(freqs, seconds, spacing=0.0, decay=0.5):
    parts = []
    for k, f in enumerate(freqs):
        parts.append((ring([(f, decay, 1.0), (f * 2.0, decay * 0.5, 0.35), (f * 2.99, decay * 0.3, 0.18), (f * 4.1, decay * 0.18, 0.08)], seconds), k * spacing))
    return mix(*parts)


def ui(rng, kind):
    if kind == "click":
        return mix(gain(click(rng, 0.0015, 3000), 0.6), ring([(1350, 0.008, 1.0), (2300, 0.005, 0.4)], 0.04))
    if kind == "open":
        return mix(ring([(640, 0.03, 0.8)], 0.08), (ring([(960, 0.04, 1.0)], 0.12), 0.045))
    if kind == "error":
        buzz = tone(lambda t: 150.0, 0.16, lambda t: (1.0 if math.sin(TAU * 150.0 * t) > 0 else 0.3) * math.exp(-t / 0.09))
        return biquad(buzz, "lp", 900)
    if kind == "alert":
        return mix(ring([(660, 0.12, 1.0), (1320, 0.05, 0.25)], 0.2), (ring([(495, 0.16, 1.0), (990, 0.06, 0.25)], 0.32), 0.14))
    if kind == "pop":
        return tone(lambda t: 420 + 1400 * t, 0.07, lambda t: math.sin(math.pi * min(t / 0.07, 1.0)) * 0.9)
    if kind == "coin":
        return bell([2093.0, 3136.0], 0.4, 0.035, 0.11)
    if kind == "cash":
        ratchet = mix(*[(gain(click(rng, 0.003, 2000), 0.7), 0.035 * k) for k in range(4)])
        return mix(ratchet, (bell([1397.0, 2794.0], 1.1, 0.0, 0.42), 0.16), (gain(shaped(biquad(noise(0.1, rng), "lp", 500), 0.001, 0.03), 0.6), 0.15))
    if kind == "chime":
        return bell([1046.5, 1318.5, 1568.0, 2093.0], 1.6, 0.085, 0.6)
    if kind == "medal":
        return bell([783.99, 1046.5, 1318.5, 1568.0, 2093.0, 2637.0], 2.2, 0.07, 0.8)
    if kind == "place":
        return mix(gain(click(rng, 0.003, 1500), 0.5), ring([(215, 0.05, 1.0), (405, 0.035, 0.6), (760, 0.02, 0.3)], 0.25))
    if kind == "paint":
        return shaped(biquad(biquad(noise(0.16, rng), "hp", 1800), "lp", 6000), 0.03, 0.035)
    if kind == "dig":
        return mix(shaped(biquad(noise(0.2, rng), "lp", 900), 0.006, 0.04), *[(gain(click(rng, 0.002, 1200), rng.uniform(0.2, 0.5)), rng.uniform(0.0, 0.1)) for _ in range(5)])
    if kind == "remove":
        return mix(shaped(biquad(noise(0.3, rng), "bp", 1400, 0.7), 0.002, 0.06), *[(gain(click(rng, 0.003, 1800), rng.uniform(0.3, 0.8)), rng.uniform(0.0, 0.2)) for _ in range(9)])
    raise ValueError(kind)


# ------------------------------------------------------------------- world

def thunder(rng):
    crack = shaped(biquad(noise(0.5, rng), "lp", 2600), 0.002, 0.09)
    roll = biquad(biquad(noise(4.2, rng), "lp", 190), "lp", 320)
    n = len(roll)
    wobble = biquad(noise(4.2, rng), "lp", 2.5)
    top = max(abs(v) for v in wobble) or 1.0
    roll = [v * (0.55 + 0.45 * wobble[i] / top) * math.exp(-(i / SR) / 1.5) * min(1.0, (i / SR) / 0.06) for i, v in enumerate(roll)]
    return mix(gain(crack, 0.9), (gain(normal(roll, 0.0), 1.0), 0.05))


def boom(rng, seconds, depth):
    low = tone(lambda t: depth * (0.4 + 0.6 * math.exp(-t / 0.25)), seconds, lambda t: math.exp(-t / (seconds * 0.3)) * min(1.0, t / 0.004))
    burst = shaped(biquad(noise(seconds, rng), "lp", 420), 0.003, seconds * 0.18)
    crackle = shaped(biquad(noise(seconds, rng), "bp", 1600, 0.6), 0.002, seconds * 0.07)
    return mix(low, gain(normal(burst, 0.0), 0.7), gain(normal(crackle, 0.0), 0.25))


def lamp_on(rng):
    hum = tone(lambda t: 100.0, 0.7, lambda t: 0.25 * min(1.0, t / 0.05) * math.exp(-t / 0.3))
    hum2 = tone(lambda t: 200.0, 0.7, lambda t: 0.1 * min(1.0, t / 0.05) * math.exp(-t / 0.25))
    return mix(ring([(180, 0.04, 1.0), (350, 0.025, 0.5)], 0.2), gain(click(rng, 0.003, 1500), 0.5), (hum, 0.02), (hum2, 0.02))


def mower(rng):
    """A small engine: firing pulses with a rattle on top. Loops."""
    seconds = 2.0
    n = int(seconds * SR)
    out = [0.0] * n
    rate = 46.0                       # firing strokes a second: a whole number of them fits the loop
    for i in range(n):
        t = i / SR
        ph = (t * rate) % 1.0
        pulse = math.exp(-ph * 9.0) * math.sin(TAU * 88.0 * t + 0.4 * math.sin(TAU * 3.0 * t))
        out[i] = pulse + 0.35 * math.sin(TAU * 184.0 * t) + 0.2 * math.sin(TAU * 276.0 * t)
    rattle = biquad(noise(seconds, rng), "bp", 1700, 0.8)
    out = [v + 0.22 * rattle[i] * (0.6 + 0.4 * math.sin(TAU * rate * i / SR)) for i, v in enumerate(out)]
    return biquad(out, "lp", 3200)


# ---------------------------------------------------------------- ambience

AMB_SR = 32000


def amb_noise(seconds, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(int(seconds * AMB_SR))]


def with_rate(rate, fn):
    """Run a building block at the ambience sample rate."""
    global SR
    keep = SR
    SR = rate
    try:
        return fn()
    finally:
        SR = keep


def birds(rng, seconds):
    """A quiet morning: a few different birds, near and far, left and right."""
    n = int(seconds * SR)
    left = [0.0] * n
    right = [0.0] * n

    def put(snd, at, pan, level):
        a = int(at * SR)
        gl = level * math.cos(pan * math.pi / 2)
        gr = level * math.sin(pan * math.pi / 2)
        for i, v in enumerate(snd):
            j = (a + i) % n            # wraps, so the loop has no seam
            left[j] += v * gl
            right[j] += v * gr
            # a faint echo from the trees
            k = (j + int(0.11 * SR)) % n
            left[k] += v * gr * 0.18
            right[k] += v * gl * 0.18

    def chirp(f0, f1, d):
        return tone(lambda t: f0 + (f1 - f0) * (t / d), d, lambda t: math.sin(math.pi * min(t / d, 1.0)) ** 1.5)

    t = 0.4
    while t < seconds - 0.5:
        kind = rng.choice(["warble", "warble", "two", "trill", "dove", "tit"])
        pan = rng.uniform(0.1, 0.9)
        level = rng.uniform(0.12, 0.5)
        if kind == "warble":
            at = t
            for k in range(rng.randint(4, 8)):
                f = rng.uniform(3000, 5200)
                d = rng.uniform(0.05, 0.11)
                put(chirp(f, f * rng.uniform(0.75, 1.3), d), at, pan, level)
                at += d + rng.uniform(0.02, 0.08)
        elif kind == "two":
            put(chirp(4300, 4100, 0.16), t, pan, level)
            put(chirp(3300, 3150, 0.22), t + 0.24, pan, level)
        elif kind == "tit":
            for k in range(3):
                put(chirp(5200, 4700, 0.07), t + k * 0.16, pan, level * 0.8)
        elif kind == "trill":
            f = rng.uniform(5000, 6200)
            for k in range(rng.randint(8, 14)):
                put(chirp(f, f * 0.93, 0.03), t + k * 0.05, pan, level * 0.7)
        else:
            for k in range(3):
                put(tone(lambda tt: 470 - 40 * tt, 0.34, lambda tt: math.sin(math.pi * min(tt / 0.34, 1.0)) ** 2), t + k * 0.5, pan, level * 0.5)
        t += rng.uniform(0.9, 2.6)
    return left, right


def crickets(rng, seconds):
    n = int(seconds * SR)
    left = [0.0] * n
    right = [0.0] * n
    for c in range(7):
        f = rng.uniform(4000, 5000)
        period = rng.choice([0.5, 0.625, 0.8, 1.0])     # each divides the loop length
        pulses = rng.choice([2, 3, 3, 4])
        pan = rng.uniform(0.05, 0.95)
        level = rng.uniform(0.08, 0.3)
        offset = rng.uniform(0.0, period)
        gl = level * math.cos(pan * math.pi / 2)
        gr = level * math.sin(pan * math.pi / 2)
        step = TAU * f / SR
        for i in range(n):
            t = (i / SR + offset) % period
            k = int(t / 0.018)
            if k < pulses:
                u = (t - k * 0.018) / 0.012
                if u < 1.0:
                    v = math.sin(step * i) * math.sin(math.pi * u)
                    left[i] += v * gl
                    right[i] += v * gr
    return left, right


def wind(rng, seconds):
    def one():
        raw = biquad(biquad(amb_noise(seconds + 1.5, rng), "lp", 620), "hp", 140)
        slow = biquad(amb_noise(seconds + 1.5, rng), "lp", 0.35)
        top = max(abs(v) for v in slow) or 1.0
        return looped([v * (0.6 + 0.4 * slow[i] / top) for i, v in enumerate(raw)], 1.5)
    return one(), one()


def rain(rng, seconds):
    def one():
        bed = biquad(biquad(amb_noise(seconds + 1.0, rng), "hp", 1600), "lp", 8500)
        body = biquad(amb_noise(seconds + 1.0, rng), "bp", 480, 0.6)
        out = [bed[i] * 0.8 + body[i] * 0.5 for i in range(len(bed))]
        # single drops close by
        for k in range(int(seconds * 26)):
            at = rng.randrange(0, len(out) - 400)
            f = rng.uniform(1800, 5200)
            g = rng.uniform(0.2, 0.7)
            for i in range(260):
                out[at + i] += g * math.exp(-i / 55.0) * math.sin(TAU * f * i / SR)
        return looped(out, 1.0)
    return one(), one()


def lava(rng, seconds):
    def one():
        rumble = biquad(biquad(amb_noise(seconds + 1.5, rng), "lp", 85), "lp", 140)
        slow = biquad(amb_noise(seconds + 1.5, rng), "lp", 0.5)
        top = max(abs(v) for v in slow) or 1.0
        out = [v * 6.0 * (0.65 + 0.35 * slow[i] / top) for i, v in enumerate(rumble)]
        for k in range(int(seconds * 1.6)):
            at = rng.randrange(0, len(out) - int(0.3 * SR))
            f0 = rng.uniform(70, 160)
            d = rng.uniform(0.08, 0.2)
            g = rng.uniform(0.25, 0.6)
            m = int(d * SR)
            ph = 0.0
            for i in range(m):
                u = i / m
                ph += TAU * f0 * (1.0 + 1.4 * u) / SR
                out[at + i] += g * math.sin(ph) * math.sin(math.pi * u)
        return looped(out, 1.5)
    return one(), one()


# ------------------------------------------------------------------ on the course

def strike_sand(rng):
    """A bunker shot: the club thumps into the sand under the ball and throws a spray of it."""
    air = whoosh(rng, 0.14, 400, 1500, 0.25)
    thump = mix(shaped(biquad(noise(0.2, rng), "lp", 240), 0.002, 0.05), gain(ring([(118, 0.06, 1.0), (176, 0.04, 0.6)], 0.25), 1.1))
    spray = shaped(biquad(biquad(noise(0.6, rng), "hp", 1500), "lp", 7000), 0.03, 0.13)
    grains = [(gain(click(rng, 0.002, 3000), rng.uniform(0.08, 0.25)), 0.03 + rng.uniform(0.0, 0.35) ** 1.3) for _ in range(26)]
    return mix(air, (gain(thump, 1.0), 0.13), (gain(spray, 0.75), 0.135), *[(g, 0.14 + at) for g, at in grains])


def strike_rough(rng):
    """Long grass grabbing the club: a swish and a tear. Plays under the club's own sound."""
    swish = sweep_filter(noise(0.2, rng), "bp", 900, 3200, 1.1)
    n = len(swish)
    swish = [v * 0.5 * (i / n) ** 1.6 for i, v in enumerate(swish)]
    tear = shaped(biquad(biquad(noise(0.3, rng), "hp", 2300), "lp", 7500), 0.006, 0.07)
    stalks = [(gain(click(rng, 0.002, 2600), rng.uniform(0.1, 0.3)), rng.uniform(0.0, 0.12)) for _ in range(9)]
    return mix(swish, (gain(tear, 0.9), 0.17), *[(s, 0.17 + at) for s, at in stalks])


def out_of_bounds(rng):
    """Two soft wooden notes going down: a marker, not a buzzer."""
    def note(f):
        return mix(gain(click(rng, 0.002, 1800), 0.25), ring([(f, 0.11, 1.0), (f * 2.76, 0.035, 0.22), (f * 5.4, 0.015, 0.08)], 0.4))
    return mix(note(659.3), (gain(note(493.9), 0.85), 0.16))


def gust(rng):
    """A breath of wind through the trees that swells and dies away."""
    seconds = 2.2
    body = biquad(biquad(biquad(noise(seconds, rng), "lp", 520), "lp", 900), "hp", 150)
    high = biquad(biquad(noise(seconds, rng), "hp", 1800), "lp", 5200)
    n = len(body)
    out = [0.0] * n
    for i in range(n):
        u = i / n
        swell = math.sin(math.pi * u ** 0.8) ** 2
        out[i] = (body[i] + 0.035 * high[i] * swell) * swell
    return out


# ------------------------------------------------------------------- voices
#
# Nobody says a real word. Each voice is a buzz from the throat (or a hiss of
# breath) shaped by the mouth, which is three or four resonances that slide
# from one vowel or consonant to the next. Change the pitch of the buzz and
# the size of the mouth and you have a different person.

VOICE_SR = 32000

# The first three resonances of the mouth for each vowel sound, for a grown man.
VOWELS = {
    "a": (730, 1090, 2440), "e": (530, 1840, 2480), "i": (270, 2290, 3010), "o": (570, 840, 2410), "u": (300, 870, 2240),
    "@": (500, 1500, 2500), "A": (660, 1720, 2410), "I": (390, 1990, 2550), "U": (440, 1020, 2240),
}
GLIDES = {"ai": ("a", "I"), "ou": ("o", "U"), "oi": ("o", "I"), "ei": ("e", "I"), "au": ("a", "U")}
# Consonants: what kind, the shape of the mouth, and for hisses and bursts where the noise sits.
CONS = {
    "b": ("stop", (200, 800, 2300), 500, True), "d": ("stop", (200, 1700, 2700), 3600, True), "g": ("stop", (200, 2200, 2400), 2000, True),
    "p": ("stop", (200, 800, 2300), 600, False), "t": ("stop", (200, 1700, 2700), 4000, False), "k": ("stop", (200, 2200, 2400), 2200, False),
    "m": ("nasal", (250, 1100, 2300)), "n": ("nasal", (250, 1650, 2600)),
    "l": ("glide", (360, 1300, 2800)), "r": ("glide", (330, 1100, 1500)), "w": ("glide", (300, 650, 2200)), "y": ("glide", (270, 2200, 3000)),
    "s": ("hiss", 6000, 0.45), "S": ("hiss", 3000, 0.55), "f": ("hiss", 4800, 0.2), "z": ("buzz", 5800, 0.25), "v": ("buzz", 4500, 0.12),
    "h": ("breath",),
}
# The cast. pitch is the natural note of the voice, tract the size of the mouth
# (bigger number, smaller head), rate how fast they talk, breath how airy,
# edge how bright the buzz is, and open how long the throat stays open each cycle.
VOICES = {
    "a": dict(pitch=112.0, tract=1.00, rate=1.00, breath=0.035, edge=3000.0, open=0.62),
    "b": dict(pitch=206.0, tract=1.17, rate=1.04, breath=0.060, edge=3400.0, open=0.68),
    "c": dict(pitch=93.0, tract=0.95, rate=0.90, breath=0.030, edge=2500.0, open=0.58),
    "d": dict(pitch=234.0, tract=1.21, rate=1.12, breath=0.070, edge=3800.0, open=0.70),
    "e": dict(pitch=137.0, tract=1.06, rate=1.08, breath=0.045, edge=3200.0, open=0.64),
}


def utter(segs, voice, rng):
    """Speak. Each segment is (seconds, mouth shape, voice, breath, hiss, hiss pitch, note)."""
    sr = SR
    scale = voice["tract"]
    base = voice["pitch"]
    oq = voice["open"]
    airy = voice["breath"]
    total = sum(int(s[0] * sr) for s in segs)
    out = [0.0] * total
    f1, f2, f3 = [v * scale for v in segs[0][1]]
    f4, f5 = 3500.0 * scale, 4500.0 * scale
    wide = 1.0 + (scale - 1.0) * 0.9
    bw = (75.0 * wide, 105.0 * wide, 150.0 * wide, 220.0 * wide, 280.0 * wide)
    av = ah = af = 0.0
    note = segs[0][6]
    fc = 4000.0
    kf = 1.0 - math.exp(-1.0 / (0.020 * sr))      # how fast the mouth moves
    ka = 1.0 - math.exp(-1.0 / (0.007 * sr))      # how fast loudness changes
    kp = 1.0 - math.exp(-1.0 / (0.045 * sr))      # how fast the note bends
    kt = 1.0 - math.exp(-TAU * voice["edge"] / sr)
    phase = rng.random()
    wobble = 1.0
    shimmer = 1.0
    drift = 0.0
    src = 0.0
    a1 = b1 = c1 = a2 = b2 = c2 = a3 = b3 = c3 = 0.0
    y11 = y12 = y21 = y22 = y31 = y32 = y41 = y42 = y51 = y52 = 0.0
    c4 = -math.exp(-TAU * bw[3] / sr)
    b4 = 2.0 * math.exp(-math.pi * bw[3] / sr) * math.cos(TAU * min(f4, sr * 0.45) / sr)
    a4 = 1.0 - b4 - c4
    c5 = -math.exp(-TAU * bw[4] / sr)
    b5 = 2.0 * math.exp(-math.pi * bw[4] / sr) * math.cos(TAU * min(f5, sr * 0.45) / sr)
    a5 = 1.0 - b5 - c5
    e1, e2, e3 = math.exp(-math.pi * bw[0] / sr), math.exp(-math.pi * bw[1] / sr), math.exp(-math.pi * bw[2] / sr)
    lo = band = 0.0
    kq = 1.0
    rnd = rng.random
    i = 0
    for seconds, shape, t_av, t_ah, t_af, t_fc, t_note in segs:
        t1, t2, t3 = shape[0] * scale, shape[1] * scale, shape[2] * scale
        if t_fc:
            fc = float(t_fc)
            kq = 2.0 * math.sin(math.pi * min(fc, sr * 0.2) / sr)
        for _ in range(int(seconds * sr)):
            f1 += (t1 - f1) * kf
            f2 += (t2 - f2) * kf
            f3 += (t3 - f3) * kf
            av += (t_av - av) * ka
            ah += (t_ah - ah) * ka
            af += (t_af - af) * ka
            note += (t_note - note) * kp
            if i & 15 == 0:
                c1 = -e1 * e1
                b1 = 2.0 * e1 * math.cos(TAU * f1 / sr)
                a1 = 1.0 - b1 - c1
                c2 = -e2 * e2
                b2 = 2.0 * e2 * math.cos(TAU * f2 / sr)
                a2 = 1.0 - b2 - c2
                c3 = -e3 * e3
                b3 = 2.0 * e3 * math.cos(TAU * min(f3, sr * 0.45) / sr)
                a3 = 1.0 - b3 - c3
                drift += (rng.uniform(-1.0, 1.0) - drift) * 0.02
            phase += base * note * wobble * (1.0 + 0.012 * drift) / sr
            if phase >= 1.0:
                phase -= 1.0
                wobble = 1.0 + rng.gauss(0.0, 0.006)       # no two cycles of a real voice are alike
                shimmer = 1.0 + rng.gauss(0.0, 0.04)
            nz = 2.0 * rnd() - 1.0
            if phase < oq:
                x = phase / oq
                g = (2.0 * x - 3.0 * x * x) * shimmer
                air = airy * 1.6
            else:
                g = 0.0
                air = airy * 0.5
            src += (av * g * 3.0 + (ah * 0.35 + av * air) * nz - src) * kt
            y = a1 * src + b1 * y11 + c1 * y12
            y12 = y11
            y11 = y
            x2 = y
            y = a2 * x2 + b2 * y21 + c2 * y22
            y22 = y21
            y21 = y
            x2 = y
            y = a3 * x2 + b3 * y31 + c3 * y32
            y32 = y31
            y31 = y
            x2 = y
            y = a4 * x2 + b4 * y41 + c4 * y42
            y42 = y41
            y41 = y
            x2 = y
            y = a5 * x2 + b5 * y51 + c5 * y52
            y52 = y51
            y51 = y
            # hisses and bursts are made at the teeth and lips, in front of the mouth's resonances
            hi = nz - lo - band * 0.7
            band += kq * hi
            lo += kq * band
            out[i] = y + af * band * 0.16
            i += 1
    # A little lift above 1 kHz, where the ear tells one vowel from another:
    # without it the voice sounds as if it were in the next room.
    clear = biquad(out, "hp", 1100.0)
    return biquad([v + 1.1 * clear[k] for k, v in enumerate(out)], "hp", 90.0)


class Line:
    """Builds the segments of one thing a voice says."""

    def __init__(self, voice):
        self.voice = voice
        self.segs = []
        self.last = VOWELS["@"]

    def add(self, seconds, shape, av=0.0, ah=0.0, af=0.0, fc=0.0, note=1.0):
        self.segs.append((seconds / self.voice["rate"], shape, av, ah, af, fc, note))
        self.last = shape

    def cons(self, c, toward, note, loud=1.0):
        d = CONS[c]
        kind = d[0]
        if kind == "stop":
            self.add(0.05 if d[3] else 0.06, d[1], av=0.12 * loud if d[3] else 0.0, note=note)
            self.add(0.012, d[1], av=0.1 * loud if d[3] else 0.0, af=0.55 if d[3] else 0.8, fc=d[2], note=note)
            if not d[3]:
                self.add(0.028, toward, ah=0.5, note=note)
        elif kind == "nasal":
            self.add(0.065, d[1], av=0.42 * loud, note=note)
        elif kind == "glide":
            self.add(0.06, d[1], av=0.75 * loud, note=note)
        elif kind == "hiss":
            self.add(0.085, toward, af=d[2], fc=d[1], note=note)
        elif kind == "buzz":
            self.add(0.07, toward, av=0.4 * loud, af=d[2], fc=d[1], note=note)
        else:
            self.add(0.055, toward, ah=0.55, note=note)

    def vowel(self, v, seconds, note, end_note=None, loud=1.0):
        a, b = GLIDES.get(v, (v, v))
        if end_note is None:
            end_note = note
        if a == b:
            if end_note == note:
                self.add(seconds, VOWELS[a], av=loud, note=note)
            else:
                self.add(seconds * 0.5, VOWELS[a], av=loud, note=note)
                self.add(seconds * 0.5, VOWELS[a], av=loud, note=end_note)
        else:
            self.add(seconds * 0.45, VOWELS[a], av=loud, note=note)
            self.add(seconds * 0.55, VOWELS[b], av=loud, note=end_note)

    def syllable(self, onset, v, coda, seconds, note, end_note=None, loud=1.0):
        first = VOWELS[GLIDES.get(v, (v, v))[0]]
        for c in onset:
            self.cons(c, first, note, loud)
        self.vowel(v, seconds, note, end_note, loud)
        for c in coda:
            self.cons(c, self.last, end_note if end_note is not None else note, loud * 0.8)

    def rest(self, seconds):
        self.add(seconds, self.last)

    def sound(self, rng):
        self.add(0.09, self.last)
        return utter(self.segs, self.voice, rng)


ONSETS = ["b", "d", "g", "m", "n", "l", "r", "w", "y", "s", "S", "f", "h", "z", "k", "p", "t", "v", "bl", "gr", "fr", "sl", "dr", "pl", "", "", "m", "n", "l", "b", "d", "w"]
NUCLEI = ["a", "e", "i", "o", "u", "@", "A", "ai", "ou", "oi", "ei", "a", "o", "u", "i", "e"]
CODAS = ["", "", "", "", "", "n", "m", "l", "s", "k", "b", "r", "g", "n", "l"]


def nonsense(rng, count):
    return [(rng.choice(ONSETS), rng.choice(NUCLEI), rng.choice(CODAS) if k == count - 1 or rng.random() < 0.3 else "") for k in range(count)]


def say(rng, voice, kind):
    """One line of conversation: a remark, a question, an exclamation, a murmur or a laugh."""
    ln = Line(voice)
    if kind == "remark":
        words = nonsense(rng, rng.randint(3, 5))
        stress = rng.randrange(0, len(words) - 1)
        for k, (on, v, co) in enumerate(words):
            u = k / (len(words) - 1)
            note = 1.12 - 0.27 * u + (0.1 if k == stress else 0.0)
            last = k == len(words) - 1
            ln.syllable(on, v, co, 0.17 if (last or k == stress) else rng.uniform(0.085, 0.125), note, note - 0.08 if last else None)
            if rng.random() < 0.15 and not last:
                ln.rest(0.05)
    elif kind == "question":
        words = nonsense(rng, rng.randint(2, 4))
        for k, (on, v, co) in enumerate(words):
            last = k == len(words) - 1
            if last:
                ln.syllable(on, v, "", 0.2, 1.08, 1.5)
            else:
                ln.syllable(on, v, co, rng.uniform(0.09, 0.13), 1.0 + rng.uniform(-0.05, 0.06))
    elif kind == "exclaim":
        words = nonsense(rng, rng.randint(2, 3))
        notes = [1.5, 1.2, 0.95]
        for k, (on, v, co) in enumerate(words):
            ln.syllable(on, v, co, 0.19 if k == 0 else 0.13, notes[k], notes[k] - 0.12)
    elif kind == "murmur":
        if rng.random() < 0.5:
            # mm-hm
            ln.add(0.17, CONS["m"][1], av=0.5, note=0.95)
            ln.add(0.05, CONS["m"][1], ah=0.3, note=1.0)
            ln.add(0.21, CONS["m"][1], av=0.5, note=1.25)
        else:
            # oh
            ln.vowel("ou", 0.34, 1.38, 0.92)
    else:
        # a laugh: ha ha ha, each one lower and softer
        beats = rng.randint(3, 5)
        v = rng.choice(["a", "A", "@", "e"])
        for k in range(beats):
            u = k / (beats - 1)
            ln.add(0.05, VOWELS[v], ah=0.5, note=1.5 - 0.42 * u)
            ln.add(0.085, VOWELS[v], av=1.0 - 0.45 * u, note=1.5 - 0.42 * u)
            ln.add(0.03, VOWELS[v], note=1.5 - 0.42 * u)
    return ln.sound(rng)


def raised(voice, edge, pitch=1.0):
    """The same person putting more (or less) into it."""
    v = dict(voice)
    v["edge"] = edge
    v["pitch"] = voice["pitch"] * pitch
    return v


def whoop(rng, voice, kind):
    ln = Line(raised(voice, 5200.0))
    if kind == "woo":
        ln.cons("w", VOWELS["u"], 1.3)
        ln.add(0.16, VOWELS["u"], av=1.0, note=1.95)
        ln.add(0.22, VOWELS["u"], av=1.0, note=2.0)
        ln.add(0.2, VOWELS["u"], av=0.8, note=1.3)
    elif kind == "yeah":
        ln.cons("y", VOWELS["A"], 1.7)
        ln.add(0.2, VOWELS["A"], av=1.0, note=1.7)
        ln.add(0.24, VOWELS["@"], av=0.85, note=1.05)
    else:
        # hey
        ln.cons("h", VOWELS["e"], 1.6)
        ln.add(0.17, VOWELS["e"], av=1.0, note=1.65)
        ln.add(0.2, VOWELS["I"], av=0.85, note=1.15)
    return ln.sound(rng)


def groan(rng, voice, kind):
    ln = Line(raised(voice, 2300.0))
    if kind == "oh":
        ln.add(0.22, VOWELS["o"], av=0.9, note=1.22)
        ln.add(0.3, VOWELS["o"], av=0.8, note=0.9)
        ln.add(0.26, VOWELS["U"], av=0.5, note=0.72)
    elif kind == "aw":
        ln.add(0.2, VOWELS["a"], av=0.9, note=1.18)
        ln.add(0.34, VOWELS["o"], av=0.75, note=0.85)
        ln.add(0.2, VOWELS["o"], av=0.4, note=0.72)
    else:
        # ugh
        ln.add(0.13, VOWELS["@"], av=0.9, note=0.95)
        ln.add(0.12, VOWELS["@"], av=0.6, note=0.74)
        ln.add(0.05, CONS["g"][1], av=0.1, note=0.7)
    return ln.sound(rng)


def boo(rng, voice):
    ln = Line(raised(voice, 2600.0))
    ln.cons("b", VOWELS["u"], 1.0)
    ln.add(0.3, VOWELS["u"], av=1.0, note=1.02)
    ln.add(rng.uniform(0.35, 0.55), VOWELS["u"], av=0.9, note=0.9)
    ln.add(0.22, VOWELS["u"], av=0.45, note=0.8)
    return ln.sound(rng)


def together(rng, parts, spread):
    """A few people making a noise at nearly the same moment, each at their own loudness."""
    placed = []
    for k, p in enumerate(parts):
        top = max(1e-9, max(abs(v) for v in p))
        placed.append((gain(p, rng.uniform(0.6, 1.0) / top), 0.0 if k == 0 else rng.uniform(0.03, spread)))
    return mix(*placed)


# -------------------------------------------------------------------- output

TMP = ""                 # where the uncompressed audio sits for a moment on its way to the encoder
WROTE = []


def encoder(tool):
    path = shutil.which(tool) or os.path.join("/opt/homebrew/bin", tool)
    if not os.path.exists(path):
        sys.exit("%s is missing. Install it with:  brew install vorbis-tools" % tool)
    return path


def read_wav(path):
    """The first channel of a 16-bit WAV file as numbers from -1 to 1."""
    with wave.open(path, "rb") as w:
        chans = w.getnchannels()
        raw = w.readframes(w.getnframes())
    vals = struct.unpack("<%dh" % (len(raw) // 2), raw)
    return [v / 32767.0 for v in vals[::chans]]


def write(name, left, right=None, rate=None, peak_db=-3.0, quality=8, loud_db=None, loops=False):
    """Save one sound as Ogg Vorbis. `quality` is oggenc's scale, -1 to 10.

    The level is set by the peak, or by the average loudness when `loud_db`
    is given (voices, so no one speaker is louder than the next)."""
    rate = rate or SR
    if right is None:
        data = normal(left, peak_db)
        if loud_db is not None:
            rms = math.sqrt(sum(v * v for v in data) / max(len(data), 1))
            g = min(1.0, 10 ** (loud_db / 20.0) / max(rms, 1e-9))
            data = [v * g for v in data]
        chans = [data]
    else:
        top = max(1e-9, max(max(abs(v) for v in left), max(abs(v) for v in right)))
        g = 10 ** (peak_db / 20.0) / top
        chans = [[v * g for v in left], [v * g for v in right]]
    n = min(len(c) for c in chans)
    frames = bytearray()
    for i in range(n):
        for c in chans:
            frames += struct.pack("<h", max(-32767, min(32767, int(round(c[i] * 32767.0)))))
    wav = os.path.join(TMP, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(len(chans))
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(frames))
    path = os.path.join(OUT, name + ".ogg")
    # a fixed serial number, so the same sound always makes the same file
    subprocess.run([encoder("oggenc"), "-Q", "-q", str(quality), "-s", str(zlib.crc32(name.encode()) & 0x7fffffff), "-o", path, wav], check=True)
    WROTE.append(path)
    # numbers to check a sound by, without ears
    mono = chans[0]
    rms = math.sqrt(sum(v * v for v in mono) / max(n, 1))
    crossings = sum(1 for i in range(1, n) if (mono[i - 1] < 0.0) != (mono[i] < 0.0))
    print("  %-16s %5.2f s  %s  peak %5.1f dB  loudness %6.1f dB  brightness %5d Hz  %5.1f KB" % (
        name, n / rate, "stereo" if len(chans) == 2 else "mono  ", 20 * math.log10(max(abs(v) for v in mono) + 1e-9),
        20 * math.log10(rms + 1e-9), int(crossings * rate / (2.0 * max(n, 1))), os.path.getsize(path) / 1024.0))
    if loops:
        # A loop must come back from the encoder the same length, and the step
        # from its last sample round to its first must be no bigger than the
        # steps inside it, or the join clicks.
        back = os.path.join(TMP, name + ".back.wav")
        subprocess.run([encoder("oggdec"), "-Q", "-o", back, path], check=True)
        got = read_wav(back)
        steps = sorted(abs(got[i] - got[i - 1]) for i in range(1, len(got)))
        usual = steps[int(len(steps) * 0.95)]
        seam = abs(got[0] - got[-1])
        err = math.sqrt(sum((got[i] - mono[i]) ** 2 for i in range(min(n, len(got)))) / max(n, 1))
        print("  %-16s loop: %d samples in, %d back; step across the join %.4f (95%% of steps inside are under %.4f); coding noise %.1f dB  %s" % (
            "", n, len(got), seam, usual, 20 * math.log10(err + 1e-9), "ok" if len(got) == n and seam <= usual * 1.5 + 0.002 else "CHECK THIS"))


def first_set():
    """The original sounds. They share one run of random numbers, so keep their order."""
    rng = random.Random(1907)
    print("golf")
    for k in ("drive", "iron", "chip", "putt"):
        for v in range(3):
            write("%s_%d" % (k, v + 1), fade(strike(rng, k), 0.001, 0.02))
    for k in ("soft", "sand", "hard"):
        for v in range(2):
            write("land_%s_%d" % (k, v + 1), fade(landing(rng, k), 0.0005, 0.02))
    write("splash", fade(splash(rng), 0.0005, 0.08))
    write("sizzle", fade(sizzle(rng), 0.0005, 0.1))
    write("cup", fade(cup(rng), 0.0005, 0.03))
    write("leaves", fade(leaves(rng), 0.002, 0.04))
    for m in ("wood", "timber", "stone", "metal", "wall", "roof", "cactus"):
        write("hit_" + m, fade(ricochet(rng, m), 0.0005, 0.03))
    write("bonk", fade(bonk(rng), 0.0005, 0.03))
    write("glass", fade(glass(rng), 0.0005, 0.06))
    write("clap", fade(applause(rng, 2.2, 150), 0.01, 0.4))
    write("ovation", fade(applause(rng, 4.0, 520), 0.01, 0.8))
    print("interface")
    for k in ("click", "open", "error", "alert", "pop", "coin", "cash", "chime", "medal", "place", "paint", "dig", "remove"):
        write(k, fade(ui(rng, k), 0.0005, 0.02))
    print("world")
    write("thunder", fade(thunder(rng), 0.001, 0.6))
    write("boom", fade(boom(rng, 3.2, 62.0), 0.001, 0.6))
    write("bomb", fade(boom(rng, 1.1, 95.0), 0.001, 0.2))
    write("lamp_on", fade(lamp_on(rng), 0.0005, 0.1))
    write("mower", mower(rng), peak_db=-6.0, loops=True)
    print("ambience (these loop)")
    l, r = with_rate(AMB_SR, lambda: birds(rng, 20.0))
    write("amb_birds", l, r, AMB_SR, -8.0, quality=6, loops=True)
    l, r = with_rate(AMB_SR, lambda: crickets(rng, 10.0))
    write("amb_crickets", l, r, AMB_SR, -10.0, quality=6, loops=True)
    l, r = with_rate(AMB_SR, lambda: wind(rng, 12.0))
    write("amb_wind", l, r, AMB_SR, -6.0, quality=6, loops=True)
    l, r = with_rate(AMB_SR, lambda: rain(rng, 8.0))
    write("amb_rain", l, r, AMB_SR, -6.0, quality=6, loops=True)
    l, r = with_rate(AMB_SR, lambda: lava(rng, 10.0))
    write("amb_lava", l, r, AMB_SR, -6.0, quality=6, loops=True)


def burp(rng):
    """A hot dog and a soda, settling. A low pulse train through a throat-shaped filter, pitch falling."""
    seconds = rng.uniform(0.28, 0.42)
    n = int(seconds * SR)
    out = [0.0] * n
    phase = 0.0
    f0 = rng.uniform(95.0, 125.0)
    for i in range(n):
        u = i / n
        f = f0 * (1.0 - 0.35 * u) * (1.0 + 0.04 * math.sin(i * 0.011))
        phase += f / SR
        if phase >= 1.0:
            phase -= 1.0
        # a ragged glottal pulse: sharp, with a bit of rasp
        pulse = max(0.0, 1.0 - phase * 4.0) ** 2 + 0.06 * (rng.random() - 0.5) * (phase < 0.3)
        env = math.sin(math.pi * u ** 0.6) ** 1.3
        out[i] = pulse * env
    out = biquad(biquad(biquad(out, "bp", 320.0 * (1.0 + 0.3 * rng.random()), 1.4), "bp", 900.0, 1.2, 4.0), "lp", 2600.0)
    return mix(out, (gain(shaped(biquad(noise(seconds, rng), "bp", 600.0, 1.2), 0.05, 0.2), 0.03), 0.0))


def flush(rng):
    """A toilet flush: the handle, a rush of water that gurgles away, and the cistern filling."""
    handle = mix(gain(click(rng, 0.004, 1200), 0.5), gain(ring([(410, 0.05, 1.0), (1180, 0.02, 0.4)], 0.2), 0.3))
    rush_s = 2.6
    rush = sweep_filter(noise(rush_s, rng), "bp", 1400, 500, 0.8)
    n = len(rush)
    for i in range(n):
        u = i / n
        swell = math.sin(math.pi * min(1.0, u * 1.25) ** 0.7) ** 1.5 if u < 0.8 else 0.0
        rush[i] *= swell * (1.0 + 0.35 * math.sin(i * 0.0017) * math.sin(i * 0.00043))
    gurgle = []
    for k in range(14):
        f = rng.uniform(140.0, 420.0)
        blip = shaped(biquad(noise(0.09, rng), "bp", f, 3.0), 0.003, 0.05)
        gurgle.append((gain(blip, rng.uniform(0.5, 1.2)), 0.9 + k * 0.1 + rng.uniform(0.0, 0.06)))
    fill = biquad(biquad(noise(1.8, rng), "bp", 2400, 1.0), "hp", 900)
    m = len(fill)
    fill = [v * 0.22 * (1.0 - i / m) ** 1.5 for i, v in enumerate(fill)]
    return mix(handle, (rush, 0.08), *gurgle, (fill, 2.3))


def slurp(rng):
    """A drink going down: a quick sip through a straw and a swallow."""
    sip = shaped(sweep_filter(noise(0.22, rng), "bp", 2600, 1500, 2.5), 0.02, 0.1)
    swallow = shaped(biquad(noise(0.12, rng), "bp", 300, 1.5), 0.01, 0.05)
    return mix(gain(sip, 0.5), (gain(swallow, 0.7), 0.26))


def bottle(rng):
    """A bottle opened at the bar: the pop of the seal letting go, the bright
    tick of the cap, a short hiss of gas, and a glug as it is poured."""
    pop_s = 0.055
    n = int(pop_s * SR)
    pop = [0.0] * n
    f0 = rng.uniform(520.0, 700.0)
    phase = 0.0
    for i in range(n):
        u = i / n
        phase += f0 * (1.0 - 0.5 * u) / SR
        pop[i] = math.sin(phase * math.tau) * math.exp(-u * 8.0)
    tick = gain(click(rng, 0.0025, 5600.0), 0.55)
    hiss = shaped(biquad(biquad(noise(0.34, rng), "bp", 4600.0 * rng.uniform(0.9, 1.1), 0.9), "hp", 2600.0), 0.004, 0.08)
    glugs = []
    for k in range(3):
        f = rng.uniform(170.0, 260.0) * (1.0 + 0.12 * k)
        blip = shaped(biquad(noise(0.07, rng), "bp", f, 4.0), 0.004, 0.045)
        glugs.append((gain(blip, 0.5), 0.34 + k * 0.1 + rng.uniform(0.0, 0.02)))
    return mix(pop, tick, (gain(hiss, 0.3), 0.03), *glugs)


def bar_set():
    """The bar: a bottle opened."""
    print("bar")
    for v in range(2):
        write("bottle_%d" % (v + 1), fade(bottle(random.Random("bottle %d" % v)), 0.001, 0.03), peak_db=-5.0)


def facilities_set():
    """Sounds of the facilities being used."""
    print("facilities")
    for v in range(3):
        write("burp_%d" % (v + 1), fade(burp(random.Random("burp %d" % v)), 0.003, 0.03), peak_db=-4.0)
    write("flush", fade(flush(random.Random("flush")), 0.001, 0.2), peak_db=-5.0)
    for v in range(2):
        write("slurp_%d" % (v + 1), fade(slurp(random.Random("slurp %d" % v)), 0.003, 0.03), peak_db=-6.0)
    bar_set()


def later_set():
    """Sounds added since. Each has random numbers of its own, named after it."""
    print("lies, wind and markers")
    for v in range(2):
        write("strike_sand_%d" % (v + 1), fade(strike_sand(random.Random("strike_sand %d" % v)), 0.001, 0.05))
    for v in range(2):
        write("strike_rough_%d" % (v + 1), fade(strike_rough(random.Random("strike_rough %d" % v)), 0.001, 0.04))
    write("oob", fade(out_of_bounds(random.Random("oob")), 0.0005, 0.05))
    write("gust", fade(gust(random.Random("gust")), 0.05, 0.3), peak_db=-6.0)
    print("voices: conversation")
    kinds = ["remark", "remark", "question", "exclaim", "murmur", "laugh"]
    for name in sorted(VOICES):
        rng = random.Random("voice " + name)
        for k, kind in enumerate(kinds):
            snd = with_rate(VOICE_SR, lambda: fade(say(rng, VOICES[name], kind), 0.004, 0.03))
            write("chat_%s_%d" % (name, k + 1), snd, rate=VOICE_SR, loud_db=-21.0)
    print("voices: a few people together")
    cast = sorted(VOICES)
    rng = random.Random("cheer")
    for v in range(3):
        def cheer():
            who = rng.sample(cast, 2 + v % 3)
            voices = together(rng, [whoop(rng, VOICES[c], rng.choice(["woo", "yeah", "hey"])) for c in who], 0.3)
            hands = normal(applause(rng, 2.0, 44), 0.0)
            return fade(mix(voices, (gain(hands, 0.3), 0.12)), 0.004, 0.35)
        write("cheer_%d" % (v + 1), with_rate(VOICE_SR, cheer), rate=VOICE_SR)
    rng = random.Random("groan")
    for v, kind in enumerate(["oh", "aw", "ugh"]):
        def moan():
            who = rng.sample(cast, 1 + v % 2)
            return fade(together(rng, [groan(rng, VOICES[c], kind) for c in who], 0.18), 0.004, 0.06)
        write("groan_%d" % (v + 1), with_rate(VOICE_SR, moan), rate=VOICE_SR, loud_db=-20.0)
    rng = random.Random("boo")
    for v in range(2):
        def jeer():
            who = rng.sample(cast, 2 + v)
            return fade(together(rng, [boo(rng, VOICES[c]) for c in who], 0.22), 0.004, 0.08)
        write("boo_%d" % (v + 1), with_rate(VOICE_SR, jeer), rate=VOICE_SR, loud_db=-20.0)


def main():
    global TMP
    os.makedirs(OUT, exist_ok=True)
    TMP = tempfile.mkdtemp(prefix="parandparcel-sounds-")
    try:
        only = sys.argv[1:]
        if "bar" in only:
            bar_set()
        elif "facilities" in only:
            facilities_set()
        else:
            if "voices" not in only:
                first_set()
            later_set()
            facilities_set()
    finally:
        shutil.rmtree(TMP, ignore_errors=True)
    print("wrote %d files, %.2f MB, to %s" % (len(WROTE), sum(os.path.getsize(p) for p in WROTE) / 1e6, OUT))


if __name__ == "__main__":
    main()
