class_name Weapons
extends RefCounted
## 무기 표. 무기마다 같은 동작(MoveSet.MOVES)을 다르게 바꾸고, 필살기를 하나씩 가진다.
## 플레이어와 AI 가 같은 표를 쓴다. 숫자를 바꾸고 싶으면 이 파일만 고치면 된다.
##
## 무기 항목
##   name, desc          : 화면에 보이는 이름과 설명
##   time                : 모든 공격의 준비/휘두르기/회복 시간 배율 (작을수록 빠름)
##   damage, cost        : 피해, 기력 소모 배율
##   reach               : 닿는 거리에 더하는 값 (m)
##   lunge               : 휘두르며 내딛는 힘 배율
##   speed               : 이동 속도 배율
##   block_cost          : 이 무기로 막을 때 줄어드는 기력 배율 (작을수록 튼튼한 막기)
##   pressure            : 이 무기에 막힌 상대가 잃는 기력 배율 (클수록 막기를 잘 무너뜨림)
##   parry               : 튕겨내기 타이밍 여유 배율
##   armor               : true 면 공격을 준비하는 동안 가벼운 공격(움찔)에 끊기지 않는다 (맞교환)
##   moves               : 동작마다 따로 바꾸는 값. {"동작": {"키": 값}} 은 그 값으로 덮어쓰고,
##                         "키_mult" 는 곱한다. 예: {"thrust": {"reach_add": 0.6, "damage_mult": 1.3}}
##   special             : 필살기 (게이지가 다 차면 V)
##   ai                  : AI 가 이 무기를 들었을 때의 버릇
##                         range 좋아하는 거리 배율, heavy/grab/thrust 그 행동을 고를 가능성 배율

const ORDER := ["sword", "greatsword", "daggers", "spear", "staff", "shuriken", "fists"]

## 필살기 게이지: 이만큼 모이면 쓸 수 있다
const GAUGE_MAX := 100.0
## 게이지가 모이는 양
const GAUGE := {
	"dealt": 1.25,      # 준 피해 1 당
	"taken": 0.9,       # 받은 피해 1 당
	"parry": 18.0,      # 튕겨내기 성공
	"block": 3.0,       # 막기 성공
	"dodge": 14.0,      # 아슬한 회피
	"regen": 1.2,       # 가만히 있어도 초당 조금씩
}

# ---- 맨몸 격투 자세 ----
# 1인칭 주먹 [회전(도), 위치]: 주먹은 화면 오른쪽 아래가 기준. 왼손 동작은 거울처럼 왼쪽에 나온다.
const F_STRAIGHT := {"windup": [Vector3(10, 6, 0), Vector3(0.03, -0.03, 0.14)],
		"strike": [Vector3(-6, -4, -10), Vector3(-0.24, 0.12, -0.6)]}
const F_HOOK := {"windup": [Vector3(0, 35, 10), Vector3(0.15, 0.02, 0.05)],
		"mid": [Vector3(-5, 0, -45), Vector3(0.0, 0.12, -0.36)],
		"strike": [Vector3(-5, -45, -85), Vector3(-0.4, 0.1, -0.3)]}
const F_UPPER := {"windup": [Vector3(35, 0, 10), Vector3(0.02, -0.24, 0.06)],
		"strike": [Vector3(-70, 0, -15), Vector3(-0.16, 0.26, -0.42)]}
const F_ELBOW := {"windup": [Vector3(70, 0, -10), Vector3(0.02, 0.28, 0.12)],
		"strike": [Vector3(-30, 0, 10), Vector3(-0.14, -0.2, -0.38)]}
const F_ELBOW_DROP := {"windup": [Vector3(70, 0, -10), Vector3(0.02, 0.28, 0.12)],
		"strike": [Vector3(-40, 0, 10), Vector3(-0.14, -0.3, -0.3)]}
const F_TUCK := {"windup": [Vector3(12, 0, 10), Vector3(-0.03, 0.08, 0.08)],
		"strike": [Vector3(18, 0, 15), Vector3(-0.05, 0.12, 0.1)]}   # 발차기 동안 주먹은 얼굴 앞에
const F_GRAB := {"windup": [Vector3(-20, 30, 0), Vector3(0.0, 0.0, 0.06)],
		"strike": [Vector3(-35, 40, 0), Vector3(-0.12, 0.06, -0.42)]}
# 3인칭 몸 [어깨, 손목, 허리 비틀기, 숙이기]
const B_STRAIGHT := {"windup": [Vector3(50, 0, 10), Vector3(0, 0, 0), -0.35, 0.0, 1.8],
		"strike": [Vector3(92, 0, -10), Vector3(0, 0, 0), 0.45, 0.25, 0.08]}
const B_HOOK := {"windup": [Vector3(70, 0, 45), Vector3(0, 0, 0), -0.5, 0.0, 1.9],
		"strike": [Vector3(88, 0, -40), Vector3(0, 0, 0), 0.6, 0.2, 1.0]}
const B_UPPER := {"windup": [Vector3(20, 0, 10), Vector3(0, 0, 0), -0.3, 0.2, 1.9],
		"strike": [Vector3(120, 0, -10), Vector3(0, 0, 0), 0.3, -0.1, 1.2]}
const B_ELBOW := {"windup": [Vector3(150, 0, 10), Vector3(0, 0, 0), 0.0, -0.1, 2.3],
		"strike": [Vector3(70, 0, -15), Vector3(0, 0, 0), 0.0, 0.4, 2.4]}
const B_KICK := {"windup": [Vector3(45, 0, -12), Vector3(0, 0, 0), -0.3, -0.12, 1.95],
		"strike": [Vector3(50, 0, -18), Vector3(0, 0, 0), 0.4, -0.28, 2.0]}


