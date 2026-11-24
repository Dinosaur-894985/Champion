class_name Duelist
extends CharacterBody3D
## AI 상대 (결투사). 다가와서 베고, 막고, 물러나고, 내 공격에 반응한다.
## 공격하기 전에는 칼이 빛나고 경고음이 나서 보고 막거나 피할 수 있다.

signal hp_changed(value: int, max_value: int)
signal combat_event(text: String, color: Color)
signal died

const MAX_HP := 100
const MOVE_SPEED := 3.9
const STRAFE_SPEED := 2.6
const TURN_SPEED := 7.0         # 평소에 몸을 돌리는 빠르기
const WINDUP_TURN_SPEED := 2.0  # 공격 준비 중에는 느리게 돈다 → 옆으로 대시하면 피할 수 있다
const REACH := 2.45
const HIT_ANGLE := 0.55         # 칼이 닿는 앞쪽 범위 (cos 값)

const ATTACKS := {
	"light": {"windup": 0.45, "strike": 0.13, "recover": 0.45, "damage": 13, "lunge": 3.0},
	"heavy": {"windup": 0.8, "strike": 0.16, "recover": 0.75, "damage": 27, "lunge": 5.0},
}

# 성격 (나중에 난이도나 '거울' 모드에서 바꿀 수 있다)
var aggression := 0.55
var block_chance := 0.45
var parry_chance := 0.3
var reaction_time := 0.1
var counter_chance := 0.65
var stats := {}   # 점검용 기록: 받은 공격 결과, 한 행동 횟수

var hp := MAX_HP
var active := false
var dead := false
var target: Player

var state := "idle"   # idle, approach, circle, windup, strike, recover, block, stagger, dash, dead
var _state_t := 0.0
var _think_t := 0.0
var _strafe_dir := 1.0
var _attack := ""
var _combo_left := 0
var _hit_done := false
var _alert := 0.0               # 맞은 직후 경계 상태 (더 잘 막음)
var _push := Vector3.ZERO       # 밀려남, 대시
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _walk_phase := 0.0
var _hits_in_row := 0
var _hits_reset := 0.0

# 몸 부품
var _model: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_r: Node3D
var _wrist: Node3D
var _arm_l: Node3D
var _torso: Node3D
var _blade_mat: StandardMaterial3D
var _blade_tip: Node3D
var _flash_mat: StandardMaterial3D
var _flash := 0.0
var _body_meshes: Array[MeshInstance3D] = []
var _audio: AudioStreamPlayer3D
var _sounds := {}

# 자세 (어깨 회전, 손목 회전) — 각도는 도(degree)
const POSES := {
	"guard": [Vector3(55, -15, 0), Vector3(0, 0, 0)],
	"light_windup": [Vector3(95, -80, 0), Vector3(0, 90, 0)],
	"light_strike": [Vector3(85, 75, 0), Vector3(0, 90, 0)],
	"heavy_windup": [Vector3(175, -10, 0), Vector3(0, 0, 0)],
	"heavy_strike": [Vector3(35, 0, 0), Vector3(0, 0, 0)],
	"block": [Vector3(80, 25, 0), Vector3(0, 90, 0)],
	"stagger": [Vector3(20, -40, 0), Vector3(0, 30, 0)],
}
var _pose_shoulder := Vector3(55, -15, 0)
var _pose_wrist := Vector3.ZERO
var _pose_speed := 12.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.85
	col.shape = cap
	col.position.y = 0.925
	add_child(col)
	_build_body()
	_audio = AudioStreamPlayer3D.new()
	_audio.unit_size = 8.0
	_audio.max_polyphony = 4
	add_child(_audio)
	_sounds = {
		"warn_light": Sfx.warn(false),
		"warn_heavy": Sfx.warn(true),
		"swing": Sfx.whoosh(0.24, 0.85),
		"hit": Sfx.thud(0.2, false),
		"hit_heavy": Sfx.thud(0.28, true),
		"clang": Sfx.clang(0.45, 0.92),
		"parry": Sfx.clang(0.7, 1.15),
	}


