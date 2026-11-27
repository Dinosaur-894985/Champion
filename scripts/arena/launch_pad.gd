class_name LaunchPad
extends Node3D
## 바람 발판: 밟으면 바람이 솟구쳐 정해진 곳(높은 기둥 꼭대기, 경기장 한가운데 등)으로 높이 날려 보낸다.
## 날아가는 동안 클릭하면 그대로 낙하 찍기나 공중 베기로 이어진다 (Player._vertical_attack).
## 플레이어와 AI 가 똑같이 쓴다. 날아가는 몸은 launch(속도) 를 받아 그 궤적을 그대로 따른다.
## 발판 자리는 길찾기에서 '지나가는 바닥'이 아니라서, AI 는 일부러 탈 때만 밟는다 (Arena 의 "launch" 길).

const RADIUS := 1.0
const COOLDOWN := 1.0        # 내려선 뒤 다시 날아오르기까지

var id := ""
var target := Vector3.ZERO   # 내려앉는 곳 (발 높이)
var apex := 8.0              # 궤적 꼭대기 높이 (바닥 기준)
var fighters: Array = []
var _cool := {}              # 몸 -> 남은 시간
var _gusts: Array[MeshInstance3D] = []
var _t := 0.0


func setup(pad_id: String, center: Vector3, to: Vector3, apex_y: float, mats: Dictionary) -> void:
	id = pad_id
	position = center
	target = to
	apex = apex_y
	var dir := Vector3(to.x - center.x, 0, to.z - center.z)
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	# 받침: 낮은 원판 (바닥 타일과 겹쳐 깜빡이지 않게 윗면을 조금 띄운다)
	LowPoly.part(self, LowPoly.cyl(RADIUS + 0.25, RADIUS + 0.35, 0.14, 10), mats.navy, Vector3(0, 0.07, 0))
	LowPoly.part(self, LowPoly.cyl(RADIUS, RADIUS, 0.04, 10), mats.teal, Vector3(0, 0.16, 0))
	LowPoly.part(self, LowPoly.cyl(0.34, 0.34, 0.04, 8), mats.gold, Vector3(0, 0.19, 0))
	# 날아갈 쪽을 가리키는 금색 화살표 두 개
	var yaw := atan2(dir.x, dir.z)
	for k in 2:
		var arrow := LowPoly.part(self, LowPoly.prism(Vector3(0.6, 0.42, 0.03)), mats.gold,
				dir * (0.45 + k * 0.38) + Vector3.UP * 0.2, Vector3(90, rad_to_deg(yaw), 0))
	# 솟구치는 바람: 반투명 고리가 위로 올라가며 사라진다 (움직이니 합치지 않는다)
	for k in 3:
		var g := MeshInstance3D.new()
		var m := TorusMesh.new()
		m.inner_radius = RADIUS * 0.78
		m.outer_radius = RADIUS * 0.9
		m.rings = 12
		m.ring_segments = 4
		g.mesh = m
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.cull_mode = BaseMaterial3D.CULL_DISABLED
		gm.albedo_color = Color(0.75, 1.0, 0.95, 0.0)
		g.material_override = gm
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		_gusts.append(g)
	# 움직이지 않는 부분은 하나로 합친다 (웹 버전이 그릴 물체 수를 줄인다)
	LowPoly.merge_children(self, false, _gusts)


## 이 발판에서 target 으로 가는 처음 속도 (중력만 받아 날아간다)
func launch_velocity(from: Vector3, gravity: float) -> Vector3:
	var top := maxf(apex, maxf(from.y, target.y) + 1.5)
	var vy := sqrt(2.0 * gravity * (top - from.y))
	var t := vy / gravity + sqrt(2.0 * (top - target.y) / gravity)
	var flat := Vector3(target.x - from.x, 0, target.z - from.z)
	return flat / t + Vector3.UP * vy


## 날아가는 데 걸리는 시간 (AI 가 공중에서 기다릴 때)
func flight_time(gravity: float) -> float:
	var top := maxf(apex, target.y + 1.5)
	return sqrt(2.0 * top / gravity) + sqrt(2.0 * (top - target.y) / gravity)


func _process(delta: float) -> void:
	_t += delta
	for k in _gusts.size():
		var g := _gusts[k]
		var f := fmod(_t * 0.9 + k / 3.0, 1.0)
		g.position.y = 0.25 + f * 2.6
		var s := 1.0 - f * 0.35
		g.scale = Vector3(s, 1, s)
		(g.material_override as StandardMaterial3D).albedo_color.a = 0.45 * sin(f * PI)


func _physics_process(delta: float) -> void:
	for f in fighters:
		if not is_instance_valid(f):
			continue
		var body := f as CharacterBody3D
		var cd: float = maxf(float(_cool.get(body, 0.0)) - delta, 0.0)
		_cool[body] = cd
		if cd > 0.0 or not body.is_on_floor() or bool(body.get("dead")):
			continue
		var p := body.global_position
		if Vector2(p.x - global_position.x, p.z - global_position.z).length() > RADIUS or absf(p.y - global_position.y) > 0.5:
			continue
		var g: float = body.get("_gravity")
		_cool[body] = COOLDOWN + flight_time(g)
		body.call("launch", launch_velocity(p + Vector3.UP * 0.05, g))
		Audio.play("double_jump", global_position, 2.0, 0.7)
		Fx.sparks(get_parent(), global_position + Vector3.UP * 0.3, Vector3.UP, 22, Color(0.7, 1.0, 0.95))
