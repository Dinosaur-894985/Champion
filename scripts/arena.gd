class_name Arena
extends Node3D
## 경기장: 하늘 위에 떠 있는 3층짜리 돌 경기장.
##   1층 (바닥 0m)   : 가운데 결투 원, 낮은 받침돌, 화분, 바람 발판
##   2층 (2.5~3.5m) : 서쪽 집, 동쪽 집, 북쪽 회랑, 남쪽 테라스, 부서지는 돌기둥
##   3층 (6.5m)     : 가운데 네 기둥과 그 위 다리 두 개, 동쪽 탑. 오르내리는 발판으로 올라간다.
## 가장자리에는 벽이 없다. 밀려 떨어지면 아래 허공으로 떨어진다 (VerticalKit 참고).
## 바닥은 네 겹 고리로 나뉘어 있고, 대결이 길어지면 바깥 고리부터 무너진다 (ArenaDirector 가 정한다).
##
## 모든 구조물은 아래 표(BLOCKS, RAMPS, LIFTS, ZIPLINES)에 적혀 있고,
## 표를 고치면 모양, 충돌, AI 길찾기가 함께 바뀐다.
##
## AI 길찾기
##   바닥에는 2.5m 간격으로 길목 점을 깔고, 구조물 위에도 점을 깐다.
##   점끼리는 "걷기", "점프"(낮은 턱), "벽 타기"(높은 벽, 벽을 탈 수 있는 캐릭터만), "뛰어내리기",
##   "발판"(오르내리는 발판 타기), "짚라인"(높은 곳에서 줄 타고 내려가기) 으로 잇는다.
##   find_path() 가 이 점들을 따라가는 길을 알려 준다. 무너질 고리의 점은 꺼서 그쪽으로 가지 않는다.

const HALF := 27.0              # 경기장 반 너비
const GRID := 2.5
## 바닥 고리: 가운데(0)부터 바깥(3)까지, 가운데에서 이 거리(가로·세로 중 큰 쪽)까지
const RINGS := [11.0, 17.0, 23.0, 27.0]
const TIER3 := 6.5
## 윗면 장식(띠, 판)은 몸통 윗면보다 이만큼 높게 둔다. 같은 높이에 색이 다른 면 두 장이 겹치면
## 화면을 돌릴 때 두 색이 번갈아 비치며 반짝인다 (특히 웹 버전).
const LIFT_TOP := 0.025

# ---- 우리 경기장 색 ----
const C_FLOOR_A := Color(0.70, 0.63, 0.53)
const C_FLOOR_B := Color(0.65, 0.58, 0.48)
const C_GROUT := Color(0.50, 0.43, 0.36)
const C_TEAL := Color(0.08, 0.42, 0.46)
const C_CORAL := Color(0.86, 0.38, 0.30)
const C_NAVY := Color(0.19, 0.23, 0.36)
const C_GOLD := Color(0.95, 0.74, 0.30)
const C_STONE := Color(0.88, 0.85, 0.79)
const C_STONE2 := Color(0.74, 0.69, 0.62)
const C_ROCK := Color(0.52, 0.46, 0.42)

## 구조물: 이름, 가운데 (x, z), 크기 (x, z), 밑면 높이, 높이, 모양
##   on: 이 구조물 위에 얹혀 있음 / float: 공중에 떠 있는 다리 (밑으로 지나갈 수 있음)
##   no_climb: 벽 타기 불가 / pickup: 아이템이 생기는 자리 이름
const BLOCKS := [
	# ---- 가운데 (끝까지 남는 곳) ----
	{"id": "spire_nw", "c": Vector2(-7, -7), "s": Vector2(2.4, 2.4), "base": 0.0, "h": TIER3, "style": "pillar", "pickup": "기둥 꼭대기"},
	{"id": "spire_ne", "c": Vector2(7, -7), "s": Vector2(2.4, 2.4), "base": 0.0, "h": TIER3, "style": "pillar", "pickup": "기둥 꼭대기"},
	{"id": "spire_sw", "c": Vector2(-7, 7), "s": Vector2(2.4, 2.4), "base": 0.0, "h": TIER3, "style": "pillar", "pickup": "기둥 꼭대기"},
	{"id": "spire_se", "c": Vector2(7, 7), "s": Vector2(2.4, 2.4), "base": 0.0, "h": TIER3, "style": "pillar", "pickup": "기둥 꼭대기"},
	{"id": "bridge_n", "c": Vector2(0, -7), "s": Vector2(11.6, 1.8), "base": TIER3 - 0.5, "h": 0.5, "style": "bridge", "float": true, "pickup": "북쪽 다리"},
	{"id": "bridge_s", "c": Vector2(0, 7), "s": Vector2(11.6, 1.8), "base": TIER3 - 0.5, "h": 0.5, "style": "bridge", "float": true, "pickup": "남쪽 다리"},
	{"id": "plinth_w", "c": Vector2(-4.2, 0), "s": Vector2(1.6, 1.6), "base": 0.0, "h": 1.1, "style": "plinth"},
	{"id": "plinth_e", "c": Vector2(4.2, 0), "s": Vector2(1.6, 1.6), "base": 0.0, "h": 1.1, "style": "plinth"},
	# ---- 2층 (세 번째로 무너짐) ----
	{"id": "west_house", "c": Vector2(-14, 0), "s": Vector2(5, 9), "base": 0.0, "h": 3.5, "style": "house", "pickup": "서쪽 지붕"},
	{"id": "east_house", "c": Vector2(14, 0), "s": Vector2(5, 9), "base": 0.0, "h": 3.0, "style": "house"},
	{"id": "east_tower", "c": Vector2(15.0, 1.5), "s": Vector2(3.0, 3.0), "base": 3.0, "h": TIER3 - 3.0, "style": "tower", "on": "east_house", "pickup": "동쪽 탑"},
	{"id": "gallery", "c": Vector2(0, -14), "s": Vector2(14, 3.5), "base": 0.0, "h": 3.0, "style": "gallery", "pickup": "북쪽 회랑"},
	{"id": "terrace", "c": Vector2(0, 14), "s": Vector2(10, 4), "base": 0.0, "h": 2.5, "style": "terrace"},
	# ---- 바깥 둘째 고리 (두 번째로 무너짐) : 부서지는 돌기둥과 발판 ----
	{"id": "obelisk_nw", "c": Vector2(-19.5, -12), "s": Vector2(1.6, 1.6), "base": 0.0, "h": 4.6, "style": "obelisk", "pickup": "돌기둥 위"},
	{"id": "obelisk_se", "c": Vector2(19.5, 12), "s": Vector2(1.6, 1.6), "base": 0.0, "h": 4.6, "style": "obelisk", "pickup": "돌기둥 위"},
	{"id": "obelisk_ne", "c": Vector2(12, -19.5), "s": Vector2(1.6, 1.6), "base": 0.0, "h": 4.6, "style": "obelisk", "pickup": "돌기둥 위"},
	{"id": "obelisk_sw", "c": Vector2(-12, 19.5), "s": Vector2(1.6, 1.6), "base": 0.0, "h": 4.6, "style": "obelisk", "pickup": "돌기둥 위"},
	{"id": "step1", "c": Vector2(-19.5, 19.5), "s": Vector2(2.2, 2.2), "base": 0.0, "h": 1.1, "style": "step"},
	{"id": "step2", "c": Vector2(-17.0, 21.0), "s": Vector2(2.2, 2.2), "base": 0.0, "h": 2.2, "style": "step"},
	{"id": "step3", "c": Vector2(-14.6, 19.6), "s": Vector2(2.2, 2.2), "base": 0.0, "h": 3.3, "style": "step"},
	{"id": "runwall_w", "c": Vector2(-5.5, 20), "s": Vector2(0.6, 6), "base": 0.0, "h": 4.0, "style": "runwall", "no_climb": true},
	{"id": "runwall_e", "c": Vector2(5.5, 20), "s": Vector2(0.6, 6), "base": 0.0, "h": 4.0, "style": "runwall", "no_climb": true},
	{"id": "planter_b1", "c": Vector2(19.5, -19.5), "s": Vector2(2, 2), "base": 0.0, "h": 1.1, "style": "planter"},
	{"id": "planter_b2", "c": Vector2(-20, -20), "s": Vector2(1.6, 1.6), "base": 0.0, "h": 1.1, "style": "planter"},
	# ---- 맨 바깥 고리 (가장 먼저 무너짐) ----
	{"id": "planter_a1", "c": Vector2(-25, -6), "s": Vector2(2, 2), "base": 0.0, "h": 1.1, "style": "planter"},
	{"id": "planter_a2", "c": Vector2(25, 6), "s": Vector2(2, 2), "base": 0.0, "h": 1.1, "style": "planter"},
	{"id": "planter_a3", "c": Vector2(8, 25), "s": Vector2(1.6, 1.6), "base": 0.0, "h": 1.1, "style": "planter"},
	{"id": "planter_a4", "c": Vector2(-8, -25), "s": Vector2(1.6, 1.6), "base": 0.0, "h": 1.1, "style": "planter"},
]

## 계단/경사로: 아래 끝, 위 끝, 너비, 올라가면 닿는 구조물
const RAMPS := [
	{"from": Vector3(-14, 0, 9.6), "to": Vector3(-14, 3.5, 4.5), "w": 3.0, "top": "west_house", "stairs": true},
	{"from": Vector3(13.0, 0, -9.6), "to": Vector3(13.0, 3.0, -4.5), "w": 3.0, "top": "east_house", "stairs": true},
	{"from": Vector3(12.8, 0, -14), "to": Vector3(7.0, 3.0, -14), "w": 3.0, "top": "gallery", "stairs": false},
	{"from": Vector3(-12.8, 0, -14), "to": Vector3(-7.0, 3.0, -14), "w": 3.0, "top": "gallery", "stairs": false},
	{"from": Vector3(-9.6, 0, 14), "to": Vector3(-5.0, 2.5, 14), "w": 2.6, "top": "terrace", "stairs": true},
	{"from": Vector3(9.6, 0, 14), "to": Vector3(5.0, 2.5, 14), "w": 2.6, "top": "terrace", "stairs": true},
]

## 오르내리는 발판: 가운데 (x, z), 올라가는 높이, 위에서 닿는 구조물, 처음 자리
const LIFTS := [
	{"c": Vector2(0, -9.45), "top": TIER3, "reach": "bridge_n", "start": "bottom"},
	{"c": Vector2(0, 9.45), "top": TIER3, "reach": "bridge_s", "start": "top"},
]

## 짚라인: 높은 끝, 낮은 끝 (줄 높이), 출발 구조물, 도착 구조물
const ZIPLINES := [
	{"id": "zip_east", "a": Vector3(14.0, TIER3 + 2.45, 1.5), "b": Vector3(-12.6, 3.5 + 2.3, -0.5), "from": "east_tower", "to": "west_house"},
	{"id": "zip_south", "a": Vector3(6.6, TIER3 + 2.45, 7.7), "b": Vector3(1.2, 2.5 + 2.3, 14.2), "from": "spire_se", "to": "terrace"},
]

