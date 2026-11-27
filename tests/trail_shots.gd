extends SceneTree
## 빛 자취(검기) 사진: 무기마다 1인칭으로 휘두른 순간 + AI 가 휘두른 순간.
## 실행: godot --fixed-fps 60 -s res://tests/trail_shots.gd -- shots=폴더 [only=무기]

const GAME := preload("res://scenes/main.tscn")

var _dir := "user://shots"
var _list: Array = Weapons.ORDER.duplicate()
var _i := -1
var _frame := 0
var _game: Node
var _was := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_dir = a.substr(6)
		elif a.begins_with("only="):
			_list = [a.substr(5)]
	_next()


func _next() -> void:
	_i += 1
	_frame = 0
	_was = ""
	if _game:
		_game.queue_free()
	if _i >= _list.size():
		quit(0)
		return
	var w: String = _list[_i]
	Game.next_mode = "duel"
	Game.test_player_build = CharacterBuild.new()
	Game.test_player_build.weapon = w
	Game.current_opponent = CharacterBuild.preset("검객")
	Game.current_opponent.weapon = w
	_game = GAME.instantiate()
	root.add_child(_game)


func _shot(n: String) -> void:
	root.get_texture().get_image().save_png(_dir.path_join("%s_%s.png" % [_list[_i], n]))


func _process(_d: float) -> bool:
	if _game == null or not is_instance_valid(_game):
		return false
	var p: Player = _game.player
	if _frame < 3:
		_frame += 1
	elif not p.controls_enabled and _frame < 40:
		return false       # 시작 숫자 세기가 끝날 때까지 기다린다
	else:
		_frame += 1
	var ai: Duelist = _game.duelist
	var w: String = _list[_i]
	if _frame == 3:
		_game.hud.hide_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _frame == 40:
		_game.arena.director.running = false
	if _frame == 40 or _frame == 110:
		ai.active = false
		ai.hp = 100000
		ai.parry_chance = 0.0
		ai.block_chance = 0.0
		ai.dodge_chance = 0.0
		ai.counter_chance = 0.0
		ai.sm.go("idle")
		p.hp = 100000
		p.global_position = Vector3(0, 0.1, 1.4)
		p.rotation.y = 0.0
		p.head.rotation.x = deg_to_rad(-4)
		var far := _frame == 110 and w == "shuriken"
		ai.global_position = Vector3(0.6, 0.1, -1.6 if not far else -8.0)
		ai.rotation.y = PI - 0.3
	if _frame == 50:
		p._request_attack("combo")
	# 1인칭: 맞히는 구간이 끝나는 순간 (자취가 가장 길 때)
	if _frame > 50 and _frame < 100:
		# 맞히는 구간이 거의 끝날 때 (자취가 가장 길 때)
		if p._attack_phase == "active" and p._attack_timer < 0.03 and _was != "done":
			_shot("fp")
			_was = "done"
	if _frame == 101 and OS.get_environment("FP_ONLY") != "":
		_next()
		return false
	if _frame == 120:
		_was = ""
		p.global_position = Vector3(-1.4, 0.1, 2.0)
		p.rotation.y = deg_to_rad(-30)
		ai.active = true
		ai._dist = 2.0 if w != "shuriken" else 9.0
		ai._dir = Vector3(0, 0, 1)
		ai._start_attack("heavy" if w == "shuriken" else "slash1")
		ai._feint_checked = true
	if _frame > 120 and _frame < 200:
		ai._think_t = 1.0
		var st := str(ai.sm.state)
		if w == "shuriken":
			if _frame == 132:
				_shot("ai")
		elif st == "strike" and ai._state_t >= float(ai._mv(ai._attack).active) * 0.8 and _was != "done":
			_shot("ai")
			_was = "done"
	if _frame == 210:
		_next()
	return false
