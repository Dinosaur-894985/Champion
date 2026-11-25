extends SceneTree
## 경기장 사진 찍기 (눈으로 확인용).
## 실행: godot -s res://tests/arena_shots.gd -- shots=폴더
## 자리: [이름, 위치, 몸 방향(도), 고개(도)]

const GAME := preload("res://scenes/main.tscn")
const SPOTS := [
	["a1_spawn", Vector3(0, 0.1, 6), 0.0, 4.0],
	["a2_overview", Vector3(-7, 6.6, 7), -45.0, -22.0],
	["a3_bridge_up", Vector3(0, 0.1, 2), 0.0, 28.0],
	["a4_east_zip", Vector3(-4, 0.1, 4), -90.0, 10.0],
	["a5_west_house", Vector3(-4, 0.1, -2), 90.0, 6.0],
	["a6_south", Vector3(0, 0.1, 3), 180.0, 4.0],
	["a7_edge", Vector3(0, 0.1, 22), 180.0, -18.0],
	["a8_obelisk", Vector3(-15, 0.1, -8), 48.0, 14.0],
	["a9_high", Vector3(20, 8, 20), 45.0, -22.0],
]

var _game: Node
var _frame := 0
var _dir := ""
var _i := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_dir = a.substr(6)
	Game.next_mode = "practice"
	_game = GAME.instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_game.hud.hide_menu()
		_game.hud.visible = false
	if _frame > 20 and _frame % 15 == 0:
		if _i >= SPOTS.size():
			quit()
			return false
		var s: Array = SPOTS[_i]
		var p: Player = _game.player
		p.global_position = s[1]
		p.velocity = Vector3.ZERO
		p.rotation.y = deg_to_rad(s[2])
		p.head.rotation.x = deg_to_rad(s[3])
	if _frame > 20 and _frame % 15 == 12 and _i < SPOTS.size():
		_save(SPOTS[_i][0])
		_i += 1
	return false


func _save(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dir.path_join(shot_name + ".png"))
