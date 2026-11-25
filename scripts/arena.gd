class_name Arena
extends Node3D
## 경기장: 밝은 돌바닥 위에 기둥, 건물, 높은 회랑, 계단, 발판, 벽 달리기용 벽을 세운다.
## 모든 구조물은 아래 표(BLOCKS, RAMPS)에 적혀 있고, 표를 고치면 모양과 충돌, AI 길찾기가 함께 바뀐다.
##
## AI 길찾기
##   바닥에는 2.5m 간격으로 길목 점을 깔고, 구조물 위에도 점을 깐다.
##   점끼리는 "걷기", "점프"(낮은 턱), "벽 타기"(높은 벽, 벽을 탈 수 있는 캐릭터만), "뛰어내리기" 로 잇는다.
##   find_path() 가 이 점들을 따라가는 길을 알려 준다.

const HALF := 26.0              # 경기장 반 너비 (벽 안쪽까지)
const WALL_H := 4.5
const GRID := 2.5

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

## 구조물: 이름, 가운데 (x, z), 크기 (x, z), 밑면 높이, 높이, 모양, 벽 타기 가능
const BLOCKS := [
	{"id": "pillar_ne", "c": Vector2(10, -10), "s": Vector2(2.6, 2.6), "base": 0.0, "h": 6.0, "style": "pillar"},
	{"id": "pillar_nw", "c": Vector2(-10, -10), "s": Vector2(2.6, 2.6), "base": 0.0, "h": 6.0, "style": "pillar"},
	{"id": "pillar_se", "c": Vector2(10, 10), "s": Vector2(2.6, 2.6), "base": 0.0, "h": 6.0, "style": "pillar"},
	{"id": "pillar_sw", "c": Vector2(-10, 10), "s": Vector2(2.6, 2.6), "base": 0.0, "h": 6.0, "style": "pillar"},
	{"id": "west_house", "c": Vector2(-17, 0), "s": Vector2(7, 10), "base": 0.0, "h": 4.2, "style": "house"},
	{"id": "east_house", "c": Vector2(17, 0), "s": Vector2(7, 10), "base": 0.0, "h": 3.0, "style": "house"},
	{"id": "east_tower", "c": Vector2(18.3, -2.0), "s": Vector2(4, 4), "base": 3.0, "h": 2.6, "style": "tower", "on": "east_house"},
	{"id": "gallery", "c": Vector2(0, -20), "s": Vector2(16, 4), "base": 0.0, "h": 2.4, "style": "gallery"},
	{"id": "step1", "c": Vector2(-12, 17), "s": Vector2(2.4, 2.4), "base": 0.0, "h": 1.1, "style": "step"},
	{"id": "step2", "c": Vector2(-15, 19.5), "s": Vector2(2.4, 2.4), "base": 0.0, "h": 2.2, "style": "step"},
	{"id": "step3", "c": Vector2(-18.3, 17), "s": Vector2(2.4, 2.4), "base": 0.0, "h": 3.3, "style": "step"},
	{"id": "crate1", "c": Vector2(6, -12), "s": Vector2(2, 2), "base": 0.0, "h": 1.1, "style": "crate"},
	{"id": "crate2", "c": Vector2(-6, -12), "s": Vector2(2, 2), "base": 0.0, "h": 1.1, "style": "crate"},
	{"id": "crate3", "c": Vector2(8, 14), "s": Vector2(1.6, 1.6), "base": 0.0, "h": 1.1, "style": "crate"},
	{"id": "crate4", "c": Vector2(-22, -15), "s": Vector2(2, 2), "base": 0.0, "h": 1.1, "style": "crate"},
	{"id": "crate5", "c": Vector2(22, 15), "s": Vector2(2, 2), "base": 0.0, "h": 1.1, "style": "crate"},
	{"id": "crate6", "c": Vector2(21, -17), "s": Vector2(1.6, 1.6), "base": 0.0, "h": 1.1, "style": "crate"},
	# 벽 달리기용 벽 (위로는 못 탄다)
	{"id": "runwall_w", "c": Vector2(-5.5, 17), "s": Vector2(0.6, 8), "base": 0.0, "h": 4.0, "style": "runwall", "no_climb": true},
	{"id": "runwall_e", "c": Vector2(5.5, 17), "s": Vector2(0.6, 8), "base": 0.0, "h": 4.0, "style": "runwall", "no_climb": true},
]