func _play(snd: String, volume: float = 0.0) -> void:
	_audio.stream = _sounds[snd]
	_audio.volume_db = volume
	_audio.pitch_scale = randf_range(0.94, 1.06)
	_audio.play()


# ---------------- 몸 만들기 ----------------

func _build_body() -> void:
	var armor := LowPoly.mat(Color(0.23, 0.25, 0.29), 0.55, 0.35)
	var armor_light := LowPoly.mat(Color(0.36, 0.39, 0.44), 0.45, 0.45)
	var cloth := LowPoly.mat(Color(0.08, 0.55, 0.56), 0.85)
	var cloth_dark := LowPoly.mat(Color(0.06, 0.36, 0.38), 0.9)
	var leather := LowPoly.mat(Color(0.24, 0.15, 0.10), 0.9)
	var visor := LowPoly.mat(Color(0.05, 0.05, 0.06), 0.3)
	_flash_mat = LowPoly.mat(Color(1, 0.95, 0.9, 0.0))
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var s := 900

	_model = Node3D.new()
	add_child(_model)

	# 다리
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(0.13 * side, 0.92, 0)
		_model.add_child(leg)
		LowPoly.part(leg, LowPoly.cyl(0.085, 0.1, 0.48, 6), cloth_dark, Vector3(0, -0.24, 0))
		LowPoly.part(leg, LowPoly.cyl(0.07, 0.085, 0.42, 6), armor, Vector3(0, -0.66, 0))
		LowPoly.part(leg, LowPoly.box(Vector3(0.13, 0.08, 0.24)), leather, Vector3(0, -0.88, -0.04))
		if side < 0:
			_leg_l = leg
		else:
			_leg_r = leg

	# 몸통
	_torso = Node3D.new()
	_torso.position = Vector3(0, 0.95, 0)
	_model.add_child(_torso)
	_body_meshes.append(LowPoly.part(_torso, LowPoly.cyl(0.2, 0.17, 0.22, 7), leather, Vector3(0, 0.08, 0)))
	_body_meshes.append(LowPoly.part(_torso, LowPoly.cyl(0.25, 0.19, 0.5, 7), armor, Vector3(0, 0.42, 0), Vector3.ZERO, 0.01, s))
	LowPoly.part(_torso, LowPoly.box(Vector3(0.3, 0.32, 0.06)), armor_light, Vector3(0, 0.45, -0.19), Vector3(-8, 0, 0))
	# 허리띠 천 (포인트 색)
	LowPoly.part(_torso, LowPoly.cyl(0.215, 0.215, 0.07, 8), cloth, Vector3(0, 0.17, 0))
	LowPoly.part(_torso, LowPoly.box(Vector3(0.12, 0.34, 0.03)), cloth, Vector3(0.06, -0.05, -0.2), Vector3(0, 0, -6))
	# 어깨 보호대
	for side in [-1.0, 1.0]:
		LowPoly.part(_torso, LowPoly.sphere(0.13, 7, 4), armor_light, Vector3(0.29 * side, 0.64, 0), Vector3(0, 0, -20 * side))
	# 머리 (투구)
	var head := Node3D.new()
	head.position = Vector3(0, 0.86, 0)
	_torso.add_child(head)
	_body_meshes.append(LowPoly.part(head, LowPoly.sphere(0.15, 8, 6), armor, Vector3(0, 0.05, 0), Vector3.ZERO, 0.004, s + 1))
	LowPoly.part(head, LowPoly.box(Vector3(0.2, 0.045, 0.05)), visor, Vector3(0, 0.06, -0.135))
	LowPoly.part(head, LowPoly.box(Vector3(0.04, 0.1, 0.3)), cloth, Vector3(0, 0.2, 0.0))
	LowPoly.part(head, LowPoly.cyl(0.08, 0.1, 0.08, 7), armor_light, Vector3(0, -0.1, 0))

	# 왼팔 (방패 없이 균형 잡는 팔)
	_arm_l = Node3D.new()
	_arm_l.position = Vector3(-0.3, 0.6, 0)
	_arm_l.rotation_degrees = Vector3(20, 0, -12)
	_torso.add_child(_arm_l)
	LowPoly.part(_arm_l, LowPoly.cyl(0.06, 0.065, 0.3, 6), armor, Vector3(0, -0.15, 0))
	LowPoly.part(_arm_l, LowPoly.cyl(0.05, 0.06, 0.28, 6), cloth_dark, Vector3(0, -0.43, 0))
	LowPoly.part(_arm_l, LowPoly.sphere(0.055, 6, 4), leather, Vector3(0, -0.6, 0))

	# 오른팔 + 칼
	_arm_r = Node3D.new()
	_arm_r.position = Vector3(0.3, 0.6, 0)
	_torso.add_child(_arm_r)
	LowPoly.part(_arm_r, LowPoly.cyl(0.06, 0.065, 0.3, 6), armor, Vector3(0, -0.15, 0))
	LowPoly.part(_arm_r, LowPoly.cyl(0.05, 0.06, 0.28, 6), cloth_dark, Vector3(0, -0.43, 0))
	_wrist = Node3D.new()
	_wrist.position = Vector3(0, -0.6, 0)
	_arm_r.add_child(_wrist)
	LowPoly.part(_wrist, LowPoly.sphere(0.055, 6, 4), leather, Vector3.ZERO)
	# 칼날은 손에서 앞(-Z)으로 뻗는다
	var sword := Node3D.new()
	_wrist.add_child(sword)
	var steel := LowPoly.mat(Color(0.72, 0.75, 0.8), 0.3, 0.85)
	var brass := LowPoly.mat(Color(0.6, 0.45, 0.2), 0.4, 0.8)
	_blade_mat = LowPoly.mat(Color(0.8, 0.83, 0.88), 0.25, 0.85)
	_blade_mat.emission_enabled = true
	_blade_mat.emission = Color(1.0, 0.5, 0.1)
	_blade_mat.emission_energy_multiplier = 0.0
	LowPoly.part(sword, LowPoly.cyl(0.02, 0.022, 0.18, 6), leather, Vector3(0, 0, 0.02), Vector3(90, 0, 0))
	LowPoly.part(sword, LowPoly.box(Vector3(0.22, 0.03, 0.045)), brass, Vector3(0, 0, -0.08))
	LowPoly.part(sword, LowPoly.box(Vector3(0.055, 0.013, 0.82)), _blade_mat, Vector3(0, 0, -0.5))
	LowPoly.part(sword, LowPoly.prism(Vector3(0.055, 0.11, 0.013)), _blade_mat, Vector3(0, 0, -0.96), Vector3(-90, 0, 0))
	LowPoly.part(sword, LowPoly.box(Vector3(0.008, 0.016, 0.8)), steel, Vector3(0, 0, -0.5))
	_blade_tip = Node3D.new()
	_blade_tip.position = Vector3(0, 0, -0.7)
	sword.add_child(_blade_tip)

	for m in _model.find_children("*", "MeshInstance3D", true, false):
		if not _body_meshes.has(m):
			_body_meshes.append(m)


