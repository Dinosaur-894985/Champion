class_name BodyRig
extends Node3D
## 3인칭 결투사 몸 (로우폴리)과 몸 움직임.
##
## 겉모습: 빌드(CharacterBuild)를 보고 만든다.
##   무기 → 옷차림 (한손검 기사, 대검 중갑, 쌍단검 두건, 창 비늘 갑옷, 봉 도복, 수리검 복면, 맨몸 격투복)
##   색/피부/머리 → 빌드의 color, skin, hair
##   몸집 → 힘과 체력이 높으면 어깨가 넓고 팔다리가 굵다, 민첩이 높으면 날렵하다
##
## 움직임은 세 겹(레이어)으로 나눠서 각자 계산한 뒤 합친다.
##   1) 아래 몸: 걷기, 옆걸음, 뒷걸음, 대시, 발차기 — 움직이는 방향과 빠르기, 지금 동작이 정한다
##   2) 위 몸: 팔과 무기 자세, 허리 비틀기, 숙이기 — 지금 하는 행동(공격/막기)이 정한다
##      두 손 무기(대검, 창, 봉)는 왼손이 자루를 따라 잡는다 (두 마디 팔 IK)
##   3) 덧붙이는 흔들림: 맞았을 때 젖혀짐, 힘 모을 때 떨림, 숨쉬기, 천자락 흔들림
## 그래서 "걸으면서 베기", "옆으로 대시하며 막기", "공격하다 움찔" 같은 조합이 따로 만들지 않아도 된다.

const WALK_REF_SPEED := 3.9
const UPPER := 0.3        # 위팔 길이
const FORE := 0.3         # 아래팔 길이 (손목까지)

var blade_tip: Node3D
var blade_tip_l: Node3D        # 왼손 끝 (쌍단검/수리검/맨몸의 왼 주먹). 없으면 null
var foot_tip: Node3D           # 오른발 끝과 발목 (발차기 빛 자취)
var foot_base: Node3D
var blade_mat: StandardMaterial3D
## 들고 있는 무기 (Weapons.WEAPONS). 씬에 넣기 전에 정한다.
var weapon := "sword"
## 겉모습을 정하는 빌드. 없으면 기본 모습.
var build: CharacterBuild

# 부품
var _hips: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _knee_l: Node3D
var _knee_r: Node3D
var _arm_r: Node3D
var _elbow_r: Node3D
var _wrist: Node3D
var _arm_l: Node3D
var _elbow_l: Node3D
var _wrist_l: Node3D
var _torso: Node3D
var _head: Node3D
var _grip2: Node3D            # 두 손 무기: 왼손이 잡을 자리
var _flaps: Array[Node3D] = [] # 천자락 (움직임에 따라 흔들린다)
var _flash_mat: StandardMaterial3D
var _body_meshes: Array[MeshInstance3D] = []

# 2) 위 몸 목표 자세
var _shoulder_target := Vector3(55, -15, 0)
var _wrist_target := Vector3.ZERO
var _elbow_target := 0.15
var _twist_target := 0.0
var _lean_target := 0.0
var _pose_speed := 12.0
var _hand := ""                # 맨몸: 이번 동작을 어느 손으로 ("l", "r", "both")
var _l_shoulder := Vector3(20, 0, -12)
var _l_elbow := 0.4

# 3) 덧붙이는 흔들림
var _kick := Vector3.ZERO        # 맞아서 젖혀진 각도 (라디안)
var _kick_vel := Vector3.ZERO
var tremble := 0.0               # 0~1, 힘 모을 때 떨림
var reach := 0.0                 # 0~1, 잡으려고 손을 앞으로 뻗기
var _flash := 0.0

var _walk_phase := 0.0
var _dash_amt := 0.0
var _dash_local := Vector3.ZERO
var _reach_amt := 0.0
var low := 0.0                   # 0~1, 낮게 미끄러지기 (다리 베기)
var _low_amt := 0.0
## 발차기: 0 = 없음, 0.5 = 무릎을 접어 올림, 1 = 뻗음. 종류는 kick_style ("kick", "kick_round", "kick_low")
var leg_kick := 0.0
var kick_style := "kick"
var _leg_kick_amt := 0.0
var frozen := false              # 쓰러진 뒤에는 움직임을 멈춘다
## 애니풍 몸놀림 (AnimStyle 표). 공중에 떠 있는지와 위아래 빠르기는 몸 주인(Duelist)이 알려 준다
var airborne := false
var vy := 0.0
var _neutral := true             # 지금 서 있는 자세(공격/막기 아님)인가
var _air_amt := 0.0
var _run_amt := 0.0
var _stance_amt := 1.0
var _flip_t := -1.0              # 0~1 동안 공중제비. 음수면 없음
var _flip_turns := 1.0
var _t := 0.0
var _flap_sway := Vector3.ZERO

# 몸집 (빌드에서)
var _w := 1.0      # 몸통 굵기
var _sw := 1.0     # 어깨 너비
var _limb := 1.0   # 팔다리 굵기


func _ready() -> void:
	if build == null:
		build = CharacterBuild.new()
		build.weapon = weapon
	_build()


# ---------------- 자세 지시 ----------------

## pose = [어깨 회전(도), 손목 회전(도), 허리 비틀기, 숙이기, (팔꿈치 굽힘, 라디안)]
## hand: 맨몸 격투에서 어느 손으로 하는 동작인가 ("l", "r", "both"). 무기 동작이면 비워 둔다.
func set_pose(pose: Array, speed: float = 12.0, hand: String = "") -> void:
	_hand = hand
	_pose_speed = speed
	var p := pose
	var st := AnimStyle.get_style(weapon)
	_neutral = pose == MoveSet.BODY_POSES.guard
	if _neutral and not (st.guard as Array).is_empty():
		p = st.guard   # 무기마다 다른 애니풍 기본 자세
	elif not _neutral and not MoveSet.BODY_POSES.values().has(pose):
		# 공격 자세: 허리 비틀기와 숙이기를 더 크게 (팔 방향은 그대로라 공격 방향은 똑같이 읽힌다)
		p = pose.duplicate()
		var amp := float(st.amp)
		p[2] = float(p[2]) * amp
		p[3] = float(p[3]) * lerpf(1.0, amp, 0.6)
	if weapon == "fists" and p.size() < 5:
		p = _fist_stance(p)
		if hand == "":
			_hand = "both"
	_shoulder_target = p[0]
	if _grip2 != null and _shoulder_target.x < 150.0:
		# 두 손 무기: 오른손을 몸 가운데로 당겨 왼손이 자루에 닿게 한다
		_shoulder_target += Vector3(0, 0, -22)
	_wrist_target = p[1]
	_twist_target = p[2]
	_lean_target = p[3]
	_elbow_target = float(p[4]) if p.size() > 4 else (0.12 if weapon != "fists" else 1.9)


## 맨몸: 무기용 자세(막기, 기본)를 두 주먹을 든 자세로 바꾼다. 팔을 높이 드는 자세(매달리기 등)는 그대로.
func _fist_stance(p: Array) -> Array:
	var sh: Vector3 = p[0]
	if sh.x > 120.0 or sh.x < 30.0:
		return [sh, Vector3.ZERO, p[2], p[3], 0.35]
	var high := sh.x > 75.0   # 막기
	return [Vector3(60.0 if high else 42.0, 0, -22.0 if high else -14.0), Vector3.ZERO, p[2] * 0.5, p[3], 2.15 if high else 1.95]


## 맞았을 때 젖혀지기. local_dir: 몸 기준으로 맞은 힘의 방향, strength: 1 = 움찔, 2.4 = 크게 휘청
func hit_kick(local_dir: Vector3, strength: float) -> void:
	_kick_vel += Vector3(-local_dir.z * 0.9 - 0.4, 0.0, local_dir.x * 0.8) * strength * 7.0
	_flash = 1.0


