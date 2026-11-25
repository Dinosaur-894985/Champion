class_name Duelist
extends CharacterBody3D
## AI 상대 (결투사). 다가와서 베고(연속 베기, 내려찍기, 차지 베기), 막고, 옆으로 피하고,
## 피한 직후 반격하고, 맞으면 움찔하거나 크게 휘청인다.
## 공격하기 전에는 칼이 빛나고 경고음이 나서 보고 막거나 피할 수 있다.
##
## 구조
##   생각(판단)  : _think, on_target_attack, on_target_charge — 무엇을 할지 고른다
##   행동 상태   : StateMachine — 고른 행동을 한 단계씩 실행
##   몸 움직임   : BodyRig — 아래 몸/위 몸/흔들림 세 겹으로 자세를 만든다
##   동작 수치   : MoveSet — 플레이어와 같은 표를 쓴다

signal hp_changed(value: int, max_value: int)
signal combat_event(text: String, color: Color)
signal died
signal stamina_changed(value: float, max_value: float)

const MAX_HP := 100
const MOVE_SPEED := 3.9
const STRAFE_SPEED := 2.6
const TURN_SPEED := 7.0         # 평소에 몸을 돌리는 빠르기
const WINDUP_TURN_SPEED := 2.0  # 공격 준비 중에는 느리게 돈다 → 옆으로 대시하면 피할 수 있다
const HIT_ANGLE := 0.55         # 칼이 닿는 앞쪽 범위 (cos 값)
const DASH_TIME := 0.24
const DASH_IFRAMES := 0.22
const DASH_COST := 16.0
const STAMINA_REGEN := 30.0
const REGEN_DELAY := 0.8
const BLOCK_COST := {"flinch": 12.0, "stagger": 26.0}

# 성격 (나중에 난이도나 '거울' 모드에서 바꿀 수 있다)
var aggression := 0.55
var block_chance := 0.45
var parry_chance := 0.3
var dodge_chance := 0.16        # 내 공격을 옆으로 피하려는 확률
var reaction_time := 0.1
var counter_chance := 0.65      # 막아낸 뒤 바로 반격
var combo_chance := 0.55        # 연속 베기를 이어갈 확률
var charge_chance := 0.18       # 거리가 벌어졌을 때 차지 베기
var stats := {}   # 점검용 기록: 받은 공격 결과, 한 행동 횟수
## 쓸 수 있는 이동 기술 (플레이어와 같은 이름). 빌드의 '벽타기' 스킬로 켜진다.
## 벽을 못 타면 계단과 경사로로만 올라간다.
var traits := {"wall_climb": true}
var arena: Arena                # 길찾기 (없으면 곧장 다가간다)
## 이 AI 의 캐릭터 (능력치, 특수 스킬). 플레이어와 같은 규칙. 씬에 넣기 전에 정한다.
var build: CharacterBuild
var skills: SkillKit

var max_hp := MAX_HP
var hp := MAX_HP
var max_stamina := 100.0
var stamina := 100.0
var _regen_wait := 0.0
var active := false
var dead := false
var target: Player

var sm := StateMachine.new()
var state: String:
	get: return sm.state
var _state_t: float:
	get: return sm.time

var _think_t := 0.0
var _strafe_dir := 1.0
var _attack := ""
var _combo_left := 0
var _hit_done := false
var _alert := 0.0               # 맞은 직후 경계 상태 (더 잘 막음)
var _push := Vector3.ZERO       # 밀려남, 대시
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _hits_in_row := 0
var _hits_reset := 0.0
var _iframes := 0.0
var _counter_ready := false     # 방금 상대 공격을 피했다 → 대시가 끝나면 반격
var _stagger_time := 0.4
var _dist := 99.0
var _dodged_by_target := 0      # 플레이어에게 몇 번 피해졌나 → 많을수록 휘두르는 타이밍을 흔든다
var _windup_len := 0.5
var _dir := Vector3.FORWARD
var _dy := 0.0                  # 상대가 나보다 얼마나 높이 있나

# 길찾기
var _direct := true             # 상대에게 곧장 갈 수 있나 (같은 층이고 막힌 게 없음)
var _direct_t := 0.0
var _path: Array = []
var _path_i := 0
var _repath_t := 0.0
var _face := Vector3.ZERO       # 길을 따라갈 때 바라볼 방향 (ZERO 면 상대를 본다)
var _climb_top := 0.0
var _climb_dir := Vector3.ZERO
var _stuck_t := 0.0
var _stuck_pos := Vector3.ZERO
var _ray := PhysicsRayQueryParameters3D.new()
var _dj_pending := false        # 점프 꼭대기에서 이중 점프
var _grap_point := Vector3.ZERO
var _grap_on_target := false
var _rope: MeshInstance3D

var rig: BodyRig
var _audio: AudioStreamPlayer3D
var _sounds := {}


func _ready() -> void:
	if build == null:
		build = CharacterBuild.preset("검객")
	max_hp = build.max_hp()
	hp = max_hp
	max_stamina = build.max_stamina()
	stamina = max_stamina
	traits = {"wall_climb": build.has("wall")}
	skills = SkillKit.new(self, build)
	vkit = VerticalKit.new(self)
	collision_layer = 2
	collision_mask = 1
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.85
	col.shape = cap
	col.position.y = 0.925
	add_child(col)
	rig = BodyRig.new()
	add_child(rig)
	_audio = AudioStreamPlayer3D.new()
	_audio.unit_size = 8.0
	_audio.max_polyphony = 4
	add_child(_audio)
	_sounds = {
		"warn_light": Sfx.warn(false),
		"warn_heavy": Sfx.warn(true),
		"swing": Sfx.whoosh(0.24, 0.85),
		"dash": Sfx.whoosh(0.16, 1.3),
		"hit": Sfx.thud(0.2, false),
		"hit_heavy": Sfx.thud(0.28, true),
		"clang": Sfx.clang(0.45, 0.92),
		"parry": Sfx.clang(0.7, 1.15),
	}
	for n in ["idle", "approach", "circle"]:
		sm.add(n, Callable(), _neutral_update)
	sm.add("windup", _windup_enter, _windup_update) \
		.add("strike", _strike_enter, _strike_update) \
		.add("recover", _recover_enter, _recover_update) \
		.add("block", _block_enter, _block_update) \
		.add("dash", _dash_enter, _dash_update) \
		.add("stagger", _stagger_enter, _stagger_update) \
		.add("climb", _climb_enter, _climb_update) \
		.add("grapple", _grapple_enter, _grapple_update, _grapple_exit) \
		.add("iron", _iron_enter, _iron_update, _iron_exit) \
		.add("plunge", _plunge_enter, _plunge_update) \
		.add("hang", _hang_enter, _hang_update) \
		.add("zip", _zip_enter, _zip_update) \
		.add("dead")
	_ray.collision_mask = 1
	_build_rope()
	sm.changed.connect(func(_a, b): stats[b] = stats.get(b, 0) + 1)
	sm.go("idle")


func _play(snd: String, volume: float = 0.0) -> void:
	_audio.stream = _sounds[snd]
	_audio.volume_db = volume
	_audio.pitch_scale = randf_range(0.94, 1.06)
	_audio.play()


# ---------------- 매 프레임 ----------------

var _move := Vector3.ZERO
var _turn_speed := TURN_SPEED


