extends SceneTree
## 높이와 경기장 점검.
##  1) 낙하 찍기: 다리에서 뛰어내리며 아래 AI 를 찍는다
##  2) 밀어 떨어뜨리기: 가장자리의 AI 를 내려찍기(Q)로 날려 낭떠러지로 떨어뜨린다
##  3) 난간 매달리기: 회랑 지붕에서 밀려 떨어지다 난간을 잡고, 클릭으로 뛰어올라 벤다
##  4) 짚라인: 동쪽 탑에서 줄을 잡고 서쪽 지붕까지 내려간다
##  5) 아이템과 바닥 붕괴: 아이템을 먹으면 회복, 시간이 되면 바깥 고리가 무너지고 AI 가 가운데로 피한다
##  6) AI 낙하 찍기: 다리 위 AI 가 아래 플레이어에게 뛰어내리며 찍는다
##  7) AI 아이템 다툼: 아이템이 생기면 AI 가 가지러 간다
## 실행: godot --headless --fixed-fps 60 -s res://tests/vertical_test.gd   (사진: -- shots=폴더)

const GAME := preload("res://scenes/main.tscn")

var _game: Node
var _f := 0
var _part := 0
var _fail := []
var _shots_dir := ""
var _v := {}
var _shot_done := {}


func _initialize() -> void:
	seed(7)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_shots_dir = a.substr(6)
	Game.opponent_mode = "preset"
	Game.opponent_preset = "검객"
	Game.test_player_build = CharacterBuild.new()
	_next()


func _next() -> void:
	if _game:
		_game.queue_free()
	_part += 1
	_f = 0
	_v = {}
	for a in ["move_forward", "move_back", "jump", "attack", "sprint"]:
		Input.action_release(a)
	if _part > 7:
		print("VERTICAL => %s %s" % ["OK" if _fail.is_empty() else "FAIL", _fail])
		quit(0 if _fail.is_empty() else 1)
		return
	Game.current_opponent = null
	Game.next_mode = "duel"
	_game = GAME.instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	if _part > 7:
		return false
	var p: Player = _game.player
	var ai: Duelist = _game.duelist
	# 3, 2, 1 시작 신호가 끝난 뒤부터 센다
	if not p.controls_enabled or not ai.active and not _v.has("start"):
		return false
	_f += 1
	if _f == 1:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		p.hp = 1000
		p.max_hp = 1000
	match _part:
		1:
			_plunge(p, ai)
		2:
			_knock_off(p, ai)
		3:
			_hang(p, ai)
		4:
			_zip(p, ai)
		5:
			_pickup_collapse(p, ai)
		6:
			_ai_plunge(p, ai)
		7:
			_ai_pickup(p, ai)
	return false


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s %s  => %s" % [name, detail, "OK" if ok else "FAIL"])
	if not ok:
		_fail.append(name)


func _hold_ai(ai: Duelist, pos: Vector3) -> void:
	ai.active = false
	ai.global_position = pos
	ai.velocity = Vector3.ZERO
	ai._push = Vector3.ZERO
	ai.sm.go("idle")


# 1) 북쪽 다리 가장자리에서 남쪽으로 걸어 나가 아래 AI 를 찍는다
func _plunge(p: Player, ai: Duelist) -> void:
	if not _v.has("start"):
		_v.start = true
		_hold_ai(ai, Vector3(0, 0.1, -4.2))
		ai.rotation.y = PI
		_v.hp = ai.hp
		p.global_position = Vector3(0, 6.6, -6.4)
		p.velocity = Vector3.ZERO
		p.rotation.y = PI          # 남쪽을 본다
		p.head.rotation.x = deg_to_rad(-40)
		Input.action_press("move_forward")
	if not p.is_on_floor() and p.global_position.y < 5.8 and not _v.has("clicked"):
		_v.clicked = true
		Input.action_release("move_forward")
		p._request_attack("combo")
	if p.sm.state == "plunge":
		_shot_once("v1_plunge")
	if _f == 150:
		_shot("v1_after")
		_check("PLUNGE", p.sm.counts.get("plunge", 0) >= 1 and ai.hp < _v.hp,
				"plunges=%d ai_hp %d->%d" % [p.sm.counts.get("plunge", 0), _v.hp, ai.hp])
		_next()


