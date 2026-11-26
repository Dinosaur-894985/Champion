class_name BodyRig
extends Node3D
## 3인칭 몸(로우폴리)과 몸 움직임.
## 움직임은 세 겹(레이어)으로 나눠서 각자 계산한 뒤 합친다.
##   1) 아래 몸: 걷기, 옆걸음, 뒷걸음, 대시 — 실제로 움직이는 방향과 빠르기로 정해진다
##   2) 위 몸: 팔과 칼 자세, 허리 비틀기, 숙이기 — 지금 하는 행동(공격/막기)이 정한다
##   3) 덧붙이는 흔들림: 맞았을 때 젖혀짐, 힘 모을 때 떨림 — 위 둘에 더해진다
## 그래서 "걸으면서 베기", "옆으로 대시하며 막기", "공격하다 움찔" 같은 조합이 따로 만들지 않아도 된다.

const WALK_REF_SPEED := 3.9

var blade_tip: Node3D
var blade_mat: StandardMaterial3D
## 들고 있는 무기 (Weapons.WEAPONS). 씬에 넣기 전에 정한다.
var weapon := "sword"

# 부품
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_r: Node3D
var _wrist: Node3D
var _arm_l: Node3D
var _torso: Node3D
var _head: Node3D
var _flash_mat: StandardMaterial3D
var _body_meshes: Array[MeshInstance3D] = []

# 2) 위 몸 목표 자세
var _shoulder_target := Vector3(55, -15, 0)
var _wrist_target := Vector3.ZERO
var _twist_target := 0.0
var _lean_target := 0.0
var _pose_speed := 12.0

# 3) 덧붙이는 흔들림
var _kick := Vector3.ZERO        # 맞아서 젖혀진 각도 (라디안)
var _kick_vel := Vector3.ZERO
var tremble := 0.0               # 0~1, 힘 모을 때 떨림
var reach := 0.0                 # 0~1, 잡으려고 왼손을 앞으로 뻗기
var _flash := 0.0

var _walk_phase := 0.0
var _dash_amt := 0.0
var _dash_local := Vector3.ZERO
var _reach_amt := 0.0
const REACH_ANGLE := -1.45
var low := 0.0                   # 0~1, 낮게 미끄러지기 (다리 베기)
var _low_amt := 0.0
var frozen := false              # 쓰러진 뒤에는 움직임을 멈춘다


func _ready() -> void:
	_build()


# ---------------- 자세 지시 ----------------

## pose = [어깨 회전(도), 손목 회전(도), 허리 비틀기, 숙이기]
func set_pose(pose: Array, speed: float = 12.0) -> void:
	_shoulder_target = pose[0]
	_wrist_target = pose[1]
	_twist_target = pose[2]
	_lean_target = pose[3]
	_pose_speed = speed


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
	var k := clampf(delta * _pose_speed, 0, 1)

	# 1) 아래 몸: 앞뒤로는 다리를 흔들고, 옆으로는 다리를 벌리며 게걸음
	var speed := Vector2(local_vel.x, local_vel.z).length()
	_walk_phase += delta * speed * 3.2
	var amt := clampf(speed / WALK_REF_SPEED, 0.0, 1.0)
	var fwd_part := 0.0
	var side_part := 0.0
	if speed > 0.05:
		fwd_part = -local_vel.z / speed
		side_part = local_vel.x / speed
	var swing := sin(_walk_phase) * amt * 0.6
	_dash_amt = maxf(_dash_amt - delta * 4.0, 0.0)
	var d := _dash_amt * _dash_amt
	var fa := absf(fwd_part)
	_leg_l.rotation.x = swing * fa - _dash_local.z * d * 0.6
	_leg_r.rotation.x = -swing * fa + _dash_local.z * d * 0.3
	var step := sin(_walk_phase) * amt * side_part * 0.3
	_leg_l.rotation.z = -step - d * 0.35
	_leg_r.rotation.z = step + d * 0.35
	_reach_amt = lerpf(_reach_amt, reach, clampf(delta * 14.0, 0, 1))
	_arm_l.rotation.x = lerpf(deg_to_rad(20) - swing * 0.6 * absf(fwd_part), REACH_ANGLE, _reach_amt)

	# 2) 위 몸: 팔과 허리를 목표 자세로
	_arm_r.rotation_degrees = _arm_r.rotation_degrees.lerp(_shoulder_target, k)
	_wrist.rotation_degrees = _wrist.rotation_degrees.lerp(_wrist_target, k)
	var tk := clampf(delta * 10.0, 0, 1)
	var lean := -_lean_target - d * (-_dash_local.z) * 0.25
	var roll := -d * _dash_local.x * 0.3

	# 3) 덧붙이는 흔들림: 스프링처럼 젖혀졌다 돌아온다
	_kick_vel += (-_kick * 140.0 - _kick_vel * 14.0) * delta
	_kick += _kick_vel * delta
	var shake := Vector3.ZERO
	if tremble > 0.0:
		var t := Time.get_ticks_msec() * 0.07
		shake = Vector3(sin(t * 1.3), sin(t * 1.7), sin(t * 2.1)) * tremble * 0.035

	_torso.rotation.x = lerpf(_torso.rotation.x, lean, tk) + _kick.x * 0.4
	_torso.rotation.y = lerpf(_torso.rotation.y, _twist_target, clampf(delta * 12.0, 0, 1))
	_torso.rotation.z = lerpf(_torso.rotation.z, roll, tk) + _kick.z * 0.4
	_head.rotation = Vector3(_kick.x * 0.6, 0, _kick.z * 0.6)
	_arm_r.rotation += shake
	# 미끄러질 때: 몸을 낮추고 뒤로 젖히며 한쪽 다리를 앞으로 뻗는다
	_low_amt = lerpf(_low_amt, low, clampf(delta * 12.0, 0, 1))
	if _low_amt > 0.01:
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, -1.35, _low_amt)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.6, _low_amt)
	rotation.x = _low_amt * 0.35
	position = Vector3(0, -_low_amt * 0.55, _kick.x * -0.08)

	# 맞으면 번쩍
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 7.0, 0.0)
		_flash_mat.albedo_color.a = _flash * 0.8
		for m in _body_meshes:
			m.material_overlay = _flash_mat if _flash > 0.0 else null


