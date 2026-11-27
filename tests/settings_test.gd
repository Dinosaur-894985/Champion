extends SceneTree
## 설정 점검: 키 바꾸기(맞바꾸기, 못 쓰는 키), 저장 후 다시 읽기, 화질 적용, 설정 화면 열고 키 바꾸기.
## 실행: godot --headless --fixed-fps 60 -s res://tests/settings_test.gd
## 사진: godot -s res://tests/settings_test.gd -- shots=폴더 (화면이 있는 환경에서)

const GAME := preload("res://scenes/main.tscn")

var _fail := []
var _f := 0
var _game: Node
var _dir := ""
var _backup := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_dir = a.substr(6)
	# 내 컴퓨터에서 돌려도 원래 설정이 남도록 잠깐 비켜 둔다
	if FileAccess.file_exists(GameSettings.PATH):
		_backup = FileAccess.get_file_as_string(GameSettings.PATH)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.PATH))
	_check_keys()
	_check_save()
	Game.next_mode = ""
	_game = GAME.instantiate()
	root.add_child(_game)


func _check(name: String, ok: bool, info := "") -> void:
	print("SETTING %-34s %s  => %s" % [name, info, "OK" if ok else "FAIL"])
	if not ok:
		_fail.append(name)


func _has(action: String, key: Key) -> bool:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	return InputMap.action_has_event(action, ev) or InputMap.event_is_action(ev, action, true)


func _check_keys() -> void:
	GameSettings.reset_keys()
	_check("기본 키 이름", GameSettings.move_label() == "W A S D" and GameSettings.key_label("jump") == "Space"
		and GameSettings.key_label("attack") == "왼쪽 클릭", GameSettings.move_label())
	_check("기본 키가 등록됨", _has("jump", KEY_SPACE) and _has("move_forward", KEY_UP))
	# 점프를 F 로: F 를 쓰던 '잡기' 는 점프가 쓰던 Space 를 받는다
	var swapped := GameSettings.rebind("jump", "key:%d" % KEY_F)
	_check("이미 쓰는 키는 맞바꿈", swapped == "grab" and _has("jump", KEY_F) and not _has("jump", KEY_SPACE)
		and _has("grab", KEY_SPACE) and not _has("grab", KEY_F), "%s jump=%s grab=%s" % [swapped, GameSettings.key_label("jump"), GameSettings.key_label("grab")])
	# 앞으로(W, ↑) 중 ↑ 를 점프로: 앞으로는 W 만 남는다
	GameSettings.rebind("jump", "key:%d" % KEY_UP)
	_check("보조 키만 가져감", _has("move_forward", KEY_W) and not _has("move_forward", KEY_UP) and _has("jump", KEY_UP))
	_check("휠은 누르는 행동에 못 씀", GameSettings.reject_reason("sprint", "mouse:%d" % MOUSE_BUTTON_WHEEL_UP) != ""
		and GameSettings.reject_reason("skill1", "mouse:%d" % MOUSE_BUTTON_WHEEL_UP) == "")
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	_check("Esc 는 못 씀", GameSettings.code_from_event(esc) == "")
	_check("조작법 글에 새 키", GameSettings.fill("{jump} 점프") == "↑ 점프")
	GameSettings.reset_keys()


func _check_save() -> void:
	GameSettings.mouse_sens = 1.7
	GameSettings.invert_y = true
	GameSettings.fov = 90.0
	GameSettings.quality = "low"
	GameSettings.show_fps = true
	GameSettings.rebind("special", "mouse:%d" % MOUSE_BUTTON_XBUTTON1)
	Audio.set_volume("Music", 0.3)
	Audio.save_settings()
	# 다음 실행처럼 처음부터 다시 읽는다
	GameSettings.mouse_sens = 1.0
	GameSettings.invert_y = false
	GameSettings.fov = 78.0
	GameSettings.quality = "high"
	GameSettings.show_fps = false
	GameSettings.bindings = {}
	GameSettings._loaded = false
	GameSettings.ensure_loaded()
	var cfg := ConfigFile.new()
	cfg.load(GameSettings.PATH)
	_check("저장 후 다시 읽기", is_equal_approx(GameSettings.mouse_sens, 1.7) and GameSettings.invert_y
		and is_equal_approx(GameSettings.fov, 90.0) and GameSettings.quality == "low" and GameSettings.show_fps
		and GameSettings.key_label("special") == "마우스 옆 버튼 1",
		"sens=%.2f q=%s special=%s" % [GameSettings.mouse_sens, GameSettings.quality, GameSettings.key_label("special")])
	_check("소리 크기도 함께 남음", is_equal_approx(float(cfg.get_value("volume", "Music", 0)), 0.3))