## 계단/경사로: 아래 끝, 위 끝, 너비, 올라가면 닿는 구조물
const RAMPS := [
	{"from": Vector3(-17, 0, 10.8), "to": Vector3(-17, 4.2, 5.0), "w": 3.0, "top": "west_house", "stairs": true},
	{"from": Vector3(15.5, 0, -10.0), "to": Vector3(15.5, 3.0, -5.0), "w": 3.0, "top": "east_house", "stairs": true},
	{"from": Vector3(13.5, 0, -20), "to": Vector3(8.0, 2.4, -20), "w": 3.2, "top": "gallery", "stairs": false},
	{"from": Vector3(-13.5, 0, -20), "to": Vector3(-8.0, 2.4, -20), "w": 3.2, "top": "gallery", "stairs": false},
]

## 발판끼리 점프로 잇는 길
const JUMP_LINKS := [["step1", "step2"], ["step2", "step3"]]

var _mats := {}
var _blocks := {}               # id -> 표 항목
# 길찾기
var _astar_climb := AStar3D.new()   # 벽을 탈 수 있는 캐릭터용
var _astar_walk := AStar3D.new()    # 못 타는 캐릭터용
var _node_pos := PackedVector3Array()
var _node_area := PackedStringArray()
var _edge_kind := {}                # "a>b" -> "walk" / "jump" / "climb" / "drop"
var _obstacles := []                # 바닥에서 지나갈 수 없는 사각형 (Rect2)


func _ready() -> void:
	_make_materials()
	for b in BLOCKS:
		_blocks[b.id] = b
	_build_floor()
	_build_walls()
	for b in BLOCKS:
		_build_block(b)
	for r in RAMPS:
		_build_ramp(r)
	_build_backdrop()
	_build_nav()


func _make_materials() -> void:
	_mats.stone = LowPoly.mat(C_STONE, 0.9)
	_mats.stone2 = LowPoly.mat(C_STONE2, 0.9)
	_mats.teal = LowPoly.mat(C_TEAL, 0.75)
	_mats.coral = LowPoly.mat(C_CORAL, 0.8)
	_mats.navy = LowPoly.mat(C_NAVY, 0.7)
	_mats.gold = LowPoly.mat(C_GOLD, 0.45, 0.35)
	_mats.sand = LowPoly.mat(Color(0.86, 0.76, 0.60), 0.9)
	_mats.window = LowPoly.mat(Color(0.16, 0.24, 0.32), 0.25, 0.2)
	var vc := StandardMaterial3D.new()
	vc.vertex_color_use_as_albedo = true
	vc.vertex_color_is_srgb = true
	vc.roughness = 0.88
	vc.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats.vcolor = vc


# ---------------- 바닥 ----------------

## 바닥 전체를 한 덩어리(그리기 한 번)로 만든다: 큰 타일, 줄눈, 8m 마다 청록 선, 가운데 원형 무늬.
## 줄무늬가 지나가는 게 보여서 달릴 때 속도감이 산다.
func _build_floor() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var tile := 2.0
	var n := int(HALF * 2.0 / tile)
	for ix in n:
		for iz in n:
			var x0 := -HALF + ix * tile
			var z0 := -HALF + iz * tile
			var h := (ix * 7 + iz * 13) % 5
			var c := C_FLOOR_A if (ix + iz) % 2 == 0 else C_FLOOR_B
			c = c.darkened(h * 0.008)
			_quad(st, Vector3(x0, 0, z0), Vector3(x0 + tile, 0, z0 + tile), c)
	# 줄눈
	for i in n + 1:
		var p := -HALF + i * tile
		var col := C_GROUT
		var w := 0.05
		if int(round(p)) % 8 == 0 and absf(p) < HALF - 0.1:
			col = C_TEAL
			w = 0.14
		_quad(st, Vector3(p - w, 0.004, -HALF), Vector3(p + w, 0.004, HALF), col)
		_quad(st, Vector3(-HALF, 0.005, p - w), Vector3(HALF, 0.005, p + w), col)
	# 가운데 결투 원
	_ring(st, 0.0, 9.0, 0.007, C_FLOOR_A, 48)
	_ring(st, 8.4, 9.0, 0.009, C_CORAL, 48)
	_ring(st, 7.9, 8.05, 0.009, C_NAVY, 48)
	_ring(st, 2.7, 3.0, 0.009, C_GOLD, 32)
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-d.z, 0, d.x) * 0.09
		var p1 := d * 3.2
		var p2 := d * 7.7
		_tri(st, p1 - side + Vector3.UP * 0.009, p2 - side + Vector3.UP * 0.009, p2 + side + Vector3.UP * 0.009, C_TEAL)
		_tri(st, p1 - side + Vector3.UP * 0.009, p2 + side + Vector3.UP * 0.009, p1 + side + Vector3.UP * 0.009, C_TEAL)
	_ring(st, 0.0, 1.3, 0.011, C_NAVY, 8)
	_ring(st, 0.0, 0.55, 0.013, C_GOLD, 8)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mats.vcolor
	add_child(mi)
	# 시작 자리 (작은 원판)
	for z in [6.0, -6.0]:
		LowPoly.part(self, LowPoly.cyl(0.7, 0.7, 0.02, 16), _mats.navy if z > 0 else _mats.coral, Vector3(0, 0.012, z))


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


