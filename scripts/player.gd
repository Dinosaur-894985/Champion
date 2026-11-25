class_name Player
extends CharacterBody3D
## 1인칭 플레이어.
## 몸 움직임은 두 겹으로 나뉜다.
##   아래 몸(이동): 걷기, 달리기, 점프 — _physics_process 에서 늘 계산
##   위 몸(행동): 가만히/막기/공격/차지/대시/경직 — 상태 기계(StateMachine)가 하나씩 맡는다
## 행동이 이동 속도에 주는 영향은 _move_mult() 한 곳에서 정한다.
## 공격 동작의 수치와 칼 자세는 scripts/combat/move_set.gd 에 모여 있다.

signal stamina_changed(value: float, max_value: float)
signal hp_changed(value: int, max_value: int)
signal attack_started(kind: String)
signal charge_started
signal counter_window(open: bool)
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

# --- 방향 대시 (Shift + 방향키: 그쪽으로 튀어나감. 방향키 없으면 뒤로) ---
const DASH_SPEED := 15.0
const DASH_TIME := 0.17
const DASH_COST := 20.0
const DASH_COOLDOWN := 0.35
const DASH_IFRAMES := 0.2      # 대시 시작부터 이 시간 동안은 공격을 피한다
const DASH_ATTACK_CANCEL := 0.6  # 대시가 이만큼 지나면 바로 베기로 이어갈 수 있다

# --- 회피 반격 ---
const PERFECT_DODGE := 0.35    # 대시하고 이 시간 안에 상대 공격을 흘리면 '아슬한 회피'
const COUNTER_WINDOW := 0.9    # 반격 기회가 열려 있는 시간

# --- 차지 베기 ---
const CHARGE_HOLD := 0.2       # 왼쪽 클릭을 이만큼 누르고 있으면 모으기 시작
const CHARGE_AUTO_RELEASE := 1.6

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
const BLOCK_COST := {"flinch": 14.0, "stagger": 30.0}

var hp := MAX_HP
var stamina := MAX_STAMINA
var controls_enabled := true
var dead := false
var blocking: bool:
	get: return sm.state == "block"

## 행동 상태: free, block, attack, charge, dash, stagger
var sm := StateMachine.new()

var _regen_wait := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _bob_t := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _sprinting := false

# 대시
var _dash_cd := 0.0
var _dash_dir := Vector3.ZERO
var _dash_local := Vector2.ZERO
var _iframes := 0.0
var _since_dash := 99.0
var _counter_t := 0.0
var _counter_used := false

# 공격
var _move := ""                # 지금 쓰는 동작 이름 (MoveSet.MOVES)
var _attack_phase := ""        # "windup" / "active" / "recover" / ""
var _attack_timer := 0.0
var _queued := ""              # 미리 눌러 둔 다음 동작
var _already_hit := {}
var _press_t := -1.0           # 왼쪽 클릭을 누르고 있는 시간 (안 누르면 -1)
var _press_owner := ""         # 그 클릭으로 시작한 동작
var _charge_level := 0.0
var _charge_full := false
var _hit_info := {}

# 경직
var _stun_time := 0.0
var _stun_kind := ""

# 화면 흔들림
var _kick := Vector3.ZERO      # 맞았을 때 카메라가 젖혀지는 정도
var _roll := 0.0               # 옆으로 대시하거나 크게 벨 때 화면 기울기
var _shake := 0.0
var _tremble := 0.0

