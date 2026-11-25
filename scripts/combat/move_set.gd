class_name MoveSet
extends RefCounted
## 모든 공격 동작을 적어 둔 표. 플레이어와 AI 가 같은 표를 쓴다.
## 새 기술이나 새 무기를 넣을 때는 여기에 한 줄(항목 하나)을 더하면 된다.
##
## 항목 설명
##   windup / active / recover : 준비, 칼날이 닿는 시간, 회복 (초). 플레이어 기준.
##   ai_windup / ai_recover    : AI 가 쓸 때 (보고 막을 수 있게 준비를 더 길게 보여준다)
##   damage, cost, reach       : 피해, 기력 소모, 닿는 거리
##   lunge                     : 휘두르며 앞으로 내딛는 힘
##   react                     : 맞은 쪽이 받는 경직 ("flinch" 움찔, "stagger" 크게 휘청)
##   guard                     : "normal" 막힘 / "break" 막기를 깨뜨림 / "unblockable" 못 막음
##   next                      : 이어지는 연속 베기 동작
##   fp                        : 1인칭 칼 자세 [회전(도), 위치] — windup 과 strike
##   body                      : 3인칭 몸 자세 [어깨, 손목, 허리 비틀기, 숙이기] — windup 과 strike

const MOVES := {
	# ---- 연속 베기 (왼쪽 클릭 연타): 왼쪽→오른쪽, 오른쪽→왼쪽, 크게 휩쓸기 ----
	"slash1": {
		"windup": 0.14, "active": 0.10, "recover": 0.26, "ai_windup": 0.45, "ai_recover": 0.45,
		"damage": 11, "cost": 9.0, "reach": 2.3, "lunge": 1.5,
		"react": "flinch", "guard": "normal", "next": "slash2", "warn": "light",
		"fp": {"windup": [Vector3(10, -55, -35), Vector3(-0.12, 0.05, 0.05)],
				"strike": [Vector3(-25, 75, 55), Vector3(0.3, -0.04, -0.12)]},
		"body": {"windup": [Vector3(95, -80, 0), Vector3(0, 90, 0), -0.5, -0.12],
				"strike": [Vector3(85, 75, 0), Vector3(0, 90, 0), 0.45, 0.25]},
	},
	"slash2": {
		"windup": 0.12, "active": 0.10, "recover": 0.26, "ai_windup": 0.34, "ai_recover": 0.45,
		"damage": 12, "cost": 9.0, "reach": 2.3, "lunge": 1.8,
		"react": "flinch", "guard": "normal", "next": "slash3", "warn": "light",
		"fp": {"windup": [Vector3(10, 55, 35), Vector3(0.12, 0.05, 0.05)],
				"strike": [Vector3(-25, -75, -55), Vector3(-0.3, -0.04, -0.12)]},
		"body": {"windup": [Vector3(95, 75, 0), Vector3(0, 90, 0), 0.45, -0.12],
				"strike": [Vector3(85, -80, 0), Vector3(0, 90, 0), -0.5, 0.25]},
	},
	"slash3": {
		"windup": 0.2, "active": 0.13, "recover": 0.42, "ai_windup": 0.42, "ai_recover": 0.7,
		"damage": 18, "cost": 13.0, "reach": 2.6, "lunge": 4.5,
		"react": "stagger", "guard": "normal", "next": "", "warn": "light",
		"fp": {"windup": [Vector3(15, -95, -55), Vector3(-0.22, 0.1, 0.16)],
				"strike": [Vector3(-30, 115, 75), Vector3(0.42, -0.06, -0.16)]},
		"body": {"windup": [Vector3(150, -60, 0), Vector3(0, 60, 0), -0.7, 0.1],
				"strike": [Vector3(60, 75, 0), Vector3(0, 60, 0), 0.7, 0.35]},
	},
	# ---- 내려찍기 (Q): 느리지만 막기를 깨뜨린다 ----
	"heavy": {
		"windup": 0.42, "active": 0.14, "recover": 0.4, "ai_windup": 0.8, "ai_recover": 0.75,
		"damage": 26, "cost": 24.0, "reach": 2.5, "lunge": 3.5,
		"react": "stagger", "guard": "break", "next": "", "warn": "heavy",
		"fp": {"windup": [Vector3(65, 10, -8), Vector3(-0.12, 0.18, 0.12)],
				"strike": [Vector3(-95, -6, 4), Vector3(-0.2, -0.22, -0.2)]},
		"body": {"windup": [Vector3(175, -10, 0), Vector3(0, 0, 0), 0.0, 0.15],
				"strike": [Vector3(35, 0, 0), Vector3(0, 0, 0), 0.0, 0.35]},
	},
	# ---- 차지 베기 (왼쪽 클릭을 길게): 모은 만큼 강해지고, 끝까지 모으면 막기를 깨뜨린다 ----
	# windup 은 '최대로 모으는 데 걸리는 시간'. 피해는 damage ~ damage_max 사이.
	"charge": {
		"windup": 0.9, "active": 0.14, "recover": 0.42, "ai_windup": 1.15, "ai_recover": 0.8,
		"damage": 18, "damage_max": 36, "cost": 22.0, "reach": 2.8, "lunge": 7.0,
		"react": "stagger", "guard": "break", "next": "", "warn": "heavy",
		"fp": {"windup": [Vector3(20, 60, 20), Vector3(0.15, 0.1, 0.15)],
				"strike": [Vector3(-45, -100, -70), Vector3(-0.38, -0.15, -0.2)]},
		"body": {"windup": [Vector3(120, -110, 0), Vector3(0, 45, 0), -0.85, -0.1],
				"strike": [Vector3(70, 80, 0), Vector3(0, 45, 0), 0.75, 0.4]},
	},
	# ---- 회피 반격: 아슬하게 피한 직후 짧은 기회에 누르면 나가는 빠른 베기. 막을 수 없다 ----
	"counter": {
		"windup": 0.05, "active": 0.12, "recover": 0.3, "ai_windup": 0.16, "ai_recover": 0.4,
		"damage": 16, "cost": 0.0, "reach": 2.7, "lunge": 8.0,
		"react": "stagger", "guard": "unblockable", "ai_guard": "normal", "next": "", "warn": "light",
		"fp": {"windup": [Vector3(20, 60, 40), Vector3(0.15, 0.08, 0.1)],
				"strike": [Vector3(-40, -95, -65), Vector3(-0.36, -0.08, -0.18)]},
		"body": {"windup": [Vector3(95, 75, 0), Vector3(0, 90, 0), 0.5, -0.05],
				"strike": [Vector3(85, -85, 0), Vector3(0, 90, 0), -0.55, 0.3]},
	},
}