func _ring(st: SurfaceTool, r0: float, r1: float, y: float, col: Color, seg: int) -> void:
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


# ---------------- 바깥 벽 ----------------

func _build_walls() -> void:
	for side in 4:
		var horizontal := side < 2
		var sgn := -1.0 if side % 2 == 0 else 1.0
		var length := HALF * 2.0 + 2.0
		var size := Vector3(length, WALL_H, 1.0) if horizontal else Vector3(1.0, WALL_H, length)
		var pos := Vector3(0, WALL_H * 0.5, sgn * (HALF + 0.5)) if horizontal else Vector3(sgn * (HALF + 0.5), WALL_H * 0.5, 0)
		LowPoly.part(self, LowPoly.box(size), _mats.stone, pos)
		# 아래 띠, 위 덮개
		var band := size
		band.y = 0.5
		LowPoly.part(self, LowPoly.box(band + Vector3(0.06, 0, 0.06)), _mats.stone2, Vector3(pos.x, 0.25, pos.z))
		var cap := size + Vector3(0.3, 0, 0.3)
		cap.y = 0.3
		LowPoly.part(self, LowPoly.box(cap), _mats.navy, Vector3(pos.x, WALL_H + 0.15, pos.z))
		var stripe := size + Vector3(0.04, 0, 0.04)
		stripe.y = 0.14
		LowPoly.part(self, LowPoly.box(stripe), _mats.teal, Vector3(pos.x, WALL_H - 0.45, pos.z))
		# 충돌은 아주 높게 (밖으로 넘어가지 못하게). 바깥 벽은 타고 오를 수 없다.
		var col_size := size
		col_size.y = 30.0
		var body := _static_box(Vector3(pos.x, 15.0 - 0.01, pos.z), col_size)
		body.set_meta("no_climb", true)
		# 깃발
		for k in range(-3, 4):
			var along := k * 7.5
			var fp := Vector3(along, 0, pos.z - sgn * 0.52) if horizontal else Vector3(pos.x - sgn * 0.52, 0, along)
			var flag := Node3D.new()
			flag.position = fp
			flag.rotation.y = 0.0 if horizontal else PI * 0.5
			add_child(flag)
			var color: Material = _mats.coral if (k + side) % 2 == 0 else _mats.teal
			LowPoly.part(flag, LowPoly.box(Vector3(1.3, 2.2, 0.05)), color, Vector3(0, 2.6, 0))
			LowPoly.part(flag, LowPoly.prism(Vector3(1.3, 0.5, 0.05)), color, Vector3(0, 1.25, 0), Vector3(0, 0, 180))
			LowPoly.part(flag, LowPoly.box(Vector3(1.5, 0.1, 0.1)), _mats.gold, Vector3(0, 3.75, 0))
			LowPoly.part(flag, LowPoly.cyl(0.22, 0.22, 0.06, 6), _mats.gold, Vector3(0, 2.7, -0.04), Vector3(90, 0, 0))


# ---------------- 구조물 ----------------