var head: Node3D
var camera: Camera3D
var _weapon_root: Node3D       # 화면에 보이는 칼의 기준점
var _weapon_pivot: Node3D      # 휘두를 때 돌아가는 부분
var _blade_tip: Node3D
var _blade_mat: StandardMaterial3D
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
		"charged": Sfx.clang(0.35, 1.6),
	}
	_audio = AudioStreamPlayer.new()
	_audio.volume_db = -4.0
	_audio.max_polyphony = 4
	add_child(_audio)

	# 행동 상태 등록 — 새 행동은 여기 한 줄과 함수 몇 개로 늘릴 수 있다
	sm.add("free") \
		.add("block", _block_enter, _block_update) \
		.add("attack", _attack_enter, _attack_update, _attack_exit) \
		.add("charge", _charge_enter, _charge_update, _charge_exit) \
		.add("dash", _dash_enter, _dash_update) \
		.add("stagger", _stagger_enter, _stagger_update)
	sm.go("free")


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
	# 차지할 때 칼날이 빛난다 (빛 설정은 처음부터 켜 두고 세기만 바꾼다 → 멈칫 없음)
	steel.emission_enabled = true
	steel.emission = Color(1.0, 0.72, 0.3)
	steel.emission_energy_multiplier = 0.0
	_blade_mat = steel
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
		var sens := MOUSE_SENS * (0.6 if sm.state == "charge" else 1.0)
		rotate_y(-event.relative.x * sens)
		head.rotate_x(-event.relative.y * sens)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-88), deg_to_rad(88))
	elif not controls_enabled:
		return
	elif event.is_action_pressed("attack"):
		attack_pressed()
	elif event.is_action_released("attack"):
		attack_released()
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

	_iframes = maxf(_iframes - delta, 0.0)
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	_since_dash += delta
	if _press_t >= 0.0:
		_press_t += delta
	if _counter_t > 0.0:
		_counter_t -= delta
		if _counter_t <= 0.0:
			counter_window.emit(false)

	# ---- 위 몸: 지금 행동 ----
	if sm.state == "free" and _can_act() and Input.is_action_pressed("block"):
		sm.go("block")
	sm.tick(delta)

	# ---- 아래 몸: 이동 ----
	_jump_buffer -= delta
	if _can_act() and sm.state != "dash" and Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
	if _jump_buffer > 0.0 and _coyote > 0.0 and stamina >= JUMP_COST * 0.5:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
		_use_stamina(JUMP_COST)

	var input := Vector2.ZERO
	if controls_enabled and not dead:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	_sprinting = _can_act() and sm.state == "free" and Input.is_action_pressed("sprint") \
			and input.y < 0.0 and stamina > 0.0
	var speed := (SPRINT_SPEED if _sprinting else WALK_SPEED) * _move_mult()

	if sm.state != "dash":
		var accel := GROUND_ACCEL if on_floor else AIR_ACCEL
		var target := dir * speed
		velocity.x = lerpf(velocity.x, target.x, clampf(accel * delta, 0, 1))
		velocity.z = lerpf(velocity.z, target.z, clampf(accel * delta, 0, 1))
	move_and_slide()

	# 기력
	if _sprinting and dir != Vector3.ZERO and on_floor:
		_use_stamina(SPRINT_COST * delta)
	elif _regen_wait > 0.0:
		_regen_wait -= delta
	elif stamina < MAX_STAMINA:
		var regen := STAMINA_REGEN * (0.5 if sm.state in ["block", "charge"] else 1.0)
		stamina = minf(stamina + regen * delta, MAX_STAMINA)
		stamina_changed.emit(stamina, MAX_STAMINA)

	var trail_mat: StandardMaterial3D = _trail.material_override
	trail_mat.albedo_color.a = move_toward(trail_mat.albedo_color.a, 0.35 if _attack_phase == "active" else 0.0, delta * 4.0 if _attack_phase != "active" else 99.0)
	_update_camera(delta, on_floor, _sprinting)


## 행동마다 이동 속도가 얼마나 느려지는지
func _move_mult() -> float:
	match sm.state:
		"block":
			return BLOCK_SPEED_MULT
		"attack":
			return 0.6
		"charge":
			return 0.5
		"stagger":
			return 0.35 if _stun_kind != "flinch" else 0.6
	return 1.0


func _can_act() -> bool:
	return controls_enabled and not dead


func _use_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_regen_wait = REGEN_DELAY
	stamina_changed.emit(stamina, MAX_STAMINA)


## 시작 전에 잔상과 칼 빛 효과를 한 번 그려 둔다 (첫 공격 때 멈칫하지 않도록).
func warmup() -> void:
	var trail_mat: StandardMaterial3D = _trail.material_override
	trail_mat.albedo_color.a = 0.02
	_blade_mat.emission_energy_multiplier = 0.01


func is_attacking() -> bool:
	return _attack_phase != "" or sm.state == "charge"


# ---------------- 칼 자세 ----------------

func _kill_weapon_tween() -> void:
	if _weapon_tween and _weapon_tween.is_valid():
		_weapon_tween.kill()