# ---------------- 매 프레임 ----------------

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_state_t += delta
	_alert = maxf(_alert - delta, 0.0)
	_hits_reset -= delta
	if _hits_reset <= 0.0:
		_hits_in_row = 0
	var move := Vector3.ZERO
	var turn_speed := TURN_SPEED

	if active and not dead and target and not target.dead:
		var to_t := target.global_position - global_position
		to_t.y = 0
		var dist := to_t.length()
		var dir := to_t / maxf(dist, 0.001)
		var side := Vector3(-dir.z, 0, dir.x)

		match state:
			"idle", "approach", "circle":
				_think_t -= delta
				if _think_t <= 0.0:
					_think(dist)
				if state == "approach":
					move = dir * MOVE_SPEED if dist > 2.0 else Vector3.ZERO
				elif state == "circle":
					var keep := (dist - 2.6) * 1.5
					move = side * _strafe_dir * STRAFE_SPEED + dir * keep
			"windup":
				turn_speed = WINDUP_TURN_SPEED
				move = dir * 0.6 if dist > 1.6 else Vector3.ZERO
				var data: Dictionary = ATTACKS[_attack]
				var k := clampf(_state_t / data.windup, 0.0, 1.0)
				_blade_mat.emission_energy_multiplier = k * k * 3.5
				if _state_t >= data.windup:
					_enter_strike()
			"strike":
				turn_speed = 0.5
				var data: Dictionary = ATTACKS[_attack]
				move = -global_transform.basis.z * data.lunge if dist > 1.3 else Vector3.ZERO
				if not _hit_done:
					_try_hit(dist, dir)
				if _state_t >= data.strike:
					_set_state("recover")
					_set_pose(_attack + "_strike", 6.0)
			"recover":
				turn_speed = 3.0
				var data: Dictionary = ATTACKS[_attack]
				_blade_mat.emission_energy_multiplier = move_toward(_blade_mat.emission_energy_multiplier, 0.0, delta * 10.0)
				if _combo_left > 0 and _state_t >= data.recover * 0.45 and dist < REACH + 0.6:
					_combo_left -= 1
					_start_attack("light")
				elif _state_t >= data.recover:
					_combo_left = 0
					_back_to_neutral()
			"block":
				move = -dir * 0.8 if dist < 2.2 else Vector3.ZERO
				if _state_t >= 0.75 and not _target_is_attacking():
					_back_to_neutral()
			"stagger":
				turn_speed = 0.0
				if _state_t >= _stagger_time:
					_back_to_neutral()
			"dash":
				turn_speed = TURN_SPEED
				if _state_t >= 0.22:
					_back_to_neutral()

		# 몸을 상대 쪽으로 돌린다
		var desired := atan2(-dir.x, -dir.z)
		rotation.y = rotate_toward(rotation.y, desired, turn_speed * delta)
	elif dead:
		move = Vector3.ZERO

	_push = _push.lerp(Vector3.ZERO, clampf(delta * 6.0, 0, 1))
	var mv := move + _push
	velocity.x = lerpf(velocity.x, mv.x, clampf(delta * 12.0, 0, 1))
	velocity.z = lerpf(velocity.z, mv.z, clampf(delta * 12.0, 0, 1))
	move_and_slide()