func _build_block(b: Dictionary) -> void:
	var size := Vector3(b.s.x, b.h, b.s.y)
	var center := Vector3(b.c.x, b.base + b.h * 0.5, b.c.y)
	var body := _static_box(center, size)
	if b.get("no_climb", false):
		body.set_meta("no_climb", true)
	if b.base == 0.0:
		_obstacles.append(Rect2(b.c - b.s * 0.5, b.s))
	match b.style:
		"pillar":
			_style_pillar(center, size)
		"house":
			_style_house(center, size, b)
		"tower":
			_style_tower(center, size)
		"gallery":
			_style_gallery(center, size)
		"step":
			var m: Material = [_mats.teal, _mats.navy, _mats.coral][int(b.h / 1.1 + 0.1) % 3]
			LowPoly.part(self, LowPoly.box(size), m, center)
			LowPoly.part(self, LowPoly.box(Vector3(size.x + 0.06, 0.12, size.z + 0.06)), _mats.stone, center + Vector3(0, size.y * 0.5 - 0.06, 0))
		"crate":
			LowPoly.part(self, LowPoly.box(size), _mats.sand, center)
			for y in [-0.42, 0.42]:
				LowPoly.part(self, LowPoly.box(Vector3(size.x + 0.04, 0.1, size.z + 0.04)), _mats.navy, center + Vector3(0, y * size.y, 0))
		"runwall":
			_style_runwall(center, size)


func _style_pillar(center: Vector3, size: Vector3) -> void:
	LowPoly.part(self, LowPoly.box(size), _mats.stone, center)
	var bottom := center.y - size.y * 0.5
	var top := center.y + size.y * 0.5
	LowPoly.part(self, LowPoly.box(Vector3(size.x + 0.2, 0.5, size.z + 0.2)), _mats.stone2, Vector3(center.x, bottom + 0.25, center.z))
	for y in [2.0, 4.0]:
		LowPoly.part(self, LowPoly.box(Vector3(size.x + 0.06, 0.3, size.z + 0.06)), _mats.coral, Vector3(center.x, bottom + y, center.z))
	LowPoly.part(self, LowPoly.box(Vector3(size.x + 0.04, 0.3, size.z + 0.04)), _mats.navy, Vector3(center.x, top - 0.15, center.z))
	# 꼭대기 금색 표시
	LowPoly.part(self, LowPoly.cyl(0.45, 0.5, 0.06, 8), _mats.gold, Vector3(center.x, top + 0.03, center.z))
	_holds(center, size, bottom + 0.8, 5)


## 벽에 박힌 작은 돌 손잡이: 이 벽은 타고 오를 수 있다는 표시
func _holds(center: Vector3, size: Vector3, from_y: float, rows: int) -> void:
	for f in 4:
		var d := Vector3(cos(f * PI * 0.5), 0, sin(f * PI * 0.5))
		var along := Vector3(-d.z, 0, d.x)
		for k in rows:
			for j in 2:
				var off := (j - 0.5) * 0.7 + (0.25 if k % 2 == 0 else -0.25)
				var p := Vector3(center.x, from_y + k * 1.0 + j * 0.45, center.z) + d * (size.x * 0.5 + 0.03) + along * off
				var hold := LowPoly.part(self, LowPoly.box(Vector3(0.22, 0.14, 0.1)), _mats.coral if (k + j) % 3 == 0 else _mats.navy, p, Vector3.ZERO, 0.02, k * 7 + j + f * 31)
				hold.rotation.y = f * PI * 0.5 + PI * 0.5


func _style_house(center: Vector3, size: Vector3, b: Dictionary) -> void:
	LowPoly.part(self, LowPoly.box(size), _mats.stone, center)
	var bottom := center.y - size.y * 0.5
	var top := center.y + size.y * 0.5
	LowPoly.part(self, LowPoly.box(Vector3(size.x + 0.12, 0.6, size.z + 0.12)), _mats.stone2, Vector3(center.x, bottom + 0.3, center.z))
	LowPoly.part(self, LowPoly.box(Vector3(size.x + 0.1, 0.35, size.z + 0.1)), _mats.teal, Vector3(center.x, top - 0.175, center.z))
	# 지붕 위 바닥 무늬
	LowPoly.part(self, LowPoly.box(Vector3(size.x - 1.2, 0.02, size.z - 1.2)), _mats.stone2, Vector3(center.x, top + 0.01, center.z))
	# 창문과 문: 경기장 가운데를 보는 면
	var face := -signf(b.c.x)
	var fx := center.x + face * (size.x * 0.5 + 0.02)
	for k in [-3.0, 0.0, 3.0]:
		var wy := top - 1.3
		var win := LowPoly.part(self, LowPoly.box(Vector3(0.06, 0.9, 1.1)), _mats.window, Vector3(fx, wy, center.z + k))
		win.rotation.y = 0
		LowPoly.part(self, LowPoly.box(Vector3(0.1, 0.12, 1.4)), _mats.coral, Vector3(fx + face * 0.05, wy + 0.55, center.z + k))
	LowPoly.part(self, LowPoly.box(Vector3(0.06, 1.9, 1.3)), _mats.navy, Vector3(fx, bottom + 0.95, center.z + 1.5))
	# 차양
	var aw := LowPoly.part(self, LowPoly.box(Vector3(0.9, 0.08, 1.8)), _mats.coral, Vector3(fx + face * 0.4, bottom + 2.05, center.z + 1.5))
	aw.rotation.z = face * deg_to_rad(-15)


