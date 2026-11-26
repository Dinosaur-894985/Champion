class_name Projectile
extends Node3D
## 날아가는 수리검. 플레이어와 AI 가 같이 쓴다.
## 매 프레임 지나간 길을 광선으로 검사해서, 처음 닿은 것에 맞는다.
##   사람(플레이어/AI)  : 근접 공격과 같은 판정 (막기, 튕겨내기, 피하기가 그대로 된다)
##   상자/기둥/허수아비 : take_hit
##   벽과 바닥          : 꽂혀서 잠깐 남았다 사라진다
## 막히면 튕겨 나가 떨어진다. 피하면 그대로 지나간다.

const GRAVITY := 3.0           # 아주 조금 떨어진다 (멀리 던지면 살짝 낮게)
const LIFE := 2.2
const STUCK_LIFE := 1.6
const SPIN := 34.0             # 초당 회전 (라디안)
const AIM_RADIUS := 0.42       # 노린 상대 몸 둘레 이만큼 안을 지나가면 맞는다 (얇은 몸에 너무 깐깐하지 않게)

var velocity := Vector3.ZERO
var thrower: Node3D
var target: Node3D             # 노리는 상대 (조금씩 따라 휜다)
var homing := 0.0              # 초당 방향을 틀어 주는 정도
var info := {}

var _life := LIFE
var _stuck := false
var _bounced := false
var _model: MeshInstance3D
var _ray := PhysicsRayQueryParameters3D.new()
var _hit_any := false


## 수리검 하나를 던진다. dir: 날아갈 방향, info: 맞았을 때 판정 (근접 공격과 같은 모양)
static func launch(world: Node, from: Vector3, dir: Vector3, speed: float, hit_info: Dictionary,
		by: Node3D, aim_at: Node3D = null, homing_power := 0.0) -> Projectile:
	var p := Projectile.new()
	p.velocity = dir.normalized() * speed
	p.thrower = by
	p.target = aim_at
	p.homing = homing_power
	p.info = hit_info.duplicate()
	p.info["projectile"] = true
	world.add_child(p)
	p.global_position = from
	if aim_at != null and aim_at.has_method("on_incoming_object"):
		aim_at.on_incoming_object(p)
	return p


func _ready() -> void:
	_model = MeshInstance3D.new()
	_model.mesh = Weapons.shuriken_mesh()
	var m := LowPoly.mat(Color(0.86, 0.88, 0.92), 0.35, 0.45)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.8, 0.45)
	m.emission_energy_multiplier = 0.6 if info.get("guard", "") == "break" else 0.15
	_model.material_override = m
	_model.scale = Vector3.ONE * 1.35
	add_child(_model)
	_ray.collision_mask = 1 | 2 | 4
	_ray.hit_from_inside = false
	if thrower is CollisionObject3D:
		_ray.exclude = [(thrower as CollisionObject3D).get_rid()]
	_face()


func _face() -> void:
	if velocity.length() > 0.1:
		var up := Vector3.UP if absf(velocity.normalized().y) < 0.95 else Vector3.FORWARD
		look_at(global_position + velocity, up)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _stuck:
		if _life <= 0.0:
			queue_free()
		return
	if _life <= 0.0:
		queue_free()
		return
	if _bounced:
		velocity.y -= 18.0 * delta
	else:
		velocity.y -= GRAVITY * delta
		if homing > 0.0 and is_instance_valid(target) and not bool(target.get("dead")):
			var want := (_aim_point(target) - global_position)
			if want.dot(velocity) > 0.0:   # 이미 지나쳤으면 따라가지 않는다
				var spd := velocity.length()
				velocity = velocity.normalized().slerp(want.normalized(), clampf(homing * delta, 0.0, 1.0)) * spd
	var step := velocity * delta
	var from := global_position
	var to := from + step
	# 노린 상대: 몸 둘레를 지나가면 맞는다 (광선이 얇은 몸을 비껴가는 것을 막는다)
	if not _bounced and is_instance_valid(target) and target != thrower:
		var c := _aim_point(target)
		var cl := Geometry3D.get_closest_point_to_segment(c, from, to)
		if cl.distance_to(c) < AIM_RADIUS and _clear(from, cl):
			global_position = cl
			_strike(target, step.normalized())
			return
	_ray.from = from
	_ray.to = to
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		global_position = to
		_model.rotate_object_local(Vector3.UP, SPIN * delta)
		_face_keep_spin()
		return
	var col: Object = hit.collider
	global_position = hit.position
	if _bounced:
		_stick(hit.normal)
		return
	if col != null and (col.has_method("receive_attack") or col.has_method("take_hit")) and col != thrower:
		_strike(col as Node3D, step.normalized())
	else:
		_stick(hit.normal)


func _face_keep_spin() -> void:
	var spin := _model.transform.basis
	_face()
	_model.transform.basis = spin


func _aim_point(n: Node3D) -> Vector3:
	return n.global_position + Vector3.UP * 1.15


## 앞이 벽에 막혀 있지 않나
func _clear(a: Vector3, b: Vector3) -> bool:
	if a.distance_to(b) < 0.05:
		return true
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	q.exclude = _ray.exclude
	if is_instance_valid(target) and target is CollisionObject3D:
		q.exclude = q.exclude + [(target as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _strike(body: Node3D, dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	var result := ""
	if body.has_method("receive_attack"):
		result = str(body.receive_attack(info, thrower if is_instance_valid(thrower) else self))
	else:
		result = str(body.take_hit(info, flat, thrower))
	if is_instance_valid(thrower) and thrower.has_method("on_projectile_result"):
		thrower.on_projectile_result(result, info, body)
	match result:
		"dodged", "none":
			# 피했다: 그대로 지나간다 (다시 맞지 않게 그 상대는 빼고)
			target = null
			if body is CollisionObject3D:
				_ray.exclude = _ray.exclude + [(body as CollisionObject3D).get_rid()]
			global_position += dir * 0.3
		"blocked", "parried":
			Fx.sparks(get_parent(), global_position, -dir, 14, Color(1.0, 0.85, 0.5))
			_bounced = true
			target = null
			velocity = (-dir * 3.0 + Vector3.UP * 3.5 + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 1.5)
			_life = 1.2
		"crate":
			_stick(-dir)
		_:
			Fx.impact(get_parent(), global_position, dir + Vector3.UP * 0.2, Color(0.75, 0.1, 0.08), 8)
			Audio.play("shuriken_hit", global_position)
			queue_free()


func _stick(normal: Vector3) -> void:
	_stuck = true
	_life = STUCK_LIFE
	Audio.play("shuriken_stick", global_position, -4.0)
	Fx.sparks(get_parent(), global_position, normal, 5, Color(1.0, 0.85, 0.5))
	global_position += normal * 0.02
