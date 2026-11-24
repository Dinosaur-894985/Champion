class_name Sfx
extends RefCounted
## 효과음을 파일 없이 코드로 만든다 (임시 소리. 나중에 진짜 효과음으로 바꿀 수 있다).

const RATE := 22050


static func _make(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


## 칼을 휘두를 때 나는 '휙' 소리.
static func whoosh(length: float = 0.22, pitch: float = 1.0) -> AudioStreamWAV:
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		var env := sin(t * PI) * sin(t * PI)
		var cutoff := lerpf(0.05, 0.35, sin(t * PI)) * pitch
		lp += (rng.randf_range(-1, 1) - lp) * cutoff
		out[i] = lp * env * 1.6
	return _make(out)


## 허수아비를 맞혔을 때 나는 '퍽' 소리.
static func thud(length: float = 0.18, heavy: bool = false) -> AudioStreamWAV:
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var lp := 0.0
	var phase := 0.0
	var base := 95.0 if heavy else 140.0
	for i in n:
		var t := float(i) / n
		var env := exp(-t * 9.0)
		var f := base * (1.0 + (1.0 - t) * 1.5)
		phase += f / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.25
		out[i] = (sin(phase * TAU) * 0.8 + lp * 0.7 * exp(-t * 20.0)) * env
	return _make(out)
