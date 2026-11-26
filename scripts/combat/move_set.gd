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
##   next                      : 이어지는 연속 베기 동작 (마우스 방향 없이 계속 클릭할 때)
##   branch                    : 연속기 갈래. 다음 클릭 때 마우스를 위/옆/아래로 움직이면 그 방향 동작으로 이어진다
##                               {"high": 동작, "side": 동작, "mid": 동작}. 없으면 next 를 쓴다
##   finisher                  : 연속기 마무리 이름 (화면에 잠깐 뜬다)
##   keep_speed                : 휘두르는 동안 달리던 빠르기를 거의 그대로 유지 (달리며 찌르기, 슬라이딩 베기 등)
##   knockdown                 : 맞으면 넘어진다
##   dir                       : 공격 방향 "high" 위 / "side" 옆 / "mid" 찌르기 (AttackDir). 막는 쪽은 같은 방향으로 막아야 한다
##   fp                        : 1인칭 칼 자세 [회전(도), 위치] — windup 과 strike. "mid" 가 있으면 휘두르는 길 가운데를 지나간다 (곡선)
##   body                      : 3인칭 몸 자세 [어깨, 손목, 허리 비틀기, 숙이기] — windup 과 strike

const MOVES := {
	# ---- 높이를 쓰는 기술 (scripts/combat/vertical_kit.gd 와 함께) ----
	# 낙하 찍기: 1.6m 넘게 떠 있을 때 공격하면 아래로 내리꽂는다. 높이 떨어질수록 강하고, 막기를 깨고, 넘어뜨린다.
	#   damage ~ damage_max: 떨어진 높이에 따라. reach: 착지할 때 둘레 반지름.
	"plunge": {
		"windup": 0.12, "active": 0.0, "recover": 0.55, "ai_windup": 0.3, "ai_recover": 0.75,
		"damage": 16, "damage_max": 42, "cost": 14.0, "reach": 2.6, "lunge": 0.0, "dir": "high",
		"react": "stagger", "guard": "break", "next": "", "warn": "heavy", "knockdown": true,
		"fp": {"windup": [Vector3(70, 5, -5), Vector3(0.0, 0.25, 0.1)],
				"strike": [Vector3(-110, 0, 0), Vector3(-0.15, -0.3, -0.25)]},
		"body": {"windup": [Vector3(178, 0, 0), Vector3(0, 0, 0), 0.0, -0.1],
				"strike": [Vector3(30, 0, 0), Vector3(0, 0, 0), 0.0, 0.5]},
	},
	# 공중 베기: 낮게 떠 있을 때 공격. 빠르고 앞으로 조금 나간다.
	"air_slash": {
		"windup": 0.09, "active": 0.12, "recover": 0.26, "ai_windup": 0.3, "ai_recover": 0.4,
		"damage": 12, "cost": 8.0, "reach": 2.5, "lunge": 2.5, "dir": "high", "keep_speed": true,
		"react": "flinch", "guard": "normal", "next": "", "warn": "light",
		"fp": {"windup": [Vector3(45, -35, -20), Vector3(-0.05, 0.15, 0.08)],
				"mid": [Vector3(-20, 5, 5), Vector3(0.05, -0.02, -0.36)],
				"strike": [Vector3(-60, 40, 30), Vector3(0.18, -0.15, -0.15)]},
		"body": {"windup": [Vector3(150, -40, 0), Vector3(0, 45, 0), -0.3, -0.1],
				"strike": [Vector3(60, 50, 0), Vector3(0, 45, 0), 0.3, 0.35]},
	},
	# 난간 반격: 매달린 채 공격하면 뛰어오르며 벤다. 못 막고 크게 휘청이게 한다.
	"ledge_slash": {
		"windup": 0.06, "active": 0.14, "recover": 0.38, "ai_windup": 0.22, "ai_recover": 0.5,
		"damage": 17, "cost": 10.0, "reach": 2.8, "lunge": 3.0, "dir": "mid",
		"react": "stagger", "guard": "unblockable", "ai_guard": "break", "next": "", "warn": "heavy",
		"fp": {"windup": [Vector3(30, 70, 40), Vector3(0.15, -0.1, 0.1)],
				"strike": [Vector3(-35, -100, -70), Vector3(-0.38, 0.05, -0.2)]},
		"body": {"windup": [Vector3(95, 75, 0), Vector3(0, 90, 0), 0.5, -0.05],
				"strike": [Vector3(85, -85, 0), Vector3(0, 90, 0), -0.55, 0.3]},
	},
	# ---- 연속 베기 (왼쪽 클릭 연타): 왼쪽→오른쪽, 오른쪽→왼쪽, 크게 휩쓸기 ----
	"slash1": {
		"dir": "side",
		"windup": 0.14, "active": 0.10, "recover": 0.26, "ai_windup": 0.45, "ai_recover": 0.45,
		"damage": 11, "cost": 9.0, "reach": 2.3, "lunge": 1.5,
		"react": "flinch", "guard": "normal", "next": "slash2", "warn": "light",
		"branch": {"side": "slash2", "high": "rising", "mid": "thrust2"},
		"fp": {"windup": [Vector3(10, -55, -35), Vector3(-0.12, 0.05, 0.05)],
				"mid": [Vector3(-30, 5, 10), Vector3(0.06, -0.08, -0.34)],
				"strike": [Vector3(-25, 75, 55), Vector3(0.3, -0.04, -0.12)]},
		"body": {"windup": [Vector3(95, -80, 0), Vector3(0, 90, 0), -0.5, -0.12],
				"strike": [Vector3(85, 75, 0), Vector3(0, 90, 0), 0.45, 0.25]},
	},
	"slash2": {
		"dir": "side",
		"windup": 0.12, "active": 0.10, "recover": 0.26, "ai_windup": 0.34, "ai_recover": 0.45,
		"damage": 12, "cost": 9.0, "reach": 2.3, "lunge": 1.8,
		"react": "flinch", "guard": "normal", "next": "slash3", "warn": "light",
		"branch": {"side": "slash3", "high": "rising", "mid": "thrust2"},
		"fp": {"windup": [Vector3(10, 55, 35), Vector3(0.12, 0.05, 0.05)],
				"mid": [Vector3(-30, -5, -10), Vector3(-0.06, -0.08, -0.34)],
				"strike": [Vector3(-25, -75, -55), Vector3(-0.3, -0.04, -0.12)]},
		"body": {"windup": [Vector3(95, 75, 0), Vector3(0, 90, 0), 0.45, -0.12],
				"strike": [Vector3(85, -80, 0), Vector3(0, 90, 0), -0.5, 0.25]},
	},
	"slash3": {
		"dir": "side",
		"windup": 0.2, "active": 0.13, "recover": 0.42, "ai_windup": 0.42, "ai_recover": 0.7,
		"damage": 18, "cost": 13.0, "reach": 2.6, "lunge": 4.5,
		"react": "stagger", "guard": "normal", "next": "spin", "warn": "light",
		"branch": {"side": "spin", "high": "cleave", "mid": "pierce"},
		"fp": {"windup": [Vector3(15, -95, -55), Vector3(-0.22, 0.1, 0.16)],
				"mid": [Vector3(-35, 10, 15), Vector3(0.08, -0.1, -0.38)],
				"strike": [Vector3(-30, 115, 75), Vector3(0.42, -0.06, -0.16)]},
		"body": {"windup": [Vector3(150, -60, 0), Vector3(0, 60, 0), -0.7, 0.1],
				"strike": [Vector3(60, 75, 0), Vector3(0, 60, 0), 0.7, 0.35]},
	},
	# ---- 연속기 갈래 (두 번째, 세 번째 클릭 때 마우스 방향으로 고른다) ----
	# 올려베기: 아래에서 위로. 찌르기 막기(가운데)로 막아야 한다.
	"rising": {
		"dir": "mid",
		"windup": 0.12, "active": 0.11, "recover": 0.28, "ai_windup": 0.4, "ai_recover": 0.48,
		"damage": 13, "cost": 10.0, "reach": 2.35, "lunge": 2.2,
		"react": "flinch", "guard": "normal", "next": "slash3", "warn": "light",
		"branch": {"side": "slash3", "high": "cleave", "mid": "pierce"},
		"fp": {"windup": [Vector3(-80, 25, 20), Vector3(0.14, -0.3, 0.02)],
				"mid": [Vector3(-20, 10, 5), Vector3(0.05, -0.1, -0.36)],
				"strike": [Vector3(65, -20, -15), Vector3(-0.1, 0.24, -0.14)]},
		"body": {"windup": [Vector3(15, -30, 0), Vector3(0, 0, 0), 0.35, 0.25],
				"strike": [Vector3(170, 20, 0), Vector3(0, 0, 0), -0.2, -0.15]},
	},
	# 두 번 찌르기: 빠르게 한 번 더.
	"thrust2": {
		"dir": "mid",
		"windup": 0.1, "active": 0.09, "recover": 0.26, "ai_windup": 0.36, "ai_recover": 0.45,
		"damage": 10, "cost": 8.0, "reach": 2.85, "lunge": 2.6,
		"react": "flinch", "guard": "normal", "next": "pierce", "warn": "light",
		"branch": {"side": "slash3", "high": "cleave", "mid": "pierce"},
		"fp": {"windup": [Vector3(-10, -14, 0), Vector3(-0.05, -0.02, 0.18)],
				"strike": [Vector3(-18, 8, 0), Vector3(0.06, 0.0, -0.32)]},
		"body": {"windup": [Vector3(40, -45, 0), Vector3(0, 0, 0), -0.4, -0.05],
				"strike": [Vector3(90, 5, 0), Vector3(0, 0, 0), 0.3, 0.32]},
	},
	# ---- 마무리 (연속기 끝): 크고 아프다. 맞으면 크게 휘청이고 밀려난다 ----
	# 회전 베기: 옆으로 이어 가면 네 번째에 한 바퀴 돌며 벤다.
	"spin": {
		"dir": "side", "finisher": "회전 베기",
		"windup": 0.2, "active": 0.16, "recover": 0.48, "ai_windup": 0.45, "ai_recover": 0.75,
		"damage": 20, "cost": 15.0, "reach": 2.8, "lunge": 4.0, "push_add": 2.5,
		"react": "stagger", "guard": "normal", "next": "", "warn": "heavy",
		"fp": {"windup": [Vector3(15, -115, -60), Vector3(-0.26, 0.1, 0.18)],
				"mid": [Vector3(-40, 15, 20), Vector3(0.05, -0.1, -0.4)],
				"strike": [Vector3(-25, 145, 80), Vector3(0.46, -0.05, -0.12)]},
		"body": {"windup": [Vector3(100, -110, 0), Vector3(0, 90, 0), -1.1, -0.05],
				"strike": [Vector3(90, 100, 0), Vector3(0, 90, 0), 1.4, 0.2]},
	},
	# 쪼개기: 위로 이어 가면 뛰어올라 내리찍는다. 막기를 깨뜨린다.
	"cleave": {
		"dir": "high", "finisher": "쪼개기",
		"windup": 0.24, "active": 0.13, "recover": 0.5, "ai_windup": 0.55, "ai_recover": 0.8,
		"damage": 22, "cost": 16.0, "reach": 2.55, "lunge": 4.0,
		"react": "stagger", "guard": "break", "next": "", "warn": "heavy", "hop": 3.2,
		"fp": {"windup": [Vector3(85, 10, -8), Vector3(-0.1, 0.28, 0.16)],
				"mid": [Vector3(0, 0, 0), Vector3(-0.14, 0.05, -0.4)],
				"strike": [Vector3(-108, -6, 4), Vector3(-0.2, -0.32, -0.25)]},
		"body": {"windup": [Vector3(180, -10, 0), Vector3(0, 0, 0), 0.0, -0.1],
				"strike": [Vector3(30, 0, 0), Vector3(0, 0, 0), 0.0, 0.45]},
	},
	# 꿰뚫기: 찌르기로 이어 가면 몸을 날려 깊게 찌른다. 멀리 밀어낸다.
	"pierce": {
		"dir": "mid", "finisher": "꿰뚫기",
		"windup": 0.18, "active": 0.12, "recover": 0.45, "ai_windup": 0.48, "ai_recover": 0.7,
		"damage": 18, "cost": 13.0, "reach": 3.1, "lunge": 9.0, "push_add": 4.0,
		"react": "stagger", "guard": "normal", "next": "", "warn": "heavy",
		"fp": {"windup": [Vector3(-8, 18, 0), Vector3(0.06, -0.06, 0.3)],
				"strike": [Vector3(-14, -4, 0), Vector3(-0.12, 0.02, -0.5)]},
		"body": {"windup": [Vector3(40, -65, 0), Vector3(0, 0, 0), -0.6, -0.1],
				"strike": [Vector3(92, 0, 0), Vector3(0, 0, 0), 0.35, 0.5]},
	},
	# ---- 움직이며 쓰는 기술 (상황별 공격) ----
	# 달리며 찌르기: 달리는 중에 클릭. 달리던 힘을 그대로 실어 찌른다.
	"run_thrust": {
		"dir": "mid", "keep_speed": true,
		"windup": 0.08, "active": 0.12, "recover": 0.36, "ai_windup": 0.34, "ai_recover": 0.55,
		"damage": 15, "cost": 12.0, "reach": 2.9, "lunge": 3.0, "push_add": 2.0,
		"react": "stagger", "guard": "normal", "next": "", "warn": "light",
		"fp": {"windup": [Vector3(-8, 12, 0), Vector3(0.04, -0.08, 0.24)],
				"strike": [Vector3(-16, -4, 0), Vector3(-0.1, 0.0, -0.5)]},
		"body": {"windup": [Vector3(45, -60, 0), Vector3(0, 0, 0), -0.5, 0.1],
				"strike": [Vector3(90, 0, 0), Vector3(0, 0, 0), 0.3, 0.45]},
	},
	# 다리 베기: 슬라이딩 중에 클릭. 낮게 휩쓸어 넘어뜨린다. 가운데(찌르기 막기)로 막는다.
	"sweep": {
		"dir": "mid", "keep_speed": true, "knockdown": true,
		"windup": 0.06, "active": 0.16, "recover": 0.34, "ai_windup": 0.3, "ai_recover": 0.6,
		"damage": 11, "cost": 10.0, "reach": 2.5, "lunge": 0.0,
		"react": "flinch", "guard": "normal", "next": "", "warn": "light",
		"fp": {"windup": [Vector3(-55, -70, -45), Vector3(-0.22, -0.26, 0.02)],
				"mid": [Vector3(-75, 5, 5), Vector3(0.05, -0.36, -0.3)],
				"strike": [Vector3(-60, 85, 60), Vector3(0.38, -0.32, -0.12)]},
		"body": {"windup": [Vector3(40, -90, 0), Vector3(0, 90, 0), -0.6, 0.5],
				"strike": [Vector3(30, 80, 0), Vector3(0, 90, 0), 0.6, 0.6]},
	},
	# 벽 차고 베기: 벽을 달리다(또는 벽을 차고 뛴 직후) 클릭. 보는 쪽으로 날아들며 돌려 벤다.
	"wall_slash": {
		"dir": "side", "keep_speed": true,
		"windup": 0.07, "active": 0.14, "recover": 0.34, "ai_windup": 0.3, "ai_recover": 0.5,
		"damage": 17, "cost": 10.0, "reach": 2.7, "lunge": 0.0, "push_add": 2.0,
		"react": "stagger", "guard": "normal", "next": "", "warn": "light",
		"fp": {"windup": [Vector3(30, -95, -55), Vector3(-0.22, 0.12, 0.15)],
				"mid": [Vector3(-35, 10, 15), Vector3(0.06, -0.08, -0.38)],
				"strike": [Vector3(-40, 125, 72), Vector3(0.42, -0.06, -0.16)]},
		"body": {"windup": [Vector3(150, -60, 0), Vector3(0, 60, 0), -0.7, 0.1],
				"strike": [Vector3(60, 75, 0), Vector3(0, 60, 0), 0.7, 0.35]},
	},
	# ---- 내려찍기 (Q): 느리지만 막기를 깨뜨린다 ----
	"heavy": {
		"dir": "high",
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
		"dir": "side",
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
		"dir": "side",
		"windup": 0.05, "active": 0.12, "recover": 0.3, "ai_windup": 0.16, "ai_recover": 0.4,
		"damage": 16, "cost": 0.0, "reach": 2.7, "lunge": 8.0,
		"react": "stagger", "guard": "unblockable", "ai_guard": "normal", "next": "", "warn": "light",
		"fp": {"windup": [Vector3(20, 60, 40), Vector3(0.15, 0.08, 0.1)],
				"strike": [Vector3(-40, -95, -65), Vector3(-0.36, -0.08, -0.18)]},
		"body": {"windup": [Vector3(95, 75, 0), Vector3(0, 90, 0), 0.5, -0.05],
				"strike": [Vector3(85, -85, 0), Vector3(0, 90, 0), -0.55, 0.3]},
	},
	# ---- 위에서 내려베기 (마우스를 살짝 위로 움직이며 클릭): 옆 베기보다 조금 느리고 아프다 ----
	"overhead": {
		"dir": "high",
		"windup": 0.17, "active": 0.1, "recover": 0.3, "ai_windup": 0.5, "ai_recover": 0.5,
		"damage": 14, "cost": 10.0, "reach": 2.35, "lunge": 2.0,
		"react": "flinch", "guard": "normal", "next": "slash2", "warn": "light",
		"branch": {"side": "slash2", "high": "rising", "mid": "thrust2"},
		"fp": {"windup": [Vector3(55, 6, -6), Vector3(-0.06, 0.16, 0.1)],
				"mid": [Vector3(-15, 0, 0), Vector3(-0.1, 0.0, -0.36)],
				"strike": [Vector3(-82, -4, 3), Vector3(-0.14, -0.2, -0.18)]},
		"body": {"windup": [Vector3(165, -8, 0), Vector3(0, 0, 0), 0.0, 0.08],
				"strike": [Vector3(45, 0, 0), Vector3(0, 0, 0), 0.0, 0.32]},
	},
	# ---- 찌르기 (마우스를 살짝 아래로 움직이며 클릭): 빠르고 멀리 닿지만 약하다 ----
	"thrust": {
		"dir": "mid",
		"windup": 0.13, "active": 0.09, "recover": 0.28, "ai_windup": 0.42, "ai_recover": 0.45,
		"damage": 10, "cost": 8.0, "reach": 2.8, "lunge": 3.0,
		"react": "flinch", "guard": "normal", "next": "slash2", "warn": "light",
		"branch": {"side": "slash2", "high": "rising", "mid": "thrust2"},
		"fp": {"windup": [Vector3(-12, 10, 0), Vector3(0.0, -0.04, 0.2)],
				"strike": [Vector3(-22, -6, 0), Vector3(-0.14, 0.02, -0.28)]},
		"body": {"windup": [Vector3(45, -55, 0), Vector3(0, 0, 0), -0.45, -0.05],
				"strike": [Vector3(88, 0, 0), Vector3(0, 0, 0), 0.25, 0.3]},
	},
	# ---- 잡기 (F): 막기를 뚫고 잡아 던진다. 하지만 휘두르는 상대에게는 끊기고, 빗나가면 빈틈이 크다 ----
	# 가위바위보: 공격 > 잡기 > 막기 > 공격
	"grab": {
		"dir": "",
		"windup": 0.18, "active": 0.1, "recover": 0.5, "ai_windup": 0.4, "ai_recover": 0.65,
		"damage": 12, "cost": 12.0, "reach": 1.9, "lunge": 3.0,
		"react": "thrown", "guard": "grab", "next": "", "warn": "grab",
		"throw_speed": 9.0, "throw_up": 3.2,
		"fp": {"windup": [Vector3(-25, 45, 30), Vector3(0.2, -0.14, 0.16)],
				"strike": [Vector3(-30, 55, 40), Vector3(0.26, -0.12, 0.02)]},
		"body": {"windup": [Vector3(70, 45, 0), Vector3(0, 0, 0), 0.35, 0.05],
				"strike": [Vector3(85, 25, 0), Vector3(0, 0, 0), 0.1, 0.35]},
	},
}

