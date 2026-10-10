#!/usr/bin/env python3
"""Génère tout le son du jeu par synthèse (aucun fichier externe, aucune licence).

    python3 tools/audio/gen_audio.py          # tout
    python3 tools/audio/gen_audio.py sfx      # bruitages seulement
    python3 tools/audio/gen_audio.py music    # musiques seulement

Sortie : audio/sfx/*.wav (mono 16 bits) et audio/music/*.ogg (stéréo, Vorbis via ffmpeg).
Déterministe : même graine → mêmes fichiers. Godot importe les fichiers à l'ouverture
du projet (ou : godot --headless --path . --import).
"""
import os
import subprocess
import sys
import wave

import numpy as np
from scipy import signal

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SFX_DIR = os.path.join(ROOT, "audio", "sfx")
MUSIC_DIR = os.path.join(ROOT, "audio", "music")
rng = np.random.default_rng(1964)  # Tokyo 1964 : le judo entre aux JO


# --------------------------------------------------------------------------- outils

def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def noise(dur):
    return rng.uniform(-1.0, 1.0, int(dur * SR))


def pink(dur):
    """Bruit rose (filtre de Voss simplifié par filtrage IIR)."""
    w = rng.standard_normal(int(dur * SR))
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1, -2.494956002, 2.017265875, -0.522189400]
    return signal.lfilter(b, a, w) * 3.0


