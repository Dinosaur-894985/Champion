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
var read_skill := 0.55          # 상대 공격 방향을 보고 맞게 막을 확률 (나머지는 버릇으로 짐작)
var feint_chance := 0.3         # 공격 준비 중 방향을 바꾸거나 잡기로 바꾸는 속임수
var grab_chance := 0.35         # 막고 있는 상대에게 다가가 잡기
## 막기 방향 (AttackDir). 상대 공격과 방향이 같아야 막힌다.
var guard_dir := AttackDir.SIDE
## 상대 버릇 기억
var mind := MindReader.new()
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
var _feint_checked := false     # 이번 공격 준비에서 속임수를 쓸지 이미 정했나
var _thrown_t := 0.0            # 던져진 뒤 남은 '벽꽝' 시간
var _grab_wait := 0.0           # 잡으려고 다가가는 시간

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
	add_to_group("grabbable")
	max_hp = build.max_hp()
	hp = max_hp
	max_stamina = build.max_stamina()
	stamina = max_stamina
	traits = {"wall_climb": build.has("wall")}
	skills = SkillKit.new(self, build)
	# 기술 능력치가 높을수록 상대 공격 방향을 잘 읽는다
	read_skill = clampf(0.45 + 0.05 * (float(build.stats.tec) - 5.0), 0.25, 0.8)
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
	if not is_on_floor() and state not in ["climb", "grapple"]:
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
	_thrown_t = maxf(_thrown_t - delta, 0.0)
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
		mind.tick(delta, target.blocking)
		_direct_t -= delta
		if _direct_t <= 0.0:
			_direct_t = 0.2
			_direct = _check_direct()
		sm.tick(delta)
		# 몸을 상대 쪽으로 돌린다 (길을 따라갈 때는 가는 쪽으로)
		var look := _face if _face != Vector3.ZERO else _dir
		var desired := atan2(-look.x, -look.z)
		rotation.y = rotate_toward(rotation.y, desired, _turn_speed * delta)

	# 던져지는 중에는 밀린 힘이 천천히 줄어든다 (멀리 날아간다)
	_push = _push.lerp(Vector3.ZERO, clampf(delta * (1.6 if _thrown_t > 0.0 else 6.0), 0, 1))
	var mv := _move + _push
	velocity.x = lerpf(velocity.x, mv.x, clampf(delta * 12.0, 0, 1))
	velocity.z = lerpf(velocity.z, mv.z, clampf(delta * 12.0, 0, 1))
	var pre_speed := Vector2(velocity.x, velocity.z).length()
	move_and_slide()
	if _thrown_t > 0.0 and is_on_wall() and pre_speed >= float(MoveSet.THROW.wall_slam_speed):
		_wall_slam()


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
	if not _direct:
		# 상대가 다른 층(지붕, 기둥 위)에 있으면: 갈고리가 있으면 줄을 걸어 날아가고, 아니면 길을 찾아 올라간다
		if _dy > 1.5 and _try_grapple_to_target():
			return
		sm.go("approach")
		return
	if _grab_wait > 0.0:
		_think_t = 0.1   # 잡으러 다가가는 중
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
	# 상대가 막고 서 있으면: 다가가서 잡는다 (잡기는 막기를 이긴다)
	if target.blocking and _dist < 3.4 and randf() < grab_chance + mind.grab_urge() * 0.6:
		if _dist < float(MoveSet.MOVES.grab.reach) + 0.2:
			_start_attack("grab")
		else:
			_grab_wait = 0.7
			sm.go("approach")
			_think_t = 0.12
		return
	# 상대가 잡기를 자주 쓰고 가까우면: 먼저 빠르게 찔러 끊는다 (공격은 잡기를 이긴다)
	if _dist < 2.4 and randf() < mind.grab_rate * 1.5 and not target.attack_threat():
		_combo_left = 0
		_start_attack("thrust")
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
		if randf() < 0.15:
			_start_attack("heavy")
			_combo_left = 0
		else:
			# 방향은 상대가 덜 막는 쪽, 지금 막고 있는 쪽은 피해서
			var dir := mind.choose_dir(target.guard_dir if target.blocking else "")
			_combo_left = 0
			if dir == AttackDir.SIDE and randf() < combo_chance:
				# 연속 베기: 몇 번 이어 갈지 미리 정한다 (0~2번 더)
				_combo_left = 1 if randf() < 0.55 else 2
			_start_attack(_move_for_dir(dir))
	elif r < aggression + 0.25:
		sm.go("circle")
		_strafe_dir = -1.0 if randf() < 0.5 else 1.0
		_think_t = randf_range(0.5, 1.1)
	elif r < aggression + 0.33:
		_dash_dir(-0.8, 0.6)
	else:
		guard_dir = mind.guess_dir()
		_enter_block()


