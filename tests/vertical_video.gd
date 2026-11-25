extends SceneTree
## 입체 경기장 소개 영상용 자동 연출.
## 실행: godot --write-movie 파일.avi --fixed-fps 30 -s res://tests/vertical_video.gd
##  1) 동쪽 탑에서 짚라인을 타고 가운데로 → 줄을 놓으며 아래 상대에게 낙하 찍기
##  2) 가장자리의 상대를 내려찍기(Q)로 날려 낭떠러지로 떨어뜨린다
##  3) 상대(AI)가 오르내리는 발판을 타고 다리 위까지 쫓아온다
##  4) 시간이 되면 바깥 바닥이 무너진다

const GAME := preload("res://scenes/main.tscn")

var _game: Node
var _f := 0
var _part := 0
var _yaw := 0.0
var _pitch := 0.0
var _v := {}


func _initialize() -> void:
	seed(11)
	Game.opponent_mode = "preset"
	Game.opponent_preset = "검객"
	Game.test_player_build = CharacterBuild.new()
	_next()


func _next() -> void:
	if _game:
		_game.queue_free()
	_part += 1
	_f = 0
	_v = {}
	if _part > 4:
		quit()
		return
	Game.current_opponent = null
	Game.next_mode = "duel"
	_game = GAME.instantiate()
	root.add_child(_game)


func _look(p: Player, yaw_deg: float, pitch_deg: float, k: float) -> void:
	_yaw = lerpf(_yaw, yaw_deg, k)
	_pitch = lerpf(_pitch, pitch_deg, k)
	p.rotation.y = deg_to_rad(_yaw)
	p.head.rotation.x = deg_to_rad(_pitch)


func _process(_delta: float) -> bool:
	if _part > 4:
		return false
	var p: Player = _game.player
	var ai: Duelist = _game.duelist
	if not p.controls_enabled:
		# 시작 신호 동안에도 화면은 보여준다 (처음 장면 자리를 미리 잡는다)
		_setup_part(p, ai)
		return false
	_f += 1
	p.hp = 1000
	match _part:
		1:
			_part1(p, ai)
		2:
			_part2(p, ai)
		3:
			_part3(p, ai)
		4:
			_part4(p, ai)
	return false


func _setup_part(p: Player, ai: Duelist) -> void:
	p.max_hp = 1000
	match _part:
		1:
			p.global_position = Vector3(14.6, 6.6, 1.5)
			_yaw = 90.0
			_pitch = -12.0
			ai.global_position = Vector3(-0.8, 0.1, 0.3)
		2:
			p.global_position = Vector3(0, 0.1, 22.6)
			_yaw = 180.0
			_pitch = -4.0
			ai.global_position = Vector3(0, 0.1, 24.5)
		3:
			p.global_position = Vector3(-3.5, 6.6, 7.2)
			_yaw = -95.0
			_pitch = -30.0
			ai.global_position = Vector3(4, 0.1, 12)
		4:
			p.global_position = Vector3(-7, 6.6, 7)
			_yaw = 160.0
			_pitch = -24.0
			ai.global_position = Vector3(5, 0.1, -3)
	p.velocity = Vector3.ZERO
	ai.velocity = Vector3.ZERO
	_look(p, _yaw, _pitch, 1.0)


# 1) 짚라인 → 낙하 찍기
func _part1(p: Player, ai: Duelist) -> void:
	if _f < 60:
		ai.active = false
		ai.global_position = Vector3(-0.8, 0.1, 0.3)
		ai.rotation.y = deg_to_rad(-90)
	if _f == 60:
		ai.active = true
	_look(p, 90.0, -12.0 if p.sm.state != "zip" else -28.0, 0.08)
	if _f == 12:
		Input.action_press("jump")
	if _f == 14:
		Input.action_release("jump")
	if p.sm.state == "zip" and p.global_position.x < 1.6 and not _v.has("drop"):
		_v.drop = true
		_pitch = -45.0
		p.head.rotation.x = deg_to_rad(-45)
		p._request_attack("combo")
	if _f > 150:
		_look(p, 90.0, -8.0, 0.1)
	if _f == 210:
		_next()


# 2) 가장자리 밀어 떨어뜨리기
func _part2(p: Player, ai: Duelist) -> void:
	if _f < 20:
		ai.active = false
		ai.global_position = Vector3(0, 0.1, 24.6)
		ai.rotation.y = 0.0
	if _f == 24:
		p._request_attack("heavy")
	if _f > 40:
		_look(p, 180.0, -32.0, 0.05)
	if _f == 130:
		ai.active = true
		_next()


# 3) AI 가 발판을 타고 올라온다
func _part3(p: Player, ai: Duelist) -> void:
	ai.traits["wall_climb"] = false
	ai.skills._cd["grapple"] = 999.0
	p.global_position.x = -3.5
	p.global_position.z = 7.2
	var to_ai := ai.global_position - p.global_position
	var yaw := rad_to_deg(atan2(-to_ai.x, -to_ai.z))
	var pitch := rad_to_deg(atan2(to_ai.y + 0.5, Vector2(to_ai.x, to_ai.z).length()))
	_look(p, yaw, clampf(pitch, -50.0, 10.0), 0.08)
	if _f == 330 or ai.global_position.y > 6.0 and not _v.has("up"):
		_v.up = _f
	if _v.has("up") and _f > _v.up + 50 or _f > 420:
		_next()


# 4) 바깥 바닥 붕괴
func _part4(p: Player, ai: Duelist) -> void:
	var d: ArenaDirector = _game.arena.director
	if _f == 1:
		d.time = 30.0 - 5.6
	ai.active = false
	ai.global_position = Vector3(5, 0.1, -3)
	p.global_position = Vector3(-7, 6.6, 7)
	_look(p, 150.0 + _f * 0.06, -24.0, 0.05)
	if _f == 330:
		_next()