## 발판끼리, 또는 발판에서 기둥으로 점프로 잇는 길
const JUMP_LINKS := [["step1", "step2"], ["step2", "step3"], ["step3", "obelisk_sw"]]
## 높이가 같아 걸어서 이어지는 구조물 (다리 ↔ 기둥)
const TOP_LINKS := [["bridge_n", "spire_nw"], ["bridge_n", "spire_ne"], ["bridge_s", "spire_sw"], ["bridge_s", "spire_se"]]

## 바람 발판: 가운데 (x, z), 내려앉는 곳(발 높이), 궤적 꼭대기 높이, 내려앉는 구조물(길찾기)
##   안쪽 둘은 기둥 꼭대기로 솟구치고, 바깥 둘은 집 지붕 위를 넘어 경기장 한가운데로 날아든다.
const LAUNCH_PADS := [
	{"id": "pad_sw", "c": Vector2(-10.5, 7.5), "to": Vector3(-7.0, TIER3, 7.0), "apex": 8.6, "area": "spire_sw"},
	{"id": "pad_ne", "c": Vector2(10.5, -7.5), "to": Vector3(7.0, TIER3, -7.0), "apex": 8.6, "area": "spire_ne"},
	{"id": "pad_w", "c": Vector2(-20.5, 0.0), "to": Vector3(-2.4, 0.0, 0.0), "apex": 9.0, "area": "ground"},
	{"id": "pad_e", "c": Vector2(20.5, -1.5), "to": Vector3(2.4, 0.0, -1.5), "apex": 9.0, "area": "ground"},
]

## 낭떠러지에 떨어진 뒤 다시 서는 자리
const SAFE_SPOTS := [Vector3(0, 0.1, 4.5), Vector3(0, 0.1, -4.5), Vector3(-2.2, 0.1, 0), Vector3(2.2, 0.1, 0)]

# ---------------- 경기장 종류 ----------------
## "sky"    하늘 경기장: 한낮, 하늘 위에 뜬 돌 경기장 (처음 경기장)
## "garden" 노을 정원: 해 질 녘 호수 위 절벽 정원. 같은 뼈대를 90도 돌려 놓아 길이 다르고,
##          색·빛·풍경(호수, 꽃나무, 떠다니는 등불)이 다르다.
## 색 이름은 역할 이름이다 (teal = 첫째 강조색, coral = 둘째, navy = 짙은 색, gold = 반짝이 장식).
const THEMES := {
	"sky": {"name": "하늘 경기장", "turn": 0,
		"pal": {"floor_a": C_FLOOR_A, "floor_b": C_FLOOR_B, "grout": C_GROUT, "teal": C_TEAL, "coral": C_CORAL,
			"navy": C_NAVY, "gold": C_GOLD, "stone": C_STONE, "stone2": C_STONE2, "rock": C_ROCK,
			"leaf": Color(0.36, 0.60, 0.38), "sand": Color(0.86, 0.76, 0.60), "window": Color(0.16, 0.24, 0.32)}},
	"garden": {"name": "노을 정원", "turn": 1,
		"pal": {"floor_a": Color(0.89, 0.81, 0.72), "floor_b": Color(0.85, 0.77, 0.68), "grout": Color(0.68, 0.56, 0.52),
			"teal": Color(0.38, 0.58, 0.46), "coral": Color(0.97, 0.58, 0.42), "navy": Color(0.34, 0.22, 0.40),
			"gold": Color(0.98, 0.80, 0.42), "stone": Color(0.95, 0.90, 0.85), "stone2": Color(0.82, 0.74, 0.70),
			"rock": Color(0.55, 0.45, 0.50), "leaf": Color(0.95, 0.62, 0.70), "sand": Color(0.92, 0.82, 0.70),
			"window": Color(0.30, 0.20, 0.30)}},
}
const THEME_ORDER := ["sky", "garden"]
## 하늘과 빛 (Game._build_environment 가 쓴다). 웹은 거기서 따로 조금 눌러 준다.
const ENV := {
	"sky": {"top": Color(0.30, 0.58, 0.90), "horizon": Color(0.86, 0.90, 0.93), "ground_h": Color(0.80, 0.82, 0.78),
		"ground_b": Color(0.45, 0.52, 0.40), "ambient": Color(0.86, 0.84, 0.80), "fog": Color(0.84, 0.88, 0.93),
		"fog_density": 0.004, "sun_rot": Vector3(-52, -30, 0), "sun": Color(1.0, 0.94, 0.84), "sun_energy": 1.0,
		"saturation": 1.08},
	"garden": {"top": Color(0.30, 0.44, 0.82), "horizon": Color(1.0, 0.82, 0.62), "ground_h": Color(0.98, 0.78, 0.62),
		"ground_b": Color(0.50, 0.42, 0.58), "ambient": Color(0.90, 0.86, 0.84), "fog": Color(0.98, 0.86, 0.76),
		"fog_density": 0.0025, "sun_rot": Vector3(-34, 115, 0), "sun": Color(1.0, 0.86, 0.68), "sun_energy": 1.1,
		"saturation": 1.16},
}

var theme := "sky"              # Game 이 add_child 전에 정한다
var _pal := {}                  # 지금 경기장 색
var _lay := {}                  # 지금 경기장 표 (BLOCKS 등을 돌려 놓은 것)

var fighters: Array = []        # 플레이어와 AI (Game 이 넣어 준다)
var director: ArenaDirector
var lifts: Array[ArenaLift] = []
var pads: Array[LaunchPad] = []
var ziplines: Array[Zipline] = []
var breakables := {}            # id -> BreakablePillar
var alive_ring := 3             # 이 번호까지의 고리가 남아 있다 (경고가 뜬 고리는 이미 빠진다)

var _mats := {}
var _blocks := {}               # id -> 표 항목
var _rings: Array[Node3D] = []
var _ring_bodies := {}          # 고리 번호 -> [StaticBody3D]
var _ring_warn := {}            # 고리 번호 -> 경고 줄무늬 MeshInstance3D
var _cur: Node3D                # 지금 만드는 것을 붙일 곳 (고리 노드)
# 길찾기
var _astar_climb := AStar3D.new()   # 벽을 탈 수 있는 캐릭터용
var _astar_walk := AStar3D.new()    # 못 타는 캐릭터용
var _node_pos := PackedVector3Array()
var _node_area := PackedStringArray()
var _node_ring := PackedInt32Array()
var _edge_kind := {}                # "a>b" -> "walk" / "jump" / "climb" / "drop" / "lift" / "zip"
var _edge_ref := {}                 # "a>b" -> 발판/짚라인 번호
var _obstacles := []                # 바닥에서 지나갈 수 없는 사각형 (Rect2)


func _ready() -> void:
	_setup_theme()
	_make_materials()
	for b in _lay.blocks:
		_blocks[b.id] = b
	for i in RINGS.size():
		var r := Node3D.new()
		r.name = "Ring%d" % i
		add_child(r)
		_rings.append(r)
		_ring_bodies[i] = []
	_build_floor()
	for b in _lay.blocks:
		_cur = _rings[block_ring(b)]
		_build_block(b)
	for r in _lay.ramps:
		_cur = _rings[ring_of(r.from)]
		_build_ramp(r)
	_cur = _rings[0]
	for l in _lay.lifts:
		_build_lift(l)
	for z in _lay.ziplines:
		var zl := Zipline.new()
		add_child(zl)
		zl.setup(z.id, z.a, z.b, _mats)
		ziplines.append(zl)
	for pd in _lay.pads:
		var pad := LaunchPad.new()
		var c: Vector2 = pd.c
		_rings[ring_of(Vector3(c.x, 0, c.y))].add_child(pad)
		pad.setup(pd.id, Vector3(c.x, 0, c.y), pd.to, pd.apex, _mats)
		pads.append(pad)
		# 발판은 지나가는 바닥이 아니다: AI 는 탈 때만 밟는다
		_obstacles.append(Rect2(c - Vector2.ONE * LaunchPad.RADIUS, Vector2.ONE * LaunchPad.RADIUS * 2.0))
	_build_backdrop()
	_build_sky_life()
	_build_nav()
	# 고리마다 움직이지 않는 장식을 재질별로 합친다 (웹 버전이 그릴 물체 수를 줄인다)
	for r in _rings:
		LowPoly.merge_children(r, false, _ring_warn.values())
	director = ArenaDirector.new()
	director.arena = self
	add_child(director)


func set_fighters(list: Array) -> void:
	fighters = list
	director.fighters = list
	for l in lifts:
		l.fighters = list
	for pd in pads:
		pd.fighters = list


## 경기장 종류에 맞게 색과 표를 준비한다. 표는 가운데를 축으로 90도씩 돌린다 (turn).
func _setup_theme() -> void:
	if not THEMES.has(theme):
		theme = "sky"
	var t: Dictionary = THEMES[theme]
	_pal = t.pal
	var turn: int = t.turn
	var blocks := []
	for b in BLOCKS:
		var nb: Dictionary = b.duplicate()
		nb.c = _rot2(b.c, turn)
		if turn % 2 == 1:
			nb.s = Vector2(b.s.y, b.s.x)
		blocks.append(nb)
	var ramps := []
	for r in RAMPS:
		var nr: Dictionary = r.duplicate()
		nr.from = _rot3(r.from, turn)
		nr.to = _rot3(r.to, turn)
		ramps.append(nr)
	var lifts_t := []
	for l in LIFTS:
		var nl: Dictionary = l.duplicate()
		nl.c = _rot2(l.c, turn)
		lifts_t.append(nl)
	var zips := []
	for z in ZIPLINES:
		var nz: Dictionary = z.duplicate()
		nz.a = _rot3(z.a, turn)
		nz.b = _rot3(z.b, turn)
		zips.append(nz)
	var pads_t := []
	for pd in LAUNCH_PADS:
		var np: Dictionary = pd.duplicate()
		np.c = _rot2(pd.c, turn)
		np.to = _rot3(pd.to, turn)
		pads_t.append(np)
	var safe := []
	for sp in SAFE_SPOTS:
		safe.append(_rot3(sp, turn))
	_lay = {"blocks": blocks, "ramps": ramps, "lifts": lifts_t, "ziplines": zips, "pads": pads_t,
		"safe_spots": safe, "jump_links": JUMP_LINKS, "top_links": TOP_LINKS, "turn": turn}


## 위에서 볼 때 가운데를 축으로 90도씩 돌린다 ((x, z) → (-z, x))
static func _rot2(v: Vector2, turn: int) -> Vector2:
	for i in turn:
		v = Vector2(-v.y, v.x)
	return v


static func _rot3(v: Vector3, turn: int) -> Vector3:
	var f := _rot2(Vector2(v.x, v.z), turn)
	return Vector3(f.x, v.y, f.y)


## 하늘 경기장 기준 자리 → 이 경기장의 같은 자리 (시작 자리, 허수아비 자리 등)
func place(v: Vector3) -> Vector3:
	return _rot3(v, _lay.turn)


## 하늘 경기장 기준 바라보는 방향(rotation.y) → 이 경기장
func yaw(a: float) -> float:
	return a - int(_lay.turn) * PI * 0.5


## 지금 경기장 이름 (메뉴, 점검용)
static func theme_name(t: String) -> String:
	return str(THEMES.get(t, THEMES.sky).name)