## 맞았을 때 경직. time: 움직이지 못하는 시간, push: 밀려나는 힘, kick: 몸(화면)이 젖혀지는 정도
const REACTIONS := {
	"flinch": {"time": 0.22, "push": 2.5, "kick": 1.0},
	"stagger": {"time": 0.6, "push": 5.5, "kick": 2.4},
	"guard_break": {"time": 0.8, "push": 4.0, "kick": 1.8},
	"recoil": {"time": 0.4, "push": 1.5, "kick": 0.5},     # 내 공격이 막혔을 때
	"parried": {"time": 0.95, "push": 2.0, "kick": 1.2},   # 내 공격이 튕겨났을 때
}

## 공격하지 않을 때의 자세
const FP_POSES := {
	"rest": [Vector3.ZERO, Vector3.ZERO],
	"block": [Vector3(8, -20, 78), Vector3(-0.32, 0.26, 0.05)],
	"stagger": [Vector3(-35, 25, -40), Vector3(0.12, -0.28, 0.12)],
}
const BODY_POSES := {
	"guard": [Vector3(55, -15, 0), Vector3(0, 0, 0), 0.0, 0.0],
	"block": [Vector3(80, 25, 0), Vector3(0, 90, 0), 0.0, -0.05],
	"stagger": [Vector3(20, -40, 0), Vector3(0, 30, 0), 0.25, -0.3],
}


static func get_move(move_name: String) -> Dictionary:
	return MOVES[move_name]


## 모은 정도(0~1)에 따른 차지 베기 피해
static func charge_damage(level: float) -> int:
	var m: Dictionary = MOVES["charge"]
	return int(lerpf(m.damage, m.damage_max, clampf(level, 0.0, 1.0)))
