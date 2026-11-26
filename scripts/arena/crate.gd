class_name ArenaCrate
extends RigidBody3D
## 나무 상자. 경기장 여기저기 놓여 있다.
##   칼로 치면 친 쪽으로 날아간다 (강한 공격일수록 멀리).
##   달리거나 슬라이딩하며 부딪히면 걷어차인다.
##   F 로 들어 올려 던질 수 있다 (플레이어).
## 날아가는 상자에 맞으면 피해를 입고 휘청인다. 막을 수 있다 (어느 방향으로 막아도 된다).
## 사람에게 맞으면 부서지고, 조금 뒤 처음 자리에 다시 생긴다.
##
## 충돌 층: 2(칼에 맞는 것, AI 몸과 같은 층) + 4(상자끼리). 1(벽/바닥)과 부딪힌다.
## AI 는 충돌 4 를 보고 상자와 부딪힌다. 길찾기 광선(층 1)에는 보이지 않는다.

const SIZE := 0.85
const THROW_SPEED := 17.0
const HIT_SPEED := 5.0          # 이보다 빠르게 날아갈 때만 사람을 다치게 한다
const DAMAGE := 12
const RESPAWN := 9.0
const STRONG := ["heavy", "charge", "slash3", "spin", "cleave", "pierce", "run_thrust", "wall_slash", "special", "plunge"]

var arena: Node3D
var home := Vector3.ZERO
var thrower: Node3D = null      # 마지막으로 차거나 던진 사람 (그 사람은 맞지 않는다)
var _armed := 0.0               # 남은 '위험한' 시간
var _held_by: Node3D = null
var _gone := 0.0                # 부서진 뒤 다시 생길 때까지
var _kick_cd := 0.0
var _warned := {}
var _visual: Node3D


func setup(at: Vector3, mats: Dictionary) -> void:
	home = at
	position = at
	mass = 6.0
	collision_layer = 2 | 4
	collision_mask = 1 | 2 | 4
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.15
	pm.friction = 0.8
	physics_material_override = pm
	linear_damp = 0.2
	angular_damp = 1.5
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * SIZE
	col.shape = shape
	add_child(col)
	_visual = Node3D.new()
	add_child(_visual)
	var wood := LowPoly.mat(Color(0.64, 0.45, 0.27), 0.85)
	var dark := LowPoly.mat(Color(0.38, 0.25, 0.15), 0.9)
	var band: Material = mats.get("coral", dark)
	LowPoly.part(_visual, LowPoly.box(Vector3.ONE * (SIZE - 0.04)), wood, Vector3.ZERO, Vector3.ZERO, 0.02, hash(at))
	# 테두리 각목과 띠
	for ax in 3:
		for a in [-1.0, 1.0]:
			for b in [-1.0, 1.0]:
				var p := Vector3.ZERO
				var sz := Vector3.ONE * 0.09
				var e := SIZE * 0.5 - 0.03
				match ax:
					0:
						p = Vector3(0, a * e, b * e)
						sz.x = SIZE
					1:
						p = Vector3(a * e, 0, b * e)
						sz.y = SIZE
					2:
						p = Vector3(a * e, b * e, 0)
						sz.z = SIZE
				LowPoly.part(_visual, LowPoly.box(sz), dark, p)
	LowPoly.part(_visual, LowPoly.box(Vector3(SIZE + 0.02, 0.1, SIZE + 0.02)), band, Vector3(0, 0.05, 0))
	# 대각선 덧댐 (앞뒤)
	for z in [-1.0, 1.0]:
		var d := LowPoly.part(_visual, LowPoly.box(Vector3(0.08, SIZE * 1.2, 0.04)), dark, Vector3(0, 0, z * (SIZE * 0.5 - 0.01)))
		d.rotation.z = deg_to_rad(45)
	# 조각 16개를 한 덩어리로 (웹 버전이 그릴 물체 수를 줄인다)
	LowPoly.merge_children(_visual)


func _physics_process(delta: float) -> void:
	_kick_cd = maxf(_kick_cd - delta, 0.0)
	if _gone > 0.0:
		_gone -= delta
		if _gone <= 0.0:
			_respawn()
		return
	if _held_by != null:
		return
	if global_position.y < -20.0:
		_break_apart(false)
		return
	if _armed <= 0.0:
		return
	_armed -= delta
	var v := linear_velocity
	if v.length() < HIT_SPEED:
		if is_on_ground():
			_armed = 0.0
			thrower = null
		return
	if arena == null:
		return
	for f in arena.get("fighters"):
		var n := f as Node3D
		if n == null or not is_instance_valid(n) or n == thrower or n.get("dead"):
			continue
		var center := n.global_position + Vector3.UP * 0.9
		var to := center - global_position
		# 다가오고 있으면 미리 알려 준다 (AI 가 막거나 피할 수 있게)
		if not _warned.has(n.get_instance_id()) and to.length() < 6.0 and v.normalized().dot(to.normalized()) > 0.8:
			_warned[n.get_instance_id()] = true
			if n.has_method("on_incoming_object"):
				n.on_incoming_object(self)
		if absf(to.y) < 1.1 and Vector2(to.x, to.z).length() < SIZE * 0.5 + 0.55:
			_hit_fighter(n, v)
			return