func _make_materials() -> void:
	_mats.stone = LowPoly.mat(_pal.stone, 0.9)
	_mats.stone2 = LowPoly.mat(_pal.stone2, 0.9)
	_mats.teal = LowPoly.mat(_pal.teal, 0.75)
	_mats.coral = LowPoly.mat(_pal.coral, 0.8)
	_mats.navy = LowPoly.mat(_pal.navy, 0.7)
	_mats.gold = LowPoly.mat(_pal.gold, 0.55, 0.3)   # 너무 매끈하면 작은 금장식이 화면을 돌릴 때 번쩍거린다
	_mats.sand = LowPoly.mat(_pal.sand, 0.9)
	_mats.rock = LowPoly.mat(_pal.rock, 0.95)
	_mats.rock2 = LowPoly.mat(_pal.rock.darkened(0.15), 0.95)
	_mats.window = LowPoly.mat(_pal.window, 0.25, 0.2)
	_mats.leaf = LowPoly.mat(_pal.leaf, 0.9)
	var glow := StandardMaterial3D.new()   # 안에서 빛나는 등불 (노을 정원)
	glow.albedo_color = Color(1.0, 0.80, 0.55)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.64, 0.34)
	glow.emission_energy_multiplier = 1.4
	_mats.glow = glow
	var vc := StandardMaterial3D.new()
	vc.vertex_color_use_as_albedo = true
	vc.vertex_color_is_srgb = true
	vc.roughness = 0.88
	vc.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats.vcolor = vc
	var warn := StandardMaterial3D.new()
	warn.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	warn.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warn.albedo_color = Color(1.0, 0.25, 0.15, 0.0)
	_mats.warn = warn


# ---------------- 고리 ----------------

## 위치가 속한 바닥 고리 (0 가운데 ~ 3 맨 바깥)
static func ring_of(p: Vector3) -> int:
	var d := maxf(absf(p.x), absf(p.z))
	for i in RINGS.size():
		if d <= RINGS[i] + 0.01:
			return i
	return RINGS.size() - 1


func block_ring(b: Dictionary) -> int:
	if b.has("on"):
		return block_ring(_blocks[b.on])
	return ring_of(Vector3(b.c.x, 0, b.c.y))


## 고리가 곧 무너진다: 붉게 깜빡이고, AI 는 그쪽으로 가지 않는다
func warn_ring(r: int) -> void:
	alive_ring = mini(alive_ring, r - 1)
	for i in _node_pos.size():
		if _node_ring[i] >= r:
			_astar_climb.set_point_disabled(i, true)
			_astar_walk.set_point_disabled(i, true)
	if _ring_warn.has(r):
		var m: MeshInstance3D = _ring_warn[r]
		m.visible = true
		var mat: StandardMaterial3D = m.material_override
		var tw := create_tween().set_loops(5)
		tw.tween_property(mat, "albedo_color:a", 0.55, 0.5)
		tw.tween_property(mat, "albedo_color:a", 0.15, 0.5)
	# 바닥이 흔들린다
	var ring := _rings[r]
	var shake := create_tween().set_loops(25)
	shake.tween_property(ring, "position", Vector3(randf_range(-0.03, 0.03), -0.02, randf_range(-0.03, 0.03)), 0.1)
	shake.tween_property(ring, "position", Vector3.ZERO, 0.1)


## 고리가 무너진다: 충돌이 사라지고 아래로 떨어진다
func collapse_ring(r: int) -> void:
	for body in _ring_bodies[r]:
		if is_instance_valid(body):
			(body as CollisionObject3D).collision_layer = 0
	for bp in breakables.values():
		if is_instance_valid(bp) and _rings[r].is_ancestor_of(bp):
			(bp as BreakablePillar).collision_layer = 0
	for z in ziplines:
		if z.alive and (ring_of(z.a) >= r or ring_of(z.b) >= r):
			z.remove()
	var ring := _rings[r]
	if _ring_warn.has(r):
		(_ring_warn[r] as MeshInstance3D).visible = false
	# 부서진 조각이 튄다
	for k in 10:
		var a := TAU * k / 10.0
		var d: float = (RINGS[r] + RINGS[r - 1]) * 0.5
		var p: Vector3 = Vector3(cos(a), 0, sin(a)) * d
		p.x = clampf(p.x, -RINGS[r], RINGS[r])
		p.z = clampf(p.z, -RINGS[r], RINGS[r])
		Fx.impact(self, p + Vector3.UP * 0.2, Vector3.UP, _pal.floor_a, 12)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ring, "position:y", -60.0, 3.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(ring, "rotation:x", deg_to_rad(randf_range(-4, 4)), 3.2).set_ease(Tween.EASE_IN)
	tw.tween_property(ring, "rotation:z", deg_to_rad(randf_range(-4, 4)), 3.2).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.hide)


func _ring_strips(r: int) -> Array:
	## 고리 하나를 덮는 사각형들 [가운데(x,z), 크기(x,z)]
	var d1: float = RINGS[r]
	if r == 0:
		return [[Vector2.ZERO, Vector2(d1 * 2.0, d1 * 2.0)]]
	var d0: float = RINGS[r - 1]
	var w := d1 - d0
	var m := (d0 + d1) * 0.5
	return [
		[Vector2(0, -m), Vector2(d1 * 2.0, w)],
		[Vector2(0, m), Vector2(d1 * 2.0, w)],
		[Vector2(-m, 0), Vector2(w, d0 * 2.0)],
		[Vector2(m, 0), Vector2(w, d0 * 2.0)],
	]


# ---------------- 바닥 ----------------

## 고리마다 바닥을 한 덩어리(그리기 한 번)로 만든다: 큰 타일과 줄눈.
## 고리 경계에는 산호색 띠를 둘러 '여기부터 무너진다'를 보여준다.
func _build_floor() -> void:
	var tile := 2.0
	var n := int(HALF * 2.0 / tile)
	var sts := []
	for r in RINGS.size():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.UP)
		sts.append(st)
	for ix in n:
		for iz in n:
			var x0 := -HALF + ix * tile
			var z0 := -HALF + iz * tile
			var r := ring_of(Vector3(x0 + tile * 0.5, 0, z0 + tile * 0.5))
			var st: SurfaceTool = sts[r]
			var h := (ix * 7 + iz * 13) % 5
			var c: Color = _pal.floor_a if (ix + iz) % 2 == 0 else _pal.floor_b
			c = c.darkened(h * 0.008 + r * 0.012)
			# 줄눈과 타일은 같은 높이에 겹치지 않게 나란히 깐다 (겹쳐 깔면 멀리서 깜빡인다)
			var g := 0.05
			_quad(st, Vector3(x0 + g, 0, z0 + g), Vector3(x0 + tile - g, 0, z0 + tile - g), c)
			_quad(st, Vector3(x0, 0, z0), Vector3(x0 + tile, 0, z0 + g), _pal.grout)
			_quad(st, Vector3(x0, 0, z0 + tile - g), Vector3(x0 + tile, 0, z0 + tile), _pal.grout)
			_quad(st, Vector3(x0, 0, z0 + g), Vector3(x0 + g, 0, z0 + tile - g), _pal.grout)
			_quad(st, Vector3(x0 + tile - g, 0, z0 + g), Vector3(x0 + tile, 0, z0 + tile - g), _pal.grout)
	# 고리 경계 띠 (바깥 고리에 속해서 같이 무너진다)
	for r in range(1, RINGS.size()):
		var d: float = RINGS[r - 1]
		var st: SurfaceTool = sts[r]
		var w := 0.28
		_quad(st, Vector3(-d - w, 0.012, -d - w), Vector3(d + w, 0.012, -d), _pal.coral)
		_quad(st, Vector3(-d - w, 0.012, d), Vector3(d + w, 0.012, d + w), _pal.coral)
		_quad(st, Vector3(-d - w, 0.012, -d), Vector3(-d, 0.012, d), _pal.coral)
		_quad(st, Vector3(d, 0.012, -d), Vector3(d + w, 0.012, d), _pal.coral)
	# 맨 바깥 가장자리: 금색 테두리 (벽이 없다는 표시)
	var o: float = HALF
	var edge: SurfaceTool = sts[RINGS.size() - 1]
	_quad(edge, Vector3(-o, 0.012, -o), Vector3(o, 0.012, -o + 0.35), _pal.gold)
	_quad(edge, Vector3(-o, 0.012, o - 0.35), Vector3(o, 0.012, o), _pal.gold)
	_quad(edge, Vector3(-o, 0.012, -o), Vector3(-o + 0.35, 0.012, o), _pal.gold)
	_quad(edge, Vector3(o - 0.35, 0.012, -o), Vector3(o, 0.012, o), _pal.gold)
	# 가운데 결투 원
	var core: SurfaceTool = sts[0]
	_ring_mesh(core, 0.0, 8.0, 0.012, _pal.floor_a, 48)
	_ring_mesh(core, 7.4, 8.0, 0.024, _pal.coral, 48)
	_ring_mesh(core, 6.9, 7.05, 0.024, _pal.navy, 48)
	_ring_mesh(core, 2.4, 2.7, 0.024, _pal.gold, 32)
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		var dd := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dd.z, 0, dd.x) * 0.09
		var p1 := dd * 2.9
		var p2 := dd * 6.7
		var up := Vector3.UP * 0.024
		_tri(core, p1 - side + up, p2 - side + up, p2 + side + up, _pal.teal)
		_tri(core, p1 - side + up, p2 + side + up, p1 + side + up, _pal.teal)
	_ring_mesh(core, 0.0, 1.2, 0.024, _pal.navy, 8)
	_ring_mesh(core, 0.0, 0.5, 0.036, _pal.gold, 8)

	for r in RINGS.size():
		var mi := MeshInstance3D.new()
		mi.mesh = (sts[r] as SurfaceTool).commit()
		mi.material_override = _mats.vcolor
		_rings[r].add_child(mi)
		# 충돌과 바닥 밑 바위
		for s in _ring_strips(r):
			var c: Vector2 = s[0]
			var sz: Vector2 = s[1]
			var body := _static_box_in(_rings[r], Vector3(c.x, -0.5, c.y), Vector3(sz.x, 1.0, sz.y))
			_ring_bodies[r].append(body)
			var rock := LowPoly.part(_rings[r], LowPoly.box(Vector3(sz.x - 0.1, 2.4, sz.y - 0.1), ), _mats.rock,
					Vector3(c.x, -1.22, c.y), Vector3.ZERO, 0.12, r * 10 + int(c.x + c.y))
			rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if r > 0:
			# 무너지기 전 경고 줄무늬 (평소엔 숨김)
			var wst := SurfaceTool.new()
			wst.begin(Mesh.PRIMITIVE_TRIANGLES)
			wst.set_normal(Vector3.UP)
			for s in _ring_strips(r):
				var c: Vector2 = s[0]
				var sz: Vector2 = s[1]
				_quad(wst, Vector3(c.x - sz.x * 0.5, 0.05, c.y - sz.y * 0.5), Vector3(c.x + sz.x * 0.5, 0.05, c.y + sz.y * 0.5), Color.WHITE)
			var wm := MeshInstance3D.new()
			wm.mesh = wst.commit()
			wm.material_override = (_mats.warn as Material).duplicate()
			wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wm.visible = false
			_rings[r].add_child(wm)
			_ring_warn[r] = wm
	# 가운데 밑의 큰 바위 기둥 (바깥이 다 무너진 뒤에 보인다)
	var mesa := LowPoly.part(_rings[0], LowPoly.cyl(14.5, 4.0, 22.0, 9, 3), _mats.rock2, Vector3(0, -13.4, 0), Vector3.ZERO, 0.9, 5)
	mesa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 가장자리 깃대 (충돌 없음, 장식)
	for side in 4:
		for k in range(-3, 4):
			var along := k * 7.5
			var sgn := -1.0 if side % 2 == 0 else 1.0
			var p := Vector3(along, 0, sgn * (HALF - 0.4)) if side < 2 else Vector3(sgn * (HALF - 0.4), 0, along)
			if theme == "garden":
				# 노을 정원: 깃대 대신 돌 등불
				var lamp := Node3D.new()
				lamp.position = p
				_rings[3].add_child(lamp)
				LowPoly.part(lamp, LowPoly.box(Vector3(0.5, 0.25, 0.5)), _mats.stone2, Vector3(0, 0.12, 0))
				LowPoly.part(lamp, LowPoly.box(Vector3(0.22, 1.1, 0.22)), _mats.stone, Vector3(0, 0.8, 0))
				LowPoly.part(lamp, LowPoly.box(Vector3(0.46, 0.4, 0.46)), _mats.glow, Vector3(0, 1.55, 0))
				LowPoly.part(lamp, LowPoly.prism(Vector3(0.8, 0.35, 0.8)), _mats.navy, Vector3(0, 1.93, 0))
				continue
			var color: Material = _mats.coral if (k + side) % 2 == 0 else _mats.teal
			var flag := Node3D.new()
			flag.position = p
			flag.rotation.y = 0.0 if side < 2 else PI * 0.5
			_rings[3].add_child(flag)
			LowPoly.part(flag, LowPoly.cyl(0.06, 0.07, 3.6, 6), _mats.navy, Vector3(0, 1.8, 0))
			LowPoly.part(flag, LowPoly.box(Vector3(0.9, 1.3, 0.04)), color, Vector3(0.48, 2.9, 0))
			LowPoly.part(flag, LowPoly.prism(Vector3(0.9, 0.35, 0.04)), color, Vector3(0.48, 2.08, 0), Vector3(0, 0, 180))
			LowPoly.part(flag, LowPoly.sphere(0.1, 6, 3), _mats.gold, Vector3(0, 3.65, 0))


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Color) -> void:
	var p1 := Vector3(a.x, a.y, a.z)
	var p2 := Vector3(b.x, a.y, a.z)
	var p3 := Vector3(b.x, a.y, b.z)
	var p4 := Vector3(a.x, a.y, b.z)
	_tri(st, p1, p2, p3, c)
	_tri(st, p1, p3, p4, c)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.set_color(col)
	st.add_vertex(b)
	st.set_color(col)
	st.add_vertex(c)