## 칼을 [회전(도), 위치] 자세로 옮긴다.
func _pose_to(pose: Array, time: float, trans := Tween.TRANS_SINE, ease_type := Tween.EASE_OUT) -> void:
	_kill_weapon_tween()
	_weapon_tween = create_tween()
	_tween_pose(_weapon_tween, pose, time, trans, ease_type)


func _tween_pose(tw: Tween, pose: Array, time: float, trans := Tween.TRANS_SINE, ease_type := Tween.EASE_OUT) -> void:
	var rot: Vector3 = pose[0]
	tw.tween_property(_weapon_pivot, "rotation", rot * (PI / 180.0), time).set_trans(trans).set_ease(ease_type)
	tw.parallel().tween_property(_weapon_pivot, "position", pose[1], time).set_trans(trans).set_ease(ease_type)


# ---------------- 막기 ----------------

func _block_enter(_d: Dictionary) -> void:
	_pose_to(MoveSet.FP_POSES.block, 0.08)


func _block_update(_delta: float) -> void:
	if not Input.is_action_pressed("block") or not _can_act():
		sm.go("free")
		_pose_to(MoveSet.FP_POSES.rest, 0.14)


# ---------------- 방향 대시 ----------------

func try_dash() -> void:
	if dead or not controls_enabled or _dash_cd > 0.0:
		return
	if not sm.is_in(["free", "block", "attack", "charge"]):
		return
	# 공격은 회복 동작 중일 때만 대시로 끊을 수 있다
	if sm.state == "attack" and _attack_phase != "recover":
		return
	if stamina < DASH_COST * 0.5:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO:
		input = Vector2(0, 1)   # 방향키 없이 누르면 뒤로 물러난다
	sm.go("dash", {"input": input.normalized()})


func _dash_enter(d: Dictionary) -> void:
	_dash_local = d.input
	_dash_dir = (transform.basis * Vector3(_dash_local.x, 0, _dash_local.y)).normalized()
	_dash_cd = DASH_COOLDOWN
	_iframes = DASH_IFRAMES
	_since_dash = 0.0
	_counter_used = false
	_use_stamina(DASH_COST)
	_pose_to(MoveSet.FP_POSES.rest, 0.12)
	camera.fov += 8.0
	_play("dash", 1.0 + _dash_local.x * 0.08, -8.0)


func _dash_update(_delta: float) -> void:
	var k := clampf(1.0 - sm.time / DASH_TIME, 0.0, 1.0)
	var dv := _dash_dir * lerpf(WALK_SPEED, DASH_SPEED, k)
	velocity.x = dv.x
	velocity.z = dv.z
	if sm.time >= DASH_TIME:
		sm.go("free")
		if _queued != "":
			var q := _queued
			_queued = ""
			_start_attack(q)


# ---------------- 회피 반격 ----------------

## 상대 공격이 빗나갔을 때 상대가 알려 준다. 막 대시한 참이면 '아슬한 회피'.
func notify_whiff(_attacker: Node3D) -> bool:
	if dead or _since_dash > PERFECT_DODGE:
		return false
	_open_counter()
	return true


func _open_counter() -> void:
	if _counter_used:
		return
	_counter_used = true
	_counter_t = COUNTER_WINDOW
	counter_window.emit(true)
	combat_event.emit("아슬한 회피! 지금 반격!", Color(0.5, 0.9, 1.0))
	_slow_motion(0.3, 0.22)


func counter_ready() -> bool:
	return _counter_t > 0.0


# ---------------- 공격 입력 ----------------

## 왼쪽 클릭을 눌렀을 때: 반격 기회면 반격, 아니면 연속 베기 (누르고 있으면 차지)
func attack_pressed() -> void:
	_press_t = 0.0
	if _counter_t > 0.0 and sm.is_in(["free", "block", "dash", "attack"]) and _move != "counter":
		_press_owner = ""
		_counter_t = 0.0
		counter_window.emit(false)
		sm.go("attack", {"move": "counter"})
		return
	_request_attack("combo")


func attack_released() -> void:
	_press_t = -1.0
	if sm.state == "charge":
		_release_charge()