## 맞았을 때 경직. time: 움직이지 못하는 시간, push: 밀려나는 힘, kick: 몸(화면)이 젖혀지는 정도
const REACTIONS := {
	"knockdown": {"time": 1.05, "push": 3.0, "kick": 3.0},   # 넘어짐 (낙하 찍기, 밀려 떨어짐)
	"flinch": {"time": 0.22, "push": 2.5, "kick": 1.0},
	"stagger": {"time": 0.6, "push": 5.5, "kick": 2.4},
	"guard_break": {"time": 0.8, "push": 4.0, "kick": 1.8},
	"recoil": {"time": 0.4, "push": 1.5, "kick": 0.5},     # 내 공격이 막혔을 때
	"parried": {"time": 0.95, "push": 2.0, "kick": 1.2},   # 내 공격이 튕겨났을 때
	"thrown": {"time": 0.95, "push": 0.0, "kick": 2.6},    # 잡혀서 던져졌을 때 (미는 힘은 던진 쪽이 정한다)
	"grab_fail": {"time": 0.55, "push": 1.5, "kick": 0.8}, # 잡으려다 상대 공격에 끊겼을 때
	"wall_slam": {"time": 0.45, "push": 0.0, "kick": 1.6}, # 던져져서 벽에 부딪혔을 때 (더해지는 경직)
}

