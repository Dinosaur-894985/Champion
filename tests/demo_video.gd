extends SceneTree
## 새 경기장 소개 영상용 자동 연출.
## 실행: godot --write-movie 파일.avi --fixed-fps 30 -s res://tests/demo_video.gd
##  1) 기둥을 타고 올라가 경기장을 둘러본다
##  2) 빨간 벽을 따라 벽 달리기
##  3) 지붕 위에서 기다리면 AI 가 벽을 타고 쫓아 올라온다

const GAME := preload("res://scenes/main.tscn")

var _game: Node
var _f := 0
var _part := 1
var _yaw := 0.0
var _pitch := 0.0


func _initialize() -> void:
	Game.next_mode = "practice"
	_game = GAME.instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_f += 1
	match _part:
		1:
			_part1()
		2:
			_part2()
	return false


func _look(p: Player, yaw_deg: float, pitch_deg: float, k: float) -> void:
	_yaw = lerpf(_yaw, yaw_deg, k)
	_pitch = lerpf(_pitch, pitch_deg, k)
	p.rotation.y = deg_to_rad(_yaw)
	p.head.rotation.x = deg_to_rad(_pitch)


func _part1() -> void:
	var p: Player = _game.player
	if _f == 2:
		_game.hud.hide_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		for d in _game.get_children():
			if d is TrainingDummy:
				d.queue_free()
		p.global_position = Vector3(10, 0.1, -3.0)
		_yaw = 0.0
		_pitch = 8.0
	if _f < 2:
		return
	if _f == 8:
		Input.action_press("move_forward")
		Input.action_press("sprint")
	if _f == 22:
		Input.action_release("sprint")
		Input.action_press("jump")
	if _f == 24:
		Input.action_release("jump")
	if _f < 70:
		_look(p, 0.0, 25.0 if p.sm.state == "climb" else 8.0, 0.08)
	if p.is_on_floor() and p.global_position.y > 5.5:
		Input.action_release("move_forward")
	if _f >= 70 and _f < 160:
		# 꼭대기에서 경기장을 한 바퀴 둘러본다
		_look(p, 0.0 + (_f - 70) * 2.2, -18.0, 0.2)
	if _f == 160:
		# 동쪽 빨간 벽 옆에서 벽 달리기
		p.global_position = Vector3(4.5, 0.1, 24.0)
		p.velocity = Vector3.ZERO
		_yaw = 0.0
		_pitch = 0.0
		p.rotation.y = 0.0
		p.head.rotation.x = 0.0
	if _f == 162:
		Input.action_press("move_forward")
		Input.action_press("sprint")
	if _f == 172:
		Input.action_press("move_right")
		Input.action_press("jump")
	if _f == 174:
		Input.action_release("jump")
	if _f == 200:
		Input.action_release("move_right")
	if _f == 215:
		for a in ["move_forward", "sprint", "move_right"]:
			Input.action_release(a)
	if _f == 240:
		_game.queue_free()
		Game.next_mode = "duel"
		_game = GAME.instantiate()
		root.add_child(_game)
		_part = 2
		_f = 0


var _arrived := -1


func _part2() -> void:
	var p: Player = _game.player
	var ai: Duelist = _game.duelist
	if _f == 2:
		_game.hud.hide_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		p.hp = 100000
		p.global_position = Vector3(-19.0, 4.3, -1.0)
		_yaw = -90.0
		_pitch = -12.0
		_look(p, -90.0, -12.0, 1.0)
	if _f < 3:
		return
	# AI 를 눈으로 따라간다
	var to := ai.global_position + Vector3.UP * 1.2 - p.camera.global_position
	var yaw := rad_to_deg(atan2(-to.x, -to.z))
	var pitch := rad_to_deg(atan2(to.y, Vector2(to.x, to.z).length()))
	while yaw - _yaw > 180.0:
		yaw -= 360.0
	while yaw - _yaw < -180.0:
		yaw += 360.0
	_look(p, yaw, clampf(pitch, -40.0, 10.0), 0.1)
	if _arrived < 0 and ai.global_position.y > 3.9:
		_arrived = _f
	if _arrived > 0:
		var since := _f - _arrived
		# 올라오면 막고 받아친다
		var threat := ai.state == "windup"
		if threat:
			Input.action_press("block")
		elif ai.state != "strike":
			Input.action_release("block")
		if ai.state in ["recover", "stagger"] and since % 6 == 0:
			p._request_attack("combo")
		if since > 150:
			quit()
	if _f > 900:
		quit()