## kind: "combo"(연속 베기 다음 단계), "heavy", 또는 동작 이름
func _request_attack(kind: String) -> void:
	if dead or not controls_enabled:
		return
	match sm.state:
		"free", "block":
			_start_attack("slash1" if kind in ["combo", "light"] else kind)
		"dash":
			var q := "slash1" if kind in ["combo", "light"] else kind
			if sm.time >= DASH_TIME * DASH_ATTACK_CANCEL:
				_start_attack(q)
			else:
				_queued = q
		"attack":
			if _move == "charge" or (_attack_phase == "windup" and _queued != ""):
				return
			if kind in ["combo", "light"]:
				var nxt: String = MoveSet.MOVES[_move].next
				_queued = nxt if nxt != "" else "slash1"
			else:
				_queued = kind


func _start_attack(move_name: String) -> void:
	var data: Dictionary = MoveSet.MOVES[move_name]
	if stamina < data.cost * 0.5:
		return
	if move_name.begins_with("slash") and _press_t >= 0.0:
		_press_owner = move_name
	else:
		_press_owner = ""
	sm.go("attack", {"move": move_name})


# ---------------- 공격 상태 ----------------

func _attack_enter(d: Dictionary) -> void:
	_move = d.move
	var data: Dictionary = MoveSet.MOVES[_move]
	_use_stamina(data.cost)
	_attack_phase = "windup"
	_attack_timer = data.windup
	_queued = ""
	_already_hit.clear()
	_hit_info = {"move": _move, "react": data.react, "guard": data.guard, "damage": data.damage}
	if _move == "charge":
		_hit_info.damage = MoveSet.charge_damage(_charge_level)
		if not _charge_full:
			_hit_info.guard = "normal"
	_kill_weapon_tween()
	_weapon_tween = create_tween()
	_tween_pose(_weapon_tween, data.fp.windup, data.windup,
			Tween.TRANS_BACK if _move == "heavy" else Tween.TRANS_SINE)
	attack_started.emit(_move)


func _attack_exit() -> void:
	_attack_phase = ""
	_move = ""


func _attack_update(delta: float) -> void:
	var data: Dictionary = MoveSet.MOVES[_move]
	_attack_timer -= delta
	match _attack_phase:
		"windup":
			if _attack_timer > 0.0:
				return
			# 같은 클릭을 아직 누르고 있으면: 조금 더 기다렸다가 차지 베기로 바꾼다
			if _press_owner == _move and _press_t >= 0.0:
				if _press_t >= CHARGE_HOLD:
					sm.go("charge")
				return
			_enter_active(data)
		"active":
			_check_hits(data)
			if sm.state == "attack" and _attack_timer <= 0.0:
				_attack_phase = "recover"
				_attack_timer = data.recover
				_tween_back(data.recover)
		"recover":
			# 다음 공격이 예약돼 있으면 회복 동작 중간에 이어서 휘두른다.
			if _queued != "" and _attack_timer <= data.recover * 0.55:
				var nxt := _queued
				_queued = ""
				_start_attack(nxt)
				if sm.state == "attack" and _move == nxt:
					return
			if _attack_timer <= 0.0:
				sm.go("free")


func _enter_active(data: Dictionary) -> void:
	_attack_phase = "active"
	_attack_timer = data.active
	_play("heavy" if _move in ["heavy", "charge", "slash3"] else "light", 1.0, -6.0)
	var fwd := -transform.basis.z
	velocity += fwd * float(data.lunge)
	_kill_weapon_tween()
	_weapon_tween = create_tween()
	var ease_type := Tween.EASE_IN if _move == "heavy" else Tween.EASE_OUT
	_tween_pose(_weapon_tween, data.fp.strike, data.active, Tween.TRANS_CUBIC, ease_type)
	if _move in ["slash3", "charge", "counter"]:
		_roll = deg_to_rad(5.0) * signf(data.fp.strike[0].y)


func _tween_back(time: float) -> void:
	_kill_weapon_tween()
	_weapon_tween = create_tween()
	_tween_pose(_weapon_tween, MoveSet.FP_POSES.rest, time, Tween.TRANS_SINE, Tween.EASE_IN_OUT)


# ---------------- 차지 베기 ----------------

func _charge_enter(_d: Dictionary) -> void:
	_charge_level = 0.0
	_charge_full = false
	_attack_phase = ""
	_pose_to(MoveSet.MOVES.charge.fp.windup, 0.25)
	charge_started.emit()