func _style_tower(center: Vector3, size: Vector3) -> void:
	LowPoly.part(self, LowPoly.box(size), _mats.stone2, center)
	var top := center.y + size.y * 0.5
	LowPoly.part(self, LowPoly.box(Vector3(size.x + 0.1, 0.3, size.z + 0.1)), _mats.coral, Vector3(center.x, top - 0.15, center.z))
	LowPoly.part(self, LowPoly.cyl(0.5, 0.55, 0.06, 8), _mats.gold, Vector3(center.x, top + 0.03, center.z))
	_holds(center, size, center.y - size.y * 0.5 + 0.4, 2)


func _style_gallery(center: Vector3, size: Vector3) -> void:
	LowPoly.part(self, LowPoly.box(size), _mats.stone, center)
	var top := center.y + size.y * 0.5
	LowPoly.part(self, LowPoly.box(Vector3(size.x + 0.08, 0.3, size.z + 0.08)), _mats.navy, Vector3(center.x, top - 0.15, center.z))
	# 앞면 아치 무늬 (장식)
	var fz := center.z + size.z * 0.5 + 0.02
	for k in range(-3, 4):
		var x: float = center.x + k * 2.2
		LowPoly.part(self, LowPoly.box(Vector3(1.3, 1.3, 0.05)), _mats.teal, Vector3(x, 0.9, fz))
		LowPoly.part(self, LowPoly.cyl(0.65, 0.65, 0.05, 8), _mats.teal, Vector3(x, 1.55, fz), Vector3(90, 0, 0))
	# 위쪽 기둥 장식 (난간 대신 낮은 말뚝 몇 개: 싸움을 방해하지 않을 만큼)
	for k in [-1, 1]:
		var p := Vector3(center.x + k * (size.x * 0.5 - 0.4), top + 0.4, center.z - size.z * 0.5 + 0.4)
		LowPoly.part(self, LowPoly.box(Vector3(0.4, 0.8, 0.4)), _mats.coral, p)
		_static_box(p, Vector3(0.4, 0.8, 0.4))


