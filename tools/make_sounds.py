"""Synthesises the game's sound effects into ../sounds/*.wav.

Everything is made from noise, sines and plucked strings, so there are no
outside files or licences to worry about. Run it again after changing a
recipe:  python tools/make_sounds.py
"""

import os
import wave

import numpy as np
from scipy.signal import butter, lfilter

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")
rng = np.random.default_rng(7)


def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def noise(seconds):
    return rng.uniform(-1, 1, int(SR * seconds))


def band(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], btype="band")
    return lfilter(b, a, x)


def low(x, hi, order=2):
    b, a = butter(order, hi / (SR / 2), btype="low")
    return lfilter(b, a, x)


def high(x, lo, order=2):
    b, a = butter(order, lo / (SR / 2), btype="high")
    return lfilter(b, a, x)


def decay(n, seconds):
    """An exponential fall to about -60 dB over `seconds`."""
    return np.exp(-np.arange(n) / SR * 6.9 / seconds)


def attack(n, seconds):
    k = max(1, int(SR * seconds))
    env = np.ones(n)
    env[:k] = np.linspace(0, 1, k)
    return env


def place(total, *parts):
    """Mix (offset_seconds, signal) parts into one buffer `total` seconds long."""
    out = np.zeros(int(SR * total))
    for at, x in parts:
        i = int(SR * at)
        j = min(len(out), i + len(x))
        out[i:j] += x[: j - i]
    return out


def pluck(freq, seconds, damp=0.996, bright=0.5):
    """Karplus-Strong plucked string."""
    n = int(SR * seconds)
    period = int(SR / freq)
    buf = rng.uniform(-1, 1, period)
    buf = low(buf, 2000 + bright * 6000)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % period]
        buf[i % period] = damp * 0.5 * (buf[i % period] + buf[(i + 1) % period])
    return out


def whoosh(seconds, f0, f1, loud=1.0):
    """Air cut by something swung or thrown: noise through a sweeping band."""
    n = int(SR * seconds)
    x = noise(seconds)
    out = np.zeros(n)
    steps = 24
    for s in range(steps):
        i, j = s * n // steps, (s + 1) * n // steps
        f = f0 + (f1 - f0) * s / steps
        out[i:j] = band(x, f * 0.6, f * 1.6)[i:j]
    env = np.sin(np.linspace(0, np.pi, n)) ** 1.5
    return out * env * loud


def thud(seconds, freq, body=1.0, crunch=0.0):
    """A blow landing: a low drop in pitch, a puff of low noise, maybe a crunch."""
    n = int(SR * seconds)
    t = t_axis(seconds)
    sweep = freq * (1 + 1.5 * np.exp(-t * 40))
    tone = np.sin(2 * np.pi * np.cumsum(sweep) / SR) * decay(n, seconds * 0.8)
    puff = low(noise(seconds), freq * 4) * decay(n, seconds * 0.5) * 1.5
    out = tone * body + puff
    if crunch:
        c = band(noise(0.04), 1200, 4000) * decay(int(SR * 0.04), 0.03)
        out[: len(c)] += c * crunch
    return out


def clang(seconds, partials, loud=1.0):
    """Struck metal: inharmonic partials, the high ones dying first."""
    n = int(SR * seconds)
    t = t_axis(seconds)
    out = np.zeros(n)
    for f, a in partials:
        out += a * np.sin(2 * np.pi * f * t) * decay(n, seconds * (900 / f) ** 0.5)
    click = high(noise(0.006), 2000) * 0.6
    out[: len(click)] += click
    return out * loud


def save(name, x, gain=0.8):
    x = np.asarray(x, dtype=float)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * gain
    # Fade the last few ms so nothing clicks off
    k = min(len(x), int(SR * 0.004))
    x[-k:] *= np.linspace(1, 0, k)
    data = (x * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(name, f"{len(x) / SR:.2f}s")


# --- Recipes ----------------------------------------------------------------------

# A bow loosed: the string's twang, the snap of release, the arrow leaving
twang = pluck(92, 0.45, damp=0.993, bright=0.3) * decay(int(SR * 0.45), 0.35)
snap = high(noise(0.01), 1500) * decay(int(SR * 0.01), 0.008)
save("bow", place(0.5, (0, twang), (0, snap * 0.8), (0.01, whoosh(0.22, 1800, 900, 0.35))))

# A crossbow: the latch clacks, a short stiff twang
clack = band(noise(0.02), 1500, 5000) * decay(int(SR * 0.02), 0.015)
save("crossbow", place(0.35, (0, clack * 1.2), (0.004, pluck(170, 0.25, damp=0.985, bright=0.6) * 0.8),
                       (0.05, clack * 0.5), (0.01, whoosh(0.15, 2200, 1200, 0.3))))

# A sling's throw, and the swish of a blade or club
save("sling", whoosh(0.28, 350, 1500))
save("swing", whoosh(0.2, 700, 2600))
save("swing_heavy", whoosh(0.34, 250, 1100))

# Arrows and blows landing on flesh
save("hit", thud(0.16, 85, body=0.8, crunch=0.5))
save("hit_heavy", thud(0.26, 60, body=1.0, crunch=0.9))
save("hit_arrow", place(0.14, (0, thud(0.12, 120, body=0.6, crunch=0.2)), (0, band(noise(0.03), 600, 2500) * decay(int(SR * 0.03), 0.02) * 0.6)))

# An arrow into the ground or wood
save("thunk", place(0.12, (0, thud(0.1, 180, body=0.7)), (0, band(noise(0.015), 2000, 6000) * 0.4)), gain=0.6)

# A shield takes it: a dull wooden knock and a ring of iron
save("block", place(0.5, (0, thud(0.1, 140, body=0.8)), (0, clang(0.45, [(530, 1.0), (1370, 0.6), (2230, 0.35), (3180, 0.2)], 0.7))))

# A body hitting the ground: a heavy thump and a second, smaller one
save("fall", place(0.45, (0, thud(0.28, 55, body=0.9)), (0.11, thud(0.2, 70, body=0.5) * 0.6)), gain=0.7)

# You're hurt: a deep thump
save("hurt", place(0.3, (0, thud(0.25, 50, body=1.0, crunch=0.6))))

# Coins: two bright pings
def ping(f, seconds=0.3):
    n = int(SR * seconds)
    t = t_axis(seconds)
    return (np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * f * 2.76 * t)) * decay(n, seconds)
save("coin", place(0.42, (0, ping(1975)), (0.07, ping(2637))), gain=0.45)

# The war horn: a rough, swelling blast with a fifth above, wavering
def horn(seconds=3.2, f=96):
    n = int(SR * seconds)
    t = t_axis(seconds)
    glide = f * (0.92 + 0.08 * (1 - np.exp(-t * 6)))
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.2 * t) * np.clip(t - 0.5, 0, 1)
    phase = 2 * np.pi * np.cumsum(glide * vib) / SR
    tone = sum(np.sin(h * phase) / h ** 0.9 for h in range(1, 14))
    fifth = sum(np.sin(h * phase * 1.5) / h ** 1.1 for h in range(1, 8)) * 0.35
    breath = band(noise(seconds), 400, 2500) * 0.08
    x = low(np.tanh((tone + fifth) * 1.6) + breath, 1600)
    env = np.minimum(1, t / 0.45) * np.clip((seconds - t) / 0.7, 0, 1)
    env *= 0.85 + 0.15 * np.sin(np.pi * np.clip(t / seconds, 0, 1))
    return x * env
save("horn", horn(), gain=0.9)
