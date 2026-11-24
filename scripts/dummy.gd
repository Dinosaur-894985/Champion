class_name TrainingDummy
extends StaticBody3D
## 연습용 허수아비. 맞으면 흔들리고, 체력이 다 닳으면 쓰러졌다가 다시 일어난다.

signal hit_taken(damage: int)
signal knocked_down

const MAX_HP := 100
const RESPAWN_TIME := 3.0

var hp := MAX_HP
var down := false

var _pivot: Node3D
var _body_meshes: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D
var _hp_root: Node3D
var _hp_fill: MeshInstance3D
var _wobble := Vector2.ZERO       # 흔들리는 각도 (x: 앞뒤, y: 좌우)
var _wobble_vel := Vector2.ZERO
var _flash := 0.0
var _audio: AudioStreamPlayer3D
var _thud_light: AudioStreamWAV
var _thud_heavy: AudioStreamWAV


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	_build()
	_thud_light = Sfx.thud(0.18, false)
	_thud_heavy = Sfx.thud(0.26, true)
	_audio = AudioStreamPlayer3D.new()
	_audio.unit_size = 6.0
	add_child(_audio)


func _build() -> void:
	var wood := LowPoly.mat(Color(0.45, 0.30, 0.18), 0.9)
	var wood_dark := LowPoly.mat(Color(0.32, 0.21, 0.13), 0.9)
	var straw := LowPoly.mat(Color(0.80, 0.66, 0.38), 0.95)
	var burlap := LowPoly.mat(Color(0.66, 0.52, 0.34), 0.95)
	var rope := LowPoly.mat(Color(0.55, 0.42, 0.25), 0.9)
	var paint := LowPoly.mat(Color(0.72, 0.16, 0.12), 0.8)
	_flash_mat = LowPoly.mat(Color(1, 0.95, 0.88, 0.0))
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var s := get_instance_id()

	# 바닥 받침 (움직이지 않음)
	LowPoly.part(self, LowPoly.box(Vector3(1.1, 0.12, 0.18)), wood_dark, Vector3(0, 0.06, 0))
	LowPoly.part(self, LowPoly.box(Vector3(0.18, 0.12, 1.1)), wood_dark, Vector3(0, 0.06, 0))
	LowPoly.part(self, LowPoly.cyl(0.13, 0.16, 0.14, 8), wood_dark, Vector3(0, 0.17, 0))

	# 흔들리는 부분
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 0.2, 0)
	add_child(_pivot)

	LowPoly.part(_pivot, LowPoly.cyl(0.06, 0.075, 1.9, 7), wood, Vector3(0, 0.95, 0), Vector3.ZERO, 0.006, s)
	_body_meshes.append(LowPoly.part(_pivot, LowPoly.cyl(0.24, 0.30, 0.95, 9, 3), burlap,
			Vector3(0, 1.05, 0), Vector3.ZERO, 0.025, s + 1))
	# 허리, 가슴 밧줄
	for y in [0.72, 1.36]:
		var band := TorusMesh.new()
		band.inner_radius = 0.27 if y < 1.0 else 0.235
		band.outer_radius = band.inner_radius + 0.045
		band.rings = 12
		band.ring_segments = 4
		LowPoly.part(_pivot, band, rope, Vector3(0, y, 0))
	# 가슴의 과녁 표시
	LowPoly.part(_pivot, LowPoly.cyl(0.11, 0.11, 0.02, 10), paint, Vector3(0, 1.15, 0.27), Vector3(90, 0, 0))
	LowPoly.part(_pivot, LowPoly.cyl(0.05, 0.05, 0.03, 8), straw, Vector3(0, 1.15, 0.28), Vector3(90, 0, 0))
	# 팔 (가로 막대 + 짚 뭉치)
	LowPoly.part(_pivot, LowPoly.cyl(0.045, 0.045, 1.25, 6), wood, Vector3(0, 1.42, 0), Vector3(0, 0, 90))
	for side in [-1.0, 1.0]:
		_body_meshes.append(LowPoly.part(_pivot, LowPoly.cyl(0.07, 0.09, 0.3, 7), straw,
				Vector3(side * 0.58, 1.42, 0), Vector3(0, 0, 90), 0.015, s + 2 + int(side)))
	# 머리
	_body_meshes.append(LowPoly.part(_pivot, LowPoly.sphere(0.19, 9, 6), burlap,
			Vector3(0, 1.78, 0), Vector3.ZERO, 0.01, s + 5))
	LowPoly.part(_pivot, LowPoly.cyl(0.03, 0.1, 0.14, 6), straw, Vector3(0, 1.98, 0), Vector3.ZERO, 0.01, s + 6)

	# 부딪힘 판정 (몸통 + 머리)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.34
	shape.height = 1.9
	col.shape = shape
	col.position = Vector3(0, 1.15, 0)
	add_child(col)

	# 체력 막대
	_hp_root = Node3D.new()
	_hp_root.position = Vector3(0, 2.45, 0)
	add_child(_hp_root)
	var bg := MeshInstance3D.new()
	bg.mesh = LowPoly.box(Vector3(0.74, 0.08, 0.01))
	var bg_mat := LowPoly.mat(Color(0.08, 0.08, 0.08))
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg.material_override = bg_mat
	_hp_root.add_child(bg)
	_hp_fill = MeshInstance3D.new()
	_hp_fill.mesh = LowPoly.box(Vector3(0.7, 0.05, 0.01))
	var fill_mat := LowPoly.mat(Color(0.85, 0.2, 0.15))
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_fill.material_override = fill_mat
	_hp_fill.position.z = 0.008
	_hp_root.add_child(_hp_fill)