const WEAPONS := {
	"sword": {
		"name": "한손검", "desc": "무난하고 빠른 기본 무기. 모든 동작이 고르다",
		"time": 1.0, "damage": 1.0, "cost": 1.0, "reach": 0.0, "lunge": 1.0,
		"speed": 1.0, "block_cost": 1.0, "pressure": 1.0, "parry": 1.0, "armor": false,
		"moves": {},
		"special": {
			"name": "회오리 베기", "desc": "몸을 한 바퀴 돌려 둘레를 모두 벤다. 막기를 깨뜨린다",
			"effect": "whirl", "dir": "side",
			"windup": 0.22, "active": 0.22, "recover": 0.4, "ai_windup": 0.5, "ai_recover": 0.6,
			"damage": 26, "cost": 0.0, "reach": 3.3, "lunge": 3.0, "push": 8.0,
			"react": "stagger", "guard": "break", "next": "", "warn": "special",
			"fp": {"windup": [Vector3(20, -120, -60), Vector3(-0.25, 0.08, 0.15)],
					"strike": [Vector3(-20, 150, 80), Vector3(0.45, -0.05, -0.15)]},
			"body": {"windup": [Vector3(100, -110, 0), Vector3(0, 90, 0), -1.1, -0.05],
					"strike": [Vector3(90, 100, 0), Vector3(0, 90, 0), 1.4, 0.2]},
		},
		"ai": {"range": 1.0, "heavy": 1.0, "grab": 1.0, "thrust": 1.0, "overhead": 1.0},
	},
	"greatsword": {
		"name": "대검", "desc": "느리지만 한 방이 크다. 휘두르는 동안 잔매에 끊기지 않고, 막혀도 상대 기력을 크게 깎는다",
		"time": 1.32, "damage": 1.3, "cost": 1.3, "reach": 0.55, "lunge": 0.85,
		"speed": 0.92, "block_cost": 0.65, "pressure": 1.45, "parry": 0.8, "armor": true,
		"moves": {
			# 크게 휘두르는 마지막 베기와 내려찍기는 맞은 상대를 크게 밀어낸다
			"slash3": {"react": "stagger", "push_add": 3.0},
			"heavy": {"push_add": 3.5, "windup_mult": 1.1},
			"overhead": {"react": "stagger"},
			"grab": {"damage_mult": 0.7, "reach_add": -0.55},   # 큰 칼을 들고 있어 잡기는 서툴다
		},
		"special": {
			"name": "대지 가르기", "desc": "뛰어올라 땅을 내리찍는다. 막을 수 없고, 앞쪽 넓은 곳을 날려 버린다",
			"effect": "quake", "dir": "high",
			"windup": 0.5, "active": 0.16, "recover": 0.65, "ai_windup": 0.85, "ai_recover": 0.85,
			"damage": 34, "cost": 0.0, "reach": 4.4, "lunge": 5.0, "push": 12.0, "lift": 4.0,
			"react": "stagger", "guard": "unblockable", "next": "", "warn": "special",
			"fp": {"windup": [Vector3(85, 8, -6), Vector3(-0.1, 0.3, 0.18)],
					"strike": [Vector3(-110, -6, 4), Vector3(-0.2, -0.32, -0.28)]},
			"body": {"windup": [Vector3(185, -10, 0), Vector3(0, 0, 0), 0.0, 0.25],
					"strike": [Vector3(25, 0, 0), Vector3(0, 0, 0), 0.0, 0.5]},
		},
		"ai": {"range": 1.15, "heavy": 2.0, "grab": 0.4, "thrust": 0.6, "overhead": 1.4},
	},
	"daggers": {
		"name": "쌍단검", "desc": "아주 빠르고 짧다. 계속 몰아치며 붙어서 잡기에 강하다. 막기는 약하다",
		"time": 0.68, "damage": 0.6, "cost": 0.62, "reach": -0.6, "lunge": 1.25,
		"speed": 1.08, "block_cost": 1.4, "pressure": 0.7, "parry": 1.3, "armor": false,
		"moves": {
			"slash3": {"next": "slash1", "react": "flinch"},     # 끝없이 이어지는 연속 베기 (기력이 허락하는 만큼)
			"grab": {"windup_mult": 0.6, "damage_mult": 1.6, "reach_add": 0.95, "recover_mult": 0.75},
			"counter": {"damage_mult": 1.9},                     # 회피 반격이 특히 아프다
			"thrust": {"damage_mult": 1.3},
		},
		"special": {
			"name": "그림자 습격", "desc": "순식간에 상대 등 뒤로 돌아가 찌른다. 막을 수 없다",
			"effect": "shadow", "dir": "mid", "jump": 9.0,
			"windup": 0.1, "active": 0.14, "recover": 0.35, "ai_windup": 0.35, "ai_recover": 0.5,
			"damage": 15, "hits": 2, "cost": 0.0, "reach": 2.2, "lunge": 2.0, "push": 3.0,
			"react": "stagger", "guard": "unblockable", "next": "", "warn": "special",
			"fp": {"windup": [Vector3(-10, 20, 10), Vector3(0.05, 0.0, 0.2)],
					"strike": [Vector3(-30, -10, 0), Vector3(-0.12, 0.04, -0.34)]},
			"body": {"windup": [Vector3(40, -60, 0), Vector3(0, 0, 0), -0.5, 0.0],
					"strike": [Vector3(90, 0, 0), Vector3(0, 0, 0), 0.3, 0.35]},
		},
		"ai": {"range": 0.75, "heavy": 0.4, "grab": 2.2, "thrust": 1.0, "overhead": 0.8},
	},
	"spear": {
		"name": "창", "desc": "멀리서 찌른다. 찌르기가 빠르고 강하지만, 가까이 붙으면 옆 베기가 굼뜨다",
		"time": 1.06, "damage": 1.0, "cost": 1.0, "reach": 0.9, "lunge": 0.9,
		"speed": 1.0, "block_cost": 0.9, "pressure": 1.0, "parry": 1.0, "armor": false,
		"moves": {
			"thrust": {"reach_add": 0.6, "damage_mult": 1.5, "windup_mult": 0.8, "next": "thrust"},
			"slash1": {"damage_mult": 0.85, "windup_mult": 1.2},
			"slash2": {"damage_mult": 0.85, "windup_mult": 1.2},
			"slash3": {"damage_mult": 0.9},
			"charge": {"dir": "mid"},                          # 힘을 모아 길게 찌른다
			"grab": {"reach_add": -0.9},                       # 긴 자루 때문에 잡기는 짧다
		},
		"special": {
			"name": "돌진 찌르기", "desc": "앞으로 내달리며 꿰뚫는다. 막기를 깨뜨리고 멀리 밀어낸다 (난간 밖으로!)",
			"effect": "rush", "dir": "mid", "rush_speed": 17.0, "rush_time": 0.42,
			"windup": 0.24, "active": 0.42, "recover": 0.45, "ai_windup": 0.55, "ai_recover": 0.6,
			"damage": 28, "cost": 0.0, "reach": 2.6, "lunge": 0.0, "push": 14.0, "lift": 2.5,
			"react": "stagger", "guard": "break", "next": "", "warn": "special",
			"fp": {"windup": [Vector3(-5, 15, 0), Vector3(0.04, -0.06, 0.32)],
					"strike": [Vector3(-18, -4, 0), Vector3(-0.1, 0.02, -0.42)]},
			"body": {"windup": [Vector3(40, -60, 0), Vector3(0, 0, 0), -0.6, 0.0],
					"strike": [Vector3(90, 0, 0), Vector3(0, 0, 0), 0.3, 0.4]},
		},
		"ai": {"range": 1.4, "heavy": 0.7, "grab": 0.5, "thrust": 3.0, "overhead": 0.7},
	},
	"staff": {
		"name": "봉", "desc": "길고 단단한 나무 봉. 양 끝으로 치고 막기가 튼튼하다. 휩쓸고 넘어뜨리기에 강하다",
		"time": 0.92, "damage": 0.86, "cost": 0.9, "reach": 0.5, "lunge": 1.0,
		"speed": 1.02, "block_cost": 0.75, "pressure": 1.1, "parry": 1.15, "armor": false,
		"moves": {
			"slash3": {"push_add": 1.5},
			"spin": {"knockdown": true, "finisher": "풍차 돌리기", "damage_mult": 1.05},
			"thrust": {"reach_add": 0.3, "push_add": 2.0},          # 봉 끝으로 밀어 찌른다
			"sweep": {"reach_add": 0.4, "damage_mult": 1.25},       # 긴 봉으로 다리를 휩쓴다
			"heavy": {"knockdown": true},                           # 내려치면 넘어진다
			"grab": {"reach_add": -0.4},
		},
		"special": {
			"name": "폭풍 난타", "desc": "봉을 휘몰아쳐 여섯 번 연달아 친다. 마지막 한 방은 막기를 깨고 넘어뜨린다",
			"effect": "flurry", "dir": "side", "strikes": 6,
			"windup": 0.2, "active": 0.78, "recover": 0.45, "ai_windup": 0.5, "ai_recover": 0.6,
			"damage": 6, "last_damage": 14, "cost": 0.0, "reach": 3.0, "lunge": 1.6, "push": 1.5, "lift": 2.0,
			"react": "flinch", "guard": "normal", "next": "", "warn": "special",
			"fp": {"windup": [Vector3(15, -95, -55), Vector3(-0.22, 0.1, 0.16)],
					"strike": [Vector3(-30, 115, 75), Vector3(0.42, -0.06, -0.16)]},
			"body": {"windup": [Vector3(100, -100, 0), Vector3(0, 90, 0), -0.9, -0.05],
					"strike": [Vector3(90, 90, 0), Vector3(0, 90, 0), 1.0, 0.2]},
		},
		"ai": {"range": 1.2, "heavy": 1.2, "grab": 0.6, "thrust": 1.4, "overhead": 1.0},
	},
	"shuriken": {
		"name": "수리검", "desc": "Q 로 끝없이 던지고, 길게 누르면 세 장을 부채꼴로 던진다. 붙으면 손에 쥔 칼날로 벤다",
		"time": 0.78, "damage": 0.74, "cost": 0.72, "reach": -0.45, "lunge": 1.15,
		"speed": 1.06, "block_cost": 1.3, "pressure": 0.75, "parry": 1.2, "armor": false,
		"moves": {
			# Q = 던지기. 수리검은 끝없이 나온다 (기력만 조금 든다). 찌르기 막기(가운데)로 막는다
			"heavy": {"windup": 0.09, "active": 0.06, "recover": 0.22, "ai_windup": 0.34, "ai_recover": 0.42,
					"damage": 7, "cost": 3.0, "reach": 18.0, "lunge": 0.0, "dir": "mid", "react": "flinch",
					"guard": "normal", "warn": "light", "next": "",
					"projectile": {"count": 1, "spread": 0.0, "speed": 34.0, "homing": 2.5},
					"fp": {"windup": [Vector3(45, -25, 10), Vector3(0.06, 0.16, 0.16)],
							"strike": [Vector3(-45, 15, -10), Vector3(-0.14, 0.02, -0.42)]},
					"body": {"windup": [Vector3(155, -30, 0), Vector3(0, 0, 0), -0.4, -0.05],
							"strike": [Vector3(85, 10, 0), Vector3(0, 0, 0), 0.35, 0.25]}},
			# 길게 눌렀다 놓으면 세 장을 한꺼번에 (끝까지 모으면 막기를 깨뜨린다)
			"charge": {"dir": "mid", "damage": 6, "damage_max": 11, "cost": 9.0, "lunge": 0.0, "reach": 18.0,
					"projectile": {"count": 3, "spread": 11.0, "speed": 38.0, "homing": 2.0},
					"fp": {"windup": [Vector3(55, -30, 10), Vector3(0.08, 0.2, 0.2)],
							"strike": [Vector3(-50, 20, -10), Vector3(-0.16, 0.0, -0.45)]},
					"body": {"windup": [Vector3(160, -40, 0), Vector3(0, 0, 0), -0.6, -0.1],
							"strike": [Vector3(85, 15, 0), Vector3(0, 0, 0), 0.45, 0.3]}},
			"grab": {"windup_mult": 0.8},
			"counter": {"damage_mult": 1.4},
		},
		"special": {
			"name": "칼날 폭풍", "desc": "수리검 여덟 장을 부채꼴로 쏟아낸다. 막으면 막기가 무너진다. 옆으로 피하라",
			"effect": "storm", "dir": "mid", "count": 8, "spread": 34.0, "speed": 30.0, "homing": 5.0,
			"windup": 0.18, "active": 0.5, "recover": 0.4, "ai_windup": 0.5, "ai_recover": 0.6,
			"damage": 6, "cost": 0.0, "reach": 14.0, "lunge": 0.0, "push": 1.5, "lift": 2.0,
			"react": "flinch", "guard": "break", "next": "", "warn": "special",
			"fp": {"windup": [Vector3(55, -30, 10), Vector3(0.08, 0.2, 0.2)],
					"strike": [Vector3(-50, 20, -10), Vector3(-0.16, 0.0, -0.45)]},
			"body": {"windup": [Vector3(160, -40, 0), Vector3(0, 0, 0), -0.6, -0.1],
					"strike": [Vector3(85, 15, 0), Vector3(0, 0, 0), 0.45, 0.3]},
		},
		"ai": {"range": 0.85, "heavy": 1.0, "grab": 1.0, "thrust": 1.0, "overhead": 0.9, "throw": 1.0},
	},
	"fists": {
		"name": "맨몸 격투", "desc": "주먹, 발차기, 호신술. 짧지만 가장 빠르고, 튕겨내기와 잡기가 강하다. 튕겨낸 상대는 오래 굳는다",
		"time": 0.8, "damage": 0.74, "cost": 0.7, "reach": -0.55, "lunge": 1.3,
		"speed": 1.12, "block_cost": 1.45, "pressure": 0.8, "parry": 1.45, "armor": false,
		"parry_stun": 1.6,
		"fp_poses": {
			"rest": [Vector3.ZERO, Vector3.ZERO],
			"block": [Vector3(-10, 25, 65), Vector3(-0.14, 0.22, 0.02)],
			"block_high": [Vector3(-25, 0, 85), Vector3(-0.16, 0.42, 0.02)],
			"block_mid": [Vector3(-25, 10, 20), Vector3(-0.12, 0.2, 0.04)],
		},
		"moves": {
			# 주먹: hand = 어느 손 (l 왼손, r 오른손). 발차기: limb = kick(앞/위), kick_round(돌려차기), kick_low(다리 걸기)
			"slash1": {"name": "왼손 훅", "hand": "l", "fp": F_HOOK, "body": B_HOOK},
			"slash2": {"name": "오른손 훅", "hand": "r", "fp": F_HOOK, "body": B_HOOK},
			"slash3": {"name": "돌려차기", "limb": "kick_round", "fp": F_TUCK, "body": B_KICK, "reach_add": 0.5, "damage_mult": 1.2},
			"spin": {"name": "뒤돌려차기", "finisher": "뒤돌려차기", "limb": "kick_round", "fp": F_TUCK, "body": B_KICK,
					"reach_add": 0.55, "damage_mult": 1.25},
			"overhead": {"name": "팔꿈치 내려찍기", "hand": "r", "limb": "elbow", "fp": F_ELBOW, "body": B_ELBOW},
			"thrust": {"name": "스트레이트", "hand": "r", "fp": F_STRAIGHT, "body": B_STRAIGHT},
			"thrust2": {"name": "왼손 잽", "hand": "l", "fp": F_STRAIGHT, "body": B_STRAIGHT},
			"rising": {"name": "어퍼컷", "hand": "r", "fp": F_UPPER, "body": B_UPPER, "damage_mult": 1.15},
			"cleave": {"name": "날아 팔꿈치", "finisher": "날아 팔꿈치", "hand": "r", "limb": "elbow", "fp": F_ELBOW, "body": B_ELBOW},
			"pierce": {"name": "옆차기", "finisher": "옆차기", "limb": "kick", "fp": F_TUCK, "body": B_KICK,
					"reach_add": 0.55, "push_add": 3.0},
			"heavy": {"name": "도끼차기", "limb": "kick", "fp": F_TUCK, "body": B_KICK, "reach_add": 0.5},
			"charge": {"name": "정권 지르기", "hand": "r", "dir": "mid", "fp": F_STRAIGHT, "body": B_STRAIGHT},
			"run_thrust": {"name": "날아 차기", "limb": "kick", "fp": F_TUCK, "body": B_KICK, "reach_add": 0.45},
			"sweep": {"name": "다리 걸기", "limb": "kick_low", "fp": F_TUCK, "reach_add": 0.4},
			"air_slash": {"name": "공중 차기", "limb": "kick", "fp": F_TUCK, "body": B_KICK, "reach_add": 0.4},
			"wall_slash": {"name": "벽 차고 돌려차기", "limb": "kick_round", "fp": F_TUCK, "body": B_KICK, "reach_add": 0.45},
			"ledge_slash": {"name": "올려차기", "limb": "kick", "fp": F_TUCK, "body": B_KICK, "reach_add": 0.4},
			"plunge": {"name": "내려찍기", "limb": "elbow", "fp": F_ELBOW_DROP},
			# 호신술: 잡기가 빠르고 멀리 닿고 크게 메친다. 아슬하게 피한 뒤 반격은 상대를 넘어뜨린다
			"grab": {"name": "업어치기", "hand": "both", "fp": F_GRAB, "windup_mult": 0.6, "damage_mult": 1.7,
					"reach_add": 0.9, "recover_mult": 0.7, "throw_speed_mult": 1.25},
			"counter": {"name": "되치기", "hand": "r", "fp": F_HOOK, "body": B_HOOK, "damage_mult": 1.4, "knockdown": true},
		},
		"special": {
			"name": "제압 메치기", "desc": "번개처럼 파고들어 붙잡아 바닥에 메친다. 막을 수 없고 넘어뜨린다",
			"effect": "takedown", "dir": "mid", "rush_speed": 14.0, "rush_time": 0.32,
			"windup": 0.16, "active": 0.32, "recover": 0.5, "ai_windup": 0.45, "ai_recover": 0.6,
			"damage": 30, "cost": 0.0, "reach": 2.0, "lunge": 0.0, "push": 3.0, "lift": 4.5, "knockdown": true,
			"react": "stagger", "guard": "unblockable", "next": "", "warn": "special", "hand": "both",
			"fp": F_GRAB,
			"body": {"windup": [Vector3(40, 0, 20), Vector3(0, 0, 0), -0.2, 0.35, 0.9],
					"strike": [Vector3(88, 0, -12), Vector3(0, 0, 0), 0.0, 0.5, 0.2]},
		},
		"ai": {"range": 0.7, "heavy": 0.8, "grab": 2.0, "thrust": 1.1, "overhead": 0.9},
	},
}

