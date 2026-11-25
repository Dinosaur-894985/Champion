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
signal feinted                  # 공격을 준비하다 멈췄다 (속임수)
signal guard_changed(dir: String)

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

# --- 수싸움 ---
const BLOCK_LOOK_SENS := 0.35  # 막는 동안은 마우스가 화면보다 막기 방향을 바꾸는 데 쓰인다
const LOCK_TURN := 7.0         # 막는 동안 상대 쪽으로 저절로 돌아보는 빠르기
const LOCK_RANGE := 9.0

## 내 캐릭터 (능력치, 특수 스킬). 씬에 넣기 전에 정해 둔다. 없으면 기본 캐릭터.
var build: CharacterBuild
## 이 캐릭터가 쓸 수 있는 이동 기술 (MoveSet.TRAVERSAL). 빌드의 '벽타기' 스킬로 켜진다.
var traits := {"wall_climb": true, "wall_run": true}

var max_hp := MAX_HP
var max_stamina := MAX_STAMINA
var hp := MAX_HP
var stamina := MAX_STAMINA
var skills: SkillKit
## 높이 규칙 (밀려 떨어지기, 낭떠러지, 난간, 아이템) — scripts/combat/vertical_kit.gd
var vkit: VerticalKit
var arena: Arena
var controls_enabled := true
var dead := false
var blocking: bool:
	get: return sm.state == "block"
## 막기 방향 (AttackDir: "high" 위 / "side" 옆 / "mid" 찌르기). 막을 때 마우스를 위/옆/아래로 움직여 바꾼다.
var guard_dir := AttackDir.SIDE
## 막는 동안 저절로 바라볼 상대 (대결에서 Game 이 정해 준다)
var opponent: Node3D

## 행동 상태: free, block, attack, charge, dash, stagger, climb(벽 오르기), wallrun(벽 달리기)
var sm := StateMachine.new()

var _regen_wait := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _jump_released := true
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

# 벽 동작
var _wall_contact := false     # 지난 프레임에 벽에 닿았나
var _wall_n := Vector3.ZERO    # 닿은 벽이 바라보는 방향
var _wall_climbable := false
var _climb_used := false       # 한 번 뛸 때 벽 오르기는 한 번만 (땅에 닿으면 다시)
var _last_run_n := Vector3.ZERO
var _run_n := Vector3.ZERO
var _run_t := Vector3.ZERO
var _fall_speed := 0.0
var _ledge_y := -INF           # 벽 오르다 짚은 꼭대기 높이
var _ray := PhysicsRayQueryParameters3D.new()

# 특수 스킬
var _grap_point := Vector3.ZERO
var _grap_body: Node3D = null
var _rope: MeshInstance3D

# 수싸움
var _flick := AttackDir.Flick.new()
var _guard_t := 99.0           # 막기 방향을 정한 뒤 지난 시간 (튕겨내기 판정)
var _thrown_t := 0.0           # 던져진 뒤 남은 '벽꽝' 시간
var _pre_speed := 0.0

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
	if build == null:
		build = CharacterBuild.new()
	add_to_group("grabbable")
	max_hp = build.max_hp()
	hp = max_hp
	max_stamina = build.max_stamina()
	stamina = max_stamina
	traits = {"wall_climb": build.has("wall"), "wall_run": build.has("wall")}
	skills = SkillKit.new(self, build)
	vkit = VerticalKit.new(self)
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
		.add("stagger", _stagger_enter, _stagger_update) \
		.add("climb", _climb_enter, _climb_update, _climb_exit) \
		.add("wallrun", _wallrun_enter, _wallrun_update, _wallrun_exit) \
		.add("grapple", _grapple_enter, _grapple_update, _grapple_exit) \
		.add("iron", _iron_enter, _iron_update, _iron_exit) \
		.add("plunge", _plunge_enter, _plunge_update, _plunge_exit) \
		.add("hang", _hang_enter, _hang_update, _hang_exit) \
		.add("zip", _zip_enter, _zip_update, _zip_exit)
	sm.go("free")
	_ray.exclude = [get_rid()]
	_ray.collision_mask = 1
	_build_rope()


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
		_flick.add(event.relative)
		var sens := MOUSE_SENS * (0.6 if sm.state == "charge" else 1.0)
		if blocking:
			sens = MOUSE_SENS * BLOCK_LOOK_SENS
			var d := _flick.dir()
			if d != "" and d != guard_dir:
				set_guard(d)
				_flick.clear()
		rotate_y(-event.relative.x * sens)
		head.rotate_x(-event.relative.y * sens)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-88), deg_to_rad(88))
	elif not controls_enabled:
		return
	elif event.is_action_pressed("attack"):
		attack_pressed(_flick.dir(), _flick.side_sign())
	elif event.is_action_released("attack"):
		attack_released()
	elif event.is_action_pressed("heavy_attack"):
		_request_attack("heavy")
	elif event.is_action_pressed("sprint"):
		try_dash()
	elif event.is_action_pressed("grab"):
		try_grab()
	elif event.is_action_pressed("block"):
		block_pressed(_flick.dir())
	elif event.is_action_pressed("skill1"):
		use_skill_slot(0)
	elif event.is_action_pressed("skill2"):
		use_skill_slot(1)


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	var on_wall_move := sm.is_in(["climb", "wallrun", "grapple", "hang", "zip"])
	if not on_floor and not on_wall_move:
		velocity.y -= _gravity * delta
		_coyote -= delta
	else:
		_coyote = COYOTE_TIME

	_iframes = maxf(_iframes - delta, 0.0)
	skills.tick(delta)
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
	_guard_t += delta
	_thrown_t = maxf(_thrown_t - delta, 0.0)
	sm.tick(delta)
	if blocking:
		_soft_lock(delta)

	# ---- 아래 몸: 이동 ----
	_jump_buffer -= delta
	# 이중 점프는 점프 키를 한 번 뗐다가 다시 눌러야 나간다 (같은 누름으로 두 번 뛰지 않게)
	if not Input.is_action_pressed("jump"):
		_jump_released = true
	if _can_act() and not sm.is_in(["dash", "climb", "wallrun", "grapple", "plunge", "hang", "zip"]) and Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
		# 이중 점프: 공중에서 한 번 더
		if _coyote <= 0.0 and _jump_released and skills.try_double_jump(JUMP_VELOCITY * 0.95):
			_jump_buffer = 0.0
			_play("dash", 1.35, -8.0)
			Fx.sparks(get_parent(), global_position, Vector3.DOWN, 10, Color(0.85, 0.9, 1.0))
	if _jump_buffer > 0.0 and _coyote > 0.0 and stamina >= JUMP_COST * 0.5:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
		_jump_released = false
		_use_stamina(JUMP_COST)

	var input := Vector2.ZERO
	if controls_enabled and not dead:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	_sprinting = _can_act() and sm.state == "free" and Input.is_action_pressed("sprint") \
			and input.y < 0.0 and stamina > 0.0
	var speed := (SPRINT_SPEED if _sprinting else WALK_SPEED) * _move_mult() * build.speed_mult() * skills.speed_mult()

	if not sm.is_in(["dash", "climb", "wallrun", "grapple", "plunge", "hang", "zip"]):
		var accel := GROUND_ACCEL if on_floor else AIR_ACCEL
		if _thrown_t > 0.0:
			accel = 1.5   # 던져지는 중에는 거의 멈추지 못하고 날아간다
		var target := dir * speed
		velocity.x = lerpf(velocity.x, target.x, clampf(accel * delta, 0, 1))
		velocity.z = lerpf(velocity.z, target.z, clampf(accel * delta, 0, 1))
	_fall_speed = velocity.y
	_pre_speed = Vector2(velocity.x, velocity.z).length()
	move_and_slide()
	_after_move(on_floor, input)
	_vertical_tick(delta)

	# 기력
	if _sprinting and dir != Vector3.ZERO and on_floor:
		_use_stamina(SPRINT_COST * delta)
	elif _regen_wait > 0.0:
		_regen_wait -= delta
	elif stamina < max_stamina:
		var regen := STAMINA_REGEN * build.regen_mult() * skills.regen_mult() \
				* (0.5 if sm.state in ["block", "charge"] else 1.0)
		stamina = minf(stamina + regen * delta, max_stamina)
		stamina_changed.emit(stamina, max_stamina)

	var trail_mat: StandardMaterial3D = _trail.material_override
	trail_mat.albedo_color.a = move_toward(trail_mat.albedo_color.a, 0.35 if _attack_phase == "active" else 0.0, delta * 4.0 if _attack_phase != "active" else 99.0)
	_update_camera(delta, on_floor, _sprinting)
	_update_rope()