func _charge_update(_delta: float) -> void:
	var full_time: float = MoveSet.MOVES.charge.windup
	_charge_level = clampf(sm.time / full_time, 0.0, 1.0)
	_tremble = _charge_level
	_blade_mat.emission_energy_multiplier = _charge_level * _charge_level * 2.5
	if _charge_level >= 1.0 and not _charge_full:
		_charge_full = true
		_play("charged", 1.0, -3.0)
		combat_event.emit("힘 최대!", Color(1.0, 0.8, 0.35))
		_shake = 0.25
	if sm.time >= CHARGE_AUTO_RELEASE or (_press_t < 0.0 and not Input.is_action_pressed("attack")):
		_release_charge()


func _release_charge() -> void:
	if sm.state != "charge":
		return
	var level := _charge_level
	var full := _charge_full
	sm.go("attack", {"move": "charge"})
	_charge_level = level
	_charge_full = full
	# 모으는 동안 이미 준비했으니 바로 휘두른다
	_hit_info.damage = MoveSet.charge_damage(level)
	_hit_info.guard = "break" if full else "normal"
	_attack_timer = 0.0
	_attack_update(0.0)


func _charge_exit() -> void:
	_tremble = 0.0
	_blade_mat.emission_energy_multiplier = 0.0


# ---------------- 경직 ----------------

func _stagger_enter(d: Dictionary) -> void:
	_stun_kind = d.kind
	var r: Dictionary = MoveSet.REACTIONS[_stun_kind]
	_stun_time = r.time
	var from_dir: Vector3 = d.get("from", Vector3.ZERO)
	if from_dir != Vector3.ZERO:
		velocity += -from_dir.normalized() * float(r.push)
		var local := global_transform.basis.inverse() * from_dir.normalized()
		var side := signf(local.x) if absf(local.x) > 0.1 else 1.0
		_kick = Vector3(deg_to_rad(5.0), 0, deg_to_rad(-6.0) * side) * float(r.kick)
	_queued = ""
	if _stun_kind == "flinch":
		_pose_to(MoveSet.FP_POSES.rest, 0.15)
	else:
		_pose_to(MoveSet.FP_POSES.stagger, 0.12)


func _stagger_update(_delta: float) -> void:
	if sm.time >= _stun_time:
		sm.go("free")
		_pose_to(MoveSet.FP_POSES.rest, 0.22)


func _react(kind: String, from_dir: Vector3) -> void:
	if dead:
		return
	sm.go("stagger", {"kind": kind, "from": from_dir})


## 상대의 공격이 나에게 닿았을 때 불린다.
## info: {"damage", "react", "guard"} — 결과: "hit", "blocked", "parried", "dodged", "guard_broken"
func receive_attack(info: Dictionary, attacker: Node3D) -> String:
	var result := _resolve_attack(info, attacker)
	attack_received.emit(result)
	return result


func _resolve_attack(info: Dictionary, attacker: Node3D) -> String:
	if dead:
		return "none"
	var to_attacker := attacker.global_position - global_position
	to_attacker.y = 0
	if _iframes > 0.0:
		combat_event.emit("회피!", Color(0.6, 0.9, 1.0))
		if _since_dash <= PERFECT_DODGE:
			_open_counter()
		return "dodged"
	var facing := -global_transform.basis.z
	facing.y = 0
	var in_front := facing.normalized().dot(to_attacker.normalized()) > 0.25
	var damage: int = info.damage
	if blocking and in_front and info.guard != "unblockable":
		var contact := _blade_tip.global_position
		if sm.time <= PARRY_WINDOW:
			_play("parry", 1.0, -1.0)
			Fx.sparks(get_parent(), contact, to_attacker.normalized(), 40, Color(0.7, 0.9, 1.0))
			combat_event.emit("튕겨내기!", Color(0.55, 0.85, 1.0))
			_shake = 0.5
			_slow_motion(0.25, 0.3)
			return "parried"
		_play("clang")
		Fx.sparks(get_parent(), contact, to_attacker.normalized())
		_shake = 0.35
		if info.guard == "break":
			stamina = 0.0
		else:
			_use_stamina(BLOCK_COST.get(info.react, 14.0))
		if stamina <= 0.0:
			# 기력이 바닥나거나 막기를 깨는 공격이면 막기가 깨진다
			_use_stamina(0.0)
			combat_event.emit("가드 깨짐!", Color(1.0, 0.5, 0.3))
			_take_damage(damage / 2, to_attacker)
			_react("guard_break", to_attacker)
			return "guard_broken"
		return "blocked"
	_take_damage(damage, to_attacker)
	# 차지 중에 맞으면 모은 힘이 날아간다
	_react(info.react, to_attacker)
	return "hit"


