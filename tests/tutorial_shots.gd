extends SceneTree
## 튜토리얼 화면 사진: 첫 단계, 완벽 막기 단계(상대가 휘두르려는 순간), 끝난 뒤 메뉴, 처음 화면.
## 실행: godot -s res://tests/tutorial_shots.gd -- shots=폴더  (화면이 있는 환경에서)

const GAME := preload("res://scenes/main.tscn")

var _dir := "user://shots"
var _game: Game
var _f := 0
var _taken := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_dir)
	if FileAccess.file_exists(Tutorial.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Tutorial.SAVE_PATH))
	Game.next_mode = "tutorial"
	_game = GAME.instantiate()
	root.add_child(_game)


func _shot(n: String) -> void:
	root.get_texture().get_image().save_png(_dir.path_join(n + ".png"))
	_taken[n] = true
	print("SHOT ", n)


func _process(_delta: float) -> bool:
	_f += 1
	var t := _game.tutorial
	if t == null:
		return false
	if _f == 90:
		_shot("1_move")
	if _f == 100:
		t.go_to(8)   # 완벽 막기
	if _f > 100 and not _taken.has("2_perfect"):
		var d := _game.duelist
		var p := _game.player
		var to := d.global_position - p.global_position
		p.rotation.y = atan2(-to.x, -to.z)
		if d.state == "windup" and d.windup_progress() > 0.6:
			_shot("2_perfect")
			t.go_to(Tutorial.STEPS.size())
			_f = 1000
	if _f == 1200:
		_shot("3_done")
		_game.hud.show_menu("start")
	if _f == 1210:
		_shot("4_start_menu")
		quit()
	return false
