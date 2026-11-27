class_name SwingTrail
extends MeshInstance3D
## 휘두른 자리에 남는 빛 자취 (검기).
##
## 무기 끝(tip)과 손잡이 쪽(base) 두 점이 지나간 길을 이어 얇은 띠를 만든다.
## - 앞(방금 지나간 곳)은 밝고 따뜻한 색, 뒤로 갈수록 가늘어지고 차가운 색으로 사라진다.
## - 시간은 게임 시간으로 흐른다: 맞는 순간 멈춤(히트스톱) 동안에는 자취도 그대로 멈춘다.
## - 점 사이는 곡선으로 메워서 빠르게 휘둘러도 각지지 않는다.
## - 설정에서 끄면 (GameSettings.trails) 아무것도 그리지 않는다.
##
## 쓰는 법: SwingTrail.attach(붙일 곳, 끝 노드, 손잡이 노드, 무기 이름) 후 emitting 을 켜고 끈다.
## 붙일 곳이 카메라면 1인칭 화면 기준으로 남고, null 이면 경기장(세계)에 남는다.

## 무기마다 자취 모양.
##   life : 자취가 남는 시간(초)   base : 손잡이 쪽 점이 끝에서 얼마나 떨어졌나 (0 = 끝, 1 = 손잡이)
##   head : 앞쪽 색   tail : 뒤쪽 색 (차갑게)   alpha : 가장 진한 곳의 불투명도
const STYLES := {
	# 칼: 넓고 긴 자취. 하얀 금빛에서 하늘색으로
	"sword": {"life": 0.2, "base": 0.62, "head": Color(1.0, 0.95, 0.72), "tail": Color(0.18, 0.55, 1.0), "alpha": 0.9},
	# 대검: 더 두껍고 오래 남는 묵직한 자취. 주황빛에서 짙은 남보라로
	"greatsword": {"life": 0.27, "base": 0.82, "head": Color(1.0, 0.78, 0.42), "tail": Color(0.32, 0.28, 0.95), "alpha": 0.92},
	# 단검: 짧고 빠른 자취 (두 손 모두)
	"daggers": {"life": 0.11, "base": 0.7, "head": Color(0.85, 1.0, 0.9), "tail": Color(0.05, 0.78, 0.8), "alpha": 0.88},
	# 창: 날 쪽만 가늘고 곧게
	"spear": {"life": 0.16, "base": 0.3, "head": Color(1.0, 0.97, 0.82), "tail": Color(0.15, 0.7, 1.0), "alpha": 0.9},
	# 봉: 쥔 곳(가운데)부터 끝까지 둥근 호
	"staff": {"life": 0.22, "base": 0.58, "head": Color(1.0, 0.85, 0.5), "tail": Color(0.55, 0.3, 1.0), "alpha": 0.82},
	# 수리검 들고 근접: 가는 자취
	"shuriken": {"life": 0.1, "base": 0.6, "head": Color(0.92, 0.96, 1.0), "tail": Color(0.25, 0.65, 1.0), "alpha": 0.82},
	# 맨몸: 주먹 끝에 아주 짧은 번쩍임
	"fists": {"life": 0.08, "base": 1.0, "head": Color(1.0, 0.92, 0.6), "tail": Color(1.0, 0.45, 0.15), "alpha": 0.85},
	# 날아가는 수리검 뒤의 가는 꼬리
	"star_tail": {"life": 0.14, "base": 1.0, "head": Color(0.9, 0.96, 1.0), "tail": Color(0.2, 0.6, 1.0), "alpha": 0.75},
}

## 필살기는 더 진하고 오래 남는다
const SPECIAL_BOOST := {"life": 1.5, "alpha": 1.15}

const SUBDIV := 3           # 두 점 사이를 곡선으로 몇 번 더 나눌지
const MAX_POINTS := 48      # 너무 오래 휘둘러도 이 이상은 기억하지 않는다

var tip: Node3D
var base: Node3D
var emitting := false:
	set(v):
		if v and not emitting:
			_seg += 1     # 새로 휘두르면 앞 자취와 잇지 않는다
		emitting = v
var boost := false         # 필살기 중
var auto_free := false     # 끝 노드가 사라지고 자취도 다 사라지면 스스로 지운다 (날아가는 수리검)
var style := {}

var _pts: Array = []       # [끝 위치, 손잡이 위치, 나이, 몇 번째 휘두름]
var _seg := 0
var _im := ImmediateMesh.new()


## 자취를 만들어 붙인다. space 가 null 이면 owner_node 아래에 세계 기준으로 둔다.
static func attach(space: Node3D, owner_node: Node, tip_node: Node3D, base_node: Node3D, weapon: String) -> SwingTrail:
	var t := SwingTrail.new()
	t.tip = tip_node
	t.base = base_node
	t.style = STYLES.get(weapon, STYLES.sword)
	if space != null:
		space.add_child(t)
	else:
		t.top_level = true
		owner_node.add_child(t)
		t.global_transform = Transform3D.IDENTITY
	return t


## 손잡이 쪽 점을 무기 끝과 같은 부모 안에 만든다 (style.base 만큼 손잡이 쪽으로)
static func make_base(tip_node: Node3D, weapon: String) -> Node3D:
	var b := Node3D.new()
	var k: float = float(STYLES.get(weapon, STYLES.sword).base)
	b.position = tip_node.position * (1.0 - k)
	tip_node.get_parent().add_child(b)
	return b


