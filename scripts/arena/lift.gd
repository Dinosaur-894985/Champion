class_name ArenaLift
extends AnimatableBody3D
## 오르내리는 발판. 바닥과 높은 다리 사이를 천천히 오간다.
## 내려올 때 밑에 누가 서 있으면 깔리지 않게 잠깐 멈춘다.
## 위치(position.y)는 발판 윗면 높이다.

const SIZE := 2.4
const THICK := 0.0           # 바닥에 있을 때 윗면 높이 (바닥과 같아서 그냥 걸어서 올라탄다)

var bottom_y := 0.0
var top_y := 6.5
var wait_time := 2.6
var travel_time := 2.6
var fighters: Array = []     # 밑에 깔리는지 볼 몸들

var phase := "bottom"        # bottom, up, top, down
var _t := 0.0


func setup(center: Vector3, top: float, mats: Dictionary, start_phase: String = "bottom") -> void:
	position = Vector3(center.x, bottom_y + THICK, center.z)
	top_y = top
	phase = start_phase
	if phase == "top":
		position.y = top_y
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = true
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(SIZE, 0.5, SIZE)
	col.shape = shape
	col.position.y = -0.25
	add_child(col)
	# 모양: 두꺼운 판 + 금색 테두리 + 위를 가리키는 화살표
	# 바닥에 내려와 있을 때 바닥 타일과 겹쳐 깜빡이지 않도록 모양은 조금 위로 띄운다
	LowPoly.part(self, LowPoly.box(Vector3(SIZE, 0.5, SIZE)), mats.navy, Vector3(0, -0.235, 0))
	LowPoly.part(self, LowPoly.box(Vector3(SIZE - 0.5, 0.02, SIZE - 0.5)), mats.stone2, Vector3(0, 0.022, 0))
	for s in [-1.0, 1.0]:
		LowPoly.part(self, LowPoly.box(Vector3(SIZE + 0.04, 0.06, 0.14)), mats.gold, Vector3(0, 0.0, s * SIZE * 0.5))
		LowPoly.part(self, LowPoly.box(Vector3(0.14, 0.06, SIZE + 0.04)), mats.gold, Vector3(s * SIZE * 0.5, 0.0, 0))
	var arrow := LowPoly.part(self, LowPoly.prism(Vector3(0.8, 0.7, 0.02)), mats.gold, Vector3(0, 0.035, 0), Vector3(-90, 0, 0))
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func surface_y() -> float:
	return position.y


func center() -> Vector3:
	return Vector3(position.x, position.y, position.z)


## 지금 y 높이에 멈춰 서 있고, 잠시 더 머무르나 (AI 가 올라탈지 정할 때)
func resting_at(y: float, margin: float = 0.7) -> bool:
	if phase == "bottom" and absf(y - (bottom_y + THICK)) < 0.6:
		return _t < wait_time - margin
	if phase == "top" and absf(y - top_y) < 0.6:
		return _t < wait_time - margin
	return false


func _physics_process(delta: float) -> void:
	var before := position.y
	_step(delta)
	if absf(position.y - before) > 0.0001:
		_carry(before)


## 위에 서 있는 몸을 발판과 함께 옮긴다 (물리 엔진에만 맡기면 발판이 몸을 뚫고 지나갈 때가 있다)
func _carry(before: float) -> void:
	for f in fighters:
		if not is_instance_valid(f):
			continue
		var body := f as CharacterBody3D
		var p := body.global_position
		if absf(p.x - position.x) > SIZE * 0.5 + 0.1 or absf(p.z - position.z) > SIZE * 0.5 + 0.1:
			continue
		if p.y < before - 0.3 or p.y > before + 0.25 or body.velocity.y > 1.5:
			continue
		body.global_position.y = position.y + 0.002
		if body.velocity.y < 0.0:
			body.velocity.y = 0.0


func _step(delta: float) -> void:
	_t += delta
	var low := bottom_y + THICK
	match phase:
		"bottom":
			position.y = low
			if _t >= wait_time:
				_go("up")
		"up":
			position.y = lerpf(low, top_y, smoothstep(0.0, 1.0, _t / travel_time))
			if _t >= travel_time:
				_go("top")
		"top":
			position.y = top_y
			if _t >= wait_time:
				_go("down")
		"down":
			if position.y > bottom_y + 0.8 and _someone_below():
				_t -= delta
				return
			position.y = lerpf(top_y, low, smoothstep(0.0, 1.0, _t / travel_time))
			if _t >= travel_time:
				_go("bottom")


func _go(p: String) -> void:
	phase = p
	_t = 0.0


func _someone_below() -> bool:
	for f in fighters:
		if not is_instance_valid(f):
			continue
		var p: Vector3 = (f as Node3D).global_position
		if absf(p.x - position.x) < SIZE * 0.5 + 0.4 and absf(p.z - position.z) < SIZE * 0.5 + 0.4 \
				and p.y < position.y - 0.3 and p.y > position.y - 2.4:
			return true
	return false
