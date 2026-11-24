class_name Player
extends CharacterBody3D
## 1인칭 플레이어: 걷기, 달리기, 점프, 마우스 시점, 칼 휘두르기.

signal stamina_changed(value: float, max_value: float)
signal swung

# --- 이동 ---
const WALK_SPEED := 4.6
const SPRINT_SPEED := 7.6
const GROUND_ACCEL := 14.0
const AIR_ACCEL := 3.5
const JUMP_VELOCITY := 5.4
const COYOTE_TIME := 0.12      # 발이 떨어진 직후에도 잠깐 점프 가능
const JUMP_BUFFER := 0.12      # 착지 직전에 누른 점프도 받아줌
const MOUSE_SENS := 0.0022
const WEAPON_REST := Vector3(0.3, -0.3, -0.5)   # 화면에서 칼이 놓이는 자리

# --- 기력 ---
const MAX_STAMINA := 100.0
const SPRINT_COST := 18.0      # 초당
const JUMP_COST := 8.0
const STAMINA_REGEN := 28.0    # 초당
const REGEN_DELAY := 0.7

# --- 공격 ---
# 약공격(왼쪽 클릭)은 좌우 번갈아 베기, 강공격(오른쪽 클릭)은 내려찍기.
const ATTACKS := {
	"light": {"windup": 0.09, "active": 0.12, "recover": 0.22, "damage": 12, "cost": 10.0, "reach": 2.3},
	"heavy": {"windup": 0.28, "active": 0.14, "recover": 0.38, "damage": 30, "cost": 24.0, "reach": 2.5},
}

var stamina := MAX_STAMINA
var _regen_wait := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _bob_t := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _attack_name := ""
var _attack_phase := ""        # "windup" / "active" / "recover" / ""
var _attack_timer := 0.0
var _combo_side := 1.0
var _already_hit := {}
var _queued_attack := ""
var _shake := 0.0

var head: Node3D
var camera: Camera3D
var _weapon_root: Node3D       # 화면에 보이는 칼의 기준점
var _weapon_pivot: Node3D      # 휘두를 때 돌아가는 부분
var _trail: MeshInstance3D
var _swing_audio: AudioStreamPlayer
var _whoosh_light: AudioStreamWAV
var _whoosh_heavy: AudioStreamWAV
var _hit_query := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1 | 2
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)

	head = Node3D.new()
	head.position.y = 1.62
	add_child(head)
	camera = Camera3D.new()
	camera.fov = 78.0
	camera.near = 0.03
	camera.current = true
	head.add_child(camera)

	_build_sword()

	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.3, 2.4)
	_hit_query.shape = box
	_hit_query.collision_mask = 2
	_hit_query.exclude = [get_rid()]

	_whoosh_light = Sfx.whoosh(0.2, 1.0)
	_whoosh_heavy = Sfx.whoosh(0.32, 0.7)
	_swing_audio = AudioStreamPlayer.new()
	_swing_audio.volume_db = -6.0
	add_child(_swing_audio)


