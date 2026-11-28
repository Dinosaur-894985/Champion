class_name AnimStyle
extends RefCounted
## 무기마다 다른 '애니풍' 몸놀림 표. 플레이어(1인칭)와 AI(3인칭 몸)가 같은 표를 쓴다.
##
## 이 표는 '보이는 모습'만 바꾼다. 공격 시간(준비/휘두르기/회복), 피해, 막기 판정은
## MoveSet / Weapons 표 그대로라서 여기 숫자를 바꿔도 밸런스는 바뀌지 않는다.
## 공격 방향(위/옆/찌르기)이 잘 읽히도록, 동작의 '끝 자세'는 그대로 두고
## 그 앞뒤(더 크게 당기기, 휘두른 뒤 더 지나가기)와 서 있기/달리기/점프만 과장한다.
##
## 1인칭 (자세 = [회전(도), 위치])
##   fp_rest   : 서 있을 때 무기 자세 (Weapons.fp_pose 의 "rest")
##   fp_run    : 달릴 때 무기 기준점에 더하는 [회전, 위치] (화면 기준)
##   fp_air    : 공중에 떠 있을 때 더하는 [회전, 위치]
##   idle      : 서 있을 때 숨쉬듯 흔들리는 [크기(위치), 빠르기]
##   pump      : 달릴 때 손이 앞뒤로 흔들리는 크기. alt 가 true 면 두 손이 번갈아 (쌍단검, 맨몸)
##   antic     : 준비 자세를 얼마나 더 크게 당기나 (0.2 = 20% 더)
##   follow    : 휘두른 뒤 얼마나 더 지나가나 (회복 시간 앞쪽 일부를 쓴다)
##   snap      : 휘두르기 빠르기 느낌 "expo" 날카롭게 / "cubic" 묵직하게
##   flourish  : 이중 점프·바람 발판 때 무기 돌리기 "twirl" 화면에서 한 바퀴 / "flip" 손목 뒤집기 / "heave" 들어올리기
##   land      : 착지할 때 무기가 눌리는 무게
## 3인칭 몸
##   guard     : 서 있는 자세 [어깨, 손목, 허리 비틀기, 숙이기, 팔꿈치]
##   left      : 왼팔 자세 [어깨, 팔꿈치] (두 손 무기는 자루를 잡으니 안 쓴다)
##   stance    : 다리 {"spread" 벌리기, "stagger" 앞뒤 엇갈림(m), "crouch" 낮추기(m), "bounce" 들썩임}
##   run       : 달릴 때 팔 "back" 두 팔을 뒤로 젖히고 달리기 / "shoulder" 어깨에 걸치기 / "low" 낮게 앞으로 겨누기
##   lean      : 달릴 때 몸을 앞으로 숙이는 정도
##   amp       : 공격할 때 허리 비틀기/숙이기를 얼마나 더 크게
##   air_flip  : 높이 뛸 때 공중제비 (1 = 앞으로 한 바퀴)

