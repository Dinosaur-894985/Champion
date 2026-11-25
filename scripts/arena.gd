class_name Arena
extends Node3D
## 경기장: 하늘 위에 떠 있는 3층짜리 돌 경기장.
##   1층 (바닥 0m)   : 가운데 결투 원, 낮은 받침돌, 상자
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
	{"id": "crate_c1", "c": Vector2(-10.5, 7.5), "s": Vector2(1.8, 1.8), "base": 0.0, "h": 1.1, "style": "crate"},
	{"id": "crate_c2", "c": Vector2(10.5, -7.5), "s": Vector2(1.8, 1.8), "base": 0.0, "h": 1.1, "style": "crate"},
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
	{"id": "crate_b1", "c": Vector2(19.5, -19.5), "s": Vector2(2, 2), "base": 0.0, "h": 1.1, "style": "crate"},
	{"id": "crate_b2", "c": Vector2(-20, -20), "s": Vector2(1.6, 1.6), "base": 0.0, "h": 1.1, "style": "crate"},
	# ---- 맨 바깥 고리 (가장 먼저 무너짐) ----
	{"id": "crate_a1", "c": Vector2(-25, -6), "s": Vector2(2, 2), "base": 0.0, "h": 1.1, "style": "crate"},
	{"id": "crate_a2", "c": Vector2(25, 6), "s": Vector2(2, 2), "base": 0.0, "h": 1.1, "style": "crate"},
	{"id": "crate_a3", "c": Vector2(8, 25), "s": Vector2(1.6, 1.6), "base": 0.0, "h": 1.1, "style": "crate"},
	{"id": "crate_a4", "c": Vector2(-8, -25), "s": Vector2(1.6, 1.6), "base": 0.0, "h": 1.1, "style": "crate"},
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

## 낭떠러지에 떨어진 뒤 다시 서는 자리
const SAFE_SPOTS := [Vector3(0, 0.1, 4.5), Vector3(0, 0.1, -4.5), Vector3(-2.2, 0.1, 0), Vector3(2.2, 0.1, 0)]

var fighters: Array = []        # 플레이어와 AI (Game 이 넣어 준다)
var director: ArenaDirector
var lifts: Array[ArenaLift] = []
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
	_make_materials()
	for b in BLOCKS:
		_blocks[b.id] = b
	for i in RINGS.size():
		var r := Node3D.new()
		r.name = "Ring%d" % i
		add_child(r)
		_rings.append(r)
		_ring_bodies[i] = []
	_build_floor()
	for b in BLOCKS:
		_cur = _rings[block_ring(b)]
		_build_block(b)
	for r in RAMPS:
		_cur = _rings[ring_of(r.from)]
		_build_ramp(r)
	_cur = _rings[0]
	for l in LIFTS:
		_build_lift(l)
	for z in ZIPLINES:
		var zl := Zipline.new()
		add_child(zl)
		zl.setup(z.id, z.a, z.b, _mats)
		ziplines.append(zl)
	_build_backdrop()
	_build_nav()
	director = ArenaDirector.new()
	director.arena = self
	add_child(director)


func set_fighters(list: Array) -> void:
	fighters = list
	director.fighters = list
	for l in lifts:
		l.fighters = list