func _build_sword() -> void:
	_weapon_root = Node3D.new()
	_weapon_root.position = WEAPON_REST
	_weapon_root.scale = Vector3.ONE * 0.72
	camera.add_child(_weapon_root)
	_weapon_pivot = Node3D.new()
	_weapon_root.add_child(_weapon_pivot)

	var steel := LowPoly.mat(Color(0.78, 0.80, 0.84), 0.28, 0.85)
	var edge := LowPoly.mat(Color(0.92, 0.94, 0.97), 0.18, 0.9)
	var brass := LowPoly.mat(Color(0.72, 0.55, 0.25), 0.4, 0.8)
	var leather := LowPoly.mat(Color(0.28, 0.16, 0.10), 0.9)

	# 칼은 손잡이가 기준점, 칼날은 +Y 방향으로 뻗는다.
	var sword := Node3D.new()
	sword.rotation_degrees = Vector3(-62, 8, -8)
	_weapon_pivot.add_child(sword)
	LowPoly.part(sword, LowPoly.cyl(0.022, 0.025, 0.2, 6), leather, Vector3(0, 0.0, 0))
	LowPoly.part(sword, LowPoly.sphere(0.034, 6, 4), brass, Vector3(0, -0.12, 0))
	LowPoly.part(sword, LowPoly.box(Vector3(0.24, 0.03, 0.05)), brass, Vector3(0, 0.115, 0))
	LowPoly.part(sword, LowPoly.box(Vector3(0.05, 0.035, 0.035)), brass, Vector3(0.13, 0.12, 0), Vector3(0, 0, 25))
	LowPoly.part(sword, LowPoly.box(Vector3(0.05, 0.035, 0.035)), brass, Vector3(-0.13, 0.12, 0), Vector3(0, 0, -25))
	LowPoly.part(sword, LowPoly.box(Vector3(0.062, 0.78, 0.014)), steel, Vector3(0, 0.52, 0))
	LowPoly.part(sword, LowPoly.box(Vector3(0.012, 0.76, 0.018)), edge, Vector3(0, 0.52, 0))
	LowPoly.part(sword, LowPoly.prism(Vector3(0.062, 0.12, 0.014)), steel, Vector3(0, 0.97, 0))

	# 휘두를 때 남는 잔상
	_trail = MeshInstance3D.new()
	var trail_mesh := LowPoly.box(Vector3(0.02, 0.7, 0.002))
	_trail.mesh = trail_mesh
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.albedo_color = Color(1, 1, 1, 0.0)
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail.material_override = tm
	_trail.position = Vector3(0, 0.55, 0)
	sword.add_child(_trail)


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENS)
		head.rotate_x(-event.relative.y * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-88), deg_to_rad(88))
	elif event.is_action_pressed("attack"):
		_request_attack("light")
	elif event.is_action_pressed("heavy_attack"):
		_request_attack("heavy")


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= _gravity * delta
		_coyote -= delta
	else:
		_coyote = COYOTE_TIME

	# 점프
	_jump_buffer -= delta
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
	if _jump_buffer > 0.0 and _coyote > 0.0 and stamina >= JUMP_COST * 0.5:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
		_use_stamina(JUMP_COST)

	# 이동 방향
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var wants_sprint := Input.is_action_pressed("sprint") and input.y < 0.0 and stamina > 0.0
	var speed := SPRINT_SPEED if wants_sprint else WALK_SPEED
	if _attack_phase != "":
		speed *= 0.6   # 공격 중엔 조금 느려짐
	var accel := GROUND_ACCEL if on_floor else AIR_ACCEL
	var target := dir * speed
	velocity.x = lerpf(velocity.x, target.x, clampf(accel * delta, 0, 1))
	velocity.z = lerpf(velocity.z, target.z, clampf(accel * delta, 0, 1))
	move_and_slide()

	# 기력
	if wants_sprint and dir != Vector3.ZERO and on_floor:
		_use_stamina(SPRINT_COST * delta)
	elif _regen_wait > 0.0:
		_regen_wait -= delta
	elif stamina < MAX_STAMINA:
		stamina = minf(stamina + STAMINA_REGEN * delta, MAX_STAMINA)
		stamina_changed.emit(stamina, MAX_STAMINA)

	_update_attack(delta)
	_update_camera(delta, on_floor, wants_sprint)


func _use_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_regen_wait = REGEN_DELAY
	stamina_changed.emit(stamina, MAX_STAMINA)


# ---------------- 공격 ----------------

func _request_attack(kind: String) -> void:
	if _attack_phase == "":
		_start_attack(kind)
	elif _attack_phase == "recover" or _attack_phase == "active":
		_queued_attack = kind   # 다음 공격 미리 입력


func _start_attack(kind: String) -> void:
	var data: Dictionary = ATTACKS[kind]
	if stamina < data.cost * 0.5:
		return
	_use_stamina(data.cost)
	_attack_name = kind
	_attack_phase = "windup"
	_attack_timer = data.windup
	_already_hit.clear()
	if kind == "light":
		_combo_side = -_combo_side
	_animate_swing(kind, data)


func _animate_swing(kind: String, data: Dictionary) -> void:
	var tw := create_tween()
	var p := _weapon_pivot
	if kind == "light":
		var s := _combo_side
		# 준비 → 베기 → 원위치
		tw.tween_property(p, "rotation", Vector3(deg_to_rad(10), deg_to_rad(55) * s, deg_to_rad(35) * s), data.windup) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(p, "position", Vector3(0.12 * s, 0.05, 0.05), data.windup)
		tw.tween_property(p, "rotation", Vector3(deg_to_rad(-25), deg_to_rad(-75) * s, deg_to_rad(-55) * s), data.active) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(p, "position", Vector3(-0.3 * s, -0.04, -0.12), data.active)
	else:
		tw.tween_property(p, "rotation", Vector3(deg_to_rad(65), deg_to_rad(10), deg_to_rad(-8)), data.windup) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(p, "position", Vector3(-0.12, 0.18, 0.12), data.windup)
		tw.tween_property(p, "rotation", Vector3(deg_to_rad(-95), deg_to_rad(-6), deg_to_rad(4)), data.active) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(p, "position", Vector3(-0.2, -0.22, -0.2), data.active)
	tw.tween_property(p, "rotation", Vector3.ZERO, data.recover).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(p, "position", Vector3.ZERO, data.recover)


