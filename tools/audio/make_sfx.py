#!/usr/bin/env python3
"""챔피언 효과음 생성기.

    python3 tools/audio/make_sfx.py

audio/sfx/*.wav 와 scripts/audio/sound_bank.gd (소리 목록) 를 새로 만든다.
모든 소리는 synth.py 의 수학 함수로 합성한 오리지널이다 (녹음/외부 파일 없음).
같은 시드로 돌리면 항상 같은 소리가 나온다.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from synth import (SR, T, ad, at, bell, bp, drive, drop_sine, expenv, fade, hp,  # noqa: E402
                   lp, mix, modal, n_of, noise, pad_to, reverb, saw, square,
                   svf, sweep_sine, trim_tail, write_wav)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "audio", "sfx")
BANK = os.path.join(ROOT, "scripts", "audio", "sound_bank.gd")

# 파일 크기를 줄이려고 32kHz 로 저장한다 (효과음에는 충분하다).
RATE = 32000

# 소리 이름 -> {"files": [...], "vol": dB, "bus": "SFX"/"UI"}
SOUNDS = {}


def rng_for(name, i):
    return np.random.default_rng(sum(map(ord, name)) * 131 + i * 7919)


def add(name, fn, variants=1, vol=0.0, bus="SFX", peak=-1.0, rt=None):
    files = []
    for i in range(variants):
        rng = rng_for(name, i)
        x = fn(rng, i)
        x = fade(trim_tail(fade(x)), 0.0, 0.04)
        fname = f"{name}_{i + 1}.wav" if variants > 1 else f"{name}.wav"
        write_wav(os.path.join(OUT, fname), x, peak_db=peak, rate=RATE)
        files.append(fname)
    SOUNDS[name] = {"files": files, "vol": vol, "bus": bus}


# ------------------------------------------------------------------
# 재료가 되는 소리들
# ------------------------------------------------------------------

def whoosh(rng, d, f0, f1, f2, q=1.2, peak=0.5, air=0.25):
    """휙: 잡음을 중심 주파수가 움직이는 필터에 통과시킨다."""
    n = n_of(d)
    t = np.linspace(0, 1, n, endpoint=False)
    rise = np.clip(t / peak, 0, 1)
    fall = np.clip((t - peak) / (1 - peak), 0, 1)
    fc = np.where(t < peak, f0 + (f1 - f0) * np.sin(rise * np.pi / 2), f1 + (f2 - f1) * fall)
    x = svf(noise(d, rng), fc, q)
    x += hp(noise(d, rng), 3000) * air * 0.25
    return x * bell(d, peak, 1.6)


def body_thump(rng, d=0.3, f_hi=170.0, f_lo=55.0, k=26.0, decay=14.0):
    b = drop_sine(d, f_hi, f_lo, k) * ad(d, 0.002, decay)
    b += lp(noise(d, rng), 1500) * expenv(d, 45) * 0.6
    return b


def crack(rng, d=0.06, f=2500.0, k=110.0):
    return hp(noise(d, rng), f) * expenv(d, k)


def rubble(rng, d, count, k=4.0, lo=300, hi=3500):
    """작은 돌 부스러기가 우르르 떨어지는 소리."""
    out = np.zeros(n_of(d) + n_of(0.1))
    for _ in range(count):
        t0 = rng.exponential(1.0 / k)
        if t0 >= d:
            continue
        gd = rng.uniform(0.008, 0.04)
        g = bp(noise(gd + 0.02, rng), rng.uniform(lo, lo * 2), rng.uniform(hi * 0.6, hi)) * expenv(gd + 0.02, rng.uniform(60, 160))
        s = n_of(t0)
        out[s:s + len(g)] += g * rng.uniform(0.3, 1.0) * np.exp(-t0 * 1.2)
    return out


def metal(rng, d, base, ratios, decays, amps, transient=0.5, scrape=0.0):
    x = modal(d, [base * r for r in ratios], decays, amps, rng)
    x = mix(x, crack(rng, 0.03, 2000, 160) * transient)
    if scrape > 0:
        sd = min(d, 0.25)
        x = mix(x, svf(noise(sd, rng), np.linspace(5000, 2500, n_of(sd)), 3.0) * bell(sd, 0.15) * scrape)
    return x


def chime(rng, freqs, gap, d=0.9, decay=5.0, wet=0.35):
    """작은 종소리 여러 개를 차례로 (아이템, 필살기 준비)."""
    out = np.zeros(n_of(d + gap * len(freqs)))
    for i, f in enumerate(freqs):
        c = modal(d, [f, f * 2.01, f * 3.03], [decay, decay * 1.8, decay * 3], [1, 0.35, 0.15], rng, 0.001)
        s = n_of(i * gap)
        out[s:s + len(c)] += c
    return reverb(out, 1.2, wet, rng)


# ------------------------------------------------------------------
# 무기별 소리
# ------------------------------------------------------------------

WEAPONS = {
    "sword": {"swing": (0.26, 600, 2600, 900, 1.3), "clash": (1220, [1, 2.39, 3.67, 5.12, 6.8], [7, 10, 14, 20, 28], 0.9)},
    "greatsword": {"swing": (0.42, 240, 1100, 280, 0.9), "clash": (610, [1, 2.21, 3.45, 4.9, 6.3], [4, 6, 9, 13, 18], 1.3)},
    "daggers": {"swing": (0.15, 1500, 5200, 2000, 1.6), "clash": (2150, [1, 2.47, 3.9, 5.6], [14, 18, 26, 35], 0.45)},
    "spear": {"swing": (0.30, 800, 2100, 1100, 4.0), "clash": (2600, [1, 2.3, 3.8], [30, 40, 55], 0.35)},
    # 봉: 굵은 나무가 공기를 가르는 낮은 '훙'. 부딪히면 나무끼리 '딱'
    "staff": {"swing": (0.32, 380, 1500, 520, 1.0), "clash": (480, [1, 2.6, 4.1], [40, 50, 70], 0.25)},
    # 수리검: 짧고 날카로운 '쉭'. 부딪히면 작은 쇠가 '팅'
    "shuriken": {"swing": (0.13, 1900, 6200, 2600, 1.8), "clash": (3300, [1, 2.71, 4.4], [26, 34, 44], 0.3)},
    # 맨몸: 주먹이 바람을 가르는 '훅'. 막으면 팔뚝에 '퍽'
    "fists": {"swing": (0.15, 450, 1700, 650, 0.9), "clash": (0, [], [], 0.2)},
}


def make_swing(w, heavy):
    d, f0, f1, f2, q = WEAPONS[w]["swing"]

    def fn(rng, i):
        k = 1.0 + (i - 1) * 0.07
        dd = d * (1.35 if heavy else 1.0) * rng.uniform(0.93, 1.07)
        lo = 0.72 if heavy else 1.0
        x = whoosh(rng, dd, f0 * lo * k, f1 * lo * k, f2 * lo * k, q, peak=rng.uniform(0.4, 0.55))
        if w == "greatsword":
            # 무거운 쇳덩이가 공기를 미는 낮은 '우웅'
            x += sweep_sine(dd, 70, 120) * bell(dd, 0.5, 2) * 0.5
        if w == "spear":
            # 가는 자루가 내는 휘파람
            x += sweep_sine(dd, 900 * k, 1500 * k) * bell(dd, 0.55, 3) * 0.12
        if w == "sword":
            x += sweep_sine(dd, 1100 * k, 1700 * k) * bell(dd, 0.5, 4) * 0.05
        if w == "staff":
            # 봉 끝이 그리는 큰 원: 두 번 겹쳐 '후웅'
            x = mix(x, at(whoosh(rng, dd * 0.7, f0 * 0.8, f1 * 0.9, f2 * 0.8, q) * 0.45, dd * 0.25))
            x += sweep_sine(dd, 85, 140) * bell(dd, 0.45, 2) * 0.35
        if w == "fists":
            # 옷자락이 펄럭이는 소리 + 짧은 숨
            x = mix(x, bp(noise(dd, rng), 300, 1400) * bell(dd, 0.3, 3) * 0.35)
        if w == "daggers" and i == 2:
            # 두 손이 연달아: 휙휙
            x = mix(x, at(whoosh(rng, dd * 0.9, f0 * 1.1, f1 * 1.1, f2, q), dd * 0.45) * 0.8)
        if heavy:
            x = mix(x * 1.0, body_thump(rng, 0.2, 110, 50, 30, 20) * 0.35)
        return x
    return fn


def make_clash(w):
    base, ratios, decays, d = WEAPONS[w]["clash"]

    def fn(rng, i):
        if w == "staff":
            f = base * rng.uniform(0.92, 1.08)
            wood = modal(0.25, [f, f * 2.6, f * 4.1, f * 6.3], [40, 50, 70, 90], [1, 0.6, 0.35, 0.2], rng)
            return reverb(mix(wood * 1.5, crack(rng, 0.03, 1500, 150) * 0.8, body_thump(rng, 0.15, 220, 90, 35, 25) * 0.4), 0.5, 0.1, rng)
        if w == "fists":
            x = mix(body_thump(rng, 0.2, 210, 80, 32, 22), bp(noise(0.08, rng), 600, 3500) * expenv(0.08, 45) * 0.8)
            return reverb(x, 0.4, 0.08, rng)
        b = base * rng.uniform(0.96, 1.04)
        x = metal(rng, d, b, ratios, decays, [1, 0.7, 0.5, 0.35, 0.2][: len(ratios)], 0.7, 0.35)
        if w == "greatsword":
            x = mix(x, body_thump(rng, 0.35, 140, 50, 22, 12) * 0.7)
        if w == "spear":
            # 나무 자루가 '딱' 하고 받는다
            wood = modal(0.2, [430 * rng.uniform(0.95, 1.05), 1100, 1750], [35, 45, 60], [1, 0.5, 0.3], rng)
            x = mix(wood * 1.4, x * 0.6, crack(rng, 0.03, 1200, 140) * 0.6)
        if w == "daggers":
            x = mix(x, body_thump(rng, 0.1, 300, 150, 40, 40) * 0.2)
        return reverb(x, 0.6, 0.12, rng)
    return fn


def make_hit(w):
    def fn(rng, i):
        if w == "greatsword":
            x = body_thump(rng, 0.45, 130, 38, 20, 9) * 1.2
            x = mix(x, lp(noise(0.25, rng), 3000) * expenv(0.25, 18) * 0.9, crack(rng, 0.06, 1500, 70) * 0.7)
            x = drive(x, 2.5)
        elif w == "daggers":
            x = body_thump(rng, 0.18, 260, 90, 40, 26) * 0.7
            x = mix(x, crack(rng, 0.03, 3500, 180), at(crack(rng, 0.03, 3000, 200) * 0.5, 0.05 if i == 1 else 0.0))
        elif w == "staff":
            # 나무로 후려치는 '퍽!'
            x = body_thump(rng, 0.32, 170, 50, 26, 13) * 1.1
            x = mix(x, modal(0.12, [520 * rng.uniform(0.9, 1.1), 1350], [45, 60], [0.7, 0.35], rng), crack(rng, 0.04, 1800, 120) * 0.7)
        elif w == "shuriken":
            x = body_thump(rng, 0.15, 280, 110, 45, 30) * 0.6
            x = mix(x, crack(rng, 0.025, 4200, 220), bp(noise(0.06, rng), 3000, 8000) * expenv(0.06, 60) * 0.5)
        elif w == "fists":
            # 주먹이 꽂히는 둔탁한 '퍽' + 살갗 치는 '찰싹'
            x = drive(body_thump(rng, 0.3, 160, 45, 24, 12) * 1.3, 2.0)
            x = mix(x, bp(noise(0.05, rng), 1200, 6000) * expenv(0.05, 70) * 0.9, crack(rng, 0.03, 2200, 160) * 0.4)
        elif w == "spear":
            x = body_thump(rng, 0.26, 200, 60, 30, 16)
            x = mix(x, modal(0.1, [380, 980], [50, 60], [0.6, 0.3], rng), bp(noise(0.1, rng), 2500, 7000) * expenv(0.1, 40) * 0.6)
        else:
            x = body_thump(rng, 0.3, 180, 55, 28, 14)
            slice_ = svf(noise(0.14, rng), np.linspace(6500, 2500, n_of(0.14)), 2.0) * ad(0.14, 0.003, 22)
            x = mix(x, slice_ * 0.9, crack(rng, 0.05, 2500, 120) * 0.6)
        return reverb(x, 0.35, 0.08, rng)
    return fn


# ------------------------------------------------------------------
# 목록 만들기
# ------------------------------------------------------------------

def build():
    for w in WEAPONS:
        add(f"swing_{w}", make_swing(w, False), 3, vol=-4.0)
        add(f"swing_{w}_heavy", make_swing(w, True), 2, vol=-2.0)
        add(f"clash_{w}", make_clash(w), 3, vol=-3.0)
        add(f"hit_{w}", make_hit(w), 3, vol=-1.0)

    # 크게 맞음 (넘어질 때): 낮게 '쿵'
    add("hit_big", lambda r, i: reverb(drive(mix(body_thump(r, 0.7, 120, 32, 14, 6) * 1.3,
                                                  crack(r, 0.08, 1800, 60),
                                                  lp(noise(0.4, r), 2200) * expenv(0.4, 12) * 0.6), 2.0), 0.8, 0.18, r),
        2, vol=0.0)
    # 내가 맞았을 때 (화면 안에서 들리는 둔탁한 소리 + 귀가 살짝 울림)
    add("hurt", lambda r, i: mix(lp(body_thump(r, 0.4, 150, 40, 20, 10), 900) * 1.3,
                                 np.sin(2 * np.pi * 3150 * T(0.6)) * ad(0.6, 0.05, 6) * 0.05,
                                 lp(noise(0.15, r), 600) * expenv(0.15, 30) * 0.5), 3, vol=-2.0)

    # 튕겨내기: 맑고 길게 '챙~' + 칼날이 미끄러지는 '쉬잉'
    add("parry", lambda r, i: reverb(mix(metal(r, 1.4, 1650 * (1 + i * 0.03), [1, 2.0, 2.76, 4.07, 5.4], [3, 4.5, 7, 11, 16], [1, 0.6, 0.5, 0.3, 0.2], 0.8),
                                         svf(noise(0.4, r), np.linspace(3000, 7000, n_of(0.4)), 3.0) * bell(0.4, 0.1) * 0.6,
                                         sweep_sine(0.9, 3300, 3320) * ad(0.9, 0.01, 4) * 0.08), 1.2, 0.3, r),
        2, vol=0.0)
    # 완벽한 회피: 시간이 느려지는 '우우웅' (거꾸로 빨려 드는 소리)
    add("perfect_dodge", lambda r, i: reverb(mix(whoosh(r, 0.5, 300, 3500, 3500, 1.0, 0.92) * 0.9,
                                                 drop_sine(0.8, 520, 140, 4) * ad(0.8, 0.25, 4) * 0.45,
                                                 at(sweep_sine(0.5, 2400, 1200) * ad(0.5, 0.01, 7) * 0.12, 0.45)), 1.4, 0.35, r),
        1, vol=-2.0)
    # 막기가 깨짐: 쇠 부딪힘 + 와장창 + 쿵
    add("guard_break", lambda r, i: reverb(mix(metal(r, 0.9, 700, [1, 2.21, 3.45, 4.9], [6, 9, 13, 18], [1, .7, .5, .3], 1.0),
                                               rubble(r, 0.3, 50, 12, 1500, 9000) * 1.2,
                                               drive(body_thump(r, 0.6, 110, 35, 14, 7), 2.0) * 1.2), 0.9, 0.2, r),
        2, vol=0.0)
    # 막는 방향을 바꿀 때 칼이 살짝 스치는 소리
    add("guard_shift", lambda r, i: mix(bp(noise(0.08, r), 2500, 7000) * bell(0.08, 0.3) * 0.5, modal(0.15, [3100, 4700], [30, 40], [.3, .15], r)), 2, vol=-17.0)
    # 속임수: 휙 하다 뚝 끊김
    add("feint", lambda r, i: mix(whoosh(r, 0.12, 700, 2200, 2200, 1.3, 0.85), at(crack(r, 0.03, 1800, 150) * 0.3, 0.1)), 2, vol=-6.0)
    # 잡기: 옷자락 붙잡는 소리 + 툭
    add("grab", lambda r, i: mix(*(at(bp(noise(0.07, r), 700, 3500) * ad(0.07, 0.005, 40) * (1 - j * 0.25), j * 0.045) for j in range(3)),
                                 body_thump(r, 0.2, 140, 70, 30, 22) * 0.7), 2, vol=-2.0)
    add("grab_whoosh", lambda r, i: mix(whoosh(r, 0.2, 400, 1500, 500, 1.0, 0.5), at(bp(noise(0.06, r), 900, 3000) * expenv(0.06, 50), 0.12) * 0.6), 2, vol=-5.0)
    add("grab_clash", lambda r, i: mix(body_thump(r, 0.25, 150, 60, 25, 16), at(body_thump(r, 0.25, 130, 55, 25, 16), 0.04),
                                       bp(noise(0.15, r), 800, 3000) * expenv(0.15, 25) * 0.6), 1, vol=-2.0)
    # 던지기: 무겁게 '후웅'
    add("throw", lambda r, i: mix(whoosh(r, 0.55, 180, 900, 250, 0.9, 0.35) * 1.1, sweep_sine(0.5, 60, 110) * bell(0.5, 0.35) * 0.5), 2, vol=-1.0)
    # 벽꽝: 크게 쾅 + 돌가루 우르르
    add("wall_slam", lambda r, i: reverb(mix(drive(body_thump(r, 0.9, 100, 28, 12, 5) * 1.5, 2.5),
                                             lp(noise(0.5, r), 2500) * expenv(0.5, 9) * 0.9,
                                             at(rubble(r, 0.9, 70, 4, 250, 3000) * 0.9, 0.03)), 1.2, 0.22, r),
        2, vol=1.0)
    # 차지 끝 (칼이 번쩍)
    add("charge_ready", lambda r, i: mix(modal(0.6, [3200, 4810, 7020], [8, 12, 16], [1, .6, .3], r),
                                         sweep_sine(0.18, 1500, 3200) * ad(0.18, 0.005, 14) * 0.3), 1, vol=-6.0)
    add("charge_hum", lambda r, i: (saw(110, 1.0, 12) * 0.25 + np.sin(2 * np.pi * 220 * T(1.0)) * 0.4) * (0.6 + 0.4 * np.sin(2 * np.pi * 6 * T(1.0))) * bell(1.0, 0.95, 1), 1, vol=-14.0)

    # 상대가 공격을 준비하는 신호 (색과 짝: 주황=약, 빨강=강, 보라=잡기, 금빛=필살기)
    add("warn_light", lambda r, i: mix(modal(0.35, [2400, 3610, 5300], [16, 20, 28], [1, .5, .3], r) * 0.8,
                                       sweep_sine(0.08, 1800, 2600) * ad(0.08, 0.003, 30) * 0.3), 1, vol=-6.0)
    add("warn_heavy", lambda r, i: mix(lp(np.sign(sweep_sine(0.5, 150, 330)) * 0.4 + sweep_sine(0.5, 300, 660) * 0.5, 1600) * bell(0.5, 0.8, 1.2),
                                       hp(noise(0.5, r), 2000) * bell(0.5, 0.9, 2) * 0.12), 1, vol=-5.0)
    add("warn_grab", lambda r, i: lp(sweep_sine(0.32, 180, 360) * (0.6 + 0.4 * np.sin(2 * np.pi * 18 * T(0.32))), 1200) * bell(0.32, 0.6, 1.2)
        + bp(noise(0.32, r), 400, 1400) * bell(0.32, 0.6, 2) * 0.3, 1, vol=-5.0)
    add("warn_special", lambda r, i: reverb(mix(modal(1.2, [330, 495 * 1.01, 742, 1113], [2.5, 3, 4, 6], [1, .7, .45, .3], r) * 1.0,
                                                at(modal(1.0, [440, 660, 990, 1485], [2.5, 3, 4, 6], [1, .7, .45, .3], r) * 0.9, 0.22),
                                                svf(noise(0.9, r), np.linspace(400, 5000, n_of(0.9)) , 2.5) * bell(0.9, 0.95, 1.5) * 0.5), 1.6, 0.35, r),
        1, vol=-1.0)

    # 필살기
    add("special_ready", lambda r, i: chime(r, [1046.5, 1318.5, 1568.0, 2093.0], 0.06, 1.0, 4.0, 0.4), 1, vol=-5.0, bus="UI")
    add("special_windup", lambda r, i: reverb(mix(svf(noise(0.7, r), np.geomspace(300, 6000, n_of(0.7)), 2.0) * bell(0.7, 0.92, 1.3),
                                                  sweep_sine(0.7, 110, 440, 2) * bell(0.7, 0.9, 1.5) * 0.4,
                                                  sweep_sine(0.7, 220, 880, 2) * bell(0.7, 0.9, 1.5) * 0.2), 1.0, 0.3, r), 1, vol=-2.0)

    def whirl(r, i):
        d = 0.75
        fc = 700 + 2200 * np.abs(np.sin(np.linspace(0, 2 * np.pi, n_of(d))))
        x = svf(noise(d, r), fc, 1.4) * bell(d, 0.5, 0.7)
        x += sweep_sine(d, 900, 1500) * np.abs(np.sin(np.linspace(0, 2 * np.pi, n_of(d)))) * 0.08
        return reverb(x, 0.8, 0.2, r)
    add("sp_whirl", whirl, 1, vol=0.0)
    add("sp_quake", lambda r, i: reverb(mix(drive(body_thump(r, 1.6, 90, 24, 6, 2.6) * 1.6, 3.0),
                                            lp(noise(1.2, r), 1800) * expenv(1.2, 4) * 0.8,
                                            at(rubble(r, 1.6, 140, 2.5, 200, 2800) * 1.2, 0.05),
                                            metal(r, 1.0, 520, [1, 2.2, 3.4], [5, 8, 12], [1, .5, .3], 0.5) * 0.4), 1.8, 0.3, r), 1, vol=2.0)

    def shadow(r, i):
        zap = np.sin(2 * np.pi * np.cumsum(1200 + 900 * np.sin(2 * np.pi * 37 * T(0.35))) / SR) * ad(0.35, 0.005, 9)
        rev = whoosh(r, 0.35, 300, 4000, 4000, 1.2, 0.95)
        return reverb(mix(rev * 0.9, at(lp(zap, 3000) * 0.25, 0.3), at(crack(r, 0.05, 2500, 80), 0.33)), 0.9, 0.3, r)
    add("sp_shadow", shadow, 1, vol=-1.0)
    add("sp_rush", lambda r, i: reverb(mix(whoosh(r, 0.9, 250, 2400, 600, 0.8, 0.25) * 1.2,
                                           lp(noise(0.9, r), 400) * bell(0.9, 0.3, 1) * 0.7,
                                           sweep_sine(0.9, 90, 60) * bell(0.9, 0.2, 1) * 0.4), 0.9, 0.25, r), 1, vol=0.0)

    # 새 무기 필살기
    def flurry(r, i):
        parts = [at(whoosh(r, 0.18, 400, 1700, 600, 1.0, 0.45) * (0.7 + 0.06 * j), j * 0.12) for j in range(6)]
        parts.append(at(body_thump(r, 0.4, 150, 45, 22, 10) * 0.9, 0.66))
        return reverb(mix(*parts), 0.8, 0.2, r)
    add("sp_flurry", flurry, 1, vol=0.0)

    def storm(r, i):
        parts = []
        for j in range(8):
            d = 0.22
            spin = 0.6 + 0.4 * np.abs(np.sin(2 * np.pi * (38 + j * 3) * T(d)))
            parts.append(at(bp(noise(d, r), 2500, 9000) * spin * ad(d, 0.01, 12) * 0.6, j * 0.06))
        parts.append(svf(noise(0.8, r), np.geomspace(800, 6000, n_of(0.8)), 2.0) * bell(0.8, 0.3, 1.2) * 0.4)
        return reverb(mix(*parts), 0.9, 0.25, r)
    add("sp_storm", storm, 1, vol=-1.0)

    def takedown(r, i):
        grab = mix(*(at(bp(noise(0.07, r), 700, 3500) * ad(0.07, 0.005, 40) * (1 - j * 0.25), j * 0.04) for j in range(3)))
        swing = at(whoosh(r, 0.35, 200, 1200, 300, 0.9, 0.3), 0.08)
        slam = at(drive(body_thump(r, 0.8, 110, 30, 14, 6) * 1.5, 2.5), 0.36)
        dust = at(lp(noise(0.5, r), 2200) * expenv(0.5, 10) * 0.7, 0.37)
        return reverb(mix(grab, swing, slam, dust), 1.0, 0.2, r)
    add("sp_takedown", takedown, 1, vol=1.0)

    # 수리검: 던질 때 '휘리릭' (빙글빙글 도는 소리), 꽂힐 때 '탁', 맞을 때 '퍽'
    def sh_throw(r, i):
        d = 0.32
        spin = 0.5 + 0.5 * np.abs(np.sin(2 * np.pi * (30 + 4 * i) * T(d)))
        x = bp(noise(d, r), 2200, 8000) * spin * ad(d, 0.006, 9) * 0.9
        return mix(x, whoosh(r, 0.12, 1500, 5000, 2500, 1.6, 0.3) * 0.6)
    add("shuriken_throw", sh_throw, 3, vol=-5.0)
    add("shuriken_stick", lambda r, i: mix(modal(0.15, [700 * r.uniform(0.9, 1.1), 1900], [40, 60], [0.8, 0.3], r),
                                            modal(0.4, [4100, 6300], [12, 18], [0.25, 0.12], r), crack(r, 0.02, 3000, 200) * 0.6), 2, vol=-6.0)
    add("shuriken_hit", lambda r, i: reverb(mix(body_thump(r, 0.2, 260, 90, 40, 26) * 0.8, crack(r, 0.03, 3800, 200) * 0.8,
                                                bp(noise(0.06, r), 2500, 7000) * expenv(0.06, 55) * 0.5), 0.3, 0.06, r), 2, vol=-3.0)

    # 이동
    def step(r, i):
        x = bp(noise(0.09, r), 150, 2400) * ad(0.09, 0.001, 55)
        x += np.sin(2 * np.pi * r.uniform(80, 110) * T(0.09)) * ad(0.09, 0.002, 45) * 0.6
        x = mix(x, crack(r, 0.03, 3500, 160) * r.uniform(0.15, 0.35))
        return lp(x, r.uniform(3500, 5000))
    add("step", step, 6, vol=-15.0)
    add("land", lambda r, i: mix(body_thump(r, 0.25, 140, 60, 30, 18), crack(r, 0.05, 2500, 90) * 0.4, bp(noise(0.12, r), 400, 2500) * expenv(0.12, 30) * 0.5), 2, vol=-7.0)
    add("land_hard", lambda r, i: reverb(mix(drive(body_thump(r, 0.5, 120, 40, 18, 9) * 1.3, 1.6), crack(r, 0.06, 2000, 70) * 0.5,
                                             at(rubble(r, 0.3, 25, 10, 400, 3000) * 0.5, 0.02)), 0.6, 0.12, r), 2, vol=-2.0)
    add("jump", lambda r, i: mix(whoosh(r, 0.16, 400, 1400, 600, 1.0, 0.35) * 0.6, body_thump(r, 0.1, 150, 90, 40, 40) * 0.35), 2, vol=-11.0)
    add("double_jump", lambda r, i: mix(whoosh(r, 0.28, 300, 2400, 1800, 0.9, 0.3), sweep_sine(0.28, 900, 1800) * ad(0.28, 0.01, 12) * 0.08), 1, vol=-8.0)
    add("dash", lambda r, i: mix(whoosh(r, 0.24, 350 * (1 + i * .08), 2000, 600, 1.0, 0.3) * 1.0, body_thump(r, 0.12, 120, 60, 35, 30) * 0.3), 3, vol=-6.0)
    add("climb", lambda r, i: mix(bp(noise(0.3, r), 900, 4500) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 24 * T(0.3)))) * bell(0.3, 0.2, 1) * 0.7,
                                 body_thump(r, 0.1, 160, 80, 40, 40) * 0.3), 2, vol=-11.0)
    add("wall_kick", lambda r, i: mix(body_thump(r, 0.15, 170, 80, 35, 30) * 0.8, crack(r, 0.04, 2500, 120) * 0.4,
                                      at(whoosh(r, 0.2, 400, 1600, 600, 1.0, 0.3) * 0.6, 0.02)), 2, vol=-8.0)
    add("hang", lambda r, i: mix(crack(r, 0.05, 1500, 120) * 0.7, body_thump(r, 0.12, 200, 90, 40, 35) * 0.5), 1, vol=-9.0)
    add("mantle", lambda r, i: mix(bp(noise(0.25, r), 600, 3000) * bell(0.25, 0.3, 1) * 0.6, body_thump(r, 0.12, 150, 80, 40, 35) * 0.4), 1, vol=-10.0)
    add("zip_attach", lambda r, i: mix(metal(r, 0.5, 880, [1, 2.6, 4.1, 5.9], [10, 14, 20, 28], [1, .6, .4, .25], 0.6),
                                       at(metal(r, 0.3, 1320, [1, 2.4, 3.8], [16, 22, 30], [.5, .3, .2], 0.3), 0.06)), 1, vol=-5.0)
    add("zip_release", lambda r, i: mix(metal(r, 0.3, 1050, [1, 2.5, 4.0], [16, 22, 30], [.7, .4, .2], 0.4), whoosh(r, 0.25, 500, 1800, 700, 1.0, 0.3) * 0.6), 1, vol=-7.0)

    def zip_loop(r, i):
        # 도르래가 줄을 타는 '지이잉' (1초에 정확히 맞게 돌아서 이어 붙여도 티가 안 난다)
        d = 1.0
        t = T(d)
        x = np.zeros_like(t)
        for f, a in ((180, 0.5), (361, 0.3), (543, 0.2), (1210, 0.1)):
            x += np.sin(2 * np.pi * f * t) * a
        x *= 0.7 + 0.3 * np.sin(2 * np.pi * 22 * t)
        nz = bp(noise(d + 0.2, r), 1500, 6000)
        cyc = nz[: n_of(d)].copy()
        xf = n_of(0.1)
        cyc[:xf] = cyc[:xf] * np.linspace(0, 1, xf) + nz[n_of(d):n_of(d) + xf] * np.linspace(1, 0, xf)
        return x * 0.6 + cyc * 0.35
    SOUNDS_LOOP.append("zip_loop")
    add_loop("zip_loop", zip_loop, vol=-12.0)

    add("plunge_dive", lambda r, i: mix(svf(noise(0.55, r), np.linspace(500, 3500, n_of(0.55)), 1.0) * bell(0.55, 0.9, 1.2),
                                        sweep_sine(0.55, 1500, 700) * bell(0.55, 0.7, 2) * 0.12), 1, vol=-4.0)
    add("plunge_impact", lambda r, i: reverb(mix(drive(body_thump(r, 1.0, 110, 28, 10, 4) * 1.5, 2.5),
                                                 metal(r, 0.6, 620, [1, 2.3, 3.6], [8, 12, 16], [1, .5, .3], 0.6) * 0.5,
                                                 at(rubble(r, 0.8, 80, 4, 250, 3000), 0.03)), 1.2, 0.25, r), 2, vol=1.0)
    add("grapple", lambda r, i: mix(svf(noise(0.22, r), np.linspace(6000, 900, n_of(0.22)), 2.0) * ad(0.22, 0.005, 9),
                                    at(metal(r, 0.2, 1500, [1, 2.7], [25, 35], [.4, .2], 0.2), 0.18)), 1, vol=-5.0)
    add("blink", lambda r, i: reverb(mix(whoosh(r, 0.25, 400, 5000, 5000, 1.2, 0.95),
                                         at(np.sin(2 * np.pi * np.cumsum(np.geomspace(3000, 400, n_of(0.18))) / SR) * ad(0.18, 0.002, 14) * 0.3, 0.22)), 0.7, 0.3, r), 1, vol=-4.0)
    add("haste", lambda r, i: reverb(mix(whoosh(r, 0.6, 200, 3000, 2500, 0.8, 0.7), chime(r, [1568, 2093], 0.07, 0.6, 6, 0.0) * 0.25), 0.9, 0.25, r), 1, vol=-5.0)
    add("iron", lambda r, i: reverb(mix(modal(1.3, [196, 294.5, 392.4, 589], [2, 2.6, 3.5, 5], [1, .5, .5, .3], r), metal(r, 0.4, 900, [1, 2.4], [12, 18], [.4, .2], 0.6)), 1.4, 0.3, r), 1, vol=-4.0)
    add("fall_void", lambda r, i: reverb(svf(noise(1.4, r), np.linspace(2500, 250, n_of(1.4)), 0.9) * bell(1.4, 0.2, 1), 1.5, 0.4, r), 1, vol=-4.0)

    # 경기장
    def floor_warn(r, i):
        d = 1.9
        rum = lp(noise(d, r), 130, 4) * 3.0 * bell(d, 0.5, 0.7)
        cr = rubble(r, d, 30, 6, 600, 5000) * 0.6
        horn = np.zeros(n_of(d))
        for k in range(3):
            hd = 0.32
            h = lp(saw(220, hd, 30) + saw(233, hd, 30), 1400) * bell(hd, 0.15, 0.6) * 0.35
            s = n_of(k * 0.45)
            horn[s:s + len(h)] += h
        return reverb(mix(rum, cr, horn), 1.0, 0.25, r)
    add("floor_warn", floor_warn, 1, vol=-3.0)
    add("floor_collapse", lambda r, i: reverb(mix(drive(lp(noise(3.0, r), 200, 4) * 4.0, 1.5) * bell(3.0, 0.1, 0.8),
                                                  rubble(r, 2.6, 400, 1.2, 200, 3500) * 1.3,
                                                  body_thump(r, 1.2, 80, 25, 6, 3) * 1.0), 1.8, 0.3, r), 1, vol=0.0)
    add("pillar_crack", lambda r, i: mix(crack(r, 0.08, 1200, 50) * 1.2, rubble(r, 0.25, 20, 12, 500, 4000) * 0.8, body_thump(r, 0.25, 120, 50, 25, 14) * 0.6), 2, vol=-3.0)
    add("pillar_break", lambda r, i: reverb(mix(drive(body_thump(r, 0.9, 90, 30, 10, 4) * 1.4, 2.0), rubble(r, 1.4, 180, 2.0, 200, 3500) * 1.3,
                                                crack(r, 0.1, 900, 40)), 1.4, 0.25, r), 1, vol=0.0)
    add("pickup_spawn", lambda r, i: mix(chime(r, [784, 1175, 1568], 0.09, 1.2, 3.0, 0.45), svf(noise(0.6, r), np.linspace(1000, 6000, n_of(0.6)), 3.0) * bell(0.6, 0.8) * 0.05), 1, vol=-8.0)
    add("pickup_get", lambda r, i: chime(r, [1046.5, 1568, 2093, 2637], 0.045, 0.8, 5.0, 0.3), 1, vol=-4.0)
    add("dummy_hit", lambda r, i: mix(modal(0.22, [310 * r.uniform(.92, 1.08), 820, 1460], [30, 40, 55], [1, .45, .3], r) * 1.2,
                                      bp(noise(0.18, r), 1500, 6000) * expenv(0.18, 22) * 0.5, body_thump(r, 0.2, 150, 70, 30, 20) * 0.5), 3, vol=-2.0)
    add("dummy_fall", lambda r, i: mix(body_thump(r, 0.5, 110, 45, 14, 8) * 1.2, modal(0.3, [240, 610], [20, 30], [.6, .3], r), at(body_thump(r, 0.3, 120, 50, 18, 12) * 0.6, 0.18)), 1, vol=-3.0)

    # 화면(메뉴) 소리
    add("ui_hover", lambda r, i: mix(np.sin(2 * np.pi * 1800 * T(0.05)) * ad(0.05, 0.001, 70) * 0.5, crack(r, 0.02, 4000, 300) * 0.2), 1, vol=-16.0, bus="UI")
    add("ui_click", lambda r, i: mix(np.sin(2 * np.pi * 1200 * T(0.12)) * ad(0.12, 0.001, 35), np.sin(2 * np.pi * 1800 * T(0.12)) * ad(0.12, 0.001, 45) * 0.5,
                                     crack(r, 0.02, 3000, 250) * 0.3), 1, vol=-9.0, bus="UI")
    add("ui_confirm", lambda r, i: reverb(mix(np.sin(2 * np.pi * 880 * T(0.25)) * ad(0.25, 0.002, 14), at(np.sin(2 * np.pi * 1318.5 * T(0.3)) * ad(0.3, 0.002, 12), 0.07),
                                              metal(r, 0.4, 2640, [1, 2.4], [12, 18], [.15, .08], 0.1)), 0.6, 0.2, r), 1, vol=-7.0, bus="UI")
    add("ui_back", lambda r, i: mix(np.sin(2 * np.pi * 900 * T(0.12)) * ad(0.12, 0.001, 35), at(np.sin(2 * np.pi * 600 * T(0.14)) * ad(0.14, 0.001, 30), 0.05)), 1, vol=-10.0, bus="UI")
    add("ui_tick", lambda r, i: np.sin(2 * np.pi * 2200 * T(0.03)) * ad(0.03, 0.0005, 150), 1, vol=-14.0, bus="UI")
    add("countdown", lambda r, i: reverb(mix(np.sin(2 * np.pi * 660 * T(0.35)) * ad(0.35, 0.003, 10), np.sin(2 * np.pi * 1320 * T(0.2)) * ad(0.2, 0.003, 20) * 0.3,
                                             lp(drop_sine(0.25, 150, 60, 25), 400) * expenv(0.25, 14) * 0.8), 0.8, 0.2, r), 1, vol=-5.0, bus="UI")
    add("fight", lambda r, i: reverb(mix(drive(body_thump(r, 1.0, 120, 40, 10, 4) * 1.4, 1.8),
                                         metal(r, 1.6, 410, [1, 1.5, 2.0, 2.98, 4.1], [2, 2.5, 3, 4, 6], [1, .6, .6, .4, .3], 1.0) * 0.6,
                                         svf(noise(0.5, r), np.linspace(2500, 7000, n_of(0.5)), 2.5) * bell(0.5, 0.05) * 0.4), 1.8, 0.35, r), 1, vol=-1.0, bus="UI")
    add("ko", lambda r, i: reverb(mix(drive(body_thump(r, 1.4, 90, 26, 8, 3) * 1.5, 2.0), lp(noise(0.6, r), 1500) * expenv(0.6, 8) * 0.6,
                                      modal(2.0, [147, 220, 294, 441], [1.5, 2, 2.5, 3.5], [1, .6, .5, .3], r) * 0.5), 2.2, 0.4, r), 1, vol=0.0, bus="UI")


SOUNDS_LOOP = []


def add_loop(name, fn, vol=0.0, bus="SFX"):
    """반복용 소리: 꼬리를 자르거나 페이드하지 않는다 (처음과 끝이 이어지게 만든다)."""
    rng = rng_for(name, 0)
    x = fn(rng, 0)
    write_wav(os.path.join(OUT, name + ".wav"), x, peak_db=-1.0, rate=RATE)
    SOUNDS[name] = {"files": [name + ".wav"], "vol": vol, "bus": bus, "loop": True}


def write_bank():
    lines = [
        "class_name SoundBank",
        "extends RefCounted",
        "## 자동으로 만든 파일: tools/audio/make_sfx.py 와 make_music.py 가 쓴다. 직접 고치지 말 것.",
        "## 이름 -> 소리 파일들(여러 개면 번갈아 무작위로), 기본 음량(dB), 버스.",
        "",
        "const SFX := {",
    ]
    for name, s in SOUNDS.items():
        files = ", ".join(f'preload("res://audio/sfx/{f}")' for f in s["files"])
        loop = ', "loop": true' if s.get("loop") else ""
        lines.append(f'\t"{name}": {{"streams": [{files}], "vol": {s["vol"]:.1f}, "bus": "{s["bus"]}"{loop}}},')
    lines.append("}")
    lines.append("")
    music_dir = os.path.join(ROOT, "audio", "music")
    lines.append("const MUSIC := {")
    if os.path.isdir(music_dir):
        for f in sorted(os.listdir(music_dir)):
            if f.endswith(".ogg"):
                lines.append(f'\t"{f[:-4]}": preload("res://audio/music/{f}"),')
    lines.append("}")
    os.makedirs(os.path.dirname(BANK), exist_ok=True)
    with open(BANK, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    for f in os.listdir(OUT) if os.path.isdir(OUT) else []:
        if f.endswith(".wav"):
            os.remove(os.path.join(OUT, f))
    build()
    write_bank()
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT) if f.endswith(".wav"))
    print(f"{sum(len(s['files']) for s in SOUNDS.values())} files, {len(SOUNDS)} sounds, {total / 1e6:.2f} MB")