func _physics_process(delta: float) -> void:
	if not is_on_floor() and state not in ["climb", "grapple", "hang", "zip"]:
		velocity.y -= _gravity * delta
	if is_on_floor():
		skills.landed()
	elif _dj_pending and velocity.y < 1.0:
		_dj_pending = false
		if skills.try_double_jump(5.6):
			_play("dash", -10.0)
	skills.tick(delta)
	_regen(delta)
	_alert = maxf(_alert - delta, 0.0)
	_iframes = maxf(_iframes - delta, 0.0)
	_hits_reset -= delta
	if _hits_reset <= 0.0:
		_hits_in_row = 0
	_move = Vector3.ZERO
	_face = Vector3.ZERO
	_turn_speed = TURN_SPEED

	if active and not dead and target and not target.dead:
		var to_t := target.global_position - global_position
		to_t.y = 0
		_dist = to_t.length()
		_dir = to_t / maxf(_dist, 0.001)
		_dy = target.global_position.y - global_position.y
		_direct_t -= delta
		if _direct_t <= 0.0:
			_direct_t = 0.2
			_direct = _check_direct()
		sm.tick(delta)
		# 몸을 상대 쪽으로 돌린다 (길을 따라갈 때는 가는 쪽으로)
		var look := _face if _face != Vector3.ZERO else _dir
		var desired := atan2(-look.x, -look.z)
		rotation.y = rotate_toward(rotation.y, desired, _turn_speed * delta)

	_push = _push.lerp(Vector3.ZERO, clampf(delta * 6.0, 0, 1))
	var mv := _move + _push
	velocity.x = lerpf(velocity.x, mv.x, clampf(delta * 12.0, 0, 1))
	velocity.z = lerpf(velocity.z, mv.z, clampf(delta * 12.0, 0, 1))
	move_and_slide()
	_vertical_tick(delta)


func _regen(delta: float) -> void:
	if _regen_wait > 0.0:
		_regen_wait -= delta
	elif stamina < max_stamina:
		var r := STAMINA_REGEN * build.regen_mult() * skills.regen_mult() * (0.5 if state in ["block", "iron"] else 1.0)
		stamina = minf(stamina + r * delta, max_stamina)
		stamina_changed.emit(stamina, max_stamina)


func spend_stamina(amount: float) -> void:
	stamina = maxf(stamina - amount, 0.0)
	_regen_wait = REGEN_DELAY
	stamina_changed.emit(stamina, max_stamina)


## 능력치와 질풍을 반영한 걷는 빠르기
func _speed() -> float:
	return MOVE_SPEED * build.speed_mult() * skills.speed_mult()


func _atk_mult() -> float:
	return build.attack_time_mult() * skills.attack_mult()


func _process(delta: float) -> void:
	rig.animate(delta, global_transform.basis.inverse() * Vector3(velocity.x, 0, velocity.z))
	_update_rope()


# ---------------- 판단 ----------------

func _think() -> void:
	_think_t = randf_range(0.18, 0.35)
	if _think_vertical():
		return
	if not _direct:
		# 상대가 다른 층(지붕, 기둥 위)에 있으면: 갈고리가 있으면 줄을 걸어 날아가고, 아니면 길을 찾아 올라간다
		if _dy > 1.5 and _try_grapple_to_target():
			return
		sm.go("approach")
		return
	if _think_skills():
		return
	if target.sm.state == "iron":
		# 상대가 철벽 중이면 때려 봐야 소용없다: 거리를 두고 돈다
		sm.go("circle")
		_strafe_dir = -1.0 if randf() < 0.5 else 1.0
		_think_t = 0.4
		return
	if stamina < 22.0:
		# 기력이 바닥났다: 물러나서 숨을 고른다
		sm.go("circle")
		_strafe_dir = -1.0 if randf() < 0.5 else 1.0
		_think_t = randf_range(0.5, 0.9)
		return
	var r := randf()
	# 거리가 좀 벌어졌으면 가끔 차지 베기로 돌진
	if _dist > 2.6 and _dist < 4.6 and randf() < charge_chance * (1.0 if r < aggression else 0.3):
		_start_attack("charge")
		return
	if _dist > 3.2:
		sm.go("approach")
		return
	if r < aggression:
		if randf() < 0.2:
			_start_attack("heavy")
			_combo_left = 0
		else:
			# 연속 베기: 몇 번 이어 갈지 미리 정한다 (0~2번 더)
			_combo_left = 0
			if randf() < combo_chance:
				_combo_left = 1 if randf() < 0.55 else 2
			_start_attack("slash1")
	elif r < aggression + 0.25:
		sm.go("circle")
		_strafe_dir = -1.0 if randf() < 0.5 else 1.0
		_think_t = randf_range(0.5, 1.1)
	elif r < aggression + 0.33:
		_dash_dir(-0.8, 0.6)
	else:
		_enter_block()


func _can_react() -> bool:
	return active and not dead and state in ["idle", "approach", "circle", "recover"]


## 플레이어가 공격을 시작했을 때 (Main 이 연결해 준다)
func on_target_attack(kind: String) -> void:
	if not _can_react():
		return
	if global_position.distance_to(target.global_position) > 3.6:
		return
	await get_tree().create_timer(reaction_time, false).timeout
	if not _can_react():
		return
	var big := kind in ["heavy", "charge"]
	var block := block_chance + (0.25 if _alert > 0.0 else 0.0)
	var dodge := dodge_chance
	if big:
		# 막기를 깨는 공격은 막기보다 피하는 편이 낫다
		dodge += block * 0.6
		block *= 0.4
	var r := randf()
	# 특수 스킬로 받아치기: 큰 공격엔 철벽이나 점멸
	if big and skills.can_use("iron_guard") and randf() < 0.65:
		_use_iron()
		return
	if skills.can_use("blink") and randf() < (0.6 if big else 0.18):
		_blink_dodge()
		return
	if r < block:
		_enter_block()
	elif r < block + dodge:
		_dash_dir(-0.2, 1.0)   # 옆으로 피하기
	elif r < block + dodge + 0.1:
		_dash_dir(-1.0, 0.4)


## 플레이어가 힘을 모으기 시작했을 때: 파고들어 끊거나, 물러난다
func on_target_charge() -> void:
	if not _can_react() or state == "recover":
		return
	await get_tree().create_timer(reaction_time + 0.1, false).timeout
	if not _can_react():
		return
	var dist := global_position.distance_to(target.global_position)
	if dist < 3.6 and skills.can_use("iron_guard") and randf() < 0.5:
		_use_iron()
		return
	if dist < 3.6 and skills.can_use("blink") and randf() < 0.5:
		_blink_dodge()
		return
	if dist < 3.4 and randf() < aggression:
		_combo_left = 0
		_start_attack("slash1")
		combat_event.emit("끊으러 온다!", Color(1.0, 0.7, 0.4))
	elif randf() < 0.6:
		_dash_dir(-1.0, 0.5)


func _back_to_neutral() -> void:
	sm.go("circle" if randf() < 0.5 else "approach")
	_strafe_dir = -1.0 if randf() < 0.5 else 1.0
	_think_t = randf_range(0.05, 0.25)
	rig.set_pose(MoveSet.BODY_POSES.guard, 10.0)
	rig.glow(rig.blade_mat.emission, 0.0)
	rig.tremble = 0.0


# ---------------- 행동 상태 ----------------

func _neutral_update(delta: float) -> void:
	_think_t -= delta
	if _think_t <= 0.0:
		_think()
		if state not in ["approach", "circle"]:
			return
	if _needs_nav():
		_move = _nav_move(delta)
		return
	_path.clear()
	var side := Vector3(-_dir.z, 0, _dir.x)
	if state == "approach":
		_move = _dir * _speed() if _dist > 2.0 else Vector3.ZERO
	else:
		var keep := (_dist - 2.6) * 1.5
		if stamina < 22.0:
			keep = (_dist - 4.0) * 1.5   # 숨 고르는 중엔 멀찍이
		_move = side * _strafe_dir * STRAFE_SPEED * build.speed_mult() + _dir * keep
	_move = _edge_guard(_move)