## 무기 + 동작 → 실제로 쓸 값. 한 번 만든 것은 기억해 둔다.
static var _cache := {}


static func valid(weapon: String) -> String:
	return weapon if WEAPONS.has(weapon) else "sword"


static func get_weapon(weapon: String) -> Dictionary:
	return WEAPONS[valid(weapon)]


static func display_name(weapon: String) -> String:
	return get_weapon(weapon).name


## 동작 표(MoveSet.MOVES)의 항목을 무기에 맞게 바꾼 것. "special" 은 그 무기의 필살기.
static func move(weapon: String, move_name: String) -> Dictionary:
	weapon = valid(weapon)
	var key := weapon + ":" + move_name
	if _cache.has(key):
		return _cache[key]
	var w: Dictionary = WEAPONS[weapon]
	var m: Dictionary
	if move_name == "special":
		m = w.special.duplicate(true)
		_cache[key] = m
		return m
	m = MoveSet.MOVES[move_name].duplicate(true)
	var tm: float = w.time
	for k in ["windup", "active", "recover", "ai_windup", "ai_recover"]:
		if m.has(k):
			# 휘두르는 순간(active)은 너무 짧아지면 맞추기 어려워 조금만 바꾼다
			m[k] = float(m[k]) * (lerpf(1.0, tm, 0.5) if k == "active" else tm)
	m.damage = int(round(float(m.damage) * float(w.damage)))
	if m.has("damage_max"):
		m.damage_max = int(round(float(m.damage_max) * float(w.damage)))
	m.cost = float(m.cost) * float(w.cost)
	m.reach = float(m.reach) + float(w.reach)
	m.lunge = float(m.lunge) * float(w.lunge)
	var over: Dictionary = w.moves.get(move_name, {})
	for k in over:
		var v = over[k]
		if k.ends_with("_mult"):
			var base: String = k.trim_suffix("_mult")
			m[base] = float(m[base]) * float(v)
			if base == "damage":
				m.damage = int(round(m.damage))
		elif k.ends_with("_add"):
			var base2: String = k.trim_suffix("_add")
			m[base2] = float(m.get(base2, 0.0)) + float(v)
		else:
			m[k] = v
	_cache[key] = m
	return m


