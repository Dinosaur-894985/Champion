extends SceneTree
## 새 무기(봉, 수리검, 맨몸 격투) 점검.
##  1) 수리검 Q 던지기: 8m 앞의 AI 에게 날아가 맞는다
##  2) 수리검 부채꼴 (왼쪽 클릭 길게): 세 장이 날아간다
##  3) AI 수리검을 찌르기 막기(가운데)로 막으면 막힌다, 안 막으면 맞는다
##  4) AI 가 수리검을 들면 멀리서 스스로 던진다
##  5) 맨몸: 주먹, 주먹, 돌려차기 연속기가 들어가고, 발차기는 다리가 올라간다
##  6) 봉: 마무리 풍차 돌리기가 상대를 넘어뜨린다
##  7) 겉모습: 무기 7가지 x 색 x 옷(부위마다 섞어서)이 모두 만들어지고, 옷은 무기를 따라가지 않으며,
##     같은 색끼리 맞붙으면 상대 색이 바뀐다
## 실행: godot --headless --fixed-fps 60 -s res://tests/new_weapons_test.gd

const GAME := preload("res://scenes/main.tscn")
const PARTS := 8

var _game: Node
var _f := 0
var _part := 0
var _fail := []
var _v := {}


func _initialize() -> void:
	seed(5)
	Game.opponent_mode = "preset"
	Game.opponent_preset = "검객"
	_next()


func _weapon_for(part: int) -> Array:
	# [내 무기, AI 무기]
	match part:
		1, 2, 8:
			return ["shuriken", "sword"]
		3, 4:
			return ["sword", "shuriken"]
		5:
			return ["fists", "sword"]
		6:
			return ["staff", "sword"]
	return ["sword", "sword"]


func _next() -> void:
	if _game:
		_game.queue_free()
	_part += 1
	_f = 0
	_v = {}
	for a in ["attack", "heavy", "block"]:
		Input.action_release(a)
	if _part > PARTS:
		print("NEWWEAPONS => %s %s" % ["OK" if _fail.is_empty() else "FAIL", _fail])
		quit(0 if _fail.is_empty() else 1)
		return
	var w := _weapon_for(_part)
	Game.test_player_build = CharacterBuild.new()
	Game.test_player_build.weapon = w[0]
	Game.current_opponent = CharacterBuild.preset("검객")
	Game.current_opponent.weapon = w[1]
	Game.next_mode = "duel"
	_game = GAME.instantiate()
	root.add_child(_game)


func _check(name: String, ok: bool, detail: String) -> void:
	print("%-14s %s  => %s" % [name, detail, "OK" if ok else "FAIL"])
	if not ok:
		_fail.append(name)


func _place(p: Player, ai: Duelist, gap: float) -> void:
	p.global_position = Vector3(0, 0.1, gap * 0.5)
	p.rotation.y = 0.0
	p.head.rotation.x = 0.0
	p.velocity = Vector3.ZERO
	p.stamina = p.max_stamina
	ai.global_position = Vector3(0, 0.1, -gap * 0.5)
	ai.rotation.y = PI
	ai.velocity = Vector3.ZERO
	ai._push = Vector3.ZERO


func _hold_ai(ai: Duelist) -> void:
	ai.active = false
	ai.hp = 100000
	ai.max_hp = 100000
	ai.parry_chance = 0.0
	ai.block_chance = 0.0
	ai.dodge_chance = 0.0
	ai.counter_chance = 0.0
	ai.sm.go("idle")


func _process(_delta: float) -> bool:
	if _part > PARTS or _game == null:
		return false
	var p: Player = _game.player
	var ai: Duelist = _game.duelist
	if not p.controls_enabled and not _v.has("start"):
		return false
	_f += 1
	if _f == 1:
		_v.start = true
		_game.arena.director.running = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		p.hp = 100000
		p.max_hp = 100000
		p.attack_received.connect(func(r): _v["me_" + r] = int(_v.get("me_" + r, 0)) + 1)
	match _part:
		1: _throw(p, ai)
		2: _fan(p, ai)
		3: _block_shuriken(p, ai)
		4: _ai_throws(p, ai)
		5: _fists(p, ai)
		6: _staff(p, ai)
		7: _looks(p, ai)
		8: _ammo_air(p, ai)
	return false


# 1) Q 던지기
func _throw(p: Player, ai: Duelist) -> void:
	if _f == 2:
		_hold_ai(ai)
		_place(p, ai, 8.0)
	if _f == 5:
		p._request_attack("heavy")
	if _f == 40:
		var n := int(ai.stats.get("got_hit", 0))
		_check("throw", n >= 1 and p.weapon == "shuriken", "ai_got_hit=%d" % n)
		_next()


