extends SceneTree
## 화면 반짝임 확인용: 같은 자리에서 고개를 아주 조금씩 돌리며 사진을 찍는다.
## 실행: godot -s res://tests/shimmer_shots.gd -- shots=폴더
const GAME := preload("res://scenes/main.tscn")
const SPOTS := [
	["s1", Vector3(0, 0.1, 6), 0.0, 4.0],
	["s2", Vector3(-4, 0.1, 4), -60.0, 6.0],
	["s3", Vector3(0, 0.1, 22), 180.0, -8.0],
]
const STEPS := 4
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
	if _frame > 30 and _frame % 8 == 0:
		var k := _i
		var si := k / STEPS
		if si >= SPOTS.size():
			quit()
			return false
		var s: Array = SPOTS[si]
		var p: Player = _game.player
		p.global_position = s[1]
		p.velocity = Vector3.ZERO
		p.rotation.y = deg_to_rad(s[2] + (k % STEPS) * 0.08)
		p.head.rotation.x = deg_to_rad(s[3])
	if _frame > 30 and _frame % 8 == 6:
		var si2 := _i / STEPS
		if si2 < SPOTS.size():
			_save("%s_%d" % [SPOTS[si2][0], _i % STEPS])
			_i += 1
	return false

func _save(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_dir.path_join(n + ".png"))