func _ring_mesh(st: SurfaceTool, r0: float, r1: float, y: float, col: Color, seg: int) -> void:
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var o0 := Vector3(cos(a0) * r1, y, sin(a0) * r1)
		var o1 := Vector3(cos(a1) * r1, y, sin(a1) * r1)
		var i0 := Vector3(cos(a0) * r0, y, sin(a0) * r0)
		var i1 := Vector3(cos(a1) * r0, y, sin(a1) * r0)
		_tri(st, i0, o0, o1, col)
		if r0 > 0.0:
			_tri(st, i0, o1, i1, col)


# ---------------- 구조물 ----------------

func _part(mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO, jitter := 0.0, seed_value := 0) -> MeshInstance3D:
	return LowPoly.part(_cur, mesh, m, pos, rot, jitter, seed_value)


func _build_block(b: Dictionary) -> void:
	var size := Vector3(b.s.x, b.h, b.s.y)
	var center := Vector3(b.c.x, b.base + b.h * 0.5, b.c.y)
	if b.base == 0.0:
		_obstacles.append(Rect2(b.c - b.s * 0.5, b.s))
	if b.style == "obelisk":
		var bp := BreakablePillar.new()
		_cur.add_child(bp)
		bp.setup(b.id, center, size, _mats)
		bp.arena = self
		bp.broken.connect(_on_pillar_broken)
		breakables[b.id] = bp
		return
	var body := _static_box(center, size)
	if b.get("no_climb", false):
		body.set_meta("no_climb", true)
	match b.style:
		"pillar":
			_style_pillar(center, size)
		"house":
			_style_house(center, size, b)
		"tower":
			_style_tower(center, size)
		"gallery":
			_style_gallery(center, size)
		"terrace":
			_style_terrace(center, size)
		"bridge":
			_style_bridge(center, size)
		"plinth":
			_part(LowPoly.box(size), _mats.teal, center)
			_part(LowPoly.box(Vector3(size.x + 0.08, 0.12, size.z + 0.08)), _mats.gold, center + Vector3(0, size.y * 0.5 - 0.06 + LIFT_TOP, 0))
			_part(LowPoly.box(Vector3(size.x + 0.14, 0.2, size.z + 0.14)), _mats.stone2, center + Vector3(0, -size.y * 0.5 + 0.1, 0))
		"step":
			var m: Material = [_mats.teal, _mats.navy, _mats.coral][int(b.h / 1.1 + 0.1) % 3]
			_part(LowPoly.box(size), m, center)
			_part(LowPoly.box(Vector3(size.x + 0.06, 0.12, size.z + 0.06)), _mats.stone, center + Vector3(0, size.y * 0.5 - 0.06 + LIFT_TOP, 0))
		"planter":
			_style_planter(center, size, b)
		"runwall":
			_style_runwall(center, size)


func _style_pillar(center: Vector3, size: Vector3) -> void:
	_part(LowPoly.box(size), _mats.stone, center)
	var bottom := center.y - size.y * 0.5
	var top := center.y + size.y * 0.5
	_part(LowPoly.box(Vector3(size.x + 0.2, 0.5, size.z + 0.2)), _mats.stone2, Vector3(center.x, bottom + 0.25, center.z))
	for y in [2.0, 4.0]:
		_part(LowPoly.box(Vector3(size.x + 0.06, 0.3, size.z + 0.06)), _mats.coral, Vector3(center.x, bottom + y, center.z))
	_part(LowPoly.box(Vector3(size.x + 0.16, 0.35, size.z + 0.16)), _mats.navy, Vector3(center.x, top - 0.175 + LIFT_TOP, center.z))
	_part(LowPoly.cyl(0.45, 0.5, 0.06, 8), _mats.gold, Vector3(center.x, top + 0.03 + LIFT_TOP * 2.0, center.z))
	_holds(center, size, bottom + 0.8, int(size.y) - 1)


## 구조물에서 경기장 가운데를 보는 면: {"dir": 바깥에서 가운데로 향하는 축 방향, "half": 그 면까지 거리}
static func _face_in(c: Vector2, size: Vector3) -> Dictionary:
	if absf(c.x) >= absf(c.y):
		return {"dir": Vector3(-signf(c.x), 0, 0), "half": size.x * 0.5}
	return {"dir": Vector3(0, 0, -signf(c.y)), "half": size.z * 0.5}


## x 를 따라 놓을 크기를, along_x 가 아니면 z 를 따라 놓도록 바꾼다
static func _axis(along_x: bool, v: Vector3) -> Vector3:
	return v if along_x else Vector3(v.z, v.y, v.x)


## 벽에 박힌 작은 돌 손잡이: 이 벽은 타고 오를 수 있다는 표시
func _holds(center: Vector3, size: Vector3, from_y: float, rows: int) -> void:
	for f in 4:
		var d := Vector3(cos(f * PI * 0.5), 0, sin(f * PI * 0.5))
		var along := Vector3(-d.z, 0, d.x)
		var half := size.x * 0.5 if f % 2 == 0 else size.z * 0.5
		for k in rows:
			for j in 2:
				var off := (j - 0.5) * 0.7 + (0.25 if k % 2 == 0 else -0.25)
				var p := Vector3(center.x, from_y + k * 1.0 + j * 0.45, center.z) + d * (half + 0.03) + along * off
				var hold := _part(LowPoly.box(Vector3(0.22, 0.14, 0.1)), _mats.coral if (k + j) % 3 == 0 else _mats.navy, p, Vector3.ZERO, 0.02, k * 7 + j + f * 31)
				hold.rotation.y = f * PI * 0.5 + PI * 0.5


func _style_house(center: Vector3, size: Vector3, b: Dictionary) -> void:
	_part(LowPoly.box(size), _mats.stone, center)
	var bottom := center.y - size.y * 0.5
	var top := center.y + size.y * 0.5
	_part(LowPoly.box(Vector3(size.x + 0.12, 0.6, size.z + 0.12)), _mats.stone2, Vector3(center.x, bottom + 0.3, center.z))
	_part(LowPoly.box(Vector3(size.x + 0.1, 0.35, size.z + 0.1)), _mats.teal, Vector3(center.x, top - 0.175 + LIFT_TOP, center.z))
	_part(LowPoly.box(Vector3(size.x - 1.2, 0.02, size.z - 1.2)), _mats.stone2, Vector3(center.x, top + 0.01 + LIFT_TOP * 2.0, center.z))
	# 지붕 모서리 장식 (낮아서 걸리지 않는다)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_part(LowPoly.box(Vector3(0.45, 0.25, 0.45)), _mats.gold, Vector3(center.x + sx * (size.x * 0.5 - 0.22), top + 0.12, center.z + sz * (size.z * 0.5 - 0.22)))
	# 창문과 문: 경기장 가운데를 보는 면
	var f := _face_in(b.c, size)
	var face: Vector3 = f.dir
	var x_face := face.x != 0.0     # 벽면이 x 쪽을 보나 (그러면 창은 z 를 따라 늘어선다)
	var along := Vector3.BACK if x_face else Vector3.RIGHT
	var fp: Vector3 = Vector3(center.x, 0, center.z) + face * (float(f.half) + 0.02)
	for k in [-2.6, 0.0, 2.6]:
		var wy := top - 1.2
		_part(LowPoly.box(_axis(x_face, Vector3(0.06, 0.8, 1.0))), _mats.window, fp + along * k + Vector3.UP * wy)
		_part(LowPoly.box(_axis(x_face, Vector3(0.1, 0.12, 1.3))), _mats.coral, fp + face * 0.05 + along * k + Vector3.UP * (wy + 0.5))
	_part(LowPoly.box(_axis(x_face, Vector3(0.06, 1.9, 1.3))), _mats.navy, fp - along * 1.3 + Vector3.UP * (bottom + 0.95))
	var aw := _part(LowPoly.box(_axis(x_face, Vector3(0.9, 0.08, 1.8))), _mats.coral, fp + face * 0.4 - along * 1.3 + Vector3.UP * (bottom + 2.05))
	if x_face:
		aw.rotation.z = face.x * deg_to_rad(-15)
	else:
		aw.rotation.x = face.z * deg_to_rad(15)
	# 바깥쪽 벽에도 손잡이 (벽 타기로 오를 수 있다)
	_holds(center, size, bottom + 0.6, int(size.y) - 1)