const STYLES := {
	# 한손검: 칼끝을 상대에게 겨누고 몸을 옆으로 튼 자세. 깔끔하고 날카로운 동작
	"sword": {
		"fp_rest": [Vector3(-14, 4, 16), Vector3(-0.02, -0.03, 0.0)],
		"fp_run": [Vector3(-16, 0, -24), Vector3(0.04, -0.03, 0.06)],
		"fp_air": [Vector3(18, -6, 14), Vector3(0.0, 0.07, 0.02)],
		"idle": [0.006, 1.6], "pump": 0.035, "alt": false,
		"antic": 0.22, "follow": 0.2, "snap": "expo", "flourish": "flip", "land": 1.0,
		"guard": [Vector3(72, -24, -6), Vector3(-38, 0, 0), -0.45, 0.08, 0.35],
		"left": [Vector3(55, 0, -25), 0.9],
		"stance": {"spread": 0.12, "stagger": 0.22, "crouch": 0.07, "bounce": 0.0},
		"run": "back", "lean": 0.32, "amp": 1.25, "air_flip": 1.0,
	},
	# 대검: 큰 칼을 어깨 위로 비스듬히 메고 낮게 버틴다. 크게 당겨서 무겁게 내리친다
	"greatsword": {
		"fp_rest": [Vector3(-22, 6, 26), Vector3(-0.04, -0.08, 0.04)],
		"fp_run": [Vector3(-14, 0, 18), Vector3(0.0, -0.03, 0.06)],
		"fp_air": [Vector3(25, 0, -8), Vector3(0.0, 0.1, 0.04)],
		"idle": [0.008, 1.1], "pump": 0.02, "alt": false,
		"antic": 0.32, "follow": 0.3, "snap": "cubic", "flourish": "heave", "land": 1.8,
		"guard": [Vector3(140, -30, -10), Vector3(0, -20, 0), -0.55, 0.06, 0.9],
		"left": [Vector3(60, 0, -20), 1.0],
		"stance": {"spread": 0.2, "stagger": 0.18, "crouch": 0.12, "bounce": 0.0},
		"run": "shoulder", "lean": 0.22, "amp": 1.35, "air_flip": 0.0,
	},
	# 쌍단검: 몸을 낮게 숙이고 두 칼을 앞뒤로 엇갈려 든다. 튀어 나가듯 빠르게
	"daggers": {
		"fp_rest": [Vector3(-12, 0, 24), Vector3(-0.02, -0.02, 0.0)],
		"fp_run": [Vector3(-16, -10, -20), Vector3(0.03, -0.03, 0.06)],
		"fp_air": [Vector3(-30, 30, 40), Vector3(0.02, 0.05, 0.0)],
		"idle": [0.009, 2.6], "pump": 0.05, "alt": true,
		"antic": 0.25, "follow": 0.22, "snap": "expo", "flourish": "twirl", "land": 0.7,
		"guard": [Vector3(70, 30, 0), Vector3(-70, 0, 0), -0.25, 0.28, 1.1],
		"left": [Vector3(60, 0, 30), 1.2],
		"stance": {"spread": 0.24, "stagger": 0.3, "crouch": 0.16, "bounce": 0.0},
		"run": "back", "lean": 0.5, "amp": 1.3, "air_flip": 1.0,
	},
	# 창: 낮게 깔고 창끝을 길게 앞으로. 길게 뻗었다가 끌어당긴다
	"spear": {
		"fp_rest": [Vector3(-12, 6, -8), Vector3(0.0, -0.06, 0.04)],
		"fp_run": [Vector3(-20, 0, 0), Vector3(0.0, -0.08, 0.12)],
		"fp_air": [Vector3(20, 0, 10), Vector3(0.0, 0.06, 0.0)],
		"idle": [0.006, 1.4], "pump": 0.025, "alt": false,
		"antic": 0.24, "follow": 0.25, "snap": "expo", "flourish": "twirl", "land": 1.2,
		"guard": [Vector3(58, -6, 0), Vector3(-72, 0, 0), -0.6, 0.14, 0.45],
		"left": [Vector3(60, 0, -20), 0.6],
		"stance": {"spread": 0.18, "stagger": 0.36, "crouch": 0.12, "bounce": 0.0},
		"run": "low", "lean": 0.35, "amp": 1.2, "air_flip": 0.0,
	},
	# 봉: 봉을 비스듬히 몸 앞에 세우고 다리를 넓게 벌린다. 빙글빙글 돌리며 친다
	"staff": {
		"fp_rest": [Vector3(-20, -20, 38), Vector3(-0.06, -0.02, 0.04)],
		"fp_run": [Vector3(-12, 10, 40), Vector3(0.0, -0.03, 0.06)],
		"fp_air": [Vector3(0, 0, 60), Vector3(-0.04, 0.06, 0.0)],
		"idle": [0.007, 1.3], "pump": 0.03, "alt": false,
		"antic": 0.26, "follow": 0.28, "snap": "expo", "flourish": "twirl", "land": 1.1,
		"guard": [Vector3(72, -40, -10), Vector3(-20, 0, -68), -0.3, 0.1, 0.8],
		"left": [Vector3(60, 0, -20), 0.6],
		"stance": {"spread": 0.3, "stagger": 0.12, "crouch": 0.16, "bounce": 0.0},
		"run": "back", "lean": 0.3, "amp": 1.3, "air_flip": 1.0,
	},
	# 수리검: 한 손은 얼굴 옆에 칼날을 끼워 들고, 가볍게 발끝으로 선다. 던질 때 몸을 크게 젖힌다
	"shuriken": {
		"fp_rest": [Vector3(15, -20, 25), Vector3(0.02, 0.05, 0.06)],
		"fp_run": [Vector3(-16, 0, -20), Vector3(0.03, -0.03, 0.06)],
		"fp_air": [Vector3(-20, 20, 30), Vector3(0.0, 0.08, 0.0)],
		"idle": [0.008, 2.2], "pump": 0.05, "alt": true,
		"antic": 0.3, "follow": 0.24, "snap": "expo", "flourish": "twirl", "land": 0.7,
		"guard": [Vector3(130, -10, -25), Vector3(0, 0, 0), -0.4, 0.12, 2.0],
		"left": [Vector3(55, 0, 25), 0.4],
		"stance": {"spread": 0.2, "stagger": 0.26, "crouch": 0.1, "bounce": 0.02},
		"run": "back", "lean": 0.5, "amp": 1.3, "air_flip": 1.0,
	},
	# 맨몸: 주먹을 높이 들고 발끝으로 통통 튄다. 주먹을 크게 감았다 내지른다
	"fists": {
		"fp_rest": [Vector3.ZERO, Vector3.ZERO],
		"fp_run": [Vector3(40, 0, 0), Vector3(0.02, -0.16, 0.12)],
		"fp_air": [Vector3(-15, 0, 10), Vector3(0.0, 0.05, 0.0)],
		"idle": [0.012, 3.0], "pump": 0.07, "alt": true,
		"antic": 0.28, "follow": 0.2, "snap": "expo", "flourish": "none", "land": 0.8,
		"guard": [],   # 맨몸은 BodyRig._fist_stance 가 두 주먹 자세를 만든다
		"left": [],
		"stance": {"spread": 0.18, "stagger": 0.3, "crouch": 0.1, "bounce": 0.03},
		"run": "back", "lean": 0.42, "amp": 1.3, "air_flip": 1.0,
	},
}