## 던지기와 벽꽝
const THROW := {
	"wall_slam_damage": 8,     # 던져져 벽에 부딪히면 더 받는 피해
	"wall_slam_speed": 3.5,    # 이보다 빠르게 부딪혀야 벽꽝
	"slam_time": 0.6,          # 던져진 뒤 이 시간 안에 부딪혀야 벽꽝
	"feint_cost": 6.0,         # 공격을 준비하다 멈출 때(속임수) 드는 기력
}

## 벽 동작 (이동 기술). 캐릭터의 traits 에 이름이 켜져 있어야 쓸 수 있다.
## 나중에 능력치/빌드로 "벽을 탈 수 있는 캐릭터" 를 정할 때 이 이름을 쓴다.
##   wall_climb : 벽을 보고 앞으로 누른 채 점프 → 벽을 타고 오른다. 꼭대기에 닿으면 손으로 짚고 올라선다.
##   wall_run   : 벽 옆을 달리다 점프 → 벽을 따라 옆으로 달린다. 달리는 중 Space 로 벽 차고 뛰기.
const TRAVERSAL := {
	"wall_climb": {
		"speed": 5.2,          # 오르는 빠르기 (m/초)
		"max_time": 1.35,      # 한 번에 오를 수 있는 시간 → 약 7m
		"cost": 14.0,          # 초당 기력
		"mantle_up": 6.0,      # 꼭대기를 짚고 몸을 끌어올리는 빠르기
		"mantle_fwd": 4.5,     # 꼭대기에서 앞으로 나가는 힘
		"kick_out": 6.0,       # 오르다 Space: 벽을 차고 뒤로
		"kick_up": 5.0,
	},
	"wall_run": {
		"speed": 9.0,          # 벽을 따라 달리는 빠르기
		"max_time": 1.1,
		"gravity": 0.22,       # 달리는 동안 중력 비율 (천천히 떨어짐)
		"lift": 2.2,           # 벽에 붙는 순간 살짝 떠오르는 힘
		"cost": 8.0,           # 붙을 때 기력
		"min_speed": 4.0,      # 이만큼 빨라야 벽에 붙는다
		"jump_out": 6.5,       # 벽 차고 뛰기: 벽 반대쪽으로
		"jump_up": 6.0,
	},
}

