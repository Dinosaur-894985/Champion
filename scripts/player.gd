class_name Player
extends CharacterBody3D
## 1인칭 플레이어: 걷기, 달리기, 대시, 점프, 마우스 시점, 베기, 막기와 튕겨내기.

signal stamina_changed(value: float, max_value: float)
signal hp_changed(value: int, max_value: int)
signal attack_started(kind: String)
signal took_damage(amount: int)
signal combat_event(text: String, color: Color)
signal died
signal attack_received(result: String)

# --- 이동 ---
const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const GROUND_ACCEL := 16.0
const AIR_ACCEL := 4.0
const JUMP_VELOCITY := 5.4
const COYOTE_TIME := 0.12      # 발이 떨어진 직후에도 잠깐 점프 가능
const JUMP_BUFFER := 0.12      # 착지 직전에 누른 점프도 받아줌
const MOUSE_SENS := 0.0022
const WEAPON_REST := Vector3(0.3, -0.3, -0.5)   # 화면에서 칼이 놓이는 자리

# --- 대시 (Shift 를 누르는 순간 순간이동하듯 튀어나감) ---
const DASH_SPEED := 15.0
const DASH_TIME := 0.17
const DASH_COST := 20.0
const DASH_COOLDOWN := 0.4
const DASH_IFRAMES := 0.17     # 대시 중에는 공격을 피한다

# --- 체력과 기력 ---
const MAX_HP := 100
const MAX_STAMINA := 100.0
const SPRINT_COST := 16.0      # 초당
const JUMP_COST := 8.0
const STAMINA_REGEN := 30.0    # 초당
const REGEN_DELAY := 0.7

# --- 막기 ---
const BLOCK_SPEED_MULT := 0.45
const PARRY_WINDOW := 0.2      # 막기를 누른 직후 이 시간 안에 맞으면 튕겨내기
const BLOCK_COST := {"light": 14.0, "heavy": 30.0}
const GUARD_BREAK_STUN := 0.8
const HIT_STUN := 0.3
const RECOIL_STUN := 0.4       # 내 공격이 막혔을 때
const PARRIED_STUN := 0.95     # 내 공격이 튕겨났을 때

# --- 공격 ---
# 약공격(왼쪽 클릭)은 좌우 번갈아 베기, 강공격(Q)은 내려찍기.
const ATTACKS := {
	"light": {"windup": 0.16, "active": 0.12, "recover": 0.24, "damage": 12, "cost": 10.0, "reach": 2.3},
	"heavy": {"windup": 0.42, "active": 0.14, "recover": 0.4, "damage": 26, "cost": 24.0, "reach": 2.5},
}

var hp := MAX_HP
var stamina := MAX_STAMINA
var controls_enabled := true
var dead := false
var blocking := false

var _regen_wait := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _bob_t := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _dash_t := 0.0
var _dash_cd := 0.0
var _dash_dir := Vector3.ZERO
var _iframes := 0.0
var _block_t := 0.0            # 막기를 시작한 뒤 지난 시간
var _stun := 0.0
var _kick := Vector3.ZERO      # 맞았을 때 카메라가 젖혀지는 정도

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
var _blade_tip: Node3D
var _weapon_tween: Tween
var _trail: MeshInstance3D
var _audio: AudioStreamPlayer
var _sounds := {}
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

	_sounds = {
		"light": Sfx.whoosh(0.2, 1.0),
		"heavy": Sfx.whoosh(0.32, 0.7),
		"dash": Sfx.whoosh(0.16, 1.4),
		"clang": Sfx.clang(0.45, 1.0),
		"parry": Sfx.clang(0.7, 1.25),
		"hurt": Sfx.hurt(),
	}
	_audio = AudioStreamPlayer.new()
	_audio.volume_db = -4.0
	_audio.max_polyphony = 4
	add_child(_audio)