# ---------------- 벽 동작 ----------------

## 움직인 뒤: 벽에 닿았는지 보고, 조건이 맞으면 벽 오르기/벽 달리기를 시작한다.
func _after_move(was_on_floor: bool, input: Vector2) -> void:
	_wall_contact = false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.y) > 0.35:
			continue
		n.y = 0
		_wall_contact = true
		_wall_n = n.normalized()
		var col := c.get_collider()
		_wall_climbable = col != null and not (col as Object).has_meta("no_climb")
	if _wall_contact and _thrown_t > 0.0 and _pre_speed >= float(MoveSet.THROW.wall_slam_speed):
		_wall_slam()
	var on_floor := is_on_floor()
	if on_floor:
		if not was_on_floor and _fall_speed < -7.0:
			# 높은 곳에서 떨어지면 착지할 때 화면이 살짝 눌린다
			_kick.x -= deg_to_rad(clampf(-_fall_speed * 0.5, 0.0, 6.0))
		_climb_used = false
		_last_run_n = Vector3.ZERO
		skills.landed()
		return
	if _try_hang_or_zip(input):
		return
	if sm.state != "free" or not _can_act():
		return
	var fwd := -transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var pushing_forward := input.y < -0.3
	if not pushing_forward:
		return
	# 벽 오르기: 벽을 마주 보고 있을 때
	var climb: Dictionary = MoveSet.TRAVERSAL.wall_climb
	if traits.get("wall_climb", false) and _wall_contact and _wall_climbable and not _climb_used \
			and fwd.dot(-_wall_n) > 0.6 and velocity.y > -5.0 and stamina > 5.0:
		sm.go("climb")
		return
	# 벽 달리기: 벽이 옆에 있고 빠르게 달리고 있을 때
	var run: Dictionary = MoveSet.TRAVERSAL.wall_run
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if traits.get("wall_run", false) and hspeed >= run.min_speed and stamina >= run.cost * 0.5:
		var n := _wall_n if _wall_contact else _side_wall()
		if n != Vector3.ZERO and absf(fwd.dot(n)) < 0.5 and n.dot(_last_run_n) < 0.9:
			sm.go("wallrun", {"n": n})


## 몸 양옆 가까이에 벽이 있으면 그 벽의 방향, 없으면 ZERO
func _side_wall() -> Vector3:
	var right := transform.basis.x
	right.y = 0
	right = right.normalized()
	for s in [-1.0, 1.0]:
		var hit := _cast(global_position + Vector3.UP * 1.0, right * s * 0.95)
		if not hit.is_empty() and absf((hit.normal as Vector3).y) < 0.35:
			var n: Vector3 = hit.normal
			n.y = 0
			return n.normalized()
	return Vector3.ZERO


func _cast(from: Vector3, dir: Vector3) -> Dictionary:
	_ray.from = from
	_ray.to = from + dir
	return get_world_3d().direct_space_state.intersect_ray(_ray)


func _climb_enter(_d: Dictionary) -> void:
	_climb_used = true
	_ledge_y = -INF
	_pose_to(MoveSet.FP_POSES.climb, 0.12)
	_play("dash", 0.8, -12.0)


func _climb_update(delta: float) -> void:
	var t: Dictionary = MoveSet.TRAVERSAL.wall_climb
	velocity = -_wall_n * 1.5 + Vector3.UP * float(t.speed)
	if _ledge_y > -INF:
		# 꼭대기를 짚었다: 발이 꼭대기 위로 올라오면 앞으로 올라선다
		velocity = -_wall_n * 0.5 + Vector3.UP * float(t.mantle_up)
		if global_position.y >= _ledge_y + 0.05:
			velocity = -_wall_n * float(t.mantle_fwd) + Vector3.UP * 1.2
			_kick.x += deg_to_rad(4.0)
			var follow := _mantle_attack
			sm.go("free")
			if follow != "":
				_start_attack(follow)
		return
	_use_stamina(float(t.cost) * delta)
	# 허리 높이 앞이 비었으면 꼭대기에 닿은 것 → 꼭대기 높이를 재고 짚는다
	if _cast(global_position + Vector3.UP * 0.9, -_wall_n * 0.9).is_empty():
		var down := _cast(global_position + Vector3.UP * 2.2 - _wall_n * 0.6, Vector3.DOWN * 2.4)
		if not down.is_empty():
			_ledge_y = (down.position as Vector3).y
			return
		sm.go("free")
		return
	if _can_act() and Input.is_action_just_pressed("jump"):
		# 벽 차고 뒤로 뛰기
		velocity = _wall_n * float(t.kick_out) + Vector3.UP * float(t.kick_up)
		_play("dash", 1.1, -8.0)
		sm.go("free")
		return
	var holding := _can_act() and Input.is_action_pressed("move_forward")
	if not holding or stamina <= 0.0 or sm.time > float(t.max_time) or (not _wall_contact and sm.time > 0.1):
		velocity.y = minf(velocity.y, 1.5)
		sm.go("free")