func dash_pulse(local_dir: Vector3) -> void:
	_dash_amt = 1.0
	_dash_local = local_dir


func glow(color: Color, energy: float) -> void:
	blade_mat.emission = color
	blade_mat.emission_energy_multiplier = energy


func glow_energy() -> float:
	return blade_mat.emission_energy_multiplier


func flash(amount: float = 1.0) -> void:
	_flash = amount


# ---------------- 매 프레임 합치기 ----------------

## local_vel: 몸 기준 이동 속도 (x 오른쪽, z 뒤쪽)
func animate(delta: float, local_vel: Vector3) -> void:
	if frozen:
		return
	_t += delta
	var k := clampf(delta * _pose_speed, 0, 1)

	# 1) 아래 몸: 앞뒤로는 다리를 흔들고 무릎을 굽히며, 옆으로는 다리를 벌리며 게걸음
	var speed := Vector2(local_vel.x, local_vel.z).length()
	_walk_phase += delta * speed * 3.2
	var amt := clampf(speed / WALK_REF_SPEED, 0.0, 1.0)
	var fwd_part := 0.0
	var side_part := 0.0
	if speed > 0.05:
		fwd_part = -local_vel.z / speed
		side_part = local_vel.x / speed
	var st := AnimStyle.get_style(weapon)
	_run_amt = lerpf(_run_amt, clampf((speed - 4.6) / 2.0, 0.0, 1.0), clampf(delta * 6.0, 0, 1))
	_air_amt = lerpf(_air_amt, 1.0 if airborne else 0.0, clampf(delta * (10.0 if airborne else 16.0), 0, 1))
	# 달리면 다리를 더 크게 휘두르고 무릎을 높이 든다
	var swing := sin(_walk_phase) * amt * lerpf(0.6, 0.95, _run_amt)
	_dash_amt = maxf(_dash_amt - delta * 4.0, 0.0)
	var d := _dash_amt * _dash_amt
	var fa := absf(fwd_part)
	_leg_l.rotation.x = swing * fa - _dash_local.z * d * 0.6
	_leg_r.rotation.x = -swing * fa + _dash_local.z * d * 0.3
	var step := sin(_walk_phase) * amt * side_part * 0.3
	_leg_l.rotation.z = -step - d * 0.35
	_leg_r.rotation.z = step + d * 0.35
	# 발을 들 때 무릎이 굽는다
	var knee_amp := lerpf(0.9, 1.7, _run_amt)
	_knee_l.rotation.x = -maxf(0.0, sin(_walk_phase + 0.9)) * amt * knee_amp - 0.06
	_knee_r.rotation.x = -maxf(0.0, -sin(_walk_phase + 0.9)) * amt * knee_amp - 0.06
	# 서 있을 때: 다리를 벌리고 앞뒤로 엇갈려 무릎을 굽힌 자세 (걸을수록 걷기 동작으로 바뀐다)
	_stance_amt = lerpf(_stance_amt, 1.0 - amt, clampf(delta * 8.0, 0, 1))
	var sta: Dictionary = st.stance
	var drop := float(sta.crouch) * _stance_amt
	if _stance_amt > 0.01:
		_leg_ik(_leg_l, _knee_l, -float(sta.stagger) * 0.5, drop, _stance_amt)
		_leg_ik(_leg_r, _knee_r, float(sta.stagger) * 0.5, drop, _stance_amt)
		_leg_l.rotation.z -= float(sta.spread) * _stance_amt
		_leg_r.rotation.z += float(sta.spread) * _stance_amt
	# 공중: 앞 무릎을 끌어올리고 뒷다리는 접는다. 떨어질 때는 착지하려고 다리를 내린다
	if _air_amt > 0.01:
		var fall := clampf(-vy / 6.0, 0.0, 1.0)
		var tuck := lerpf(1.0, 0.45, fall)
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 1.25 * tuck, _air_amt)
		_knee_l.rotation.x = lerpf(_knee_l.rotation.x, -1.9 * tuck, _air_amt)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -0.35 + 0.4 * (1.0 - tuck), _air_amt)
		_knee_r.rotation.x = lerpf(_knee_r.rotation.x, -1.3 * tuck - 0.1, _air_amt)
		_leg_l.rotation.z = lerpf(_leg_l.rotation.z, -0.12, _air_amt)
		_leg_r.rotation.z = lerpf(_leg_r.rotation.z, 0.12, _air_amt)
	# 발차기: 무릎을 접어 올렸다가(0.5) 뻗는다(1)
	_leg_kick_amt = lerpf(_leg_kick_amt, leg_kick, clampf(delta * 20.0, 0, 1))
	if _leg_kick_amt > 0.01:
		var chamber := clampf(_leg_kick_amt * 2.0, 0.0, 1.0)
		var extend := clampf(_leg_kick_amt * 2.0 - 1.0, 0.0, 1.0)
		var hip_x := 1.45
		var hip_z := 0.0
		match kick_style:
			"kick_round":
				hip_x = 1.25
				hip_z = 0.85
			"kick_low":
				hip_x = 0.9
				hip_z = 0.55
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, hip_x, chamber)
		_leg_r.rotation.z = lerpf(_leg_r.rotation.z, hip_z, chamber)
		_knee_r.rotation.x = lerpf(-2.1, -0.05, extend) * chamber + _knee_r.rotation.x * (1.0 - chamber)
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, -0.15, chamber)
		_knee_l.rotation.x = lerpf(_knee_l.rotation.x, -0.25, chamber)

	# 2) 위 몸: 팔과 허리를 목표 자세로
	var sh_t := _shoulder_target
	var wr_t := _wrist_target
	var el_t := _elbow_target
	var run_arm := _run_amt * (1.0 if _neutral else 0.0) * (1.0 - _air_amt)
	if run_arm > 0.01:
		# 달리기 팔: 무기마다 다르게 (뒤로 젖히기 / 어깨에 메기 / 낮게 겨누기)
		var rp: Array = RUN_ARMS.get(str(st.run), RUN_ARMS.back)
		sh_t = sh_t.lerp(rp[0], run_arm)
		wr_t = wr_t.lerp(rp[1], run_arm)
		el_t = lerpf(el_t, float(rp[2]), run_arm)
	_arm_r.rotation_degrees = _arm_r.rotation_degrees.lerp(sh_t, k)
	_wrist.rotation_degrees = _wrist.rotation_degrees.lerp(wr_t, k)
	_elbow_r.rotation.x = lerpf(_elbow_r.rotation.x, el_t, k)
	var tk := clampf(delta * 10.0, 0, 1)
	var lean := -_lean_target - d * (-_dash_local.z) * 0.25 - float(st.lean) * _run_amt * (1.0 - _air_amt) \
			- 0.18 * _air_amt
	var roll := -d * _dash_local.x * 0.3
	if _leg_kick_amt > 0.01:
		lean += _leg_kick_amt * 0.25          # 발을 뻗으면 몸을 뒤로 젖혀 균형을 잡는다
		roll -= _leg_kick_amt * (0.3 if kick_style == "kick_round" else 0.1)

	# 3) 덧붙이는 흔들림: 스프링처럼 젖혀졌다 돌아온다
	_kick_vel += (-_kick * 140.0 - _kick_vel * 14.0) * delta
	_kick += _kick_vel * delta
	var shake := Vector3.ZERO
	if tremble > 0.0:
		var tt := Time.get_ticks_msec() * 0.07
		shake = Vector3(sin(tt * 1.3), sin(tt * 1.7), sin(tt * 2.1)) * tremble * 0.035
	var breathe := sin(_t * 2.2) * 0.012 * (1.0 - amt)

	_torso.rotation.x = lerpf(_torso.rotation.x, lean, tk) + _kick.x * 0.4 + breathe
	_torso.rotation.y = lerpf(_torso.rotation.y, _twist_target, clampf(delta * 12.0, 0, 1))
	_torso.rotation.z = lerpf(_torso.rotation.z, roll, tk) + _kick.z * 0.4
	_head.rotation = Vector3(_kick.x * 0.6 - breathe * 0.5, -_torso.rotation.y * 0.35, _kick.z * 0.6)
	_arm_r.rotation += shake
	_left_arm(delta)
	# 미끄러질 때: 몸을 낮추고 뒤로 젖히며 한쪽 다리를 앞으로 뻗는다
	_low_amt = lerpf(_low_amt, low, clampf(delta * 12.0, 0, 1))
	if _low_amt > 0.01:
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, -1.35, _low_amt)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.6, _low_amt)
		_knee_r.rotation.x = lerpf(_knee_r.rotation.x, -1.2, _low_amt)
	# 가볍게 들썩이며 서는 무기 (맨몸, 수리검)
	var bounce := absf(sin(_t * 5.0)) * float(sta.bounce) * _stance_amt * (1.0 - _air_amt)
	position = Vector3(0, -_low_amt * 0.55 + bounce - drop * (1.0 - _air_amt), _kick.x * -0.08)
	# 공중제비: 몸 가운데(허리 높이)를 축으로 앞으로 돈다
	var flip := 0.0
	if _flip_t >= 0.0:
		_flip_t += delta / 0.55
		var ft := clampf(_flip_t, 0.0, 1.0)
		flip = -TAU * _flip_turns * (ft * ft * (3.0 - 2.0 * ft))
		if _flip_t >= 1.0 or (not airborne and _flip_t > 0.3):
			_flip_t = -1.0
			flip = 0.0
	rotation.x = _low_amt * 0.35 + flip
	if flip != 0.0:
		var c := Vector3(0, 0.95, 0)
		position += c - c.rotated(Vector3.RIGHT, flip)

	# 천자락: 움직이는 반대쪽으로 날린다
	_flap_sway = _flap_sway.lerp(Vector3(clampf(-local_vel.z, -8, 8) * 0.09 + amt * 0.12, 0, clampf(local_vel.x, -8, 8) * 0.06), clampf(delta * 6.0, 0, 1))
	var flutter := sin(_t * 9.0) * 0.05 * amt
	for f in _flaps:
		var base: Vector3 = f.get_meta("base")
		var dirn: float = f.get_meta("dir")
		f.rotation = base + Vector3((_flap_sway.x + flutter) * dirn, 0, _flap_sway.z)

	# 맞으면 번쩍
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 7.0, 0.0)
		_flash_mat.albedo_color.a = _flash * 0.8
		for m in _body_meshes:
			m.material_overlay = _flash_mat if _flash > 0.0 else null


