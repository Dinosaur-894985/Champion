extends SceneTree
## 무기 사진 찍기 (눈으로 확인용): 무기마다 1인칭 자세, 마주 선 AI, 필살기 순간.
## 실행: godot -s res://tests/weapon_shots.gd -- shots=폴더 [only=무기]

const GAME := preload("res://scenes/main.tscn")

var _game: Node
var _frame := 0
var _dir := ""
var _i := -1
var _list: Array = Weapons.ORDER.duplicate()


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
	_frame += 1
	if _game == null or not is_instance_valid(_game):
		return false
	var p: Player = _game.player
	var ai: Duelist = _game.duelist
	var w: String = _list[_i]
	match _frame:
		3:
			_game.hud.hide_menu()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		40:
			ai.active = false
			ai.sm.go("idle")
			p.global_position = Vector3(0, 0.1, 1.6)
			p.rotation.y = 0.0
			p.head.rotation.x = deg_to_rad(-4)
			ai.global_position = Vector3(0.3, 0.1, -1.6)
			ai.rotation.y = PI - 0.5
			ai.rig.set_pose(MoveSet.BODY_POSES.guard, 30.0)
			p.gauge = Weapons.GAUGE_MAX
			p.gauge_changed.emit(p.gauge, Weapons.GAUGE_MAX)
		44:
			# 3인칭: 옆에서 AI 몸과 무기를 본다
			var cam := Camera3D.new()
			cam.name = "SideCam"
			_game.add_child(cam)
			cam.global_position = ai.global_position + Vector3(2.2, 1.0, 1.4)
			cam.look_at(ai.global_position + Vector3(0, 1.0, 0))
			cam.current = true
		58:
			_shot("0_body")
		60:
			_game.get_node("SideCam").queue_free()
			p.camera.current = true
		70:
			_shot("1_rest")
		72:
			p.set_physics_process(false)
			var m := Weapons.move(w, "slash1")
			p._weapon_pivot.rotation = m.fp.windup[0] * (PI / 180.0)
			p._weapon_pivot.position = m.fp.windup[1]
			ai.rig.set_pose(Weapons.move(w, "overhead").body.windup, 40.0)
		80:
			_shot("2_windup")
		82:
			var m := Weapons.move(w, "thrust")
			p._weapon_pivot.rotation = m.fp.strike[0] * (PI / 180.0)
			p._weapon_pivot.position = m.fp.strike[1]
			ai.rig.set_pose(Weapons.move(w, "thrust").body.strike, 40.0)
		90:
			_shot("3_thrust")
		92:
			p._weapon_pivot.rotation = Vector3.ZERO
			p._weapon_pivot.position = Vector3.ZERO
			p.set_physics_process(true)
			ai.rig.set_pose(Weapons.move(w, "special").body.windup, 40.0)
			ai.rig.glow(Color(1.0, 0.8, 0.15), 3.0)
			p.try_special()
		100:
			_shot("4_special_windup")
		_:
			pass
	var sp := Weapons.move(w, "special")
	if _frame > 92 and p.sm.state == "special" and p._sp_phase == "active" and not _game.has_meta("shot_active"):
		_game.set_meta("shot_active", true)
		_shot("5_special_strike")
	if _frame == 100 + int((float(sp.windup) + float(sp.active) + 0.8) * 60.0):
		_next()
	return false