# 2) 부채꼴: 길게 눌렀다 놓기
func _fan(p: Player, ai: Duelist) -> void:
	if _f == 2:
		_hold_ai(ai)
		_place(p, ai, 7.0)
	if _f == 5:
		Input.action_press("attack")
		p.attack_pressed("", 0.0)
	if _f == 75:
		Input.action_release("attack")
		p.attack_released()
	if _f == 77:
		var n := 0
		for c in _game.get_children():
			if c is Projectile:
				n += 1
		_v.flying = n
	if _f == 110:
		_check("fan", int(_v.flying) >= 3 and int(ai.stats.get("got_hit", 0)) >= 1,
				"flying=%d ai_got_hit=%d" % [_v.flying, int(ai.stats.get("got_hit", 0))])
		_next()


# 3) AI 수리검을 막기 / 안 막기
func _block_shuriken(p: Player, ai: Duelist) -> void:
	if _f == 2:
		_hold_ai(ai)
		_place(p, ai, 8.0)
		p.set_guard("mid")
		Input.action_press("block")
		p.sm.go("block")
		ai.active = true
		ai._dist = 8.0
		ai._dir = Vector3(0, 0, 1)
		ai._start_attack("heavy")
		ai._feint_checked = true   # 이 점검은 막기만 본다 (속임수로 근접 공격으로 바뀌지 않게)
	if _f > 2 and _f < 60:
		if OS.get_environment("NW_DEBUG") != "" and _f % 4 == 0:
			print("f=%d ai=%s atk=%s p=%s guard=%s v=%s" % [_f, ai.state, ai._attack, p.sm.state, p.guard_dir, _v])
		ai._think_t = 1.0
		p.rotation.y = 0.0
		if p.sm.state == "free":
			p.sm.go("block")
	if _f == 60:
		_v.blocked = int(_v.get("me_blocked", 0)) + int(_v.get("me_parried", 0))
		Input.action_release("block")
		p.sm.go("free")
		_hold_ai(ai)
		_place(p, ai, 8.0)
		ai.active = true
		ai._dist = 8.0
		ai._dir = Vector3(0, 0, 1)
		ai._start_attack("heavy")
		ai._feint_checked = true   # 이 점검은 막기만 본다 (속임수로 근접 공격으로 바뀌지 않게)
	if _f > 60 and _f < 120:
		ai._think_t = 1.0
	if _f == 120:
		var hits := int(_v.get("me_hit", 0))
		_check("block_shuriken", _v.blocked >= 1 and hits >= 1, "blocked=%d then hit=%d" % [_v.blocked, hits])
		_next()


# 4) AI 가 멀리서 스스로 던진다
func _ai_throws(p: Player, ai: Duelist) -> void:
	if _f == 2:
		_place(p, ai, 10.0)
		p.controls_enabled = false
	if _f > 2:
		p.global_position = Vector3(0, 0.1, 5.0)
		p.velocity = Vector3.ZERO
	if _f == 260:
		var thrown := int(ai.stats.get("move_heavy", 0)) + int(ai.stats.get("move_charge", 0))
		var got := int(_v.get("me_hit", 0)) + int(_v.get("me_guard_broken", 0))
		_check("ai_throws", thrown >= 1 and got >= 1, "thrown=%d me_hit=%d" % [thrown, got])
		_next()


# 5) 맨몸: 훅, 훅, 돌려차기
func _fists(p: Player, ai: Duelist) -> void:
	if _f == 2:
		_hold_ai(ai)
		_place(p, ai, 1.7)
		_v.kick_seen = false
	if _f in [4, 22, 40]:
		p.attack_pressed("side", 1.0 if _f == 22 else -1.0)
		p.attack_released()
	if p._move == "slash3" and p._kick_leg and p._kick_leg.visible:
		_v.kick_seen = true
	if _f == 100:
		var hits := int(ai.stats.get("got_hit", 0))
		var lk := Weapons.move("fists", "slash3")
		_check("fists_combo", hits >= 3 and _v.kick_seen and str(lk.get("limb", "")) == "kick_round",
				"ai_got_hit=%d kick_leg_seen=%s" % [hits, _v.kick_seen])
		_next()