func _can_react() -> bool:
	return active and not dead and state in ["idle", "approach", "circle", "recover"]


## 상대 공격 방향 읽기: 실력(read_skill)만큼은 보고 맞히고, 나머지는 버릇으로 짐작한다
func _read_dir(actual: String) -> String:
	if actual == "":
		return guard_dir
	if randf() < read_skill:
		return actual
	return mind.guess_dir()


func _set_guard(dir: String) -> void:
	guard_dir = dir
	if state == "block":
		rig.set_pose(MoveSet.BODY_POSES[MoveSet.block_pose(guard_dir)], 22.0)


## 플레이어가 공격을 시작했을 때 (Main 이 연결해 준다)
func on_target_attack(kind: String) -> void:
	if not active or dead:
		return
	var dir: String = MoveSet.MOVES[kind].get("dir", "") if MoveSet.MOVES.has(kind) else ""
	if kind == "grab":
		mind.saw_grab()
	else:
		mind.saw_attack(dir)
	if global_position.distance_to(target.global_position) > 3.6:
		return
	# 힘을 모으던 중에 상대가 먼저 휘두르면: 모으기를 끊고 옆으로 빠진다 (차지 끊고 대시)
	if state == "windup" and _attack == "charge" and kind != "grab" and randf() < 0.55:
		combat_event.emit("상대가 차지를 끊었다!", Color(1.0, 0.7, 0.4))
		stats["charge_cancel"] = stats.get("charge_cancel", 0) + 1
		_counter_ready = true
		_dash_dir(-0.1, 1.0)
		return
	if state == "block":
		# 막는 중: 방향을 다시 읽고 맞춘다
		await get_tree().create_timer(reaction_time, false).timeout
		if state != "block":
			return
		if kind == "grab":
			# 잡기다! 막고 있으면 잡힌다 → 빠져나간다
			if randf() < 0.25 + read_skill * 0.5:
				_dash_dir(-1.0, 0.4)
			return
		_set_guard(_read_dir(dir))
		return
	if not _can_react():
		return
	await get_tree().create_timer(reaction_time, false).timeout
	if not _can_react():
		return
	if kind == "grab":
		# 잡기는 막으면 안 된다: 뒤로 빠지거나, 가까우면 먼저 찔러 끊는다
		if randf() < 0.3 + read_skill * 0.4:
			_dash_dir(-1.0, 0.3)
		return
	guard_dir = _read_dir(dir)
	var big := kind in ["heavy", "charge"]
	# 상대가 자주 속이면 서둘러 막지 않는다
	var block := (block_chance + (0.25 if _alert > 0.0 else 0.0)) * (1.0 - mind.feint_rate * 0.6)
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


## 플레이어가 공격을 멈췄을 때 (속임수). 자주 속이면 다음엔 덜 서둘러 막는다.
func on_target_feint() -> void:
	mind.saw_feint()
	stats["saw_feint"] = stats.get("saw_feint", 0) + 1
	# 속임수에 막기만 하고 서 있으면 잡힌다: 가끔 바로 막기를 풀고 반격
	if state == "block" and _dist < 2.6 and randf() < 0.4 + mind.feint_rate:
		_combo_left = 0
		_start_attack("thrust")


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
	rig.reach = 0.0
	# 경직이 풀렸는데 상대가 이미 휘두르고 있으면: 바로 방향을 읽고 막는다 (연타에 갇히지 않게)
	if active and target and target.attack_threat() and _dist < 3.2 \
			and randf() < block_chance + (0.3 if _alert > 0.0 else 0.1):
		guard_dir = _read_dir(target.attack_dir())
		_enter_block()