## 왼팔: 두 손 무기는 자루를 잡고, 쌍단검은 오른팔을 거울처럼 따라 하고, 맨몸은 손에 따라 주먹을 낸다
func _left_arm(delta: float) -> void:
	var k := clampf(delta * _pose_speed, 0, 1)
	_reach_amt = lerpf(_reach_amt, reach, clampf(delta * 14.0, 0, 1))
	if _grip2 != null and _reach_amt < 0.5 \
			and _torso.to_local(_grip2.global_position).distance_to(_arm_l.position) < UPPER + FORE + 0.14:
		_aim_left_at(_grip2.global_position)
		return
	var target := Vector3(20, 0, -12)
	var elbow := 0.45
	var st := AnimStyle.get_style(weapon)
	var left: Array = st.left
	if _neutral and not left.is_empty():
		target = left[0]
		elbow = float(left[1])
	if _run_amt > 0.05 and _neutral and _grip2 == null:
		# 달리기: 왼팔도 뒤로 젖힌다
		target = target.lerp(Vector3(-45, 0, -18), _run_amt * (1.0 - _air_amt))
		elbow = lerpf(elbow, 0.25, _run_amt)
	if _air_amt > 0.05 and _neutral and _grip2 == null:
		target = target.lerp(Vector3(35, 0, -70), _air_amt)   # 공중: 팔을 펼쳐 균형
	var mirror := Vector3(_shoulder_target.x, -_shoulder_target.y, -_shoulder_target.z)
	if weapon == "daggers" and not (_neutral and not left.is_empty() and _run_amt < 0.05):
		target = mirror
		elbow = _elbow_target
	elif weapon == "fists":
		if _hand in ["l", "both"]:
			target = mirror
			elbow = _elbow_target
		else:
			target = Vector3(45, 0, 16)     # 다른 손은 얼굴 앞을 지킨다
			elbow = 2.0
		if _reach_amt > 0.01:
			_arm_r.rotation_degrees = _arm_r.rotation_degrees.lerp(Vector3(82, 0, -8), _reach_amt)
			_elbow_r.rotation.x = lerpf(_elbow_r.rotation.x, 0.15, _reach_amt)
		if _hand == "l":
			# 왼손 동작: 오른손은 지키는 자세로 돌려 둔다 (이미 오른팔 목표가 동작 자세라 여기서 바꾼다)
			_arm_r.rotation_degrees = _arm_r.rotation_degrees.lerp(Vector3(45, 0, -16), k)
			_elbow_r.rotation.x = lerpf(_elbow_r.rotation.x, 2.0, k)
	else:
		# 한 손 무기: 걸을 때 팔을 흔든다
		target.x -= sin(_walk_phase) * 25.0 * clampf(_dash_amt + 0.5, 0, 1) * (1.0 - _run_amt)
	target = target.lerp(Vector3(82, 0, 8), _reach_amt)
	elbow = lerpf(elbow, 0.15, _reach_amt)
	_l_shoulder = _l_shoulder.lerp(target, k)
	_l_elbow = lerpf(_l_elbow, elbow, k)
	_arm_l.transform.basis = Basis.from_euler(_l_shoulder * (PI / 180.0))
	_elbow_l.transform.basis = Basis(Vector3.RIGHT, _l_elbow)


## 두 마디 팔 IK: 왼손이 world 위치 target 에 닿도록 어깨와 팔꿈치를 돌린다 (팔꿈치는 바깥 아래로)
func _aim_left_at(target_g: Vector3) -> void:
	var s_local := _arm_l.position
	var t_local := _torso.to_local(target_g)
	var v := t_local - s_local
	var dist := clampf(v.length(), 0.12, UPPER + FORE - 0.002)
	var dirn := v.normalized() if v.length() > 0.001 else Vector3.DOWN
	var cos_a := clampf((UPPER * UPPER + dist * dist - FORE * FORE) / (2.0 * UPPER * dist), -1.0, 1.0)
	var alpha := acos(cos_a)
	var pole := Vector3(-0.6, -1.0, 0.25).normalized()
	var n := dirn.cross(pole)
	if n.length() < 0.001:
		n = Vector3.RIGHT
	n = n.normalized()
	var upper_dir := dirn.rotated(n, alpha)
	var elbow_pos := s_local + upper_dir * UPPER
	var fore_dir := (s_local + dirn * dist - elbow_pos).normalized()
	var b_upper := Basis(Quaternion(Vector3.DOWN, upper_dir))
	_arm_l.transform.basis = b_upper
	var fore_local := b_upper.inverse() * fore_dir
	_elbow_l.transform.basis = Basis(Quaternion(Vector3.DOWN, fore_local))


## 달리기 팔 자세 [어깨, 손목, 팔꿈치] (AnimStyle 의 run 값)
const RUN_ARMS := {
	"back": [Vector3(-55, 0, 18), Vector3(-60, 0, 0), 0.25],       # 두 팔을 뒤로 젖히고 몸을 숙여 달린다
	"shoulder": [Vector3(150, -20, 30), Vector3(0, 0, 0), 1.9],    # 큰 칼을 어깨에 메고 달린다
	"low": [Vector3(35, -10, 0), Vector3(-15, 0, 0), 0.3],         # 창끝을 낮게 앞으로 겨누고 달린다
}