## 칼에 맞았을 때 불린다. dir 은 맞은 방향 (공격자 → 허수아비).
func take_hit(damage: int, dir: Vector3, heavy: bool) -> void:
	if down:
		return
	hp = max(hp - damage, 0)
	var local_dir := global_transform.basis.inverse() * dir
	var push := (0.9 if heavy else 0.5)
	_wobble_vel += Vector2(local_dir.z, -local_dir.x) * push * 9.0
	_flash = 1.0
	_audio.stream = _thud_heavy if heavy else _thud_light
	_audio.pitch_scale = randf_range(0.9, 1.1)
	_audio.play()
	_spawn_number(damage, heavy)
	hit_taken.emit(damage)
	if hp <= 0:
		_fall(local_dir)


func _fall(local_dir: Vector3) -> void:
	down = true
	knocked_down.emit()
	var dir2 := Vector2(local_dir.z, -local_dir.x)
	if dir2.length() < 0.1:
		dir2 = Vector2(1, 0)
	dir2 = dir2.normalized()
	_wobble_vel = Vector2.ZERO
	var tw := create_tween()
	tw.tween_property(self, "_wobble", dir2 * deg_to_rad(82.0), 0.55) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(RESPAWN_TIME)
	tw.tween_property(self, "_wobble", Vector2.ZERO, 0.6) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		hp = MAX_HP
		down = false)


func _spawn_number(damage: int, heavy: bool) -> void:
	var label := Label3D.new()
	label.text = str(damage)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 96 if heavy else 72
	label.outline_size = 18
	label.pixel_size = 0.003
	label.modulate = Color(1.0, 0.85, 0.3) if heavy else Color(1, 1, 1)
	label.outline_modulate = Color(0.15, 0.05, 0.0)
	add_child(label)
	label.position = Vector3(randf_range(-0.25, 0.25), 2.0, randf_range(-0.1, 0.1))
	var tw := label.create_tween().set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y + 0.7, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.tween_property(label, "outline_modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(label.queue_free)


func _process(delta: float) -> void:
	# 스프링처럼 흔들리다가 제자리로 돌아온다.
	if not down:
		var k := 60.0
		var damping := 5.5
		_wobble_vel += (-_wobble * k - _wobble_vel * damping) * delta
		_wobble += _wobble_vel * delta
		_wobble = _wobble.clamp(Vector2(-0.6, -0.6), Vector2(0.6, 0.6))
	_pivot.rotation = Vector3(_wobble.x, 0, _wobble.y)

	# 맞았을 때 하얗게 번쩍
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 7.0, 0.0)
		_flash_mat.albedo_color.a = _flash * 0.85
		for m in _body_meshes:
			m.material_overlay = _flash_mat if _flash > 0.0 else null

	# 체력 막대는 항상 카메라를 바라본다
	var hp_ratio := float(hp) / MAX_HP
	_hp_fill.scale.x = maxf(hp_ratio, 0.001)
	_hp_fill.position.x = -0.35 * (1.0 - hp_ratio)
	_hp_root.visible = not down and hp < MAX_HP
	var cam := get_viewport().get_camera_3d()
	if cam and _hp_root.visible:
		var target := cam.global_position
		target.y = _hp_root.global_position.y
		if target.distance_to(_hp_root.global_position) > 0.01:
			_hp_root.look_at(target, Vector3.UP, true)
