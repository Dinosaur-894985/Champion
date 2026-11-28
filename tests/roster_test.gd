extends SceneTree
## 캐릭터 3개 저장 점검: 예전 저장 파일 옮기기, 칸에 저장·고르기·지우기, 칸별 전적, 거울 상대,
## 처음 화면/상대 고르기의 '내 캐릭터' 줄, 캐릭터 만들기 화면의 칸 버튼·이름·지우기.
## 실행: godot --headless --fixed-fps 60 -s res://tests/roster_test.gd
## 사진: godot -s res://tests/roster_test.gd -- shots=폴더 (화면이 있는 환경에서)

const GAME := preload("res://scenes/main.tscn")

var _fail := []
var _f := 0
var _game: Node
var _dir := ""
var _backups := {}
var _choices := []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_dir = a.substr(6)
	# 내 컴퓨터에서 돌려도 원래 캐릭터와 전적이 남도록 잠깐 비켜 둔다
	for p in [CharacterBuild.SAVE_PATH, Progress.PATH]:
		if FileAccess.file_exists(p):
			_backups[p] = FileAccess.get_file_as_string(p)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_check_storage()
	_setup_for_screens()
	Game.next_mode = ""
	Game.test_player_build = null
	_game = GAME.instantiate()
	root.add_child(_game)


func _check(name: String, ok: bool, info := "") -> void:
	print("ROSTER %-34s %s  => %s" % [name, info, "OK" if ok else "FAIL"])
	if not ok:
		_fail.append(name)


func _check_storage() -> void:
	# 아무것도 없을 때: 기본 캐릭터, 1번 칸
	var b := CharacterBuild.load_saved()
	_check("처음엔 기본 캐릭터", b.weapon == "sword" and b.name == "캐릭터 1" and CharacterBuild.active_slot() == 0, b.name)

	# 예전 파일 (캐릭터 하나, [build] [look]) → 1번 칸으로
	var old := ConfigFile.new()
	old.set_value("build", "weapon", "spear")
	old.set_value("build", "stats", {"str": 6, "vit": 4, "agi": 6, "tec": 4, "end": 6})
	old.set_value("build", "skills", ["grapple", "double_jump"])
	old.set_value("look", "color", 5)
	old.set_value("look", "parts", {"head": "lancer", "torso": "lancer", "arms": "lancer", "legs": "lancer", "feet": "lancer"})
	old.save(CharacterBuild.SAVE_PATH)
	b = CharacterBuild.load_saved()
	_check("예전 캐릭터를 1번 칸으로", b.weapon == "spear" and b.color == 5 and b.part("head") == "lancer"
		and b.name == "캐릭터 1" and CharacterBuild.load_slot(0) != null, "%s %s" % [b.name, b.weapon])

	# 2번 칸에 새 캐릭터 저장 → 지금 쓰는 캐릭터가 된다
	var c := CharacterBuild.preset("암살자")
	c.name = "  번개 발\n"
	c.save_to_slot(1)
	b = CharacterBuild.load_saved()
	_check("2번 칸 저장 → 지금 쓰는 캐릭터", CharacterBuild.active_slot() == 1 and b.weapon == "daggers" and b.name == "번개 발", b.name)
	var all := CharacterBuild.load_all_slots()
	_check("칸 목록", all.size() == 3 and all[0] != null and all[1] != null and all[2] == null)
	_check("예전 칸 이름은 지워짐", not ConfigFile.new().has_section("build") and _cfg().has_section("slot0") and not _cfg().has_section("build"))
	c.name = "아주아주아주아주긴이름입니다"
	c.save_to_slot(1)
	_check("이름은 10글자까지", CharacterBuild.load_slot(1).name.length() == CharacterBuild.NAME_MAX, CharacterBuild.load_slot(1).name)
	c.name = ""
	c.save_to_slot(1)
	_check("빈 이름은 '캐릭터 2'", CharacterBuild.load_slot(1).name == "캐릭터 2")

	# 고르기
	_check("빈 칸은 못 고름", not CharacterBuild.set_active_slot(2) and CharacterBuild.active_slot() == 1)
	_check("1번 칸 고르기", CharacterBuild.set_active_slot(0) and CharacterBuild.load_saved().weapon == "spear")
	_check("거울 상대 = 고른 캐릭터", Game.make_opponent("mirror", CharacterBuild.load_saved()).weapon == "spear")

	# 칸별 전적
	Records.add_result("spear", "normal", true, 30.0, 0)
	Records.add_result("daggers", "normal", false, 40.0, 1)
	var rec := Records.add_result("daggers", "hard", true, 50.0, 1)
	var r := Records.load_all()
	_check("칸별 전적", r.chars.get("0") == [1, 0] and r.chars.get("1") == [1, 1] and rec.char == [1, 1], str(r.chars))

	# 지우기: 쓰는 칸을 지우면 남은 칸으로, 마지막 하나는 못 지움, 전적도 같이 지움
	_check("쓰는 칸 지우기", CharacterBuild.delete_slot(0) and CharacterBuild.active_slot() == 1
		and CharacterBuild.load_saved().weapon == "daggers")
	_check("지운 칸 전적도 지움", not Records.load_all().chars.has("0") and Records.load_all().chars.has("1"))
	_check("마지막 캐릭터는 못 지움", not CharacterBuild.delete_slot(1) and CharacterBuild.load_slot(1) != null)
	_check("빈 칸 지우기는 안 됨", not CharacterBuild.delete_slot(2))


func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(CharacterBuild.SAVE_PATH)
	return cfg