# 2) 남쪽 가장자리에 선 AI 를 Q 로 날려 떨어뜨린다
func _knock_off(p: Player, ai: Duelist) -> void:
	if not _v.has("start"):
		_v.start = true
		_hold_ai(ai, Vector3(0, 0.1, 25.6))
		_v.hp = ai.hp
		p.global_position = Vector3(0, 0.1, 23.7)
		p.velocity = Vector3.ZERO
		p.rotation.y = PI
		p.head.rotation.x = 0.0
	if _f == 8:
		p._request_attack("heavy")
	if _f == 40:
		_shot("v2_knock")
	if _f == 160:
		_check("KNOCK_OFF", ai.stats.get("void", 0) >= 1 and ai.hp < _v.hp - 25,
				"void=%d ai_hp %d->%d pos=%s" % [ai.stats.get("void", 0), _v.hp, ai.hp, ai.global_position])
		_next()


# 3) 회랑 지붕 남쪽 끝에서 북쪽을 보고 서 있다가 남쪽으로 밀려 떨어진다 → 난간을 잡는다 → 클릭
func _hang(p: Player, ai: Duelist) -> void:
	if not _v.has("start"):
		_v.start = true
		_hold_ai(ai, Vector3(0, 3.1, -14.5))
		p.global_position = Vector3(0, 3.1, -12.6)
		p.velocity = Vector3.ZERO
		p.rotation.y = 0.0
		p.head.rotation.x = 0.0
		p.attack_started.connect(func(m): _v["atk_" + m] = true)
	if _f == 6:
		p.apply_knockback(Vector3(0, 2.5, 4.5))
	if p.sm.state == "hang" and not _v.has("hung"):
		_v.hung = _f
	if _v.has("hung") and _f == _v.hung + 12:
		_shot("v3_hang")
		p.attack_pressed()
		p.attack_released()
	if _f == 150:
		_shot("v3_after")
		_check("LEDGE", p.sm.counts.get("hang", 0) >= 1 and _v.has("atk_ledge_slash") and p.global_position.y > 2.9,
				"hangs=%d ledge_slash=%s y=%.2f" % [p.sm.counts.get("hang", 0), _v.has("atk_ledge_slash"), p.global_position.y])
		_next()


# 4) 동쪽 탑 위 줄 밑에서 점프해서 줄을 잡는다
func _zip(p: Player, ai: Duelist) -> void:
	if not _v.has("start"):
		_v.start = true
		_hold_ai(ai, Vector3(20, 0.1, 20))
		p.global_position = Vector3(14.2, 6.6, 1.5)
		p.velocity = Vector3.ZERO
		p.rotation.y = deg_to_rad(90)   # 서쪽을 본다
		p.head.rotation.x = deg_to_rad(-10)
	if _f == 10:
		Input.action_press("jump")
	if _f == 12:
		Input.action_release("jump")
	if p.sm.state == "zip" and p.sm.time > 0.6:
		_shot_once("v4_zip")
	if _f == 260:
		_check("ZIPLINE", p.sm.counts.get("zip", 0) >= 1 and p.global_position.x < -8.0 and p.global_position.y > 3.0,
				"zips=%d pos=%s" % [p.sm.counts.get("zip", 0), p.global_position])
		_next()