## 다리 두 마디 IK (앞뒤 방향만): 엉덩이 기준으로 발이 z (앞이 -) 에, 엉덩이가 drop 만큼 내려가도 땅에 닿게
func _leg_ik(leg: Node3D, knee: Node3D, z: float, drop: float, w: float) -> void:
	const L1 := 0.44
	const L2 := 0.47
	var dy := L1 + L2 - 0.01 - drop
	var dist := clampf(sqrt(z * z + dy * dy), 0.2, L1 + L2 - 0.005)
	var phi := atan2(-z, dy)
	var a := acos(clampf((L1 * L1 + dist * dist - L2 * L2) / (2.0 * L1 * dist), -1.0, 1.0))
	var b := acos(clampf((L2 * L2 + dist * dist - L1 * L1) / (2.0 * L2 * dist), -1.0, 1.0))
	leg.rotation.x = lerpf(leg.rotation.x, phi + a, w)
	knee.rotation.x = lerpf(knee.rotation.x, -(a + b), w)


## 높이 뛸 때 공중제비 (무기마다 AnimStyle air_flip). 이중 점프, 바람 발판에서 부른다
func flip() -> void:
	var turns := float(AnimStyle.val(weapon, "air_flip", 0.0))
	if turns <= 0.0 or _flip_t >= 0.0:
		return
	_flip_turns = turns
	_flip_t = 0.0


## 쓰러지기
func fall(local_dir: Vector3) -> void:
	frozen = true
	glow(blade_mat.emission, 0.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "rotation:x", -PI * 0.47 * signf(-local_dir.z if absf(local_dir.z) > 0.1 else 1.0), 0.7) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:y", 0.15, 0.7)


# ---------------- 몸 만들기 ----------------

## 부위 모양마다 재질 (BodyRig.make_mats 의 이름): 허벅지, 정강이 / 신발 / 위팔, 아래팔, 손
## 다리는 legs, 신발은 feet, 팔은 arms 부위가 고른 모양을 따른다 (CharacterBuild.parts)
const LEG_LOOK := {
	"knight": ["cloth_dark", "armor"], "heavy": ["armor", "armor_light"], "rogue": ["suit", "leather"],
	"lancer": ["cloth_dark", "armor_light"], "monk": ["cream", "cream"], "shadow": ["suit", "cloth_dark"],
	"brawler": ["cloth_dark", "cloth_dark"],
}
const FEET_LOOK := {
	"knight": "leather", "heavy": "armor", "rogue": "leather_dark", "lancer": "leather",
	"monk": "straw", "shadow": "suit", "brawler": "skin",
}
const ARM_LOOK := {
	"knight": ["armor", "armor_light", "leather"], "heavy": ["armor_light", "armor_light", "armor"],
	"rogue": ["cloth_dark", "leather", "leather_dark"], "lancer": ["cloth", "armor_light", "leather"],
	"monk": ["cloth", "skin", "cream"], "shadow": ["suit", "cloth_dark", "suit"],
	"brawler": ["skin", "skin", "cream"],
}

var _m := {}   # 재질 모음


## 몸에 쓰는 재질 모음 (1인칭 손/다리도 같은 것을 쓴다)
static func make_mats(b: CharacterBuild) -> Dictionary:
	var acc := b.accent()
	return {
		"skin": LowPoly.mat(b.skin_color(), 0.75),
		"hair": LowPoly.mat(b.hair_color(), 0.8),
		"cloth": LowPoly.mat(acc, 0.85),
		"cloth_dark": LowPoly.mat(acc.darkened(0.38), 0.9),
		"trim": LowPoly.mat(acc.lightened(0.35), 0.8),
		"armor": LowPoly.mat(Color(0.33, 0.35, 0.4), 0.45, 0.55),
		"armor_light": LowPoly.mat(Color(0.62, 0.65, 0.7), 0.35, 0.7),
		"leather": LowPoly.mat(Color(0.3, 0.19, 0.11), 0.9),
		"leather_dark": LowPoly.mat(Color(0.17, 0.11, 0.07), 0.9),
		"suit": LowPoly.mat(Color(0.13, 0.14, 0.17), 0.85),
		"cream": LowPoly.mat(Color(0.88, 0.84, 0.74), 0.9),
		"straw": LowPoly.mat(Color(0.72, 0.6, 0.36), 0.95),
		"brass": LowPoly.mat(Color(0.78, 0.6, 0.28), 0.4, 0.75),
		"eye": LowPoly.mat(Color(0.06, 0.05, 0.05), 0.4),
		"visor": LowPoly.mat(Color(0.04, 0.04, 0.05), 0.3),
	}


