class_name BreakablePillar
extends StaticBody3D
## 부서지는 돌기둥. 칼로 몇 번 치면 금이 가다가 쓰러진다.
## 위에 서 있던 사람은 떨어진다. 강한 공격(내려찍기, 차지, 낙하 찍기)은 두 번 친 만큼 부순다.
## 칼에 맞도록 충돌 층 2(맞을 수 있는 것)에도 들어 있다.
## 쓰러지는 쪽(친 방향)에 있던 사람은 깔려서 크게 다치고 넘어진다. 쓰러지기 시작할 때 금이 번쩍이고
## 땅이 울려서 피할 틈(약 0.9초)이 있다. 누가 부쉈든 깔리면 똑같이 다친다.

signal broken(pillar_id: String)

const HP := 5
const STRONG := ["heavy", "charge", "plunge", "slash3", "ledge_slash"]

const CRUSH_DAMAGE := 24

var id := ""
var arena: Node3D               # 깔리는 사람을 찾을 때 (Arena.fighters)
var hp := HP
var size := Vector3.ONE
var _visual: Node3D
var _cracks: Array[MeshInstance3D] = []


func setup(pillar_id: String, center: Vector3, s: Vector3, mats: Dictionary) -> void:
	id = pillar_id
	size = s
	position = center
	collision_layer = 1 | 2
	collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = s
	col.shape = shape
	add_child(col)
	# 쓰러질 때 밑동을 축으로 돌도록 모양은 밑동 기준으로 붙인다
	_visual = Node3D.new()
	_visual.position = Vector3(0, -s.y * 0.5, 0)
	add_child(_visual)
	var h := s.y
	LowPoly.part(_visual, LowPoly.box(Vector3(s.x, h, s.z)), mats.sand, Vector3(0, h * 0.5, 0), Vector3.ZERO, 0.03, 11)
	LowPoly.part(_visual, LowPoly.box(Vector3(s.x + 0.25, 0.4, s.z + 0.25)), mats.stone2, Vector3(0, 0.2, 0))
	LowPoly.part(_visual, LowPoly.box(Vector3(s.x + 0.2, 0.3, s.z + 0.2)), mats.coral, Vector3(0, h - 0.15, 0))
	# 금 간 띠: 부서지는 기둥이라는 표시 (청록 대신 모래색 + 갈라진 무늬)
	for y in [1.3, 2.6]:
		LowPoly.part(_visual, LowPoly.box(Vector3(s.x + 0.04, 0.12, s.z + 0.04)), mats.navy, Vector3(0, y, 0))
	# 손잡이 (타고 오를 수 있다)
	for f in 4:
		var d := Vector3(cos(f * PI * 0.5), 0, sin(f * PI * 0.5))
		var along := Vector3(-d.z, 0, d.x)
		for k in int(h / 1.0):
			var p := Vector3(0, 0.7 + k * 1.0, 0) + d * (s.x * 0.5 + 0.03) + along * (0.25 if k % 2 == 0 else -0.25)
			var hold := LowPoly.part(_visual, LowPoly.box(Vector3(0.22, 0.14, 0.1)), mats.navy, p)
			hold.rotation.y = f * PI * 0.5 + PI * 0.5
	# 맞을수록 드러나는 금
	var crack_mat := LowPoly.mat(Color(0.25, 0.18, 0.14))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pillar_id)
	for i in HP - 1:
		var f := i % 4
		var d := Vector3(cos(f * PI * 0.5), 0, sin(f * PI * 0.5))
		var c := LowPoly.part(_visual, LowPoly.box(Vector3(0.06, rng.randf_range(0.9, 1.6), 0.03)), crack_mat,
				Vector3(0, rng.randf_range(1.0, h - 1.0), 0) + d * (s.x * 0.5 + 0.02))
		c.rotation = Vector3(0, f * PI * 0.5 + PI * 0.5, rng.randf_range(-0.6, 0.6))
		c.visible = false
		_cracks.append(c)