func _ready() -> void:
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.disable_receive_shadows = true
	m.disable_fog = true
	material_override = m
	extra_cull_margin = 16.0
	if top_level:
		global_transform = Transform3D.IDENTITY


func _process(delta: float) -> void:
	if not GameSettings.trails:
		if not _pts.is_empty():
			_pts.clear()
			_im.clear_surfaces()
		return
	var life := float(style.life) * (SPECIAL_BOOST.life if boost else 1.0)
	for p in _pts:
		p[2] += delta
	while not _pts.is_empty() and _pts[0][2] > life:
		_pts.pop_front()
	if auto_free and not is_instance_valid(tip) and _pts.is_empty():
		queue_free()
		return
	if emitting and is_instance_valid(tip) and is_instance_valid(base) and tip.is_visible_in_tree():
		_pts.append([to_local(tip.global_position), to_local(base.global_position), 0.0, _seg])
		if _pts.size() > MAX_POINTS:
			_pts.pop_front()
	_rebuild(life)


## 지금 남은 자취를 다시 그린다
func _rebuild(life: float) -> void:
	_im.clear_surfaces()
	if _pts.size() < 2:
		return
	var head: Color = style.head
	var tail: Color = style.tail
	var alpha := minf(float(style.alpha) * (SPECIAL_BOOST.alpha if boost else 1.0), 0.95)
	var began := false
	var i := 0
	while i < _pts.size() - 1:
		# 같은 휘두름끼리만 잇는다
		if _pts[i][3] != _pts[i + 1][3]:
			i += 1
			continue
		var p0: Array = _pts[i - 1] if i > 0 and _pts[i - 1][3] == _pts[i][3] else _pts[i]
		var p1: Array = _pts[i]
		var p2: Array = _pts[i + 1]
		var p3: Array = _pts[i + 2] if i + 2 < _pts.size() and _pts[i + 2][3] == _pts[i][3] else p2
		for s in SUBDIV:
			var a := float(s) / SUBDIV
			var b := float(s + 1) / SUBDIV
			var ta := _cr(p0[0], p1[0], p2[0], p3[0], a)
			var ba := _cr(p0[1], p1[1], p2[1], p3[1], a)
			var tb := _cr(p0[0], p1[0], p2[0], p3[0], b)
			var bb := _cr(p0[1], p1[1], p2[1], p3[1], b)
			var age_a := clampf(lerpf(p1[2], p2[2], a) / life, 0.0, 1.0)
			var age_b := clampf(lerpf(p1[2], p2[2], b) / life, 0.0, 1.0)
			if not began:
				_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				began = true
			_quad(ta, ba, age_a, tb, bb, age_b, head, tail, alpha)
		i += 1
	if began:
		_im.surface_end()


## 한 칸(사각형 = 삼각형 두 개). 뒤로 갈수록(나이가 많을수록) 손잡이 쪽 점이 끝으로 모여 가늘어진다.
func _quad(ta: Vector3, ba: Vector3, age_a: float, tb: Vector3, bb: Vector3, age_b: float,
		head: Color, tail: Color, alpha: float) -> void:
	var wa := 1.0 - age_a
	var wb := 1.0 - age_b
	var ia := ta.lerp(ba, wa * wa)          # 안쪽 가장자리 (가늘어짐)
	var ib := tb.lerp(bb, wb * wb)
	var ca := _col(head, tail, age_a, alpha)
	var cb := _col(head, tail, age_b, alpha)
	# 날 끝이 지나간 바깥선이 가장 밝다: 바깥 띠(폭의 18%)는 진하게, 안쪽은 손잡이 쪽으로 옅어진다
	var ea := ta.lerp(ia, 0.18)
	var eb := tb.lerp(ib, 0.18)
	var ca_edge := Color(ca.lerp(Color.WHITE, 0.35 * (1.0 - age_a)), minf(ca.a * 1.1, 1.0))
	var cb_edge := Color(cb.lerp(Color.WHITE, 0.35 * (1.0 - age_b)), minf(cb.a * 1.1, 1.0))
	var ca_mid := Color(ca, ca.a * 0.55)
	var cb_mid := Color(cb, cb.a * 0.55)
	var ca_in := Color(ca, 0.0)
	var cb_in := Color(cb, 0.0)
	_v(ta, ca_edge); _v(tb, cb_edge); _v(eb, cb_mid)
	_v(ta, ca_edge); _v(eb, cb_mid); _v(ea, ca_mid)
	_v(ea, ca_mid); _v(eb, cb_mid); _v(ib, cb_in)
	_v(ea, ca_mid); _v(ib, cb_in); _v(ia, ca_in)


func _col(head: Color, tail: Color, age: float, alpha: float) -> Color:
	var c := head.lerp(tail, smoothstep(0.0, 0.5, age))
	c.a = alpha * pow(1.0 - age, 1.3)
	return c


func _v(p: Vector3, c: Color) -> void:
	_im.surface_set_color(c)
	_im.surface_add_vertex(p)


## 네 점을 지나는 부드러운 곡선 (Catmull-Rom)
static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## 남은 자취를 바로 지운다 (죽거나 장면이 바뀔 때)
func clear() -> void:
	_pts.clear()
	_im.clear_surfaces()
	emitting = false


## 지금 그리고 있는 자취의 점 개수 (점검용)
func point_count() -> int:
	return _pts.size()