func _make_materials() -> void:
	_mats.stone = LowPoly.mat(C_STONE, 0.9)
	_mats.stone2 = LowPoly.mat(C_STONE2, 0.9)
	_mats.teal = LowPoly.mat(C_TEAL, 0.75)
	_mats.coral = LowPoly.mat(C_CORAL, 0.8)
	_mats.navy = LowPoly.mat(C_NAVY, 0.7)
	_mats.gold = LowPoly.mat(C_GOLD, 0.45, 0.35)
	_mats.sand = LowPoly.mat(Color(0.86, 0.76, 0.60), 0.9)
	_mats.rock = LowPoly.mat(C_ROCK, 0.95)
	_mats.rock2 = LowPoly.mat(C_ROCK.darkened(0.15), 0.95)
	_mats.window = LowPoly.mat(Color(0.16, 0.24, 0.32), 0.25, 0.2)
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
		Fx.impact(self, p + Vector3.UP * 0.2, Vector3.UP, C_FLOOR_A, 12)
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
			var c := C_FLOOR_A if (ix + iz) % 2 == 0 else C_FLOOR_B
			c = c.darkened(h * 0.008 + r * 0.012)
			_quad(st, Vector3(x0, 0, z0), Vector3(x0 + tile, 0, z0 + tile), C_GROUT)
			_quad(st, Vector3(x0 + 0.05, 0.004, z0 + 0.05), Vector3(x0 + tile - 0.05, 0.004, z0 + tile - 0.05), c)
	# 고리 경계 띠 (바깥 고리에 속해서 같이 무너진다)
	for r in range(1, RINGS.size()):
		var d: float = RINGS[r - 1]
		var st: SurfaceTool = sts[r]
		var w := 0.28
		_quad(st, Vector3(-d - w, 0.008, -d - w), Vector3(d + w, 0.008, -d), C_CORAL)
		_quad(st, Vector3(-d - w, 0.008, d), Vector3(d + w, 0.008, d + w), C_CORAL)
		_quad(st, Vector3(-d - w, 0.008, -d), Vector3(-d, 0.008, d), C_CORAL)
		_quad(st, Vector3(d, 0.008, -d), Vector3(d + w, 0.008, d), C_CORAL)
	# 맨 바깥 가장자리: 금색 테두리 (벽이 없다는 표시)
	var o: float = HALF
	var edge: SurfaceTool = sts[RINGS.size() - 1]
	_quad(edge, Vector3(-o, 0.008, -o), Vector3(o, 0.008, -o + 0.35), C_GOLD)
	_quad(edge, Vector3(-o, 0.008, o - 0.35), Vector3(o, 0.008, o), C_GOLD)
	_quad(edge, Vector3(-o, 0.008, -o), Vector3(-o + 0.35, 0.008, o), C_GOLD)
	_quad(edge, Vector3(o - 0.35, 0.008, -o), Vector3(o, 0.008, o), C_GOLD)
	# 가운데 결투 원
	var core: SurfaceTool = sts[0]
	_ring_mesh(core, 0.0, 8.0, 0.007, C_FLOOR_A, 48)
	_ring_mesh(core, 7.4, 8.0, 0.009, C_CORAL, 48)
	_ring_mesh(core, 6.9, 7.05, 0.009, C_NAVY, 48)
	_ring_mesh(core, 2.4, 2.7, 0.009, C_GOLD, 32)
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		var dd := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dd.z, 0, dd.x) * 0.09
		var p1 := dd * 2.9
		var p2 := dd * 6.7
		var up := Vector3.UP * 0.009
		_tri(core, p1 - side + up, p2 - side + up, p2 + side + up, C_TEAL)
		_tri(core, p1 - side + up, p2 + side + up, p1 + side + up, C_TEAL)
	_ring_mesh(core, 0.0, 1.2, 0.011, C_NAVY, 8)
	_ring_mesh(core, 0.0, 0.5, 0.013, C_GOLD, 8)

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
				_quad(wst, Vector3(c.x - sz.x * 0.5, 0.02, c.y - sz.y * 0.5), Vector3(c.x + sz.x * 0.5, 0.02, c.y + sz.y * 0.5), Color.WHITE)
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
			_part(LowPoly.box(Vector3(size.x + 0.08, 0.12, size.z + 0.08)), _mats.gold, center + Vector3(0, size.y * 0.5 - 0.06, 0))
			_part(LowPoly.box(Vector3(size.x + 0.14, 0.2, size.z + 0.14)), _mats.stone2, center + Vector3(0, -size.y * 0.5 + 0.1, 0))
		"step":
			var m: Material = [_mats.teal, _mats.navy, _mats.coral][int(b.h / 1.1 + 0.1) % 3]
			_part(LowPoly.box(size), m, center)
			_part(LowPoly.box(Vector3(size.x + 0.06, 0.12, size.z + 0.06)), _mats.stone, center + Vector3(0, size.y * 0.5 - 0.06, 0))
		"crate":
			_part(LowPoly.box(size), _mats.sand, center)
			for y in [-0.42, 0.42]:
				_part(LowPoly.box(Vector3(size.x + 0.04, 0.1, size.z + 0.04)), _mats.navy, center + Vector3(0, y * size.y, 0))
		"runwall":
			_style_runwall(center, size)


