extends SceneTree
## 튜토리얼 점검: 점검 봇이 12단계를 차례로 직접 해내서 끝까지 가는지 본다.
## (걷기, 점프, 달리기, 두 번 눌러 피하기, 연속기, 공격 방향, 강공격,
##  막기, 완벽 막기, 바로 반격, 공격 피하기, 필살기) + 건너뛰기, 메뉴 버튼.
## 실행: godot --headless --fixed-fps 60 -s res://tests/tutorial_test.gd
## 무기 바꾸기: -- weapon=shuriken

const GAME := preload("res://scenes/main.tscn")
const STEP_LIMIT := 60.0 * 25   # 한 단계에 25초 넘게 걸리면 실패

var _fail := []
var _game: Game
var _tut: Tutorial
var _f := 0
var _step_f := 0
var _last_index := -1
var _hold := 0
var _done := false
var _end_f := -1
var _weapon := "sword"
var _backup := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("weapon="):
			_weapon = a.substr(7)
	# 내 컴퓨터에서 돌려도 원래 기록이 남도록 잠깐 비켜 둔다
	if FileAccess.file_exists(Tutorial.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(Tutorial.SAVE_PATH)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Tutorial.SAVE_PATH))
	var b := CharacterBuild.preset("검객")
	b.weapon = _weapon
	Game.test_player_build = b
	Game.arena_choice = "sky"
	Game.next_mode = "tutorial"
	_game = GAME.instantiate()
	root.add_child(_game)


func _check(name: String, ok: bool, info := "") -> void:
	print("TUTORIAL %-30s %s  => %s" % [name, info, "OK" if ok else "FAIL"])
	if not ok:
		_fail.append(name)


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "block"]:
		Input.action_release(a)


func _process(_delta: float) -> bool:
	_f += 1
	if _f == 2:
		_tut = _game.tutorial
		_check("튜토리얼 시작", _tut != null and _tut.index == 0 and _game.duelist.tutor and not _game.duelist.active)
		_check("허수아비 3개", _dummies() == 3)
		_check("조작법 글 숨김", not _game.hud._help.visible)
	if _tut == null or _f < 40:
		return false
	if _done:
		if _f - _end_f == 150:
			_check("끝나면 메뉴", _game.hud._menu_kind == "tutorial_done" and get_root().get_tree().paused)
			_check("완료 저장", Tutorial.is_done())
			_check("처음 화면에 '다시 하기' 버튼", _menu_has("tutorial"))
			_finish()
			return true
		return false
	if _tut.index != _last_index:
		if _last_index >= 0:
			_check("%d. %s" % [_last_index + 1, Tutorial.STEPS[_last_index].title], true, "%.1f초" % (_step_f / 60.0))
		_release_all()
		_last_index = _tut.index
		_step_f = 0
		_hold = 0
		if _tut.index >= Tutorial.STEPS.size():
			_done = true
			_end_f = _f
			return false
	_step_f += 1
	if _step_f > STEP_LIMIT:
		_check("%d. %s" % [_tut.index + 1, _tut.step.title], false, "시간 초과 %.1f/%d" % [_tut.count, _tut.step.goal])
		_finish()
		return true
	_bot(_tut.step.id)
	return false


func _dummies() -> int:
	var n := 0
	for c in _game.get_children():
		if c is TrainingDummy:
			n += 1
	return n


func _menu_has(choice: String) -> bool:
	# 처음 화면을 다시 그려 보고 버튼이 있는지 본다
	_game.hud.show_menu("start")
	for b in _game.hud._menu_buttons.get_children():
		if b is Button and not b.is_queued_for_deletion() and b.text.begins_with("튜토리얼"):
			return true
	return false


func _face(target: Vector3) -> void:
	var p := _game.player
	var to := target - p.global_position
	p.rotation.y = atan2(-to.x, -to.z)


## 단계마다 사람처럼 해 본다
func _bot(id: String) -> void:
	var p := _game.player
	var d: Duelist = _game.duelist
	match id:
		"move":
			Input.action_press("move_forward")
		"jump":
			if _step_f % 50 == 1:
				Input.action_press("jump")
			elif _step_f % 50 == 6:
				Input.action_release("jump")
		"sprint":
			if _step_f == 1:
				p.global_position = Vector3(0, 0.1, 7.5)
				p.rotation.y = PI * 0.5
			p.rotation.y += 0.025   # 빙글빙글 원을 그리며 달린다 (벽, 허수아비에 막히지 않게)
			Input.action_press("move_forward")
			Input.action_press("sprint")
		"dodge":
			if _step_f % 40 == 1:
				p.try_dash(Vector2(-1 if (_step_f / 40) % 2 == 0 else 1, 0))
		"combo", "aim", "heavy":
			if id == "combo" and _step_f == 1:
				p.global_position = Vector3(0, 0.1, 2.0)   # 달리기/피하기로 멀리 갔으면 허수아비 앞으로
			var dummy := _nearest_dummy()
			if dummy == null:
				return
			_face(dummy.global_position)
			if p.global_position.distance_to(dummy.global_position) > 2.0:
				Input.action_press("move_forward")
				return
			Input.action_release("move_forward")
			if id == "combo" and _step_f % 14 == 0:
				p.attack_pressed("", 0.0)
				p.attack_released()
			elif id == "aim" and _step_f % 60 == 0:
				p.attack_pressed(AttackDir.HIGH if (_step_f / 60) % 2 == 0 else AttackDir.MID, 0.0)
				p.attack_released()
			elif id == "heavy" and _step_f % 70 == 0:
				p._request_attack("heavy")
		"block", "perfect", "riposte":
			_face(d.global_position)
			var ad := d.attack_dir()
			if ad != "" and ad != "grab":
				if id != "block":
					p.set_guard(ad)
				Input.action_press("block")
				if not p.blocking:
					p.block_pressed()
			elif p.blocking and _hold <= 0:
				Input.action_release("block")
			if id == "riposte" and p._riposte_t > 0.0:
				Input.action_release("block")
				p.attack_pressed("", 0.0)
				p.attack_released()
		"evade":
			_face(d.global_position)
			if d.state == "windup" and d.windup_progress() > 0.93:
				p.try_dash(Vector2(1, 0))
		"special":
			_face(d.global_position)
			if _step_f == 30:
				_check("필살기 게이지 가득", p.special_ready())
				p.try_special()


func _nearest_dummy() -> Node3D:
	var best: Node3D = null
	for c in _game.get_children():
		if c is TrainingDummy and not c.is_queued_for_deletion():
			if best == null or c.global_position.distance_to(_game.player.global_position) < best.global_position.distance_to(_game.player.global_position):
				best = c
	return best


func _finish() -> void:
	_release_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Tutorial.SAVE_PATH))
	if _backup != "":
		var f := FileAccess.open(Tutorial.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
	print("TUTORIAL => %s %s" % ["OK" if _fail.is_empty() else "FAIL", _fail])
	quit(0 if _fail.is_empty() else 1)
