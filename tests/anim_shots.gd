extends SceneTree
## 애니풍 동작 사진 (눈으로 확인용).
##   fp   : 무기마다 1인칭으로 서 있기 / 달리기 / 점프 / 준비 / 휘두른 뒤 / 위 막기
##   body : 무기 7가지 결투사를 한 줄로 세워 서 있기 / 달리기 / 공중 / 공격 자세
## 실행: godot -s res://tests/anim_shots.gd -- shots=폴더 [part=fp|body] [only=무기]
## 화면 있는 godot 로 --fixed-fps 60 을 함께 줄 것 (시간이 프레임마다 똑같이 흐르게)

const GAME := preload("res://scenes/main.tscn")

var _game: Node
var _frame := 0
var _dir := ""
var _part := "all"
var _i := -1
var _list: Array = Weapons.ORDER.duplicate()
var _rigs: Array[BodyRig] = []
var _holders: Array[Node3D] = []
var _cam: Camera3D
var _vel := Vector3.ZERO
var _quick := false   # quick=1 : 서 있기/달리기/공중만


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_dir = a.substr(6)
		elif a.begins_with("only="):
			_list = [a.substr(5)]
		elif a == "quick=1":
			_quick = true
		elif a.begins_with("part="):
			_part = a.substr(5)
	if _part == "body":
		_i = _list.size() - 1
	_next()


func _next() -> void:
	_i += 1
	_frame = 0
	if _game:
		_game.queue_free()
		_game = null
	if _i > _list.size() or (_i == _list.size() and _part == "fp"):
		quit(0)
		return
	Game.next_mode = "duel"
	Game.test_player_build = CharacterBuild.new()
	if _i < _list.size():
		Game.test_player_build.weapon = _list[_i]
	Game.current_opponent = CharacterBuild.preset("검객")
	_game = GAME.instantiate()
	root.add_child(_game)


func _shot(n: String) -> void:
	var tag: String = _list[_i] if _i < _list.size() else "body"
	root.get_texture().get_image().save_png(_dir.path_join("%s_%s.png" % [tag, n]))


func _process(_d: float) -> bool:
	_frame += 1
	if _game == null or not is_instance_valid(_game):
		return false
	if _i >= _list.size():
		_body_process()
		return false
	var p: Player = _game.player
	var ai: Duelist = _game.duelist
	match _frame:
		3:
			_game.hud.hide_menu()
			_game.hud.visible = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			ai.active = false
			ai.visible = false
			ai.global_position = Vector3(0, 0.1, -30)
			_game.arena.director.running = false
		10:
			p.global_position = Vector3(0, 0.1, 6.0)
			p.rotation.y = 0.0
			p.head.rotation.x = deg_to_rad(-6)
		60:
			p.controls_enabled = true
		70:
			_shot("1_rest")
			Input.action_press("move_forward")
			Input.action_press("sprint")
			p.global_position = Vector3(0, 0.1, 9.0)
		112:
			_shot("2_run")
			Input.action_release("move_forward")
			Input.action_release("sprint")
		140:
			p.velocity = Vector3.ZERO
			p.global_position = Vector3(0, 0.1, 6.0)
		150:
			p.velocity.y = 6.5
		166:
			_shot("3_air")
			if _quick:
				_next()
		200:
			p._start_attack("slash1")
		207:
			_shot("4_windup")
		217:
			_shot("5_follow")
		260:
			Input.action_press("block")
			p.block_pressed("high")
		272:
			_shot("6_block")
			Input.action_release("block")
		280:
			_next()
	return false


# ---------------- 3인칭 줄 세우기 ----------------

func _spawn(b: CharacterBuild, at: Vector3) -> BodyRig:
	var h := Node3D.new()
	_game.add_child(h)
	h.position = at
	h.rotation.y = PI + deg_to_rad(28)
	var r := BodyRig.new()
	r.build = b
	r.weapon = b.weapon
	h.add_child(r)
	_holders.append(h)
	return r


func _body_process() -> void:
	if _frame > 4:
		for r in _rigs:
			r.animate(1.0 / 60.0, _vel)
	match _frame:
		4:
			_game.hud.hide_menu()
			_game.hud.visible = false
			_game.duelist.visible = false
			_game.duelist.active = false
			var names := ["검객", "탱커", "암살자", "사냥꾼", "봉술가", "수리검사", "격투가"]
			for i in names.size():
				var b := CharacterBuild.preset(names[i])
				var r := _spawn(b, Vector3(-3.9 + i * 1.3, 0.1, 0.0))
				r.set_pose(MoveSet.BODY_POSES.guard, 30.0)
				_rigs.append(r)
			_cam = Camera3D.new()
			_cam.fov = 50
			_game.add_child(_cam)
			_cam.current = true
			_cam.global_position = Vector3(0, 1.2, 6.0)
			_cam.look_at(Vector3(0, 0.95, 0.0))
		40:
			_shot("1_stance")
			_vel = Vector3(0, 0, -7.2)
		75:
			_shot("2_run")
			_vel = Vector3(0, 0, -3.0)
			for r in _rigs:
				if "airborne" in r:
					r.airborne = true
					r.vy = 3.0
		100:
			_shot("3_air")
			_vel = Vector3.ZERO
			for r in _rigs:
				if "airborne" in r:
					r.airborne = false
		120:
			var moves := ["slash1", "heavy", "slash2", "thrust", "spin", "heavy", "slash3"]
			for i in _rigs.size():
				var r := _rigs[i]
				var m := Weapons.move(r.weapon, moves[i])
				r.set_pose(m.body.windup, 60.0, str(m.get("hand", "")))
		140:
			_shot("4_windup")
			var moves := ["slash1", "heavy", "slash2", "thrust", "spin", "heavy", "slash3"]
			for i in _rigs.size():
				var r := _rigs[i]
				var m := Weapons.move(r.weapon, moves[i])
				r.set_pose(m.body.strike, 60.0, str(m.get("hand", "")))
				if str(m.get("limb", "")).begins_with("kick"):
					r.kick_style = m.limb
					r.leg_kick = 1.0
		160:
			_shot("5_strike")
			quit(0)