## 달리기와 슬라이딩 (Shift 달리기, C 앉기). 누구나 쓸 수 있다.
const RUN := {
	"sprint_accel": 30.0,     # 달리기를 누르면 이 빠르기로 금방 빨라진다 (순간 돌진은 없다)
	"carry_accel": 4.0,       # 슬라이딩/점프 뒤 빠르기가 남아 있을 때 천천히 줄어드는 정도
	"crouch_mult": 0.5,       # 앉아 걷기 빠르기 배율
	"slide_min_speed": 5.5,   # 이만큼 빨라야 슬라이딩이 된다
	"slide_boost": 1.15,      # 미끄러지기 시작할 때 빠르기 배율 (달리던 빠르기 기준)
	"slide_friction": 6.0,    # 초당 줄어드는 빠르기
	"slide_end_speed": 3.8,   # 이보다 느려지면 슬라이딩이 끝난다
	"slide_max_time": 1.0,
	"slide_cost": 8.0,
	"slide_jump": 5.0,        # 슬라이딩 중 Space: 빠르기를 유지한 채 뛰어오른다
	"wall_slash_time": 0.45,  # 벽을 차고 뛴 뒤 이 시간 안에 클릭하면 벽 차고 베기
	"wall_slash_speed": 10.0, # 벽 차고 베기로 날아드는 빠르기
	"run_attack_speed": 6.5,  # 이보다 빨리 달리며 클릭하면 달리며 찌르기
}