func _start_attack(kind: String) -> void:
	if stamina < float(MoveSet.MOVES[kind].cost) * 0.5:
		_back_to_neutral()
		return
	_attack = kind
	stats["move_" + kind] = stats.get("move_" + kind, 0) + 1
	sm.go("windup")


func _windup_enter(_d: Dictionary) -> void:
	_hit_done = false
	var data: Dictionary = MoveSet.MOVES[_attack]
	spend_stamina(float(data.cost))
	# 자꾸 피하면 일부러 한 박자 늦게 휘두르기도 한다
	_windup_len = data.ai_windup * _atk_mult() + randf() * 0.12 * mini(_dodged_by_target, 3)
	rig.set_pose(data.body.windup, 2.5 / (data.ai_windup * _atk_mult()))
	var col := Color(1.0, 0.55, 0.1)
	if data.warn == "heavy":
		col = Color(1.0, 0.15, 0.1)
	if _attack == "counter":
		col = Color(0.4, 0.8, 1.0)
	rig.glow(col, 0.0)
	_play("warn_heavy" if data.warn == "heavy" else "warn_light", -3.0)


func _windup_update(_delta: float) -> void:
	var data: Dictionary = MoveSet.MOVES[_attack]
	_turn_speed = WINDUP_TURN_SPEED
	var k := clampf(_state_t / (data.ai_windup * _atk_mult()), 0.0, 1.0)
	rig.glow(rig.blade_mat.emission, k * k * 3.5)
	if _attack == "charge":
		# 힘을 모으며 천천히 다가온다
		rig.tremble = k
		_move = _dir * 1.4 if _dist > 2.2 else Vector3.ZERO
	else:
		_move = _dir * 0.6 if _dist > 1.6 else Vector3.ZERO
	if _state_t >= _windup_len:
		sm.go("strike")


func _strike_enter(_d: Dictionary) -> void:
	var data: Dictionary = MoveSet.MOVES[_attack]
	rig.set_pose(data.body.strike, 30.0)
	rig.tremble = 0.0
	_play("swing", -2.0)


func _strike_update(_delta: float) -> void:
	var data: Dictionary = MoveSet.MOVES[_attack]
	_turn_speed = 0.5
	_move = -global_transform.basis.z * float(data.lunge) if _dist > 1.3 else Vector3.ZERO
	if not _hit_done:
		_try_hit(data)
	if _state_t >= data.active:
		if not _hit_done:
			# 빗나갔다 — 막 대시로 피한 거라면 플레이어에게 반격 기회
			if target.notify_whiff(self):
				_dodged_by_target += 1
		sm.go("recover")


func _recover_enter(_d: Dictionary) -> void:
	pass


func _recover_update(delta: float) -> void:
	var data: Dictionary = MoveSet.MOVES[_attack]
	_turn_speed = 3.0
	rig.glow(rig.blade_mat.emission, move_toward(rig.glow_energy(), 0.0, delta * 10.0))
	var nxt: String = data.next
	var rec: float = data.ai_recover * _atk_mult()
	if _combo_left > 0 and nxt != "" and _state_t >= rec * 0.35 and _dist < float(data.reach) + 0.9:
		_combo_left -= 1
		_start_attack(nxt)
	elif _state_t >= rec:
		_combo_left = 0
		_back_to_neutral()


func _enter_block() -> void:
	sm.go("block")


func _block_enter(_d: Dictionary) -> void:
	rig.set_pose(MoveSet.BODY_POSES.block, 22.0)
	rig.glow(rig.blade_mat.emission, 0.0)


func _block_update(_delta: float) -> void:
	_move = -_dir * 0.8 if _dist < 2.2 else Vector3.ZERO
	if _state_t >= 0.75 and not target.is_attacking():
		_back_to_neutral()


## back: 앞(+)/뒤(-) 비율, side: 옆 비율
func _dash_dir(back: float, side_amt: float) -> void:
	if stamina < DASH_COST * 0.5:
		# 기력이 없어 대시를 못 한다: 대신 막는다
		_enter_block()
		return
	var side := Vector3(-_dir.z, 0, _dir.x) * (1.0 if randf() < 0.5 else -1.0)
	sm.go("dash", {"vec": (_dir * back + side * side_amt).normalized()})


func _dash_enter(d: Dictionary) -> void:
	var v: Vector3 = d.vec
	_push = v * 11.0 * build.dash_mult()
	_iframes = DASH_IFRAMES
	if v.length() > 0.5:
		spend_stamina(DASH_COST)
	_counter_ready = false
	rig.set_pose(MoveSet.BODY_POSES.guard, 12.0)
	rig.dash_pulse(global_transform.basis.inverse() * v)
	rig.glow(rig.blade_mat.emission, 0.0)
	rig.tremble = 0.0
	_play("dash", -6.0)


func _dash_update(_delta: float) -> void:
	if _state_t >= DASH_TIME:
		if _counter_ready and _dist < 3.4:
			# 피한 직후 반격
			_counter_ready = false
			_combo_left = 0
			_start_attack("counter")
		else:
			_back_to_neutral()


func _stagger_enter(d: Dictionary) -> void:
	_stagger_time = d.time
	_combo_left = 0
	rig.tremble = 0.0
	rig.glow(rig.blade_mat.emission, 0.0)
	if d.get("big", true):
		rig.set_pose(MoveSet.BODY_POSES.stagger, 14.0)


func _stagger_update(_delta: float) -> void:
	_turn_speed = 0.0
	if _state_t >= _stagger_time:
		_back_to_neutral()


func _stagger(t: float, big: bool = true) -> void:
	sm.go("stagger", {"time": t * build.stun_mult(), "big": big})


# ---------------- 길찾기와 벽 오르기 ----------------