func _update_attack(delta: float) -> void:
	var trail_mat: StandardMaterial3D = _trail.material_override
	trail_mat.albedo_color.a = move_toward(trail_mat.albedo_color.a, 0.0, delta * 4.0)
	if _attack_phase == "":
		return
	var data: Dictionary = ATTACKS[_attack_name]
	_attack_timer -= delta
	if _attack_phase == "windup" and _attack_timer <= 0.0:
		_attack_phase = "active"
		_attack_timer = data.active
		_swing_audio.stream = _whoosh_heavy if _attack_name == "heavy" else _whoosh_light
		_swing_audio.pitch_scale = randf_range(0.92, 1.08)
		_swing_audio.play()
		swung.emit()
	elif _attack_phase == "active":
		trail_mat.albedo_color.a = 0.35
		_check_hits(data)
		if _attack_timer <= 0.0:
			_attack_phase = "recover"
			_attack_timer = data.recover
	elif _attack_phase == "recover":
		# 다음 공격이 예약돼 있으면 회복 동작 중간에 이어서 휘두른다.
		if _queued_attack != "" and _attack_timer <= data.recover * 0.55:
			var next := _queued_attack
			_queued_attack = ""
			_attack_phase = ""
			_start_attack(next)
		elif _attack_timer <= 0.0:
			_attack_phase = ""


func _check_hits(data: Dictionary) -> void:
	var fwd := -camera.global_transform.basis.z
	var center: Vector3 = camera.global_position + fwd * float(data.reach) * 0.5
	_hit_query.transform = Transform3D(camera.global_transform.basis, center)
	var results := get_world_3d().direct_space_state.intersect_shape(_hit_query, 8)
	for r in results:
		var body: Object = r.collider
		if body == null or _already_hit.has(body.get_instance_id()):
			continue
		if not body.has_method("take_hit"):
			continue
		_already_hit[body.get_instance_id()] = true
		var to_target: Vector3 = (body.global_position - global_position)
		to_target.y = 0
		var hit_dir := to_target.normalized() if to_target.length() > 0.01 else fwd
		var dmg: int = data.damage + randi_range(-2, 2)
		body.take_hit(dmg, hit_dir, _attack_name == "heavy")
		_on_hit_landed(_attack_name == "heavy")


func _on_hit_landed(heavy: bool) -> void:
	_shake = 0.6 if heavy else 0.3
	# 타격감: 아주 잠깐 시간을 멈춘다 (히트스톱)
	Engine.time_scale = 0.05
	await get_tree().create_timer(0.07 if heavy else 0.04, true, false, true).timeout
	Engine.time_scale = 1.0


# ---------------- 카메라 ----------------

func _update_camera(delta: float, on_floor: bool, sprinting: bool) -> void:
	var horiz := Vector2(velocity.x, velocity.z).length()
	# 걸을 때 화면이 살짝 흔들림
	if on_floor and horiz > 0.5:
		_bob_t += delta * horiz * 1.9
	else:
		_bob_t = lerpf(_bob_t, roundf(_bob_t / PI) * PI, clampf(delta * 6.0, 0, 1))
	var bob_amt := 0.045 if sprinting else 0.03
	var bob := Vector3(cos(_bob_t * 0.5) * bob_amt * 0.6, absf(sin(_bob_t)) * bob_amt, 0)
	# 맞혔을 때 화면 흔들림
	_shake = maxf(_shake - delta * 3.5, 0.0)
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * _shake * 0.05
	camera.position = camera.position.lerp(bob, clampf(delta * 12.0, 0, 1)) + shake
	# 달릴 때 시야가 살짝 넓어짐
	var target_fov := 86.0 if sprinting and horiz > WALK_SPEED else 78.0
	camera.fov = lerpf(camera.fov, target_fov, clampf(delta * 6.0, 0, 1))
	# 칼도 걸음에 맞춰 살짝 흔들림
	_weapon_root.position = WEAPON_REST + Vector3(bob.x * 0.5, -bob.y * 0.6, 0)