func _style_pillar(center: Vector3, size: Vector3) -> void:
	_part(LowPoly.box(size), _mats.stone, center)
	var bottom := center.y - size.y * 0.5
	var top := center.y + size.y * 0.5
	_part(LowPoly.box(Vector3(size.x + 0.2, 0.5, size.z + 0.2)), _mats.stone2, Vector3(center.x, bottom + 0.25, center.z))
	for y in [2.0, 4.0]:
		_part(LowPoly.box(Vector3(size.x + 0.06, 0.3, size.z + 0.06)), _mats.coral, Vector3(center.x, bottom + y, center.z))
	_part(LowPoly.box(Vector3(size.x + 0.16, 0.35, size.z + 0.16)), _mats.navy, Vector3(center.x, top - 0.17, center.z))
	_part(LowPoly.cyl(0.45, 0.5, 0.06, 8), _mats.gold, Vector3(center.x, top + 0.03, center.z))
	_holds(center, size, bottom + 0.8, int(size.y) - 1)


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
	_part(LowPoly.box(Vector3(size.x + 0.1, 0.35, size.z + 0.1)), _mats.teal, Vector3(center.x, top - 0.175, center.z))
	_part(LowPoly.box(Vector3(size.x - 1.2, 0.02, size.z - 1.2)), _mats.stone2, Vector3(center.x, top + 0.01, center.z))
	# 지붕 모서리 장식 (낮아서 걸리지 않는다)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_part(LowPoly.box(Vector3(0.45, 0.25, 0.45)), _mats.gold, Vector3(center.x + sx * (size.x * 0.5 - 0.22), top + 0.12, center.z + sz * (size.z * 0.5 - 0.22)))
	# 창문과 문: 경기장 가운데를 보는 면
	var face := -signf(b.c.x)
	var fx := center.x + face * (size.x * 0.5 + 0.02)
	for k in [-2.6, 0.0, 2.6]:
		var wy := top - 1.2
		_part(LowPoly.box(Vector3(0.06, 0.8, 1.0)), _mats.window, Vector3(fx, wy, center.z + k))
		_part(LowPoly.box(Vector3(0.1, 0.12, 1.3)), _mats.coral, Vector3(fx + face * 0.05, wy + 0.5, center.z + k))
	_part(LowPoly.box(Vector3(0.06, 1.9, 1.3)), _mats.navy, Vector3(fx, bottom + 0.95, center.z - 1.3))
	var aw := _part(LowPoly.box(Vector3(0.9, 0.08, 1.8)), _mats.coral, Vector3(fx + face * 0.4, bottom + 2.05, center.z - 1.3))
	aw.rotation.z = face * deg_to_rad(-15)
	# 바깥쪽 벽에도 손잡이 (벽 타기로 오를 수 있다)
	_holds(center, size, bottom + 0.6, int(size.y) - 1)


func _style_tower(center: Vector3, size: Vector3) -> void:
	_part(LowPoly.box(size), _mats.stone2, center)
	var top := center.y + size.y * 0.5
	_part(LowPoly.box(Vector3(size.x + 0.1, 0.3, size.z + 0.1)), _mats.coral, Vector3(center.x, top - 0.15, center.z))
	_part(LowPoly.cyl(0.5, 0.55, 0.06, 8), _mats.gold, Vector3(center.x, top + 0.03, center.z))
	_holds(center, size, center.y - size.y * 0.5 + 0.4, 3)


func _style_gallery(center: Vector3, size: Vector3) -> void:
	_part(LowPoly.box(size), _mats.stone, center)
	var top := center.y + size.y * 0.5
	_part(LowPoly.box(Vector3(size.x + 0.08, 0.3, size.z + 0.08)), _mats.navy, Vector3(center.x, top - 0.15, center.z))
	var fz := center.z + size.z * 0.5 + 0.02
	for k in range(-2, 3):
		var x: float = center.x + k * 2.4
		_part(LowPoly.box(Vector3(1.3, 1.3, 0.05)), _mats.teal, Vector3(x, 0.9, fz))
		_part(LowPoly.cyl(0.65, 0.65, 0.05, 8), _mats.teal, Vector3(x, 1.55, fz), Vector3(90, 0, 0))
	_holds(center, Vector3(size.x, size.y, size.z), 0.6, 2)


func _style_terrace(center: Vector3, size: Vector3) -> void:
	_part(LowPoly.box(size), _mats.stone, center)
	var top := center.y + size.y * 0.5
	_part(LowPoly.box(Vector3(size.x + 0.1, 0.3, size.z + 0.1)), _mats.coral, Vector3(center.x, top - 0.15, center.z))
	_part(LowPoly.box(Vector3(size.x - 1.0, 0.02, size.z - 1.0)), _mats.sand, Vector3(center.x, top + 0.01, center.z))
	var fz := center.z - size.z * 0.5 - 0.02
	for k in range(-1, 2):
		_part(LowPoly.box(Vector3(1.6, 1.0, 0.05)), _mats.navy, Vector3(center.x + k * 3.0, 1.0, fz))