## 모은 정도(0~1)에 따른 차지 공격 피해
static func charge_damage(weapon: String, level: float) -> int:
	var m := move(weapon, "charge")
	return int(lerpf(m.damage, m.damage_max, clampf(level, 0.0, 1.0)))


static func stat(weapon: String, key: String) -> float:
	return float(get_weapon(weapon)[key])


## 표에 없을 수도 있는 값 (없으면 dflt)
static func stat_or(weapon: String, key: String, dflt: float) -> float:
	return float(get_weapon(weapon).get(key, dflt))


## 공격하지 않을 때의 1인칭 자세. 무기마다 따로 정한 게 있으면 그걸 쓴다 (맨몸: 두 주먹을 올린 막기)
static func fp_pose(weapon: String, pose_name: String) -> Array:
	var own: Dictionary = get_weapon(weapon).get("fp_poses", {})
	return own.get(pose_name, MoveSet.FP_POSES[pose_name])


static func has_armor(weapon: String) -> bool:
	return bool(get_weapon(weapon).get("armor", false))


static func ai(weapon: String, key: String) -> float:
	return float(get_weapon(weapon).ai.get(key, 1.0))


# ---------------- 모양 ----------------
# 무기는 손잡이가 기준점이고 날은 +Y 로 뻗는다 (1인칭 칼과 같은 방향).
# 3인칭 몸에 붙일 때는 부르는 쪽이 -Z 로 돌려서 붙인다.
# opts (모두 없어도 된다)
#   accent : 포인트 색 (캐릭터 색. 손잡이 감개, 술, 보석)
#   glove  : 1인칭에서 무기를 쥔 손 재질 (있으면 손을 그린다)
#   sleeve : 1인칭 소매 재질
# 돌려주는 값: {"root": 무기 노드, "tip": 끝 노드, "mat": 빛나는 날 재질, "len": 날 길이, "grip2": 두 번째 손 자리(없으면 null)}