# ---------------- 행동 상태 ----------------

func _neutral_update(delta: float) -> void:
	_think_t -= delta
	if _think_t <= 0.0:
		_think()
		if state not in ["approach", "circle"]:
			return
	if not _direct:
		_move = _nav_move(delta)
		return
	_path.clear()
	var side := Vector3(-_dir.z, 0, _dir.x)
	if _grab_wait > 0.0:
		# 잡으려고 바짝 붙는다
		_grab_wait -= delta
		_move = _dir * _speed() * 1.2
		if _dist < float(MoveSet.MOVES.grab.reach) and target.blocking:
			_grab_wait = 0.0
			_start_attack("grab")
		return
	if state == "approach":
		_move = _dir * _speed() if _dist > 2.0 else Vector3.ZERO
	else:
		var keep := (_dist - 2.6) * 1.5
		if stamina < 22.0:
			keep = (_dist - 4.0) * 1.5   # 숨 고르는 중엔 멀찍이
		_move = side * _strafe_dir * STRAFE_SPEED * build.speed_mult() + _dir * keep


func _start_attack(kind: String) -> void:
	if stamina < float(MoveSet.MOVES[kind].cost) * 0.5:
		_back_to_neutral()
		return
	_attack = kind
	_grab_wait = 0.0
	_feint_checked = false
	stats["move_" + kind] = stats.get("move_" + kind, 0) + 1
	sm.go("windup")


## 방향에 맞는 공격 동작
static func _move_for_dir(dir: String) -> String:
	match dir:
		AttackDir.HIGH:
			return "overhead"
		AttackDir.MID:
			return "thrust"
	return "slash1"


## 지금 준비 중인 공격의 방향 (화면 표시와 점검용). 잡기는 "grab".
func attack_dir() -> String:
	if state not in ["windup", "strike"]:
		return ""
	if _attack == "grab":
		return "grab"
	return MoveSet.MOVES[_attack].get("dir", "")


## 공격 준비가 얼마나 됐나 (0~1, 휘두르는 중이면 1)
func windup_progress() -> float:
	if state == "strike":
		return 1.0
	if state != "windup":
		return 0.0
	return clampf(_state_t / maxf(_windup_len, 0.01), 0.0, 1.0)


## 잡기를 끊을 수 있는 공격 중인가
func attack_threat() -> bool:
	return state in ["windup", "strike"] and _attack != "grab"


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
	if _attack == "grab":
		col = Color(0.8, 0.35, 1.0)   # 보랏빛 = 잡기: 막지 말고 때리거나 피하라
		rig.reach = 1.0
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
	# 속임수: 준비가 반쯤 됐을 때 한 번 정한다
	if not _feint_checked and _state_t >= _windup_len * 0.45:
		_feint_checked = true
		if _try_feint():
			return
	if _state_t >= _windup_len:
		sm.go("strike")


