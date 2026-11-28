extends SceneTree
## 승리 연출과 전적 점검:
##  1) 이긴 판: 느린 화면 + 상대를 비추는 카메라 → "승리!" → 결과 화면(이번 판 숫자, 무기 전적, 연승)
##  2) 진 판: 느린 화면 → 결과 화면, 연승이 끊긴다
##  3) 전적 화면: 무기별·난이도별 줄
## 실행: godot --headless --fixed-fps 60 -s res://tests/result_test.gd
## 사진: -- shots=폴더 (화면이 있는 환경에서)

const GAME := preload("res://scenes/main.tscn")

var _fail := []
var _game: Game
var _f := 0
var _part := 0
var _backup := ""
var _dir := ""
var _v := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_dir = a.substr(6)
	# 내 컴퓨터에서 돌려도 원래 기록이 남도록 잠깐 비켜 둔다
	if FileAccess.file_exists(Progress.PATH):
		_backup = FileAccess.get_file_as_string(Progress.PATH)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.PATH))
	var b := CharacterBuild.preset("검객")
	b.weapon = "spear"
	Game.test_player_build = b
	Game.difficulty = "hard"
	Game.opponent_mode = "preset"
	Game.opponent_preset = "검객"
	_next()


func _check(name: String, ok: bool, info := "") -> void:
	print("RESULT %-30s %s  => %s" % [name, info, "OK" if ok else "FAIL"])
	if not ok:
		_fail.append(name)


func _shot(n: String) -> void:
	if _dir != "":
		root.get_texture().get_image().save_png(_dir.path_join(n + ".png"))


func _next() -> void:
	_part += 1
	_f = 0
	if _game:
		_game.queue_free()
		_game = null
	if _part > 2:
		_finish()
		return
	Engine.time_scale = 1.0
	paused = false
	Game.next_mode = "duel"
	Game.current_opponent = null
	_game = GAME.instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	if _game == null:
		return false
	_f += 1
	var p := _game.player
	var d := _game.duelist
	if _f == 200:
		# 숫자 세기가 끝나고 몇 대 주고받은 셈 치기
		d.take_hit({"damage": 30, "react": "flinch", "guard": "normal", "dir": "side"}, Vector3.FORWARD, p)
		p._take_damage(12, Vector3.BACK)
		if _part == 1:
			d.hp = 1
			d.take_hit({"damage": 40, "react": "stagger", "guard": "normal", "dir": "side"}, Vector3.FORWARD, p)
		else:
			p._take_damage(500, Vector3.BACK)
	if _f == 215:
		_v.slow = Engine.time_scale
		_v.cam = _game._cine_cam != null and _game._cine_cam.current
		_v.bars = _game.hud._bars.size() == 2 and not _game.hud._crosshair.visible
	if _f == 240:
		_shot("result%d_cine" % _part)
	if _f == 500:
		var won := _part == 1
		var h := _game.hud
		_check("%s: 느린 화면" % ("승리" if won else "패배"), float(_v.slow) < 0.5, "time_scale=%.2f" % _v.slow)
		_check("%s: 검은 띠 + 막대 숨김" % ("승리" if won else "패배"), _v.bars)
		if won:
			_check("승리: 상대를 비추는 카메라", _v.cam)
		_check("%s: 결과 화면" % ("승리" if won else "패배"), h._menu_kind == ("win" if won else "lose") and Engine.time_scale == 1.0, h._menu_kind)
		var st: Dictionary = h.result.get("stats", {})
		_check("%s: 이번 판 숫자" % ("승리" if won else "패배"), int(st.get("dealt", 0)) >= 30 and int(st.get("taken", 0)) >= 12
			and float(h.result.get("time", 0.0)) > 0.5, str(st))
		var r := Records.load_all()
		if won:
			_check("승리: 전적 저장", r.weapons.get("spear", []) == [1, 0] and r.diffs.get("hard", []) == [1, 0]
				and r.streak == 1 and float(r.fastest.get("hard", 0.0)) > 0.0, str(r))
		else:
			_check("패배: 전적 저장, 연승 끊김", r.weapons.get("spear", []) == [1, 1] and r.streak == 0 and r.best_streak == 1, str(r))
			h.show_menu("records")
			_check("전적 화면", h._menu_kind == "records" and h._menu_title.text == "전적")
		_shot("result%d_menu" % _part)
	if _f == 505 and _part == 2:
		_shot("result3_records")
	if _f == 510:
		_next()
	return false


func _finish() -> void:
	Engine.time_scale = 1.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Progress.PATH))
	if _backup != "":
		var f := FileAccess.open(Progress.PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	print("RESULTS => %s %s" % ["OK" if _fail.is_empty() else "FAIL", _fail])
	quit(0 if _fail.is_empty() else 1)