## 무기마다 두 손으로 쥐는 자리 (손잡이 기준 +Y 거리). 없으면 한 손 무기.
const GRIP2 := {"greatsword": -0.2, "spear": 0.72, "staff": 0.42}

static func build_model(parent: Node3D, weapon: String, left_hand := false, opts := {}) -> Dictionary:
	weapon = valid(weapon)
	var root := Node3D.new()
	parent.add_child(root)
	var accent_c: Color = opts.get("accent", Color(0.08, 0.55, 0.56))
	var steel := LowPoly.mat(Color(0.74, 0.77, 0.82), 0.26, 0.85)
	steel.emission_enabled = true
	steel.emission = Color(1.0, 0.72, 0.3)
	steel.emission_energy_multiplier = 0.0
	var edge := LowPoly.mat(Color(0.93, 0.95, 0.98), 0.16, 0.9)
	var fuller := LowPoly.mat(Color(0.52, 0.55, 0.6), 0.32, 0.85)
	var brass := LowPoly.mat(Color(0.78, 0.6, 0.28), 0.38, 0.8)
	var leather := LowPoly.mat(Color(0.26, 0.15, 0.09), 0.9)
	var dark := LowPoly.mat(Color(0.17, 0.18, 0.21), 0.45, 0.65)
	var wood := LowPoly.mat(Color(0.47, 0.3, 0.16), 0.75)
	var wood_dark := LowPoly.mat(Color(0.3, 0.18, 0.1), 0.8)
	var accent := LowPoly.mat(accent_c, 0.75)
	var gem := LowPoly.mat(accent_c.lightened(0.25), 0.15, 0.3)
	gem.emission_enabled = true
	gem.emission = accent_c
	gem.emission_energy_multiplier = 0.35
	var tip_y := 0.6
	var blade_len := 0.7
	var glow_mat := steel
	match weapon:
		"sword":
			# 감개를 감은 손잡이, 보석 박힌 폼멜, 끝이 휜 코등이, 홈이 파인 날
			LowPoly.part(root, LowPoly.cyl(0.021, 0.024, 0.2, 6), leather)
			for i in 3:
				LowPoly.part(root, LowPoly.cyl(0.026, 0.026, 0.018, 6), accent, Vector3(0, -0.06 + i * 0.06, 0))
			LowPoly.part(root, LowPoly.sphere(0.036, 6, 4), brass, Vector3(0, -0.125, 0))
			LowPoly.part(root, LowPoly.sphere(0.016, 6, 3), gem, Vector3(0, -0.125, -0.03))
			LowPoly.part(root, LowPoly.box(Vector3(0.2, 0.032, 0.05)), brass, Vector3(0, 0.115, 0))
			LowPoly.part(root, LowPoly.box(Vector3(0.07, 0.03, 0.035)), brass, Vector3(0.12, 0.13, 0), Vector3(0, 0, 28))
			LowPoly.part(root, LowPoly.box(Vector3(0.07, 0.03, 0.035)), brass, Vector3(-0.12, 0.13, 0), Vector3(0, 0, -28))
			LowPoly.part(root, LowPoly.box(Vector3(0.05, 0.05, 0.03)), dark, Vector3(0, 0.15, 0))
			_blade(root, 0.064, 0.78, 0.016, 0.17, 0.13, steel, edge, fuller)
			tip_y = 0.98
			blade_len = 0.8
		"greatsword":
			# 두 손 손잡이, 넓은 날, 날 밑의 걸쇠 가시, 각진 코등이
			LowPoly.part(root, LowPoly.cyl(0.026, 0.03, 0.44, 6), leather, Vector3(0, -0.09, 0))
			for i in 4:
				LowPoly.part(root, LowPoly.cyl(0.032, 0.032, 0.02, 6), accent, Vector3(0, -0.26 + i * 0.1, 0))
			LowPoly.part(root, LowPoly.cyl(0.05, 0.035, 0.07, 6), dark, Vector3(0, -0.34, 0))
			LowPoly.part(root, LowPoly.sphere(0.022, 6, 3), gem, Vector3(0, -0.38, 0))
			LowPoly.part(root, LowPoly.box(Vector3(0.36, 0.055, 0.075)), dark, Vector3(0, 0.15, 0))
			LowPoly.part(root, LowPoly.prism(Vector3(0.09, 0.08, 0.07)), dark, Vector3(0.21, 0.15, 0), Vector3(0, 0, -90))
			LowPoly.part(root, LowPoly.prism(Vector3(0.09, 0.08, 0.07)), dark, Vector3(-0.21, 0.15, 0), Vector3(0, 0, 90))
			LowPoly.part(root, LowPoly.box(Vector3(0.09, 0.14, 0.03)), dark, Vector3(0, 0.24, 0))
			# 걸쇠 가시 (날 밑에서 옆으로)
			LowPoly.part(root, LowPoly.prism(Vector3(0.05, 0.07, 0.02)), steel, Vector3(0.075, 0.33, 0), Vector3(0, 0, -100))
			LowPoly.part(root, LowPoly.prism(Vector3(0.05, 0.07, 0.02)), steel, Vector3(-0.075, 0.33, 0), Vector3(0, 0, 100))
			_blade(root, 0.13, 1.05, 0.024, 0.31, 0.22, steel, edge, fuller)
			tip_y = 1.2
			blade_len = 1.05
		"daggers":
			# 짧고 살짝 휜 날, 손가락 보호대
			LowPoly.part(root, LowPoly.cyl(0.019, 0.022, 0.13, 6), leather)
			LowPoly.part(root, LowPoly.cyl(0.024, 0.024, 0.016, 6), accent, Vector3(0, 0.0, 0))
			LowPoly.part(root, LowPoly.sphere(0.027, 6, 4), dark, Vector3(0, -0.08, 0))
			LowPoly.part(root, LowPoly.box(Vector3(0.12, 0.024, 0.04)), dark, Vector3(0, 0.075, 0))
			# 손가락 보호대 (손잡이를 감싸는 고리)
			LowPoly.part(root, LowPoly.box(Vector3(0.012, 0.15, 0.014)), dark, Vector3(0.05, 0.0, 0), Vector3(0, 0, 4))
			LowPoly.part(root, LowPoly.box(Vector3(0.05, 0.012, 0.014)), dark, Vector3(0.03, -0.075, 0))
			LowPoly.part(root, LowPoly.box(Vector3(0.054, 0.2, 0.012)), steel, Vector3(0.004, 0.18, 0), Vector3(0, 0, -2))
			LowPoly.part(root, LowPoly.box(Vector3(0.048, 0.16, 0.012)), steel, Vector3(0.012, 0.35, 0), Vector3(0, 0, -7))
			LowPoly.part(root, LowPoly.box(Vector3(0.01, 0.34, 0.016)), edge, Vector3(0.034, 0.26, 0), Vector3(0, 0, -4))
			LowPoly.part(root, LowPoly.box(Vector3(0.016, 0.26, 0.014)), fuller, Vector3(0.0, 0.24, 0), Vector3(0, 0, -4))
			LowPoly.part(root, LowPoly.prism(Vector3(0.048, 0.1, 0.012)), steel, Vector3(0.03, 0.48, 0), Vector3(0, 0, -10))
			tip_y = 0.4
			blade_len = 0.38
		"spear":
			# 쇠띠를 두른 나무 자루, 잎 모양 창날과 가운데 등줄, 날개 돌기, 포인트 색 술
			LowPoly.part(root, LowPoly.cyl(0.022, 0.025, 1.72, 7), wood, Vector3(0, 0.25, 0))
			LowPoly.part(root, LowPoly.cyl(0.028, 0.028, 0.16, 7), leather, Vector3(0, 0.0, 0))
			LowPoly.part(root, LowPoly.cyl(0.027, 0.027, 0.12, 7), leather, Vector3(0, -0.45, 0))
			for y in [-0.3, 0.35, 0.7]:
				LowPoly.part(root, LowPoly.cyl(0.027, 0.027, 0.025, 7), dark, Vector3(0, y, 0))
			LowPoly.part(root, LowPoly.cyl(0.028, 0.012, 0.1, 6), dark, Vector3(0, -0.64, 0))
			LowPoly.part(root, LowPoly.cyl(0.032, 0.026, 0.12, 7), dark, Vector3(0, 1.13, 0))
			# 술
			for i in 6:
				var a := TAU * float(i) / 6.0
				LowPoly.part(root, LowPoly.cyl(0.012, 0.004, 0.16, 4), accent, Vector3(cos(a) * 0.03, 1.02, sin(a) * 0.03), Vector3(sin(a) * 18.0, 0, -cos(a) * 18.0))
			LowPoly.part(root, LowPoly.cyl(0.04, 0.03, 0.04, 7), accent, Vector3(0, 1.09, 0))
			# 날개 돌기
			LowPoly.part(root, LowPoly.prism(Vector3(0.05, 0.06, 0.018)), dark, Vector3(0.05, 1.2, 0), Vector3(0, 0, -95))
			LowPoly.part(root, LowPoly.prism(Vector3(0.05, 0.06, 0.018)), dark, Vector3(-0.05, 1.2, 0), Vector3(0, 0, 95))
			LowPoly.part(root, LowPoly.box(Vector3(0.08, 0.22, 0.016)), steel, Vector3(0, 1.32, 0))
			LowPoly.part(root, LowPoly.box(Vector3(0.016, 0.36, 0.026)), fuller, Vector3(0, 1.36, 0))
			LowPoly.part(root, LowPoly.prism(Vector3(0.08, 0.2, 0.016)), steel, Vector3(0, 1.53, 0))
			LowPoly.part(root, LowPoly.prism(Vector3(0.08, 0.06, 0.016)), steel, Vector3(0, 1.2, 0), Vector3(0, 0, 180))
			tip_y = 1.55
			blade_len = 0.45
		"staff":
			# 양 끝에 쇠 마개, 가운데 감개 두 곳, 나뭇결 띠. 손잡이(0)가 가운데라 위아래로 뻗는다
			LowPoly.part(root, LowPoly.cyl(0.026, 0.026, 1.9, 8), wood, Vector3(0, 0.05, 0))
			for y in [-0.62, -0.3, 0.42, 0.72]:
				LowPoly.part(root, LowPoly.cyl(0.0275, 0.0275, 0.05, 8), wood_dark, Vector3(0, y, 0))
			LowPoly.part(root, LowPoly.cyl(0.03, 0.03, 0.2, 8), accent, Vector3(0, 0.0, 0))
			LowPoly.part(root, LowPoly.cyl(0.03, 0.03, 0.16, 8), accent, Vector3(0, -0.5, 0))
			for y in [0.1, -0.1, -0.42, -0.58]:
				LowPoly.part(root, LowPoly.cyl(0.032, 0.032, 0.012, 8), leather, Vector3(0, y, 0))
			# 쇠 마개 (위쪽은 빛난다 = 때리는 쪽)
			LowPoly.part(root, LowPoly.cyl(0.033, 0.03, 0.14, 8), steel, Vector3(0, 0.95, 0))
			LowPoly.part(root, LowPoly.cyl(0.02, 0.033, 0.035, 8), steel, Vector3(0, 1.04, 0))
			LowPoly.part(root, LowPoly.cyl(0.036, 0.036, 0.02, 8), dark, Vector3(0, 0.87, 0))
			LowPoly.part(root, LowPoly.cyl(0.03, 0.033, 0.14, 8), steel, Vector3(0, -0.85, 0))
			LowPoly.part(root, LowPoly.cyl(0.033, 0.02, 0.035, 8), steel, Vector3(0, -0.94, 0))
			LowPoly.part(root, LowPoly.cyl(0.036, 0.036, 0.02, 8), dark, Vector3(0, -0.77, 0))
			tip_y = 1.0
			blade_len = 0.9
		"shuriken":
			# 손에 쥔 수리검 한 장 (네 갈래 별). 날은 +Y 쪽으로 한 갈래가 튀어나온다
			var star := Node3D.new()
			star.position = Vector3(0, 0.07, 0)
			star.rotation_degrees = Vector3(0, 0, 45)
			root.add_child(star)
			var sm := MeshInstance3D.new()
			sm.mesh = shuriken_mesh()
			# 평평한 날이 하늘빛에 어둡게 보이지 않도록 덜 반짝이는 쇠
			steel.albedo_color = Color(0.86, 0.88, 0.92)
			steel.metallic = 0.45
			steel.roughness = 0.35
			sm.material_override = steel
			sm.scale = Vector3.ONE * 1.5
			sm.rotation_degrees = Vector3(90, 0, 0)
			star.add_child(sm)
			# 손잡이 대신 감개를 감은 가운데 고리
			LowPoly.part(root, LowPoly.cyl(0.02, 0.02, 0.06, 6), leather, Vector3(0, 0.0, 0))
			LowPoly.part(root, LowPoly.cyl(0.024, 0.024, 0.015, 6), accent, Vector3(0, 0.02, 0))
			tip_y = 0.19
			blade_len = 0.2
		"fists":
			# 붕대를 감은 주먹. 앞(-Z)이 주먹 머리. 손잡이 기준점 = 손목
			var skin := LowPoly.mat(opts.get("skin", Color(0.86, 0.66, 0.5)), 0.7)
			var wrap := LowPoly.mat(Color(0.93, 0.9, 0.84), 0.9)
			_fist(root, skin, wrap, accent)
			glow_mat = wrap
			wrap.emission_enabled = true
			wrap.emission = Color(1.0, 0.72, 0.3)
			wrap.emission_energy_multiplier = 0.0
			tip_y = 0.0
			blade_len = 0.1
	var grip2: Node3D = null
	if GRIP2.has(weapon):
		grip2 = Node3D.new()
		grip2.position = Vector3(0, float(GRIP2[weapon]), 0)
		root.add_child(grip2)
	if opts.has("glove") and weapon != "fists":
		_grip_hand(root, 0.0, opts.glove, opts.get("sleeve", leather))
		if grip2 != null:
			_grip_hand(root, float(GRIP2[weapon]) + (0.0 if weapon == "greatsword" else 0.0), opts.glove, null)
	if left_hand:
		root.scale = Vector3(-1, 1, 1)
	var tip := Node3D.new()
	tip.position = Vector3(0, tip_y, 0) if weapon != "fists" else Vector3(0, 0, -0.1)
	root.add_child(tip)
	return {"root": root, "tip": tip, "mat": glow_mat, "len": blade_len, "grip2": grip2}