func _style_tower(center: Vector3, size: Vector3) -> void:
	_part(LowPoly.box(size), _mats.stone2, center)
	var top := center.y + size.y * 0.5
	_part(LowPoly.box(Vector3(size.x + 0.1, 0.3, size.z + 0.1)), _mats.coral, Vector3(center.x, top - 0.15 + LIFT_TOP, center.z))
	_part(LowPoly.cyl(0.5, 0.55, 0.06, 8), _mats.gold, Vector3(center.x, top + 0.03 + LIFT_TOP * 2.0, center.z))
	_holds(center, size, center.y - size.y * 0.5 + 0.4, 3)


func _style_gallery(center: Vector3, size: Vector3) -> void:
	_part(LowPoly.box(size), _mats.stone, center)
	var top := center.y + size.y * 0.5
	_part(LowPoly.box(Vector3(size.x + 0.08, 0.3, size.z + 0.08)), _mats.navy, Vector3(center.x, top - 0.15 + LIFT_TOP, center.z))
	# 경기장 가운데를 보는 면에 아치 문
	var f := _face_in(Vector2(center.x, center.z), size)
	var face: Vector3 = f.dir
	var x_face := face.x != 0.0
	var along := Vector3.BACK if x_face else Vector3.RIGHT
	var fp: Vector3 = Vector3(center.x, 0, center.z) + face * (float(f.half) + 0.02)
	for k in range(-2, 3):
		var p := fp + along * (k * 2.4)
		_part(LowPoly.box(_axis(not x_face, Vector3(1.3, 1.3, 0.05))), _mats.teal, p + Vector3.UP * 0.9)
		_part(LowPoly.cyl(0.65, 0.65, 0.05, 8), _mats.teal, p + Vector3.UP * 1.55, Vector3(0, 0, 90) if x_face else Vector3(90, 0, 0))
	_holds(center, Vector3(size.x, size.y, size.z), 0.6, 2)


func _style_terrace(center: Vector3, size: Vector3) -> void:
	_part(LowPoly.box(size), _mats.stone, center)
	var top := center.y + size.y * 0.5
	_part(LowPoly.box(Vector3(size.x + 0.1, 0.3, size.z + 0.1)), _mats.coral, Vector3(center.x, top - 0.15 + LIFT_TOP, center.z))
	_part(LowPoly.box(Vector3(size.x - 1.0, 0.02, size.z - 1.0)), _mats.sand, Vector3(center.x, top + 0.01 + LIFT_TOP * 2.0, center.z))
	var f := _face_in(Vector2(center.x, center.z), size)
	var face: Vector3 = f.dir
	var x_face := face.x != 0.0
	var along := Vector3.BACK if x_face else Vector3.RIGHT
	var fp: Vector3 = Vector3(center.x, 0, center.z) + face * (float(f.half) + 0.02)
	for k in range(-1, 2):
		_part(LowPoly.box(_axis(not x_face, Vector3(1.6, 1.0, 0.05))), _mats.navy, fp + along * (k * 3.0) + Vector3.UP * 1.0)


func _style_bridge(center: Vector3, size: Vector3) -> void:
	_part(LowPoly.box(size), _mats.stone, center)
	var top := center.y + size.y * 0.5
	var bottom := center.y - size.y * 0.5
	var lx := size.x >= size.z      # 다리가 x 를 따라 길다
	var long_ax := Vector3.RIGHT if lx else Vector3.BACK
	var short_ax := Vector3.BACK if lx else Vector3.RIGHT
	var long_len := size.x if lx else size.z
	var short_len := size.z if lx else size.x
	var c0 := Vector3(center.x, 0, center.z)
	# 가장자리 산호색 띠: 난간이 없다는 표시
	for s in [-1.0, 1.0]:
		_part(LowPoly.box(_axis(lx, Vector3(long_len, 0.06, 0.16))), _mats.coral, c0 + short_ax * s * (short_len * 0.5 - 0.08) + Vector3.UP * (top + 0.02))
	# 밑을 받치는 들보와 아래로 드리운 천 (밑에서 올려다볼 때 보기 좋게)
	for k in range(-2, 3):
		_part(LowPoly.box(_axis(lx, Vector3(0.3, 0.3, short_len + 0.1))), _mats.navy, c0 + long_ax * (k * 2.4) + Vector3.UP * (bottom - 0.15))
	for k in [-1, 1]:
		var m: Material = _mats.teal if k < 0 else _mats.coral
		var banner := _part(LowPoly.box(_axis(lx, Vector3(1.2, 1.6, 0.04))), m, c0 + long_ax * (k * 2.4) + Vector3.UP * (bottom - 0.9))
		banner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_part(LowPoly.prism(Vector3(1.2, 0.4, 0.04)), m, c0 + long_ax * (k * 2.4) + Vector3.UP * (bottom - 1.9), Vector3(0, 0 if lx else 90, 180))


func _style_runwall(center: Vector3, size: Vector3) -> void:
	_part(LowPoly.box(size), _mats.coral, center)
	var top := center.y + size.y * 0.5
	_part(LowPoly.box(Vector3(size.x + 0.08, 0.25, size.z + 0.08)), _mats.navy, Vector3(center.x, top - 0.125 + LIFT_TOP, center.z))
	var thin_x := size.x <= size.z   # 벽이 x 쪽으로 얇다 (z 를 따라 길다)
	var n_ax := Vector3.RIGHT if thin_x else Vector3.BACK
	var l_ax := Vector3.BACK if thin_x else Vector3.RIGHT
	var half_n := (size.x if thin_x else size.z) * 0.5
	for side in [-1.0, 1.0]:
		for k in range(-2, 3):
			var p: Vector3 = Vector3(center.x, 1.9, center.z) + n_ax * side * (half_n + 0.02) + l_ax * (k * 1.1)
			var chev := _part(LowPoly.prism(Vector3(0.7, 0.5, 0.04)), _mats.stone, p)
			chev.rotation = Vector3(0, PI * 0.5, PI * 0.5) if thin_x else Vector3(0, 0, PI * 0.5)


## 화분: 돌 화분에 네모나게 다듬은 덤불. 밟고 올라설 수 있는 낮은 엄폐물.
func _style_planter(center: Vector3, size: Vector3, b: Dictionary) -> void:
	var bottom := center.y - size.y * 0.5
	var pot_h := size.y - 0.4
	_part(LowPoly.box(Vector3(size.x, pot_h, size.z)), _mats.stone2, Vector3(center.x, bottom + pot_h * 0.5, center.z))
	_part(LowPoly.box(Vector3(size.x + 0.1, 0.14, size.z + 0.1)), _mats.coral, Vector3(center.x, bottom + pot_h - 0.05, center.z))
	var seed_v := int(absf(b.c.x * 7.0 + b.c.y * 13.0))
	_part(LowPoly.box(Vector3(size.x - 0.16, 0.48, size.z - 0.16)), _mats.leaf, Vector3(center.x, bottom + pot_h + 0.2, center.z), Vector3.ZERO, 0.05, seed_v)
	# 덤불 위 작은 꽃 몇 송이
	for k in 3:
		var a := TAU * k / 3.0 + seed_v
		var p := Vector3(center.x + cos(a) * size.x * 0.25, bottom + size.y + 0.04, center.z + sin(a) * size.z * 0.25)
		_part(LowPoly.sphere(0.12, 5, 3), _mats.gold if k == 0 else _mats.coral, p)


func _build_lift(l: Dictionary) -> void:
	var lift := ArenaLift.new()
	var c: Vector2 = l.c
	# 자리를 먼저 정하고 넣는다 (넣은 뒤에 옮기면 물리 쪽 위치가 원점에 남는다)
	lift.setup(Vector3(c.x, 0, c.y), l.top, _mats, l.start)
	_rings[0].add_child(lift)
	lifts.append(lift)
	_obstacles.append(Rect2(c - Vector2.ONE * ArenaLift.SIZE * 0.5, Vector2.ONE * ArenaLift.SIZE))
	# 발판이 오가는 길을 보여주는 기둥 (장식, 충돌 없음)
	var h: float = l.top + 1.0
	var along_x := absf(c.y) >= absf(c.x)   # 기둥은 다리와 나란히 선다
	var ax := Vector3.RIGHT if along_x else Vector3.BACK
	for sx in [-1.0, 1.0]:
		var p: Vector3 = Vector3(c.x, h * 0.5, c.y) + ax * sx * (ArenaLift.SIZE * 0.5 + 0.25)
		_part(LowPoly.box(Vector3(0.18, h, 0.18)), _mats.navy, p)
		for y in range(1, int(h), 2):
			_part(LowPoly.box(Vector3(0.24, 0.12, 0.24)), _mats.gold, Vector3(p.x, y, p.z))
	_part(LowPoly.box(_axis(along_x, Vector3(ArenaLift.SIZE + 0.7, 0.16, 0.2))), _mats.coral, Vector3(c.x, h, c.y))


func _on_pillar_broken(pid: String) -> void:
	for i in _node_pos.size():
		if _node_area[i] == pid:
			_astar_climb.set_point_disabled(i, true)
			_astar_walk.set_point_disabled(i, true)
	# 기둥이 서 있던 바닥은 다시 지나갈 수 있다
	var b: Dictionary = _blocks[pid]
	var rect := Rect2(b.c - b.s * 0.5, b.s)
	_obstacles.erase(rect)


func _build_ramp(r: Dictionary) -> void:
	var from: Vector3 = r.from
	var to: Vector3 = r.to
	var w: float = r.w
	var flat := Vector3(to.x - from.x, 0, to.z - from.z)
	var run := flat.length()
	var dir := flat / run
	var rise := to.y - from.y
	var side := Vector3(-dir.z, 0, dir.x)
	var basis := Basis(side, Vector3.UP, -dir)   # 로컬 -z 가 올라가는 방향
	var steps := int(ceil(rise / 0.25)) if r.stairs else 1
	var d := run / steps
	var h := rise / steps
	if r.stairs:
		for i in steps:
			var top_y := from.y + (i + 1) * h
			var mid := from + dir * (d * (i + 0.5))
			var m: Material = _mats.stone if i % 2 == 0 else _mats.stone2
			if i == steps - 1:
				m = _mats.teal
			var step := _part(LowPoly.box(Vector3(w, top_y - from.y, d + 0.01)), m, Vector3(mid.x, (from.y + top_y) * 0.5, mid.z))
			step.basis = basis
		var mid_all := from + dir * run * 0.5
		for s in [-1.0, 1.0]:
			var sw := MeshInstance3D.new()
			sw.mesh = _ramp_side_mesh(run, rise)
			sw.material_override = _mats.stone2
			sw.basis = basis
			sw.position = Vector3(mid_all.x, from.y, mid_all.z) + side * s * (w * 0.5 + 0.03)
			_cur.add_child(sw)
		# 걷는 경사는 맨 위 칸이 시작되는 곳에서 꼭대기 높이에 닿는다 (턱이 생기지 않게)
		var start := from - dir * d * 0.5
		var stop := from + dir * (run - d) + Vector3.UP * rise
		_slope(start, stop, w, side)
		var last := from + dir * (run - d * 0.5)
		var lb := _static_box(Vector3(last.x, to.y - 0.15, last.z), Vector3(w, 0.3, d))
		lb.basis = basis
	else:
		var start := from
		var stop := Vector3(to.x, to.y, to.z)
		var mid := (start + stop) * 0.5
		var length := start.distance_to(stop)
		var ang := atan2(rise, run)
		var slab := _part(LowPoly.box(Vector3(w, 0.3, length)), _mats.stone2, mid - Vector3.UP * 0.15)
		slab.basis = basis * Basis(Vector3.RIGHT, ang)
		var sw := MeshInstance3D.new()
		sw.mesh = _ramp_side_mesh(run, rise, w)
		sw.material_override = _mats.stone
		sw.basis = basis
		sw.position = Vector3((from.x + to.x) * 0.5, from.y, (from.z + to.z) * 0.5)
		_cur.add_child(sw)
		for s in [-1.0, 1.0]:
			var edge := _part(LowPoly.box(Vector3(0.12, 0.12, length)), _mats.teal, mid + side * s * (w * 0.5 - 0.06) + Vector3.UP * 0.05)
			edge.basis = slab.basis
		_slope(start, stop, w, side)
	var corners := [from + side * w * 0.5, from - side * w * 0.5, to + side * w * 0.5, to - side * w * 0.5]
	var rect := Rect2(Vector2(corners[0].x, corners[0].z), Vector2.ZERO)
	for c in corners:
		rect = rect.expand(Vector2(c.x, c.z))
	_obstacles.append(rect)


