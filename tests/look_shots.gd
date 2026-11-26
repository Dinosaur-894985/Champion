extends SceneTree
## 결투사 겉모습 사진 (눈으로 확인용): 무기 7가지 옷차림을 한 줄로 세워 앞/뒤/가까이/공격 자세로 찍는다.
## 실행: godot -s res://tests/look_shots.gd -- shots=폴더

const GAME := preload("res://scenes/main.tscn")

var _game: Node
var _frame := 0
var _dir := ""
var _rigs: Array[BodyRig] = []
var _holders: Array[Node3D] = []
var _cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_dir = a.substr(6)
	Game.next_mode = "duel"
	Game.test_player_build = CharacterBuild.new()
	_game = GAME.instantiate()
	root.add_child(_game)


func _shot(n: String) -> void:
	root.get_texture().get_image().save_png(_dir.path_join("look_%s.png" % n))


func _lineup() -> void:
	_game.hud.hide_menu()
	_game.hud.visible = false
	_game.duelist.visible = false
	_game.duelist.active = false
	var names := ["검객", "탱커", "암살자", "사냥꾼", "봉술가", "수리검사", "격투가"]
	for i in names.size():
		var b := CharacterBuild.preset(names[i])
		var r := _spawn(b, Vector3(-4.2 + i * 1.4, 0.1, -2.0))
		r.set_pose(MoveSet.BODY_POSES.guard, 30.0)
		_rigs.append(r)
	_cam = Camera3D.new()
	_cam.fov = 50
	_game.add_child(_cam)
	_cam.current = true


## 몸은 자기 위치를 스스로 움직이므로(숙이기, 젖혀짐) 받침 노드 위에 세운다. 카메라 쪽(+Z)을 보게 돌린다
func _spawn(b: CharacterBuild, at: Vector3) -> BodyRig:
	var h := Node3D.new()
	_game.add_child(h)
	h.position = at
	h.rotation.y = PI
	var r := BodyRig.new()
	r.build = b
	r.weapon = b.weapon
	h.add_child(r)
	_holders.append(h)
	return r


func _place(pos: Vector3, look: Vector3) -> void:
	_cam.global_position = pos
	_cam.look_at(look)


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 4:
		_lineup()
	if _frame > 4:
		for r in _rigs:
			r.animate(1.0 / 60.0, Vector3.ZERO)
	match _frame:
		20:
			_place(Vector3(0, 1.3, 5.6), Vector3(0, 1.0, -2.0))
		24:
			_shot("lineup_front")
		26:
			for h in _holders:
				h.rotation.y = 0.0
		40:
			_shot("lineup_back")
		42:
			for h in _holders:
				h.rotation.y = PI
			_cam.fov = 30
			_place(Vector3(-2.8, 1.75, 0.6), Vector3(-2.8, 1.75, -2.0))
		50:
			_shot("faces_left")
		52:
			_place(Vector3(1.4, 1.75, 0.6), Vector3(1.4, 1.75, -2.0))
		60:
			_shot("faces_right")
		62:
			# 공격 자세: 무기마다 대표 동작의 휘두르는 순간
			_cam.fov = 50
			_place(Vector3(0, 1.4, 5.0), Vector3(0, 1.0, -2.0))
			var moves := ["slash1", "heavy", "thrust", "thrust", "spin", "heavy", "slash3"]
			for i in _rigs.size():
				var r := _rigs[i]
				var m := Weapons.move(r.weapon, moves[i])
				r.set_pose(m.body.strike, 60.0, str(m.get("hand", "")))
				if str(m.get("limb", "")).begins_with("kick"):
					r.kick_style = m.limb
					r.leg_kick = 1.0
				_holders[i].rotation.y = PI + deg_to_rad(35)
		90:
			_shot("lineup_action")
		92:
			# 같은 검을 들어도 옷(부위마다 따로 고름), 몸집, 색, 머리에 따라 다르다
			for h in _holders:
				h.queue_free()
			_rigs.clear()
			_holders.clear()
			var looks := [[0, 0, 0, 10, 10, 1], [1, 2, 1, 2, 3, 9], [3, 3, 2, 6, 6, 5], [5, 1, 3, 9, 8, 1], [6, 0, 1, 3, 3, 10]]
			for i in looks.size():
				var b := CharacterBuild.new()
				b.weapon = "sword"
				var outfits := [["heavy", "monk", "brawler", "monk", "brawler"], ["shadow", "rogue", "shadow", "rogue", "rogue"],
						["knight", "lancer", "heavy", "knight", "heavy"], ["brawler", "brawler", "brawler", "shadow", "monk"],
						["rogue", "monk", "lancer", "monk", "monk"]]
				for pi in CharacterBuild.PART_ORDER.size():
					b.parts[CharacterBuild.PART_ORDER[pi]] = outfits[i][pi]
				b.color = looks[i][0]
				b.skin = looks[i][1]
				b.hair = looks[i][2]
				b.stats = {"str": looks[i][3], "vit": looks[i][4], "agi": looks[i][5], "tec": 5, "end": 5}
				var r := _spawn(b, Vector3(-2.8 + i * 1.4, 0.1, -2.0))
				r.set_pose(MoveSet.BODY_POSES.guard, 30.0)
				_rigs.append(r)
		110:
			_shot("variety")
		112:
			quit(0)
	return false
