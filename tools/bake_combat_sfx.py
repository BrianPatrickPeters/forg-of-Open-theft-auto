#!/usr/bin/env python3
"""Bake combat SFX for Open Theft Auto.

Turns recorded CC0 firearm takes and a physically-motivated energy-discharge
synth into short, game-ready 44.1 kHz mono WAVs. The old in-engine sine
"pew" / sine-crack guns read as plastic; these replace them.

Sources (all CC0):
  - assets/audio/gunshot.wav, gunshot_sniper.wav  (Free Firearm Sound Library)
  - OpenGameArt "Gunshots" (22 Pistol / 22 Magnum / Black Powder)
  - Kenney Sci-fi Sounds (force-field + low-frequency explosion layers only)

Run from anywhere:
    python3 tools/bake_combat_sfx.py
"""

from __future__ import annotations

import math
import random
import struct
import subprocess
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"
RATE = 44100
SRC_TMP = Path("/tmp/ota-sfx")


def clamp(x: float, lo: float = -1.0, hi: float = 1.0) -> float:
    return lo if x < lo else hi if x > hi else x


def read_wav(path: Path) -> list[float]:
    """Decode any ffmpeg-readable file to 44.1 kHz mono float."""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp_path = Path(tmp.name)
    try:
        subprocess.run(
            [
                "ffmpeg", "-y", "-i", str(path),
                "-ac", "1", "-ar", str(RATE),
                "-c:a", "pcm_s16le", str(tmp_path),
            ],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        with wave.open(str(tmp_path), "rb") as w:
            n = w.getnframes()
            raw = w.readframes(n)
        samples = struct.unpack("<" + "h" * (len(raw) // 2), raw)
        return [s / 32768.0 for s in samples]
    finally:
        tmp_path.unlink(missing_ok=True)


def write_wav(path: Path, samples: list[float]) -> None:
    peak = max((abs(s) for s in samples), default=1.0) or 1.0
    # Leave ~1.5 dB of headroom so stacked playback doesn't clip.
    gain = 0.84 / peak
    data = b"".join(
        struct.pack("<h", int(clamp(s * gain) * 32767.0)) for s in samples
    )
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print(f"  wrote {path.name:28s}  {len(samples) / RATE:.3f}s")


def ones(n: int) -> list[float]:
    return [0.0] * n


def add_at(dst: list[float], src: list[float], at: int, gain: float = 1.0) -> None:
    need = at + len(src)
    if need > len(dst):
        dst.extend([0.0] * (need - len(dst)))
    for i, s in enumerate(src):
        dst[at + i] += s * gain


def fade(samples: list[float], attack: float, release: float) -> list[float]:
    n = len(samples)
    a = max(1, int(attack * RATE))
    r = max(1, int(release * RATE))
    out = samples[:]
    for i in range(min(a, n)):
        out[i] *= i / a
    for i in range(min(r, n)):
        out[n - 1 - i] *= i / r
    return out


def trim_shot(samples: list[float], t0: float, dur: float, pre: float = 0.008) -> list[float]:
    start = max(0, int((t0 - pre) * RATE))
    end = min(len(samples), int((t0 + dur) * RATE))
    return fade(samples[start:end], 0.002, 0.05)


def pitch(samples: list[float], factor: float) -> list[float]:
    if abs(factor - 1.0) < 1e-4:
        return samples[:]
    n = max(1, int(len(samples) / factor))
    out = []
    last = len(samples) - 1
    for i in range(n):
        src = i * factor
        j = int(src)
        f = src - j
        a = samples[j] if j <= last else 0.0
        b = samples[j + 1] if j + 1 <= last else 0.0
        out.append(a + (b - a) * f)
    return out


def lowpass(samples: list[float], cutoff: float) -> list[float]:
    x = math.exp(-2.0 * math.pi * cutoff / RATE)
    a = 1.0 - x
    y = 0.0
    out = []
    for s in samples:
        y += a * (s - y)
        out.append(y)
    return out


def highpass(samples: list[float], cutoff: float) -> list[float]:
    lp = lowpass(samples, cutoff)
    return [s - l for s, l in zip(samples, lp)]


def peak_norm(samples: list[float], target: float = 0.95) -> list[float]:
    p = max((abs(s) for s in samples), default=1.0) or 1.0
    g = target / p
    return [s * g for s in samples]


def pink_noise(n: int, rng: random.Random) -> list[float]:
    # Paul Kellet's refined filter.
    b0 = b1 = b2 = b3 = b4 = b5 = b6 = 0.0
    out = []
    for _ in range(n):
        w = rng.uniform(-1.0, 1.0)
        b0 = 0.99886 * b0 + w * 0.0555179
        b1 = 0.99332 * b1 + w * 0.0750759
        b2 = 0.96900 * b2 + w * 0.1538520
        b3 = 0.86650 * b3 + w * 0.3104856
        b4 = 0.55000 * b4 + w * 0.5329522
        b5 = -0.7616 * b5 - w * 0.0168980
        pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362
        b6 = w * 0.115926
        out.append(pink * 0.11)
    return out


def brown_noise(n: int, rng: random.Random) -> list[float]:
    y = 0.0
    out = []
    for _ in range(n):
        y = (y + rng.uniform(-1.0, 1.0) * 0.02) / 1.02
        out.append(y * 3.2)
    return peak_norm(out, 0.7)


def room_tail(dur: float, rng: random.Random, dark: float = 1800.0) -> list[float]:
    n = int(dur * RATE)
    tail = pink_noise(n, rng)
    for i in range(n):
        t = i / n
        tail[i] *= (1.0 - t) ** 1.7
    return lowpass(tail, dark)


def crack_transient(dur: float, rng: random.Random) -> list[float]:
    """Supersonic crack: impulse + very short band-limited noise. No sine."""
    n = int(dur * RATE)
    out = ones(n)
    # Differentiated impulse (the actual crack is a shock, not a tone).
    if n > 4:
        out[2] = 1.0
        out[3] = -0.85
        out[4] = 0.25
    noise = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    noise = highpass(lowpass(noise, 6500.0), 1800.0)
    for i in range(n):
        env = math.exp(-i / (0.006 * RATE))
        out[i] = out[i] * 0.7 + noise[i] * env * 0.55
    return out


def body_thump(dur: float, freq: float) -> list[float]:
    """Heavily damped low boom — under the noise, never a musical note."""
    n = int(dur * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t / 0.045)
        out.append(math.sin(2.0 * math.pi * freq * t) * env)
    return out


def mix_gun(shot: list[float], rng: random.Random, *,
            extra_pitch: float = 1.0, tail: float = 0.45, boom: float = 0.22,
            crack: float = 0.35, body_hz: float = 95.0) -> list[float]:
    shot = pitch(shot, extra_pitch)
    buf: list[float] = []
    add_at(buf, shot, 0, 1.0)
    add_at(buf, crack_transient(0.04, rng), int(0.002 * RATE), crack)
    add_at(buf, body_thump(0.16, body_hz), 0, boom)
    add_at(buf, room_tail(tail, rng), int(0.012 * RATE), 0.28)
    return fade(peak_norm(buf, 0.95), 0.001, 0.04)


def bake_guns() -> None:
    pistol_src = read_wav(SRC_TMP / "pistol.wav")
    magnum_src = read_wav(SRC_TMP / "magnum.wav")
    black_src = read_wav(SRC_TMP / "blackpowder.wav")
    stock = read_wav(ROOT / "assets" / "audio" / "gunshot.wav")
    sniper = read_wav(ROOT / "assets" / "audio" / "gunshot_sniper.wav")

    pistols = [
        trim_shot(pistol_src, 0.144, 0.42),
        trim_shot(pistol_src, 1.392, 0.38),
        trim_shot(pistol_src, 1.744, 0.38),
    ]
    magnums = [
        trim_shot(magnum_src, 0.236, 0.55),
        trim_shot(magnum_src, 0.936, 0.50),
        trim_shot(magnum_src, 1.660, 0.50),
    ]
    blacks = [
        trim_shot(black_src, 0.148, 0.70),
        trim_shot(black_src, 0.840, 0.70),
        trim_shot(black_src, 1.556, 0.70),
    ]

    rng = random.Random(7)

    # Pistol — close, snappy 9mm. Recorded 22 + stock crack for bite.
    for i, take in enumerate(pistols):
        buf: list[float] = []
        add_at(buf, mix_gun(take, rng, tail=0.38, boom=0.16, crack=0.28, body_hz=110), 0, 1.0)
        add_at(buf, fade(stock, 0.001, 0.08), 0, 0.38)
        write_wav(OUT / f"gun_pistol_{i}.wav", buf)

    # Revolver — heavier, lower, longer room.
    for i, take in enumerate(magnums):
        buf = mix_gun(take, rng, extra_pitch=0.92, tail=0.62, boom=0.38, crack=0.22, body_hz=78)
        write_wav(OUT / f"gun_revolver_{i}.wav", buf)

    # SMG — very short, brighter, quieter so 18 Hz fire doesn't roar.
    for i, take in enumerate(pistols):
        short = fade(pitch(take, 1.18), 0.001, 0.03)[: int(0.095 * RATE)]
        buf = mix_gun(short, rng, tail=0.12, boom=0.08, crack=0.42, body_hz=160)
        write_wav(OUT / f"gun_smg_{i}.wav", fade(buf, 0.001, 0.018))

    # Rifle — stock recorded shot + magnum body, mid pitch.
    for i, take in enumerate(magnums):
        buf = []
        add_at(buf, mix_gun(stock if i == 0 else take, rng, extra_pitch=0.96,
                            tail=0.50, boom=0.28, crack=0.30, body_hz=88), 0, 1.0)
        if i != 0:
            add_at(buf, fade(stock, 0.001, 0.10), 0, 0.45)
        write_wav(OUT / f"gun_rifle_{i}.wav", buf)

    # Shotgun — black-powder boom, extra brown body, long dark tail.
    for i, take in enumerate(blacks):
        buf = mix_gun(pitch(take, 0.84), rng, tail=0.85, boom=0.55, crack=0.18, body_hz=62)
        add_at(buf, lowpass(brown_noise(int(0.28 * RATE), rng), 400.0), 0, 0.35)
        write_wav(OUT / f"gun_shotgun_{i}.wav", buf)

    # Sniper — keep the recorded boom, add a dark room instead of a sine sub.
    for i in range(2):
        buf = []
        add_at(buf, sniper, 0, 1.0)
        add_at(buf, room_tail(0.85, rng, dark=900.0), int(0.02 * RATE), 0.32)
        add_at(buf, body_thump(0.28, 48.0 + i * 4), 0, 0.22)
        write_wav(OUT / f"gun_sniper_{i}.wav", buf)

    # Generic NPC shot — recorded stock + room so cops match the player.
    buf = mix_gun(stock, rng, tail=0.42, boom=0.18, crack=0.25, body_hz=100)
    write_wav(OUT / "gun_generic.wav", buf)


def bake_repulsor() -> None:
    """Movie-style palm discharge: capacitor snap + air whomp + plasma hiss.

    Deliberately not a sine sweep. Iron Man's wrist blast is an electrical
    discharge shoving air, not a chiptune note.
    """
    rng = random.Random(11)
    field0 = read_wav(SRC_TMP / "Audio" / "forceField_000.ogg")
    field1 = read_wav(SRC_TMP / "Audio" / "forceField_001.ogg")
    boom0 = read_wav(SRC_TMP / "Audio" / "lowFrequency_explosion_000.ogg")
    crunch = read_wav(SRC_TMP / "Audio" / "explosionCrunch_000.ogg")
    fields = [field0, field1]

    for i in range(3):
        rng_i = random.Random(11 + i * 17)
        n = int(0.42 * RATE)
        buf = ones(n)

        # 1. Capacitor snap — 3–8 ms impulse + HF hash. The "ignition".
        snap = crack_transient(0.018, rng_i)
        add_at(buf, snap, int(0.006 * RATE), 0.55)

        # 2. Air displacement — damped 55–90 Hz whomp, not a held tone.
        whomp_hz = 58.0 + i * 8.0
        whomp = []
        for k in range(int(0.22 * RATE)):
            t = k / RATE
            env = math.exp(-t / 0.055) * (1.0 - math.exp(-t / 0.004))
            # Slight frequency drop sells mass without becoming a pew.
            f = whomp_hz * (1.0 - 0.28 * min(1.0, t / 0.12))
            whomp.append(math.sin(2.0 * math.pi * f * t) * env)
        add_at(buf, whomp, int(0.004 * RATE), 0.85)
        add_at(buf, lowpass(brown_noise(int(0.18 * RATE), rng_i), 220.0), 0, 0.40)

        # 3. Plasma — band-limited noise that opens then chokes. No oscillator.
        plasma_n = int(0.28 * RATE)
        plasma = [rng_i.uniform(-1.0, 1.0) for _ in range(plasma_n)]
        plasma = highpass(lowpass(plasma, 2400.0 + i * 200), 700.0)
        for k in range(plasma_n):
            t = k / RATE
            env = (1.0 - math.exp(-t / 0.006)) * math.exp(-t / 0.075)
            plasma[k] *= env
        add_at(buf, plasma, int(0.008 * RATE), 0.48)

        # 4. Electrical layer — Kenney force-field, pitched down and short
        #    so it reads as an arc, not a UI blip.
        field = fade(pitch(fields[i % 2], 0.62 + i * 0.04), 0.004, 0.08)[: int(0.22 * RATE)]
        field = highpass(field, 400.0)
        add_at(buf, field, int(0.004 * RATE), 0.28)

        # 5. Soft body from the low-frequency explosion, ducked and faded
        #    so it is weight, not a cartoon boom.
        body = fade(pitch(boom0, 0.85), 0.002, 0.12)[: int(0.26 * RATE)]
        add_at(buf, lowpass(body, 500.0), 0, 0.32)

        # 6. A hint of metal on the first milliseconds (gauntlet).
        if i == 0:
            add_at(buf, fade(crunch, 0.001, 0.06)[: int(0.08 * RATE)], 0, 0.12)

        # High hiss tail — air after the beam, dies fast.
        hiss = highpass([rng_i.uniform(-1.0, 1.0) for _ in range(int(0.20 * RATE))], 4000.0)
        for k in range(len(hiss)):
            hiss[k] *= math.exp(-k / (0.05 * RATE))
        add_at(buf, hiss, int(0.010 * RATE), 0.16)

        write_wav(OUT / f"repulsor_{i}.wav", fade(buf[:n], 0.001, 0.05))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    print("Baking guns…")
    bake_guns()
    print("Baking repulsor…")
    bake_repulsor()
    print("done")


if __name__ == "__main__":
    main()
