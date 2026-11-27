extends SceneTree
## 빛 자취(검기)와 맞는 순간 멈춤(히트스톱) 점검. 무기 7가지 모두:
##  1) 내가 휘두르면 1인칭 자취가 생기고, 휘두름이 끝나면 곧 사라진다
##  2) AI 가 휘두르면 경기장에 자취가 생긴다 (수리검은 날아가는 수리검 꼬리)
##  3) 맞히면 시간이 잠깐 멈췄다가 반드시 원래 속도로 돌아온다. 대검이 단검보다 오래 멈춘다
##  4) 설정에서 끄면 자취가 하나도 그려지지 않는다
## 실행: godot --headless --fixed-fps 60 -s res://tests/trail_test.gd

const GAME := preload("res://scenes/main.tscn")

var _game: Node
var _f := 0
var _i := -1
var _fail := []
var _v := {}
var _weapons: Array = Weapons.ORDER.duplicate()


func _initialize() -> void:
	seed(9)
	Game.opponent_mode = "preset"
	Game.opponent_preset = "검객"
	_check("hitstop_len", Weapons.hitstop_time("greatsword", false) > Weapons.hitstop_time("sword", false)
			and Weapons.hitstop_time("sword", false) > Weapons.hitstop_time("daggers", false),
			"대검 %.3f > 칼 %.3f > 단검 %.3f" % [Weapons.hitstop_time("greatsword", false),
			Weapons.hitstop_time("sword", false), Weapons.hitstop_time("daggers", false)])
	_next()


func _next() -> void:
	if _game:
		_game.queue_free()
	_i += 1
	_f = 0
	_v = {}
	GameSettings.trails = true
	Engine.time_scale = 1.0
	# 마지막 한 판은 설정에서 자취를 끈 칼
	if _i > _weapons.size():
		print("TRAILS => %s %s" % ["OK" if _fail.is_empty() else "FAIL", _fail])
		quit(0 if _fail.is_empty() else 1)
		return
	var w: String = _weapons[_i] if _i < _weapons.size() else "sword"
	Game.test_player_build = CharacterBuild.new()
	Game.test_player_build.weapon = w
	Game.current_opponent = CharacterBuild.preset("검객")
	Game.current_opponent.weapon = w
	Game.next_mode = "duel"
	_game = GAME.instantiate()
	root.add_child(_game)


func _check(name: String, ok: bool, detail: String) -> void:
	print("%-22s %s  => %s" % [name, detail, "OK" if ok else "FAIL"])
	if not ok:
		_fail.append(name)


func _trail_pts(t: SwingTrail) -> int:
	return t.point_count() if t != null and is_instance_valid(t) else 0


func _player_pts(p: Player) -> int:
	return _trail_pts(p._trail) + _trail_pts(p._trail_l) + _trail_pts(p._trail_leg)


func _ai_pts(ai: Duelist) -> int:
	var n := _trail_pts(ai._trail) + _trail_pts(ai._trail_l) + _trail_pts(ai._trail_leg)
	for c in _game.get_children():
		if c is SwingTrail:
			n += (c as SwingTrail).point_count()
	return n


func _process(_delta: float) -> bool:
	if _game == null or _i > _weapons.size():
		return false
	var p: Player = _game.player
	var ai: Duelist = _game.duelist
	if not p.controls_enabled and not _v.has("start"):
		return false
	_f += 1
	var off := _i == _weapons.size()
	if _f == 1:
		_v.start = true
		_game.arena.director.running = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		p.hp = 100000
		p.max_hp = 100000
		if off:
			GameSettings.trails = false
	if _f == 2:
		ai.active = false
		ai.hp = 100000
		ai.max_hp = 100000
		ai.parry_chance = 0.0
		ai.block_chance = 0.0
		ai.dodge_chance = 0.0
		ai.counter_chance = 0.0
		ai.sm.go("idle")
		p.global_position = Vector3(0, 0.1, 1.0)
		p.rotation.y = 0.0
		p.head.rotation.x = 0.0
		ai.global_position = Vector3(0, 0.1, -1.0)
		ai.rotation.y = PI
	# 1) 내가 휘두른다
	if _f == 5:
		p._request_attack("combo")
	if _f > 5 and _f < 60:
		_v.p_max = maxi(int(_v.get("p_max", 0)), _player_pts(p))
		_v.ts_min = minf(float(_v.get("ts_min", 1.0)), Engine.time_scale)
	if _f == 90:
		if p.weapon == "shuriken":
			ai.global_position = Vector3(0, 0.1, -9.0)   # 멀리서 던져야 꼬리가 길게 보인다
		_v.p_after = _player_pts(p)
		_v.ts_after = Engine.time_scale
		# 2) AI 가 휘두른다 (수리검이면 근접 대신 던진다)
		ai.active = true
		ai._dist = 2.0 if p.weapon != "shuriken" else 10.0
		ai._dir = Vector3(0, 0, 1)
		ai._start_attack("heavy" if p.weapon == "shuriken" else "slash1")
		ai._feint_checked = true
	if _f > 90 and _f < 160:
		ai._think_t = 1.0
		_v.ai_max = maxi(int(_v.get("ai_max", 0)), _ai_pts(ai))
	if _f == 200:
		var w := p.weapon
		_v.ts_end = Engine.time_scale
		if off:
			_check("trails_off", int(_v.p_max) == 0 and int(_v.ai_max) == 0,
					"내 자취 %d, AI 자취 %d (0 이어야)" % [_v.p_max, _v.ai_max])
		else:
			_check("player_trail " + w, int(_v.p_max) >= 3 and int(_v.p_after) == 0,
					"휘두를 때 점 %d, 끝난 뒤 %d" % [_v.p_max, _v.p_after])
			_check("ai_trail " + w, int(_v.ai_max) >= 3, "AI 자취 점 %d" % _v.ai_max)
			_check("hitstop " + w, float(_v.ts_min) < 0.5 and is_equal_approx(float(_v.ts_after), 1.0)
					and is_equal_approx(float(_v.ts_end), 1.0),
					"가장 느릴 때 %.2f, 뒤 %.2f / %.2f" % [_v.ts_min, _v.ts_after, _v.ts_end])
		_next()
	return false