## 경사로 옆면 (직각삼각형). 두께 w 를 주면 속이 찬 삼각 기둥.
func _ramp_side_mesh(run: float, rise: float, w: float = 0.05) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := w * 0.5
	var a := Vector3(0, 0, run * 0.5)
	var b := Vector3(0, 0, -run * 0.5)
	var c := Vector3(0, rise, -run * 0.5)
	for s in [-1.0, 1.0]:
		var o := Vector3(s * hw, 0, 0)
		st.add_vertex(a + o)
		st.add_vertex(b + o)
		st.add_vertex(c + o)
	if w > 0.1:
		var l := Vector3(-hw, 0, 0)
		var r := Vector3(hw, 0, 0)
		for q in [[b, c], [c, a], [a, b]]:
			st.add_vertex(q[0] + l)
			st.add_vertex(q[0] + r)
			st.add_vertex(q[1] + r)
			st.add_vertex(q[0] + l)
			st.add_vertex(q[1] + r)
			st.add_vertex(q[1] + l)
	st.generate_normals()
	return st.commit()


func _slope(start: Vector3, stop: Vector3, w: float, side: Vector3) -> void:
	var mid := (start + stop) * 0.5
	var along := (stop - start)
	var length := along.length()
	var fwd := along / length
	var up := fwd.cross(side).normalized()
	if up.y < 0:
		up = -up
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, 0.4, length)
	col.shape = shape
	body.add_child(col)
	body.basis = Basis(side, up, -fwd).orthonormalized()
	body.position = mid - up * 0.2
	body.set_meta("no_climb", true)
	_cur.add_child(body)
	_register_body(body)


func _static_box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := _static_box_in(_cur, pos, size)
	_register_body(body)
	return body