func _style_runwall(center: Vector3, size: Vector3) -> void:
	LowPoly.part(self, LowPoly.box(size), _mats.coral, center)
	var top := center.y + size.y * 0.5
	LowPoly.part(self, LowPoly.box(Vector3(size.x + 0.08, 0.25, size.z + 0.08)), _mats.navy, Vector3(center.x, top - 0.12, center.z))
	# 화살표 띠: 벽을 따라 달리라는 표시
	for side in [-1.0, 1.0]:
		var x: float = center.x + side * (size.x * 0.5 + 0.02)
		for k in range(-3, 4):
			var z := center.z + k * 1.1
			var chev := LowPoly.part(self, LowPoly.prism(Vector3(0.7, 0.5, 0.04)), _mats.stone, Vector3(x, 1.9, z))
			chev.rotation = Vector3(0, PI * 0.5, PI * 0.5)


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
			var step := LowPoly.part(self, LowPoly.box(Vector3(w, top_y - from.y, d + 0.01)), m, Vector3(mid.x, (from.y + top_y) * 0.5, mid.z))
			step.basis = basis
		# 옆 벽 (계단 밑을 막는다)
		var mid_all := from + dir * run * 0.5
		for s in [-1.0, 1.0]:
			var sw := MeshInstance3D.new()
			sw.mesh = _ramp_side_mesh(run, rise)
			sw.material_override = _mats.stone2
			sw.basis = basis
			sw.position = Vector3(mid_all.x, from.y, mid_all.z) + side * s * (w * 0.5 + 0.03)
			add_child(sw)
		# 걸을 때 쓰는 경사 충돌: 계단 가운데를 지나간다
		var start := from - dir * d * 0.5
		var stop := from + dir * (run - d * 0.5) + Vector3.UP * rise
		_slope(start, stop, w, side)
		# 맨 위 칸은 평평하게
		var last := from + dir * (run - d * 0.5)
		var lb := _static_box(Vector3(last.x, to.y - 0.15, last.z), Vector3(w, 0.3, d))
		lb.basis = basis
	else:
		var start := from
		var stop := Vector3(to.x, to.y, to.z)
		var mid := (start + stop) * 0.5
		var length := start.distance_to(stop)
		var ang := atan2(rise, run)
		var slab := LowPoly.part(self, LowPoly.box(Vector3(w, 0.3, length)), _mats.stone2, mid - Vector3.UP * 0.15)
		slab.basis = basis * Basis(Vector3.RIGHT, ang)
		# 밑을 메우는 삼각 기둥
		var sw := MeshInstance3D.new()
		sw.mesh = _ramp_side_mesh(run, rise, w)
		sw.material_override = _mats.stone
		sw.basis = basis
		sw.position = Vector3((from.x + to.x) * 0.5, from.y, (from.z + to.z) * 0.5)
		add_child(sw)
		for s in [-1.0, 1.0]:
			var edge := LowPoly.part(self, LowPoly.box(Vector3(0.12, 0.12, length)), _mats.teal, mid + side * s * (w * 0.5 - 0.06) + Vector3.UP * 0.05)
			edge.basis = slab.basis
		_slope(start, stop, w, side)
	# 경사로가 차지한 바닥 자리
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
	var a := Vector3(0, 0, run * 0.5)     # 아래 끝 (로컬 +z 쪽이 아래)
	var b := Vector3(0, 0, -run * 0.5)
	var c := Vector3(0, rise, -run * 0.5)
	for s in [-1.0, 1.0]:
		var o := Vector3(s * hw, 0, 0)
		st.add_vertex(a + o)
		st.add_vertex(b + o)
		st.add_vertex(c + o)
	# 뒤쪽 세운 면과 비스듬한 면은 두께가 있을 때만
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
	add_child(body)


func _static_box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.position = pos
	body.add_child(col)
	add_child(body)
	return body


# ---------------- 바깥 풍경 ----------------