func _take_damage(amount: int, from_dir: Vector3) -> void:
	hp = max(hp - amount, 0)
	hp_changed.emit(hp, MAX_HP)
	took_damage.emit(amount)
	_play("hurt", 1.0, -2.0)
	_shake = 0.7
	if hp <= 0:
		_die()


func _die() -> void:
	dead = true
	sm.go("free")
	_kill_weapon_tween()
	died.emit()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(head, "position:y", 0.35, 0.8).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(head, "rotation:z", deg_to_rad(28), 0.8)
	tw.tween_property(_weapon_root, "position:y", -1.2, 0.5)


func _slow_motion(ts: float, real_seconds: float) -> void:
	Engine.time_scale = ts
	await get_tree().create_timer(real_seconds, true, false, true).timeout
	Engine.time_scale = 1.0


# ---------------- 맞히기 ----------------

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
		var info := _hit_info.duplicate()
		info.damage = int(info.damage) + randi_range(-2, 2)
		var result = body.take_hit(info, hit_dir, self)
		var contact := _blade_tip.global_position
		match result:
			"blocked":
				# 상대가 막았다: 칼이 튕겨 나오고 잠깐 굳는다
				_play("clang")
				Fx.sparks(get_parent(), contact, -hit_dir)
				combat_event.emit("막힘", Color(0.85, 0.85, 0.85))
				_shake = 0.3
				_react("recoil", Vector3.ZERO)
				return
			"parried":
				_play("parry", 0.9, -1.0)
				Fx.sparks(get_parent(), contact, -hit_dir, 40, Color(1.0, 0.55, 0.3))
				combat_event.emit("튕겨냄 당함!", Color(1.0, 0.45, 0.35))
				_shake = 0.5
				_react("parried", Vector3.ZERO)
				return
			"dodged":
				combat_event.emit("피했다!", Color(1.0, 0.7, 0.4))
			_:
				_on_hit_landed(info.react == "stagger")


func _on_hit_landed(big: bool) -> void:
	_shake = 0.6 if big else 0.3
	# 타격감: 아주 잠깐 시간을 멈춘다 (히트스톱)
	Engine.time_scale = 0.1
	await get_tree().create_timer(0.06 if big else 0.035, true, false, true).timeout
	Engine.time_scale = 1.0


# ---------------- 카메라 ----------------

func _update_camera(delta: float, on_floor: bool, sprinting: bool) -> void:
	var horiz := Vector2(velocity.x, velocity.z).length()
	# 걸을 때 화면이 살짝 흔들림
	if on_floor and horiz > 0.5 and sm.state != "dash":
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
	# 옆으로 대시하면 그쪽으로 화면이 기운다
	var roll_target := 0.0
	if sm.state == "dash":
		roll_target = -_dash_local.x * deg_to_rad(7.0)
	_roll = lerpf(_roll, roll_target, clampf(delta * 10.0, 0, 1))
	camera.rotation = _kick + Vector3(0, 0, _roll)
	# 달리거나 대시할 때 시야가 넓어짐
	var target_fov := 78.0
	if sm.state == "dash":
		target_fov = 90.0
	elif sm.state == "charge":
		target_fov = 78.0 - _charge_level * 6.0
	elif sprinting and horiz > WALK_SPEED:
		target_fov = 86.0
	camera.fov = lerpf(camera.fov, target_fov, clampf(delta * 8.0, 0, 1))
	# 칼도 걸음에 맞춰 살짝 흔들림
	var tr := Vector3.ZERO
	if _tremble > 0.0:
		var t := Time.get_ticks_msec() * 0.06
		tr = Vector3(sin(t * 1.3), sin(t * 1.9), 0) * _tremble * 0.006
	_weapon_root.position = WEAPON_REST + Vector3(bob.x * 0.5, -bob.y * 0.6, 0) + tr