func _static_box_in(parent: Node3D, pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.position = pos
	body.add_child(col)
	parent.add_child(body)
	return body


func _register_body(body: StaticBody3D) -> void:
	var idx := _rings.find(_cur)
	if idx >= 0:
		_ring_bodies[idx].append(body)


# ---------------- 바깥 풍경 (아래로 멀리 보이는 골짜기) ----------------

const VALLEY_Y := -34.0


func _build_backdrop() -> void:
	if theme == "garden":
		_build_lake()
		return
	var grass := LowPoly.mat(Color(0.52, 0.68, 0.40), 0.95)
	var grass2 := LowPoly.mat(Color(0.58, 0.72, 0.44), 0.95)
	var bark := LowPoly.mat(Color(0.45, 0.33, 0.24), 0.95)
	var leaf := LowPoly.mat(Color(0.35, 0.58, 0.36), 0.9)
	var leaf2 := LowPoly.mat(Color(0.95, 0.66, 0.55), 0.9)
	var water := LowPoly.mat(Color(0.35, 0.62, 0.72), 0.2, 0.1)
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(320, 320)
	ground_mesh.subdivide_width = 40
	ground_mesh.subdivide_depth = 40
	var ground := LowPoly.part(self, ground_mesh, grass, Vector3.ZERO)
	ground.mesh = _bumpy_ground(ground_mesh)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 골짜기 바닥의 강
	var river := LowPoly.part(self, LowPoly.box(Vector3(18, 0.1, 320)), water, Vector3(-6, VALLEY_Y + 0.4, 0), Vector3(0, 20, 0))
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# 둘레의 다른 바위 기둥들 (우리 경기장이 하늘 높이 떠 있다는 느낌)
	for i in 7:
		var a := TAU * i / 7.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(52.0, 75.0)
		var h := rng.randf_range(22.0, 40.0)
		var p := Vector3(cos(a) * r, VALLEY_Y + h * 0.5, sin(a) * r)
		var col := LowPoly.part(self, LowPoly.cyl(rng.randf_range(4.0, 7.0), rng.randf_range(6.0, 9.0), h, 7, 2), _mats.rock, p, Vector3.ZERO, 0.6, i)
		col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		LowPoly.part(self, LowPoly.cyl(rng.randf_range(4.2, 7.2), rng.randf_range(4.0, 7.0), 1.2, 7), grass2, p + Vector3.UP * (h * 0.5 + 0.4), Vector3.ZERO, 0.3, i + 50)
	for i in 46:
		var a := rng.randf() * TAU
		var r := rng.randf_range(34.0, 120.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = _hill_height(p.x, p.z) - 0.2
		var tree := Node3D.new()
		tree.position = p
		tree.rotation.y = rng.randf() * TAU
		tree.scale = Vector3.ONE * rng.randf_range(1.6, 2.8)
		add_child(tree)
		LowPoly.part(tree, LowPoly.cyl(0.16, 0.24, 2.0, 6), bark, Vector3(0, 1.0, 0), Vector3.ZERO, 0.03, i)
		var lm: Material = leaf2 if i % 4 == 0 else leaf
		LowPoly.part(tree, LowPoly.sphere(1.3, 7, 5), lm, Vector3(0, 2.8, 0), Vector3.ZERO, 0.22, i + 100)
		LowPoly.part(tree, LowPoly.sphere(0.9, 6, 4), grass2 if i % 3 == 0 else lm, Vector3(0.6, 3.4, 0.3), Vector3.ZERO, 0.15, i + 200)


## 하늘 풍경: 경기장 둘레를 천천히 도는 열기구와 둥실 떠 있는 바위섬.
## 싸우다 고개를 들거나 높이 날아오를 때 '하늘 위 경기장'이라는 느낌이 나게 한다. 충돌은 없다.
func _build_sky_life() -> void:
	if theme == "garden":
		_build_lanterns()
		return
	var bark := LowPoly.mat(Color(0.45, 0.33, 0.24), 0.95)
	var grass := LowPoly.mat(Color(0.56, 0.72, 0.42), 0.95)
	var cream := LowPoly.mat(Color(0.96, 0.92, 0.84), 0.85)
	var balloons := [
		[_mats.coral, _mats.gold, 38.0, 14.0, 0.0, 0.035],
		[_mats.teal, cream, 46.0, 20.0, 2.2, -0.028],
		[_mats.navy, _mats.coral, 42.0, 8.0, 4.1, 0.03],
	]
	for i in balloons.size():
		var bd: Array = balloons[i]
		var orbit := Node3D.new()
		orbit.rotation.y = bd[4]
		add_child(orbit)
		var b := Node3D.new()
		b.position = Vector3(bd[2], bd[3], 0)
		orbit.add_child(b)
		var env := LowPoly.part(b, LowPoly.sphere(3.0, 10, 7), bd[0], Vector3(0, 4.2, 0), Vector3.ZERO, 0.08, i)
		env.scale = Vector3(1, 1.18, 1)
		# 가운데 띠와 꼭대기 덮개 (다른 색)
		LowPoly.part(b, LowPoly.cyl(3.2, 3.2, 1.0, 10), bd[1], Vector3(0, 4.4, 0))
		LowPoly.part(b, LowPoly.cyl(1.2, 2.2, 0.9, 10), bd[1], Vector3(0, 7.55, 0))
		LowPoly.part(b, LowPoly.cyl(1.0, 0.7, 0.9, 8), bd[1], Vector3(0, 0.8, 0))
		LowPoly.part(b, LowPoly.box(Vector3(1.3, 0.9, 1.3)), bark, Vector3(0, -1.6, 0), Vector3.ZERO, 0.04, i + 9)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				LowPoly.part(b, LowPoly.box(Vector3(0.05, 2.3, 0.05)), bark, Vector3(sx * 0.6, -0.15, sz * 0.6))
		LowPoly.merge_children(b, false)
		# 천천히 경기장 둘레를 돌며 위아래로 흔들린다
		var spin := create_tween().set_loops()
		spin.tween_property(orbit, "rotation:y", orbit.rotation.y + TAU * signf(bd[5]), absf(TAU / bd[5]))
		spin.tween_callback(func(): orbit.rotation.y -= TAU * signf(bd[5]))
		var bob := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		bob.tween_property(b, "position:y", bd[3] + 1.6, 5.0 + i)
		bob.tween_property(b, "position:y", bd[3], 5.0 + i)
	# 떠 있는 바위섬: 거꾸로 선 바위 + 풀 덮인 윗면 + 작은 나무
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in 5:
		var a := TAU * i / 5.0 + 0.4
		var r := rng.randf_range(36.0, 48.0)
		var isl := Node3D.new()
		isl.position = Vector3(cos(a) * r, rng.randf_range(-6.0, 6.0), sin(a) * r)
		isl.rotation.y = rng.randf() * TAU
		add_child(isl)
		var w := rng.randf_range(3.0, 5.5)
		LowPoly.part(isl, LowPoly.cyl(w, 0.4, w * 1.6, 7, 2), _mats.rock, Vector3(0, -w * 0.8, 0), Vector3.ZERO, 0.35, i + 30)
		LowPoly.part(isl, LowPoly.cyl(w + 0.15, w, 0.5, 7), grass, Vector3(0, 0.2, 0), Vector3.ZERO, 0.12, i + 40)
		LowPoly.part(isl, LowPoly.cyl(0.18, 0.25, 1.8, 6), bark, Vector3(w * 0.3, 1.3, 0))
		LowPoly.part(isl, LowPoly.sphere(1.2, 7, 5), _mats.leaf, Vector3(w * 0.3, 2.7, 0), Vector3.ZERO, 0.2, i + 50)
		LowPoly.merge_children(isl, false)
		var bob := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		bob.tween_property(isl, "position:y", isl.position.y + 1.2, 4.0 + i * 0.7)
		bob.tween_property(isl, "position:y", isl.position.y, 4.0 + i * 0.7)


# ---------------- 노을 정원 풍경 ----------------

const LAKE_Y := -16.0


## 꽃나무 한 그루 (줄기 + 분홍 꽃 덩어리 셋). parent 에 붙이고 합치는 건 부르는 쪽이 한다.
func _blossom_tree(parent: Node3D, p: Vector3, sc: float, seed_v: int, bark: Material, petals: Array) -> void:
	var t := Node3D.new()
	t.position = p
	t.rotation.y = seed_v * 0.7
	t.scale = Vector3.ONE * sc
	parent.add_child(t)
	LowPoly.part(t, LowPoly.cyl(0.14, 0.24, 2.2, 6), bark, Vector3(0, 1.1, 0), Vector3(0, 0, 6), 0.03, seed_v)
	LowPoly.part(t, LowPoly.sphere(1.25, 7, 5), petals[seed_v % petals.size()], Vector3(0, 2.7, 0), Vector3.ZERO, 0.22, seed_v + 100)
	LowPoly.part(t, LowPoly.sphere(0.85, 6, 4), petals[(seed_v + 1) % petals.size()], Vector3(0.7, 3.1, 0.2), Vector3.ZERO, 0.18, seed_v + 200)
	LowPoly.part(t, LowPoly.sphere(0.7, 6, 4), petals[(seed_v + 2) % petals.size()], Vector3(-0.6, 3.2, -0.3), Vector3.ZERO, 0.18, seed_v + 300)


## 노을 정원: 해 질 녘 잔잔한 호수 한가운데 솟은 절벽 위 정원.
## 둘레에는 꽃나무가 핀 작은 섬들과 바위 기둥, 멀리 보랏빛 산이 겹겹이 있다. 충돌 없음.
func _build_lake() -> void:
	var water := LowPoly.mat(Color(0.56, 0.66, 0.86), 0.08, 0.15)   # 하늘빛이 비친 물
	var water_deep := LowPoly.mat(Color(0.38, 0.46, 0.72), 0.12, 0.1)
	var bark := LowPoly.mat(Color(0.40, 0.28, 0.26), 0.95)
	var moss := LowPoly.mat(Color(0.55, 0.66, 0.48), 0.95)
	var petals := [LowPoly.mat(Color(0.98, 0.70, 0.78), 0.9), LowPoly.mat(Color(1.0, 0.86, 0.88), 0.9), LowPoly.mat(Color(0.93, 0.55, 0.66), 0.9)]
	var far := [LowPoly.mat(Color(0.50, 0.50, 0.72), 0.95), LowPoly.mat(Color(0.60, 0.58, 0.78), 0.95), LowPoly.mat(Color(0.43, 0.43, 0.66), 0.95)]
	var lake := LowPoly.part(self, LowPoly.cyl(300, 300, 0.2, 24), water, Vector3(0, LAKE_Y, 0))
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 경기장 절벽 둘레의 짙은 물 (물이 깊어 보이게)
	var deep := LowPoly.part(self, LowPoly.cyl(30, 30, 0.2, 16), water_deep, Vector3(0, LAKE_Y + 0.03, 0))
	deep.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var scenery := Node3D.new()
	add_child(scenery)
	# 멀리 겹겹이 선 산 (가까울수록 진하게)
	for i in 22:
		var a := TAU * i / 22.0 + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(140.0, 190.0)
		var h := rng.randf_range(28.0, 62.0)
		var m: Material = far[i % far.size()]
		LowPoly.part(scenery, LowPoly.cyl(rng.randf_range(2.0, 6.0), rng.randf_range(26.0, 40.0), h, 6, 2), m,
				Vector3(cos(a) * r, LAKE_Y + h * 0.5 - 1.0, sin(a) * r), Vector3.ZERO, 1.2, i)
	# 바위 기둥 몇 개 (꼭대기에 꽃나무)
	for i in 6:
		var a := TAU * i / 6.0 + 0.5 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(48.0, 70.0)
		var h := rng.randf_range(16.0, 26.0)
		var p := Vector3(cos(a) * r, LAKE_Y + h * 0.5, sin(a) * r)
		LowPoly.part(scenery, LowPoly.cyl(rng.randf_range(3.0, 5.0), rng.randf_range(5.0, 7.0), h, 7, 2), _mats.rock, p, Vector3.ZERO, 0.6, i + 20)
		LowPoly.part(scenery, LowPoly.cyl(rng.randf_range(3.2, 5.2), rng.randf_range(3.0, 5.0), 1.0, 7), moss, p + Vector3.UP * (h * 0.5 + 0.3), Vector3.ZERO, 0.3, i + 60)
		_blossom_tree(scenery, p + Vector3.UP * (h * 0.5 + 0.7), rng.randf_range(1.6, 2.2), i, bark, petals)
	# 물 위의 작은 섬: 풀 덮인 돌 + 꽃나무 한두 그루
	for i in 14:
		var a := rng.randf() * TAU
		var r := rng.randf_range(36.0, 110.0)
		var p := Vector3(cos(a) * r, LAKE_Y, sin(a) * r)
		var w := rng.randf_range(2.5, 6.0)
		LowPoly.part(scenery, LowPoly.cyl(w * 0.8, w, 1.4, 7), _mats.rock, p + Vector3.UP * 0.3, Vector3.ZERO, 0.3, i + 80)
		LowPoly.part(scenery, LowPoly.cyl(w * 0.75, w * 0.85, 0.4, 7), moss, p + Vector3.UP * 1.1, Vector3.ZERO, 0.15, i + 120)
		for k in (1 if w < 4.0 else 2):
			_blossom_tree(scenery, p + Vector3(k * w * 0.4, 1.3, -k * w * 0.2), rng.randf_range(1.2, 1.9), i * 3 + k, bark, petals)
	LowPoly.merge_children(scenery, true)


## 노을 정원 하늘: 둥실 떠오르는 종이 등불 (안에서 빛난다), 꽃나무 바위섬 셋. 충돌 없음.
func _build_lanterns() -> void:
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.78, 0.52)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.62, 0.32)
	glow.emission_energy_multiplier = 1.6
	glow.roughness = 0.7
	var cap := LowPoly.mat(_pal.navy, 0.8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for i in 16:
		var a := TAU * i / 16.0 + rng.randf_range(-0.15, 0.15)
		var r := rng.randf_range(32.0, 54.0)
		var l := Node3D.new()
		l.position = Vector3(cos(a) * r, rng.randf_range(-4.0, 14.0), sin(a) * r)
		add_child(l)
		var sc := rng.randf_range(0.9, 1.5)
		var body := LowPoly.part(l, LowPoly.cyl(0.55 * sc, 0.45 * sc, 1.1 * sc, 8), glow, Vector3.ZERO)
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		LowPoly.part(l, LowPoly.cyl(0.35 * sc, 0.58 * sc, 0.12 * sc, 8), cap, Vector3(0, 0.6 * sc, 0))
		LowPoly.part(l, LowPoly.cyl(0.5 * sc, 0.4 * sc, 0.1 * sc, 8), cap, Vector3(0, -0.58 * sc, 0))
		LowPoly.merge_children(l, false)
		# 천천히 떠오르고 가라앉는다
		var bob := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		bob.tween_property(l, "position:y", l.position.y + rng.randf_range(1.5, 3.0), rng.randf_range(4.0, 7.0))
		bob.tween_property(l, "position:y", l.position.y, rng.randf_range(4.0, 7.0))
	var bark := LowPoly.mat(Color(0.40, 0.28, 0.26), 0.95)
	var moss := LowPoly.mat(Color(0.58, 0.70, 0.50), 0.95)
	var petals := [LowPoly.mat(Color(0.98, 0.70, 0.78), 0.9), LowPoly.mat(Color(1.0, 0.86, 0.88), 0.9)]
	for i in 3:
		var a := TAU * i / 3.0 + 1.1
		var isl := Node3D.new()
		isl.position = Vector3(cos(a) * 40.0, 4.0 + i * 3.0, sin(a) * 40.0)
		add_child(isl)
		var w := 3.5 + i
		LowPoly.part(isl, LowPoly.cyl(w, 0.4, w * 1.6, 7, 2), _mats.rock, Vector3(0, -w * 0.8, 0), Vector3.ZERO, 0.35, i + 30)
		LowPoly.part(isl, LowPoly.cyl(w + 0.15, w, 0.5, 7), moss, Vector3(0, 0.2, 0), Vector3.ZERO, 0.12, i + 40)
		_blossom_tree(isl, Vector3(w * 0.25, 0.4, 0), 1.3, i, bark, petals)
		LowPoly.merge_children(isl, true)
		var bob := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		bob.tween_property(isl, "position:y", isl.position.y + 1.2, 4.0 + i * 0.7)
		bob.tween_property(isl, "position:y", isl.position.y, 4.0 + i * 0.7)


func _hill_height(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var hill := clampf((d - 40.0) / 80.0, 0.0, 1.0)
	return VALLEY_Y + (sin(x * 0.07) * cos(z * 0.06) * 3.0 + sin(x * 0.03 + z * 0.025) * 5.0) * (0.3 + hill) + hill * hill * 26.0


func _bumpy_ground(src: PlaneMesh) -> ArrayMesh:
	var arrays := src.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		v.y = _hill_height(v.x, v.z)
		verts[i] = v
	arrays[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return LowPoly.flat(am)


# ---------------- 아이템 자리, 다시 서는 자리 ----------------

## 지금 아이템이 생길 수 있는 높은 자리들: [{"id", "pos", "ring", "name"}]
func pickup_spots() -> Array:
	var out := []
	for b in _lay.blocks:
		if not b.has("pickup"):
			continue
		var ring := block_ring(b)
		if ring > alive_ring:
			continue
		if breakables.has(b.id) and (breakables[b.id] as BreakablePillar).is_broken():
			continue
		var pos := Vector3(b.c.x, b.base + b.h, b.c.y)
		if b.id == "west_house":
			pos += _rot3(Vector3(0, 0, -2.5), _lay.turn)
		out.append({"id": b.id, "pos": pos, "ring": ring, "name": b.pickup})
	return out


## 낭떠러지에 떨어진 몸이 다시 설 자리: 다른 사람에게서 가장 먼 곳
func safe_spawn(me: Node3D) -> Vector3:
	var best := _lay.safe_spots[0] as Vector3
	var best_d := -1.0
	for s in _lay.safe_spots:
		var d := 99.0
		for f in fighters:
			if is_instance_valid(f) and f != me:
				d = minf(d, (f as Node3D).global_position.distance_to(s))
		if d > best_d:
			best_d = d
			best = s
	return best


## 이 위치가 곧 무너지거나 이미 무너진 바닥인가
func is_doomed(p: Vector3) -> bool:
	return ring_of(p) > alive_ring


## 짚라인: 발 위치에서 손이 닿는 줄이 있으면 [줄, 위치], 없으면 []
func zipline_near(feet: Vector3) -> Array:
	for z in ziplines:
		# 무너져 사라진 줄은 건너뛴다 (사라진 뒤에 부르면 게임이 멈출 수 있다)
		if not is_instance_valid(z):
			continue
		var t := z.grab_t(feet)
		if t >= 0.0:
			return [z, t]
	return []


# ---------------- 길찾기 ----------------

func _add_node(p: Vector3, area: String, ring: int = -1) -> int:
	var id := _node_pos.size()
	_node_pos.append(p)
	_node_area.append(area)
	if ring < 0:
		ring = ring_of(p) if area == "ground" else block_ring(_blocks[area]) if _blocks.has(area) else ring_of(p)
	_node_ring.append(ring)
	_astar_climb.add_point(id, p)
	_astar_walk.add_point(id, p)
	return id


func _link(a: int, b: int, kind: String, both_ways: bool = true, ref: int = -1) -> void:
	if kind != "climb":
		_astar_walk.connect_points(a, b, false)
	_astar_climb.connect_points(a, b, false)
	_edge_kind["%d>%d" % [a, b]] = kind
	if ref >= 0:
		_edge_ref["%d>%d" % [a, b]] = ref
	if both_ways:
		var back := kind
		if kind == "climb" or kind == "jump":
			back = "drop"
		_astar_walk.connect_points(b, a, false)
		_astar_climb.connect_points(b, a, false)
		_edge_kind["%d>%d" % [b, a]] = back
		if ref >= 0:
			_edge_ref["%d>%d" % [b, a]] = ref


func _blocked(p: Vector2, margin: float) -> bool:
	if absf(p.x) > HALF - margin or absf(p.y) > HALF - margin:
		return true
	for r in _obstacles:
		if (r as Rect2).grow(margin).has_point(p):
			return true
	return false


func _top_y(b: Dictionary) -> float:
	return b.base + b.h


func _build_nav() -> void:
	# 1) 바닥 격자
	var n := int(ceil(HALF * 2.0 / GRID))
	var grid := {}
	for ix in n:
		for iz in n:
			# 돌려 놓은 경기장은 격자도 같이 돌린다 (하늘 경기장과 똑같은 길목이 되게)
			var p := _rot2(Vector2(-HALF + GRID * (ix + 0.5), -HALF + GRID * (iz + 0.5)), _lay.turn)
			if _blocked(p, 0.9):
				continue
			grid[Vector2i(ix, iz)] = _add_node(Vector3(p.x, 0, p.y), "ground")
	for key in grid:
		for off in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
			var other: Vector2i = key + off
			if not grid.has(other):
				continue
			var a: Vector3 = _node_pos[grid[key]]
			var b: Vector3 = _node_pos[grid[other]]
			var clear := true
			for t in [0.25, 0.5, 0.75]:
				var q := Vector2(lerpf(a.x, b.x, t), lerpf(a.z, b.z, t))
				if _blocked(q, 0.5):
					clear = false
			if clear:
				_link(grid[key], grid[other], "walk")

	# 2) 구조물 위
	var tops := {}
	for b in _lay.blocks:
		if b.style == "runwall":
			continue
		var ids := []
		var cnt := Vector2i(maxi(1, int(b.s.x / 2.2)), maxi(1, int(b.s.y / 2.2)))
		for ix in cnt.x:
			for iz in cnt.y:
				var lx: float = b.c.x + (ix + 0.5 - cnt.x * 0.5) * (b.s.x - 1.2) / maxf(cnt.x, 1) if cnt.x > 1 else b.c.x
				var lz: float = b.c.y + (iz + 0.5 - cnt.y * 0.5) * (b.s.y - 1.2) / maxf(cnt.y, 1) if cnt.y > 1 else b.c.y
				var p := Vector3(lx, _top_y(b), lz)
				if _covered_by_other(p, b.id):
					continue
				ids.append(_add_node(p, b.id))
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				if _node_pos[ids[i]].distance_to(_node_pos[ids[j]]) < 3.6:
					_link(ids[i], ids[j], "walk")
		tops[b.id] = ids

	# 3) 구조물 옆면: 낮으면 점프, 높으면 벽 타기. 위에서 아래로는 뛰어내리기.
	#    떠 있는 다리는 밑에서 오를 수 없고 뛰어내리기만 한다.
	for b in _lay.blocks:
		if b.style == "runwall":
			continue
		var top_y: float = _top_y(b)
		var base_area: String = b.get("on", "ground")
		var height: float = b.h
		var floating: bool = b.get("float", false)
		for f in 4:
			var normal := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)][f] as Vector2
			var along := Vector2(-normal.y, normal.x)
			var half_n: float = (b.s.x if normal.x != 0.0 else b.s.y) * 0.5
			var half_a: float = (b.s.y if normal.x != 0.0 else b.s.x) * 0.5
			var count := maxi(1, int(half_a * 2.0 / 4.0))
			for k in count:
				var t := (k + 0.5) / count * 2.0 - 1.0
				var off_a := along * t * (half_a - 0.8)
				var out2: Vector2 = b.c + normal * (half_n + 1.0) + off_a
				var in2: Vector2 = b.c + normal * (half_n - 0.7) + off_a
				var top_p := Vector3(in2.x, top_y, in2.y)
				if _covered_by_other(top_p, b.id):
					continue
				var base_id := -1
				if base_area == "ground":
					if _blocked(out2, 0.5):
						continue
					base_id = _add_node(Vector3(out2.x, 0, out2.y), "ground")
					_connect_nearest(base_id, "ground", 3.6, 3)
				else:
					var below: Dictionary = _blocks[base_area]
					var r := Rect2(below.c - below.s * 0.5, below.s).grow(-0.4)
					if not r.has_point(out2):
						continue
					base_id = _add_node(Vector3(out2.x, _top_y(below), out2.y), base_area)
					_connect_nearest(base_id, base_area, 3.6, 3)
				var top_id := _add_node(top_p, b.id)
				_connect_nearest(top_id, b.id, 3.6, 3)
				if floating:
					_link(top_id, base_id, "drop", false)
				else:
					_link(base_id, top_id, "jump" if height <= 1.3 else "climb")

	# 4) 계단과 경사로
	for r in _lay.ramps:
		var from: Vector3 = r.from
		var to: Vector3 = r.to
		var flat := Vector3(to.x - from.x, 0, to.z - from.z).normalized()
		var ring := ring_of(from)
		var bottom := _add_node(from - flat * 0.9, "ground", ring)
		_connect_nearest(bottom, "ground", 3.6, 3)
		var mid := _add_node((from + to) * 0.5, "ramp", ring)
		var top := _add_node(to + flat * 0.8, r.top)
		_connect_nearest(top, r.top, 3.6, 3)
		_link(bottom, mid, "walk")
		_link(mid, top, "walk")

	# 5) 발판끼리 점프
	for pair in _lay.jump_links:
		var ia: int = tops[pair[0]][0]
		var ib: int = tops[pair[1]][0]
		_link(ia, ib, "jump")

	# 6) 다리와 기둥 꼭대기를 잇는다 (가장 가까운 점끼리)
	for pair in _lay.top_links:
		var best := [-1, -1]
		var best_d := INF
		for ia in tops[pair[0]]:
			for ib in tops[pair[1]]:
				var d := _node_pos[ia].distance_to(_node_pos[ib])
				if d < best_d:
					best_d = d
					best = [ia, ib]
		if best[0] >= 0:
			_link(best[0], best[1], "walk")

	# 7) 오르내리는 발판: 바닥 점 ↔ 위 점
	for i in _lay.lifts.size():
		var l: Dictionary = _lay.lifts[i]
		var c: Vector2 = l.c
		var low := _add_node(Vector3(c.x, 0.0, c.y), "ground", 0)
		_connect_nearest(low, "ground", 3.4, 4)
		var high := _add_node(Vector3(c.x, l.top, c.y), "lift_top", 0)
		_connect_nearest(high, l.reach, 3.4, 2)
		_link(low, high, "lift", true, i)

	# 8) 바람 발판: 발판 위 점 → 내려앉는 곳 (한쪽으로만)
	for i in _lay.pads.size():
		var pd: Dictionary = _lay.pads[i]
		var c: Vector2 = pd.c
		var on_pad := _add_node(Vector3(c.x, 0.0, c.y), "ground")
		_connect_nearest(on_pad, "ground", 3.6, 3)
		var land := _nearest_in_area(pd.to, pd.area)
		if land >= 0:
			_link(on_pad, land, "launch", false, i)

	# 9) 짚라인: 출발 구조물 위 → 도착 구조물 위 (한쪽으로만)
	for i in _lay.ziplines.size():
		var z: Dictionary = _lay.ziplines[i]
		var start := _nearest_in_area(Vector3(z.a.x, z.a.y - Zipline.HANG, z.a.z), z.from)
		var end := _nearest_in_area(Vector3(z.b.x, z.b.y - Zipline.HANG, z.b.z), z.to)
		if start >= 0 and end >= 0:
			_link(start, end, "zip", false, i)


func _nearest_in_area(p: Vector3, area: String) -> int:
	var best := -1
	var best_d := INF
	for i in _node_pos.size():
		if _node_area[i] != area:
			continue
		var d := _node_pos[i].distance_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


func _covered_by_other(p: Vector3, self_id: String) -> bool:
	for o in _lay.blocks:
		if o.id == self_id:
			continue
		if o.get("on", "") == self_id or (o.base <= p.y + 0.01 and _top_y(o) > p.y + 0.01):
			var r := Rect2(o.c - o.s * 0.5, o.s).grow(0.5)
			if r.has_point(Vector2(p.x, p.z)):
				return true
	return false


func _connect_nearest(id: int, area: String, max_d: float, count: int) -> void:
	var p := _node_pos[id]
	var found := []
	for i in _node_pos.size():
		if i == id or _node_area[i] != area:
			continue
		var d := _node_pos[i].distance_to(p)
		if d <= max_d:
			found.append([d, i])
	found.sort_custom(func(x, y): return x[0] < y[0])
	for k in mini(count, found.size()):
		_link(id, found[k][1], "walk")


## 어떤 위치에서 가장 가까운 길목 점. 높이 차이는 크게 따진다. 꺼진 점(무너질 곳)은 건너뛴다.
func nearest_node(p: Vector3) -> int:
	var best := -1
	var best_c := INF
	for i in _node_pos.size():
		if _astar_climb.is_point_disabled(i):
			continue
		var q := _node_pos[i]
		var dy := p.y - q.y
		var c := Vector2(p.x - q.x, p.z - q.z).length() + (absf(dy) * 3.0 if dy > -0.4 else 50.0)
		if c < best_c:
			best_c = c
			best = i
	return best


func area_of(p: Vector3) -> String:
	var i := nearest_node(p)
	return _node_area[i] if i >= 0 else "ground"


## from 에서 to 로 가는 길. [{"pos": Vector3, "kind": "walk"/"jump"/"climb"/"drop"/"lift"/"zip"/"launch", "ref": 번호}, ...]
func find_path(from: Vector3, to: Vector3, can_climb: bool) -> Array:
	var a := nearest_node(from)
	var b := nearest_node(to)
	if a < 0 or b < 0:
		return []
	var astar := _astar_climb if can_climb else _astar_walk
	var ids := astar.get_id_path(a, b)
	var out := []
	for i in ids.size():
		var kind := "walk"
		var ref := -1
		if i > 0:
			var key := "%d>%d" % [ids[i - 1], ids[i]]
			kind = _edge_kind.get(key, "walk")
			ref = _edge_ref.get(key, -1)
		out.append({"pos": _node_pos[ids[i]], "kind": kind, "ref": ref})
	return out


func node_count() -> int:
	return _node_pos.size()
