extends SceneTree
## 자동 점검: 게임을 켜고, 앞으로 걸어가 허수아비를 베어 본 뒤 결과를 확인한다.
## 실행: godot --path . -s res://tests/smoke_test.gd  (사진을 남기려면 끝에 -- shots=폴더)

var _main: Node
var _frame := 0
var _shots_dir := ""
var _failed := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_shots_dir = a.substr(6)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	var player: Player = _main.player
	if _frame == 5:
		_main.hud._show_overlay(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_shot("01_start")
	if _frame > 5 and _frame < 100:
		Input.action_press("move_forward")
	if _frame == 100:
		Input.action_release("move_forward")
		_shot("02_close")
	if _frame == 110:
		player._request_attack("light")
	if _frame == 117:
		_shot("03_swing")
	if _frame == 140:
		player._request_attack("light")
	if _frame == 175:
		player._request_attack("heavy")
	if _frame == 195:
		_shot("04_heavy")
	if _frame == 230:
		Input.action_press("jump")
	if _frame == 232:
		Input.action_release("jump")
	if _frame == 300:
		var ok: bool = _main.hits >= 3
		print("SMOKE hits=%d knockdowns=%d stamina=%.1f pos=%s  => %s" % [
			_main.hits, _main.knockdowns, player.stamina, player.global_position, "OK" if ok else "FAIL"])
		_main.hud._show_overlay(true)
		_shot("05_menu")
		if not ok:
			_failed = true
	if _frame == 302:
		quit(1 if _failed else 0)
	return false


func _shot(name: String) -> void:
	if _shots_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(_shots_dir.path_join(name + ".png"))