## 칼(또는 낙하 찍기)에 맞았다. 플레이어/AI 공격이 같은 방법으로 부른다.
func take_hit(info: Dictionary, dir: Vector3, _attacker: Node3D = null) -> String:
	if hp <= 0:
		return "none"
	hp -= 2 if info.get("move", "") in STRONG else 1
	for i in _cracks.size():
		_cracks[i].visible = i < HP - hp
	Audio.play("pillar_crack", global_position + Vector3.UP * 1.5)
	Fx.impact(get_parent(), global_position + Vector3(0, 0.3, 0) - dir * size.x * 0.5, -dir + Vector3.UP * 0.5,
			Color(0.82, 0.72, 0.56), 14)
	var tw := create_tween()
	tw.tween_property(_visual, "position:x", 0.06, 0.04)
	tw.tween_property(_visual, "position:x", -0.05, 0.05)
	tw.tween_property(_visual, "position:x", 0.0, 0.05)
	if hp <= 0:
		_break(dir)
	return "hit"


func is_broken() -> bool:
	return hp <= 0


func _break(dir: Vector3) -> void:
	collision_layer = 0
	broken.emit(id)
	var fall := Vector3(dir.x, 0, dir.z)
	fall = fall.normalized() if fall.length() > 0.1 else Vector3.RIGHT
	var axis := Vector3.UP.cross(fall).normalized()
	# 쓰러질 자리에 있는 사람에게 미리 알린다 (AI 는 옆으로 피한다)
	for f in _in_fall_zone(fall):
		if f.has_method("on_falling_hazard"):
			f.on_falling_hazard(axis, global_position)
	var tw := create_tween()
	tw.tween_property(_visual, "basis", Basis(axis, deg_to_rad(88)), 0.9).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		Fx.impact(get_parent(), global_position + fall * size.y * 0.6 + Vector3.DOWN * size.y * 0.4, Vector3.UP,
				Color(0.82, 0.72, 0.56), 40)
		Audio.play("pillar_break", global_position)
		_crush(fall))
	tw.tween_property(_visual, "position:y", -size.y * 0.5 - 3.0, 1.6).set_delay(0.6)
	tw.tween_callback(func(): _visual.visible = false)


## from 에서 쳐서 쓰러뜨리면 who 가 깔리나 (AI 가 노릴 때)
func would_crush(from: Vector3, who: Node3D) -> bool:
	var fall := global_position - from
	fall.y = 0
	if fall.length() < 0.1:
		return false
	return who in _in_fall_zone(fall.normalized())


## 쓰러지는 기둥이 덮치는 땅: 밑동에서 fall 쪽으로 기둥 길이만큼, 기둥 너비 + 여유
func _in_fall_zone(fall: Vector3) -> Array:
	var out := []
	if arena == null:
		return out
	var base := global_position - Vector3.UP * size.y * 0.5
	var side := Vector3(-fall.z, 0, fall.x)
	for f in arena.get("fighters"):
		var n := f as Node3D
		if n == null or not is_instance_valid(n) or n.get("dead"):
			continue
		var to := n.global_position - base
		var along := to.dot(fall)
		var across := absf(to.dot(side))
		if along > 0.4 and along < size.y + 0.6 and across < size.x * 0.5 + 0.7 and to.y < 2.5 and to.y > -1.5:
			out.append(n)
	return out


func _crush(fall: Vector3) -> void:
	for n in _in_fall_zone(fall):
		var info := {"move": "pillar", "damage": CRUSH_DAMAGE, "react": "stagger", "guard": "unblockable",
				"dir": "", "knockdown": true, "push_add": 3.0}
		if n.has_method("receive_attack"):
			n.receive_attack(info, self)
		elif n.has_method("take_hit"):
			n.take_hit(info, fall, self)
		if n.has_signal("combat_event"):
			n.emit_signal("combat_event", "기둥에 깔렸다!" if n is Player else "상대가 기둥에 깔렸다!", Color(1.0, 0.6, 0.3))
