#!/usr/bin/env python3
"""챔피언 배경음악 생성기.

    python3 tools/audio/make_music.py

audio/music/ 에 경기장 음악(arena.ogg), 메뉴 음악(menu.ogg), 승리/패배 짧은 음악을 만든다.
악기 소리부터 악보까지 전부 이 파일 안의 코드로 만든 오리지널이다 (샘플, 녹음 없음).
반복 음악은 끝의 울림을 처음에 겹쳐 놓아서 이어 틀어도 끊김이 없다.
필요: numpy, scipy, ffmpeg(libvorbis)
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
import scipy.signal as sg

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from synth import SR, T, ad, drop_sine, expenv, hp, lp, n_of, bp, write_wav  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "audio", "music")


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def saw_band(f, d, maxf=8000.0, phase=None, rng=None):
    t = T(d)
    K = int(max(1, min(maxf / f, 60)))
    out = np.zeros_like(t)
    ph = 0.0 if rng is None else rng.uniform(0, 2 * np.pi)
    for k in range(1, K + 1):
        out += np.sin(2 * np.pi * k * f * t + ph * k) / k
    return out * 0.55


def env_adsr(d, a, dcy, s, r, total=None):
    """a: 올라가는 시간, dcy: 줄어드는 시간, s: 유지 크기, r: 놓은 뒤 사라지는 시간."""
    total = total or d + r
    t = T(total)
    e = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(dcy, 1e-4)))
    rel = np.clip(1 - (t - d) / max(r, 1e-4), 0, 1)
    return e * np.where(t > d, rel, 1.0)


class Song:
    def __init__(self, bpm, bars, seed, tail=4.0):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.bars = bars
        self.length = bars * 4 * self.beat
        self.n = n_of(self.length)
        total = self.n + n_of(tail)
        self.dry = np.zeros((2, total))
        self.send = np.zeros((2, total))
        self.rng = np.random.default_rng(seed)

    def t(self, bar, beat=0.0):
        return (bar * 4 + beat) * self.beat

    def put(self, x, time, pan=0.0, gain=1.0, rev=0.2):
        s = n_of(time)
        if s >= self.dry.shape[1]:
            return
        x = x[: self.dry.shape[1] - s] * gain
        a = (pan + 1) * np.pi / 4
        l, r = x * np.cos(a), x * np.sin(a)
        self.dry[0, s:s + len(x)] += l
        self.dry[1, s:s + len(x)] += r
        if rev > 0:
            self.send[0, s:s + len(x)] += l * rev
            self.send[1, s:s + len(x)] += r * rev

    def render(self, rt60=1.8, wet=0.35, target_rms_db=-17.0):
        rng = self.rng
        out = self.dry.copy()
        for ch in range(2):
            d = rt60 * 1.3
            tt = T(d)
            ir = rng.normal(0, 1, len(tt)) * np.exp(-tt * 6.9 / rt60)
            ir = lp(ir, 5000)
            ir[: n_of(0.02)] = 0
            ir /= np.sqrt(np.sum(ir ** 2))
            w = sg.fftconvolve(self.send[ch], ir)[: out.shape[1]]
            out[ch] += w * wet
        # 끝의 울림을 처음에 겹친다 → 반복할 때 이음매가 없다
        loop = out[:, : self.n].copy()
        tail = out[:, self.n:]
        loop[:, : tail.shape[1]] += tail
        return master(loop, target_rms_db)

    def render_oneshot(self, rt60=1.8, wet=0.35, target_rms_db=-16.0):
        rng = self.rng
        out = self.dry.copy()
        for ch in range(2):
            tt = T(rt60 * 1.3)
            ir = rng.normal(0, 1, len(tt)) * np.exp(-tt * 6.9 / rt60)
            ir = lp(ir, 5000)
            ir[: n_of(0.02)] = 0
            ir /= np.sqrt(np.sum(ir ** 2))
            out[ch] += sg.fftconvolve(self.send[ch], ir)[: out.shape[1]] * wet
        a = np.abs(out).max(axis=0)
        idx = np.where(a > a.max() * 10 ** (-50 / 20))[0]
        out = out[:, : idx[-1] + n_of(0.05)]
        fo = n_of(0.3)
        out[:, -fo:] *= np.linspace(1, 0, fo)
        return master(out, target_rms_db)


def master(x, target_rms_db):
    x = np.vstack([hp(x[0], 38), hp(x[1], 38)])
    # 노트북/핸드폰 스피커에서도 잘 들리게 높은 쪽을 살짝 살린다
    x = x + np.vstack([hp(x[0], 1800), hp(x[1], 1800)]) * 0.45
    rms = np.sqrt(np.mean(x ** 2))
    x = x / rms * 10 ** (target_rms_db / 20)
    # 부드럽게 눌러서 튀는 소리를 막는다
    x = np.tanh(x * 1.4) / 1.4
    peak = np.abs(x).max()
    if peak > 0.89:
        x *= 0.89 / peak
    return x


# ------------------------------------------------------------------
# 악기
# ------------------------------------------------------------------

def kick(rng):
    d = 0.45
    x = drop_sine(d, 160, 46, 32) * ad(d, 0.001, 7)
    x += hp(rng.uniform(-1, 1, n_of(d)), 2500) * expenv(d, 200) * 0.25
    return np.tanh(x * 1.6)


def snare(rng):
    d = 0.32
    x = bp(rng.uniform(-1, 1, n_of(d)), 1200, 9000) * expenv(d, 16) * 0.8
    x += drop_sine(d, 260, 180, 30) * expenv(d, 25) * 0.6
    return x


def clap(rng):
    d = 0.3
    x = np.zeros(n_of(d))
    for k, dt in enumerate([0.0, 0.011, 0.022]):
        s = n_of(dt)
        m = n_of(d) - s
        b = bp(rng.uniform(-1, 1, m), 900, 4000) * np.exp(-np.arange(m) / SR * (60 if k < 2 else 14))
        x[s:] += b
    return x * 0.7


def hat(rng, open_=False):
    d = 0.3 if open_ else 0.06
    return hp(rng.uniform(-1, 1, n_of(d)), 7000) * expenv(d, 9 if open_ else 70) * 0.5


def shaker(rng):
    d = 0.08
    return bp(rng.uniform(-1, 1, n_of(d)), 4000, 11000) * ad(d, 0.015, 40) * 0.4


def taiko(rng, f=70.0, d=0.9):
    x = drop_sine(d, f * 2.2, f, 18) * ad(d, 0.002, 4.5)
    x += lp(rng.uniform(-1, 1, n_of(d)), 900) * expenv(d, 25) * 0.6
    x += bp(rng.uniform(-1, 1, n_of(d)), 1500, 5000) * expenv(d, 90) * 0.2
    return np.tanh(x * 1.3)


def tom(rng, f):
    return taiko(rng, f, 0.5) * 0.7


def crash(rng, d=2.2):
    x = hp(rng.uniform(-1, 1, n_of(d)), 4000) * ad(d, 0.002, 1.8) * 0.5
    return x


def riser(rng, d):
    nz = rng.uniform(-1, 1, n_of(d))
    t = np.linspace(0, 1, n_of(d))
    x = hp(nz, 1500) * t ** 2.5
    return x * 0.5


def bass(f, d, rng, bright=1.0):
    x = saw_band(f, d + 0.05, 2500, rng=rng)
    dark = lp(x, 350)
    brt = lp(x, 900 * bright)
    e = env_adsr(d, 0.004, 0.12, 0.7, 0.05, d + 0.05)
    fe = np.exp(-T(d + 0.05) * 14)
    y = dark * (1 - fe) + brt * fe
    y += np.sin(2 * np.pi * f * T(d + 0.05)) * 0.35
    return y * e


def pluck(f, d, rng, cut=2600):
    x = saw_band(f, d + 0.15, 7000, rng=rng) + saw_band(f * 1.004, d + 0.15, 7000, rng=rng)
    fe = np.exp(-T(d + 0.15) * 22)
    y = lp(x, 700) * (1 - fe) + lp(x, cut) * fe
    return y * env_adsr(d, 0.002, 0.09, 0.25, 0.1, d + 0.15) * 0.5


def pad(freqs, d, rng, cut=1500, attack=0.35, release=0.8):
    total = d + release
    out = np.zeros(n_of(total))
    for f in freqs:
        for det in (-0.006, 0.0, 0.0065):
            out += saw_band(f * (1 + det), total, 2400, rng=rng)
    out = lp(out, cut, 2)
    return out * env_adsr(d, attack, 0.6, 0.85, release, total) / len(freqs) * 0.5


def brass(freqs, d, rng, cut_hi=3200, cut_lo=1100):
    total = d + 0.25
    out = np.zeros(n_of(total))
    for f in freqs:
        for det in (-0.004, 0.004):
            out += saw_band(f * (1 + det), total, 6000, rng=rng)
    fe = np.exp(-T(total) * 6)
    y = lp(out, cut_lo) * (1 - fe) + lp(out, cut_hi) * fe
    y = np.tanh(y * 0.8)
    return y * env_adsr(d, 0.03, 0.25, 0.6, 0.2, total) / len(freqs)


def harp(f, d, rng):
    total = d + 1.2
    t = T(total)
    x = np.sin(2 * np.pi * f * t) * np.exp(-t * 2.6)
    x += np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 4.5) * 0.35
    x += np.sin(2 * np.pi * 3 * f * t) * np.exp(-t * 7) * 0.12
    x *= np.clip(t / 0.003, 0, 1)
    return x * 0.5


def lead(f, d, rng, vib=0.006):
    total = d + 0.3
    t = T(total)
    vibr = 1 + vib * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.15) / 0.3, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * vibr) / SR
    x = np.zeros_like(t)
    for k in range(1, int(min(6000 / f, 30)) + 1):
        x += np.sin(k * ph) / k * (1.0 if k % 2 else 0.6)
    x = lp(x, 2600)
    return x * env_adsr(d, 0.05, 0.3, 0.8, 0.25, total) * 0.4


# ------------------------------------------------------------------
# 곡
# ------------------------------------------------------------------

MINOR = [0, 3, 7]
MAJOR = [0, 4, 7]
# 화음 이름 -> (근음 midi, 모양)
CH = {
    "Dm": (50, MINOR), "Bb": (46, MAJOR), "F": (53, MAJOR), "C": (48, MAJOR), "Gm": (55, MINOR),
    "A": (45, MAJOR), "Eb": (51, MAJOR), "Cm": (48, MINOR), "D": (50, MAJOR), "Am": (45, MINOR),
}


def chord_notes(name, octave_shift=0):
    root, shape = CH[name]
    return [root + i + octave_shift for i in shape]


def arena():
    """경기장: 빠르고 긴박한 D단조 (140 BPM, 32마디)."""
    s = Song(140, 32, seed=140)
    r = s.rng
    prog = (["Dm", "Dm", "Bb", "Bb", "Gm", "Gm", "A", "A"]          # 1~8: 시작, 쌓아 올림
            + ["Dm", "Bb", "F", "C", "Dm", "Bb", "Gm", "A"]         # 9~16: 전부 들어옴
            + ["Bb", "C", "Dm", "Dm", "Bb", "C", "A", "A"]          # 17~24: 북 중심, 긴장
            + ["Dm", "Bb", "F", "C", "Gm", "A", "Dm", "A"])         # 25~32: 주제 선율, 다시 처음으로
    K = kick(r)
    S = snare(r)
    CL = clap(r)
    TK = taiko(r, 62)
    TKH = taiko(r, 95, 0.6)
    pattern = [0, 3, 2, 3, 0, 3, 2, 3, 0, 3, 2, 3, 1, 3, 2, 3]
    accent = [1.0, .5, .7, .5, .85, .5, .7, .5, 1.0, .5, .7, .5, .9, .6, .8, .6]

    # 주제 선율 (마디, 박, 길이(박), midi)
    motif = [(0, 0, 1.5, 74), (0, 1.5, 0.5, 76), (0, 2, 2, 77),
             (1, 0, 1, 76), (1, 1, 1, 74), (1, 2, 2, 70),
             (2, 0, 1.5, 72), (2, 1.5, 0.5, 74), (2, 2, 1, 76), (2, 3, 1, 77),
             (3, 0, 3, 76), (3, 3, 1, 72),
             (4, 0, 1.5, 74), (4, 1.5, 0.5, 76), (4, 2, 2, 77),
             (5, 0, 1, 79), (5, 1, 1, 77), (5, 2, 2, 76),
             (6, 0, 3, 74), (6, 3, 1, 73),
             (7, 0, 4, 76)]

    for bar, name in enumerate(prog):
        sec = bar // 8
        notes = chord_notes(name)
        root = notes[0]
        tones = [notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[0] + 24]
        # 바이올린처럼 쉼 없이 도는 16분음표
        if not (sec == 0 and bar < 2):
            for k in range(16):
                m = tones[pattern[k]]
                g = accent[k] * (0.55 if sec == 0 else 0.75 if sec == 2 else 0.85)
                s.put(pluck(mtof(m), s.beat / 4 * 0.9, r), s.t(bar, k / 4), pan=-0.35 if k % 2 else 0.35, gain=g * 0.7, rev=0.25)
        # 베이스
        if sec == 0 and bar >= 4:
            s.put(bass(mtof(root - 12), s.beat * 4 * 0.95, r, 0.8), s.t(bar), gain=0.6, rev=0.05)
        elif sec in (1, 3):
            for k in range(8):
                m = root - 12 + (12 if k in (3, 7) else 0)
                s.put(bass(mtof(m), s.beat / 2 * 0.8, r, 1.2), s.t(bar, k / 2), gain=0.55, rev=0.03)
        elif sec == 2:
            s.put(bass(mtof(root - 12), s.beat * 2.9, r, 0.9), s.t(bar), gain=0.8, rev=0.05)
            s.put(bass(mtof(root - 12), s.beat * 0.9, r, 1.2), s.t(bar, 3), gain=0.7, rev=0.05)
        # 바탕 화음
        if sec >= 1 or bar >= 4:
            s.put(pad([mtof(m + 12) for m in notes], s.beat * 4, r, 1300 if sec != 2 else 1000), s.t(bar), gain=0.55, rev=0.5)
        # 금관 찌르기
        if sec in (1, 3):
            for b in (0, 1.5):
                s.put(brass([mtof(m + 12) for m in notes] + [mtof(notes[0])], s.beat * 0.55, r), s.t(bar, b), gain=0.55, rev=0.35)
            if bar % 2 == 1:
                s.put(brass([mtof(m + 12) for m in notes], s.beat * 0.4, r), s.t(bar, 3.5), gain=0.3, rev=0.35)
        # 북
        if sec == 0:
            s.put(TK, s.t(bar, 0), gain=0.65, rev=0.3)
            s.put(TK, s.t(bar, 2), gain=0.45, rev=0.3)
            for k in range(16 if bar >= 4 else 8):
                s.put(hat(r), s.t(bar, k / (4 if bar >= 4 else 2)), pan=0.3, gain=(0.35 if k % 2 else 0.5) * (0.6 + bar * 0.05), rev=0.05)
            if bar == 7:
                for k in range(8):
                    s.put(tom(r, 90 - k * 4), s.t(bar, 2 + k / 4), pan=-0.4 + k * 0.1, gain=0.5 + k * 0.05, rev=0.25)
                s.put(riser(r, s.beat * 4), s.t(bar), gain=0.35, rev=0.3)
        elif sec in (1, 3):
            for b in (0, 1.5, 2, 3.5) if bar % 2 == 0 else (0, 1.5, 2.5, 3):
                s.put(K, s.t(bar, b), gain=0.7, rev=0.02)
            for b in (1, 3):
                s.put(S, s.t(bar, b), gain=0.55, rev=0.25)
                s.put(CL, s.t(bar, b), gain=0.4, rev=0.3)
            for k in range(16):
                s.put(hat(r, k in (6, 14)), s.t(bar, k / 4), pan=0.3, gain=0.45 if k % 2 == 0 else 0.28, rev=0.05)
            if bar % 4 == 0:
                s.put(TK, s.t(bar), gain=0.7, rev=0.35)
            if bar % 8 == 0:
                s.put(crash(r), s.t(bar), pan=-0.2, gain=0.55, rev=0.4)
        elif sec == 2:
            # 반박자 느낌: 큰 북이 3-3-2 로 몰아친다
            for b in (0, 0.75, 1.5):
                s.put(TK, s.t(bar, b), gain=0.6, rev=0.35)
            s.put(TKH, s.t(bar, 2.5), gain=0.6, rev=0.3)
            s.put(S, s.t(bar, 2), gain=0.55, rev=0.4)
            s.put(K, s.t(bar, 0), gain=0.8)
            for k in range(8):
                s.put(hat(r), s.t(bar, k / 2), pan=0.35, gain=0.3, rev=0.05)
            if bar == 23:
                for k in range(12):
                    s.put(tom(r, 110 - k * 5), s.t(bar, 1 + k / 4), pan=-0.5 + k * 0.08, gain=0.45 + k * 0.04, rev=0.25)
                s.put(riser(r, s.beat * 4), s.t(bar), gain=0.45, rev=0.3)
        if bar == 31:
            s.put(riser(r, s.beat * 4), s.t(bar), gain=0.4, rev=0.3)
    # 주제 선율: 9~16 마디는 낮게 한 번, 25~32 마디는 크게
    for (b, bt, ln, m) in motif:
        s.put(lead(mtof(m - 12), ln * s.beat * 0.95, r), s.t(8 + b, bt), pan=0.1, gain=0.32, rev=0.35)
        s.put(lead(mtof(m), ln * s.beat * 0.95, r), s.t(24 + b, bt), pan=-0.1, gain=0.55, rev=0.4)
        s.put(brass([mtof(m - 12)], ln * s.beat * 0.9, r, 2600, 900), s.t(24 + b, bt), pan=0.15, gain=0.35, rev=0.4)
    # 17~24: 낮은 현이 긴 음으로 긴장을 끈다
    for i, m in enumerate([62, 64, 65, 65, 62, 64, 61, 61]):
        s.put(lead(mtof(m), s.beat * 3.8, r, 0.004), s.t(16 + i), gain=0.28, rev=0.5)
    return s.render(rt60=1.9, wet=0.4, target_rms_db=-17.0)


def menu():
    """메뉴: 차분하지만 결의가 느껴지는 G단조 (92 BPM, 16마디)."""
    s = Song(92, 16, seed=92)
    r = s.rng
    prog = ["Gm", "Eb", "Bb", "F", "Gm", "Eb", "Cm", "D",
            "Gm", "Eb", "Bb", "F", "Cm", "Gm", "Eb", "D"]
    TK = taiko(r, 55, 1.2)
    melody = [(8, 0, 2, 74), (8, 2, 1, 72), (8, 3, 1, 70),
              (9, 0, 3, 70), (9, 3, 1, 67),
              (10, 0, 2, 70), (10, 2, 1, 72), (10, 3, 1, 74),
              (11, 0, 4, 72),
              (12, 0, 2, 75), (12, 2, 1, 74), (12, 3, 1, 72),
              (13, 0, 3, 74), (13, 3, 1, 70),
              (14, 0, 2, 70), (14, 2, 2, 72),
              (15, 0, 4, 69)]
    arp = [0, 1, 2, 3, 2, 1, 2, 3]
    for bar, name in enumerate(prog):
        notes = chord_notes(name)
        if name in ("Gm", "Cm", "D"):
            notes = [n + 12 if n < 50 else n for n in notes]
        s.put(pad([mtof(m) for m in notes] + [mtof(notes[0] + 12)], s.beat * 4, r, 1100, 0.8, 1.5), s.t(bar), gain=0.6, rev=0.6)
        s.put(bass(mtof(notes[0] - 24), s.beat * 3.9, r, 0.6), s.t(bar), gain=0.35, rev=0.1)
        tones = [notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[0] + 24]
        for k in range(8):
            s.put(harp(mtof(tones[arp[k]]), s.beat / 2, r), s.t(bar, k / 2), pan=-0.4 + 0.1 * k, gain=0.5 if k else 0.6, rev=0.45)
        if bar % 2 == 0:
            s.put(TK, s.t(bar), gain=0.38, rev=0.45)
        if bar >= 4:
            s.put(taiko(r, 80, 0.5), s.t(bar, 2.5), gain=0.25, rev=0.4)
            for k in range(16):
                s.put(shaker(r), s.t(bar, k / 4), pan=0.4, gain=0.3 if k % 2 else 0.4, rev=0.1)
    for (b, bt, ln, m) in melody:
        s.put(brass([mtof(m - 12)], ln * s.beat * 0.95, r, 1800, 700), s.t(b, bt), pan=0.1, gain=0.45, rev=0.5)
        s.put(lead(mtof(m), ln * s.beat * 0.95, r, 0.004), s.t(b, bt), pan=-0.1, gain=0.18, rev=0.55)
    return s.render(rt60=2.4, wet=0.45, target_rms_db=-20.0)


def victory():
    s = Song(120, 2, seed=7, tail=3.5)
    r = s.rng
    seq = [(0, 58), (0.25, 62), (0.5, 65), (0.75, 70)]
    for bt, m in seq:
        s.put(brass([mtof(m)], s.beat * 0.3, r), s.t(0, bt), gain=0.6, rev=0.4)
    s.put(brass([mtof(m) for m in (58, 62, 65, 70, 74)], s.beat * 3.5, r, 3600, 1400), s.t(0, 1), gain=0.8, rev=0.5)
    s.put(pad([mtof(m) for m in (46, 58, 62, 65)], s.beat * 3.5, r, 1800, 0.05, 1.5), s.t(0, 1), gain=0.6, rev=0.5)
    for k in range(10):
        s.put(taiko(r, 70, 0.4), s.t(0, k * 0.1), gain=0.25 + k * 0.05, rev=0.3)
    s.put(taiko(r, 60), s.t(0, 1), gain=1.0, rev=0.4)
    s.put(crash(r, 3.0), s.t(0, 1), gain=0.6, rev=0.5)
    for i, m in enumerate((82, 86, 89, 94)):
        s.put(harp(mtof(m), 0.2, r), s.t(0, 1.25 + i * 0.12), gain=0.25, rev=0.6)
    return s.render_oneshot(2.2, 0.45, -15.0)


def defeat():
    s = Song(80, 2, seed=8, tail=3.5)
    r = s.rng
    for i, m in enumerate((58, 57, 55)):
        s.put(brass([mtof(m - 12)], s.beat * (0.9 if i < 2 else 3.0), r, 1500, 600), s.t(0, i), gain=0.7, rev=0.5)
    s.put(pad([mtof(m) for m in (43, 55, 58, 62)], s.beat * 3.5, r, 900, 0.4, 2.0), s.t(0, 1.5), gain=0.6, rev=0.6)
    s.put(taiko(r, 50, 1.5), s.t(0, 2), gain=1.0, rev=0.5)
    s.put(bass(mtof(31), s.beat * 3, r, 0.5), s.t(0, 2), gain=0.6, rev=0.2)
    return s.render_oneshot(2.6, 0.5, -17.0)


def save_ogg(name, x):
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        write_wav(wav, x, peak_db=-1.0, stereo=True)
        dst = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", dst], check=True)
    print(name, f"{x.shape[1] / SR:.1f}s", f"{os.path.getsize(dst) / 1e6:.2f} MB")


if __name__ == "__main__":
    only = sys.argv[1:] or ["arena", "menu", "victory", "defeat"]
    for name in only:
        save_ogg(name, globals()[name]())