## 상대에게 곧장 걸어갈 수 있나: 같은 층(높이 차 작음)이고, 같은 구역이고, 사이에 벽이 없으면.
func _check_direct() -> bool:
	if arena == null:
		return true
	if target.is_hanging() and _dist < 3.5 and _dy > -2.4:
		return true
	if absf(_dy) > 1.0:
		return false
	if arena.area_of(global_position) != arena.area_of(target.global_position):
		return false
	_ray.from = global_position + Vector3.UP * 0.6
	_ray.to = target.global_position + Vector3.UP * 0.6
	_ray.exclude = [get_rid(), target.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


## 길목 점을 따라 움직일 방향. 벽 오르기/점프가 필요한 곳에서는 그 동작을 시작한다.
func _nav_move(delta: float) -> Vector3:
	_repath_t -= delta
	if _riding_lift() and _path_i < _path.size() and _path[_path_i].kind == "lift":
		_repath_t = maxf(_repath_t, 0.3)   # 발판을 타고 있는 동안에는 길을 다시 찾지 않는다
	if _repath_t <= 0.0 or _path_i >= _path.size():
		_repath_t = 0.6
		_path = arena.find_path(global_position, _nav_goal(), traits.get("wall_climb", false))
		# 길이 너무 멀면 갈고리로 지름길
		if _path.size() > 6 and _try_grapple_to_target():
			return Vector3.ZERO
		_path_i = 1 if _path.size() > 1 else 0
	if _path.is_empty():
		# 갈 길이 없다 (벽을 못 타는데 상대가 기둥 위에 있다 등): 아래에서 기다리며 맴돈다
		return Vector3(-_dir.z, 0, _dir.x) * _strafe_dir * STRAFE_SPEED * 0.5
	var wp: Dictionary = _path[mini(_path_i, _path.size() - 1)]
	var p: Vector3 = wp.pos
	var to := Vector3(p.x - global_position.x, 0, p.z - global_position.z)
	var hd := to.length()
	var dy := p.y - global_position.y
	# 도착하면 다음 점으로
	if hd < 0.8 and dy < 0.6 and dy > -1.2:
		_path_i += 1
		if _path_i >= _path.size():
			_repath_t = 0.0
			return _dir * MOVE_SPEED
		wp = _path[_path_i]
		p = wp.pos
		to = Vector3(p.x - global_position.x, 0, p.z - global_position.z)
		hd = to.length()
		dy = p.y - global_position.y
	var dir := to / maxf(hd, 0.001)
	_face = dir
	_check_stuck(delta)
	var special = _nav_special(wp, dir, hd)
	if special != null:
		return special
	match wp.kind:
		"climb":
			if dy > 0.6 and hd < 1.9 and is_on_floor():
				sm.go("climb", {"top": p.y, "dir": dir})
				return Vector3.ZERO
		"jump":
			if dy > 0.4 and hd < 2.2 and is_on_floor():
				velocity.y = 6.3
				_dj_pending = skills.has("double_jump") and dy > 1.4
	return dir * _speed() * (1.15 if not _direct else 1.0)


## 오래 제자리면 (모서리에 걸림) 한 번 뛰고 길을 다시 찾는다
func _check_stuck(delta: float) -> void:
	_stuck_t += delta
	if _stuck_t < 1.2:
		return
	if global_position.distance_to(_stuck_pos) < 0.4 and is_on_floor():
		velocity.y = 5.5
		_repath_t = 0.0
		stats["unstuck"] = stats.get("unstuck", 0) + 1
	_stuck_t = 0.0
	_stuck_pos = global_position


func _climb_enter(d: Dictionary) -> void:
	_climb_top = d.top
	_climb_dir = d.dir
	rig.set_pose(MoveSet.BODY_POSES.climb, 10.0)
	rig.glow(rig.blade_mat.emission, 0.0)
	rig.tremble = 0.0


func _climb_update(_delta: float) -> void:
	var t: Dictionary = MoveSet.TRAVERSAL.wall_climb
	_face = _climb_dir
	_turn_speed = 12.0
	_move = _climb_dir * 2.0
	velocity.y = float(t.speed) * 0.9
	if global_position.y >= _climb_top + 0.05:
		# 꼭대기: 짚고 올라선다
		velocity.y = 3.0
		_push = _climb_dir * 4.0
		_path_i += 1
		_back_to_neutral()
		if _after_climb_attack != "":
			# 난간에서 뛰어오르며 벤다
			var follow := _after_climb_attack
			_after_climb_attack = ""
			_combo_left = 0
			_start_attack(follow)
			return
		sm.go("approach")
		return
	# 벽에 안 붙었거나 너무 오래 걸리면 포기 (떨어진다)
	var near_top := global_position.y > _climb_top - 0.7
	if (_state_t > 0.35 and not is_on_wall() and not near_top) or _state_t > 3.0:
		velocity.y = 0.0
		_repath_t = 0.0
		_back_to_neutral()


# ---------------- 공격 맞히기 ----------------

func _try_hit(data: Dictionary) -> void:
	if _try_smash(data):
		return
	var reach_dy := 2.4 if target.is_hanging() else 1.4
	if _dist > float(data.reach) + 0.15 or absf(_dy) > reach_dy:
		return
	var facing := -global_transform.basis.z
	facing.y = 0
	if facing.normalized().dot(_dir) < HIT_ANGLE:
		return
	_hit_done = true
	var info := {
		"move": _attack, "damage": int(round(float(data.damage) * build.damage_mult() * vkit.damage_mult())) + randi_range(-2, 2),
		"power": vkit.powered(),
		"react": data.react, "guard": data.get("ai_guard", data.guard), "pressure": build.guard_pressure(),
	}
	var result := target.receive_attack(info, self)
	match result:
		"parried":
			_stagger(0.75)
			combat_event.emit("반격 기회!", Color(0.55, 0.85, 1.0))
		"blocked":
			_push = -_dir * 3.0
			_combo_left = 0
		"dodged":
			_dodged_by_target += 1
		"guard_broken", "hit":
			Fx.impact(get_parent(), target.global_position + Vector3(0, 1.3, 0), _dir + Vector3.UP * 0.3,
					Color(0.75, 0.1, 0.08), 14)


# ---------------- 맞을 때 ----------------

## 플레이어의 칼에 닿았을 때 불린다. info: {"damage", "react", "guard"}
## 결과: "hit", "blocked", "parried", "dodged"
func take_hit(info: Dictionary, dir: Vector3, _attacker: Node3D = null) -> String:
	var r := ""
	if state == "hang" and not dead:
		r = _hit_while_hanging(info, dir)
	else:
		r = _take_hit(info, dir)
		_after_hit(r, info, dir)
	stats["got_" + r] = stats.get("got_" + r, 0) + 1
	return r


func _take_hit(info: Dictionary, dir: Vector3) -> String:
	if dead:
		return "none"
	var damage: int = info.damage
	var big: bool = info.react == "stagger"
	if _iframes > 0.0:
		# 옆으로 피했다 → 대시가 끝나면 반격
		_counter_ready = true
		combat_event.emit("상대가 피했다!", Color(1.0, 0.7, 0.4))
		return "dodged"
	if state == "iron":
		# 철벽: 어떤 공격이든 막는다. 기력도 줄지 않는다.
		_play("clang", -1.0)
		combat_event.emit("상대 철벽!", Color(1.0, 0.85, 0.4))
		_push = dir * 1.5
		return "blocked"
	var facing := -global_transform.basis.z
	facing.y = 0
	var facing_attacker := facing.normalized().dot(-dir) > 0.2
	if state == "block" and facing_attacker and info.guard != "unblockable":
		var parry := parry_chance * (1.0 + 0.12 * (float(build.stats.tec) - 5.0))
		if _state_t < 0.3 and randf() < parry:
			_play("parry")
			# 튕겨낸 뒤 바로 반격
			_combo_left = 0
			_start_attack("slash1")
			sm.time = MoveSet.MOVES.slash1.ai_windup * 0.45
			return "parried"
		if info.guard == "break":
			# 막기를 깨는 공격
			_play("clang")
			combat_event.emit("가드 깨기!", Color(1.0, 0.75, 0.3))
			_apply_damage(damage / 2, dir, true)
			if not dead:
				_stagger(MoveSet.REACTIONS.guard_break.time)
			return "hit"
		_play("clang", -2.0)
		_push = dir * (4.0 if big else 2.0)
		spend_stamina(float(BLOCK_COST.get(info.react, 12.0)) * float(info.get("pressure", 1.0)))
		if stamina <= 0.0:
			# 기력이 바닥나 막기가 깨졌다
			combat_event.emit("가드 깨기!", Color(1.0, 0.75, 0.3))
			_apply_damage(damage / 2, dir, true)
			if not dead:
				_stagger(MoveSet.REACTIONS.guard_break.time)
			return "hit"
		if randf() < counter_chance:
			# 막아낸 뒤 상대가 튕겨난 틈에 바로 반격
			_combo_left = 0
			_start_attack("slash1")
			sm.time = MoveSet.MOVES.slash1.ai_windup * 0.35
		else:
			sm.time = 0.0   # 계속 막고 있는다
		return "blocked"

	_apply_damage(damage, dir, big)
	_hits_in_row += 1
	_hits_reset = 1.2
	if not dead:
		if _hits_in_row >= 3 and not big:
			# 연속으로 세 번 맞으면 뒤로 빠져서 연타에 갇히지 않는다
			_hits_in_row = 0
			_dash_dir(-1.0, 0.5)
		elif big:
			_stagger(MoveSet.REACTIONS.stagger.time)
		elif state == "windup" and _attack in ["heavy", "charge", "slash3"]:
			pass   # 큰 공격을 준비 중이면 가벼운 공격엔 버티고 그대로 휘두른다 (맞교환)
		elif state == "windup" and randf() < 0.5:
			pass
		else:
			_stagger(MoveSet.REACTIONS.flinch.time, false)
	return "hit"


func _apply_damage(damage: int, dir: Vector3, big: bool) -> void:
	hp = max(hp - damage, 0)
	hp_changed.emit(hp, max_hp)
	_alert = 2.0
	var r: Dictionary = MoveSet.REACTIONS["stagger" if big else "flinch"]
	_push = dir * float(r.push)
	rig.hit_kick(global_transform.basis.inverse() * dir, float(r.kick))
	_play("hit_heavy" if big else "hit")
	Fx.impact(get_parent(), global_position + Vector3(0, 1.3, 0) - dir * 0.3, -dir + Vector3.UP * 0.4,
			Color(0.75, 0.1, 0.08), 22 if big else 12)
	_spawn_number(damage, big)
	if hp <= 0:
		_die(dir)


func _die(dir: Vector3) -> void:
	dead = true
	sm.go("dead")
	active = false
	collision_layer = 0
	died.emit()
	rig.fall(global_transform.basis.inverse() * dir)


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


## 시작 전에 맞았을 때 효과(번쩍임, 피해 숫자)를 한 번 그려 둔다.
func warmup(pos: Vector3) -> void:
	rig.flash(0.05)
	# 숫자 글자도 크기별로 미리 그려 둔다 (글자를 처음 만들 때도 멈칫한다)
	for size in [72, 96]:
		var label := Label3D.new()
		label.text = "0123456789"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = size
		label.outline_size = 18
		label.pixel_size = 0.0005
		get_parent().add_child(label)
		label.global_position = pos
		get_tree().create_timer(0.3, false).timeout.connect(label.queue_free)


# ---------------- 특수 스킬 (플레이어와 같은 규칙, 같은 쿨타임) ----------------

func _announce(skill: String) -> void:
	combat_event.emit("상대 %s!" % CharacterBuild.SKILLS[skill].name, Color(1.0, 0.6, 0.45))
	stats["skill_" + skill] = stats.get("skill_" + skill, 0) + 1


## 평소 판단할 때 쓸 만한 스킬이 있으면 쓰고 true
func _think_skills() -> bool:
	# 질풍: 멀리서 다가갈 때, 또는 상대가 약해졌을 때 몰아치기
	if skills.can_use("haste") and (_dist > 6.0 or (target.hp < target.max_hp * 0.45 and _dist < 4.0)) \
			and randf() < 0.6:
		skills.use("haste")
		_announce("haste")
		rig.glow(Color(0.5, 1.0, 0.7), 1.2)
	# 점멸: 멀리 있으면 순간이동으로 붙어서 바로 벤다
	if skills.can_use("blink") and _dist > 6.0 and _dist < 11.0 and randf() < 0.5:
		var reach := _dist - 2.2
		_blink(_dir, reach)
		_combo_left = 1 if randf() < combo_chance else 0
		_start_attack("slash1")
		return true
	# 갈고리: 멀리 있으면 줄을 걸어 날아간다
	if _dist > 8.0 and _try_grapple_to_target():
		return true
	# 체력이 낮은데 상대가 몰아치면 철벽
	if skills.can_use("iron_guard") and hp < max_hp * 0.4 and target.is_attacking() and _dist < 3.0:
		_use_iron()
		return true
	return false


# --- 점멸 ---

## dir 방향으로 최대 dist 만큼 순간이동 (벽 앞에서 멈춤)
func _blink(dir: Vector3, dist: float) -> void:
	if not skills.use("blink"):
		return
	dist = minf(dist, float(CharacterBuild.SKILLS.blink.range))
	_ray.exclude = [get_rid(), target.get_rid()]
	for h in [0.4, 1.0, 1.6]:
		_ray.from = global_position + Vector3.UP * h
		_ray.to = _ray.from + dir * dist
		var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
		if not hit.is_empty():
			var flat: Vector3 = hit.position - global_position
			flat.y = 0
			dist = minf(dist, flat.length() - 0.6)
	dist = maxf(dist, 0.0)
	var c := Color(1.0, 0.55, 0.4)
	Fx.sparks(get_parent(), global_position + Vector3.UP, -dir, 18, c)
	global_position += dir * dist
	Fx.sparks(get_parent(), global_position + Vector3.UP, dir, 18, c)
	_iframes = 0.3
	_play("dash", -3.0)
	_announce("blink")


## 상대 공격을 점멸로 옆이나 뒤로 피하고, 바로 반격한다
func _blink_dodge() -> void:
	var side := Vector3(-_dir.z, 0, _dir.x) * (1.0 if randf() < 0.5 else -1.0)
	var dir := (side + _dir * (0.6 if randf() < 0.5 else -0.4)).normalized()
	_blink(dir, 4.0)
	# 짧은 대시 상태로 넘어가서, 끝나면 반격
	sm.go("dash", {"vec": dir * 0.2})
	_counter_ready = true


# --- 갈고리 ---

func _build_rope() -> void:
	_rope = MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.03, 0.03, 1.0)
	_rope.mesh = m
	_rope.material_override = LowPoly.mat(Color(0.35, 0.25, 0.15), 0.9)
	_rope.top_level = true
	_rope.visible = false
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rope)