func _climb_exit() -> void:
	_mantle_attack = ""
	_pose_to(MoveSet.FP_POSES.rest, 0.18)


func _wallrun_enter(d: Dictionary) -> void:
	var t: Dictionary = MoveSet.TRAVERSAL.wall_run
	_run_n = d.n
	_last_run_n = _run_n
	_run_t = _run_n.cross(Vector3.UP).normalized()
	var fwd := -transform.basis.z
	if _run_t.dot(Vector3(velocity.x, 0, velocity.z) + fwd) < 0.0:
		_run_t = -_run_t
	velocity.y = maxf(velocity.y, float(t.lift))
	_use_stamina(float(t.cost))
	_pose_to(MoveSet.FP_POSES.wallrun, 0.12)
	_play("dash", 0.9, -10.0)


func _wallrun_update(delta: float) -> void:
	var t: Dictionary = MoveSet.TRAVERSAL.wall_run
	var spd: float = t.speed
	velocity.x = _run_t.x * spd - _run_n.x * 1.5
	velocity.z = _run_t.z * spd - _run_n.z * 1.5
	velocity.y -= _gravity * float(t.gravity) * delta
	if _can_act() and Input.is_action_just_pressed("jump"):
		# 벽 차고 뛰기: 다른 벽으로 이어 달릴 수 있다
		velocity = _run_n * float(t.jump_out) + _run_t * spd * 0.75 + Vector3.UP * float(t.jump_up)
		_play("dash", 1.2, -8.0)
		sm.go("free")
		return
	var holding := _can_act() and Input.is_action_pressed("move_forward")
	var near_wall := _wall_contact or not _cast(global_position + Vector3.UP * 1.0, -_run_n * 0.9).is_empty()
	if is_on_floor() or not holding or sm.time > float(t.max_time) or not near_wall:
		sm.go("free")


func _wallrun_exit() -> void:
	_pose_to(MoveSet.FP_POSES.rest, 0.18)


func is_on_wall_move() -> bool:
	return sm.is_in(["climb", "wallrun", "grapple", "hang", "zip"])


## 행동마다 이동 속도가 얼마나 느려지는지
func _move_mult() -> float:
	match sm.state:
		"block":
			return BLOCK_SPEED_MULT
		"attack":
			return 0.6
		"charge":
			return 0.5
		"iron":
			return 0.55
		"stagger":
			return 0.35 if _stun_kind != "flinch" else 0.6
	return 1.0


func _can_act() -> bool:
	return controls_enabled and not dead


## 스킬 같은 바깥 코드가 기력을 쓸 때
func spend_stamina(amount: float) -> void:
	_use_stamina(amount)


func _use_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_regen_wait = REGEN_DELAY
	stamina_changed.emit(stamina, max_stamina)


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
	_guard_t = 0.0
	_pose_to(MoveSet.FP_POSES[MoveSet.block_pose(guard_dir)], 0.08)


## 오른쪽 클릭을 눌렀을 때: 마우스를 움직이던 쪽으로 막는다.
## 공격을 준비하던 중이면 그 공격을 멈춘다 (속임수: 휘두르는 척하다 막기).
func block_pressed(dir: String = "") -> void:
	if not _can_act():
		return
	if dir != "":
		set_guard(dir)
	if _try_feint():
		sm.go("block")


## 막기 방향을 바꾼다. 막는 중이면 칼 자세도 바로 바뀌고, 튕겨내기 시간이 다시 시작된다.
func set_guard(dir: String) -> void:
	if not dir in AttackDir.ALL:
		return
	var changed_dir := dir != guard_dir
	guard_dir = dir
	if blocking:
		_guard_t = 0.0
		_pose_to(MoveSet.FP_POSES[MoveSet.block_pose(guard_dir)], 0.06)
		if changed_dir:
			_play("dash", 1.8, -16.0)
	if changed_dir:
		guard_changed.emit(dir)


## 막는 동안 상대 쪽으로 저절로 돌아본다 (마우스는 막기 방향을 바꾸는 데 쓰라고)
func _soft_lock(delta: float) -> void:
	if opponent == null or not is_instance_valid(opponent):
		return
	var to := opponent.global_position - global_position
	var flat := Vector3(to.x, 0, to.z)
	if flat.length() > LOCK_RANGE or flat.length() < 0.3:
		return
	var yaw := atan2(-flat.x, -flat.z)
	rotation.y = rotate_toward(rotation.y, yaw, LOCK_TURN * delta)
	var pitch := atan2(to.y + 1.2 - head.position.y, flat.length())
	head.rotation.x = rotate_toward(head.rotation.x, clampf(pitch, -0.8, 0.8), LOCK_TURN * 0.5 * delta)


## 공격 준비(휘두르기 전)나 힘 모으기를 멈춘다. 멈췄으면 true. 기력이 조금 든다.
func _try_feint() -> bool:
	var winding := sm.state == "attack" and _attack_phase == "windup" and _move not in ["counter", "grab"]
	if not winding and sm.state != "charge":
		return sm.state in ["free", "block"]
	_use_stamina(float(MoveSet.THROW.feint_cost))
	_queued = ""
	_press_owner = ""
	sm.go("free")
	_pose_to(MoveSet.FP_POSES.rest, 0.08)
	combat_event.emit("속임수", Color(0.85, 0.75, 1.0))
	feinted.emit()
	return true


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
	# 공격은 준비 중(속임수)이거나 회복 동작 중일 때만 대시로 끊을 수 있다. 휘두르는 순간은 안 된다.
	if sm.state == "attack" and _attack_phase == "active":
		return
	if sm.state == "attack" and _attack_phase == "windup" and _move in ["counter", "grab"]:
		return
	if stamina < DASH_COST * 0.5:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO:
		input = Vector2(0, 1)   # 방향키 없이 누르면 뒤로 물러난다
	if (sm.state == "attack" and _attack_phase == "windup") or sm.state == "charge":
		_try_feint()   # 휘두르는 척하다 / 힘 모으다 대시로 빠지기
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
	var dv := _dash_dir * lerpf(WALK_SPEED, DASH_SPEED * build.dash_mult(), k)
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
## dir: 마우스를 움직이던 방향 — "high" 위에서 내려베기, "mid" 찌르기, "side"/"" 옆 베기(연속 베기)
## side: 옆으로 움직였다면 어느 쪽인지 (-1 왼쪽에서, +1 오른쪽에서)
func attack_pressed(dir: String = "", side: float = 0.0) -> void:
	_press_t = 0.0
	_aim_dir = dir
	_aim_side = side
	if _counter_t > 0.0 and sm.is_in(["free", "block", "dash", "attack"]) and _move != "counter":
		_press_owner = ""
		_counter_t = 0.0
		counter_window.emit(false)
		sm.go("attack", {"move": "counter"})
		return
	_request_attack("combo")