func _play(snd: String, pitch: float = 1.0, volume: float = -4.0) -> void:
	_audio.stream = _sounds[snd]
	_audio.pitch_scale = pitch * randf_range(0.94, 1.06)
	_audio.volume_db = volume
	_audio.play()


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
	_blade_tip = Node3D.new()
	_blade_tip.position = Vector3(0, 0.6, 0)
	sword.add_child(_blade_tip)

	# 휘두를 때 남는 잔상
	_trail = MeshInstance3D.new()
	_trail.mesh = LowPoly.box(Vector3(0.02, 0.7, 0.002))
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.albedo_color = Color(1, 1, 1, 0.0)
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail.material_override = tm
	_trail.position = Vector3(0, 0.55, 0)
	sword.add_child(_trail)


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or dead:
		return
	if event is InputEventMouseMotion:
		# 브라우저에서 마우스를 잠근 직전/직후 한 번 크게 튀는 값이 들어올 수 있어 무시한다
		if event.relative.length() > 300.0:
			return
		rotate_y(-event.relative.x * MOUSE_SENS)
		head.rotate_x(-event.relative.y * MOUSE_SENS)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-88), deg_to_rad(88))
	elif not controls_enabled:
		return
	elif event.is_action_pressed("attack"):
		_request_attack("light")
	elif event.is_action_pressed("heavy_attack"):
		_request_attack("heavy")
	elif event.is_action_pressed("sprint"):
		try_dash()


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= _gravity * delta
		_coyote -= delta
	else:
		_coyote = COYOTE_TIME

	_stun = maxf(_stun - delta, 0.0)
	_iframes = maxf(_iframes - delta, 0.0)
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	var can_act := controls_enabled and not dead and _stun <= 0.0

	# 막기 (오른쪽 클릭을 누르고 있는 동안)
	var want_block := can_act and Input.is_action_pressed("block") and _attack_phase == "" and _dash_t <= 0.0
	if want_block != blocking:
		_set_blocking(want_block)
	if blocking:
		_block_t += delta

	# 점프
	_jump_buffer -= delta
	if can_act and Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
	if _jump_buffer > 0.0 and _coyote > 0.0 and stamina >= JUMP_COST * 0.5:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
		_use_stamina(JUMP_COST)

	# 이동 방향
	var input := Vector2.ZERO
	if controls_enabled and not dead:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var wants_sprint := can_act and Input.is_action_pressed("sprint") and input.y < 0.0 \
			and stamina > 0.0 and not blocking
	var speed := SPRINT_SPEED if wants_sprint else WALK_SPEED
	if _attack_phase != "":
		speed *= 0.6   # 공격 중엔 조금 느려짐
	if blocking:
		speed *= BLOCK_SPEED_MULT
	if _stun > 0.0:
		speed *= 0.35

	if _dash_t > 0.0:
		_dash_t -= delta
		var k := clampf(_dash_t / DASH_TIME, 0.0, 1.0)
		var dv := _dash_dir * lerpf(WALK_SPEED, DASH_SPEED, k)
		velocity.x = dv.x
		velocity.z = dv.z
	else:
		var accel := GROUND_ACCEL if on_floor else AIR_ACCEL
		var target := dir * speed
		velocity.x = lerpf(velocity.x, target.x, clampf(accel * delta, 0, 1))
		velocity.z = lerpf(velocity.z, target.z, clampf(accel * delta, 0, 1))
	move_and_slide()

	# 기력
	if wants_sprint and dir != Vector3.ZERO and on_floor and _dash_t <= 0.0:
		_use_stamina(SPRINT_COST * delta)
	elif _regen_wait > 0.0:
		_regen_wait -= delta
	elif stamina < MAX_STAMINA:
		var regen := STAMINA_REGEN * (0.5 if blocking else 1.0)
		stamina = minf(stamina + regen * delta, MAX_STAMINA)
		stamina_changed.emit(stamina, MAX_STAMINA)

	_update_attack(delta)
	_update_camera(delta, on_floor, wants_sprint)


func _use_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_regen_wait = REGEN_DELAY
	stamina_changed.emit(stamina, MAX_STAMINA)


# ---------------- 대시 ----------------