## 쓰러지기
func fall(local_dir: Vector3) -> void:
	frozen = true
	glow(blade_mat.emission, 0.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "rotation:x", -PI * 0.47 * signf(-local_dir.z if absf(local_dir.z) > 0.1 else 1.0), 0.7) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:y", 0.15, 0.7)


# ---------------- 몸 만들기 ----------------

func _build() -> void:
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

	# 다리
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(0.13 * side, 0.92, 0)
		add_child(leg)
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
	add_child(_torso)
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
	_head = Node3D.new()
	_head.position = Vector3(0, 0.86, 0)
	_torso.add_child(_head)
	_body_meshes.append(LowPoly.part(_head, LowPoly.sphere(0.15, 8, 6), armor, Vector3(0, 0.05, 0), Vector3.ZERO, 0.004, s + 1))
	LowPoly.part(_head, LowPoly.box(Vector3(0.2, 0.045, 0.05)), visor, Vector3(0, 0.06, -0.135))
	LowPoly.part(_head, LowPoly.box(Vector3(0.04, 0.1, 0.3)), cloth, Vector3(0, 0.2, 0.0))
	LowPoly.part(_head, LowPoly.cyl(0.08, 0.1, 0.08, 7), armor_light, Vector3(0, -0.1, 0))

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
	_arm_r.rotation_degrees = _shoulder_target
	_torso.add_child(_arm_r)
	LowPoly.part(_arm_r, LowPoly.cyl(0.06, 0.065, 0.3, 6), armor, Vector3(0, -0.15, 0))
	LowPoly.part(_arm_r, LowPoly.cyl(0.05, 0.06, 0.28, 6), cloth_dark, Vector3(0, -0.43, 0))
	_wrist = Node3D.new()
	_wrist.position = Vector3(0, -0.6, 0)
	_arm_r.add_child(_wrist)
	LowPoly.part(_wrist, LowPoly.sphere(0.055, 6, 4), leather, Vector3.ZERO)
	# 무기는 손에서 앞(-Z)으로 뻗는다. 모양은 Weapons.build_model (+Y 로 뻗는 모양을 눕혀서 붙인다)
	var holder := Node3D.new()
	holder.rotation_degrees = Vector3(-90, 0, 0)
	if weapon == "spear":
		holder.position = Vector3(0, 0, 0.35)   # 긴 자루는 뒤로도 나온다
	_wrist.add_child(holder)
	var model := Weapons.build_model(holder, weapon)
	blade_mat = model.mat
	blade_mat.emission = Color(1.0, 0.5, 0.1)
	blade_tip = model.tip
	if weapon == "daggers":
		# 왼손에도 단검 하나
		var lh := Node3D.new()
		lh.position = Vector3(0, -0.6, 0)
		lh.rotation_degrees = Vector3(-70, 0, 0)
		_arm_l.add_child(lh)
		Weapons.build_model(lh, weapon, true)

	for m in find_children("*", "MeshInstance3D", true, false):
		if not _body_meshes.has(m):
			_body_meshes.append(m)