func _process(_delta: float) -> bool:
	_f += 1
	var hud = _game.hud if _game else null
	match _f:
		5:
			# 저장된 '낮음' 화질이 켤 때 적용됐는지
			var sun := _sun()
			_check("낮음 화질 적용", sun != null and not sun.shadow_enabled and root.msaa_3d == Viewport.MSAA_DISABLED)
			_check("시야 넓이 적용", is_equal_approx(_game.player.camera.fov, 90.0), str(_game.player.camera.fov))
			GameSettings.quality = "ultra"
			GameSettings.apply_graphics()
			_check("최고 화질 적용", sun.shadow_enabled and root.msaa_3d == Viewport.MSAA_4X)
			GameSettings.mouse_sens = 1.0
			GameSettings.invert_y = false
			GameSettings.fov = 78.0
			GameSettings.quality = "high"
			GameSettings.apply_graphics()
			GameSettings.reset_keys()
			hud.show_menu("pause")
			_check("일시정지에 설정 버튼", _menu_has(hud, "settings"))
			hud.show_menu("start")
			_check("시작 화면에 설정 버튼", _menu_has(hud, "settings"))
			hud.open_settings()
		10:
			_shot("s1_controls")
		12:
			hud._settings.show_tab("keys")
			hud._settings._start_listen("special")
		14:
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_G
			ev.pressed = true
			Input.parse_input_event(ev)
		18:
			_check("화면에서 키 바꾸기", GameSettings.key_label("special") == "G" and _has("special", KEY_G)
				and hud._settings._key_buttons["special"].text == "G", GameSettings.key_label("special"))
			_shot("s2_keys")
		20:
			hud._settings.show_tab("graphics")
		24:
			_shot("s3_graphics")
		26:
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_ESCAPE
			ev.pressed = true
			Input.parse_input_event(ev)
		30:
			_check("Esc 로 닫고 메뉴로", hud._settings == null and hud._menu_kind == "start")
			_check("조작법에 바뀐 키", "G  무기 필살기" in hud._help.text)
			_check("설정 파일에 저장", ConfigFile.new().load(GameSettings.PATH) == OK)
			_finish()
	return false


## 메뉴에 이 선택을 보내는 버튼이 있는지 (누르면 menu_choice 로 choice 가 나오는지 확인)
func _menu_has(hud, choice: String) -> bool:
	var got := []
	var cb := func(c: String): got.append(c)
	hud.menu_choice.disconnect(_game._on_menu_choice)   # 진짜로 열리지는 않게
	hud.menu_choice.connect(cb)
	for b in hud._menu_buttons.get_children():
		if b is Button and b.text.begins_with("설정"):
			b.pressed.emit()
	hud.menu_choice.disconnect(cb)
	hud.menu_choice.connect(_game._on_menu_choice)
	return choice in got


func _sun() -> DirectionalLight3D:
	for c in _game.get_children():
		if c is DirectionalLight3D:
			return c
	return null


func _shot(name: String) -> void:
	if _dir == "":
		return
	DirAccess.make_dir_recursive_absolute(_dir)
	root.get_texture().get_image().save_png("%s/%s.png" % [_dir, name])


func _finish() -> void:
	GameSettings.reset_keys()
	if _backup != "":
		var f := FileAccess.open(GameSettings.PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.PATH))
	print("SETTINGS => %s %s" % ["OK" if _fail.is_empty() else "FAIL", _fail])
	quit(0 if _fail.is_empty() else 1)