# 5) 아이템을 먹고, 시간을 당겨 바깥 고리가 무너지게 한다. AI 는 바깥에 서 있다가 가운데로 피해야 한다.
func _pickup_collapse(p: Player, ai: Duelist) -> void:
	var d: ArenaDirector = _game.arena.director
	if not _v.has("start"):
		_v.start = true
		p.hp = 600
		p.hp_changed.emit(p.hp, p.max_hp)
		d.time = d.PICKUP_FIRST - 0.05
		_v.order = d._order_i
		ai.global_position = Vector3(-25, 0.1, 0)
		ai.target = p
		p.global_position = Vector3(0, 0.1, 3)
	if _f == 10:
		# 첫 아이템(회복)으로 걸어간다
		var pk: ArenaPickup = d.pickups[0] if d.pickups.size() > 0 else null
		_v.has_pickup = pk != null
		if pk:
			_v.kind = pk.kind
			p.global_position = pk.global_position + Vector3(0, 0.05, 0)
			p.velocity = Vector3.ZERO
	if _f == 14:
		_check("PICKUP", _v.has_pickup and p.hp > 600 and d.pickups.all(func(x): return not is_instance_valid(x) or x.taken),
				"kind=%s hp=%d" % [_v.get("kind", "-"), p.hp])
		p.global_position = Vector3(0, 0.1, 3)
		p.velocity = Vector3.ZERO
		d.time = 30.0 - 5.2    # 곧 경고
	if _f == 60:
		_shot("v5_warn")
	if _f == 380:
		_shot("v5_collapsed")
		var r := Arena.ring_of(ai.global_position)
		_check("COLLAPSE", d.collapsed >= 1 and _game.arena.alive_ring == 2 and r <= 2,
				"collapsed=%d alive_ring=%d ai_ring=%d ai_void=%d" % [d.collapsed, _game.arena.alive_ring, r, ai.stats.get("void", 0)])
		_next()


# 6) AI 가 남쪽 다리 위, 플레이어는 그 앞 바닥 → AI 가 뛰어내리며 찍는다
func _ai_plunge(p: Player, ai: Duelist) -> void:
	if not _v.has("start"):
		_v.start = true
		ai.global_position = Vector3(0, 6.6, 7.0)
		ai.velocity = Vector3.ZERO
		p.global_position = Vector3(0.5, 0.1, 3.6)
		p.velocity = Vector3.ZERO
		p.attack_received.connect(func(r): _v["got_" + r] = true)
	if ai.state == "plunge":
		_shot_once("v6_ai_plunge")
	if ai.stats.get("move_plunge", 0) >= 1 and not _v.has("t"):
		_v.t = _f
	if _f == 400 or (_v.has("t") and _f == _v.t + 90):
		_check("AI_PLUNGE", ai.stats.get("move_plunge", 0) >= 1, "plunges=%d hit=%s stats=%s" % [
				ai.stats.get("move_plunge", 0), _v.has("got_hit") or _v.has("got_guard_broken"), ai.stats])
		_next()


# 7) 높은 곳에 아이템이 생기면 AI 가 가지러 간다 (플레이어는 멀리 있음)
func _ai_pickup(p: Player, ai: Duelist) -> void:
	var d: ArenaDirector = _game.arena.director
	if not _v.has("start"):
		_v.start = true
		p.global_position = Vector3(-14, 3.6, -2)   # 서쪽 지붕
		p.velocity = Vector3.ZERO
		ai.global_position = Vector3(10, 0.1, -10)
		ai.hp = int(ai.max_hp * 0.5)
		ai.traits["wall_climb"] = true
		d.time = d.PICKUP_FIRST - 0.05
		d._rng.seed = 3
	if _f == 6 and d.pickups.size() > 0:
		_v.spot = d.pickups[0].spot.id
		_v.kind = d.pickups[0].kind
	if ai._seeking():
		_v.sought = true
	if _f == 900 or (_v.has("spot") and d.pickups.size() > 0 and d.pickups[0].taken):
		var taken_by_ai: bool = ai.hp > int(ai.max_hp * 0.5)
		_check("AI_PICKUP", _v.has("sought") and taken_by_ai, "spot=%s kind=%s sought=%s ai_hp=%d/%d frames=%d" % [
				_v.get("spot", "-"), _v.get("kind", "-"), _v.has("sought"), ai.hp, ai.max_hp, _f])
		_next()


func _shot_once(shot_name: String) -> void:
	if _shot_done.has(shot_name):
		return
	_shot_done[shot_name] = true
	_shot(shot_name)


func _shot(shot_name: String) -> void:
	if _shots_dir == "":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_shots_dir.path_join(shot_name + ".png"))