def bandpass(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, f, order=2):
    sos = signal.butter(order, f, btype="low", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x, f, order=2):
    sos = signal.butter(order, f, btype="high", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def sweep_bandpass(x, f0, f1, q=2.0, steps=48):
    """Passe-bande dont la fréquence centrale glisse de f0 à f1 (souffle, whoosh)."""
    out = np.zeros_like(x)
    n = len(x)
    seg = max(1, n // steps)
    win = np.hanning(seg * 2)
    for k in range(steps + 1):
        c = f0 * (f1 / f0) ** (k / steps)
        lo, hi = c / (1 + 0.5 / q), min(c * (1 + 0.5 / q), SR / 2 - 100)
        a = max(0, k * seg - seg)
        b = min(n, a + seg * 2)
        if b <= a:
            continue
        y = bandpass(x[a:b], lo, hi)
        out[a:b] += y * win[: b - a]
    return out


def env(n, attack, decay, sustain=0.0, release=0.0, curve=4.0):
    """Enveloppe ADSR en secondes, renvoie n échantillons."""
    e = np.zeros(n)
    a = int(attack * SR)
    d = int(decay * SR)
    r = int(release * SR)
    s_len = max(0, n - a - d - r)
    i = 0
    if a > 0:
        e[i:i + a] = np.linspace(0, 1, a)[: n - i]
        i += a
    if d > 0 and i < n:
        k = np.linspace(0, 1, d)[: n - i]
        e[i:i + len(k)] = sustain + (1 - sustain) * np.exp(-curve * k)
        i += len(k)
    if i < n:
        e[i:i + s_len] = sustain
        i += s_len
    if r > 0 and i < n:
        k = np.linspace(0, 1, r)[: n - i]
        e[i:i + len(k)] = sustain * np.exp(-curve * k)
    return e


def exp_decay(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def pitch_sine(f_start, f_end, dur, tau=None):
    """Sinus à fréquence glissante exponentielle (fûts, impacts sourds)."""
    n = int(dur * SR)
    tt = np.arange(n) / SR
    if tau is None:
        tau = dur / 3
    f = f_end + (f_start - f_end) * np.exp(-tt / tau)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph)


def saw(freq, dur):
    tt = t_axis(dur)
    f = np.broadcast_to(freq, tt.shape) if np.ndim(freq) else np.full(tt.shape, freq)
    ph = np.cumsum(f) / SR
    return 2.0 * (ph - np.floor(ph + 0.5))


def formant(x, freqs, bws, gains):
    out = np.zeros_like(x)
    for f, bw, g in zip(freqs, bws, gains):
        out += g * bandpass(x, max(40, f - bw / 2), min(SR / 2 - 100, f + bw / 2))
    return out


def reverb(x, size=1.2, mix=0.25, damp=3000.0):
    """Réverbe par convolution avec une queue de bruit décroissante (salle de sport)."""
    n = int(size * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (size * SR / 6.0))
    ir = lowpass(ir, damp)
    ir[:int(0.012 * SR)] = 0  # pré-délai
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    wet = pad_to(signal.fftconvolve(x, ir), len(x) + n)
    dry = np.concatenate([x, np.zeros(n)])
    return dry * (1 - mix) + wet * mix


def pad_to(x, n):
    return np.concatenate([x, np.zeros(max(0, n - len(x)))])[:n] if len(x) != n else x


def mix(*parts):
    n = max(len(p) for p in parts)
    return sum(pad_to(p, n) for p in parts)


def fade(x, fin=0.002, fout=0.01):
    x = x.copy()
    a = int(fin * SR)
    b = int(fout * SR)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def trim(x, thresh=1e-4):
    idx = np.where(np.abs(x) > thresh * np.max(np.abs(x) + 1e-12))[0]
    return x[: idx[-1] + 1] if len(idx) else x


def normalize(x, peak_db=-3.0):
    p = np.max(np.abs(x)) + 1e-12
    return x * (10 ** (peak_db / 20) / p)


def write_wav(path, x):
    x = np.clip(x, -1, 1)
    data = (x * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1 if data.ndim == 1 else 2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def save_sfx(name, x, peak_db=-3.0, verb=None):
    if verb:
        x = reverb(x, *verb)
    x = fade(trim(normalize(x, peak_db)))
    x = normalize(x, peak_db)
    write_wav(os.path.join(SFX_DIR, name + ".wav"), x)
    return len(x) / SR


# --------------------------------------------------------------------------- bruitages

def sfx_ui():
    # déplacement de curseur : clic court, brillant
    tt = t_axis(0.06)
    x = np.sin(2 * np.pi * 1800 * tt) * exp_decay(len(tt), 0.012)
    x += 0.4 * np.sin(2 * np.pi * 3600 * tt) * exp_decay(len(tt), 0.006)
    save_sfx("ui_move", x, -9)
    # onglet : double clic grave
    a = np.sin(2 * np.pi * 900 * t_axis(0.05)) * exp_decay(int(0.05 * SR), 0.01)
    save_sfx("ui_tab", mix(a, np.concatenate([np.zeros(int(0.045 * SR)), a * 0.8])), -9)
    # validation : accord montant + coup de tambour
    parts = []
    for k, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        d = 0.32 - k * 0.04
        tone = (saw(f, d) * 0.3 + np.sin(2 * np.pi * f * t_axis(d))) * env(int(d * SR), 0.003, d * 0.9, 0, 0, 5)
        parts.append(np.concatenate([np.zeros(int(k * 0.035 * SR)), lowpass(tone, 5000)]))
    kick = pitch_sine(180, 60, 0.18, 0.03) * exp_decay(int(0.18 * SR), 0.05)
    save_sfx("ui_accept", mix(*parts, kick * 0.8), -6, (0.5, 0.15, 5000))
    # retour : glissé descendant
    d = 0.16
    f = np.linspace(700, 300, int(d * SR))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(f), 0.003, d, 0, 0, 3)
    save_sfx("ui_back", x, -8)
    # refus : buzz
    d = 0.18
    x = lowpass(saw(110, d) + saw(116, d), 1500) * env(int(d * SR), 0.004, 0.02, 0.8, 0.06)
    save_sfx("ui_error", x, -10)
    # slam du VS : impact + souffle montant
    whoosh = sweep_bandpass(noise(0.35), 300, 6000, 1.5) * np.linspace(0, 1, int(0.35 * SR)) ** 2
    boom = pitch_sine(120, 38, 0.9, 0.08) * exp_decay(int(0.9 * SR), 0.25)
    crack = highpass(noise(0.12), 1500) * exp_decay(int(0.12 * SR), 0.02)
    save_sfx("vs_slam", np.concatenate([whoosh, mix(boom * 1.2, crack * 0.7)]), -2, (1.6, 0.3, 4000))


def sfx_body():
    # saisie du judogi : froissement de coton épais, 4 variantes
    for v in range(4):
        d = 0.16 + 0.03 * v
        n = int(d * SR)
        flutter = 0.6 + 0.4 * np.sin(2 * np.pi * (35 + 9 * v) * t_axis(d) + v)
        x = bandpass(noise(d), 700 + 150 * v, 4500) * flutter * env(n, 0.004, d * 0.8, 0, 0, 4)
        thump = pitch_sine(140, 80, d, 0.02) * exp_decay(n, 0.02) * 0.5
        save_sfx("grip_%d" % v, x + thump, -8)
    # rupture de saisie : claquement sec du tissu
    for v in range(2):
        d = 0.2
        n = int(d * SR)
        snap = highpass(noise(d), 1800) * exp_decay(n, 0.008 + 0.004 * v)
        rustle = bandpass(noise(d), 500, 3000) * exp_decay(n, 0.05) * 0.4
        save_sfx("grip_break_%d" % v, snap + rustle, -6)
    # pas glissés sur le tatami (suri-ashi)
    for v in range(4):
        d = 0.14 + 0.02 * v
        n = int(d * SR)
        x = bandpass(pink(d), 250, 2200) * env(n, 0.02, d * 0.7, 0, 0, 3)
        save_sfx("step_%d" % v, x, -14)
    # souffle d'entrée de technique (whoosh), du plus rapide au plus ample
    for v, (d, f0, f1) in enumerate([(0.22, 600, 3500), (0.3, 400, 3000), (0.42, 250, 2400)]):
        n = int(d * SR)
        shape = np.sin(np.pi * np.linspace(0, 1, n)) ** 1.5
        x = sweep_bandpass(noise(d), f0, f1, 1.8) * shape
        save_sfx("whoosh_%d" % v, x, -6)
    # chute sur le tatami : grosse frappe + claquement des bras (ukemi) + écho de salle
    for name, (f0, f1, tau, slap, dur) in {
        "fall_heavy": (90, 34, 0.18, 1.0, 1.0),
        "fall_medium": (110, 45, 0.12, 0.8, 0.7),
        "fall_light": (140, 60, 0.07, 0.6, 0.45),
    }.items():
        n = int(dur * SR)
        body = pitch_sine(f0, f1, dur, 0.06) * exp_decay(n, tau)
        mat = lowpass(noise(dur), 900) * exp_decay(n, 0.05) * 0.9
        arms = bandpass(noise(dur), 1200, 5000) * exp_decay(n, 0.012) * slap
        arms2 = np.concatenate([np.zeros(int(0.03 * SR)), arms[: n - int(0.03 * SR)] * 0.6])
        save_sfx(name, mix(body * 1.4, mat, arms, arms2), -1, (1.4, 0.22, 3500))
    # garde qui bloque : choc sourd corps contre corps
    d = 0.25
    n = int(d * SR)
    x = pitch_sine(160, 70, d, 0.03) * exp_decay(n, 0.05) + lowpass(noise(d), 1200) * exp_decay(n, 0.03) * 0.6
    save_sfx("block", x, -5)
    # contre : coup de fouet + accent
    d = 0.5
    n = int(d * SR)
    crack = highpass(noise(d), 2500) * exp_decay(n, 0.01)
    hit = pitch_sine(220, 90, d, 0.04) * exp_decay(n, 0.07)
    zing = sweep_bandpass(noise(d), 2000, 7000, 3) * exp_decay(n, 0.12) * 0.5
    save_sfx("counter", mix(crack, hit, zing), -3, (0.8, 0.2, 6000))
    # froissements au sol (ne-waza), boucle courte jouée au hasard
    for v in range(3):
        d = 0.5 + 0.1 * v
        n = int(d * SR)
        am = np.abs(lowpass(rng.standard_normal(n), 9)) * 6
        x = bandpass(pink(d), 400, 3500) * np.clip(am, 0, 1) * env(n, 0.05, d, 0, 0, 2)
        save_sfx("rustle_%d" % v, x, -12)
    # main chassée (bataille de mains) : claque sèche
    for v in range(3):
        d = 0.18
        n = int(d * SR)
        crack = bandpass(noise(d), 1800 + 300 * v, 7000) * exp_decay(n, 0.008)
        thump = pitch_sine(260 - 30 * v, 140, d, 0.01) * exp_decay(n, 0.02) * 0.6
        save_sfx("slap_%d" % v, crack + thump, -4, (0.5, 0.12, 6000))
    # dash : appui explosif, glissé de pieds sur le tatami
    for v in range(2):
        d = 0.22
        n = int(d * SR)
        skid = bandpass(pink(d), 400, 3000) * env(n, 0.004, d * 0.6, 0, 0, 5)
        air = sweep_bandpass(noise(d), 900, 2600 + 600 * v, 2.0) * np.sin(np.pi * np.linspace(0, 1, n)) * 0.6
        save_sfx("dash_%d" % v, skid + air, -7)
    # action-réaction : accent percussif court (le moment à saisir)
    d = 0.5
    n = int(d * SR)
    hit = pitch_sine(320, 160, d, 0.02) * exp_decay(n, 0.06) + bandpass(noise(d), 3000, 9000) * exp_decay(n, 0.015) * 0.5
    ring = np.sin(2 * np.pi * 1320 * t_axis(d)) * exp_decay(n, 0.12) * 0.25
    save_sfx("reaction", hit + ring, -5, (0.8, 0.2, 6000))
    # tape (abandon) : trois tapes sur le tatami
    tap = bandpass(noise(0.08), 600, 4000) * exp_decay(int(0.08 * SR), 0.01) + pitch_sine(200, 120, 0.08, 0.01) * exp_decay(int(0.08 * SR), 0.015)
    gap = np.zeros(int(0.17 * SR))
    save_sfx("tap_out", np.concatenate([tap, gap, tap * 0.9, gap, tap * 0.95]), -4, (0.9, 0.15, 4000))


def voice(f0_start, f0_end, dur, vowel="a", breath=0.25, growl=0.0):
    """Voix synthétique (source glottale + formants), pour les kiai."""
    n = int(dur * SR)
    tt = np.arange(n) / SR
    f0 = f0_end + (f0_start - f0_end) * np.exp(-tt / (dur / 2.5))
    f0 = f0 * (1 + 0.012 * np.sin(2 * np.pi * 5.5 * tt))
    src = saw(f0, dur)
    src = lowpass(src, 3500)
    if growl:
        src *= 1 + growl * np.sin(2 * np.pi * 70 * tt)
    vow = {
        "a": ([800, 1200, 2600, 3400], [120, 140, 200, 250], [1.0, 0.6, 0.25, 0.12]),
        "e": ([550, 1800, 2600, 3400], [100, 140, 200, 250], [1.0, 0.5, 0.25, 0.1]),
        "o": ([520, 900, 2500, 3300], [100, 120, 200, 250], [1.0, 0.5, 0.15, 0.08]),
        "i": ([320, 2300, 3000, 3600], [80, 160, 200, 250], [1.0, 0.35, 0.25, 0.1]),
    }[vowel]
    v = formant(src, *vow)
    br = bandpass(noise(dur), 1000, 6000) * breath
    return v + br


def sfx_voices():
    # kiai : deux timbres (P1 plus grave, P2 plus aigu), quelques variantes
    for who, base in [(0, 150), (1, 175)]:
        for v, (vow, k, d) in enumerate([("a", 1.0, 0.32), ("e", 1.08, 0.28), ("o", 0.95, 0.38)]):
            n = int(d * SR)
            x = voice(base * k * 1.35, base * k, d, vow, 0.3, 0.15)
            h = bandpass(noise(0.06), 1200, 5000) * exp_decay(int(0.06 * SR), 0.02) * 0.6  # attaque "h"
            x = mix(h, np.concatenate([np.zeros(int(0.02 * SR)), x * env(n, 0.012, d * 0.6, 0.3, d * 0.3, 3)]))
            save_sfx("kiai_%d_%d" % (who, v), x, -4, (0.7, 0.18, 5000))
        # effort au sol (souffle tendu)
        d = 0.45
        n = int(d * SR)
        x = voice(base * 0.9, base * 0.85, d, "i", 0.6) * 0.5 + bandpass(noise(d), 800, 3000) * 0.4
        save_sfx("grunt_%d" % who, x * env(n, 0.05, d, 0, 0, 2.5), -9)
    # arbitre : appels courts, voix grave et autoritaire (« ha-jime », « ma-te »…)
    def word(syl, gap=0.02):
        out = []
        for (vow, f0, d, cons) in syl:
            n = int(d * SR)
            c = {"h": bandpass(noise(0.07), 1000, 5000) * 0.6,
                 "m": lowpass(saw(f0, 0.06), 400) * 0.7,
                 "t": highpass(noise(0.03), 2500) * exp_decay(int(0.03 * SR), 0.006) * 1.2,
                 "p": bandpass(noise(0.03), 600, 3000) * exp_decay(int(0.03 * SR), 0.006) * 1.2,
                 "k": highpass(noise(0.035), 1500) * exp_decay(int(0.035 * SR), 0.008) * 1.2,
                 "s": highpass(noise(0.1), 4000) * 0.5,
                 "dj": highpass(noise(0.07), 2500) * 0.5,
                 "": np.zeros(1)}[cons]
            vv = voice(f0 * 1.1, f0, d, vow, 0.12) * env(n, 0.01, d * 0.5, 0.6, d * 0.35, 3)
            out += [c, vv, np.zeros(int(gap * SR))]
        return np.concatenate(out)
    calls = {
        "ref_hajime": [("a", 125, 0.16, "h"), ("i", 140, 0.12, "dj"), ("e", 118, 0.28, "m")],
        "ref_matte": [("a", 135, 0.16, "m"), ("e", 115, 0.3, "t")],
        "ref_ippon": [("i", 150, 0.16, ""), ("o", 125, 0.42, "p")],
        "ref_wazaari": [("a", 135, 0.14, ""), ("a", 130, 0.12, "dj"), ("a", 140, 0.1, ""), ("i", 120, 0.28, "")],
        "ref_osaekomi": [("o", 125, 0.12, ""), ("a", 130, 0.1, "s"), ("e", 135, 0.1, ""), ("o", 125, 0.1, "k"), ("i", 118, 0.26, "m")],
        "ref_toketa": [("o", 130, 0.12, "t"), ("e", 135, 0.12, "k"), ("a", 115, 0.26, "t")],
        "ref_shido": [("i", 130, 0.14, "s"), ("o", 115, 0.3, "t")],
        "ref_soremade": [("o", 125, 0.12, "s"), ("e", 130, 0.12, ""), ("a", 135, 0.12, "m"), ("e", 112, 0.3, "t")],
    }
    for name, syl in calls.items():
        save_sfx(name, word(syl), -5, (1.3, 0.3, 4500))


def sfx_arena():
    # taiko (hajime / début de combat)
    d = 1.4
    n = int(d * SR)
    body = pitch_sine(140, 58, d, 0.05) * exp_decay(n, 0.35)
    skin = lowpass(noise(d), 700) * exp_decay(n, 0.04) * 0.8
    save_sfx("taiko", body * 1.3 + skin, -2, (1.8, 0.3, 3000))
    d = 0.5
    n = int(d * SR)
    save_sfx("taiko_small", pitch_sine(220, 110, d, 0.03) * exp_decay(n, 0.12) + lowpass(noise(d), 1500) * exp_decay(n, 0.02) * 0.5, -4, (1.0, 0.25, 4000))
    # hyoshigi (claquoir en bois) pour matte
    d = 0.35
    n = int(d * SR)
    wood = sum(np.sin(2 * np.pi * f * t_axis(d)) * exp_decay(n, tau) for f, tau in [(1850, 0.03), (2900, 0.02), (4300, 0.012)])
    save_sfx("clack", wood + highpass(noise(d), 3000) * exp_decay(n, 0.004), -4, (1.2, 0.3, 6000))
    # gong de fin de combat
    d = 4.0
    n = int(d * SR)
    tt = t_axis(d)
    partials = [(1.0, 1.0, 1.6), (2.02, 0.6, 1.2), (2.74, 0.5, 1.0), (3.76, 0.35, 0.8), (5.4, 0.2, 0.5), (6.8, 0.12, 0.3)]
    g = sum(a * np.sin(2 * np.pi * 98 * r * tt * (1 + 0.002 * np.sin(2 * np.pi * 0.7 * tt))) * exp_decay(n, tau) for r, a, tau in partials)
    g *= np.minimum(1, tt / 0.01)
    save_sfx("gong", g, -2, (2.5, 0.25, 3000))
    # chrono : tic des dernières secondes et tic d'osaekomi
    d = 0.08
    n = int(d * SR)
    save_sfx("tick", np.sin(2 * np.pi * 2100 * t_axis(d)) * exp_decay(n, 0.008) + highpass(noise(d), 4000) * exp_decay(n, 0.002) * 0.4, -10)
    save_sfx("tock", np.sin(2 * np.pi * 1300 * t_axis(d)) * exp_decay(n, 0.01), -10)
    # buzzer de pénalité (shido) : grave et court
    d = 0.4
    x = lowpass(saw(98, d) + saw(98 * 1.5, d) * 0.6, 1800) * env(int(d * SR), 0.005, 0.05, 0.7, 0.12)
    save_sfx("buzzer", x, -8)
    # stingers d'annonce
    def stinger(notes, dur, bright):
        parts = []
        for k, (f, delay) in enumerate(notes):
            dd = dur - delay
            n2 = int(dd * SR)
            tone = (saw(f, dd) + saw(f * 1.005, dd) + 0.5 * saw(f * 2, dd)) * env(n2, 0.005, dd * 0.6, 0.25, dd * 0.3, 3)
            parts.append(np.concatenate([np.zeros(int(delay * SR)), lowpass(tone, bright)]))
        return mix(*parts)
    d = 2.4
    boom = pitch_sine(110, 36, d, 0.1) * exp_decay(int(d * SR), 0.5) * 1.6
    crash = highpass(noise(d), 3000) * exp_decay(int(d * SR), 0.45) * 0.45
    ipp = stinger([(220, 0), (277.18, 0.0), (329.63, 0.0), (440, 0.08), (554.37, 0.08), (659.25, 0.08)], d, 4500)
    save_sfx("stinger_ippon", mix(boom, crash, ipp * 0.5), -1, (2.4, 0.3, 5000))
    d = 1.2
    wz = stinger([(293.66, 0), (369.99, 0.0), (440, 0.06), (587.33, 0.06)], d, 4000)
    save_sfx("stinger_wazaari", mix(pitch_sine(140, 50, d, 0.06) * exp_decay(int(d * SR), 0.2), wz * 0.5), -2, (1.6, 0.25, 5000))
    d = 0.9
    save_sfx("stinger_osaekomi", mix(stinger([(196, 0), (246.94, 0.04), (293.66, 0.08)], d, 3000) * 0.5,
                                    pitch_sine(120, 60, d, 0.05) * exp_decay(int(d * SR), 0.15)), -4, (1.2, 0.25, 4000))


def crowd_layer(dur, density=40, f_lo=250, f_hi=2600):
    """Brouhaha : beaucoup de « voix » de bruit formanté avec modulations lentes."""
    n = int(dur * SR)
    base = bandpass(pink(dur), f_lo, f_hi)
    am = np.zeros(n)
    for _ in range(density):
        rate = rng.uniform(1.5, 5.0)
        ph = rng.uniform(0, 2 * np.pi)
        am += np.clip(np.sin(2 * np.pi * rate * np.arange(n) / SR + ph), 0, 1) ** 2
    am /= density
    return base * (0.6 + am)


def loopable(x, xfade=1.0):
    """Rend une boucle continue par fondu enchaîné fin → début."""
    k = int(xfade * SR)
    head, body, tail = x[:k], x[k:-k], x[-k:]
    w = np.linspace(0, 1, k)
    return np.concatenate([body, tail * (1 - w) + head * w])


def sfx_crowd():
    # ambiance de salle en boucle (12 s)
    x = crowd_layer(14.0, 60) + 0.25 * lowpass(pink(14.0), 300)
    x = reverb(x, 1.5, 0.35, 3000)[: int(14.0 * SR)]
    write_wav(os.path.join(SFX_DIR, "crowd_loop.wav"), normalize(loopable(x), -6))
    # montée de foule (attaque dangereuse, osaekomi qui dure)
    d = 2.5
    n = int(d * SR)
    x = crowd_layer(d, 80, 300, 3200) * np.linspace(0.2, 1, n) ** 1.5 * env(n, 0.3, d, 0.0, 0, 1.0)
    save_sfx("crowd_ooh", x + voice(330, 300, d, "o", 0.6) * 0.15 * np.sin(np.pi * np.linspace(0, 1, n)), -4)
    # acclamation (waza-ari / ippon)
    for name, d, amt in [("crowd_cheer", 3.5, 1.0), ("crowd_cheer_small", 2.0, 0.6)]:
        n = int(d * SR)
        whoop = sum(voice(rng.uniform(250, 420), rng.uniform(300, 500), d, rng.choice(["a", "o", "e"]), 0.4) * rng.uniform(0.02, 0.06) for _ in range(8))
        claps = np.zeros(n)
        for _ in range(int(220 * d * amt)):
            p = rng.integers(0, n - 2000)
            claps[p:p + 1500] += bandpass(noise(1500 / SR), 800, 5000) * exp_decay(1500, 0.004) * rng.uniform(0.2, 1.0)
        shape = env(n, 0.08, d, 0.0, 0, 1.6)
        x = (crowd_layer(d, 90, 300, 3500) * 1.2 + whoop + claps * 0.25) * shape
        save_sfx(name, x, -3 if amt == 1 else -6, (1.4, 0.3, 4000))


# --------------------------------------------------------------------------- musique

BPM_MATCH = 132


def note_hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def ks_fast(f, dur, bright=0.5, decay=0.996):
    """Version vectorisée par blocs de période (bien plus rapide)."""
    n = int(dur * SR)
    p = max(2, int(round(SR / f)))
    buf = rng.uniform(-1, 1, p)
    if bright < 1:
        buf = lowpass(np.tile(buf, 4), 800 + 9000 * bright)[-p:]
    out = np.empty(n)
    i = 0
    while i < n:
        k = min(p, n - i)
        out[i:i + k] = buf[:k]
        buf = decay * 0.5 * (buf + np.roll(buf, -1))
        i += k
    return out


def drum_kit():
    kit = {}
    d = 0.6
    kit["taiko"] = pitch_sine(120, 52, d, 0.04) * exp_decay(int(d * SR), 0.18) * 1.2 + lowpass(noise(d), 600) * exp_decay(int(d * SR), 0.03) * 0.5
    d = 0.35
    kit["shime"] = pitch_sine(420, 300, d, 0.01) * exp_decay(int(d * SR), 0.05) * 0.7 + bandpass(noise(d), 1500, 6000) * exp_decay(int(d * SR), 0.012) * 0.5
    d = 0.18
    kit["kick"] = pitch_sine(150, 45, d, 0.025) * exp_decay(int(d * SR), 0.07)
    d = 0.25
    kit["snare"] = bandpass(noise(d), 1200, 8000) * exp_decay(int(d * SR), 0.05) * 0.7 + pitch_sine(260, 180, d, 0.02) * exp_decay(int(d * SR), 0.04) * 0.5
    d = 0.06
    kit["hat"] = highpass(noise(d), 7000) * exp_decay(int(d * SR), 0.012) * 0.35
    d = 0.5
    kit["ohat"] = highpass(noise(d), 6500) * exp_decay(int(d * SR), 0.12) * 0.25
    d = 0.12
    kit["clack"] = sum(np.sin(2 * np.pi * f * t_axis(d)) * exp_decay(int(d * SR), 0.02) for f in [1850, 2900]) * 0.4
    return kit


def place(track, x, t, gain=1.0, pan=0.0):
    i = int(t * SR)
    if i >= track.shape[1]:
        return
    k = min(len(x), track.shape[1] - i)
    l = np.cos((pan + 1) * np.pi / 4)
    r = np.sin((pan + 1) * np.pi / 4)
    track[0, i:i + k] += x[:k] * gain * l
    track[1, i:i + k] += x[:k] * gain * r


def synth_bass(f, dur):
    n = int(dur * SR)
    x = saw(f, dur) * 0.6 + np.sin(2 * np.pi * f * t_axis(dur)) * 0.8
    cutoff_env = env(n, 0.003, dur * 0.7, 0.15, 0.02, 4)
    # filtre dynamique simplifié : mélange passe-bas fermé / ouvert
    closed = lowpass(x, 300)
    opened = lowpass(x, 2200)
    return (closed * (1 - cutoff_env) + opened * cutoff_env) * env(n, 0.004, dur, 0.85, 0.03, 2)


def synth_lead(f, dur, vib=True):
    n = int(dur * SR)
    tt = t_axis(dur)
    fm = f * (1 + (0.006 * np.sin(2 * np.pi * 5.8 * tt) * np.clip(tt / 0.25, 0, 1) if vib else 0))
    x = saw(fm, dur) + saw(fm * 1.007, dur) * 0.8 + saw(fm * 0.5, dur) * 0.3
    return lowpass(x, 3200) * env(n, 0.01, 0.2, 0.6, min(0.08, dur * 0.3), 2) * 0.35


def synth_pad(freqs, dur):
    n = int(dur * SR)
    x = sum(saw(f * (1 + d), dur) for f in freqs for d in (-0.004, 0.0, 0.005))
    return lowpass(x, 1400) * env(n, dur * 0.3, 0.1, 1.0, dur * 0.3, 2) * 0.08


def shakuhachi(f, dur):
    n = int(dur * SR)
    tt = t_axis(dur)
    fm = f * (1 + 0.01 * np.sin(2 * np.pi * 4.5 * tt) * np.clip((tt - 0.3) / 0.4, 0, 1))
    tone = np.sin(2 * np.pi * np.cumsum(fm) / SR) + 0.25 * np.sin(4 * np.pi * np.cumsum(fm) / SR)
    breath = bandpass(noise(dur), f * 1.5, min(f * 6, 9000)) * 0.35
    return (tone + breath) * env(n, 0.12, 0.3, 0.75, dur * 0.35, 2) * 0.4


# gamme : mode mineur (dorien) avec la saveur « in » japonaise sur la mélodie
SCALE_IN = [0, 1, 5, 7, 10]  # miyako-bushi (in sen)
SCALE_MIN = [0, 2, 3, 5, 7, 8, 10]


def music_match():
    beat = 60.0 / BPM_MATCH
    bars = 16
    dur = bars * 4 * beat
    tr = np.zeros((2, int(dur * SR) + SR * 2))
    kit = drum_kit()
    root = 45  # la grave
    prog = [0, 0, -4, -2, 0, 0, -5, -2]  # Am Am F G Am Am E G (en demi-tons depuis la)
    for bar in range(bars):
        t0 = bar * 4 * beat
        section = bar // 4  # 0 intro, 1 groove, 2 tension, 3 sommet
        # batterie
        for s in range(16):
            t = t0 + s * beat / 4
            if s in (0, 6, 8, 11) or (section >= 2 and s == 14):
                place(tr, kit["kick"], t, 0.9)
            if s in (4, 12):
                place(tr, kit["snare"], t, 0.55 if section else 0.3, 0.1)
            if s % 2 == 0:
                place(tr, kit["hat"], t, 0.5 if s % 4 else 0.8, 0.35)
            elif section >= 1:
                place(tr, kit["hat"], t, 0.3, 0.35)
            if s == 14 and section >= 1:
                place(tr, kit["ohat"], t, 0.6, 0.35)
        # taiko : gros temps et roulement en fin de phrase
        place(tr, kit["taiko"], t0, 0.8, -0.2)
        if bar % 4 == 3:
            for k in range(4 if section < 3 else 8):
                place(tr, kit["shime"], t0 + 2 * beat + k * beat / (2 if section < 3 else 4), 0.5, 0.3)
        if bar % 2 == 1:
            place(tr, kit["clack"], t0 + 3.5 * beat, 0.5, -0.4)
        # basse (croches syncopées)
        r = root + prog[bar % 8]
        for s, oct_ in [(0, 0), (3, 0), (6, 12), (8, 0), (10, 0), (11, 12), (14, 0)]:
            place(tr, synth_bass(note_hz(r + oct_), beat * 0.45), t0 + s * beat / 4, 0.55)
        # nappe
        if section >= 1:
            chord = [note_hz(r + 12 + k) for k in (0, 3, 7)] if prog[bar % 8] != -5 else [note_hz(r + 12 + k) for k in (0, 4, 7)]
            place(tr, synth_pad(chord, 4 * beat), t0, 0.8, 0.0)
        # mélodie : motif pentatonique « in », plus dense au sommet
        if section >= 2:
            motif = [(0, 12, 2), (2, 13, 1), (3, 17, 1), (4, 19, 3), (7, 17, 1)] if bar % 2 == 0 else [(0, 22, 2), (2, 19, 1), (3, 17, 2), (5, 13, 1), (6, 12, 2)]
            for (pos, deg, ln) in motif:
                place(tr, synth_lead(note_hz(root + 12 + deg), ln * beat / 2 * 0.95), t0 + pos * beat / 2, 0.55 if section == 3 else 0.4, 0.15)
        # koto en contre-chant
        if section in (1, 3):
            for k, deg in enumerate([0, 7, 12, 10, 7, 5, 1, 0]):
                place(tr, ks_fast(note_hz(root + 24 + deg), beat * 1.2, 0.7, 0.995), t0 + k * beat / 2, 0.22, -0.45)
    out = tr[:, : int(dur * SR)]
    # queue de réverbe repliée au début pour une boucle propre
    wet = np.stack([reverb(out[c], 1.2, 0.18, 6000) for c in range(2)])
    tail = wet[:, int(dur * SR):]
    wet = wet[:, : int(dur * SR)]
    wet[:, : tail.shape[1]] += tail
    return wet


def music_menu():
    bpm = 96
    beat = 60.0 / bpm
    bars = 8
    dur = bars * 4 * beat
    tr = np.zeros((2, int(dur * SR) + SR * 3))
    kit = drum_kit()
    root = 50  # ré
    prog = [0, -2, -4, -5]
    for bar in range(bars):
        t0 = bar * 4 * beat
        r = root + prog[bar % 4]
        place(tr, kit["taiko"], t0, 0.7, -0.1)
        place(tr, kit["taiko"], t0 + 2.5 * beat, 0.45, -0.1)
        if bar >= 2:
            for s in range(8):
                place(tr, kit["hat"], t0 + s * beat / 2, 0.35 if s % 2 else 0.55, 0.3)
            place(tr, kit["snare"], t0 + beat, 0.3)
            place(tr, kit["snare"], t0 + 3 * beat, 0.3)
        chord = [note_hz(r + 12 + k) for k in (0, 3, 7, 10)]
        place(tr, synth_pad(chord, 4 * beat), t0, 1.0)
        for s in (0, 3, 4, 7):
            place(tr, synth_bass(note_hz(r), beat * 0.4), t0 + s * beat / 2, 0.45)
        # arpège de koto
        for k in range(8):
            deg = [0, 7, 12, 15, 19, 15, 12, 7][k]
            place(tr, ks_fast(note_hz(r + 24 + deg), beat * 1.5, 0.6, 0.996), t0 + k * beat / 2, 0.2, 0.4 - 0.1 * (k % 3))
        if bar >= 4:
            mel = [(0, 24, 3), (3, 22, 1), (4, 19, 2), (6, 17, 2)] if bar % 2 == 0 else [(0, 15, 2), (2, 17, 2), (4, 12, 4)]
            for pos, deg, ln in mel:
                place(tr, shakuhachi(note_hz(root + deg), ln * beat / 2 * 1.1), t0 + pos * beat / 2, 0.5, -0.2)
    out = tr[:, : int(dur * SR)]
    wet = np.stack([reverb(out[c], 2.2, 0.3, 5000) for c in range(2)])
    tail = wet[:, int(dur * SR):]
    wet = wet[:, : int(dur * SR)]
    wet[:, : tail.shape[1]] += tail
    return wet


def music_dojo():
    """Dojo / entraînement : calme, flûte et koto, pas de batterie lourde."""
    bpm = 72
    beat = 60.0 / bpm
    bars = 8
    dur = bars * 4 * beat
    tr = np.zeros((2, int(dur * SR) + SR * 4))
    kit = drum_kit()
    root = 52  # mi
    prog = [0, 1, 0, -2]
    for bar in range(bars):
        t0 = bar * 4 * beat
        r = root + prog[bar % 4]
        place(tr, kit["taiko"], t0, 0.35)
        place(tr, kit["clack"], t0 + 3 * beat, 0.25, 0.5)
        place(tr, synth_pad([note_hz(r + 12), note_hz(r + 19), note_hz(r + 24)], 4 * beat), t0, 0.8)
        for k, deg in enumerate([0, 5, 7, 12, 13, 12, 7, 5]):
            if k % 2 == 0 or bar % 2:
                place(tr, ks_fast(note_hz(root + 12 + deg), beat * 2, 0.45, 0.997), t0 + k * beat / 2, 0.22, 0.3)
        if bar % 2 == 0:
            place(tr, shakuhachi(note_hz(root + 24 + [0, 1, 5, 7][bar // 2 % 4]), 3 * beat), t0 + beat * 0.5, 0.45, -0.25)
    out = tr[:, : int(dur * SR)]
    wet = np.stack([reverb(out[c], 2.8, 0.38, 4500) for c in range(2)])
    tail = wet[:, int(dur * SR):]
    wet = wet[:, : int(dur * SR)]
    wet[:, : tail.shape[1]] += tail
    return wet


def music_victory():
    beat = 60.0 / 120
    dur = 6.0
    tr = np.zeros((2, int(dur * SR) + SR * 3))
    kit = drum_kit()
    for k in range(6):
        place(tr, kit["shime"], k * beat / 4, 0.5)
    place(tr, kit["taiko"], 1.5 * beat, 1.0)
    root = 57
    for k, deg in enumerate([0, 4, 7, 12]):
        place(tr, synth_lead(note_hz(root + deg), beat * 0.5), 1.5 * beat + k * beat / 2, 0.5)
    chord = [note_hz(root + k) for k in (0, 4, 7, 12, 16)]
    place(tr, synth_pad(chord, 3.5) * 3, 3.5 * beat, 1.0)
    place(tr, synth_lead(note_hz(root + 12), 2.0, True), 3.5 * beat, 0.5)
    place(tr, kit["taiko"], 3.5 * beat, 1.0)
    out = tr
    wet = np.stack([reverb(out[c], 2.0, 0.3, 5000) for c in range(2)])
    return trim_stereo(wet)


def trim_stereo(x):
    m = np.max(np.abs(x), axis=0)
    idx = np.where(m > 1e-4 * m.max())[0]
    return x[:, : idx[-1] + 1]


def save_music(name, st, peak_db=-4.0):
    st = st / (np.max(np.abs(st)) + 1e-9) * 10 ** (peak_db / 20)
    tmp = os.path.join(MUSIC_DIR, name + ".tmp.wav")
    write_wav(tmp, st.T.copy())
    out = os.path.join(MUSIC_DIR, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "5", out], check=True)
    os.remove(tmp)
    return st.shape[1] / SR


def main():
    what = sys.argv[1:] or ["sfx", "music"]
    os.makedirs(SFX_DIR, exist_ok=True)
    os.makedirs(MUSIC_DIR, exist_ok=True)
    if "sfx" in what:
        sfx_ui()
        sfx_body()
        sfx_voices()
        sfx_arena()
        sfx_crowd()
        print("bruitages :", len([f for f in os.listdir(SFX_DIR) if f.endswith(".wav")]))
    if "music" in what:
        for name, fn in [("match", music_match), ("menu", music_menu), ("dojo", music_dojo), ("victory", music_victory)]:
            print("musique %s : %.1f s" % (name, save_music(name, fn())))


if __name__ == "__main__":
    main()