## 상대가 내 공격 방향에 맞춰 막고 있으면: 방향을 바꾸거나, 잡기로 바꾸거나, 멈춘다.
## 잘 막는 상대일수록 자주 쓴다. 바꾼 뒤에도 보고 막을 시간은 남겨 둔다.
func _try_feint() -> bool:
	if _attack in ["counter", "grab"]:
		return false
	var chance := feint_chance * (0.4 + mind.feint_urge())
	var reading := target.blocking and AttackDir.blocks(target.guard_dir, attack_dir())
	if reading:
		chance += 0.25
	if randf() >= chance:
		return false
	stats["feint"] = stats.get("feint", 0) + 1
	var r := randf()
	if target.blocking and _dist < float(MoveSet.MOVES.grab.reach) + 0.6 and r < 0.5:
		# 휘두르는 척하다 잡기
		stats["feint_grab"] = stats.get("feint_grab", 0) + 1
		_start_attack("grab")
		_feint_checked = true
		return true
	if r < 0.85 and _attack != "charge":
		# 방향 바꾸기: 다른 방향으로 다시 준비한다 (조금 짧게)
		var old := attack_dir()
		var dir := old
		for i in 4:
			dir = mind.choose_dir(target.guard_dir if target.blocking else old)
			if dir != old:
				break
		if dir == old:
			return false
		stats["feint_switch"] = stats.get("feint_switch", 0) + 1
		_combo_left = 0
		_attack = _move_for_dir(dir)
		_feint_checked = true
		var data: Dictionary = MoveSet.MOVES[_attack]
		_windup_len = maxf(data.ai_windup * _atk_mult() * 0.75, 0.32)
		sm.time = 0.0
		rig.set_pose(data.body.windup, 3.0 / _windup_len)
		_play("warn_light", -5.0)
		return true
	# 멈추고 물러난다 (헛막기를 유도)
	stats["feint_stop"] = stats.get("feint_stop", 0) + 1
	if _attack == "charge":
		# 차지를 끊고 옆으로 대시
		_counter_ready = false
		_dash_dir(0.3, 1.0)
	else:
		_back_to_neutral()
	return true


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
		if _attack == "grab":
			_try_grab(data)
		else:
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
	rig.set_pose(MoveSet.BODY_POSES[MoveSet.block_pose(guard_dir)], 22.0)
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
	_grab_wait = 0.0
	rig.reach = 0.0
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
	if _repath_t <= 0.0 or _path_i >= _path.size():
		_repath_t = 0.6
		_path = arena.find_path(global_position, target.global_position, traits.get("wall_climb", false))
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
	if _dist > float(data.reach) + 0.15 or absf(_dy) > 1.4:
		return
	var facing := -global_transform.basis.z
	facing.y = 0
	if facing.normalized().dot(_dir) < HIT_ANGLE:
		return
	_hit_done = true
	var info := {
		"move": _attack, "damage": int(round(float(data.damage) * build.damage_mult())) + randi_range(-2, 2),
		"react": data.react, "guard": data.get("ai_guard", data.guard), "pressure": build.guard_pressure(),
		"dir": data.get("dir", ""),
	}
	var result := target.receive_attack(info, self)
	mind.my_attack_result(info.dir, result)
	stats["res_" + result] = stats.get("res_" + result, 0) + 1
	match result:
		"parried":
			_stagger(0.75)
			combat_event.emit("반격 기회!", Color(0.55, 0.85, 1.0))
		"blocked":
			_push = -_dir * 3.0
			_combo_left = 0
		"dodged":
			_dodged_by_target += 1
		"guard_broken", "hit", "wrong_guard":
			Fx.impact(get_parent(), target.global_position + Vector3(0, 1.3, 0), _dir + Vector3.UP * 0.3,
					Color(0.75, 0.1, 0.08), 14)


# ---------------- 잡기 ----------------

func _try_grab(data: Dictionary) -> void:
	if _dist > float(data.reach) + 0.2 or absf(_dy) > 1.2:
		return
	var facing := -global_transform.basis.z
	facing.y = 0
	if facing.normalized().dot(_dir) < 0.4:
		return
	_hit_done = true
	rig.reach = 0.0
	var info := {"damage": int(round(float(data.damage) * build.damage_mult())), "react": "thrown",
			"throw": _throw_dir() * float(data.throw_speed) + Vector3.UP * float(data.throw_up)}
	var result := target.take_grab(info, self)
	stats["grab_" + result] = stats.get("grab_" + result, 0) + 1
	match result:
		"thrown":
			_play("hit_heavy")
			combat_event.emit("상대가 잡아 던졌다!", Color(1.0, 0.45, 0.8))
		"beaten", "blocked":
			_stagger(MoveSet.REACTIONS.grab_fail.time)
			_push = -_dir * float(MoveSet.REACTIONS.grab_fail.push)
		"clash":
			_play("clang", -2.0)
			_stagger(MoveSet.REACTIONS.recoil.time, false)
			_push = -_dir * 3.0


