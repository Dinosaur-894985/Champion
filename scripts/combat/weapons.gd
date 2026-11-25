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

const ORDER := ["sword", "greatsword", "daggers", "spear"]

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
		"time": 1.32, "damage": 1.4, "cost": 1.3, "reach": 0.55, "lunge": 0.85,
		"speed": 0.92, "block_cost": 0.65, "pressure": 1.7, "parry": 0.8, "armor": true,
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


static func has_armor(weapon: String) -> bool:
	return bool(get_weapon(weapon).get("armor", false))


static func ai(weapon: String, key: String) -> float:
	return float(get_weapon(weapon).ai.get(key, 1.0))


# ---------------- 모양 ----------------
# 무기는 손잡이가 기준점이고 날은 +Y 로 뻗는다 (1인칭 칼과 같은 방향).
# 3인칭 몸에 붙일 때는 부르는 쪽이 -Z 로 돌려서 붙인다.
# 돌려주는 값: {"root": 무기 노드, "tip": 끝 노드, "mat": 빛나는 날 재질, "len": 날 길이}

static func build_model(parent: Node3D, weapon: String, left_hand := false) -> Dictionary:
	weapon = valid(weapon)
	var root := Node3D.new()
	parent.add_child(root)
	var steel := LowPoly.mat(Color(0.78, 0.80, 0.84), 0.28, 0.85)
	steel.emission_enabled = true
	steel.emission = Color(1.0, 0.72, 0.3)
	steel.emission_energy_multiplier = 0.0
	var edge := LowPoly.mat(Color(0.92, 0.94, 0.97), 0.18, 0.9)
	var brass := LowPoly.mat(Color(0.72, 0.55, 0.25), 0.4, 0.8)
	var leather := LowPoly.mat(Color(0.28, 0.16, 0.10), 0.9)
	var dark := LowPoly.mat(Color(0.2, 0.21, 0.24), 0.5, 0.6)
	var wood := LowPoly.mat(Color(0.42, 0.27, 0.15), 0.8)
	var accent := LowPoly.mat(Color(0.08, 0.55, 0.56), 0.8)   # 몸 천과 같은 청록색
	var tip_y := 0.6
	var blade_len := 0.7
	match weapon:
		"sword":
			LowPoly.part(root, LowPoly.cyl(0.022, 0.025, 0.2, 6), leather)
			LowPoly.part(root, LowPoly.sphere(0.034, 6, 4), brass, Vector3(0, -0.12, 0))
			LowPoly.part(root, LowPoly.box(Vector3(0.24, 0.03, 0.05)), brass, Vector3(0, 0.115, 0))
			LowPoly.part(root, LowPoly.box(Vector3(0.05, 0.035, 0.035)), brass, Vector3(0.13, 0.12, 0), Vector3(0, 0, 25))
			LowPoly.part(root, LowPoly.box(Vector3(0.05, 0.035, 0.035)), brass, Vector3(-0.13, 0.12, 0), Vector3(0, 0, -25))
			LowPoly.part(root, LowPoly.box(Vector3(0.062, 0.78, 0.014)), steel, Vector3(0, 0.52, 0))
			LowPoly.part(root, LowPoly.box(Vector3(0.012, 0.76, 0.018)), edge, Vector3(0, 0.52, 0))
			LowPoly.part(root, LowPoly.prism(Vector3(0.062, 0.12, 0.014)), steel, Vector3(0, 0.97, 0))
		"greatsword":
			# 두 손 손잡이, 넓은 날, 각진 코등이
			LowPoly.part(root, LowPoly.cyl(0.026, 0.03, 0.42, 6), leather, Vector3(0, -0.08, 0))
			LowPoly.part(root, LowPoly.cyl(0.03, 0.03, 0.05, 6), accent, Vector3(0, 0.02, 0))
			LowPoly.part(root, LowPoly.sphere(0.05, 6, 4), dark, Vector3(0, -0.32, 0))
			LowPoly.part(root, LowPoly.box(Vector3(0.38, 0.05, 0.07)), dark, Vector3(0, 0.15, 0))
			LowPoly.part(root, LowPoly.prism(Vector3(0.08, 0.07, 0.06)), dark, Vector3(0.2, 0.15, 0), Vector3(0, 0, -90))
			LowPoly.part(root, LowPoly.prism(Vector3(0.08, 0.07, 0.06)), dark, Vector3(-0.2, 0.15, 0), Vector3(0, 0, 90))
			LowPoly.part(root, LowPoly.box(Vector3(0.13, 1.1, 0.022)), steel, Vector3(0, 0.73, 0))
			LowPoly.part(root, LowPoly.box(Vector3(0.03, 1.0, 0.028)), dark, Vector3(0, 0.68, 0))
			LowPoly.part(root, LowPoly.box(Vector3(0.016, 1.08, 0.026)), edge, Vector3(0.058, 0.73, 0))
			LowPoly.part(root, LowPoly.box(Vector3(0.016, 1.08, 0.026)), edge, Vector3(-0.058, 0.73, 0))
			LowPoly.part(root, LowPoly.prism(Vector3(0.13, 0.2, 0.022)), steel, Vector3(0, 1.38, 0))
			tip_y = 1.0
			blade_len = 1.05
		"daggers":
			# 짧고 휜 날, 손가락 보호대
			LowPoly.part(root, LowPoly.cyl(0.02, 0.022, 0.13, 6), leather)
			LowPoly.part(root, LowPoly.sphere(0.028, 6, 4), dark, Vector3(0, -0.08, 0))
			LowPoly.part(root, LowPoly.box(Vector3(0.12, 0.025, 0.04)), accent, Vector3(0, 0.075, 0))
			LowPoly.part(root, LowPoly.box(Vector3(0.055, 0.34, 0.012)), steel, Vector3(0.006, 0.26, 0), Vector3(0, 0, -3))
			LowPoly.part(root, LowPoly.box(Vector3(0.01, 0.32, 0.016)), edge, Vector3(0.03, 0.26, 0), Vector3(0, 0, -3))
			LowPoly.part(root, LowPoly.prism(Vector3(0.055, 0.1, 0.012)), steel, Vector3(0.02, 0.47, 0), Vector3(0, 0, -6))
			tip_y = 0.36
			blade_len = 0.36
		"spear":
			# 긴 나무 자루, 잎 모양 창날, 청록 술
			LowPoly.part(root, LowPoly.cyl(0.022, 0.024, 1.7, 6), wood, Vector3(0, 0.25, 0))
			LowPoly.part(root, LowPoly.cyl(0.028, 0.028, 0.14, 6), leather, Vector3(0, 0.0, 0))
			LowPoly.part(root, LowPoly.cyl(0.026, 0.02, 0.06, 6), dark, Vector3(0, -0.62, 0))
			LowPoly.part(root, LowPoly.cyl(0.03, 0.026, 0.1, 6), dark, Vector3(0, 1.12, 0))
			LowPoly.part(root, LowPoly.cyl(0.05, 0.02, 0.12, 6), accent, Vector3(0, 1.08, 0))
			LowPoly.part(root, LowPoly.box(Vector3(0.075, 0.24, 0.016)), steel, Vector3(0, 1.28, 0))
			LowPoly.part(root, LowPoly.box(Vector3(0.012, 0.3, 0.022)), edge, Vector3(0, 1.3, 0))
			LowPoly.part(root, LowPoly.prism(Vector3(0.075, 0.18, 0.016)), steel, Vector3(0, 1.49, 0))
			tip_y = 1.3
			blade_len = 0.4
	if left_hand:
		root.scale = Vector3(-1, 1, 1)
	var tip := Node3D.new()
	tip.position = Vector3(0, tip_y, 0)
	root.add_child(tip)
	return {"root": root, "tip": tip, "mat": steel, "len": blade_len}
