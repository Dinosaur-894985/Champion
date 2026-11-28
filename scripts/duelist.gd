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

signal ammo_changed(value: int, max_value: int)
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
const HALF_BLOCK := 0.5        # 방향이 틀린 막기: 피해 절반 (플레이어와 같은 규칙)
const RUN_SPEED := 7.2          # 달려들 때 (플레이어 달리기와 비슷하게)
const SLIDE_SPEED := 8.5        # 미끄러져 들어올 때

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
## 난이도: Game.ai_difficulty() 가 정한다. "normal"(보통)은 위 기본값 그대로.
## 쉬움은 굼뜨고 덜 막고 덜 아프게, 어려움은 빨리 읽고 잘 막고 속임수도 자주.
## read: 공격 방향 읽기 더하기, windup: 휘두르는 준비·회복 시간 배율, damage: 주는 피해 배율,
## special: 필살기가 차면 쓰는 확률
const DIFFICULTY := {
	"easy": {"aggression": 0.48, "block_chance": 0.28, "parry_chance": 0.14, "dodge_chance": 0.08,
		"reaction_time": 0.2, "counter_chance": 0.35, "combo_chance": 0.35, "charge_chance": 0.12,
		"feint_chance": 0.1, "grab_chance": 0.18, "read": -0.15, "windup": 1.2, "damage": 0.85, "special": 0.3},
	"normal": {},
	"hard": {"aggression": 0.62, "block_chance": 0.58, "parry_chance": 0.42, "dodge_chance": 0.24,
		"reaction_time": 0.05, "counter_chance": 0.85, "combo_chance": 0.68, "charge_chance": 0.2,
		"feint_chance": 0.42, "grab_chance": 0.45, "read": 0.15, "windup": 0.88, "damage": 1.1, "special": 0.8},
}
const DIFFICULTY_NAMES := {"easy": "쉬움", "normal": "보통", "hard": "어려움"}
var difficulty := "normal"
var _windup_scale := 1.0
var _damage_scale := 1.0
var _special_chance := 0.55
## 튜토리얼 연습 상대: 혼자 판단하지 않고, 다가와 서서 천천히 한 방씩만 휘두른다.
## 막거나 피하지 않고, 속임수도 안 쓰고, 쓰러지지도 않는다 (scripts/tutorial.gd 가 조종).
var tutor := false
var tutor_attacks := false      # 지금 공격할 차례인가 (튜토리얼 단계가 정함)
var tutor_dirs: Array = AttackDir.ALL   # 고를 공격 방향
var tutor_gap := 1.5            # 한 번 휘두른 뒤 다음까지 쉬는 시간
const TUTOR_SLOW := 1.7         # 준비 동작을 이만큼 느리게 (보고 반응할 시간)
var _tutor_cd := 1.0
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
## 들고 있는 무기 (Weapons.WEAPONS). 빌드에서 정해진다.
var weapon := "sword"
## 필살기 게이지. 다 차면 좋은 때를 골라 필살기를 쓴다.
var gauge := 0.0
var ammo := 0                     # 들고 있는 수리검 수 (던지는 무기만)
var ammo_max := 0
var _ammo_t := 0.0
signal gauge_changed(value: float, max_value: float)

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
var _flying := false           # 바람 발판에 날려 가는 중 (궤적을 그대로 따른다)
var _fly_grace := 0.0
var _stuck_pos := Vector3.ZERO
var _ray := PhysicsRayQueryParameters3D.new()
var _dj_pending := false        # 점프 꼭대기에서 이중 점프
var _grap_point := Vector3.ZERO
var _grap_on_target := false
var _rope: MeshInstance3D

var rig: BodyRig
var _step_dist := 0.0
var _was_on_floor := true
var _fall_v := 0.0


func _ready() -> void:
	if build == null:
		build = CharacterBuild.preset("검객")
	add_to_group("grabbable")
	max_hp = build.max_hp()
	hp = max_hp
	max_stamina = build.max_stamina()
	stamina = max_stamina
	traits = {"wall_climb": build.has("wall")}
	weapon = Weapons.valid(build.weapon)
	ammo_max = Weapons.ammo_max(weapon)
	ammo = ammo_max
	skills = SkillKit.new(self, build)
	vkit = VerticalKit.new(self)
	# 기술 능력치가 높을수록 상대 공격 방향을 잘 읽는다
	read_skill = clampf(0.45 + 0.05 * (float(build.stats.tec) - 5.0), 0.25, 0.8)
	_apply_difficulty()
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
	rig.weapon = weapon
	rig.build = build
	add_child(rig)
	# 휘두를 때 남는 빛 자취 (검기): 경기장에 남는다 (scripts/combat/swing_trail.gd)
	_trail = SwingTrail.attach(null, self, rig.blade_tip, _trail_base(rig.blade_tip), weapon)
	if rig.blade_tip_l != null:
		_trail_l = SwingTrail.attach(null, self, rig.blade_tip_l, _trail_base(rig.blade_tip_l), weapon)
	if weapon == "fists" and rig.foot_tip != null:
		_trail_leg = SwingTrail.attach(null, self, rig.foot_tip, rig.foot_base, weapon)
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


## 효과음: 상대가 있는 자리에서 난다 (왼쪽에 있으면 왼쪽에서 들림)
func _play(snd: String, volume: float = 0.0) -> void:
	Audio.play(snd, global_position + Vector3.UP * 1.2, volume)


func _wsnd(kind: String, w: String = "") -> String:
	return Audio.weapon_sound(kind, w if w != "" else weapon)


