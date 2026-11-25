extends SceneTree
## 소리 점검.
##  1) 코드에서 부르는 소리 이름이 모두 소리 목록(SoundBank)에 있는지 (오타 찾기)
##  2) 무기 4종 × 휘두르기/막기/맞기, 필살기 소리, 배경음악이 다 있는지
##  3) 모든 소리를 실제로 한 번씩 내 보고, 음악 바꾸기/음량 저장이 되는지
##  4) AI 와 잠깐 싸워서 발소리, 경고음, 휘두르기, 맞는 소리, 숫자 세기, 경기장 음악이 실제로 나는지
## 실행: godot --headless --fixed-fps 60 -s res://tests/audio_test.gd

const GAME := preload("res://scenes/main.tscn")

var _fail := []
var _f := 0
var _phase := ""
var _game: Node


func _initialize() -> void:
	seed(3)
	_check_names()
	_check_bank()
	Audio.director()   # 자동 등록이 없으므로 여기서 만든다 (다음 프레임에 붙는다)
	_phase = "play_all"


func _check_names() -> void:
	var re := RegEx.new()
	re.compile("(?:_play|Audio\\.play|Audio\\.ui|Audio\\.step)\\(\\s*\"([a-z0-9_]+)\"\\s*[,)]")
	var re_loop := RegEx.new()
	re_loop.compile("Audio\\.loop_start\\([^,]+,\\s*\"([a-z0-9_]+)\"")
	var used := {}
	for path in _scripts("res://scripts"):
		var text := FileAccess.get_file_as_string(path)
		for m in re.search_all(text):
			used[m.get_string(1)] = path
		for m in re_loop.search_all(text):
			used[m.get_string(1)] = path
	var missing := []
	for n in used:
		if not SoundBank.SFX.has(n):
			missing.append("%s (%s)" % [n, used[n]])
	print("AUDIO names used=%d missing=%s  => %s" % [used.size(), missing, "OK" if missing.is_empty() else "FAIL"])
	if not missing.is_empty():
		_fail.append("names")


func _scripts(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir + "/" + d))
	return out


func _check_bank() -> void:
	var missing := []
	for w in Weapons.ORDER:
		for k in ["swing", "swing_heavy", "clash", "hit"]:
			var n := Audio.weapon_sound(k, w)
			if not SoundBank.SFX.has(n):
				missing.append(n)
		var sp: Dictionary = Weapons.move(w, "special")
		if not SoundBank.SFX.has("sp_" + str(sp.effect)):
			missing.append("sp_" + str(sp.effect))
	for n in ["warn_light", "warn_heavy", "warn_grab", "warn_special", "parry", "perfect_dodge", "guard_break",
			"grab", "throw", "wall_slam", "step", "dash", "floor_warn", "floor_collapse", "pickup_get"]:
		if not SoundBank.SFX.has(n):
			missing.append(n)
	for t in ["menu", "arena", "victory", "defeat"]:
		if not SoundBank.MUSIC.has(t):
			missing.append("music:" + t)
	var nulls := 0
	for n in SoundBank.SFX:
		for s in SoundBank.SFX[n].streams:
			if s == null or (s is AudioStreamWAV and (s as AudioStreamWAV).data.is_empty()):
				nulls += 1
	print("AUDIO bank sounds=%d music=%d missing=%s empty=%d  => %s" % [SoundBank.SFX.size(), SoundBank.MUSIC.size(),
			missing, nulls, "OK" if missing.is_empty() and nulls == 0 else "FAIL"])
	if not missing.is_empty() or nulls > 0:
		_fail.append("bank")


func _process(_delta: float) -> bool:
	_f += 1
	match _phase:
		"play_all":
			if _f == 3:
				var d := Audio.director()
				var ok := d.is_inside_tree()
				var cam := Camera3D.new()
				root.add_child(cam)
				cam.current = true
				for n in SoundBank.SFX:
					Audio.play(n)
					Audio.play(n, Vector3(3, 0, -2))
				Audio.music("menu")
				var before := Audio.get_volume("Music")
				Audio.set_volume("Music", 0.3)
				Audio.save_settings()
				d.volumes["Music"] = 1.0
				d.load_settings()
				var vol_ok := absf(Audio.get_volume("Music") - 0.3) < 0.01
				Audio.set_volume("Music", before)
				Audio.save_settings()
				print("AUDIO play_all in_tree=%s counted=%d volume_saved=%s  => %s" % [ok, d.counts.size(), vol_ok,
						"OK" if ok and d.counts.size() == SoundBank.SFX.size() and vol_ok else "FAIL"])
				if not (ok and d.counts.size() == SoundBank.SFX.size() and vol_ok):
					_fail.append("play_all")
				cam.queue_free()
			if _f == 30:
				var music_ok: bool = Audio.director().current_music() == "menu"
				Audio.director().counts.clear()
				print("AUDIO music menu playing=%s  => %s" % [music_ok, "OK" if music_ok else "FAIL"])
				if not music_ok:
					_fail.append("music")
				Game.opponent_mode = "preset"
				Game.opponent_preset = "검객"
				Game.current_opponent = null
				Game.test_player_build = CharacterBuild.new()
				Game.next_mode = "duel"
				_game = GAME.instantiate()
				root.add_child(_game)
				_phase = "duel"
				_f = 0
		"duel":
			# 플레이어는 가만히 서 있고 AI 가 다가와 공격한다
			if _f == 60 * 9:
				var c: Dictionary = Audio.director().counts
				var need := {
					"countdown": c.has("countdown"), "fight": c.has("fight"),
					"step": c.has("step"),
					"warn": c.keys().any(func(k): return str(k).begins_with("warn_")),
					"swing": c.keys().any(func(k): return str(k).begins_with("swing_") or k == "grab_whoosh"),
					"impact": c.keys().any(func(k): return str(k).begins_with("hit_") or str(k).begins_with("clash_") or k == "hurt" or k == "grab"),
					"arena_music": Audio.director().current_music() == "arena",
				}
				var bad := need.keys().filter(func(k): return not need[k])
				print("AUDIO duel sounds=%s missing=%s  => %s" % [c, bad, "OK" if bad.is_empty() else "FAIL"])
				if not bad.is_empty():
					_fail.append("duel")
				print("AUDIO => %s %s" % ["OK" if _fail.is_empty() else "FAIL", _fail])
				quit(0 if _fail.is_empty() else 1)
	return false