var _stagger_time := 0.4


func _process(delta: float) -> void:
	# 자세를 부드럽게 따라간다
	var a := _arm_r.rotation_degrees
	_arm_r.rotation_degrees = a.lerp(_pose_shoulder, clampf(delta * _pose_speed, 0, 1))
	_wrist.rotation_degrees = _wrist.rotation_degrees.lerp(_pose_wrist, clampf(delta * _pose_speed, 0, 1))
	# 걷기
	var horiz := Vector2(velocity.x, velocity.z).length()
	_walk_phase += delta * horiz * 3.2
	var swing := sin(_walk_phase) * clampf(horiz / MOVE_SPEED, 0.0, 1.0) * 0.6
	_leg_l.rotation.x = swing
	_leg_r.rotation.x = -swing
	_arm_l.rotation.x = deg_to_rad(20) - swing * 0.6
	# 공격할 때 몸을 앞으로 숙인다
	var lean := 0.0
	match state:
		"windup":
			lean = -0.12 if _attack == "light" else 0.15
		"strike":
			lean = 0.25
		"block":
			lean = -0.05
		"stagger":
			lean = -0.3
	if not dead:
		_torso.rotation.x = lerpf(_torso.rotation.x, -lean, clampf(delta * 10.0, 0, 1))
		var twist := 0.0
		if state == "windup" and _attack == "light":
			twist = -0.5
		elif state == "strike" and _attack == "light":
			twist = 0.45
		_torso.rotation.y = lerpf(_torso.rotation.y, twist, clampf(delta * 12.0, 0, 1))
	# 맞으면 번쩍
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 7.0, 0.0)
		_flash_mat.albedo_color.a = _flash * 0.8
		for m in _body_meshes:
			m.material_overlay = _flash_mat if _flash > 0.0 else null