func _mat(key: String, c: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	if not _m.has(key):
		_m[key] = LowPoly.mat(c, rough, metal)
	return _m[key]


func _p(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := LowPoly.part(parent, mesh, mat, pos, rot)
	if scl != Vector3.ONE:
		mi.scale = scl
	return mi


## 천자락 하나: pivot 에서 아래로 늘어진다. dir: 앞자락 1, 뒷자락 -1
func _flap(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, dir: float, tilt := Vector3.ZERO) -> Node3D:
	var f := Node3D.new()
	f.position = pos
	f.rotation_degrees = tilt
	f.set_meta("base", f.rotation)
	f.set_meta("dir", dir)
	parent.add_child(f)
	_p(f, LowPoly.box(size), mat, Vector3(0, -size.y * 0.5, 0))
	_flaps.append(f)
	return f


func _build() -> void:
	weapon = Weapons.valid(weapon)
	var s_head := build.part("head")
	var s_torso := build.part("torso")
	var s_arms := build.part("arms")
	var s_legs := build.part("legs")
	var s_feet := build.part("feet")
	var st: Dictionary = build.stats
	var bulk := clampf((float(st.get("str", 5)) + float(st.get("vit", 5)) - 2.0) / 18.0, 0.0, 1.0)
	var agi := clampf(float(st.get("agi", 5)) / 10.0, 0.0, 1.0)
	_w = 0.9 + bulk * 0.22 - agi * 0.05
	_sw = 0.92 + bulk * 0.26 - agi * 0.04
	_limb = 0.9 + bulk * 0.3
	scale = Vector3.ONE * (0.97 + bulk * 0.06)

	var acc := build.accent()
	_m = make_mats(build)
	var skin: Material = _m.skin
	var hair: Material = _m.hair
	var cloth: Material = _m.cloth
	var cloth_dark: Material = _m.cloth_dark
	var armor: Material = _m.armor
	var armor_light: Material = _m.armor_light
	var leather: Material = _m.leather
	var leather_dark: Material = _m.leather_dark
	var suit: Material = _m.suit
	var cream: Material = _m.cream
	var eye: Material = _m.eye
	_flash_mat = LowPoly.mat(Color(1, 0.95, 0.9, 0.0))
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# 부위마다 고른 모양의 재질: 허벅지, 정강이, 신발, 위팔, 아래팔, 손
	var look: Array = []
	for k in LEG_LOOK.get(s_legs, LEG_LOOK.knight):
		look.append(_m[k])
	look.append(_m[FEET_LOOK.get(s_feet, "leather")])
	for k in ARM_LOOK.get(s_arms, ARM_LOOK.knight):
		look.append(_m[k])

	# ---- 엉덩이와 다리 ----
	_hips = Node3D.new()
	add_child(_hips)
	var thigh_r := 0.085 * _limb * (1.22 if s_legs in ["monk", "brawler"] else 1.0)   # 도복/격투복은 바지가 넉넉하다
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(0.11 * side * _w, 0.92, 0)
		_hips.add_child(leg)
		_p(leg, LowPoly.cyl(thigh_r, thigh_r * 1.15, 0.46, 7), look[0], Vector3(0, -0.22, 0))
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.44, 0)
		leg.add_child(knee)
		_p(knee, LowPoly.cyl(0.066 * _limb, 0.08 * _limb, 0.4, 7), look[1], Vector3(0, -0.2, 0))
		_p(knee, LowPoly.box(Vector3(0.12, 0.1, 0.24) * Vector3(_limb, 1, 1)), look[2], Vector3(0, -0.43, -0.04))
		_p(knee, LowPoly.box(Vector3(0.1, 0.05, 0.08)), look[2], Vector3(0, -0.4, -0.15), Vector3(-20, 0, 0))
		match s_legs:
			"knight", "lancer", "heavy":
				_p(knee, LowPoly.sphere(0.07 * _limb, 6, 4), armor_light, Vector3(0, 0.0, -0.04))   # 무릎 덮개
				_p(knee, LowPoly.box(Vector3(0.12, 0.26, 0.04) * Vector3(_limb, 1, 1)), armor_light, Vector3(0, -0.2, -0.07))
			"monk", "shadow":
				for i in 3:
					_p(knee, LowPoly.cyl(0.075 * _limb, 0.075 * _limb, 0.03, 7), cream if s_legs == "monk" else cloth, Vector3(0, -0.12 - i * 0.08, 0))
			"brawler":
				_p(knee, LowPoly.cyl(0.08 * _limb, 0.08 * _limb, 0.05, 7), cloth, Vector3(0, -0.34, 0))
			"rogue":
				_p(knee, LowPoly.cyl(0.085 * _limb, 0.078 * _limb, 0.16, 7), leather_dark, Vector3(0, -0.3, 0))
		_build_feet(knee, s_feet)
		if side > 0:
			foot_tip = Node3D.new()
			foot_tip.position = Vector3(0, -0.47, -0.16)
			knee.add_child(foot_tip)
			foot_base = Node3D.new()
			foot_base.position = Vector3(0, -0.3, -0.02)
			knee.add_child(foot_base)
		if side < 0:
			_leg_l = leg
			_knee_l = knee
		else:
			_leg_r = leg
			_knee_r = knee

	# ---- 몸통 ----
	_torso = Node3D.new()
	_torso.position = Vector3(0, 0.95, 0)
	_hips.add_child(_torso)
	var chest_mat: Material = {"knight": armor, "heavy": armor, "rogue": leather, "lancer": armor,
			"monk": cloth, "shadow": suit, "brawler": cream}[s_torso]
	var belly_mat: Material = {"knight": cloth_dark, "heavy": armor, "rogue": suit, "lancer": cloth_dark,
			"monk": cloth, "shadow": suit, "brawler": cream}[s_torso]
	_body_meshes.append(_p(_torso, LowPoly.cyl(0.17 * _w, 0.18 * _w, 0.2, 8), look[0], Vector3(0, -0.02, 0)))
	_p(_torso, LowPoly.cyl(0.165 * _w, 0.17 * _w, 0.2, 8), belly_mat, Vector3(0, 0.16, 0))
	_body_meshes.append(_p(_torso, LowPoly.cyl(0.24 * _sw, 0.17 * _w, 0.36, 8), chest_mat, Vector3(0, 0.43, 0), Vector3.ZERO, Vector3(1, 1, 0.82)))
	_p(_torso, LowPoly.cyl(0.2 * _sw, 0.24 * _sw, 0.07, 8), chest_mat, Vector3(0, 0.64, 0), Vector3.ZERO, Vector3(1, 1, 0.8))
	_p(_torso, LowPoly.cyl(0.055, 0.065, 0.1, 7), skin, Vector3(0, 0.71, 0))
	# 허리띠
	var belt_mat: Material = cloth if s_torso in ["monk", "brawler", "rogue", "shadow"] else leather
	_p(_torso, LowPoly.cyl(0.185 * _w, 0.185 * _w, 0.07 if s_torso != "monk" else 0.11, 8), belt_mat, Vector3(0, 0.07, 0))
	_build_outfit(s_torso)

	# ---- 머리 ----
	_head = Node3D.new()
	_head.position = Vector3(0, 0.845, 0)
	_torso.add_child(_head)
	_build_head(s_head, skin, hair, eye)

	# ---- 팔 ----
	var arm_t := _limb * (1.12 if s_arms == "brawler" else 1.0)
	for side in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(0.265 * side * _sw, 0.6, 0)
		_torso.add_child(sh)
		_p(sh, LowPoly.sphere(0.068 * arm_t, 7, 4), look[3], Vector3(0, -0.02, 0))
		_p(sh, LowPoly.cyl(0.058 * arm_t, 0.062 * arm_t, UPPER, 7), look[3], Vector3(0, -UPPER * 0.5, 0))
		var el := Node3D.new()
		el.position = Vector3(0, -UPPER, 0)
		sh.add_child(el)
		_p(el, LowPoly.sphere(0.05 * arm_t, 6, 4), look[4], Vector3.ZERO)
		_p(el, LowPoly.cyl(0.05 * arm_t, 0.056 * arm_t, FORE - 0.03, 7), look[4], Vector3(0, -FORE * 0.48, 0))
		match s_arms:
			"knight", "lancer", "heavy":
				_p(el, LowPoly.cyl(0.066 * arm_t, 0.058 * arm_t, 0.13, 7), armor_light, Vector3(0, -FORE + 0.08, 0))   # 손목 보호대
			"monk", "brawler":
				for i in 3:
					_p(el, LowPoly.cyl(0.054 * arm_t, 0.054 * arm_t, 0.025, 7), cream, Vector3(0, -FORE + 0.04 + i * 0.045, 0))
			"rogue", "shadow":
				_p(el, LowPoly.cyl(0.058 * arm_t, 0.054 * arm_t, 0.14, 7), cloth if s_arms == "shadow" else leather_dark, Vector3(0, -FORE + 0.09, 0))
		var wr := Node3D.new()
		wr.position = Vector3(0, -FORE, 0)
		el.add_child(wr)
		_p(wr, LowPoly.box(Vector3(0.075, 0.085, 0.08) * arm_t), look[5], Vector3(0, -0.035, 0))
		_p(wr, LowPoly.box(Vector3(0.028, 0.045, 0.035) * arm_t), look[5], Vector3(-0.045 * side, -0.02, -0.03), Vector3(0, 0, 20 * side))
		if side < 0:
			_arm_l = sh
			_elbow_l = el
			_wrist_l = wr
		else:
			_arm_r = sh
			_elbow_r = el
			_wrist = wr
	_arm_r.rotation_degrees = _shoulder_target
	_build_outfit_arms(s_arms)

	# ---- 무기 ----
	# 무기는 손에서 앞(-Z)으로 뻗는다. 모양은 Weapons.build_model (+Y 로 뻗는 모양을 눕혀서 붙인다)
	var opts := {"accent": acc, "skin": build.skin_color()}
	if weapon == "fists":
		# 맨몸: 손이 곧 무기. 붕대 감은 주먹이 빛난다
		var wrap := LowPoly.mat(Color(0.93, 0.9, 0.84), 0.9)
		wrap.emission_enabled = true
		wrap.emission = Color(1.0, 0.5, 0.1)
		wrap.emission_energy_multiplier = 0.0
		for wr in [_wrist, _wrist_l]:
			_p(wr, LowPoly.box(Vector3(0.085, 0.09, 0.088) * arm_t), wrap, Vector3(0, -0.04, 0))
			_p(wr, LowPoly.box(Vector3(0.088, 0.03, 0.03) * arm_t), cloth, Vector3(0, 0.0, 0))
		blade_mat = wrap
		blade_tip = Node3D.new()
		blade_tip.position = Vector3(0, -0.08, 0)
		_wrist.add_child(blade_tip)
		blade_tip_l = Node3D.new()
		blade_tip_l.position = Vector3(0, -0.08, 0)
		_wrist_l.add_child(blade_tip_l)
		set_pose(MoveSet.BODY_POSES.guard, 12.0)
	else:
		var holder := Node3D.new()
		holder.rotation_degrees = Vector3(-90, 0, 0)
		holder.position = Vector3(0, -0.04, 0)
		if weapon == "spear":
			holder.position = Vector3(0, -0.04, 0.35)   # 긴 자루는 뒤로도 나온다
		_wrist.add_child(holder)
		var model := Weapons.build_model(holder, weapon, false, opts)
		blade_mat = model.mat
		blade_mat.emission = Color(1.0, 0.5, 0.1)
		blade_tip = model.tip
		_grip2 = model.grip2
		if weapon in ["daggers", "shuriken"]:
			# 왼손에도 하나
			var lh := Node3D.new()
			lh.position = Vector3(0, -0.04, 0)
			lh.rotation_degrees = Vector3(-90, 0, 0)
			_wrist_l.add_child(lh)
			blade_tip_l = Weapons.build_model(lh, weapon, true, opts).tip

	for m in find_children("*", "MeshInstance3D", true, false):
		if not _body_meshes.has(m):
			_body_meshes.append(m)


## 옷차림: 가슴, 어깨, 허리 아래 천자락, 망토
func _build_outfit(style: String) -> void:
	var m := _m
	var t := _torso
	var sw := _sw
	match style:
		"knight":
			# 가슴판 + 둥근 어깨받이 + 포인트 색 앞자락
			_p(t, LowPoly.box(Vector3(0.34 * sw, 0.3, 0.07)), m.armor_light, Vector3(0, 0.46, -0.16), Vector3(-6, 0, 0))
			_p(t, LowPoly.box(Vector3(0.05, 0.26, 0.075)), m.cloth, Vector3(0, 0.46, -0.165), Vector3(-6, 0, 0))
			for s in [-1.0, 1.0]:
				_p(t, LowPoly.sphere(0.12, 7, 4), m.armor_light, Vector3(0.28 * s * sw, 0.63, 0), Vector3(0, 0, -22 * s), Vector3(1.15, 0.75, 1.1))
				_p(t, LowPoly.cyl(0.12, 0.13, 0.03, 7), m.cloth, Vector3(0.3 * s * sw, 0.575, 0), Vector3(0, 0, -22 * s))
			_p(t, LowPoly.cyl(0.08, 0.1, 0.07, 7), m.armor, Vector3(0, 0.71, 0))
			_p(t, LowPoly.box(Vector3(0.06, 0.05, 0.03)), m.brass, Vector3(0, 0.07, -0.19))
			_flap(t, Vector3(0, 0.04, -0.17), Vector3(0.2 * _w, 0.42, 0.025), m.cloth, 1.0)
			_flap(t, Vector3(0, 0.04, 0.17), Vector3(0.22 * _w, 0.38, 0.025), m.cloth_dark, -1.0)
		"heavy":
			# 겹친 큰 어깨받이, 목 가리개, 허리 갑옷 비늘, 포인트 색 망토
			_p(t, LowPoly.box(Vector3(0.38 * sw, 0.32, 0.08)), m.armor_light, Vector3(0, 0.46, -0.16), Vector3(-6, 0, 0))
			_p(t, LowPoly.box(Vector3(0.36 * sw, 0.26, 0.06)), m.armor_light, Vector3(0, 0.45, 0.16), Vector3(6, 0, 0))
			for s in [-1.0, 1.0]:
				_p(t, LowPoly.sphere(0.15, 7, 4), m.armor_light, Vector3(0.3 * s * sw, 0.64, 0), Vector3(0, 0, -25 * s), Vector3(1.2, 0.75, 1.15))
				_p(t, LowPoly.box(Vector3(0.2, 0.05, 0.26)), m.armor, Vector3(0.34 * s * sw, 0.54, 0), Vector3(0, 0, -38 * s))
				_p(t, LowPoly.box(Vector3(0.05, 0.04, 0.27)), m.cloth, Vector3(0.42 * s * sw, 0.5, 0), Vector3(0, 0, -38 * s))
			_p(t, LowPoly.cyl(0.11, 0.15, 0.1, 8), m.armor_light, Vector3(0, 0.72, 0))
			for i in 5:
				var a := -0.9 + i * 0.45
				_p(t, LowPoly.box(Vector3(0.14, 0.2, 0.03)), m.armor, Vector3(sin(a) * 0.19 * _w, -0.1, -cos(a) * 0.19 * _w), Vector3(-10, rad_to_deg(a), 0))
			_flap(t, Vector3(0, 0.66, 0.15), Vector3(0.46 * sw, 1.0, 0.025), m.cloth, -1.0, Vector3(6, 0, 0))
		"rogue":
			# 가죽 조끼, 엇갈린 끈, 주머니, 짧은 어깨 망토
			for s in [-1.0, 1.0]:
				_p(t, LowPoly.box(Vector3(0.04, 0.5, 0.02)), m.leather_dark, Vector3(0.0, 0.42, -0.165), Vector3(-4, 0, 32 * s))
			_p(t, LowPoly.box(Vector3(0.08, 0.06, 0.05)), m.leather_dark, Vector3(0.13, 0.03, -0.15))
			_p(t, LowPoly.box(Vector3(0.07, 0.07, 0.05)), m.leather_dark, Vector3(-0.15, 0.04, -0.12), Vector3(0, 30, 0))
			_p(t, LowPoly.box(Vector3(0.06, 0.24, 0.04)), m.leather_dark, Vector3(0.17, 0.0, 0.1), Vector3(0, 0, 10))   # 등 뒤 단검집
			_p(t, LowPoly.cyl(0.22 * sw, 0.3 * sw, 0.22, 8), m.cloth_dark, Vector3(0, 0.58, 0.02), Vector3.ZERO, Vector3(1, 1, 0.85))
			_flap(t, Vector3(0.08, 0.06, -0.16), Vector3(0.09, 0.3, 0.02), m.cloth, 1.0, Vector3(0, 0, 6))
			_flap(t, Vector3(0, 0.5, 0.14), Vector3(0.36 * sw, 0.42, 0.02), m.cloth_dark, -1.0, Vector3(8, 0, 0))
		"lancer":
			# 비늘 갑옷 줄, 왼쪽 큰 어깨받이, 앞뒤로 긴 천자락
			for row in 4:
				for col in 4:
					var x := (-0.135 + col * 0.09 + (0.045 if row % 2 == 1 else 0.0)) * sw
					if absf(x) > 0.17 * sw:
						continue
					_p(t, LowPoly.box(Vector3(0.085, 0.075, 0.02)), m.armor_light, Vector3(x, 0.56 - row * 0.07, -0.17 + row * 0.006), Vector3(-10, 0, 0))
			_p(t, LowPoly.sphere(0.14, 7, 4), m.armor_light, Vector3(-0.29 * sw, 0.63, 0), Vector3(0, 0, 25), Vector3(1.2, 0.8, 1.15))
			_p(t, LowPoly.box(Vector3(0.05, 0.04, 0.22)), m.cloth, Vector3(-0.37 * sw, 0.56, 0), Vector3(0, 0, 40))
			_p(t, LowPoly.sphere(0.1, 7, 4), m.cloth, Vector3(0.28 * sw, 0.62, 0), Vector3(0, 0, -20), Vector3(1.1, 0.7, 1.0))
			_p(t, LowPoly.cyl(0.08, 0.1, 0.07, 7), m.armor, Vector3(0, 0.71, 0))
			_flap(t, Vector3(0, 0.06, -0.17), Vector3(0.18 * _w, 0.55, 0.022), m.cloth, 1.0)
			_flap(t, Vector3(0, 0.06, 0.17), Vector3(0.2 * _w, 0.6, 0.022), m.cloth, -1.0)
			_p(t, LowPoly.box(Vector3(0.19 * _w, 0.03, 0.03)), m.trim, Vector3(0, 0.06, -0.18))
		"monk":
			# 여민 깃, 넓은 띠와 늘어진 띠 끝, 나무 염주
			for s in [-1.0, 1.0]:
				_p(t, LowPoly.box(Vector3(0.05, 0.36, 0.02)), m.trim, Vector3(0.05 * s, 0.5, -0.18), Vector3(-6, 0, -24 * s))
			_flap(t, Vector3(0.12, 0.04, -0.15), Vector3(0.06, 0.34, 0.02), m.cloth_dark, 1.0, Vector3(0, 0, 8))
			_flap(t, Vector3(0.05, 0.04, -0.17), Vector3(0.05, 0.28, 0.02), m.cloth_dark, 1.0, Vector3(0, 0, -4))
			_flap(t, Vector3(0, 0.0, -0.16), Vector3(0.3 * _w, 0.32, 0.02), m.cloth, 1.0)   # 도복 앞자락
			_flap(t, Vector3(0, 0.0, 0.16), Vector3(0.32 * _w, 0.32, 0.02), m.cloth, -1.0)
			var bead := _mat("bead", Color(0.36, 0.2, 0.1), 0.5)
			for i in 9:
				var a := PI * (0.15 + 0.7 * float(i) / 8.0)
				_p(t, LowPoly.sphere(0.022, 6, 3), bead, Vector3(cos(a) * 0.12, 0.7 - sin(a) * 0.1, -sin(a) * 0.1 - 0.06))
		"shadow":
			# 몸에 붙는 옷, 포인트 색 목도리와 긴 끝자락, 수리검 띠
			_p(t, LowPoly.cyl(0.1, 0.13, 0.1, 8), m.cloth, Vector3(0, 0.7, 0))
			_flap(t, Vector3(0.05, 0.7, 0.1), Vector3(0.07, 0.6, 0.02), m.cloth, -1.0, Vector3(30, 0, 8))
			_flap(t, Vector3(-0.04, 0.7, 0.1), Vector3(0.06, 0.48, 0.02), m.cloth, -1.0, Vector3(34, 0, -6))
			var strap := _p(t, LowPoly.box(Vector3(0.05, 0.56, 0.02)), m.leather, Vector3(0.0, 0.42, -0.17), Vector3(-4, 0, -38))
			strap.name = "strap"
			var steel := _mat("star", Color(0.75, 0.78, 0.83), 0.25, 0.85)
			for i in 3:
				var mi := MeshInstance3D.new()
				mi.mesh = Weapons.shuriken_mesh()
				mi.material_override = steel
				mi.position = Vector3(-0.09 + i * 0.08, 0.3 + i * 0.08, -0.185)
				mi.rotation_degrees = Vector3(90, 0, 20 * i)
				mi.scale = Vector3.ONE * 0.6
				t.add_child(mi)
			_flap(t, Vector3(0, 0.02, -0.16), Vector3(0.1, 0.24, 0.02), m.cloth_dark, 1.0)
		"brawler":
			# 민소매 웃옷, 매듭 띠, 넉넉한 바지 자락
			_p(t, LowPoly.cyl(0.22 * _sw, 0.18 * _w, 0.06, 8), m.cloth, Vector3(0, 0.26, 0), Vector3.ZERO, Vector3(1, 1, 0.82))
			_flap(t, Vector3(0.1, 0.06, -0.15), Vector3(0.05, 0.26, 0.02), m.cloth, 1.0, Vector3(0, 0, 10))
			_flap(t, Vector3(0.14, 0.06, -0.13), Vector3(0.05, 0.2, 0.02), m.cloth, 1.0, Vector3(0, 0, -6))


func _build_outfit_arms(style: String) -> void:
	match style:
		"heavy":
			for e in [_elbow_l, _elbow_r]:
				_p(e, LowPoly.sphere(0.065 * _limb, 6, 4), _m.armor, Vector3(0, 0, -0.02))
		"knight", "lancer":
			for e in [_elbow_l, _elbow_r]:
				_p(e, LowPoly.sphere(0.058 * _limb, 6, 4), _m.armor_light, Vector3(0, 0, -0.02))
		"monk":
			for a in [_arm_l, _arm_r]:
				_p(a, LowPoly.cyl(0.075 * _limb, 0.09 * _limb, 0.18, 7), _m.cloth, Vector3(0, -0.14, 0))   # 넓은 소매
		"brawler":
			for s in [-1.0, 1.0]:
				_p(_torso, LowPoly.sphere(0.085 * _limb * 1.12, 7, 4), _m.skin, Vector3(0.24 * s * _sw, 0.6, 0), Vector3.ZERO, Vector3(1.2, 1.0, 1.1))   # 드러난 어깨


## 신발 모양마다 덧붙이는 것 (knee 노드 기준, 발은 -0.43 높이)
func _build_feet(knee: Node3D, style: String) -> void:
	match style:
		"heavy":
			_p(knee, LowPoly.box(Vector3(0.13 * _limb, 0.05, 0.12)), _m.armor_light, Vector3(0, -0.36, -0.08), Vector3(-15, 0, 0))   # 쇠 발등
		"lancer":
			_p(knee, LowPoly.box(Vector3(0.11, 0.04, 0.06)), _m.armor_light, Vector3(0, -0.45, -0.15))   # 쇠 코
			_p(knee, LowPoly.cyl(0.075 * _limb, 0.075 * _limb, 0.03, 7), _m.brass, Vector3(0, -0.33, 0))
		"knight", "rogue":
			_p(knee, LowPoly.cyl(0.078 * _limb, 0.072 * _limb, 0.1, 7), _m[FEET_LOOK[style]], Vector3(0, -0.33, 0))   # 장화 목
		"monk":
			_p(knee, LowPoly.box(Vector3(0.125 * _limb, 0.02, 0.25)), _m.leather, Vector3(0, -0.475, -0.04))   # 짚신 바닥
			for i in 2:
				_p(knee, LowPoly.box(Vector3(0.13 * _limb, 0.015, 0.02)), _m.leather_dark, Vector3(0, -0.42, -0.1 + i * 0.08))
		"shadow":
			for i in 3:
				_p(knee, LowPoly.cyl(0.07 * _limb, 0.07 * _limb, 0.02, 7), _m.cloth_dark, Vector3(0, -0.3 - i * 0.035, 0))   # 감은 끈
		"brawler":
			_p(knee, LowPoly.cyl(0.07 * _limb, 0.068 * _limb, 0.07, 7), _m.cream, Vector3(0, -0.36, 0))   # 발목 붕대


## 머리: 얼굴(눈, 눈썹, 코, 귀) + 머리 모양 + 옷차림에 따른 투구/두건/머리띠
func _build_head(style: String, skin: Material, hair: Material, eye: Material) -> void:
	var h := _head
	var m := _m
	var face_hidden := style == "heavy"
	if not face_hidden:
		_body_meshes.append(_p(h, LowPoly.sphere(0.122, 8, 6), skin, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(0.92, 1.06, 1.0)))
		_p(h, LowPoly.cyl(0.1, 0.07, 0.1, 7), skin, Vector3(0, -0.05, -0.012))
		_p(h, LowPoly.prism(Vector3(0.034, 0.05, 0.05)), skin, Vector3(0, 0.0, -0.116), Vector3(-90, 0, 0))
		for s in [-1.0, 1.0]:
			_p(h, LowPoly.box(Vector3(0.032, 0.016, 0.01)), eye, Vector3(0.042 * s, 0.03, -0.112))
			_p(h, LowPoly.box(Vector3(0.046, 0.013, 0.014)), hair, Vector3(0.043 * s, 0.056, -0.114), Vector3(0, 0, -10 * s))
			_p(h, LowPoly.box(Vector3(0.022, 0.048, 0.032)), skin, Vector3(0.112 * s, 0.01, 0.005))
		_p(h, LowPoly.box(Vector3(0.042, 0.008, 0.008)), _mat("lip", build.skin_color().darkened(0.3), 0.7), Vector3(0, -0.058, -0.106))
	var hair_shown := style in ["knight", "lancer", "monk", "brawler"]
	if hair_shown:
		_build_hair(h, hair, style in ["knight", "lancer"])
	match style:
		"knight":
			# 얼굴이 트인 반투구 + 코 가리개
			_p(h, LowPoly.sphere(0.138, 8, 5), m.armor_light, Vector3(0, 0.06, 0.008), Vector3.ZERO, Vector3(1, 0.78, 1.04))
			_p(h, LowPoly.cyl(0.142, 0.142, 0.024, 8), m.armor, Vector3(0, 0.04, 0.008))
			_p(h, LowPoly.box(Vector3(0.024, 0.085, 0.02)), m.armor, Vector3(0, 0.02, -0.135))
			_p(h, LowPoly.box(Vector3(0.026, 0.05, 0.2)), m.cloth, Vector3(0, 0.16, 0.0))
		"heavy":
			# 얼굴을 다 가리는 투구, T 자 틈, 포인트 색 깃털 장식
			_body_meshes.append(_p(h, LowPoly.cyl(0.135, 0.145, 0.24, 8), m.armor_light, Vector3(0, 0.0, 0)))
			_p(h, LowPoly.sphere(0.136, 8, 4), m.armor_light, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
			_p(h, LowPoly.box(Vector3(0.2, 0.025, 0.03)), m.visor, Vector3(0, 0.035, -0.13))
			_p(h, LowPoly.box(Vector3(0.03, 0.1, 0.03)), m.visor, Vector3(0, -0.02, -0.13))
			_p(h, LowPoly.prism(Vector3(0.12, 0.06, 0.04)), m.armor, Vector3(0, -0.09, -0.13), Vector3(180, 0, 0))
			for i in 5:
				_p(h, LowPoly.box(Vector3(0.03, 0.07 - i * 0.008, 0.06)), m.cloth, Vector3(0, 0.2 - i * 0.012, -0.08 + i * 0.05), Vector3(20 + i * 10, 0, 0))
		"rogue":
			# 두건 + 입 가리개 (눈만 보인다)
			_body_meshes.append(_p(h, LowPoly.sphere(0.155, 8, 6), m.cloth_dark, Vector3(0, 0.04, 0.05), Vector3.ZERO, Vector3(1.0, 1.08, 1.12)))
			_p(h, LowPoly.prism(Vector3(0.14, 0.06, 0.1)), m.cloth_dark, Vector3(0, 0.15, -0.07), Vector3(-30, 0, 0))
			_p(h, LowPoly.box(Vector3(0.21, 0.075, 0.09)), m.suit, Vector3(0, -0.055, -0.07))
			_p(h, LowPoly.cyl(0.13, 0.15, 0.08, 8), m.cloth_dark, Vector3(0, -0.13, 0.02))
		"lancer":
			# 가벼운 투구 + 볼 가리개 + 포인트 색 볏
			_p(h, LowPoly.sphere(0.138, 8, 5), m.armor_light, Vector3(0, 0.06, 0.008), Vector3.ZERO, Vector3(1, 0.8, 1.04))
			for s in [-1.0, 1.0]:
				_p(h, LowPoly.box(Vector3(0.02, 0.1, 0.1)), m.armor_light, Vector3(0.125 * s, -0.02, -0.02), Vector3(0, 0, 6 * s))
			_p(h, LowPoly.box(Vector3(0.022, 0.09, 0.28)), m.cloth, Vector3(0, 0.19, 0.02), Vector3(-6, 0, 0))
			_p(h, LowPoly.box(Vector3(0.028, 0.03, 0.3)), m.armor, Vector3(0, 0.15, 0.02))
		"monk":
			# 포인트 색 머리띠 + 뒤로 날리는 끝
			_p(h, LowPoly.cyl(0.128, 0.128, 0.035, 8), m.cloth, Vector3(0, 0.07, 0.0), Vector3(-6, 0, 0))
			_flap(h, Vector3(0.02, 0.07, 0.12), Vector3(0.035, 0.22, 0.012), m.cloth, -1.0, Vector3(40, 0, 10))
			_flap(h, Vector3(-0.02, 0.07, 0.12), Vector3(0.03, 0.17, 0.012), m.cloth, -1.0, Vector3(46, 0, -8))
		"shadow":
			# 머리를 감싼 복면 (눈 둘레만 트임) + 긴 머리띠 끝
			_body_meshes.append(_p(h, LowPoly.sphere(0.132, 8, 6), m.suit, Vector3(0, 0.035, 0.006), Vector3.ZERO, Vector3(0.96, 1.05, 1.02)))
			_p(h, LowPoly.box(Vector3(0.2, 0.085, 0.09)), m.suit, Vector3(0, -0.05, -0.075))
			_p(h, LowPoly.box(Vector3(0.17, 0.02, 0.07)), m.suit, Vector3(0, 0.068, -0.1))
			_p(h, LowPoly.cyl(0.136, 0.136, 0.03, 8), m.cloth, Vector3(0, 0.09, 0.0), Vector3(-5, 0, 0))
			_flap(h, Vector3(0.0, 0.09, 0.13), Vector3(0.035, 0.3, 0.012), m.cloth, -1.0, Vector3(36, 0, 6))


func _build_hair(h: Node3D, hair: Material, under_helm: bool) -> void:
	var style := build.hair
	if style == 3:
		# 민머리: 살짝 짙은 살결만
		_p(h, LowPoly.sphere(0.126, 8, 5), _mat("stubble", build.skin_color().darkened(0.12), 0.8), Vector3(0, 0.045, 0.01), Vector3.ZERO, Vector3(0.95, 0.85, 1.02))
		return
	_p(h, LowPoly.sphere(0.131, 8, 5), hair, Vector3(0, 0.05, 0.014), Vector3.ZERO, Vector3(0.97, 0.86, 1.04))
	if under_helm:
		_p(h, LowPoly.box(Vector3(0.16, 0.06, 0.05)), hair, Vector3(0, -0.02, 0.1))
		return
	match style:
		0:
			# 짧은 머리: 앞머리를 옆으로 넘겼다
			_p(h, LowPoly.box(Vector3(0.2, 0.045, 0.06)), hair, Vector3(0.012, 0.1, -0.085), Vector3(25, 0, -6))
			for s in [-1.0, 1.0]:
				_p(h, LowPoly.box(Vector3(0.02, 0.06, 0.04)), hair, Vector3(0.113 * s, 0.03, -0.035))
		1:
			# 묶은 머리: 정수리 상투 + 뒤로 늘어진 꽁지
			_p(h, LowPoly.box(Vector3(0.19, 0.035, 0.05)), hair, Vector3(0, 0.105, -0.085), Vector3(30, 0, 0))
			_p(h, LowPoly.sphere(0.048, 7, 4), hair, Vector3(0, 0.165, 0.04))
			_p(h, LowPoly.cyl(0.03, 0.03, 0.03, 6), _m.cloth, Vector3(0, 0.13, 0.05))
			_flap(h, Vector3(0, 0.15, 0.07), Vector3(0.05, 0.2, 0.03), hair, -1.0, Vector3(55, 0, 0))
		2:
			# 뻗친 머리: 뒤로 솟은 가시 머리
			for i in 6:
				var a := -0.9 + i * 0.36
				_p(h, LowPoly.prism(Vector3(0.06, 0.12, 0.05)), hair,
						Vector3(sin(a) * 0.07, 0.13 - absf(a) * 0.02, 0.02 + cos(a) * 0.03), Vector3(-55 + absf(a) * 10, 0, -rad_to_deg(a) * 0.6))
			_p(h, LowPoly.prism(Vector3(0.14, 0.06, 0.05)), hair, Vector3(0, 0.11, -0.095), Vector3(-30, 0, 0))