static func get_style(weapon: String) -> Dictionary:
	return STYLES.get(weapon, STYLES.sword)


static func val(weapon: String, key: String, dflt = null):
	return get_style(weapon).get(key, dflt)


## 준비 자세를 더 크게: 서 있는 자세에서 준비 자세로 가는 만큼을 더 간다 (회전은 ±175도 안에서)
static func anticipate(weapon: String, windup: Array, rest: Array) -> Array:
	var a := float(val(weapon, "antic", 0.2))
	var r: Vector3 = windup[0] + (windup[0] - rest[0]) * a
	r = r.clamp(Vector3.ONE * -175.0, Vector3.ONE * 175.0)
	var p: Vector3 = windup[1] + (windup[1] - rest[1]) * a * 0.6
	return [r, p]


## 휘두른 뒤 더 지나가는 자세: 준비 → 휘두르기 방향으로 조금 더
static func follow_through(weapon: String, windup: Array, strike: Array) -> Array:
	var f := float(val(weapon, "follow", 0.2))
	var r: Vector3 = strike[0] + (strike[0] - windup[0]) * f
	r = r.clamp(Vector3.ONE * -175.0, Vector3.ONE * 175.0)
	var p: Vector3 = strike[1] + (strike[1] - windup[1]) * f * 0.5
	return [r, p]