func _build_backdrop() -> void:
	var grass := LowPoly.mat(Color(0.52, 0.68, 0.40), 0.95)
	var grass2 := LowPoly.mat(Color(0.58, 0.72, 0.44), 0.95)
	var bark := LowPoly.mat(Color(0.45, 0.33, 0.24), 0.95)
	var leaf := LowPoly.mat(Color(0.35, 0.58, 0.36), 0.9)
	var leaf2 := LowPoly.mat(Color(0.95, 0.66, 0.55), 0.9)   # 분홍빛 나무
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(220, 220)
	ground_mesh.subdivide_width = 36
	ground_mesh.subdivide_depth = 36
	var ground := LowPoly.part(self, ground_mesh, grass, Vector3(0, -0.06, 0))
	ground.mesh = _bumpy_ground(ground_mesh)
	_static_box(Vector3(0, -0.5, 0), Vector3(220, 1, 220))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 34:
		var a := rng.randf() * TAU
		var r := rng.randf_range(32.0, 70.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = _hill_height(p.x, p.z) - 0.2
		var tree := Node3D.new()
		tree.position = p
		tree.rotation.y = rng.randf() * TAU
		tree.scale = Vector3.ONE * rng.randf_range(1.2, 2.0)
		add_child(tree)
		LowPoly.part(tree, LowPoly.cyl(0.16, 0.24, 2.0, 6), bark, Vector3(0, 1.0, 0), Vector3.ZERO, 0.03, i)
		var lm: Material = leaf2 if i % 4 == 0 else leaf
		LowPoly.part(tree, LowPoly.sphere(1.3, 7, 5), lm, Vector3(0, 2.8, 0), Vector3.ZERO, 0.22, i + 100)
		LowPoly.part(tree, LowPoly.sphere(0.9, 6, 4), grass2 if i % 3 == 0 else lm, Vector3(0.6, 3.4, 0.3), Vector3.ZERO, 0.15, i + 200)


func _hill_height(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var hill := clampf((d - 30.0) / 40.0, 0.0, 1.0)
	return (sin(x * 0.11) * cos(z * 0.09) * 1.5 + sin(x * 0.05 + z * 0.04) * 3.0) * hill + hill * hill * 9.0


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


# ---------------- 길찾기 ----------------

func _add_node(p: Vector3, area: String) -> int:
	var id := _node_pos.size()
	_node_pos.append(p)
	_node_area.append(area)
	_astar_climb.add_point(id, p)
	_astar_walk.add_point(id, p)
	return id


func _link(a: int, b: int, kind: String, both_ways: bool = true) -> void:
	if kind != "climb":
		_astar_walk.connect_points(a, b, false)
	_astar_climb.connect_points(a, b, false)
	_edge_kind["%d>%d" % [a, b]] = kind
	if both_ways:
		var back := kind
		if kind == "climb" or kind == "jump":
			back = "drop"
		_astar_walk.connect_points(b, a, false)
		_astar_climb.connect_points(b, a, false)
		_edge_kind["%d>%d" % [b, a]] = back


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
	var n := int(HALF * 2.0 / GRID)
	var grid := {}
	for ix in n:
		for iz in n:
			var p := Vector2(-HALF + GRID * (ix + 0.5), -HALF + GRID * (iz + 0.5))
			if _blocked(p, 0.7):
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
	for b in BLOCKS:
		if b.style == "runwall":
			continue
		var top_y: float = _top_y(b)
		var base_area: String = b.get("on", "ground")
		var height: float = b.h
		for f in 4:
			var normal := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)][f] as Vector2
			var along := Vector2(-normal.y, normal.x)
			var half_n: float = (b.s.x if normal.x != 0.0 else b.s.y) * 0.5
			var half_a: float = (b.s.y if normal.x != 0.0 else b.s.x) * 0.5
			var count := maxi(1, int(half_a * 2.0 / 4.0))
			for k in count:
				var t := (k + 0.5) / count * 2.0 - 1.0
				var off_a := along * t * (half_a - 0.8)
				var out2: Vector2 = b.c + normal * (half_n + 0.9) + off_a
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
				_link(base_id, top_id, "jump" if height <= 1.3 else "climb")

	# 4) 계단과 경사로
	for r in RAMPS:
		var from: Vector3 = r.from
		var to: Vector3 = r.to
		var flat := Vector3(to.x - from.x, 0, to.z - from.z).normalized()
		var bottom := _add_node(from - flat * 0.8, "ground")
		_connect_nearest(bottom, "ground", 3.6, 3)
		var mid := _add_node((from + to) * 0.5, "ramp")
		var top := _add_node(to + flat * 0.8, r.top)
		_connect_nearest(top, r.top, 3.6, 3)
		_link(bottom, mid, "walk")
		_link(mid, top, "walk")

	# 5) 발판끼리 점프
	for pair in JUMP_LINKS:
		var a: Dictionary = _blocks[pair[0]]
		var b: Dictionary = _blocks[pair[1]]
		var ia: int = tops[a.id][0]
		var ib: int = tops[b.id][0]
		_link(ia, ib, "jump")


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


## 어떤 위치에서 가장 가까운 길목 점. 높이 차이는 크게 따진다.
func nearest_node(p: Vector3) -> int:
	var best := -1
	var best_c := INF
	for i in _node_pos.size():
		var q := _node_pos[i]
		var dy := p.y - q.y
		# 점보다 아래에 있으면 (떨어지는 중이 아니면) 그 점에 서 있을 수 없다
		var c := Vector2(p.x - q.x, p.z - q.z).length() + (absf(dy) * 3.0 if dy > -0.4 else 50.0)
		if c < best_c:
			best_c = c
			best = i
	return best


func area_of(p: Vector3) -> String:
	var i := nearest_node(p)
	return _node_area[i] if i >= 0 else "ground"


## from 에서 to 로 가는 길. [{"pos": Vector3, "kind": "walk"/"jump"/"climb"/"drop"}, ...]
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
		if i > 0:
			kind = _edge_kind.get("%d>%d" % [ids[i - 1], ids[i]], "walk")
		out.append({"pos": _node_pos[ids[i]], "kind": kind})
	return out


func node_count() -> int:
	return _node_pos.size()