## 1인칭 손 재질: 옷차림(BodyRig.OUTFIT)에 맞춘 장갑, 소매, 그리고 맨몸 발차기 다리의 신발/바지
static func fp_hand_mats(_weapon: String, b: CharacterBuild) -> Dictionary:
	# 무기와 상관없이 캐릭터가 고른 팔/다리/신발 모양을 따른다 (3인칭 몸과 같은 재질)
	var m := BodyRig.make_mats(b)
	var arm: Array = BodyRig.ARM_LOOK.get(b.part("arms"), BodyRig.ARM_LOOK.knight)
	var leg: Array = BodyRig.LEG_LOOK.get(b.part("legs"), BodyRig.LEG_LOOK.knight)
	return {"glove": m[arm[2]], "sleeve": m[arm[1]], "boot": m[BodyRig.FEET_LOOK.get(b.part("feet"), "leather")],
			"pants": m[leg[0]], "wrap": m.cloth}


## 홈이 파인 곧은 칼날. y0 = 날이 시작하는 높이
static func _blade(root: Node3D, w: float, length: float, t: float, y0: float, tip_len: float,
		steel: Material, edge: Material, fuller: Material) -> void:
	var body_len := length - tip_len
	var cy := y0 + body_len * 0.5
	LowPoly.part(root, LowPoly.box(Vector3(w * 0.72, body_len, t)), steel, Vector3(0, cy, 0))
	# 양날 (조금 얇고 밝다)
	for s in [-1.0, 1.0]:
		LowPoly.part(root, LowPoly.box(Vector3(w * 0.16, body_len, t * 0.6)), edge, Vector3(w * 0.42 * s, cy, 0))
	# 가운데 홈
	LowPoly.part(root, LowPoly.box(Vector3(w * 0.2, body_len * 0.78, t * 1.12)), fuller, Vector3(0, y0 + body_len * 0.42, 0))
	LowPoly.part(root, LowPoly.prism(Vector3(w, tip_len, t)), steel, Vector3(0, y0 + body_len + tip_len * 0.5, 0))


