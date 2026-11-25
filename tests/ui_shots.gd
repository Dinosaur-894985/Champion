extends SceneTree
## 캐릭터 만들기 화면, 상대 고르기, 스킬 칸, AI 스킬 사진 찍기 (눈으로 확인용).
## 실행: godot -s res://tests/ui_shots.gd -- shots=폴더

const GAME := preload("res://scenes/main.tscn")

var _game: Node
var _frame := 0
var _dir := ""
var _part := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_dir = a.substr(6)
	seed(5)
	var me := CharacterBuild.preset("암살자")
	me.name = "나"
	Game.test_player_build = me
	_next()


func _next() -> void:
	_part += 1
	_frame = 0
	if _game:
		_game.queue_free()
	match _part:
		1:
			Game.next_mode = ""          # 처음 화면
		2:
			Game.next_mode = "duel"
			Game.opponent_mode = "preset"
			Game.opponent_preset = "사냥꾼"
			Game.current_opponent = null
		3:
			Game.next_mode = "duel"
			Game.opponent_preset = "탱커"
			Game.current_opponent = null
		_:
			quit(0)
			return
	_game = GAME.instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_frame += 1
	match _part:
		1:
			_menus()
		2:
			_grapple_ai()
		3:
			_iron_ai()
	return false


func _menus() -> void:
	var hud = _game.hud
	# 사진은 그 프레임이 다 그려진 뒤에 찍히므로, 찍는 프레임과 화면을 바꾸는 프레임을 나눈다
	if _frame == 40:
		_shot("u1_start_menu")
	if _frame == 45:
		hud.open_build_editor(_game.player.build)
	if _frame == 55:
		hud._editor._desc.text = "점멸: " + CharacterBuild.SKILLS.blink.desc
	if _frame == 60:
		_shot("u2_build_editor")
	if _frame == 65:
		hud._editor.finished.emit(false)
	if _frame == 70:
		hud.show_menu("opponent")
	if _frame == 80:
		_shot("u3_opponent_menu")
	if _frame == 85:
		hud.show_menu("presets")
	if _frame == 95:
		_shot("u4_presets")
	if _frame == 100:
		paused = false
		_next()


## 사냥꾼 AI: 멀리서 갈고리를 걸고 날아온다
func _grapple_ai() -> void:
	var player: Player = _game.player
	var ai: Duelist = _game.duelist
	if _frame == 3:
		_game.hud.hide_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.global_position = Vector3(0, 0.1, 9.0)
		player.hp = 9999
	if _frame > 3:
		var to_ai := ai.global_position - player.global_position
		player.rotation.y = atan2(-to_ai.x, -to_ai.z)
		player.head.rotation.x = deg_to_rad(4)
	if ai.state == "grapple" and ai._state_t > 0.12:
		_shot_once("u5_ai_grapple")
	if _frame == 260:
		# 내 스킬 칸 (점멸을 막 써서 쿨타임이 보이게)
		player.skills._cd["blink"] = 4.2
	if _frame == 275:
		_shot("u6_skill_slots")
	if _frame > 300:
		_next()


## 탱커 AI: 큰 공격에 철벽으로 버틴다
func _iron_ai() -> void:
	var player: Player = _game.player
	var ai: Duelist = _game.duelist
	if _frame == 3:
		_game.hud.hide_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.hp = 9999
	if _frame > 3:
		var to_ai := ai.global_position - player.global_position
		player.rotation.y = atan2(-to_ai.x, -to_ai.z)
		player.head.rotation.x = deg_to_rad(-4)
		if to_ai.length() > 2.4:
			Input.action_press("move_forward")
		else:
			Input.action_release("move_forward")
	if ai.active and _frame % 50 == 0 and player.sm.state == "free":
		player._request_attack("heavy")
	if ai.state == "iron" and ai._state_t > 0.3:
		_shot_once("u7_ai_iron")
	if _done.has("u7_ai_iron") or _frame > 1500:
		Input.action_release("move_forward")
		_next()


var _done := {}


func _shot_once(n: String) -> void:
	if _done.has(n):
		return
	_done[n] = true
	_shot(n)


func _shot(n: String) -> void:
	if _dir == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dir.path_join(n + ".png"))