var _aim_dir := ""
var _aim_side := 0.0


## 클릭 방향에 맞는 동작. prev: 지금 쓰고 있는 동작 (연속 베기를 이어간다)
func _combo_move(prev: String) -> String:
	match _aim_dir:
		AttackDir.HIGH:
			return "overhead"
		AttackDir.MID:
			return "thrust"
	if prev != "":
		var nxt: String = MoveSet.MOVES[prev].next
		if nxt != "":
			return nxt
	if _aim_side > 0.0:
		return "slash2"
	return "slash1"


func attack_released() -> void:
	_press_t = -1.0
	if sm.state == "charge":
		_release_charge()


## kind: "combo"(연속 베기 다음 단계), "heavy", 또는 동작 이름
func _request_attack(kind: String) -> void:
	if dead or not controls_enabled:
		return
	if _vertical_attack(kind):
		return
	match sm.state:
		"free", "block":
			_start_attack(_combo_move("") if kind in ["combo", "light"] else kind)
		"dash":
			var q := _combo_move("") if kind in ["combo", "light"] else kind
			if sm.time >= DASH_TIME * DASH_ATTACK_CANCEL:
				_start_attack(q)
			else:
				_queued = q
		"attack":
			if _move == "charge" or (_attack_phase == "windup" and _queued != ""):
				return
			if kind in ["combo", "light"]:
				_queued = _combo_move(_move)
			else:
				_queued = kind