# 6) 봉: 옆으로 네 번 → 풍차 돌리기 (넘어뜨림)
func _staff(p: Player, ai: Duelist) -> void:
	if _f == 2:
		_hold_ai(ai)
		_place(p, ai, 2.2)
		_v.moves = []
		p.attack_started.connect(func(k): _v.moves.append(k))
	if _f in [4, 26, 48, 74]:
		_place(p, ai, 2.2)
		p.attack_pressed("side", -1.0)
		p.attack_released()
	if ai.sm.state == "stagger" and p._move == "spin":
		_v.spin_stagger = true
	if _f == 140:
		_check("staff_spin", "spin" in _v.moves and int(ai.stats.get("got_hit", 0)) >= 3 and Weapons.move("staff", "spin").get("knockdown", false),
				"moves=%s ai_got_hit=%d" % [_v.moves, int(ai.stats.get("got_hit", 0))])
		_next()


# 7) 겉모습
func _looks(p: Player, _ai: Duelist) -> void:
	if _f == 2:
		var made := 0
		var styles := CharacterBuild.STYLE_ORDER
		for wi in Weapons.ORDER.size():
			var w: String = Weapons.ORDER[wi]
			for c in CharacterBuild.COLORS.size():
				var b := CharacterBuild.new()
				b.weapon = w
				b.color = c
				b.hair = c % CharacterBuild.HAIRS.size()
				for pi in CharacterBuild.PART_ORDER.size():
					b.parts[CharacterBuild.PART_ORDER[pi]] = styles[(wi + c * 3 + pi * 2) % styles.size()]
				var r := BodyRig.new()
				r.build = b
				r.weapon = w
				_game.add_child(r)
				if r.blade_tip != null and r.blade_mat != null:
					made += 1
				r.queue_free()
		var a := CharacterBuild.new()
		var o := CharacterBuild.preset("검객")
		o.contrast_with(a)
		# 옷은 무기를 따라가지 않는다: 무기만 바꾸면 1인칭 장갑/신발도 그대로
		var k := CharacterBuild.new()
		k.wear_set("heavy")
		var g1: StandardMaterial3D = Weapons.fp_hand_mats("sword", k).glove
		var g2: StandardMaterial3D = Weapons.fp_hand_mats("fists", k).glove
		var free := g1.albedo_color == g2.albedo_color and k.part("feet") == "heavy"
		# 저장했다 불러와도 부위 옷이 남는다
		var sv := CharacterBuild.new()
		sv.parts = {"head": "monk", "torso": "rogue", "arms": "brawler", "legs": "lancer", "feet": "shadow"}
		var cfg := ConfigFile.new()
		cfg.set_value("look", "parts", sv.parts)
		var back = cfg.get_value("look", "parts", {})
		_check("looks", made == Weapons.ORDER.size() * CharacterBuild.COLORS.size() and o.color != a.color and free and back == sv.parts,
				"rigs=%d contrast=%d/%d weapon_free=%s" % [made, a.color, o.color, free])
		_next()


# 8) 수리검 수, 공중에서 던지기 (낙하 찍기로 바뀌지 않기), 떨어진 것 줍기
func _ammo_air(p: Player, ai: Duelist) -> void:
	if _f == 2:
		_hold_ai(ai)
		_place(p, ai, 8.0)
		_v.full = p.ammo
	if _f == 5:
		# 높이 떠 있을 때 Q: 던져야 한다
		p.global_position.y = 4.5
		p.velocity = Vector3.ZERO
		p._request_attack("heavy")
		_v.air_state = p.sm.state
		_v.air_move = p._move
	if _f == 30:
		_check("air_throw", _v.air_state == "attack" and _v.air_move == "heavy" and p.ammo == _v.full - 1,
				"state=%s move=%s ammo=%d/%d" % [_v.air_state, _v.air_move, p.ammo, p.ammo_max])
	if _f == 70:
		# 다 쓰면 못 던진다
		p.ammo = 0
		p._request_attack("heavy")
		_v.empty_state = p.sm.state
	if _f == 72:
		# 떨어진 수리검 위를 지나가면 줍는다
		var star := Projectile.launch(p.get_parent(), p.global_position + Vector3(0, 1.5, -1.0), Vector3.DOWN, 10.0,
				{"damage": 1, "ammo": true}, p)
		_v.star = star
	if _f == 110:
		_check("ammo_pickup", _v.empty_state != "attack" and p.ammo >= 1 and Weapons.falloff_mult("shuriken", 16.0) < 0.5
				and is_equal_approx(Weapons.falloff_mult("shuriken", 5.0), 1.0),
				"empty_state=%s ammo_after_pickup=%d" % [_v.empty_state, p.ammo])
		_next()