## 던질 방향: 상대 뒤쪽 가운데 + 양옆으로 비스듬히 중에서, 벽에 부딪히거나 낭떠러지로 떨어지는 쪽
func _throw_dir() -> Vector3:
	var best := _dir
	var best_score := 0.0
	var space := get_world_3d().direct_space_state
	var from := target.global_position + Vector3.UP * 1.0
	_ray.exclude = [get_rid(), target.get_rid()]
	for deg in [0.0, -40.0, 40.0, -75.0, 75.0]:
		var c := _dir.rotated(Vector3.UP, deg_to_rad(deg))
		var score := 0.0
		_ray.from = from
		_ray.to = from + c * 3.2
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty() and absf((hit.normal as Vector3).y) < 0.4:
			score = 2.0 + (3.2 - from.distance_to(hit.position))   # 벽꽝
		else:
			# 2.5m 앞에 발 디딜 곳이 없으면 낭떠러지
			_ray.from = from + c * 2.5
			_ray.to = _ray.from + Vector3.DOWN * 3.0
			if space.intersect_ray(_ray).is_empty():
				score = 4.0
		score -= absf(deg) / 150.0
		if score > best_score:
			best_score = score
			best = c
	return best


## 상대가 나를 잡았을 때. 결과: "thrown", "beaten", "clash", "dodged", "blocked"
func take_grab(info: Dictionary, attacker: Node3D) -> String:
	var r := _take_grab(info, attacker)
	stats["got_grab_" + r] = stats.get("got_grab_" + r, 0) + 1
	return r


func _take_grab(info: Dictionary, attacker: Node3D) -> String:
	if dead:
		return "none"
	if _iframes > 0.0:
		_counter_ready = true
		combat_event.emit("상대가 잡기를 피했다!", Color(1.0, 0.7, 0.4))
		return "dodged"
	if state == "iron":
		combat_event.emit("철벽은 잡히지 않는다", Color(1.0, 0.85, 0.4))
		return "blocked"
	if state == "windup" and _attack == "grab":
		_stagger(MoveSet.REACTIONS.recoil.time, false)
		_push = (global_position - attacker.global_position).normalized() * 3.0
		return "clash"
	if attack_threat():
		combat_event.emit("상대가 휘둘러 잡기를 끊었다!", Color(1.0, 0.55, 0.35))
		return "beaten"
	var dir := global_position - attacker.global_position
	dir.y = 0
	dir = dir.normalized()
	_apply_damage(int(info.damage), dir, true)
	if not dead:
		_stagger(MoveSet.REACTIONS.thrown.time)
		apply_throw(info.throw)
	return "thrown"


## 던져진다: 날아가는 동안 벽에 세게 부딪히면 '벽꽝'
func apply_throw(vec: Vector3) -> void:
	_thrown_t = float(MoveSet.THROW.slam_time)
	if has_method("apply_knockback"):
		call("apply_knockback", vec)
	else:
		_push = Vector3(vec.x, 0, vec.z)
		velocity = vec


func _wall_slam() -> void:
	_thrown_t = 0.0
	_push = Vector3.ZERO
	var dmg := int(MoveSet.THROW.wall_slam_damage)
	combat_event.emit("벽꽝!", Color(1.0, 0.6, 0.3))
	stats["wall_slam"] = stats.get("wall_slam", 0) + 1
	var n := get_wall_normal()
	_apply_damage(dmg, -n, true)
	if not dead:
		_stagger(MoveSet.REACTIONS.stagger.time)


# ---------------- 맞을 때 ----------------

## 플레이어의 칼에 닿았을 때 불린다. info: {"damage", "react", "guard"}
## 결과: "hit", "blocked", "parried", "dodged"
func take_hit(info: Dictionary, dir: Vector3, _attacker: Node3D = null) -> String:
	var r := _take_hit(info, dir)
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
	if state == "block" and facing_attacker and info.guard != "unblockable" \
			and not AttackDir.blocks(guard_dir, info.get("dir", "")):
		# 막는 방향이 틀렸다: 빈 곳을 베였다
		combat_event.emit("빈 곳을 베었다!", Color(1.0, 0.85, 0.4))
		stats["wrong_guard"] = stats.get("wrong_guard", 0) + 1
		_apply_damage(damage, dir, big)
		if not dead:
			_stagger(MoveSet.REACTIONS.stagger.time if big else MoveSet.REACTIONS.flinch.time, big)
		return "hit"
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