## 1인칭: 손잡이(+Y 축)를 감아쥔 장갑 손. sleeve 가 있으면 손목 소매도
static func _grip_hand(root: Node3D, y: float, glove: Material, sleeve: Variant) -> void:
	var h := Node3D.new()
	h.position = Vector3(0, y, 0)
	root.add_child(h)
	# 손바닥 + 손가락 마디 (손잡이를 앞에서 감싼다)
	LowPoly.part(h, LowPoly.box(Vector3(0.075, 0.095, 0.06)), glove, Vector3(0.0, 0.0, 0.032))
	for i in 4:
		LowPoly.part(h, LowPoly.box(Vector3(0.068, 0.022, 0.03)), glove, Vector3(-0.004, 0.035 - i * 0.023, -0.03), Vector3(0, 0, 0))
	LowPoly.part(h, LowPoly.box(Vector3(0.032, 0.05, 0.03)), glove, Vector3(-0.045, 0.03, 0.0), Vector3(0, 0, -25))
	if sleeve != null:
		LowPoly.part(h, LowPoly.cyl(0.05, 0.045, 0.06, 7), glove, Vector3(0.0, -0.06, 0.04), Vector3(-20, 0, 0))
		LowPoly.part(h, LowPoly.cyl(0.058, 0.052, 0.22, 7), sleeve, Vector3(0.0, -0.18, 0.08), Vector3(-20, 0, 0))


