extends SceneTree
## 칼 자세 사진 찍기 (개발용): godot -s res://tests/pose_shots.gd -- shots=폴더
const GAME := preload("res://scenes/main.tscn")
var _g: Node
var _f := 0
var _dir := ""
var _list := []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_dir = a.substr(6)
	Game.next_mode = "practice"
	_g = GAME.instantiate()
	root.add_child(_g)
	for m in MoveSet.MOVES:
		_list.append([m + "_windup", MoveSet.MOVES[m].fp.windup])
		_list.append([m + "_strike", MoveSet.MOVES[m].fp.strike])
	for p in MoveSet.FP_POSES:
		_list.append([p, MoveSet.FP_POSES[p]])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			_list = _list.filter(func(e): return e[0].begins_with(a.substr(5)))
	# 후보 자세 시험: try=rx,ry,rz,px,py,pz;...
	for a in OS.get_cmdline_user_args():
		if a.begins_with("try="):
			var n := 0
			for c in a.substr(4).split(";"):
				var v := c.split_floats(",")
				_list.append(["try%d" % n, [Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5])]])
				n += 1

func _process(_d: float) -> bool:
	_f += 1
	if _f == 3:
		_g.hud.hide_menu()
		_g.player.set_physics_process(false)
	var i := (_f - 60) / 4
	if _f >= 60 and (_f - 60) % 4 == 0 and i < _list.size():
		var pose: Array = _list[i][1]
		_g.player._weapon_pivot.rotation = pose[0] * (PI / 180.0)
		_g.player._weapon_pivot.position = pose[1]
	if _f >= 60 and (_f - 60) % 4 == 2 and i < _list.size():
		root.get_texture().get_image().save_png(_dir.path_join("%s.png" % _list[i][0]))
	if i >= _list.size():
		quit()
	return false
