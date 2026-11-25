class_name BreakablePillar
extends StaticBody3D
## 부서지는 돌기둥. 칼로 몇 번 치면 금이 가다가 쓰러진다.
## 위에 서 있던 사람은 떨어진다. 강한 공격(내려찍기, 차지, 낙하 찍기)은 두 번 친 만큼 부순다.
## 칼에 맞도록 충돌 층 2(맞을 수 있는 것)에도 들어 있다.

signal broken(pillar_id: String)

const HP := 5
const STRONG := ["heavy", "charge", "plunge", "slash3", "ledge_slash"]

var id := ""
var hp := HP
var size := Vector3.ONE
var _visual: Node3D
var _cracks: Array[MeshInstance3D] = []
var _audio: AudioStreamPlayer3D


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
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = Sfx.thud(0.3, true)
	_audio.unit_size = 10.0
	add_child(_audio)


## 칼(또는 낙하 찍기)에 맞았다. 플레이어/AI 공격이 같은 방법으로 부른다.
func take_hit(info: Dictionary, dir: Vector3, _attacker: Node3D = null) -> String:
	if hp <= 0:
		return "none"
	hp -= 2 if info.get("move", "") in STRONG else 1
	for i in _cracks.size():
		_cracks[i].visible = i < HP - hp
	_audio.pitch_scale = randf_range(0.8, 1.0)
	_audio.play()
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
	var axis := Vector3.UP.cross(dir.normalized() if dir.length() > 0.1 else Vector3.RIGHT).normalized()
	var tw := create_tween()
	tw.tween_property(_visual, "basis", Basis(axis, deg_to_rad(88)), 0.9).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		Fx.impact(get_parent(), global_position + dir * size.y * 0.6 + Vector3.DOWN * size.y * 0.4, Vector3.UP,
				Color(0.82, 0.72, 0.56), 40)
		_audio.pitch_scale = 0.6
		_audio.play())
	tw.tween_property(_visual, "position:y", -size.y * 0.5 - 3.0, 1.6).set_delay(0.6)
	tw.tween_callback(func(): _visual.visible = false)