func _start_attack(move_name: String) -> void:
	var data: Dictionary = MoveSet.MOVES[move_name]
	if stamina < data.cost * 0.5:
		return
	if move_name in ["slash1", "slash2", "slash3"] and _press_t >= 0.0:
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
	_attack_timer = data.windup * _atk_mult()
	_queued = ""
	_already_hit.clear()
	_hit_info = {"move": _move, "react": data.react, "guard": data.guard, "damage": data.damage,
			"pressure": build.guard_pressure(), "dir": data.get("dir", "")}
	if _move == "charge":
		_hit_info.damage = MoveSet.charge_damage(_charge_level)
		if not _charge_full:
			_hit_info.guard = "normal"
	_kill_weapon_tween()
	_weapon_tween = create_tween()
	_tween_pose(_weapon_tween, data.fp.windup, data.windup * _atk_mult(),
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
			if _move == "grab":
				_check_grab(data)
			else:
				_check_hits(data)
			if sm.state == "attack" and _attack_timer <= 0.0:
				_attack_phase = "recover"
				_attack_timer = data.recover * _atk_mult()
				_tween_back(data.recover * _atk_mult())
		"recover":
			# 다음 공격이 예약돼 있으면 회복 동작 중간에 이어서 휘두른다.
			if _queued != "" and _attack_timer <= data.recover * _atk_mult() * 0.55:
				var nxt := _queued
				_queued = ""
				_start_attack(nxt)
				if sm.state == "attack" and _move == nxt:
					return
			if _attack_timer <= 0.0:
				sm.go("free")


## 기술 능력치와 질풍에 따른 공격 동작 시간 배율
func _atk_mult() -> float:
	return build.attack_time_mult() * skills.attack_mult()


func _enter_active(data: Dictionary) -> void:
	_attack_phase = "active"
	_attack_timer = data.active
	_play("heavy" if _move in ["heavy", "charge", "slash3"] else ("dash" if _move == "grab" else "light"), 1.0, -6.0)
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


# ---------------- 잡기 (F) ----------------
# 가위바위보: 공격 > 잡기 > 막기 > 공격.
# 막고 있는 상대는 잡아서 던진다. 휘두르는 상대를 잡으려 하면 끊긴다. 빗나가면 빈틈이 크다.

func try_grab() -> void:
	if not _can_act():
		return
	if sm.state == "attack" and _move == "grab":
		return
	var winding := (sm.state == "attack" and _attack_phase == "windup") or sm.state == "charge"
	if winding:
		_try_feint()   # 휘두르는 척하다 잡기
	elif not sm.is_in(["free", "block"]):
		return
	if stamina < float(MoveSet.MOVES.grab.cost) * 0.5:
		return
	_press_owner = ""
	sm.go("attack", {"move": "grab"})


func is_grabbing() -> bool:
	return sm.state == "attack" and _move == "grab"


## 잡기를 끊을 수 있는 공격 중인가 (준비하거나 휘두르는 중, 힘 모으는 중)
func attack_threat() -> bool:
	if sm.state == "charge":
		return true
	return sm.state == "attack" and _move != "grab" and _attack_phase in ["windup", "active"]


## 지금 하고 있는 공격의 방향 ("" = 공격 중 아님)
func attack_dir() -> String:
	if sm.state == "charge":
		return MoveSet.MOVES.charge.dir
	if sm.state == "attack" and _move != "":
		return MoveSet.MOVES[_move].get("dir", "")
	return ""


## 던질 방향: 보는 쪽. A/D 를 누르고 있으면 그쪽으로 비스듬히.
func _throw_dir() -> Vector3:
	var fwd := -transform.basis.z
	fwd.y = 0
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if _can_act() else Vector2.ZERO
	var right := transform.basis.x
	right.y = 0
	return (fwd.normalized() + right.normalized() * input.x * 0.9).normalized()


func _check_grab(data: Dictionary) -> void:
	if _already_hit.has("grab"):
		return
	var fwd := -transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var best: Node3D = null
	var best_d := float(data.reach) + 0.4
	for n in get_tree().get_nodes_in_group("grabbable"):
		var b := n as Node3D
		if b == null or b == self:
			continue
		var to := b.global_position - global_position
		if absf(to.y) > 1.2:
			continue
		to.y = 0
		var d := to.length()
		if d < best_d and (d < 0.5 or fwd.dot(to / d) > 0.5):
			best = b
			best_d = d
	if best == null:
		return
	_already_hit["grab"] = true
	var info := {"damage": int(round(float(data.damage) * build.damage_mult())), "react": "thrown",
			"throw": _throw_dir() * float(data.throw_speed) + Vector3.UP * float(data.throw_up)}
	var result: String = best.take_grab(info, self)
	_grab_result(result, best)


## 잡기 결과에 따라 내 몸이 어떻게 되는지
func _grab_result(result: String, target: Node3D) -> void:
	var to := target.global_position - global_position
	to.y = 0
	match result:
		"thrown":
			_play("heavy", 0.7, -2.0)
			combat_event.emit("잡아 던지기!", Color(0.95, 0.6, 1.0))
			_shake = 0.6
			_kick.x += deg_to_rad(4.0)
			_on_hit_landed(true)
		"beaten":
			# 상대가 휘두르는 중이었다: 잡기가 끊긴다
			combat_event.emit("잡기가 끊겼다!", Color(1.0, 0.45, 0.35))
			_react("grab_fail", to)
		"clash":
			# 서로 잡으려다 맞잡았다: 둘 다 튕겨 난다
			combat_event.emit("맞잡기!", Color(0.9, 0.9, 0.9))
			_play("clang", 0.7)
			_react("recoil", to)
		"blocked":
			combat_event.emit("잡히지 않는다", Color(0.85, 0.85, 0.85))
			_react("grab_fail", to)
		"dodged":
			combat_event.emit("피했다!", Color(1.0, 0.7, 0.4))


## 상대가 나를 잡았을 때. 결과: "thrown" 던져짐, "beaten" 내 공격이 잡기를 끊음, "clash" 맞잡기,
## "dodged" 피함, "blocked" (철벽)
func take_grab(info: Dictionary, attacker: Node3D) -> String:
	var r := _take_grab(info, attacker)
	attack_received.emit("grabbed" if r == "thrown" else "grab_" + r)
	return r


func _take_grab(info: Dictionary, attacker: Node3D) -> String:
	if dead:
		return "none"
	var to_attacker := attacker.global_position - global_position
	to_attacker.y = 0
	if _iframes > 0.0:
		combat_event.emit("잡기 회피!", Color(0.6, 0.9, 1.0))
		return "dodged"
	if sm.state == "iron":
		return "blocked"
	if is_grabbing() and _attack_phase == "windup":
		_react("recoil", to_attacker)
		combat_event.emit("맞잡기!", Color(0.9, 0.9, 0.9))
		return "clash"
	if attack_threat():
		combat_event.emit("잡기를 끊었다!", Color(0.6, 1.0, 0.6))
		return "beaten"
	_take_damage(int(info.damage), to_attacker)
	combat_event.emit("잡혔다!", Color(1.0, 0.45, 0.8))
	_react("thrown", Vector3.ZERO)
	_kick = Vector3(deg_to_rad(-10.0), 0, deg_to_rad(8.0))
	apply_throw(info.throw)
	return "thrown"


## 던져진다: 날아가는 동안 벽에 세게 부딪히면 '벽꽝'
func apply_throw(vec: Vector3) -> void:
	_thrown_t = float(MoveSet.THROW.slam_time)
	if has_method("apply_knockback"):
		call("apply_knockback", vec)
	else:
		velocity = vec


func _wall_slam() -> void:
	_thrown_t = 0.0
	var dmg := int(MoveSet.THROW.wall_slam_damage)
	_take_damage(dmg, -_wall_n)
	combat_event.emit("벽꽝! -%d" % dmg, Color(1.0, 0.5, 0.3))
	_shake = 0.9
	_kick += Vector3(deg_to_rad(8.0), 0, 0)
	Fx.impact(get_parent(), global_position + Vector3.UP * 1.2 - _wall_n * 0.3, _wall_n, Color(0.9, 0.85, 0.75), 18)
	_react("wall_slam", Vector3.ZERO)


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
	_stun_time = r.time * (build.stun_mult() if _stun_kind in ["flinch", "stagger", "guard_break"] else 1.0)
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
	if sm.state == "hang" and not dead:
		var hung := _hit_while_hanging(info, attacker)
		attack_received.emit(hung)
		return hung
	var result := _resolve_attack(info, attacker)
	_after_received(result, info, attacker)
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
	if sm.state == "iron":
		# 철벽: 어느 방향이든, 어떤 공격이든 막는다. 기력도 줄지 않는다.
		_play("clang", 0.8)
		Fx.sparks(get_parent(), _blade_tip.global_position, to_attacker.normalized(), 24, Color(1.0, 0.85, 0.4))
		combat_event.emit("철벽!", Color(1.0, 0.85, 0.4))
		_shake = 0.3
		return "blocked"
	if blocking and in_front and info.guard != "unblockable" and not AttackDir.blocks(guard_dir, info.get("dir", "")):
		# 막기 방향이 틀렸다: 그대로 맞는다
		combat_event.emit("%s 공격이었다!" % AttackDir.NAMES.get(info.dir, ""), Color(1.0, 0.55, 0.35))
		_take_damage(damage, to_attacker)
		_react(info.react, to_attacker)
		return "wrong_guard"
	if blocking and in_front and info.guard != "unblockable":
		var contact := _blade_tip.global_position
		if _guard_t <= build.parry_window():
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
			_use_stamina(BLOCK_COST.get(info.react, 14.0) * float(info.get("pressure", 1.0)))
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
	hp_changed.emit(hp, max_hp)
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
		info.damage = int(round(float(info.damage) * build.damage_mult() * vkit.damage_mult())) + randi_range(-2, 2)
		info.power = vkit.powered()
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
	elif sm.state == "wallrun":
		# 벽 반대쪽으로 화면이 기운다
		var ln := global_transform.basis.inverse() * _run_n
		roll_target = ln.x * deg_to_rad(12.0)
	_roll = lerpf(_roll, roll_target, clampf(delta * 10.0, 0, 1))
	camera.rotation = _kick + Vector3(0, 0, _roll)
	# 달리거나 대시할 때 시야가 넓어짐
	var target_fov := 78.0
	if sm.state == "dash":
		target_fov = 90.0
	elif sm.state == "wallrun":
		target_fov = 92.0
	elif sm.state == "climb":
		target_fov = 82.0
	elif sm.state == "grapple":
		target_fov = 94.0
	elif sm.state == "plunge":
		target_fov = 96.0
	elif sm.state == "zip":
		target_fov = 90.0
	elif sm.state == "charge":
		target_fov = 78.0 - _charge_level * 6.0
	elif sprinting and horiz > WALK_SPEED:
		target_fov = 86.0
	if skills.haste_active():
		target_fov += 4.0
	camera.fov = lerpf(camera.fov, target_fov, clampf(delta * 8.0, 0, 1))
	# 칼도 걸음에 맞춰 살짝 흔들림
	var tr := Vector3.ZERO
	if _tremble > 0.0:
		var t := Time.get_ticks_msec() * 0.06
		tr = Vector3(sin(t * 1.3), sin(t * 1.9), 0) * _tremble * 0.006
	_weapon_root.position = WEAPON_REST + Vector3(bob.x * 0.5, -bob.y * 0.6, 0) + tr


# ---------------- 특수 스킬 ----------------
# 스킬 수치(쿨타임, 기력, 거리)는 scripts/character/character_build.gd 의 SKILLS 표에 있다.
# 쿨타임과 기력 계산은 SkillKit 이 하고, 여기서는 몸을 움직인다.

## E 는 첫 번째 스킬, R 은 두 번째 스킬. 늘 켜져 있는 스킬(벽타기, 이중 점프)이면 아무 일도 없다.
func use_skill_slot(slot: int) -> void:
	if slot < build.skills.size():
		use_skill(build.skills[slot])


func use_skill(skill: String) -> bool:
	if not _can_act() or not CharacterBuild.SKILLS[skill].active:
		return false
	if sm.is_in(["stagger", "grapple", "iron"]):
		return false
	if not skills.can_use(skill):
		if skills.cooldown_left(skill) > 0.0:
			combat_event.emit("%s 준비 중 (%.0f초)" % [CharacterBuild.SKILLS[skill].name,
					ceilf(skills.cooldown_left(skill))], Color(0.8, 0.8, 0.8))
		else:
			combat_event.emit("기력 부족", Color(0.9, 0.75, 0.5))
		return false
	match skill:
		"blink":
			skills.use(skill)
			_do_blink()
		"grapple":
			var aim := _grapple_aim()
			if aim.is_empty():
				combat_event.emit("닿는 곳이 없다", Color(0.8, 0.8, 0.8))
				return false
			skills.use(skill)
			_cancel_action()
			sm.go("grapple", aim)
		"haste":
			skills.use(skill)
			combat_event.emit("질풍!", Color(0.55, 1.0, 0.7))
			_play("dash", 0.7, -4.0)
			camera.fov += 6.0
		"iron_guard":
			skills.use(skill)
			_cancel_action()
			sm.go("iron")
	return true


## 하던 공격/모으기를 멈춘다 (스킬로 끊을 때)
func _cancel_action() -> void:
	if sm.is_in(["attack", "charge", "block", "climb", "wallrun"]):
		_queued = ""
		sm.go("free")
		_pose_to(MoveSet.FP_POSES.rest, 0.1)


# --- 점멸 ---

func _do_blink() -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO:
		input = Vector2(0, -1)   # 방향키가 없으면 앞으로
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	blink_toward(dir)


## dir 방향(수평)으로 순간이동. 벽이 있으면 벽 앞에서 멈춘다.
func blink_toward(dir: Vector3) -> void:
	_cancel_action()
	var dist: float = CharacterBuild.SKILLS.blink.range
	for h in [0.4, 1.0, 1.6]:
		var hit := _cast(global_position + Vector3.UP * h, dir * dist)
		if not hit.is_empty():
			var hp_flat: Vector3 = hit.position - global_position
			hp_flat.y = 0
			dist = minf(dist, hp_flat.length() - 0.55)
	dist = maxf(dist, 0.0)
	var start := global_position + Vector3.UP * 1.0
	global_position += dir * dist
	velocity.x = dir.x * 7.0
	velocity.z = dir.z * 7.0
	velocity.y = maxf(velocity.y, 0.5)
	# 순간이동하는 순간은 맞지 않는다. 아슬하게 피하면 반격 기회도 열린다.
	_iframes = 0.3
	_since_dash = 0.0
	_counter_used = false
	var c := Color(0.6, 0.75, 1.0)
	Fx.sparks(get_parent(), start, -dir, 18, c)
	Fx.sparks(get_parent(), global_position + Vector3.UP * 1.0, dir, 18, c)
	camera.fov += 14.0
	_roll = -signf(input_side(dir)) * deg_to_rad(6.0)
	_play("dash", 1.6, -5.0)


## dir 가 내 오른쪽이면 +, 왼쪽이면 -
func input_side(dir: Vector3) -> float:
	return transform.basis.x.dot(dir)


# --- 갈고리 ---

func _build_rope() -> void:
	_rope = MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.025, 0.025, 1.0)
	_rope.mesh = m
	_rope.material_override = LowPoly.mat(Color(0.35, 0.25, 0.15), 0.9)
	_rope.top_level = true
	_rope.visible = false
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rope)