func try_dash() -> void:
	if dead or not controls_enabled or _stun > 0.0 or _dash_cd > 0.0 or _dash_t > 0.0:
		return
	if stamina < DASH_COST * 0.5:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO:
		input = Vector2(0, 1)   # 방향키 없이 누르면 뒤로 물러난다
	_dash_dir = (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	_dash_t = DASH_TIME
	_dash_cd = DASH_COOLDOWN
	_iframes = DASH_IFRAMES
	_use_stamina(DASH_COST)
	# 대시는 공격 후 회복 동작을 끊고 나갈 수 있다.
	if _attack_phase == "recover":
		_attack_phase = ""
		_queued_attack = ""
	if blocking:
		_set_blocking(false)
	camera.fov += 8.0
	_play("dash", 1.0, -8.0)


# ---------------- 막기 ----------------

func _set_blocking(on: bool) -> void:
	blocking = on
	_block_t = 0.0
	_kill_weapon_tween()
	_weapon_tween = create_tween()
	var p := _weapon_pivot
	if on:
		# 칼을 눕혀서 몸 앞을 가로막는다
		_weapon_tween.tween_property(p, "rotation", Vector3(deg_to_rad(8), deg_to_rad(-20), deg_to_rad(78)), 0.08)
		_weapon_tween.parallel().tween_property(p, "position", Vector3(-0.32, 0.26, 0.05), 0.08)
	else:
		_weapon_tween.tween_property(p, "rotation", Vector3.ZERO, 0.14)
		_weapon_tween.parallel().tween_property(p, "position", Vector3.ZERO, 0.14)


## 상대의 공격이 나에게 닿았을 때 불린다. 결과: "hit", "blocked", "parried", "dodged", "guard_broken"
func receive_attack(damage: int, heavy: bool, attacker: Node3D) -> String:
	var result := _resolve_attack(damage, heavy, attacker)
	attack_received.emit(result)
	return result


func _resolve_attack(damage: int, heavy: bool, attacker: Node3D) -> String:
	if dead:
		return "none"
	if _iframes > 0.0:
		combat_event.emit("회피!", Color(0.6, 0.9, 1.0))
		return "dodged"
	var to_attacker := attacker.global_position - global_position
	to_attacker.y = 0
	var facing := -global_transform.basis.z
	facing.y = 0
	var in_front := facing.normalized().dot(to_attacker.normalized()) > 0.25
	if blocking and in_front:
		var contact := _blade_tip.global_position
		if _block_t <= PARRY_WINDOW:
			_play("parry", 1.0, -1.0)
			Fx.sparks(get_parent(), contact, to_attacker.normalized(), 40, Color(0.7, 0.9, 1.0))
			combat_event.emit("튕겨내기!", Color(0.55, 0.85, 1.0))
			_shake = 0.5
			_slow_motion(0.25, 0.3)
			return "parried"
		_use_stamina(BLOCK_COST["heavy" if heavy else "light"])
		_play("clang")
		Fx.sparks(get_parent(), contact, to_attacker.normalized())
		_shake = 0.35
		if stamina <= 0.0:
			# 기력이 바닥나면 막기가 깨진다
			_set_blocking(false)
			_stun = GUARD_BREAK_STUN
			combat_event.emit("가드 깨짐!", Color(1.0, 0.5, 0.3))
			_take_damage(damage / 2, to_attacker)
			return "guard_broken"
		return "blocked"
	_take_damage(damage, to_attacker)
	return "hit"


func _take_damage(amount: int, from_dir: Vector3) -> void:
	hp = max(hp - amount, 0)
	hp_changed.emit(hp, MAX_HP)
	took_damage.emit(amount)
	_play("hurt", 1.0, -2.0)
	_shake = 0.7
	# 맞은 방향 반대쪽으로 카메라가 젖혀진다
	var local := global_transform.basis.inverse() * from_dir.normalized()
	_kick = Vector3(deg_to_rad(6.0), 0, deg_to_rad(-8.0) * signf(local.x if absf(local.x) > 0.1 else 1.0))
	velocity += -from_dir.normalized() * 4.0
	_cancel_attack()
	_stun = maxf(_stun, HIT_STUN)
	if hp <= 0:
		_die()


func _die() -> void:
	dead = true
	blocking = false
	_cancel_attack()
	died.emit()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(head, "position:y", 0.35, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(head, "rotation:z", deg_to_rad(28), 0.8)
	tw.tween_property(_weapon_root, "position:y", -1.2, 0.5)


func _slow_motion(ts: float, real_seconds: float) -> void:
	Engine.time_scale = ts
	await get_tree().create_timer(real_seconds, true, false, true).timeout
	Engine.time_scale = 1.0


# ---------------- 공격 ----------------

func _request_attack(kind: String) -> void:
	if _stun > 0.0 or _dash_t > 0.0:
		return
	if blocking:
		_set_blocking(false)
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
	attack_started.emit(kind)


func _kill_weapon_tween() -> void:
	if _weapon_tween and _weapon_tween.is_valid():
		_weapon_tween.kill()


func _cancel_attack() -> void:
	_attack_phase = ""
	_queued_attack = ""
	_kill_weapon_tween()
	_weapon_tween = create_tween()
	_weapon_tween.tween_property(_weapon_pivot, "rotation", Vector3.ZERO, 0.2)
	_weapon_tween.parallel().tween_property(_weapon_pivot, "position", Vector3.ZERO, 0.2)


func _animate_swing(kind: String, data: Dictionary) -> void:
	_kill_weapon_tween()
	_weapon_tween = create_tween()
	var tw := _weapon_tween
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
		_play(_attack_name, 1.0, -6.0)
	elif _attack_phase == "active":
		trail_mat.albedo_color.a = 0.35
		_check_hits(data)
		if _attack_timer <= 0.0 and _attack_phase == "active":
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
		var heavy := _attack_name == "heavy"
		var dmg: int = data.damage + randi_range(-2, 2)
		var result = body.take_hit(dmg, hit_dir, heavy, self)
		var contact := _blade_tip.global_position
		match result:
			"blocked":
				# 상대가 막았다: 칼이 튕겨 나오고 잠깐 굳는다
				_play("clang")
				Fx.sparks(get_parent(), contact, -hit_dir)
				combat_event.emit("막힘", Color(0.85, 0.85, 0.85))
				_shake = 0.3
				_stun = RECOIL_STUN
				_cancel_attack()
				return
			"parried":
				_play("parry", 0.9, -1.0)
				Fx.sparks(get_parent(), contact, -hit_dir, 40, Color(1.0, 0.55, 0.3))
				combat_event.emit("튕겨냄 당함!", Color(1.0, 0.45, 0.35))
				_shake = 0.5
				_stun = PARRIED_STUN
				_cancel_attack()
				return
			_:
				_on_hit_landed(heavy)


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
	if on_floor and horiz > 0.5 and _dash_t <= 0.0:
		_bob_t += delta * horiz * 1.9
	else:
		_bob_t = lerpf(_bob_t, roundf(_bob_t / PI) * PI, clampf(delta * 6.0, 0, 1))
	var bob_amt := 0.045 if sprinting else 0.03
	var bob := Vector3(cos(_bob_t * 0.5) * bob_amt * 0.6, absf(sin(_bob_t)) * bob_amt, 0)
	# 맞혔을 때 / 맞았을 때 화면 흔들림
	_shake = maxf(_shake - delta * 3.5, 0.0)
	var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * _shake * 0.05
	camera.position = camera.position.lerp(bob, clampf(delta * 12.0, 0, 1)) + shake
	_kick = _kick.lerp(Vector3.ZERO, clampf(delta * 7.0, 0, 1))
	camera.rotation = _kick
	# 달리거나 대시할 때 시야가 넓어짐
	var target_fov := 78.0
	if _dash_t > 0.0:
		target_fov = 90.0
	elif sprinting and horiz > WALK_SPEED:
		target_fov = 86.0
	camera.fov = lerpf(camera.fov, target_fov, clampf(delta * 8.0, 0, 1))
	# 칼도 걸음에 맞춰 살짝 흔들림
	_weapon_root.position = WEAPON_REST + Vector3(bob.x * 0.5, -bob.y * 0.6, 0)