## 발소리와 착지 소리
func _footsteps(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		if _fall_v < -11.0:
			_play("land_hard")
		elif _fall_v < -3.0:
			_play("land")
		_step_dist = 0.0
	_was_on_floor = on_floor
	if not on_floor or state in ["dash", "stagger", "dead"]:
		return
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed < 1.0:
		return
	_step_dist += hspeed * delta
	if _step_dist >= (2.1 if hspeed > 6.5 else 1.6):
		_step_dist = 0.0
		Audio.step(global_position, 2.0)


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
			_play("double_jump")
	skills.tick(delta)
	_regen(delta)
	_ammo_tick(delta)
	if active and not dead:
		add_gauge(Weapons.GAUGE.regen * delta)
	_alert = maxf(_alert - delta, 0.0)
	_move_cd -= delta
	if state == "idle":
		_tutor_cd -= delta
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
	_fly_grace = maxf(_fly_grace - delta, 0.0)
	if _flying and is_on_floor() and _fly_grace <= 0.0:
		_flying = false
	var mv := _move + _push
	if not _flying:
		velocity.x = lerpf(velocity.x, mv.x, clampf(delta * 12.0, 0, 1))
		velocity.z = lerpf(velocity.z, mv.z, clampf(delta * 12.0, 0, 1))
	var pre_speed := Vector2(velocity.x, velocity.z).length()
	_fall_v = velocity.y
	move_and_slide()
	_footsteps(delta)
	_vertical_tick(delta)
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
	return MOVE_SPEED * build.speed_mult() * skills.speed_mult() * Weapons.stat(weapon, "speed")


## 내 무기에 맞춘 동작 값 (Weapons.move)
func _mv(move_name: String) -> Dictionary:
	return Weapons.move(weapon, move_name)


## 무기 버릇 (Weapons.WEAPONS[무기].ai)
func _style(key: String) -> float:
	return Weapons.ai(weapon, key)


func _atk_mult() -> float:
	return build.attack_time_mult() * skills.attack_mult() * _windup_scale


## 난이도 표(DIFFICULTY)대로 성격 수치를 바꾼다
func _apply_difficulty() -> void:
	if tutor or not DIFFICULTY.has(difficulty):
		return
	var d: Dictionary = DIFFICULTY[difficulty]
	for k in d:
		match k:
			"read":
				read_skill = clampf(read_skill + float(d.read), 0.15, 0.9)
			"windup":
				_windup_scale = float(d.windup)
			"damage":
				_damage_scale = float(d.damage)
			"special":
				_special_chance = float(d.special)
			_:
				set(k, d[k])


func _process(delta: float) -> void:
	rig.animate(delta, global_transform.basis.inverse() * Vector3(velocity.x, 0, velocity.z))
	_update_rope()
	_update_trails()


var _trail: SwingTrail
var _trail_l: SwingTrail
var _trail_leg: SwingTrail


## 빛 자취의 손잡이 쪽 점. 맨몸은 주먹 위아래로 폭을 준다.
func _trail_base(tip: Node3D) -> Node3D:
	if weapon != "fists":
		return SwingTrail.make_base(tip, weapon)
	var b := Node3D.new()
	b.position = tip.position + Vector3(0, 0.09, 0)
	tip.get_parent().add_child(b)
	return b


## 휘두르는 동안(맞히는 구간)만 자취를 남긴다. 던지기와 잡기는 자취 없이.
func _update_trails() -> void:
	var swinging := false
	var hand := ""
	var limb := ""
	if sm.state == "strike" and _attack != "grab":
		var data := _mv(_attack)
		swinging = not data.has("projectile")
		hand = str(data.get("hand", ""))
		limb = str(data.get("limb", ""))
	elif sm.state == "plunge":
		swinging = true
	var kicking := swinging and limb.begins_with("kick")
	var arms := swinging and not kicking
	_trail.emitting = arms and (weapon != "fists" or hand != "l")
	_trail.boost = _attack == "special"
	if _trail_l != null:
		_trail_l.emitting = arms and (weapon != "fists" or hand != "r")
		_trail_l.boost = _trail.boost
	if _trail_leg != null:
		_trail_leg.emitting = kicking


# ---------------- 판단 ----------------

func _think() -> void:
	_think_t = randf_range(0.18, 0.35)
	if tutor:
		_tutor_think()
		return
	if _think_vertical():
		return
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
	if _try_special():
		return
	if target.blocking and _dist < 3.4 and randf() < (grab_chance + mind.grab_urge() * 0.6) * minf(_style("grab"), 1.6):
		if _dist < float(_mv("grab").reach) + 0.2:
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
	# 수리검: 멀리 있으면 던진다 (들고 있는 만큼). 가끔 세 장 부채꼴
	if Weapons.get_weapon(weapon).ai.has("throw") and (ammo > 0 or ammo_max <= 0) and _dist > 3.2 and _dist < 16.0 \
			and absf(_dy) < 2.5 and randf() < 0.55 * _style("throw") and _clear_line_to_target():
		_combo_left = 0
		_start_attack("heavy" if randf() < 0.75 else "charge")
		return
	if _think_movement():
		return
	if _chase_ranged():
		return
	var r := randf()
	# 거리가 좀 벌어졌으면 가끔 차지 베기로 돌진
	if _dist > 2.6 and _dist < 4.6 and randf() < charge_chance * (1.0 if r < aggression else 0.3):
		_start_attack("charge")
		return
	if _dist > 3.2 * _style("range"):
		sm.go("approach")
		return
	if r < aggression:
		if randf() < 0.15 * _style("heavy"):
			_start_attack("heavy")
			_combo_left = 0
		else:
			# 방향은 상대가 덜 막는 쪽, 지금 막고 있는 쪽은 피해서
			var dir := mind.choose_dir(target.guard_dir if target.blocking else "")
			# 무기 버릇: 창은 찌르기, 대검은 내려베기를 즐겨 쓴다 (막는 방향은 피해서)
			var guard_now := target.guard_dir if target.blocking else ""
			if guard_now != AttackDir.MID and randf() < (_style("thrust") - 1.0) * 0.3:
				dir = AttackDir.MID
			elif guard_now != AttackDir.HIGH and randf() < (_style("overhead") - 1.0) * 0.3:
				dir = AttackDir.HIGH
			_combo_left = 0
			if randf() < combo_chance * (1.0 if dir == AttackDir.SIDE else 0.7):
				# 연속기: 몇 번 이어 갈지 미리 정한다 (1~3번 더). 갈래는 이을 때마다 고른다
				var rr := randf()
				_combo_left = 1 if rr < 0.5 else (2 if rr < 0.85 else 3)
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


## 튜토리얼 상대: 적당한 거리로 다가와 서 있다가, 차례가 되면 한 방 휘두른다
func _tutor_think() -> void:
	_think_t = 0.15
	if _dist > 2.6 or not _direct:
		sm.go("approach")
		return
	sm.go("idle")
	if tutor_attacks and _tutor_cd <= 0.0 and target.sm.state not in ["special", "stagger"]:
		_combo_left = 0
		_start_attack(_move_for_dir(tutor_dirs.pick_random()))


## 상대가 수리검을 들고 멀리 있다: 달려가 붙고, 가끔 앞으로 대시해 거리를 확 좁힌다
func _chase_ranged() -> bool:
	if target.ammo_max <= 0 or _dist < 5.0:
		return false
	if stamina > 45.0 and is_on_floor() and randf() < 0.3:
		_dash_dir(1.0, 0.35)
		return true
	sm.go("approach")
	_think_t = 0.15
	return true


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
	if not active or dead or tutor:
		return
	var dir: String = Weapons.move(target.weapon, kind).get("dir", "") if (MoveSet.MOVES.has(kind) or kind == "special") else ""
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
	# 막기를 깨는 공격, 필살기, 잔매에 끊기지 않는 대검은 막기보다 피하는 편이 낫다
	var big := kind in ["heavy", "charge", "special"] or (Weapons.has_armor(target.weapon) and kind != "grab")
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
	if tutor:
		return
	mind.saw_feint()
	stats["saw_feint"] = stats.get("saw_feint", 0) + 1
	# 속임수에 막기만 하고 서 있으면 잡힌다: 가끔 바로 막기를 풀고 반격
	if state == "block" and _dist < 2.6 and randf() < 0.4 + mind.feint_rate:
		_combo_left = 0
		_start_attack("thrust")


## 플레이어가 힘을 모으기 시작했을 때: 파고들어 끊거나, 물러난다
func on_target_charge() -> void:
	if tutor or not _can_react() or state == "recover":
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
	if tutor:
		_tutor_cd = tutor_gap
	sm.go("circle" if randf() < 0.5 else "approach")
	_strafe_dir = -1.0 if randf() < 0.5 else 1.0
	_think_t = randf_range(0.05, 0.25)
	rig.set_pose(MoveSet.BODY_POSES.guard, 10.0)
	rig.glow(rig.blade_mat.emission, 0.0)
	rig.tremble = 0.0
	rig.reach = 0.0
	rig.leg_kick = 0.0
	# 경직이 풀렸는데 상대가 이미 휘두르고 있으면: 바로 방향을 읽고 막는다 (연타에 갇히지 않게)
	if active and not tutor and target and target.attack_threat() and _dist < 3.2 \
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
	if _needs_nav():
		_move = _nav_move(delta)
		return
	_path.clear()
	if tutor and state == "idle":
		# 튜토리얼 상대: 제자리에서 거리만 맞춘다 (빙빙 돌지 않는다)
		_move = _dir * clampf((_dist - 2.2) * 1.5, -1.5, 1.5)
		_move = _edge_guard(_move)
		return
	var side := Vector3(-_dir.z, 0, _dir.x)
	if _grab_wait > 0.0:
		# 잡으려고 바짝 붙는다
		_grab_wait -= delta
		_move = _dir * _speed() * 1.2
		if _dist < float(_mv("grab").reach) and target.blocking:
			_grab_wait = 0.0
			_start_attack("grab")
		return
	if state == "approach":
		# 멀면 달려간다 (도망치는 상대를 걸어서는 못 따라잡는다)
		var spd := _speed() if _dist < 5.5 else maxf(_speed(), RUN_SPEED * build.speed_mult())
		_move = _dir * spd if _dist > 2.0 * _style("range") else Vector3.ZERO
	else:
		var keep := (_dist - 2.6 * _style("range")) * 1.5
		if stamina < 22.0:
			keep = (_dist - 4.0) * 1.5   # 숨 고르는 중엔 멀찍이
		_move = side * _strafe_dir * STRAFE_SPEED * build.speed_mult() + _dir * keep
	_move = _edge_guard(_move)


func _start_attack(kind: String) -> void:
	if _mv(kind).has("projectile") and ammo_max > 0 and ammo <= 0:
		kind = "slash1"   # 수리검이 떨어졌다: 손에 쥔 칼날로 벤다
	if stamina < float(_mv(kind).cost) * 0.5:
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
	return _mv(_attack).get("dir", "")


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
	var data: Dictionary = _mv(_attack)
	if _attack == "special" and data.effect == "quake" and is_on_floor():
		velocity.y = 5.0   # 뛰어올랐다 내리찍는다
	spend_stamina(float(data.cost))
	# 자꾸 피하면 일부러 한 박자 늦게 휘두르기도 한다
	_windup_len = data.ai_windup * _atk_mult() + randf() * 0.12 * mini(_dodged_by_target, 3)
	if tutor:
		_windup_len = data.ai_windup * _atk_mult() * TUTOR_SLOW
	rig.set_pose(data.body.windup, 2.5 / (data.ai_windup * _atk_mult()), str(data.get("hand", "")))
	_kick_pose(data, 0.5)
	var col := Color(1.0, 0.55, 0.1)
	if data.warn == "heavy":
		col = Color(1.0, 0.15, 0.1)
	if _attack == "special":
		col = Color(1.0, 0.8, 0.15)   # 금빛 = 필살기: 막기보다 피하라
		combat_event.emit("상대 필살기: %s!" % data.name, Color(1.0, 0.8, 0.3))
	if _attack == "counter":
		col = Color(0.4, 0.8, 1.0)
	if _attack == "grab":
		col = Color(0.8, 0.35, 1.0)   # 보랏빛 = 잡기: 막지 말고 때리거나 피하라
		rig.reach = 1.0
	rig.glow(col, 0.0)
	if _attack == "special":
		_play("warn_special")
	elif _attack == "grab":
		_play("warn_grab")
	else:
		_play("warn_heavy" if data.warn == "heavy" else "warn_light")


func _windup_update(_delta: float) -> void:
	var data: Dictionary = _mv(_attack)
	_turn_speed = WINDUP_TURN_SPEED
	var k := clampf(_state_t / (_windup_len if tutor else data.ai_windup * _atk_mult()), 0.0, 1.0)
	rig.glow(rig.blade_mat.emission, k * k * 3.5)
	if _attack == "charge":
		# 힘을 모으며 천천히 다가온다
		rig.tremble = k
		_move = _dir * 1.4 if _dist > 2.2 else Vector3.ZERO
	elif _attack in ["run_thrust", "sweep"] and is_on_floor():
		# 달려들며 찌르기 / 미끄러져 들어오며 다리 베기
		_move = _dir * (RUN_SPEED if _attack == "run_thrust" else SLIDE_SPEED) if _dist > 1.6 else _dir * 2.0
		rig.low = 1.0 if _attack == "sweep" else 0.0
	elif _attack == "air_slash" and not is_on_floor():
		_move = _dir * 5.0 if _dist > 1.4 else Vector3.ZERO
	else:
		_move = _dir * 0.6 if _dist > 1.6 else Vector3.ZERO
	# 속임수: 준비가 반쯤 됐을 때 한 번 정한다
	if not _feint_checked and not tutor and _state_t >= _windup_len * 0.45:
		_feint_checked = true
		if _try_feint():
			return
	if _state_t >= _windup_len:
		sm.go("strike")


## 상대가 내 공격 방향에 맞춰 막고 있으면: 방향을 바꾸거나, 잡기로 바꾸거나, 멈춘다.
## 잘 막는 상대일수록 자주 쓴다. 바꾼 뒤에도 보고 막을 시간은 남겨 둔다.
func _try_feint() -> bool:
	if _attack in ["counter", "grab", "special"]:
		return false
	var chance := feint_chance * (0.4 + mind.feint_urge())
	var reading := target.blocking and AttackDir.blocks(target.guard_dir, attack_dir())
	if reading:
		chance += 0.25
	if randf() >= chance:
		return false
	stats["feint"] = stats.get("feint", 0) + 1
	var r := randf()
	if target.blocking and _dist < float(_mv("grab").reach) + 0.6 and r < 0.5:
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
		var data: Dictionary = _mv(_attack)
		_windup_len = maxf(data.ai_windup * _atk_mult() * 0.75, 0.32)
		sm.time = 0.0
		rig.set_pose(data.body.windup, 3.0 / _windup_len, str(data.get("hand", "")))
		_kick_pose(data, 0.5)
		_play("feint")
		_play("warn_light", -2.0)
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
	var data: Dictionary = _mv(_attack)
	if float(data.get("hop", 0.0)) > 0.0 and is_on_floor():
		velocity.y = float(data.hop) * 0.8
	_strike_i = 0
	_strike_extra = {}
	if _attack == "special":
		_special_strike(data)
	rig.set_pose(data.body.strike, 30.0, str(data.get("hand", "")))
	_kick_pose(data, 1.0)
	rig.tremble = 0.0
	if _attack == "special":
		_play("sp_" + str(data.effect))
	elif _attack == "grab":
		_play("grab_whoosh")
	elif data.has("projectile"):
		_play("shuriken_throw")
	else:
		_play(_wsnd("swing_heavy" if _attack in ["heavy", "charge", "slash3", "spin", "cleave", "pierce"] else "swing"))
	if data.has("projectile"):
		# 수리검 던지기: 휘두르지 않고 날려 보낸다
		_hit_done = true
		var pr: Dictionary = data.projectile
		var n := use_ammo(int(pr.count))
		_throw_projectiles(data, n, float(pr.spread) * float(n) / float(maxi(int(pr.count), 1)), float(pr.speed), float(pr.get("homing", 0.0)), -1, ammo_max > 0)


func _strike_update(_delta: float) -> void:
	var data: Dictionary = _mv(_attack)
	_turn_speed = 0.5
	_move = -global_transform.basis.z * float(data.lunge) if _dist > 1.3 else Vector3.ZERO
	if _attack in ["run_thrust", "sweep"] and _dist > 1.3:
		_move = -global_transform.basis.z * (RUN_SPEED if _attack == "run_thrust" else SLIDE_SPEED) * 0.7
	if _attack == "special" and data.effect in ["rush", "takedown"] and not _hit_done:
		_move = -global_transform.basis.z * float(data.rush_speed)
		_turn_speed = 1.5
	if _attack == "special" and data.effect in ["flurry", "storm"]:
		_special_multi(data)
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
	rig.low = 0.0
	rig.leg_kick = 0.0


func _recover_update(delta: float) -> void:
	var data: Dictionary = _mv(_attack)
	_turn_speed = 3.0
	rig.glow(rig.blade_mat.emission, move_toward(rig.glow_energy(), 0.0, delta * 10.0))
	var nxt := ""
	if _combo_left > 0:
		# 연속기 갈래: 상대가 막고 있는 방향은 피해서 고른다 (MoveSet.combo_next)
		var guard_now := target.guard_dir if target.blocking else ""
		nxt = MoveSet.combo_next(data, mind.choose_dir(guard_now))
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
	if stamina < DASH_COST * build.dash_cost_mult() * 0.5:
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
		spend_stamina(DASH_COST * build.dash_cost_mult())
	_counter_ready = false
	rig.set_pose(MoveSet.BODY_POSES.guard, 12.0)
	rig.dash_pulse(global_transform.basis.inverse() * v)
	rig.glow(rig.blade_mat.emission, 0.0)
	rig.tremble = 0.0
	_play("dash")


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
	rig.low = 0.0
	_combo_left = 0
	_grab_wait = 0.0
	rig.reach = 0.0
	rig.leg_kick = 0.0
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
	if _flying:
		_repath_t = maxf(_repath_t, 0.3)   # 바람 발판으로 날아가는 중에도
		_stuck_t = 0.0
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
	_play("climb")


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
	if facing.normalized().dot(_dir) < (HIT_ANGLE if data.get("effect", "") != "whirl" else -1.0):
		return
	_hit_done = true
	var info := {
		"move": _attack, "damage": int(round(float(data.damage) * float(data.get("hits", 1)) * build.damage_mult() * vkit.damage_mult() * _damage_scale)) + randi_range(-2, 2),
		"power": vkit.powered(),
		"react": data.react, "guard": data.get("ai_guard", data.guard),
		"pressure": build.guard_pressure() * Weapons.stat(weapon, "pressure"),
		"push_add": data.get("push_add", 0.0), "push": data.get("push", 0.0), "lift": data.get("lift", 2.0),
		"dir": data.get("dir", ""), "knockdown": data.get("knockdown", false),
	}
	info.merge(_strike_extra, true)
	var result := target.receive_attack(info, self)
	if result in ["hit", "guard_broken", "wrong_guard"] and _attack != "special":
		add_gauge(info.damage * Weapons.GAUGE.dealt)
	mind.my_attack_result(info.dir, result)
	stats["res_" + result] = stats.get("res_" + result, 0) + 1
	match result:
		"parried":
			# 맨몸 격투(호신술)에 튕겨나면 더 오래 굳는다
			_stagger(0.75 * Weapons.stat_or(target.weapon, "parry_stun", 1.0))
			combat_event.emit("반격 기회!", Color(0.55, 0.85, 1.0))
		"blocked":
			# 완벽 막기를 당했다: 칼이 튕겨 잠깐 휘청한다
			_push = -_dir * float(MoveSet.REACTIONS.recoil.push) * 2.0
			_combo_left = 0
			if _attack != "special":
				_stagger(MoveSet.REACTIONS.recoil.time, false)
		"dodged":
			_dodged_by_target += 1
		"guard_broken", "hit", "wrong_guard":
			Fx.impact(get_parent(), target.global_position + Vector3(0, 1.3, 0), _dir + Vector3.UP * 0.3,
					Color(0.75, 0.1, 0.08), 14)
			# 맞는 순간 멈춤: 맞는 쪽도 '쿵' 느끼게 (때릴 때보다 조금 짧게)
			Fx.hitstop(self, Weapons.hitstop_time(weapon, str(info.react) == "stagger" or _attack == "special") * 0.8)


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
	var info := {"damage": int(round(float(data.damage) * build.damage_mult() * _damage_scale)), "react": "thrown",
			"throw": _throw_dir() * float(data.throw_speed) + Vector3.UP * float(data.throw_up)}
	var result := target.take_grab(info, self)
	stats["grab_" + result] = stats.get("grab_" + result, 0) + 1
	match result:
		"thrown":
			_play("throw")
			combat_event.emit("상대가 잡아 던졌다!", Color(1.0, 0.45, 0.8))
		"beaten", "blocked":
			_stagger(MoveSet.REACTIONS.grab_fail.time)
			_push = -_dir * float(MoveSet.REACTIONS.grab_fail.push)
		"clash":
			_play("grab_clash")
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
	_apply_damage(int(info.damage), dir, true, "grab")
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
	_apply_damage(dmg, -n, true, "wall_slam")
	if not dead:
		_stagger(MoveSet.REACTIONS.stagger.time)


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
		_play(_wsnd("clash"))
		combat_event.emit("상대 철벽!", Color(1.0, 0.85, 0.4))
		_push = dir * 1.5
		return "blocked"
	var facing := -global_transform.basis.z
	facing.y = 0
	var facing_attacker := facing.normalized().dot(-dir) > 0.2
	if state == "block" and facing_attacker and info.guard != "unblockable" \
			and not AttackDir.blocks(guard_dir, info.get("dir", "")):
		# 막는 방향이 틀렸다: 반만 막는다 (피해 절반, 큰 공격이면 살짝 움찔)
		stats["wrong_guard"] = stats.get("wrong_guard", 0) + 1
		spend_stamina(float(BLOCK_COST.get(info.react, 12.0)) * float(info.get("pressure", 1.0)) * Weapons.stat(weapon, "block_cost"))
		if info.guard == "break" or stamina <= 0.0:
			_play("guard_break")
			combat_event.emit("가드 깨기!", Color(1.0, 0.75, 0.3))
			_apply_damage(damage / 2, dir, true)
			if not dead:
				_stagger(MoveSet.REACTIONS.guard_break.time)
			return "hit"
		_play(_wsnd("clash"), -4.0)
		_push = dir * (3.0 if big else 1.5)
		_apply_damage(int(ceilf(damage * HALF_BLOCK)), dir, false)
		if not dead and big:
			_stagger(MoveSet.REACTIONS.flinch.time, false)
		elif not dead:
			sm.time = 0.0   # 계속 막고 있는다
		return "wrong_guard"
	if state == "block" and facing_attacker and info.guard != "unblockable":
		var parry := parry_chance * (1.0 + 0.12 * (float(build.stats.tec) - 5.0)) * Weapons.stat(weapon, "parry")
		if _state_t < 0.3 and randf() < parry:
			_play("parry")
			add_gauge(Weapons.GAUGE.parry)
			if info.get("projectile", false):
				return "parried"   # 날아온 수리검: 쳐내기만 한다
			# 튕겨낸 뒤 바로 반격
			_combo_left = 0
			_start_attack("slash1")
			sm.time = _mv("slash1").ai_windup * 0.45
			return "parried"
		if info.guard == "break":
			# 막기를 깨는 공격
			_play("guard_break")
			combat_event.emit("가드 깨기!", Color(1.0, 0.75, 0.3))
			_apply_damage(damage / 2, dir, true)
			if not dead:
				_stagger(MoveSet.REACTIONS.guard_break.time)
			return "hit"
		_play(_wsnd("clash"))
		_push = dir * (4.0 if big else 2.0)
		spend_stamina(float(BLOCK_COST.get(info.react, 12.0)) * float(info.get("pressure", 1.0)) * Weapons.stat(weapon, "block_cost"))
		add_gauge(Weapons.GAUGE.block)
		if stamina <= 0.0:
			# 기력이 바닥나 막기가 깨졌다
			combat_event.emit("가드 깨기!", Color(1.0, 0.75, 0.3))
			_apply_damage(damage / 2, dir, true)
			if not dead:
				_stagger(MoveSet.REACTIONS.guard_break.time)
			return "hit"
		if randf() < counter_chance and not info.get("projectile", false):
			# 막아낸 뒤 상대가 튕겨난 틈에 바로 반격
			_combo_left = 0
			_start_attack("slash1")
			sm.time = _mv("slash1").ai_windup * 0.35
		else:
			sm.time = 0.0   # 계속 막고 있는다
		return "blocked"

	if _attack == "special" and state in ["windup", "strike"]:
		# 필살기를 쓰는 동안은 맞아도 멈추지 않는다 (피해는 받는다)
		_apply_damage(damage, dir, false)
		return "hit"
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
		elif state in ["windup", "strike"] and Weapons.has_armor(weapon) and _attack != "grab":
			pass   # 대검: 휘두르는 중엔 잔매에 끊기지 않는다
		elif state == "windup" and _attack in ["heavy", "charge", "slash3"]:
			pass   # 큰 공격을 준비 중이면 가벼운 공격엔 버티고 그대로 휘두른다 (맞교환)
		elif state == "windup" and randf() < 0.5:
			pass
		else:
			_stagger(MoveSet.REACTIONS.flinch.time, false)
	return "hit"


func _apply_damage(damage: int, dir: Vector3, big: bool, sound := "") -> void:
	hp = max(hp - damage, 1 if tutor else 0)   # 튜토리얼 상대는 쓰러지지 않는다
	add_gauge(damage * Weapons.GAUGE.taken)
	hp_changed.emit(hp, max_hp)
	_alert = 2.0
	var r: Dictionary = MoveSet.REACTIONS["stagger" if big else "flinch"]
	_push = dir * float(r.push)
	rig.hit_kick(global_transform.basis.inverse() * dir, float(r.kick))
	if sound == "":
		_play(_wsnd("hit", str(target.weapon) if target else ""))
		if big:
			_play("hit_big", -4.0)
	elif sound != "none":
		_play(sound)
	Fx.impact(get_parent(), global_position + Vector3(0, 1.3, 0) - dir * 0.3, -dir + Vector3.UP * 0.4,
			Color(0.75, 0.1, 0.08), 22 if big else 12)
	_spawn_number(damage, big)
	if hp <= 0:
		_die(dir)


func _die(dir: Vector3) -> void:
	Audio.loop_stop("zip_ai_%d" % get_instance_id())
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
	_play("blink")
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
	_play("grapple")


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
	# 높은 곳에서 아래 상대에게 낙하 찍기. 이미 내려가려고 길을 찾는 중(approach)이면 망설이지 않고 뛰어내린다
	# (빙 돌아 계단으로 내려가는 것보다 박진감 있고, 주사위가 몇 번 빗나가 그냥 걸어 내려가는 일이 없다)
	var plunge_cost: float = _mv("plunge").cost
	if _dy < -1.8 and _dy > -9.0 and _dist < 6.5 and is_on_floor() and stamina > plunge_cost \
			and (state == "approach" or randf() < 0.6) and _clear_line_to_target():
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
	# 돌기둥 너머에 상대가 서 있으면: 기둥을 쳐서 상대 쪽으로 쓰러뜨린다 (금이 많이 갔을수록 자주)
	if _direct and stamina > 25.0:
		for v in arena.breakables.values():
			var bp := v as BreakablePillar
			if bp == null or bp.is_broken():
				continue
			var to_b := bp.global_position - global_position
			to_b.y = 0
			if to_b.length() > 2.6 or not bp.would_crush(global_position, target):
				continue
			if randf() < (0.75 if bp.hp <= 2 else 0.3):
				_smash = bp
				_face = to_b.normalized()
				_combo_left = 0
				_start_attack("heavy" if bp.hp <= 2 else "slash1")
				stats["pillar_drop"] = stats.get("pillar_drop", 0) + 1
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
	spend_stamina(float(_mv("plunge").cost))
	sm.go("plunge")


func _plunge_enter(_d: Dictionary) -> void:
	_plunge_landed = false
	_plunge_from = global_position.y
	_combo_left = 0
	rig.set_pose(_mv("plunge").body.windup, 10.0)
	rig.glow(Color(1.0, 0.15, 0.1), 3.0)
	_play("warn_heavy")
	_play("jump")
	combat_event.emit("위에서 내려온다!", Color(1.0, 0.45, 0.3))


func _plunge_update(_delta: float) -> void:
	var data: Dictionary = _mv("plunge")
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
	var data: Dictionary = _mv("plunge")
	_plunge_landed = true
	sm.time = 0.0
	velocity = Vector3.ZERO
	_move = Vector3.ZERO
	_leap_v = Vector3.ZERO
	_play("plunge_impact")
	Fx.impact(get_parent(), global_position + Vector3.UP * 0.1, Vector3.UP, Color(0.82, 0.74, 0.6), 26)
	rig.glow(rig.blade_mat.emission, 0.0)
	var drop := maxf(_plunge_from - global_position.y, 0.0) + 1.0
	var dmg := int(lerpf(float(data.damage), float(data.damage_max), clampf((drop - 1.6) / 6.0, 0.0, 1.0)))
	var to_t := target.global_position - global_position
	var dy := to_t.y
	to_t.y = 0
	if to_t.length() <= float(data.reach) and absf(dy) < 1.5:
		var info := {"move": "plunge", "damage": int(round(dmg * build.damage_mult() * vkit.damage_mult() * _damage_scale)),
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
	if _flying:
		return false
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
	_play("hang")
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
	_play("zip_attach")
	Audio.loop_start("zip_ai_%d" % get_instance_id(), "zip_loop", self, -3.0)


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
	if below > 2.0 and _dist < 3.0 and stamina > float(_mv("plunge").cost) * 0.5:
		_zip_leave(Vector3.ZERO)
		_leap_v = _dir * 2.0
		_attack = "plunge"
		stats["move_plunge"] = stats.get("move_plunge", 0) + 1
		spend_stamina(float(_mv("plunge").cost))
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
	Audio.loop_stop("zip_ai_%d" % get_instance_id())
	_play("zip_release")
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
		"launch":
			# 바람 발판: 발판 한가운데로 걸어 올라가면 발판이 날려 보낸다
			if _flying:
				return Vector3.ZERO
			var pad: LaunchPad = arena.pads[wp.ref]
			var to_pad := pad.global_position - global_position
			to_pad.y = 0
			_stuck_t = 0.0
			if to_pad.length() > 6.0:
				_repath_t = 0.0   # 발판에서 멀어졌다 (밀려났다 등): 길을 다시 찾는다
			_face = to_pad.normalized() if to_pad.length() > 0.1 else _face
			return to_pad.normalized() * _speed() if to_pad.length() > 0.1 else Vector3.ZERO
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
		_apply_damage(f, Vector3.ZERO, true, "land_hard")
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
		_apply_damage(dmg, Vector3.ZERO, true, "fall_void")
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
	_play("pickup_get", -3.0)
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


# ---------------- 필살기 ----------------
# 게이지가 다 차면, 그 무기 필살기가 잘 맞을 거리에서 쓴다. 수치는 Weapons.WEAPONS[무기].special.
# 준비 동작은 금빛으로 빛난다 → 플레이어는 막지 말고 대시로 피해야 한다.

func add_gauge(amount: float) -> void:
	if amount <= 0.0 or dead or (_attack == "special" and state in ["windup", "strike"]):
		return
	var before := gauge
	gauge = minf(gauge + amount, Weapons.GAUGE_MAX)
	if gauge != before:
		gauge_changed.emit(gauge, Weapons.GAUGE_MAX)


func _try_special() -> bool:
	if gauge < Weapons.GAUGE_MAX or target.sm.state == "iron" or randf() > _special_chance:
		return false
	var sp := _mv("special")
	var ok := false
	match str(sp.effect):
		"whirl":
			ok = _dist < float(sp.reach) - 0.4
		"quake":
			ok = _dist < float(sp.reach) - 0.8
		"shadow":
			ok = _dist > 1.8 and _dist < float(sp.jump)
		"rush":
			ok = _dist > 2.5 and _dist < float(sp.rush_speed) * float(sp.active) + 1.5
		"takedown":
			ok = _dist > 1.4 and _dist < float(sp.rush_speed) * float(sp.active) + 1.0
		"flurry":
			ok = _dist < float(sp.reach) - 0.3
		"storm":
			ok = _dist > 2.0 and _dist < float(sp.reach) and _clear_line_to_target()
	if not ok or absf(_dy) > 1.2:
		return false
	gauge = 0.0
	gauge_changed.emit(gauge, Weapons.GAUGE_MAX)
	stats["special"] = stats.get("special", 0) + 1
	_combo_left = 0
	_start_attack("special")
	return true


func _special_strike(data: Dictionary) -> void:
	match str(data.effect):
		"storm":
			_hit_done = true
		"takedown":
			rig.reach = 1.0
		"shadow":
			# 상대 등 뒤로 순간이동
			Fx.sparks(get_parent(), global_position + Vector3.UP, Vector3.UP, 18, Color(0.5, 0.35, 0.9))
			var back := target.global_transform.basis.z
			back.y = 0
			back = back.normalized()
			var spot := target.global_position + back * 1.3
			for side in [back, back.rotated(Vector3.UP, 1.2), back.rotated(Vector3.UP, -1.2)]:
				_ray.from = target.global_position + Vector3.UP
				_ray.to = _ray.from + side * 1.6
				_ray.exclude = [get_rid(), target.get_rid()]
				if get_world_3d().direct_space_state.intersect_ray(_ray).is_empty():
					spot = target.global_position + side * 1.3
					break
			global_position = Vector3(spot.x, target.global_position.y + 0.05, spot.z)
			var look := target.global_position - global_position
			look.y = 0
			rotation.y = atan2(-look.x, -look.z)
			_dir = look.normalized()
			_dist = look.length()
			_iframes = 0.2
			Fx.sparks(get_parent(), global_position + Vector3.UP, Vector3.UP, 18, Color(0.5, 0.35, 0.9))
		"quake":
			velocity.y = minf(velocity.y, -10.0)
			for i in 10:
				var a := TAU * float(i) / 10.0
				Fx.sparks(get_parent(), global_position - global_transform.basis.z * 1.6 + Vector3(cos(a), 0.1, sin(a)) * 1.4,
						Vector3(cos(a), 0.6, sin(a)), 8, Color(1.0, 0.75, 0.35))



# ---------------- 자유로운 움직임: 달려들기, 미끄러지기, 뛰어 베기, 기둥 쓰러뜨리기 ----------------
# 플레이어와 같은 동작 표(MoveSet: run_thrust, sweep, air_slash)를 쓴다.

var _move_cd := 0.0


## 거리와 주변을 보고 움직이며 쓰는 기술을 고른다. 골랐으면 true
func _think_movement() -> bool:
	if not is_on_floor() or _move_cd > 0.0:
		return false
	if stamina < 35.0 or target.sm.state == "iron":
		return false
	var r := randf() * (1.2 - aggression * 0.4)
	# 좀 떨어져 있으면: 달려들며 찌르기, 또는 미끄러져 다리 베기
	if _dist > 3.3 and _dist < 6.5:
		if r < 0.16:
			_move_cd = 2.5
			_combo_left = 0
			_start_attack("run_thrust")
			return true
		if r < 0.26 and not target.is_sliding():
			_move_cd = 3.0
			_combo_left = 0
			_start_attack("sweep")
			return true
	# 조금 더 가까우면 뛰어올라 공중 베기
	if _dist > 2.8 and _dist < 4.4 and r < 0.1 and absf(_dy) < 0.6:
		_move_cd = 3.0
		_combo_left = 0
		velocity.y = 5.4
		_push = _dir * 5.0
		_play("jump")
		_start_attack("air_slash")
		return true
	return false


## 바람 발판에 날려 간다 (LaunchPad 가 부른다)
func launch(vel: Vector3) -> void:
	if state in ["climb", "hang", "zip", "dash", "block"]:
		_back_to_neutral()
	velocity = vel
	_push = Vector3.ZERO
	_flying = true
	_fly_grace = 0.2
	vkit.reset_fall()
	stats["launch"] = stats.get("launch", 0) + 1


## 수리검이 날아온다 (Projectile 이 알려 준다): 막거나 옆으로 피한다
func on_incoming_object(obj: Node3D) -> void:
	if not active or dead:
		return
	await get_tree().create_timer(reaction_time, false).timeout
	if not active or dead or not is_instance_valid(obj):
		return
	if not (_can_react() or state == "block"):
		return
	var r := randf()
	if obj is Projectile:
		# 수리검: 찌르기 막기(가운데)로 막거나 옆으로 피한다. 가끔은 못 본다
		if r < 0.2:
			return
		# 멀리서 날아오면: 앞쪽 비스듬히 대시해 피하면서 거리를 좁힌다
		if _dist > 5.5 and stamina > DASH_COST * 1.5 and r < 0.7:
			_dash_dir(0.6, 0.8)
			return
		guard_dir = _read_dir(AttackDir.MID)
	if r < block_chance + 0.15:
		_face = Vector3.ZERO
		_enter_block()
	elif r < block_chance + 0.15 + dodge_chance + 0.25:
		_dash_dir(0.0, 1.0)


## 기둥이 내 쪽으로 쓰러진다: 옆으로 피한다 (늘 피하지는 못한다)
func on_falling_hazard(axis: Vector3, from: Vector3) -> void:
	if not active or dead:
		return
	await get_tree().create_timer(reaction_time + 0.1, false).timeout
	if not active or dead or state in ["stagger", "hang", "zip", "grapple"]:
		return
	if randf() > 0.35 + read_skill * 0.6:
		return
	var side := signf((global_position - from).dot(axis))
	if side == 0.0:
		side = 1.0
	stats["dodge_pillar"] = stats.get("dodge_pillar", 0) + 1
	sm.go("dash", {"vec": axis * side})


# ---------------- 새 무기: 발차기 자세, 수리검 던지기, 여러 번 치는 필살기 ----------------

var _strike_i := 0          # 여러 번 치는 필살기: 지금까지 낸 수
var _strike_extra := {}     # 이번 한 방에만 덧붙는 판정 (마지막 한 방 등)


## 맨몸 발차기면 다리를 든다 (amt 0.5 = 무릎 접기, 1 = 뻗기)
func _kick_pose(data: Dictionary, amt: float) -> void:
	var limb := str(data.get("limb", ""))
	if limb.begins_with("kick"):
		rig.kick_style = limb
		rig.leg_kick = amt
	else:
		rig.leg_kick = 0.0


## 수리검을 던진다. 상대가 움직이는 쪽을 조금 앞서 노린다 (다 앞서지는 않아서 옆으로 피할 수 있다)
func _throw_projectiles(data: Dictionary, count: int, spread_deg: float, speed: float, homing: float, only := -1, uses_ammo := false) -> void:
	if target == null:
		return
	var fwd := -global_transform.basis.z
	var from := global_position + Vector3.UP * 1.45 + fwd * 0.45 + global_transform.basis.x * 0.18
	var aim := target.global_position + Vector3.UP * 1.15
	var tt := from.distance_to(aim) / maxf(speed, 1.0)
	aim += Vector3(target.velocity.x, 0, target.velocity.z) * tt * 0.55
	var base_dir := (aim - from).normalized()
	var dmg := float(data.damage)
	var info := {"move": _attack, "damage": 0, "react": data.react, "guard": data.get("ai_guard", data.guard),
			"pressure": build.guard_pressure() * Weapons.stat(weapon, "pressure"), "dir": data.get("dir", AttackDir.MID),
			"push": float(data.get("push", 0.0)), "lift": float(data.get("lift", 2.0)), "power": vkit.powered()}
	if uses_ammo:
		info.ammo = true
		info.falloff_w = weapon
	for i in count:
		if only >= 0 and i != only:
			continue
		var a := 0.0
		if count > 1:
			a = lerpf(-spread_deg * 0.5, spread_deg * 0.5, float(i) / float(count - 1))
		var dir := base_dir.rotated(Vector3.UP, deg_to_rad(a))
		info.damage = int(round(dmg * build.damage_mult() * vkit.damage_mult())) + randi_range(-1, 1)
		Projectile.launch(get_parent(), from, dir, speed, info, self, target, homing)


## 수리검이 어디에 닿았는지 (Projectile 이 알려 준다)
func on_projectile_result(result: String, info: Dictionary, _body: Node3D) -> void:
	stats["res_" + result] = stats.get("res_" + result, 0) + 1
	if result in ["hit", "guard_broken", "wrong_guard"]:
		if info.get("move", "") != "special":
			add_gauge(float(info.damage) * Weapons.GAUGE.dealt)
	if result in ["hit", "guard_broken", "wrong_guard", "blocked", "parried", "dodged"]:
		mind.my_attack_result(str(info.get("dir", "")), result)


## 폭풍 난타(봉) / 칼날 폭풍(수리검): 휘두르는 시간 동안 나눠서 여러 번 친다
func _special_multi(data: Dictionary) -> void:
	var count := int(data.get("strikes", data.get("count", 1)))
	var gap := float(data.active) / float(count)
	while _strike_i < count and _state_t >= gap * _strike_i:
		var i := _strike_i
		_strike_i += 1
		var last := i == count - 1
		if data.effect == "storm":
			# 부채꼴 안에서 왼쪽 오른쪽을 오가며 한 장씩
			var order := (i * 3) % count
			_throw_projectiles(data, count, float(data.spread), float(data.speed), float(data.get("homing", 0.0)), order)
			_play("shuriken_throw", -3.0)
		else:
			_hit_done = false
			_strike_extra = {}
			if last:
				_strike_extra = {"damage": int(round(float(data.last_damage) * build.damage_mult() * _damage_scale)), "guard": "break",
						"react": "stagger", "knockdown": true, "push": 9.0, "lift": 3.0}
			rig.set_pose(data.body.strike if i % 2 == 0 else data.body.windup, 45.0)
			_play(_wsnd("swing_heavy" if last else "swing"), -2.0)


# ---------------- 던지는 무기의 수 (수리검) ----------------

## 던질 수 있는 만큼 쓴다. 0 장이면 못 던진다. 돌려준 값만큼 던진다.
func use_ammo(want: int) -> int:
	if ammo_max <= 0:
		return want
	var n := mini(want, ammo)
	ammo -= n
	_ammo_t = 0.0
	ammo_changed.emit(ammo, ammo_max)
	return n


## 떨어진 수리검을 주웠다 (Projectile 이 부른다). 가득 차 있으면 줍지 않는다.
func pick_up_star() -> bool:
	if dead or ammo_max <= 0 or ammo >= ammo_max:
		return false
	ammo += 1
	ammo_changed.emit(ammo, ammo_max)
	_play("shuriken_stick")
	return true


func _ammo_tick(delta: float) -> void:
	if ammo_max <= 0 or ammo >= ammo_max:
		return
	_ammo_t += delta
	if _ammo_t >= Weapons.stat_or(weapon, "ammo_regen", 4.0):
		_ammo_t = 0.0
		ammo += 1
		ammo_changed.emit(ammo, ammo_max)