## 조준점에 줄을 걸 수 있으면 {"point", "body"}, 아니면 {}
func _grapple_aim() -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * float(CharacterBuild.SKILLS.grapple.range)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {}
	var body: Node3D = hit.collider if hit.collider is Duelist else null
	if (hit.position as Vector3).distance_to(from) < 2.5:
		return {}
	return {"point": hit.position, "body": body}


func _grapple_target() -> Vector3:
	if _grap_body and is_instance_valid(_grap_body):
		return _grap_body.global_position + Vector3.UP * 1.0
	return _grap_point


func _grapple_enter(d: Dictionary) -> void:
	_grap_point = d.point
	_grap_body = d.body
	_rope.visible = true
	_pose_to(MoveSet.FP_POSES.wallrun, 0.1)
	_play("dash", 0.6, -4.0)
	_update_rope()


func _grapple_update(_delta: float) -> void:
	var target := _grapple_target()
	var to := target - (global_position + Vector3.UP * 1.0)
	var dist := to.length()
	var stop := 2.1 if _grap_body else 1.1
	var spd: float = CharacterBuild.SKILLS.grapple.speed
	var stalled := sm.time > 0.25 and get_real_velocity().length() < 2.0
	if dist < stop or sm.time > 1.4 or stalled or (_can_act() and Input.is_action_just_pressed("jump")):
		if _grap_body:
			velocity = to.normalized() * 4.0
		else:
			# 끝에 닿으면 살짝 튀어 올라 지붕 모서리 위로 올라설 수 있게
			var flat := Vector3(to.x, 0, to.z).normalized()
			velocity = flat * 4.0 + Vector3.UP * 5.5
		sm.go("free")
		return
	velocity = to / dist * spd


func _grapple_exit() -> void:
	_rope.visible = false
	_pose_to(MoveSet.FP_POSES.rest, 0.15)


func _update_rope() -> void:
	if not _rope.visible:
		return
	var a := camera.global_transform * Vector3(0.25, -0.25, -0.4)
	var b := _grapple_target()
	var rope_len := a.distance_to(b)
	if rope_len < 0.05:
		return
	_rope.global_transform = Transform3D(Basis.looking_at(b - a, Vector3.UP if absf((b - a).normalized().y) < 0.98 else Vector3.RIGHT), (a + b) * 0.5)
	_rope.scale = Vector3(1, 1, rope_len)


# --- 철벽 ---

func _iron_enter(_d: Dictionary) -> void:
	_pose_to(MoveSet.FP_POSES.block, 0.06)
	_blade_mat.emission = Color(1.0, 0.85, 0.4)
	_blade_mat.emission_energy_multiplier = 1.6
	combat_event.emit("철벽!", Color(1.0, 0.85, 0.4))
	_play("charged", 0.8, -4.0)


func _iron_update(_delta: float) -> void:
	if sm.time >= float(CharacterBuild.SKILLS.iron_guard.duration):
		sm.go("free")


func _iron_exit() -> void:
	_blade_mat.emission = Color(1.0, 0.72, 0.3)
	_blade_mat.emission_energy_multiplier = 0.0
	_pose_to(MoveSet.FP_POSES.rest, 0.15)