# ---------------- 판단 ----------------

func _think(dist: float) -> void:
	_think_t = randf_range(0.18, 0.35)
	if dist > 3.2:
		_set_state("approach")
		return
	var r := randf()
	if r < aggression:
		_start_attack("heavy" if randf() < 0.25 else "light")
		_combo_left = 1 if randf() < 0.35 else 0
	elif r < aggression + 0.25:
		_set_state("circle")
		_strafe_dir = -1.0 if randf() < 0.5 else 1.0
		_think_t = randf_range(0.5, 1.1)
	elif r < aggression + 0.33:
		_dash(-1.0)
	else:
		_enter_block()


## 플레이어가 공격을 시작했을 때 (Main 이 연결해 준다)
func on_target_attack(_kind: String) -> void:
	if not active or dead:
		return
	if state not in ["idle", "approach", "circle", "recover"]:
		return
	var dist := global_position.distance_to(target.global_position)
	if dist > 3.4:
		return
	await get_tree().create_timer(reaction_time, false).timeout
	if dead or state not in ["idle", "approach", "circle", "recover"]:
		return
	var chance := block_chance + (0.25 if _alert > 0.0 else 0.0)
	var r := randf()
	if r < chance:
		_enter_block()
	elif r < chance + 0.12:
		_dash(-1.0)


func _target_is_attacking() -> bool:
	return target._attack_phase != ""


func _set_state(s: String) -> void:
	stats[s] = stats.get(s, 0) + 1
	state = s
	_state_t = 0.0


func _set_pose(pose: String, speed: float = 12.0) -> void:
	var p: Array = POSES[pose]
	_pose_shoulder = p[0]
	_pose_wrist = p[1]
	_pose_speed = speed


func _back_to_neutral() -> void:
	_set_state("circle" if randf() < 0.5 else "approach")
	_strafe_dir = -1.0 if randf() < 0.5 else 1.0
	_think_t = randf_range(0.05, 0.25)
	_set_pose("guard", 10.0)
	_blade_mat.emission_energy_multiplier = 0.0


func _start_attack(kind: String) -> void:
	_attack = kind
	_set_state("windup")
	_hit_done = false
	var data: Dictionary = ATTACKS[kind]
	_set_pose(kind + "_windup", 1.0 / data.windup * 2.5)
	_blade_mat.emission = Color(1.0, 0.55, 0.1) if kind == "light" else Color(1.0, 0.15, 0.1)
	_play("warn_heavy" if kind == "heavy" else "warn_light", -3.0)


func _enter_strike() -> void:
	_set_state("strike")
	_set_pose(_attack + "_strike", 30.0)
	_play("swing", -2.0)


func _enter_block() -> void:
	_set_state("block")
	_set_pose("block", 22.0)
	_blade_mat.emission_energy_multiplier = 0.0


func _dash(sign_dir: float) -> void:
	var to_t := target.global_position - global_position
	to_t.y = 0
	var dir := to_t.normalized()
	var side := Vector3(-dir.z, 0, dir.x) * (1.0 if randf() < 0.5 else -1.0)
	_push = (dir * sign_dir * 0.8 + side * 0.6).normalized() * 11.0
	_set_state("dash")
	_set_pose("guard", 12.0)


func _try_hit(dist: float, dir: Vector3) -> void:
	if dist > REACH:
		return
	var facing := -global_transform.basis.z
	facing.y = 0
	if facing.normalized().dot(dir) < HIT_ANGLE:
		return
	_hit_done = true
	var data: Dictionary = ATTACKS[_attack]
	var dmg: int = data.damage + randi_range(-2, 2)
	var result := target.receive_attack(dmg, _attack == "heavy", self)
	match result:
		"parried":
			_stagger(0.75)
			combat_event.emit("반격 기회!", Color(0.55, 0.85, 1.0))
		"blocked":
			_push = -dir * 3.0
			_combo_left = 0
		"guard_broken", "hit":
			Fx.impact(get_parent(), target.global_position + Vector3(0, 1.3, 0), dir + Vector3.UP * 0.3,
					Color(0.75, 0.1, 0.08), 14)