## 연속기: 지금 동작(prev) 다음에 dir 방향으로 클릭했을 때 이어지는 동작. 없으면 "".
## 옆(또는 방향 없이)으로 이으면 next, 위/아래로 이으면 branch 의 갈래.
static func combo_next(data: Dictionary, dir: String) -> String:
	if dir in [AttackDir.HIGH, AttackDir.MID] and data.has("branch"):
		return str(data.branch.get(dir, data.get("next", "")))
	return str(data.get("next", ""))


## 연속기 첫 동작
static func combo_start(dir: String, side: float = 0.0) -> String:
	match dir:
		AttackDir.HIGH:
			return "overhead"
		AttackDir.MID:
			return "thrust"
	return "slash2" if side > 0.0 else "slash1"


## 공격하지 않을 때의 자세
const FP_POSES := {
	"hang": [Vector3(-60, 0, -10), Vector3(0.1, -0.5, 0.1)],
	"plunge": [Vector3(-110, 0, 0), Vector3(-0.15, -0.1, -0.2)],
	"zip": [Vector3(70, -20, 10), Vector3(0.0, 0.15, 0.05)],
	"rest": [Vector3.ZERO, Vector3.ZERO],
	"block": [Vector3(8, -20, 78), Vector3(-0.32, 0.26, 0.05)],         # 옆 막기
	"block_high": [Vector3(10, -80, 80), Vector3(-0.3, 0.42, 0.0)],     # 위 막기: 칼을 머리 위로 눕힌다
	"block_mid": [Vector3(40, -10, 0), Vector3(-0.28, 0.08, 0.0)],      # 찌르기 막기: 칼을 가운데에 곧게 세운다
	"stagger": [Vector3(-35, 25, -40), Vector3(0.12, -0.28, 0.12)],
	"climb": [Vector3(-50, 10, -20), Vector3(0.18, -0.45, 0.15)],
	"wallrun": [Vector3(-10, 30, 25), Vector3(0.05, -0.12, 0.05)],
	"slide": [Vector3(-30, -25, -40), Vector3(0.1, -0.2, 0.12)],
	"carry": [Vector3(-70, 0, 0), Vector3(0.1, -0.5, 0.1)],
}
const BODY_POSES := {
	"hang": [Vector3(175, 0, 0), Vector3(0, 0, 0), 0.0, -0.1],
	"plunge": [Vector3(178, 0, 0), Vector3(0, 0, 0), 0.0, 0.4],
	"guard": [Vector3(55, -15, 0), Vector3(0, 0, 0), 0.0, 0.0],
	"block": [Vector3(80, 25, 0), Vector3(0, 90, 0), 0.0, -0.05],
	"block_high": [Vector3(160, 30, 0), Vector3(0, 90, 0), 0.0, -0.05],
	"block_mid": [Vector3(70, 0, 0), Vector3(0, 0, 0), 0.0, -0.08],
	"stagger": [Vector3(20, -40, 0), Vector3(0, 30, 0), 0.25, -0.3],
	"climb": [Vector3(170, 0, 0), Vector3(0, 0, 0), 0.0, -0.25],
	"kick": [Vector3(60, -20, 0), Vector3(0, 0, 0), 0.4, -0.2],
}


static func get_move(move_name: String) -> Dictionary:
	return MOVES[move_name]


## 모은 정도(0~1)에 따른 차지 베기 피해
static func charge_damage(level: float) -> int:
	var m: Dictionary = MOVES["charge"]
	return int(lerpf(m.damage, m.damage_max, clampf(level, 0.0, 1.0)))


## 막기 방향 → 1인칭/3인칭 막기 자세 이름
static func block_pose(guard: String) -> String:
	return {"high": "block_high", "mid": "block_mid"}.get(guard, "block")