# ---------------- 높이: 낙하 찍기, 공중 베기, 난간 매달리기, 짚라인, 밀려 떨어지기 ----------------
# 공통 규칙과 수치는 scripts/combat/vertical_kit.gd, 기술 수치는 MoveSet 의 plunge / air_slash / ledge_slash.

const PLUNGE_MIN_HEIGHT := 1.6   # 이만큼 떠 있어야 낙하 찍기
const PLUNGE_SPEED := 22.0

var _plunge_from := 0.0
var _plunge_landed := false
var _hang := {}
var _hang_cd := 0.0
var _mantle_attack := ""         # 난간에서 올라서자마자 쓸 기술
var _zip: Zipline
var _zip_t := 0.0
var _zip_cd := 0.0
var _zip_stall := 0.0


## 공중, 난간, 짚라인에서 누른 공격. 처리했으면 true.
func _vertical_attack(kind: String) -> bool:
	if sm.state == "hang":
		_mantle_from_hang("ledge_slash")
		return true
	if sm.state == "zip":
		_zip_release(_zip.dir() * Zipline.SPEED * 0.6 if is_instance_valid(_zip) else Vector3.ZERO)
		# 줄에서 손을 놓으며 그대로 아래로 찍거나 벤다
	if is_on_floor() or not sm.is_in(["free", "dash", "wallrun", "climb"]):
		return false
	var h := vkit.height_above_ground(14.0)
	var looking_down := head.rotation.x < deg_to_rad(-18)
	if h >= PLUNGE_MIN_HEIGHT and (kind == "heavy" or looking_down or h >= 3.2):
		if stamina < float(MoveSet.MOVES.plunge.cost) * 0.5:
			return false
		sm.go("plunge")
		return true
	if kind in ["combo", "light"] and h > 0.6:
		_start_attack("air_slash")
		return sm.state == "attack"
	return false


# --- 낙하 찍기 ---

func _plunge_enter(_d: Dictionary) -> void:
	var data: Dictionary = MoveSet.MOVES.plunge
	_use_stamina(float(data.cost))
	_plunge_from = global_position.y
	_plunge_landed = false
	_queued = ""
	var fwd := -transform.basis.z
	fwd.y = 0
	velocity = fwd.normalized() * 2.5 + Vector3.UP * 2.0
	_pose_to(data.fp.windup, float(data.windup))
	_play("heavy", 0.75, -4.0)
	attack_started.emit("plunge")


func _plunge_update(delta: float) -> void:
	var data: Dictionary = MoveSet.MOVES.plunge
	if _plunge_landed:
		if sm.time >= float(data.recover) * _atk_mult():
			sm.go("free")
		return
	if sm.time < float(data.windup):
		return
	if sm.time - delta < float(data.windup):
		_pose_to(data.fp.strike, 0.12, Tween.TRANS_CUBIC, Tween.EASE_IN)
		_play("dash", 0.7, -4.0)
	# 내리꽂으며 보는 쪽으로 조금 움직일 수 있다
	var fwd := -transform.basis.z
	fwd.y = 0
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if _can_act() else Vector2.ZERO
	var steer := (transform.basis * Vector3(input.x, 0, input.y)) * 4.5 + fwd.normalized() * 1.5
	velocity.x = lerpf(velocity.x, steer.x, clampf(delta * 6.0, 0, 1))
	velocity.z = lerpf(velocity.z, steer.z, clampf(delta * 6.0, 0, 1))
	velocity.y = -PLUNGE_SPEED
	if is_on_floor() or sm.time > 2.5:
		_plunge_impact()


func _plunge_impact() -> void:
	var data: Dictionary = MoveSet.MOVES.plunge
	var drop := maxf(_plunge_from - global_position.y, 0.0) + 1.0
	var k := clampf((drop - PLUNGE_MIN_HEIGHT) / 6.0, 0.0, 1.0)
	var dmg := int(lerpf(float(data.damage), float(data.damage_max), k))
	_plunge_landed = true
	sm.time = 0.0
	velocity = Vector3.ZERO
	_shake = 0.6 + k * 0.5
	_kick.x -= deg_to_rad(5.0 + k * 4.0)
	_play("clang", 0.55, -1.0)
	var feet := global_position + Vector3.UP * 0.1
	Fx.impact(get_parent(), feet, Vector3.UP, Color(0.82, 0.74, 0.6), 26)
	Fx.sparks(get_parent(), feet, Vector3.UP, 20, Color(1.0, 0.8, 0.45))
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = float(data.reach)
	q.shape = sph
	q.transform = Transform3D(Basis(), global_position + Vector3.UP * 0.7)
	q.collision_mask = 2
	q.exclude = [get_rid()]
	var landed := false
	for r in get_world_3d().direct_space_state.intersect_shape(q, 8):
		var body: Object = r.collider
		if body == null or not body.has_method("take_hit"):
			continue
		var to_t: Vector3 = (body as Node3D).global_position - global_position
		to_t.y = 0
		var dir := to_t.normalized() if to_t.length() > 0.05 else -transform.basis.z
		var info := {"move": "plunge", "react": data.react, "guard": data.guard, "dir": data.get("dir", "high"),
				"damage": int(round(dmg * build.damage_mult() * vkit.damage_mult())), "pressure": build.guard_pressure(),
				"power": vkit.powered(), "knockdown": true}
		var result = body.take_hit(info, dir, self)
		if result in ["hit", "guard_broken"] and body is Duelist:
			landed = true
	if landed:
		combat_event.emit("낙하 찍기!", Color(1.0, 0.75, 0.3))
		_on_hit_landed(true)
	vkit.reset_fall()


func _plunge_exit() -> void:
	_pose_to(MoveSet.FP_POSES.rest, 0.2)


# --- 난간 매달리기 ---

## 공중에서: 손이 닿는 짚라인을 잡거나, 눈앞 난간을 잡는다
func _try_hang_or_zip(input: Vector2) -> bool:
	if not _can_act():
		return false
	if arena and _zip_cd <= 0.0 and sm.is_in(["free", "wallrun", "climb"]):
		var z := arena.zipline_near(global_position)
		if not z.is_empty():
			sm.go("zip", {"z": z[0], "t": z[1]})
			return true
	if _hang_cd > 0.0 or velocity.y > 0.5 or input.y > 0.3:
		return false
	if not (sm.state == "free" or (sm.state == "stagger" and sm.time > 0.25)):
		return false
	var ledge := vkit.find_ledge(-transform.basis.z)
	if ledge.is_empty():
		return false
	sm.go("hang", ledge)
	return true