## 화면 점검용: 1번 '창잡이', 2번 '번개 발'(쓰는 중), 3번 빈 칸
func _setup_for_screens() -> void:
	var a := CharacterBuild.preset("사냥꾼")
	a.name = "창잡이"
	a.save_to_slot(0)
	var c := CharacterBuild.preset("암살자")
	c.name = "번개 발"
	c.save_to_slot(1)


func _process(_delta: float) -> bool:
	_f += 1
	var hud = _game.hud if _game else null
	match _f:
		5:
			# 진짜로 다시 불러오지 않게 메뉴 선택은 여기서 받는다
			hud.menu_choice.disconnect(_game._on_menu_choice)
			hud.menu_choice.connect(func(c: String): _choices.append(c))
			_check("고른 캐릭터로 시작", _game.player.build.name == "번개 발" and _game.player.weapon == "daggers")
			var texts := _button_texts(hud._menu_buttons)
			_check("처음 화면 내 캐릭터 줄", "창잡이" in texts and "번개 발" in texts and "+ 새로 만들기" in texts, str(texts))
		48:
			_shot("r1_start")
			hud.show_menu("opponent")
		50:
			var texts := _button_texts(hud._menu_buttons)
			_check("상대 고르기에 내 캐릭터 줄", "창잡이" in texts and "랜덤 상대" in texts, str(texts))
			_press(hud._menu_buttons, "창잡이")
			_check("칸 누르면 slot_0", _choices.has("slot_0"), str(_choices))
		52:
			_shot("r2_opponent")
			hud.open_build_editor(_game.player.build)
		54:
			var ed = hud._editor
			_check("편집 화면은 쓰는 칸부터", ed._slot == 1 and ed.build.name == "번개 발" and ed._name_edit.text == "번개 발")
			_check("칸 버튼 3개", ed._slot_buttons.size() == 3 and "쓰는 중" in ed._slot_buttons[1].text
				and "빈 칸" in ed._slot_buttons[2].text, ed._slot_buttons[1].text)
			ed._on_slot(2)
			_check("빈 칸 열면 새 캐릭터", ed.build.name == "캐릭터 3" and ed.build.weapon == "sword" and ed._delete_button.disabled)
			ed._name_edit.text = "불주먹"
			ed._name_edit.text_changed.emit("불주먹")
			ed._on_weapon("fists")
			_check("이름 바꾸면 칸 버튼도", "불주먹" in ed._slot_buttons[2].text)
		58:
			_shot("r3_editor_new")
			var ed = hud._editor
			ed._on_slot(1)
			ed._on_slot(2)
			_check("칸 옮겨도 고치던 것 남음", ed.build.name == "불주먹" and ed.build.weapon == "fists")
			ed._on_save()
		60:
			_check("저장하고 닫힘", hud._editor == null and _choices.has("build_saved"))
			var b := CharacterBuild.load_saved()
			_check("3번 칸 저장, 쓰는 중", CharacterBuild.active_slot() == 2 and b.name == "불주먹" and b.weapon == "fists")
			hud.open_build_editor(_game.player.build, 0)
		62:
			var ed = hud._editor
			_check("칸 지정해서 열기", ed._slot == 0 and ed.build.name == "창잡이" and not ed._delete_button.disabled)
			ed._on_delete()
			_check("한 번 누르면 확인만", ed._delete_button.text == "정말 지울까요?" and CharacterBuild.load_slot(0) != null)
		64:
			_shot("r4_editor_delete")
			var ed = hud._editor
			ed._on_delete()
			_check("두 번 누르면 지움", CharacterBuild.load_slot(0) == null and "저장 전" in ed._slot_buttons[0].text, ed._slot_buttons[0].text)
			ed.finished.emit(ed._roster_changed)
		66:
			_check("지운 뒤 닫으면 새로 불러옴", _choices.count("build_saved") == 2)
			# 진짜 흐름: 게임을 '지금 장면'으로 띄워 칸을 고르면 다시 불러와 같은 메뉴로 돌아오는지
			_game.queue_free()
			_game = null
			change_scene_to_packed(GAME)
		80:
			var g = current_scene
			g.hud.show_menu("opponent")
			g.hud.menu_choice.emit("slot_1")
		110:
			var g = current_scene
			_check("칸 고르면 그 캐릭터로 다시 불러옴", g.player.build.name == "번개 발" and g.player.weapon == "daggers"
				and CharacterBuild.active_slot() == 1, g.player.build.name)
			_check("보던 메뉴(상대 고르기)로 돌아옴", g.hud.menu_kind() == "opponent", g.hud.menu_kind())
			g.hud.menu_choice.emit("slot_0")   # 0번은 앞에서 지운 빈 칸
		140:
			_check("빈 칸 누르면 만들기 화면", current_scene.hud._editor != null and current_scene.hud._editor._slot == 0
				and current_scene.hud._editor.build.name == "캐릭터 1")
			_finish()
	return false


func _button_texts(box: Node) -> Array:
	var out := []
	for n in box.find_children("*", "Button", true, false):
		out.append((n as Button).text)
	return out


func _press(box: Node, text: String) -> void:
	for n in box.find_children("*", "Button", true, false):
		if (n as Button).text == text:
			(n as Button).pressed.emit()
			return


func _shot(name: String) -> void:
	if _dir == "":
		return
	DirAccess.make_dir_recursive_absolute(_dir)
	root.get_texture().get_image().save_png("%s/%s.png" % [_dir, name])


func _finish() -> void:
	for p in [CharacterBuild.SAVE_PATH, Progress.PATH]:
		if _backups.has(p):
			var f := FileAccess.open(p, FileAccess.WRITE)
			f.store_string(_backups[p])
			f.close()
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("ROSTER => %s %s" % ["OK" if _fail.is_empty() else "FAIL", _fail])
	quit(0 if _fail.is_empty() else 1)