## 상대가 보이고 줄이 닿으면 상대 쪽으로 날아간다
func _try_grapple_to_target() -> bool:
	if not skills.can_use("grapple"):
		return false
	var from := global_position + Vector3.UP * 1.5
	var to := target.global_position + Vector3.UP * 0.4
	if from.distance_to(to) > float(CharacterBuild.SKILLS.grapple.range) or from.distance_to(to) < 4.0:
		return false
	_ray.from = from
	_ray.to = to
	_ray.exclude = [get_rid(), target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	var point := to
	if not hit.is_empty():
		# 상대가 지붕 위에 있으면 지붕 모서리에 걸린다. 모서리가 상대 가까이일 때만 쓴다.
		point = hit.position
		if point.distance_to(to) > 3.5:
			return false
	skills.use("grapple")
	_announce("grapple")
	sm.go("grapple", {"point": point, "on_target": hit.is_empty()})
	return true


func _grapple_enter(d: Dictionary) -> void:
	_grap_point = d.point
	_grap_on_target = d.on_target
	_rope.visible = true
	rig.set_pose(MoveSet.BODY_POSES.climb, 12.0)
	rig.glow(rig.blade_mat.emission, 0.0)
	_play("dash", -4.0)


func _grapple_target() -> Vector3:
	return target.global_position + Vector3.UP * 0.8 if _grap_on_target else _grap_point


func _grapple_update(_delta: float) -> void:
	var tgt := _grapple_target()
	var to := tgt - (global_position + Vector3.UP * 1.0)
	var d := to.length()
	_face = Vector3(to.x, 0, to.z).normalized()
	var stalled := _state_t > 0.3 and get_real_velocity().length() < 2.0
	if d < (2.3 if _grap_on_target else 1.1) or _state_t > 1.5 or stalled:
		var flat := Vector3(to.x, 0, to.z).normalized()
		velocity = flat * 3.0 + Vector3.UP * (2.0 if _grap_on_target else 5.5)
		_push = flat * 3.0
		_repath_t = 0.0
		_direct_t = 0.0
		_back_to_neutral()
		sm.go("approach")
		return
	var v := to / d * float(CharacterBuild.SKILLS.grapple.speed) * 0.85
	_move = Vector3(v.x, 0, v.z)
	velocity = v


func _grapple_exit() -> void:
	_rope.visible = false


func _update_rope() -> void:
	if not _rope.visible:
		return
	var a := global_position + Vector3.UP * 1.5
	var b := _grapple_target()
	var rope_len := a.distance_to(b)
	if rope_len < 0.05:
		return
	var up := Vector3.UP if absf((b - a).normalized().y) < 0.98 else Vector3.RIGHT
	_rope.global_transform = Transform3D(Basis.looking_at(b - a, up), (a + b) * 0.5)
	_rope.scale = Vector3(1, 1, rope_len)


# --- 철벽 ---

func _use_iron() -> void:
	if not skills.use("iron_guard"):
		return
	_announce("iron_guard")
	sm.go("iron")


func _iron_enter(_d: Dictionary) -> void:
	rig.set_pose(MoveSet.BODY_POSES.block, 22.0)
	rig.glow(Color(1.0, 0.85, 0.35), 2.5)


func _iron_update(_delta: float) -> void:
	_move = -_dir * 0.5 if _dist < 2.0 else Vector3.ZERO
	if _state_t >= float(CharacterBuild.SKILLS.iron_guard.duration):
		# 버틴 뒤 바로 반격
		if _dist < 3.0:
			_combo_left = 1
			_start_attack("slash1")
		else:
			_back_to_neutral()


func _iron_exit() -> void:
	rig.glow(rig.blade_mat.emission, 0.0)


# ---------------- 높이: 높은 곳, 아이템, 낭떠러지, 낙하 찍기, 난간, 짚라인, 발판 ----------------
# 공통 규칙은 scripts/combat/vertical_kit.gd. 플레이어와 같은 규칙을 쓴다.

var vkit: VerticalKit
var _seek: ArenaPickup = null       # 노리는 아이템
var _plunge_landed := false
var _plunge_from := 0.0
var _hang := {}
var _hang_hold := 0.5
var _hang_cd := 0.0
var _after_climb_attack := ""
var _zip: Zipline
var _zip_t := 0.0
var _zip_want := -1                 # 이 번호 짚라인을 잡으려고 뛰었다
var _zip_want_t := 0.0
var _smash: BreakablePillar = null  # 상대가 올라선 부서지는 기둥 (벽을 못 타면 부숴서 떨어뜨린다)


## 평소 판단 전에: 높이와 경기장을 이용할 기회가 있으면 쓰고 true
func _think_vertical() -> bool:
	if arena == null:
		return false
	_smash = null
	# 무너질 바닥에 서 있으면 먼저 빠져나간다
	if arena.is_doomed(global_position):
		_seek = null
		sm.go("approach")
		return true
	# 매달린 상대: 바로 베서 떨어뜨린다
	if target.is_hanging() and _dist < 2.6 and _dy > -2.4:
		_combo_left = 0
		_start_attack("slash1")
		stats["stomp"] = stats.get("stomp", 0) + 1
		return true
	# 높은 곳에서 아래 상대에게 낙하 찍기
	var plunge_cost: float = MoveSet.MOVES.plunge.cost
	if _dy < -1.8 and _dy > -9.0 and _dist < 6.5 and is_on_floor() and stamina > plunge_cost \
			and randf() < 0.6 and _clear_line_to_target():
		_leap_plunge()
		return true
	# 아이템 다툼
	var pk := arena.director.best_pickup_for(self, target) if arena.director else null
	if pk and _want_pickup(pk):
		_seek = pk
		sm.go("approach")
		return true
	_seek = null
	# 상대가 낭떠러지나 높은 곳 끝에 서 있으면 날려 보내는 공격
	if _direct and _dist < 2.9 and stamina > 28.0 and randf() < 0.55 and _target_near_edge():
		_combo_left = 0
		_start_attack("heavy" if randf() < 0.6 else "charge")
		stats["edge_push"] = stats.get("edge_push", 0) + 1
		return true
	# 상대가 부서지는 기둥 위에 있는데 올라갈 수 없으면 기둥을 부순다
	if not _direct and not traits.get("wall_climb", false):
		var area := arena.area_of(target.global_position)
		if arena.breakables.has(area):
			var bp: BreakablePillar = arena.breakables[area]
			var to_b := bp.global_position - global_position
			to_b.y = 0
			if not bp.is_broken() and to_b.length() < 2.6:
				_smash = bp
				_combo_left = 2
				_start_attack("slash1")
				return true
	return false


func _want_pickup(pk: ArenaPickup) -> bool:
	var d_me := global_position.distance_to(pk.global_position)
	var d_t := target.global_position.distance_to(pk.global_position)
	if _dist < 2.4 and absf(_dy) < 1.0:
		return false   # 바로 앞에서 싸우는 중이면 싸움부터
	if pk.kind == "heal" and hp < max_hp * 0.75 and d_me < 24.0:
		return true
	return d_me < d_t + 2.5 and d_me < 18.0


func _seeking() -> bool:
	return _seek != null and is_instance_valid(_seek) and not _seek.taken


## 길찾기 목표: 무너질 곳이면 안전한 곳, 아이템을 노리면 아이템, 아니면 상대
func _nav_goal() -> Vector3:
	if arena and arena.is_doomed(global_position):
		return arena.safe_spawn(self)
	if _seeking():
		return _seek.global_position
	return target.global_position


func _needs_nav() -> bool:
	return not _direct or _seeking() or (arena != null and arena.is_doomed(global_position))


## 상대 뒤쪽이 낭떠러지거나 높은 곳 끝인가
func _target_near_edge() -> bool:
	var away := target.global_position - global_position
	away.y = 0
	if away.length() < 0.1:
		return false
	var p := target.global_position + away.normalized() * 2.2
	return not vkit.ground_near(p, 2.6)


## 뛰어내릴 앞쪽이 막혀 있지 않나 (벽이나 기둥이 없고, 상대가 선 곳에 바닥이 있다)
func _clear_line_to_target() -> bool:
	_ray.exclude = [get_rid(), target.get_rid()]
	_ray.from = global_position + Vector3.UP * 1.0
	_ray.to = _ray.from + _dir * minf(_dist, 2.5)
	if not get_world_3d().direct_space_state.intersect_ray(_ray).is_empty():
		return false
	return vkit.ground_near(target.global_position, 1.0)


## 걸어가는 쪽이 낭떠러지(또는 곧 무너질 바닥)면 옆으로 비키거나 멈춘다
func _edge_guard(mv: Vector3) -> Vector3:
	if arena == null or mv.length() < 0.3 or not is_on_floor():
		return mv
	var ahead := global_position + Vector3(mv.x, 0, mv.z).normalized() * 1.3
	var doomed_ahead := arena.is_doomed(ahead) and not arena.is_doomed(global_position)
	if not doomed_ahead and vkit.ground_near(ahead, 2.2):
		return mv
	stats["edge_avoid"] = stats.get("edge_avoid", 0) + 1
	var side := Vector3(-mv.z, 0, mv.x).normalized()
	for s in [1.0, -1.0]:
		var q: Vector3 = global_position + side * s * 1.3
		if vkit.ground_near(q, 2.2) and not (arena.is_doomed(q) and not arena.is_doomed(global_position)):
			return side * s * mv.length() * 0.8
	return Vector3.ZERO


# --- 낙하 찍기 ---

var _leap_v := Vector3.ZERO


func _leap_plunge() -> void:
	var fall := maxf(-_dy, 0.5)
	var t := sqrt(2.0 * fall / _gravity) + 0.35
	_leap_v = _dir * clampf(_dist / t, 2.0, 8.0)
	velocity = _leap_v + Vector3.UP * 3.5
	_attack = "plunge"
	stats["move_plunge"] = stats.get("move_plunge", 0) + 1
	spend_stamina(float(MoveSet.MOVES.plunge.cost))
	sm.go("plunge")


func _plunge_enter(_d: Dictionary) -> void:
	_plunge_landed = false
	_plunge_from = global_position.y
	_combo_left = 0
	rig.set_pose(MoveSet.MOVES.plunge.body.windup, 10.0)
	rig.glow(Color(1.0, 0.15, 0.1), 3.0)
	_play("warn_heavy", -2.0)
	combat_event.emit("위에서 내려온다!", Color(1.0, 0.45, 0.3))


func _plunge_update(_delta: float) -> void:
	var data: Dictionary = MoveSet.MOVES.plunge
	if _plunge_landed:
		_turn_speed = 2.0
		if _state_t >= float(data.ai_recover) * _atk_mult():
			_back_to_neutral()
		return
	_face = _dir
	# 상대 쪽으로 몸을 틀며 내려간다
	_move = _leap_v.lerp(_dir * clampf(_dist * 2.5, 0.0, 8.0), 0.5)
	if _state_t > 0.3 or velocity.y < 0.0:
		velocity.y = minf(velocity.y, -16.0)
		rig.set_pose(data.body.strike, 18.0)
	if is_on_floor() and _state_t > 0.1:
		_plunge_impact()
	elif _state_t > 3.0:
		_back_to_neutral()


func _plunge_impact() -> void:
	var data: Dictionary = MoveSet.MOVES.plunge
	_plunge_landed = true
	sm.time = 0.0
	velocity = Vector3.ZERO
	_move = Vector3.ZERO
	_leap_v = Vector3.ZERO
	_play("hit_heavy", 0.0)
	Fx.impact(get_parent(), global_position + Vector3.UP * 0.1, Vector3.UP, Color(0.82, 0.74, 0.6), 26)
	rig.glow(rig.blade_mat.emission, 0.0)
	var drop := maxf(_plunge_from - global_position.y, 0.0) + 1.0
	var dmg := int(lerpf(float(data.damage), float(data.damage_max), clampf((drop - 1.6) / 6.0, 0.0, 1.0)))
	var to_t := target.global_position - global_position
	var dy := to_t.y
	to_t.y = 0
	if to_t.length() <= float(data.reach) and absf(dy) < 1.5:
		var info := {"move": "plunge", "damage": int(round(dmg * build.damage_mult() * vkit.damage_mult())),
				"react": data.react, "guard": data.guard, "dir": data.get("dir", "high"),
				"pressure": build.guard_pressure(), "power": vkit.powered(), "knockdown": true}
		var result := target.receive_attack(info, self)
		if result in ["hit", "guard_broken"]:
			stats["plunge_hit"] = stats.get("plunge_hit", 0) + 1
			Fx.impact(get_parent(), target.global_position + Vector3(0, 1.3, 0), Vector3.UP, Color(0.75, 0.1, 0.08), 18)
		elif result == "dodged":
			_dodged_by_target += 1
	vkit.reset_fall()


# --- 난간 매달리기 ---

func _try_hang() -> bool:
	if _hang_cd > 0.0 or velocity.y > -1.0 or is_on_floor():
		return false
	if not (state in ["idle", "approach", "circle", "recover"] or (state == "stagger" and _state_t > 0.2)):
		return false
	var ledge := vkit.find_ledge(-global_transform.basis.z)
	if ledge.is_empty():
		var back := Vector3(-_push.x, 0, -_push.z)
		if back.length() > 0.5:
			ledge = vkit.find_ledge(back)
	if ledge.is_empty():
		return false
	sm.go("hang", ledge)
	return true


func _hang_enter(d: Dictionary) -> void:
	_hang = d
	var n: Vector3 = d.n
	var p: Vector3 = d.point
	global_position = Vector3(p.x, float(d.y) - 1.35, p.z) + n * 0.45
	velocity = Vector3.ZERO
	_push = Vector3.ZERO
	rotation.y = atan2(n.x, n.z)
	_hang_hold = randf_range(0.35, 0.9)
	vkit.reset_fall()
	rig.set_pose(MoveSet.BODY_POSES.hang, 12.0)
	rig.glow(rig.blade_mat.emission, 0.0)
	stats["hang"] = stats.get("hang", 0) + 1
	combat_event.emit("상대가 난간에 매달렸다!", Color(1.0, 0.8, 0.5))


func _hang_update(delta: float) -> void:
	_move = Vector3.ZERO
	velocity = Vector3.ZERO
	_face = -(_hang.n as Vector3)
	_turn_speed = 20.0
	spend_stamina(VerticalKit.HANG_COST * delta)
	if _state_t < _hang_hold:
		return
	var ledge_y: float = _hang.y
	var lp: Vector3 = _hang.point
	var t_flat := Vector2(target.global_position.x - lp.x, target.global_position.z - lp.z).length()
	# 상대가 난간 위 바로 앞에 있으면 뛰어오르며 벤다
	if t_flat < 3.2 and absf(target.global_position.y - ledge_y) < 0.6 and stamina > 8.0:
		_after_climb_attack = "ledge_slash"
	sm.go("climb", {"top": ledge_y, "dir": -(_hang.n as Vector3)})


func _hit_while_hanging(info: Dictionary, dir: Vector3) -> String:
	_apply_damage(int(info.damage), dir, false)
	if dead:
		return "hit"
	_hang_cd = 1.0
	_push = (_hang.n as Vector3) * 2.5
	velocity = Vector3.DOWN
	vkit.knock()
	combat_event.emit("상대가 난간에서 떨어진다!", Color(1.0, 0.8, 0.4))
	_stagger(MoveSet.REACTIONS.flinch.time, false)
	return "hit"


# --- 짚라인 ---

func _zip_enter(d: Dictionary) -> void:
	_zip = d.z
	_zip_t = d.t
	_zip.rider_count += 1
	rig.set_pose(MoveSet.BODY_POSES.climb, 12.0)
	stats["zip"] = stats.get("zip", 0) + 1
	_play("dash", -4.0)


func _zip_update(delta: float) -> void:
	if not is_instance_valid(_zip) or not _zip.alive:
		_zip_leave(Vector3.ZERO)
		return
	_zip_t += Zipline.SPEED * delta / _zip.length()
	var zdir := _zip.dir()
	_face = Vector3(zdir.x, 0, zdir.z).normalized()
	_turn_speed = 12.0
	# 지나가는 길 아래에 상대가 있으면 손을 놓고 내리꽂는다
	var below := global_position.y - target.global_position.y
	if below > 2.0 and _dist < 3.0 and stamina > float(MoveSet.MOVES.plunge.cost) * 0.5:
		_zip_leave(Vector3.ZERO)
		_leap_v = _dir * 2.0
		_attack = "plunge"
		stats["move_plunge"] = stats.get("move_plunge", 0) + 1
		spend_stamina(float(MoveSet.MOVES.plunge.cost))
		sm.go("plunge")
		return
	if _zip_t >= 1.0:
		_zip_leave(zdir * 5.0 + Vector3.UP * 2.0)
		_path_i += 1
		_back_to_neutral()
		sm.go("approach")
		return
	var v := (_zip.feet_at(_zip_t) - global_position) / maxf(delta, 0.001)
	velocity = v
	_move = Vector3(v.x, 0, v.z)


func _zip_leave(v: Vector3) -> void:
	if is_instance_valid(_zip):
		_zip.rider_count -= 1
	_zip = null
	velocity = v
	_push = Vector3(v.x, 0, v.z)
	vkit.reset_fall()


# --- 발판과 짚라인 길 ---

## 길이 '발판' 이나 '짚라인' 일 때 움직일 방향. 처리할 게 아니면 null 대신 ZERO 와 false.
func _nav_special(wp: Dictionary, dir: Vector3, hd: float) -> Variant:
	# 다음 길이 발판이면, 발판이 내 높이에 와서 멈춰 있을 때만 올라선다 (밑에 서 있으면 내려오지 못한다)
	if wp.kind != "lift" and _path_i + 1 < _path.size() and _path[_path_i + 1].kind == "lift":
		var nl: ArenaLift = arena.lifts[_path[_path_i + 1].ref]
		var nc := nl.center()
		var noff := Vector2(global_position.x - nc.x, global_position.z - nc.z)
		var riding := noff.length() < 1.0 and absf(global_position.y - nl.surface_y()) < 0.4
		if not riding and not nl.resting_at(global_position.y):
			_stuck_t = 0.0
			if noff.length() < 2.3:
				if noff.length() < 0.2:
					noff = Vector2(1, 0)
				return Vector3(noff.x, 0, noff.y).normalized() * 3.0
			return dir * _speed() if noff.length() > 3.2 else Vector3.ZERO
	match wp.kind:
		"lift":
			var lift: ArenaLift = arena.lifts[wp.ref]
			var c := lift.center()
			var off := Vector2(global_position.x - c.x, global_position.z - c.z)
			_stuck_t = 0.0
			if off.length() < 1.0 and absf(global_position.y - lift.surface_y()) < 0.4:
				# 타고 있다: 가운데에 서서 기다린다
				return Vector3(c.x - global_position.x, 0, c.z - global_position.z) * 2.0
			if lift.resting_at(global_position.y):
				return dir * _speed()
			# 발판이 오기를 옆에서 기다린다 (밑에 서 있으면 내려오지 않는다)
			if off.length() < 2.1:
				if off.length() < 0.3:
					var prev: Vector3 = _path[maxi(_path_i - 1, 0)].pos if _path_i > 0 else global_position + Vector3.RIGHT
					off = Vector2(global_position.x - c.x, global_position.z - c.z) + Vector2(prev.x - c.x, prev.z - c.z).normalized() * 0.5
					if off.length() < 0.3:
						off = Vector2(1, 0)
				return Vector3(off.x, 0, off.y).normalized() * 3.0
			return Vector3.ZERO
		"zip":
			var z: Zipline = arena.ziplines[wp.ref]
			if not z.alive:
				_repath_t = 0.0
				return Vector3.ZERO
			var start := Vector2(z.a.x - global_position.x, z.a.z - global_position.z)
			if start.length() < 1.4 and is_on_floor():
				velocity.y = 5.6
				_zip_want = wp.ref
				_zip_want_t = 0.0
				return Vector3.ZERO
			var to := Vector3(start.x, 0, start.y)
			_face = to.normalized()
			return to.normalized() * _speed()
	return null


# --- 매 프레임 (move_and_slide 다음) ---

func _vertical_tick(delta: float) -> void:
	_hang_cd = maxf(_hang_cd - delta, 0.0)
	if _zip_want >= 0:
		_zip_want_t += delta
		if not is_on_floor() and state != "zip" and arena:
			var z: Zipline = arena.ziplines[_zip_want]
			var t := z.grab_t(global_position)
			if t >= 0.0:
				_zip_want = -1
				sm.go("zip", {"z": z, "t": t})
		elif _zip_want_t > 0.4 and is_on_floor():
			_zip_want = -1
			_repath_t = 0.0
	if active and not dead and arena:
		_try_hang()
	var f := vkit.tick(delta, is_on_floor())
	if f == -1:
		_fall_into_void()
	elif f > 0 and not dead:
		_apply_damage(f, Vector3.ZERO, true)
		combat_event.emit("상대 추락! -%d" % f, Color(1.0, 0.8, 0.4))
		stats["fall_damage"] = stats.get("fall_damage", 0) + f
		if not dead:
			_stagger(MoveSet.REACTIONS.knockdown.time)


func _fall_into_void() -> void:
	stats["void"] = stats.get("void", 0) + 1
	if state == "zip":
		_zip_leave(Vector3.ZERO)
	global_position = arena.safe_spawn(self) if arena else Vector3(0, 0.1, 0)
	velocity = Vector3.ZERO
	_push = Vector3.ZERO
	vkit.reset_fall()
	_iframes = 1.0
	_repath_t = 0.0
	if arena and arena.director.running and not dead:
		var dmg := int(ceilf(max_hp * VerticalKit.VOID_DAMAGE))
		combat_event.emit("상대가 낭떠러지로! -%d" % dmg, Color(1.0, 0.85, 0.35))
		_apply_damage(dmg, Vector3.ZERO, true)
		if not dead:
			_back_to_neutral()


## 맞은 결과에 따라 날려 보내기와 넘어짐을 붙인다 (_take_hit 은 그대로 두고 바깥에서)
func _after_hit(result: String, info: Dictionary, dir: Vector3) -> void:
	if dead or result != "hit":
		return
	vkit.knock(VerticalKit.FLINCH_KNOCK_TIME)
	var l := VerticalKit.launch_for(info)
	if l != Vector2.ZERO:
		apply_knockback(Vector3(dir.x, 0, dir.z).normalized() * l.x + Vector3.UP * l.y)
	if info.get("knockdown", false):
		_stagger(MoveSet.REACTIONS.knockdown.time)


## 강한 공격이나 던지기로 날려 보낸다
func apply_knockback(vec: Vector3) -> void:
	_push = Vector3(vec.x, 0, vec.z)
	velocity.x = vec.x
	velocity.z = vec.z
	velocity.y = maxf(velocity.y, vec.y)
	vkit.knock()


func is_hanging() -> bool:
	return state == "hang"


func on_pickup(kind: String) -> void:
	_seek = null
	_play("clang", -4.0)
	if kind == "power":
		rig.glow(Color(1.0, 0.55, 0.2), 1.5)


## 부서지는 기둥을 노리고 휘두를 때: 기둥에 닿으면 true
func _try_smash(data: Dictionary) -> bool:
	if _smash == null or not is_instance_valid(_smash) or _smash.is_broken():
		return false
	var to_b := _smash.global_position - global_position
	to_b.y = 0
	if to_b.length() > float(data.reach) + 1.0:
		return false
	_hit_done = true
	var info := {"move": _attack, "damage": int(data.damage), "react": data.react, "guard": data.guard}
	_smash.take_hit(info, to_b.normalized(), self)
	stats["smash"] = stats.get("smash", 0) + 1
	return true


## 지금 올라타 있는 발판이 있나
func _riding_lift() -> bool:
	if arena == null:
		return false
	for l in arena.lifts:
		var c := l.center()
		if absf(global_position.x - c.x) < 1.15 and absf(global_position.z - c.z) < 1.15 \
				and absf(global_position.y - l.surface_y()) < 0.4:
			return true
	return false