func is_on_ground() -> bool:
	return get_contact_count() > 0 or absf(linear_velocity.y) < 0.2


func _hit_fighter(n: Node3D, v: Vector3) -> void:
	var dir := Vector3(v.x, 0, v.z).normalized()
	var info := {"move": "crate", "damage": DAMAGE + int(clampf(v.length() - 10.0, 0.0, 8.0)), "react": "stagger",
			"guard": "normal", "dir": "", "pressure": 1.4, "push_add": 1.5}
	var result := ""
	if n.has_method("receive_attack"):
		result = n.receive_attack(info, self)
	elif n.has_method("take_hit"):
		result = n.take_hit(info, dir, self)
	if thrower != null and is_instance_valid(thrower) and result in ["hit", "guard_broken", "wrong_guard"]:
		if thrower.has_method("add_gauge"):
			thrower.add_gauge(info.damage * Weapons.GAUGE.dealt)
		if thrower.has_signal("combat_event"):
			thrower.emit_signal("combat_event", "상자 명중!", Color(1.0, 0.8, 0.4))
	Audio.play("hit_big", global_position)
	_break_apart(true)


## 칼에 맞았다: 친 쪽으로 날아간다
func take_hit(info: Dictionary, dir: Vector3, attacker: Node3D = null) -> String:
	if _gone > 0.0 or _held_by != null:
		return "none"
	var strong := str(info.get("move", "")) in STRONG
	var d := Vector3(dir.x, 0, dir.z).normalized()
	if attacker != null and is_instance_valid(attacker):
		# 칼을 휘두른 사람이 보는 쪽으로 (조준이 쉽게)
		var look := -attacker.global_transform.basis.z
		look.y = 0
		if look.length() > 0.1:
			d = d.lerp(look.normalized(), 0.6).normalized()
	kick(d * (16.0 if strong else 13.0) + Vector3.UP * (3.0 if strong else 2.4), attacker)
	Audio.play("pillar_crack", global_position, -3.0, 1.35)
	return "crate"


func can_kick() -> bool:
	return _gone <= 0.0 and _held_by == null and _kick_cd <= 0.0


func can_pick() -> bool:
	return _gone <= 0.0 and _held_by == null and _armed <= 0.0


## 차서 날린다 (velocity: 날아가는 속도)
func kick(vel: Vector3, by: Node3D) -> void:
	if not can_kick():
		return
	freeze = false
	sleeping = false
	linear_velocity = vel
	# 날아가는 쪽으로 앞구르듯 돈다 (매번 같게: 맞히기 쉽게)
	var spin_axis := Vector3.UP.cross(Vector3(vel.x, 0, vel.z).normalized())
	angular_velocity = spin_axis * 7.0
	thrower = by
	_armed = 1.4
	_warned.clear()
	_kick_cd = 0.15
	Fx.sparks(get_parent(), global_position, -vel.normalized(), 8, Color(0.85, 0.7, 0.45))


## 걸어서 밀었다: 위험하지 않게 살짝 밀린다
func nudge(vel: Vector3) -> void:
	if _held_by != null or _gone > 0.0:
		return
	sleeping = false
	apply_central_impulse(Vector3(vel.x, 0, vel.z) * mass * 0.15)


func pick_up(by: Node3D) -> void:
	_held_by = by
	freeze = true
	collision_layer = 0
	collision_mask = 0


func throw_from(at: Vector3, vel: Vector3, by: Node3D) -> void:
	_held_by = null
	collision_layer = 2 | 4
	collision_mask = 1 | 2 | 4
	global_position = at
	freeze = false
	_kick_cd = 0.0
	if by == null:
		linear_velocity = vel
		return
	kick(vel, by)


func is_held() -> bool:
	return _held_by != null


func _break_apart(effect: bool) -> void:
	if effect:
		Fx.impact(get_parent(), global_position, Vector3.UP, Color(0.64, 0.45, 0.27), 26)
		Audio.play("pillar_break", global_position, -4.0, 1.6)
	_gone = RESPAWN
	_armed = 0.0
	thrower = null
	visible = false
	freeze = true
	collision_layer = 0
	collision_mask = 0
	global_position = home + Vector3.DOWN * 50.0


func _respawn() -> void:
	# 처음 자리의 바닥이 무너졌으면 다시 생기지 않는다
	var q := PhysicsRayQueryParameters3D.create(home + Vector3.UP * 0.5, home + Vector3.DOWN * 1.5, 1)
	if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		_gone = RESPAWN
		return
	global_position = home
	rotation = Vector3.ZERO
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = 2 | 4
	collision_mask = 1 | 2 | 4
	visible = true
	freeze = false
	_visual.scale = Vector3.ONE * 0.2
	create_tween().tween_property(_visual, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