func _stagger(t: float) -> void:
	_stagger_time = t
	_combo_left = 0
	_set_state("stagger")
	_set_pose("stagger", 14.0)
	_blade_mat.emission_energy_multiplier = 0.0


# ---------------- 맞을 때 ----------------

## 플레이어의 칼에 닿았을 때 불린다. 결과: "hit", "blocked", "parried"
func take_hit(damage: int, dir: Vector3, heavy: bool, _attacker: Node3D = null) -> String:
	var r := _take_hit(damage, dir, heavy)
	stats["got_" + r] = stats.get("got_" + r, 0) + 1
	return r


func _take_hit(damage: int, dir: Vector3, heavy: bool) -> String:
	if dead:
		return "none"
	var facing := -global_transform.basis.z
	facing.y = 0
	var facing_attacker := facing.normalized().dot(-dir) > 0.2
	if state == "block" and facing_attacker:
		if _state_t < 0.3 and randf() < parry_chance:
			_play("parry")
			# 튕겨낸 뒤 바로 반격
			_start_attack("light")
			_state_t = ATTACKS.light.windup * 0.45
			return "parried"
		if heavy:
			# 강공격은 막기를 깨뜨린다
			_play("clang")
			combat_event.emit("가드 깨기!", Color(1.0, 0.75, 0.3))
			_apply_damage(damage / 2, dir, true)
			if not dead:
				_stagger(0.7)
			return "hit"
		_play("clang", -2.0)
		_push = dir * 2.0
		if randf() < counter_chance:
			# 막아낸 뒤 상대가 튕겨난 틈에 바로 반격
			_start_attack("light")
			_state_t = ATTACKS.light.windup * 0.35
		else:
			_state_t = 0.0   # 계속 막고 있는다
		return "blocked"

	_apply_damage(damage, dir, heavy)
	_hits_in_row += 1
	_hits_reset = 1.2
	if not dead:
		if _hits_in_row >= 3:
			# 연속으로 세 번 맞으면 뒤로 빠져서 연타에 갇히지 않는다
			_hits_in_row = 0
			_dash(-1.0)
		elif heavy or state != "windup":
			# 공격 준비 중에는 약공격에 맞아도 버티고 그대로 휘두른다 (맞교환)
			_stagger(0.5 if heavy else 0.22)
	return "hit"


func _apply_damage(damage: int, dir: Vector3, heavy: bool) -> void:
	hp = max(hp - damage, 0)
	hp_changed.emit(hp, MAX_HP)
	_flash = 1.0
	_alert = 2.0
	_push = dir * (5.0 if heavy else 2.5)
	_play("hit_heavy" if heavy else "hit")
	Fx.impact(get_parent(), global_position + Vector3(0, 1.3, 0) - dir * 0.3, -dir + Vector3.UP * 0.4,
			Color(0.75, 0.1, 0.08), 22 if heavy else 12)
	_spawn_number(damage, heavy)
	if hp <= 0:
		_die(dir)


func _die(dir: Vector3) -> void:
	dead = true
	_set_state("dead")
	active = false
	_blade_mat.emission_energy_multiplier = 0.0
	collision_layer = 0
	died.emit()
	var local := global_transform.basis.inverse() * dir
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_model, "rotation:x", -PI * 0.47 * signf(-local.z if absf(local.z) > 0.1 else 1.0), 0.7) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_model, "position:y", 0.15, 0.7)


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
	get_parent().add_child(label)
	label.global_position = global_position + Vector3(randf_range(-0.3, 0.3), 2.1, 0)
	var tw := label.create_tween().set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y + 0.7, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.tween_property(label, "outline_modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(label.queue_free)
