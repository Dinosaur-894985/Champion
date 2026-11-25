"""챔피언 소리 합성 도구 모음 (효과음/음악 생성기가 함께 쓴다).

녹음이나 남의 소리 파일은 하나도 쓰지 않는다. 모든 소리는 아래 수학 함수
(사인파, 잡음, 필터, 울림)로 만든다. 그래서 결과물은 이 프로젝트의 오리지널이다.
필요한 것: python3, numpy, scipy  (음악 OGG 변환에는 ffmpeg)
"""
import os
import wave

import numpy as np
import scipy.signal as sg

SR = 44100


def T(d):
    return np.arange(int(d * SR)) / SR


def n_of(d):
    return int(d * SR)


def noise(d, rng):
    return rng.uniform(-1.0, 1.0, n_of(d))


def _sos(kind, f, order):
    if isinstance(f, (list, tuple)):
        f = [min(max(x, 20.0), SR * 0.45) for x in f]
    else:
        f = min(max(f, 20.0), SR * 0.45)
    return sg.butter(order, f, kind, fs=SR, output="sos")


def lp(x, f, order=2):
    return sg.sosfilt(_sos("low", f, order), x)


def hp(x, f, order=2):
    return sg.sosfilt(_sos("high", f, order), x)


def bp(x, lo, hi, order=2):
    return sg.sosfilt(_sos("band", [lo, hi], order), x)


def svf(x, fc, q=0.7, mode="band"):
    """시간에 따라 주파수가 바뀌는 필터 (휙 소리처럼 음색이 움직이는 소리에 쓴다).
    fc 는 샘플마다의 중심 주파수 배열."""
    fc = np.minimum(np.asarray(fc, dtype=float), 7000.0)
    fs = (2.0 * np.sin(np.pi * fc / SR)).tolist()
    xs = x.tolist()
    damp = 1.0 / q
    low = band = 0.0
    out = [0.0] * len(xs)
    if mode == "band":
        for i, v in enumerate(xs):
            f = fs[i]
            low += f * band
            high = v - low - damp * band
            band += f * high
            out[i] = band
    elif mode == "low":
        for i, v in enumerate(xs):
            f = fs[i]
            low += f * band
            high = v - low - damp * band
            band += f * high
            out[i] = low
    else:
        for i, v in enumerate(xs):
            f = fs[i]
            low += f * band
            high = v - low - damp * band
            band += f * high
            out[i] = high
    return np.array(out)


def expenv(d, k):
    return np.exp(-T(d) * k)


def ad(d, attack, k):
    """빠르게 올라갔다가 지수로 줄어드는 모양."""
    t = T(d)
    a = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    return a * np.exp(-np.maximum(t - attack, 0.0) * k)


def bell(d, peak=0.5, power=2.0):
    """가운데(peak 비율 지점)가 가장 큰 둥근 모양."""
    t = np.linspace(0.0, 1.0, n_of(d), endpoint=False)
    up = np.clip(t / peak, 0, 1)
    down = np.clip((1 - t) / (1 - peak), 0, 1)
    return (np.sin(np.minimum(up, down) * np.pi / 2)) ** power


def sweep_sine(d, f0, f1, curve=1.0, phase=0.0):
    t = np.linspace(0.0, 1.0, n_of(d), endpoint=False)
    f = f0 + (f1 - f0) * t ** curve
    return np.sin(2 * np.pi * np.cumsum(f) / SR + phase)


def drop_sine(d, f_hi, f_lo, k):
    """높은 음에서 낮은 음으로 빠르게 떨어지는 사인 (북, 쿵 소리의 몸통)."""
    t = T(d)
    f = f_lo + (f_hi - f_lo) * np.exp(-t * k)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def modal(d, freqs, decays, amps, rng, beat=0.0025):
    """금속이 울리는 소리: 맞지 않는 배음 여러 개가 각자 다른 속도로 사라진다."""
    t = T(d)
    out = np.zeros_like(t)
    for f, k, a in zip(freqs, decays, amps):
        for det in (1.0, 1.0 + beat):
            ph = rng.uniform(0, 2 * np.pi)
            out += a * 0.5 * np.sin(2 * np.pi * f * det * t + ph) * np.exp(-t * k)
    return out


def saw(f, d, k_max=None, phase=0.0):
    """배음을 직접 더해서 만든 톱니파 (거칠지 않게 높은 배음은 뺀다)."""
    t = T(d)
    if np.isscalar(f):
        K = int(min(9000.0 / max(f, 20.0), 80)) if k_max is None else k_max
        out = np.zeros_like(t)
        for k in range(1, K + 1):
            out += np.sin(2 * np.pi * k * f * t + phase * k) / k
        return out * 0.6
    raise ValueError


def square(f, d, k_max=40):
    t = T(d)
    out = np.zeros_like(t)
    K = int(min(9000.0 / f, k_max))
    for k in range(1, K + 1, 2):
        out += np.sin(2 * np.pi * k * f * t) / k
    return out * 0.8


def drive(x, amount):
    return np.tanh(x * amount) / np.tanh(amount)


def pad_to(x, n):
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def at(x, delay):
    """소리를 delay 초 뒤에 시작하게 한다."""
    return np.concatenate([np.zeros(n_of(delay)), x])


def reverb_ir(d, rt60, rng, bright=6000.0, pre=0.008):
    t = T(d)
    ir = rng.normal(0, 1, len(t)) * np.exp(-t * 6.9 / rt60)
    ir = lp(ir, bright)
    ir[: n_of(pre)] = 0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    return ir


def reverb(x, rt60, wet, rng, bright=6000.0):
    ir = reverb_ir(min(rt60 * 1.2, 4.0), rt60, rng, bright)
    w = sg.fftconvolve(x, ir)[: len(x) + len(ir)]
    dry = pad_to(x, len(w))
    return dry + w * wet


def fade(x, fin=0.002, fout=0.012):
    x = x.copy()
    a, b = n_of(fin), n_of(fout)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0 and b < len(x):
        x[-b:] *= np.linspace(1, 0, b)
    return x


def trim_tail(x, thresh_db=-48.0):
    """끝부분의 거의 안 들리는 꼬리를 잘라 파일을 줄인다."""
    a = np.abs(x)
    th = np.max(a) * 10 ** (thresh_db / 20)
    idx = np.where(a > th)[0]
    if len(idx) == 0:
        return x
    end = min(len(x), idx[-1] + n_of(0.02))
    return x[:end]


def write_wav(path, x, peak_db=-1.0, stereo=False, rate=SR):
    """최고 음량을 peak_db 에 맞춰 16비트 WAV 로 저장. rate 를 낮추면 파일이 작아진다."""
    x = np.asarray(x, dtype=float)
    if rate != SR:
        from math import gcd
        g = gcd(rate, SR)
        x = sg.resample_poly(x, rate // g, SR // g, axis=-1)
    m = np.max(np.abs(x)) + 1e-12
    x = x / m * 10 ** (peak_db / 20)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = np.clip(x * 32767, -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2 if stereo else 1)
        w.setsampwidth(2)
        w.setframerate(rate)
        if stereo:
            w.writeframes(data.T.reshape(-1).tobytes())
        else:
            w.writeframes(data.tobytes())


def pan(x, p):
    """p: -1 왼쪽 ~ +1 오른쪽. 두 줄(스테레오)로 돌려준다."""
    a = (p + 1) * np.pi / 4
    return np.vstack([x * np.cos(a), x * np.sin(a)])