## 붕대 감은 주먹 (앞 = -Z). 손목에서 팔뚝이 뒤(+Z)로 이어진다
static func _fist(root: Node3D, skin: Material, wrap: Material, accent: Material) -> void:
	LowPoly.part(root, LowPoly.box(Vector3(0.09, 0.085, 0.1)), wrap, Vector3(0, 0, -0.05))
	for i in 4:
		LowPoly.part(root, LowPoly.box(Vector3(0.022, 0.04, 0.034)), skin, Vector3(-0.033 + i * 0.022, 0.012, -0.105), Vector3(0, 0, 0))
	LowPoly.part(root, LowPoly.box(Vector3(0.094, 0.03, 0.03)), wrap, Vector3(0, 0.028, -0.104))
	LowPoly.part(root, LowPoly.box(Vector3(0.035, 0.03, 0.06)), skin, Vector3(-0.05, -0.025, -0.07), Vector3(0, 15, 0))
	LowPoly.part(root, LowPoly.cyl(0.045, 0.05, 0.1, 7), wrap, Vector3(0, -0.005, 0.03), Vector3(90, 0, 0))
	LowPoly.part(root, LowPoly.cyl(0.047, 0.047, 0.02, 7), accent, Vector3(0, -0.005, 0.07), Vector3(90, 0, 0))
	LowPoly.part(root, LowPoly.cyl(0.05, 0.058, 0.3, 7), skin, Vector3(0, -0.01, 0.22), Vector3(90, 0, 0))


## 수리검 별 모양 (XZ 평면, 가운데 구멍). 던지는 수리검도 같은 모양을 쓴다
static var _star_mesh: ArrayMesh = null

static func shuriken_mesh() -> ArrayMesh:
	if _star_mesh != null:
		return _star_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := 4
	var r_out := 0.085
	var r_in := 0.026
	var t := 0.007
	var ring := []
	for i in points * 2:
		var a := TAU * float(i) / float(points * 2)
		var r := r_out if i % 2 == 0 else r_in
		ring.append(Vector3(cos(a) * r, 0, sin(a) * r))
	var top := Vector3(0, t, 0)
	var bot := Vector3(0, -t, 0)
	for i in ring.size():
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % ring.size()]
		# 가운데가 도톰한 날: 위아래 두 면
		for tri in [[top, b, a], [bot, a, b]]:
			var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			for v in tri:
				st.set_normal(n)
				st.add_vertex(v)
	_star_mesh = st.commit()
	return _star_mesh