func _style_bridge(center: Vector3, size: Vector3) -> void:
	_part(LowPoly.box(size), _mats.stone, center)
	var top := center.y + size.y * 0.5
	var bottom := center.y - size.y * 0.5
	# 가장자리 산호색 띠: 난간이 없다는 표시
	for s in [-1.0, 1.0]:
		_part(LowPoly.box(Vector3(size.x, 0.06, 0.16)), _mats.coral, Vector3(center.x, top + 0.02, center.z + s * (size.z * 0.5 - 0.08)))
	# 밑을 받치는 들보와 아래로 드리운 천 (밑에서 올려다볼 때 보기 좋게)
	for k in range(-2, 3):
		var x: float = center.x + k * 2.4
		_part(LowPoly.box(Vector3(0.3, 0.3, size.z + 0.1)), _mats.navy, Vector3(x, bottom - 0.15, center.z))
	for k in [-1, 1]:
		var banner := _part(LowPoly.box(Vector3(1.2, 1.6, 0.04)), _mats.teal if k < 0 else _mats.coral, Vector3(center.x + k * 2.4, bottom - 0.9, center.z))
		banner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_part(LowPoly.prism(Vector3(1.2, 0.4, 0.04)), _mats.teal if k < 0 else _mats.coral, Vector3(center.x + k * 2.4, bottom - 1.9, center.z), Vector3(0, 0, 180))


func _style_runwall(center: Vector3, size: Vector3) -> void:
	_part(LowPoly.box(size), _mats.coral, center)
	var top := center.y + size.y * 0.5
	_part(LowPoly.box(Vector3(size.x + 0.08, 0.25, size.z + 0.08)), _mats.navy, Vector3(center.x, top - 0.12, center.z))
	for side in [-1.0, 1.0]:
		var x: float = center.x + side * (size.x * 0.5 + 0.02)
		for k in range(-2, 3):
			var z := center.z + k * 1.1
			var chev := _part(LowPoly.prism(Vector3(0.7, 0.5, 0.04)), _mats.stone, Vector3(x, 1.9, z))
			chev.rotation = Vector3(0, PI * 0.5, PI * 0.5)


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
	for sx in [-1.0, 1.0]:
		var p := Vector3(c.x + sx * (ArenaLift.SIZE * 0.5 + 0.25), h * 0.5, c.y)
		_part(LowPoly.box(Vector3(0.18, h, 0.18)), _mats.navy, p)
		for y in range(1, int(h), 2):
			_part(LowPoly.box(Vector3(0.24, 0.12, 0.24)), _mats.gold, Vector3(p.x, y, p.z))
	_part(LowPoly.box(Vector3(ArenaLift.SIZE + 0.7, 0.16, 0.2)), _mats.coral, Vector3(c.x, h, c.y))


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
	for b in BLOCKS:
		if not b.has("pickup"):
			continue
		var ring := block_ring(b)
		if ring > alive_ring:
			continue
		if breakables.has(b.id) and (breakables[b.id] as BreakablePillar).is_broken():
			continue
		var pos := Vector3(b.c.x, b.base + b.h, b.c.y)
		if b.id == "west_house":
			pos.z -= 2.5
		out.append({"id": b.id, "pos": pos, "ring": ring, "name": b.pickup})
	return out


## 낭떠러지에 떨어진 몸이 다시 설 자리: 다른 사람에게서 가장 먼 곳
func safe_spawn(me: Node3D) -> Vector3:
	var best := SAFE_SPOTS[0] as Vector3
	var best_d := -1.0
	for s in SAFE_SPOTS:
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
			var p := Vector2(-HALF + GRID * (ix + 0.5), -HALF + GRID * (iz + 0.5))
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
	for b in BLOCKS:
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
	for b in BLOCKS:
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
	for r in RAMPS:
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
	for pair in JUMP_LINKS:
		var ia: int = tops[pair[0]][0]
		var ib: int = tops[pair[1]][0]
		_link(ia, ib, "jump")

	# 6) 다리와 기둥 꼭대기를 잇는다 (가장 가까운 점끼리)
	for pair in TOP_LINKS:
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
	for i in LIFTS.size():
		var l: Dictionary = LIFTS[i]
		var c: Vector2 = l.c
		var low := _add_node(Vector3(c.x, 0.0, c.y), "ground", 0)
		_connect_nearest(low, "ground", 3.4, 4)
		var high := _add_node(Vector3(c.x, l.top, c.y), "lift_top", 0)
		_connect_nearest(high, l.reach, 3.4, 2)
		_link(low, high, "lift", true, i)

	# 8) 짚라인: 출발 구조물 위 → 도착 구조물 위 (한쪽으로만)
	for i in ZIPLINES.size():
		var z: Dictionary = ZIPLINES[i]
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
	for o in BLOCKS:
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


## from 에서 to 로 가는 길. [{"pos": Vector3, "kind": "walk"/"jump"/"climb"/"drop"/"lift"/"zip", "ref": 번호}, ...]
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