func _hang_enter(d: Dictionary) -> void:
	_hang = d
	_mantle_attack = ""
	var n: Vector3 = d.n
	var p: Vector3 = d.point
	global_position = Vector3(p.x, float(d.y) - 1.55, p.z) + n * 0.42
	velocity = Vector3.ZERO
	vkit.reset_fall()
	_pose_to(MoveSet.FP_POSES.hang, 0.1)
	_play("dash", 0.7, -10.0)
	combat_event.emit("매달림  Space 올라서기 · 클릭 뛰어올라 베기", Color(0.95, 0.92, 0.75))


func _hang_update(delta: float) -> void:
	velocity = Vector3.ZERO
	_use_stamina(VerticalKit.HANG_COST * delta)
	if not _can_act():
		return
	if Input.is_action_just_pressed("jump"):
		_mantle_from_hang("")
		return
	if Input.is_action_pressed("move_back") or stamina <= 0.0 or sm.time > VerticalKit.HANG_MAX:
		_drop_from_hang()


func _hang_exit() -> void:
	if sm.state != "climb":
		_pose_to(MoveSet.FP_POSES.rest, 0.15)


func _drop_from_hang() -> void:
	_hang_cd = VerticalKit.HANG_COOLDOWN
	velocity = (_hang.n as Vector3) * 1.5
	sm.go("free")


## 난간을 짚고 올라선다. attack 을 주면 올라서자마자 그 기술을 쓴다 (난간 반격).
func _mantle_from_hang(attack: String) -> void:
	var ledge_y: float = _hang.y
	_wall_n = _hang.n
	sm.go("climb")
	_ledge_y = ledge_y
	_mantle_attack = attack
	if attack != "":
		_pose_to(MoveSet.MOVES[attack].fp.windup, 0.15)
		combat_event.emit("난간 반격!", Color(1.0, 0.75, 0.35))


func is_hanging() -> bool:
	return sm.state == "hang"


## 매달려 있을 때 맞으면 막지 못하고 손을 놓친다
func _hit_while_hanging(info: Dictionary, attacker: Node3D) -> String:
	var to_a := attacker.global_position - global_position
	to_a.y = 0
	_take_damage(int(info.damage), to_a)
	combat_event.emit("난간에서 떨어졌다!", Color(1.0, 0.5, 0.35))
	_hang_cd = 1.0
	var out: Vector3 = _hang.n
	sm.go("free")
	velocity = out * 2.5 + Vector3.DOWN
	vkit.knock()
	if not dead:
		_react("flinch", Vector3.ZERO)
	return "hit"


# --- 짚라인 ---

func _zip_enter(d: Dictionary) -> void:
	_zip = d.z
	_zip_t = d.t
	_zip_stall = 0.0
	_zip.rider_count += 1
	_pose_to(MoveSet.FP_POSES.zip, 0.12)
	_play("dash", 0.6, -6.0)


func _zip_update(delta: float) -> void:
	if not is_instance_valid(_zip) or not _zip.alive:
		_zip_release(Vector3.ZERO)
		return
	_zip_t += Zipline.SPEED * delta / _zip.length()
	if _zip_t >= 1.0:
		_zip_release(_zip.dir() * 5.0 + Vector3.UP * 2.5)
		return
	var target := _zip.feet_at(_zip_t)
	velocity = (target - global_position) / maxf(delta, 0.001)
	# 무언가에 막히면 놓는다
	if sm.time > 0.3 and get_real_velocity().length() < 2.0:
		_zip_stall += delta
		if _zip_stall > 0.2:
			_zip_release(Vector3.ZERO)
			return
	if not _can_act():
		return
	if Input.is_action_just_pressed("jump"):
		_zip_release(_zip.dir() * Zipline.SPEED * 0.7 + Vector3.UP * 4.5)
	elif Input.is_action_pressed("move_back") and sm.time > 0.25:
		_zip_release(_zip.dir() * Zipline.SPEED * 0.5)


func _zip_release(v: Vector3) -> void:
	velocity = v
	_zip_cd = 0.6
	vkit.reset_fall()
	if sm.state == "zip":
		sm.go("free")


func _zip_exit() -> void:
	if is_instance_valid(_zip):
		_zip.rider_count -= 1
	_pose_to(MoveSet.FP_POSES.rest, 0.15)


# --- 밀려 떨어지기, 낭떠러지 ---

## 강한 공격이나 던지기로 날려 보낸다 (다른 기술도 이 함수를 쓰면 낙하 피해가 따라온다)
func apply_knockback(vec: Vector3) -> void:
	velocity.x = vec.x
	velocity.z = vec.z
	velocity.y = maxf(velocity.y, vec.y)
	vkit.knock()


## 맞은 결과에 따라 날려 보내기와 넘어짐을 붙인다 (_resolve_attack 은 그대로 두고 바깥에서)
func _after_received(result: String, info: Dictionary, attacker: Node3D) -> void:
	if dead or not (result in ["hit", "guard_broken"]):
		return
	vkit.knock(VerticalKit.FLINCH_KNOCK_TIME)
	var l := VerticalKit.launch_for(info)
	if l != Vector2.ZERO:
		var away := global_position - attacker.global_position
		away.y = 0
		away = away.normalized() if away.length() > 0.05 else transform.basis.z
		apply_knockback(away * l.x + Vector3.UP * l.y)
	if info.get("knockdown", false):
		_react("knockdown", Vector3.ZERO)


func _vertical_tick(delta: float) -> void:
	_hang_cd = maxf(_hang_cd - delta, 0.0)
	_zip_cd = maxf(_zip_cd - delta, 0.0)
	var f := vkit.tick(delta, is_on_floor())
	if f == -1:
		_fall_into_void()
	elif f > 0 and not dead:
		_take_damage(f, Vector3.ZERO)
		combat_event.emit("추락! -%d" % f, Color(1.0, 0.5, 0.3))
		if not dead:
			_react("knockdown", Vector3.ZERO)


func _fall_into_void() -> void:
	if sm.state != "free":
		sm.go("free")
	global_position = arena.safe_spawn(self) if arena else Vector3(0, 0.1, 0)
	velocity = Vector3.ZERO
	vkit.reset_fall()
	_iframes = 1.0
	_shake = 0.6
	# 연습장에서는 다시 서기만 한다. 대결 중이면 큰 피해.
	if arena and arena.director.running and not dead:
		var dmg := int(ceilf(max_hp * VerticalKit.VOID_DAMAGE))
		combat_event.emit("낭떠러지! -%d" % dmg, Color(1.0, 0.35, 0.3))
		_take_damage(dmg, Vector3.ZERO)
	else:
		combat_event.emit("낭떠러지!", Color(1.0, 0.35, 0.3))


func on_pickup(kind: String) -> void:
	_play("charged", 1.3, -4.0)
	if kind == "power":
		_blade_mat.emission = Color(1.0, 0.55, 0.2)
