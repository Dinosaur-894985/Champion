class_name Fx
extends RefCounted
## 눈에 보이는 효과: 칼끼리 부딪힐 때 불꽃, 몸에 맞을 때 먼지 튀김.


## 칼과 칼이 부딪힌 자리에 불꽃을 튀긴다.
static func sparks(world: Node, pos: Vector3, normal: Vector3 = Vector3.UP, amount: int = 26,
		color: Color = Color(1.0, 0.78, 0.35)) -> void:
	var p := _burst(world, pos, amount, 0.32)
	p.direction = normal
	p.spread = 70.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	# 날아가는 방향으로 길쭉한 불똥
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.018, 0.1, 0.018)
	p.mesh = mesh
	p.particle_flag_align_y = true
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	p.material_override = m


## 몸에 맞은 자리에서 작은 조각들이 튄다.
static func impact(world: Node, pos: Vector3, dir: Vector3, color: Color, amount: int = 16) -> void:
	var p := _burst(world, pos, amount, 0.45)
	p.direction = dir
	p.spread = 45.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -9, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 0.04, 0.04)
	p.mesh = mesh
	var m := LowPoly.mat(color)
	p.material_override = m


## 맞는 순간 멈춤(히트스톱): 아주 잠깐 시간을 거의 멈춰 '쿵' 하는 손맛을 준다.
## 무거운 무기일수록 길다 (Weapons.HITSTOP). 다른 느린 화면(쓰러질 때 등)이 시작되면 그걸 덮어쓰지 않는다.
const HITSTOP_SCALE := 0.06
static var _stop_token := 0

static func hitstop(node: Node, seconds: float) -> void:
	if seconds <= 0.0 or not node.is_inside_tree():
		return
	# 이미 더 느린 화면이면(다른 연출 중) 건드리지 않는다
	if Engine.time_scale < HITSTOP_SCALE - 0.001:
		return
	if Engine.time_scale > HITSTOP_SCALE + 0.001 and Engine.time_scale < 0.999:
		return
	_stop_token += 1
	var my := _stop_token
	Engine.time_scale = HITSTOP_SCALE
	await node.get_tree().create_timer(seconds, true, false, true).timeout
	if my == _stop_token and is_equal_approx(Engine.time_scale, HITSTOP_SCALE):
		Engine.time_scale = 1.0


static func _burst(world: Node, pos: Vector3, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	world.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(life + 0.3, false).timeout.connect(p.queue_free)
	return p
