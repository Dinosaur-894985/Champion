class_name AttackDir
extends RefCounted
## 공격 방향과 막기 방향. 플레이어와 AI 가 같이 쓴다.
##
##   "high" 위   : 머리 위에서 내려베기 → 칼을 위로 들어 막는다
##   "side" 옆   : 옆에서 휘두르기     → 칼을 옆으로 세워 막는다 (기본)
##   "mid"  찌르기 : 가운데로 찌르기     → 칼을 가운데로 내려 막는다
##
## 막기 방향이 공격 방향과 같아야 막힌다. 틀리면 그대로 맞는다.
## 마우스로 고른다: 살짝 위/옆/아래로 움직이면서 클릭(또는 막기) → 그 방향.

const HIGH := "high"
const SIDE := "side"
const MID := "mid"
const ALL := [HIGH, SIDE, MID]

const NAMES := {"high": "위", "side": "옆", "mid": "찌르기"}

## 마우스 움직임을 '방향 입력'으로 볼 최소 크기 (화면 픽셀, 최근 FLICK_TIME 동안 합)
const FLICK_MIN := 14.0
const FLICK_TIME := 0.14


static func blocks(guard: String, attack: String) -> bool:
	return attack == "" or guard == attack


## 마우스 움직임(화면 기준, 아래가 +y) → 방향. 너무 작으면 "".
## 위아래가 옆보다 확실히 클 때만 위/찌르기로 본다 (상대를 따라 옆으로 돌리는 건 늘 있으니까).
static func from_flick(v: Vector2) -> String:
	if v.length() < FLICK_MIN:
		return ""
	if absf(v.y) > absf(v.x) * 1.3:
		return HIGH if v.y < 0.0 else MID
	return SIDE


## 마우스를 최근에 어느 쪽으로 움직였는지 기억한다.
class Flick:
	extends RefCounted
	var _events: Array = []   # [시각(초), Vector2]

	func add(rel: Vector2) -> void:
		var now := Time.get_ticks_msec() / 1000.0
		_events.append([now, rel])
		_trim(now)

	func recent() -> Vector2:
		var now := Time.get_ticks_msec() / 1000.0
		_trim(now)
		var s := Vector2.ZERO
		for e in _events:
			s += e[1]
		return s

	func dir() -> String:
		return AttackDir.from_flick(recent())

	## 옆으로 움직였다면 어느 쪽인지 (-1 왼쪽, +1 오른쪽, 0 모름)
	func side_sign() -> float:
		var v := recent()
		return signf(v.x) if absf(v.x) >= FLICK_MIN * 0.7 else 0.0

	func clear() -> void:
		_events.clear()

	func _trim(now: float) -> void:
		while not _events.is_empty() and now - float(_events[0][0]) > AttackDir.FLICK_TIME:
			_events.pop_front()
