extends SceneTree
## 자유로운 움직임 점검.
##  1) 달리기: Shift 를 누르면 걷기에서 점점 빨라진다 (순간 돌진 없음). Shift + 옆 = 옆으로 달리기 (피하기 아님)
##  2) 슬라이딩: 달리다 C → 미끄러짐, 몸이 낮아짐, 미끄러지다 Space → 빠르기를 지닌 채 점프
##  3) 연속기 갈래: 옆→위→위 = 베기, 올려베기, 쪼개기 / 옆 네 번 = 회전 베기
##  4) 달리며 찌르기  5) 슬라이딩 다리 베기 (넘어뜨림)  6) 벽 차고 베기
##  7) 피하기: 같은 방향키를 빠르게 두 번 (한 번은 그냥 걷기)  8) 바람 발판: 기둥 꼭대기와 한가운데로 날아간다
##  9) 돌기둥을 쓰러뜨려 AI 덮치기  10) AI 가 달려들기/미끄러지기/뛰어 베기를 쓰고, 바람 발판을 타고 쫓아온다
## 실행: godot --headless --fixed-fps 60 -s res://tests/free_move_test.gd   (사진: -- shots=폴더)

const GAME := preload("res://scenes/main.tscn")
const PARTS := 10
const TIER_TOP := 6.5

var _game: Node
var _f := 0
var _part := 0
var _fail := []
var _shots_dir := ""
var _v := {}
var _moves: Array = []


func _initialize() -> void:
	seed(11)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_shots_dir = a.substr(6)
	Game.opponent_mode = "preset"
	Game.opponent_preset = "검객"
	Game.test_player_build = CharacterBuild.new()
	_next()


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump", "attack", "sprint", "crouch", "grab"]:
		Input.action_release(a)


func _next() -> void:
	if _game:
		_game.queue_free()
	_part += 1
	_f = 0
	_v = {}
	_moves = []
	if _part > 1:
		_release_all()
	if _part > PARTS:
		print("FREEMOVE => %s %s" % ["OK" if _fail.is_empty() else "FAIL", _fail])
		quit(0 if _fail.is_empty() else 1)
		return
	Game.current_opponent = null
	Game.next_mode = "duel"
	_game = GAME.instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	if _part > PARTS:
		return false
	var p: Player = _game.player
	var ai: Duelist = _game.duelist
	if not p.controls_enabled or not ai.active and not _v.has("start"):
		return false
	_f += 1
	if _f == 1:
		_v.start = true
		_game.arena.director.running = false   # 바닥이 무너지지 않게
		p.attack_started.connect(func(k): _moves.append(k))
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		p.hp = 1000
		p.max_hp = 1000
		ai.parry_chance = 0.0
		ai.block_chance = 0.0
		ai.counter_chance = 0.0
	match _part:
		1: _sprint(p, ai)
		2: _slide(p, ai)
		3: _combo(p, ai)
		4: _run_thrust(p, ai)
		5: _sweep(p, ai)
		6: _wall_slash(p, ai)
		7: _dodge(p, ai)
		8: _pads(p, ai)
		9: _pillar(p, ai)
		10: _ai_moves(p, ai)
	return false


func _check(name: String, ok: bool, detail: String) -> void:
	if OS.get_environment("FM_ONLY") != "" and not ok:
		pass
	print("%-12s %s  => %s" % [name, detail, "OK" if ok else "FAIL"])
	if not ok:
		_fail.append(name)


func _hold_ai(ai: Duelist, pos: Vector3, face_y: float = 0.0) -> void:
	ai.active = false
	ai.global_position = pos
	ai.rotation.y = face_y
	ai.velocity = Vector3.ZERO
	ai._push = Vector3.ZERO
	ai.hp = 100000
	ai.max_hp = 100000
	ai.sm.go("idle")


func _place(p: Player, pos: Vector3, face_y: float) -> void:
	p.global_position = pos
	p.rotation.y = face_y
	p.head.rotation.x = 0.0
	p.velocity = Vector3.ZERO
	p.stamina = p.max_stamina


func _hspeed(n: Node3D) -> float:
	var v: Vector3 = n.velocity
	return Vector2(v.x, v.z).length()


# 1) 달리기
func _sprint(p: Player, ai: Duelist) -> void:
	if _f == 1:
		_hold_ai(ai, Vector3(-20, 0.1, 0))
		_place(p, Vector3(0, 0.1, -6), PI)   # +z 쪽을 본다
		Input.action_press("move_forward")
	if _f == 20:
		_v.walk = _hspeed(p)
		Input.action_press("sprint")
		p.sprint_pressed()
	if _f == 26:
		_v.early = _hspeed(p)
	if _f > 20 and p.sm.state == "dash":
		_v.dashed = true
	if _f == 70:
		_v.run = _hspeed(p)
		_shot("f1_sprint")
		Input.action_release("move_forward")
		Input.action_press("move_left")
		p.sprint_pressed()
	if _f == 110:
		_v.side = _hspeed(p)
		_v.side_state = p.sm.state
	if _f == 115:
		# 가만히 서서 Shift 만 눌러도 피하기(점멸)가 나가지 않는다
		Input.action_release("move_left")
		Input.action_release("sprint")
		p.velocity = Vector3.ZERO
		Input.action_press("sprint")
		p.sprint_pressed()
	if _f == 130:
		Input.action_release("sprint")
		var ok: bool = not _v.has("dashed") and _v.run > 7.3 and _v.early < _v.walk + 1.6 and _v.early > _v.walk + 0.2 \
				and _v.side > 5.6 and _v.side < _v.run and _v.side_state == "free"
		_check("SPRINT", ok, "walk=%.1f first0.1s=%.1f after0.8s=%.1f side_run=%.1f any_dash=%s side_state=%s"
				% [_v.walk, _v.early, _v.run, _v.side, _v.has("dashed"), _v.side_state])
		_next()


# 2) 슬라이딩과 슬라이딩 점프
func _slide(p: Player, ai: Duelist) -> void:
	if _f == 1:
		_hold_ai(ai, Vector3(-20, 0.1, 0))
		_place(p, Vector3(0, 0.1, -6), PI)
		Input.action_press("move_forward")
		Input.action_press("sprint")
	if _f == 35:
		_v.before = _hspeed(p)
		Input.action_press("crouch")
		p.crouch_pressed()
		_v.state = p.sm.state
	if _f == 44:
		_v.head = p.head.position.y
		_v.cap = p._cap.height
		_v.slide_speed = _hspeed(p)
		_shot("f2_slide")
	if _f == 50:
		Input.action_press("jump")
	if _f == 52:
		Input.action_release("jump")
	if _f == 58:
		_v.air = not p.is_on_floor()
		_v.air_speed = _hspeed(p)
	if _f == 70:
		Input.action_release("crouch")
		Input.action_release("sprint")
		Input.action_release("move_forward")
	if _f == 120:
		var ok: bool = _v.state == "slide" and _v.head < 1.1 and _v.cap < 1.2 and _v.air and _v.air_speed > 6.0 \
				and p._cap.height > 1.7
		_check("SLIDE", ok, "state=%s speed %.1f->%.1f head=%.2f cap=%.2f jump_air=%s air_speed=%.1f stood=%s"
				% [_v.state, _v.before, _v.slide_speed, _v.head, _v.cap, _v.air, _v.air_speed, p._cap.height > 1.7])
		_next()


# 3) 연속기 갈래
func _combo(p: Player, ai: Duelist) -> void:
	if _f == 1:
		_place(p, Vector3(0, 0.1, 1.0), 0.0)   # -z 쪽을 본다
		_hold_ai(ai, Vector3(0, 0.1, -0.9), PI)
	ai.global_position = Vector3(0, 0.1, -0.9)
	p.stamina = p.max_stamina
	var seq_a := ["", "high", "high"]
	var seq_b := ["", "", "", ""]
	var t := _f - 5
	if t >= 0 and t % 13 == 0:
		var i := t / 13
		var d := "skip"
		if i < seq_a.size():
			d = seq_a[i]
		elif i >= 6 and i - 6 < seq_b.size():
			d = seq_b[i - 6]
		if d != "skip":
			p.attack_pressed(d, 0.0)
			p.attack_released()
			if OS.get_environment("FM_DEBUG") != "":
				print("  click f=%d dir=%s state=%s move=%s phase=%s queued=%s buf=%s" % [_f, d, p.sm.state, p._move, p._attack_phase, p._queued, p._buffer_dir])
	if _f == 5 + 13 * 2 + 10:
		_shot("f3_cleave")
	if _f == 5 + 13 * 8 + 12:
		_shot("f3_spin")
	if _f == 5 + 13 * 16:
		var a := _moves.slice(0, 3)
		var b := _moves.slice(3)
		var ok: bool = a == ["slash1", "rising", "cleave"] and b == ["slash1", "slash2", "slash3", "spin"]
		_check("COMBO", ok, "up-up=%s side x4=%s ai_dmg=%d" % [a, b, 100000 - ai.hp])
		_next()


# 4) 달리며 찌르기
func _run_thrust(p: Player, ai: Duelist) -> void:
	if _f == 1:
		_place(p, Vector3(0, 0.1, 5.0), 0.0)
		_hold_ai(ai, Vector3(0, 0.1, -4.0), PI)
		Input.action_press("move_forward")
		Input.action_press("sprint")
	if not _v.has("clicked") and p.global_position.z - ai.global_position.z < 3.4 and _f > 10:
		_v.clicked = true
		_v.speed = _hspeed(p)
		p.attack_pressed("", 0.0)
		p.attack_released()
		_release_all()
	if p.sm.state == "attack" and p._attack_phase == "active":
		_shot_once("f4_run_thrust")
	if _f == 90:
		_check("RUNTHRUST", _moves.has("run_thrust") and ai.hp < 100000,
				"moves=%s speed=%.1f ai_dmg=%d" % [_moves, _v.get("speed", 0.0), 100000 - ai.hp])
		_next()


# 5) 슬라이딩 다리 베기: 넘어뜨린다
func _sweep(p: Player, ai: Duelist) -> void:
	if _f == 1:
		_place(p, Vector3(0, 0.1, 6.0), 0.0)
		_hold_ai(ai, Vector3(0, 0.1, -3.0), PI)
		Input.action_press("move_forward")
		Input.action_press("sprint")
	var gap := p.global_position.z - ai.global_position.z
	if not _v.has("slid") and gap < 5.2 and _f > 10:
		_v.slid = true
		Input.action_press("crouch")
		p.crouch_pressed()
	if _v.has("slid") and not _v.has("clicked") and gap < 3.0:
		_v.clicked = true
		_v.state = p.sm.state
		p.attack_pressed("", 0.0)
		p.attack_released()
		_release_all()
	if p.sm.state == "attack" and p._move == "sweep":
		_shot_once("f5_sweep")
	if ai.sm.state == "stagger":
		_v.down = maxf(_v.get("down", 0.0), ai._stagger_time)
	if _f == 100:
		_check("SWEEP", _moves.has("sweep") and _v.get("down", 0.0) >= 1.0,
				"from=%s moves=%s ai_down_time=%.2f" % [_v.get("state", ""), _moves, _v.get("down", 0.0)])
		_next()


# 6) 벽 차고 베기: 벽을 차고 뛴 직후 클릭
func _wall_slash(p: Player, ai: Duelist) -> void:
	if _f == 1:
		_hold_ai(ai, Vector3(0, 0.1, -3.0), PI)
		_place(p, Vector3(0, 0.9, 1.0), 0.0)
		p.velocity = Vector3(0, 1.0, 0)
		p._since_walljump = 0.0
	if _f == 3:
		p.attack_pressed("", 0.0)
		p.attack_released()
		_v.vz = p.velocity.z
	if _f == 6:
		_shot("f6_wall_slash")
	if _f == 80:
		_check("WALLSLASH", _moves.has("wall_slash") and _v.vz < -6.0 and ai.hp < 100000,
				"moves=%s fly_speed=%.1f ai_dmg=%d" % [_moves, -_v.vz, 100000 - ai.hp])
		_next()


# 7) 피하기: 방향키 한 번은 그냥 걷기, 빠르게 두 번이면 그쪽으로 짧게 피한다
func _dodge(p: Player, ai: Duelist) -> void:
	if _f == 1:
		_hold_ai(ai, Vector3(-20, 0.1, 0))
		_place(p, Vector3(0, 0.1, 4), 0.0)
	if _f == 10:
		_v.x0 = p.global_position.x
		p._tap_dodge("move_right", Vector2(1, 0))
		_v.one_tap = p.sm.state
	if _f == 40:
		p._tap_dodge("move_left", Vector2(-1, 0))
	if _f == 46:
		p._tap_dodge("move_left", Vector2(-1, 0))
		_v.two_tap = p.sm.state
	if _f == 70:
		var moved: float = _v.x0 - p.global_position.x
		_check("DODGE", _v.one_tap == "free" and _v.two_tap == "dash" and moved > 1.2,
				"one_tap=%s double_tap=%s moved_left=%.2f" % [_v.one_tap, _v.two_tap, moved])
		_next()


# 8) 바람 발판: 안쪽 발판은 기둥 꼭대기로, 바깥 발판은 경기장 한가운데로 날려 보낸다
func _pads(p: Player, ai: Duelist) -> void:
	var arena: Arena = _game.arena
	_hold_ai(ai, Vector3(-20, 0.1, 12))
	var tests := [0, 2]   # pad_sw (기둥 꼭대기), pad_w (한가운데)
	var k := int(_v.get("k", 0))
	if k >= tests.size():
		_check("LAUNCHPAD", _v.get("ok", 0) == tests.size(), str(_v.get("log", [])))
		_next()
		return
	var pad: LaunchPad = arena.pads[tests[k]]
	if not _v.has("t0"):
		_v.t0 = _f
		_place(p, pad.global_position + Vector3(0, 0.1, 0), 0.0)
		_v.peak = 0.0
	_v.peak = maxf(_v.peak, p.global_position.y)
	if OS.get_environment("FM_DEBUG") != "" and (_f - _v.t0) % 10 == 0:
		print("  fly ", p.global_position, " v=", p.velocity, " st=", p.sm.state, " fl=", p._flying)
	if _f - _v.t0 == 40:
		_shot("f8_pad_%d" % k)
	if _f - _v.t0 > 30 and p.is_on_floor() and not p._flying or _f - _v.t0 > 400:
		var land := p.global_position
		var err := Vector2(land.x - pad.target.x, land.z - pad.target.z).length()
		var ok: bool = err < 0.9 and absf(land.y - pad.target.y) < 0.4 and _v.peak > pad.target.y + 1.0
		var log: Array = _v.get("log", [])
		log.append("%s err=%.2f y=%.2f peak=%.1f" % [pad.id, err, land.y, _v.peak])
		_v.log = log
		_v.ok = int(_v.get("ok", 0)) + (1 if ok else 0)
		_v.k = k + 1
		_v.erase("t0")
		p.hp = 1000


# 9) 금 간 돌기둥을 쳐서 그 너머 AI 를 덮친다
func _pillar(p: Player, ai: Duelist) -> void:
	var arena: Arena = _game.arena
	var bp: BreakablePillar = arena.breakables["obelisk_nw"]
	if _f == 1:
		_place(p, Vector3(-19.5, 0.1, -10.4), 0.0)   # 기둥(-19.5, -12)을 북쪽으로 보고 선다
		_hold_ai(ai, Vector3(-19.5, 0.1, -15.0), PI)
		bp.hp = 1
	if _f == 20:
		p.attack_pressed("", 0.0)
		p.attack_released()
	if _f == 60:
		_shot("f9_pillar_fall")
	if _f == 150:
		_check("PILLAR", bp.is_broken() and 100000 - ai.hp >= BreakablePillar.CRUSH_DAMAGE - 2,
				"broken=%s ai_dmg=%d" % [bp.is_broken(), 100000 - ai.hp])
		_next()


# 10) AI 가 새 움직임을 쓴다: 떨어져 서 있는 상대에게 달려들거나 미끄러지거나 뛰어 베고, 옆의 상자를 찬다
func _ai_moves(p: Player, ai: Duelist) -> void:
	if _f == 1:
		_place(p, Vector3(0, 0.1, 5.0), PI)
		ai.global_position = Vector3(0, 0.1, -3.0)
		ai.hp = 100000
		ai.max_hp = 100000
		p.hp = 100000
	p.controls_enabled = true
	if ai.state == "windup" and ai._attack == "sweep":
		_shot_once("f10_ai_sweep")
	# 플레이어는 가끔 뒤로 물러나 거리를 벌린다
	# 플레이어는 가끔 뒤로 크게 물러나 거리를 벌린다
	var st0 := ai.stats
	var need: bool = st0.get("move_run_thrust", 0) + st0.get("move_sweep", 0) + st0.get("move_air_slash", 0) == 0
	if _f - int(_v.get("tp", 0)) > 90 and need and ai.state in ["approach", "circle", "idle"]:
		_v.tp = _f
		var away := p.global_position - ai.global_position
		away.y = 0
		p.global_position = ai.global_position + away.normalized() * 5.5
		p.velocity = Vector3.ZERO
	var st := ai.stats
	var moving: int = st.get("move_run_thrust", 0) + st.get("move_sweep", 0) + st.get("move_air_slash", 0)
	if moving >= 1 and not _v.has("moves_ok"):
		_v.moves_ok = _f
		_check("AIMOVES", true, "frames=%d run_thrust=%d sweep=%d air_slash=%d"
				% [_f, st.get("move_run_thrust", 0), st.get("move_sweep", 0), st.get("move_air_slash", 0)])
		# 이어서: 플레이어가 기둥 꼭대기에 올라가 있으면 AI 가 바람 발판을 타고 쫓아온다
		p.global_position = Vector3(-7.0, TIER_TOP + 0.1, 7.0)
		p.velocity = Vector3.ZERO
		ai.global_position = Vector3(-13.0, 0.1, 10.5)
		ai.velocity = Vector3.ZERO
		ai.traits["wall_climb"] = false
		_v.chase_t = _f
	if _v.has("chase_t"):
		p.global_position = Vector3(-7.0, TIER_TOP + 0.1, 7.0)
		p.velocity = Vector3.ZERO
		if st.get("launch", 0) >= 1 and ai.global_position.y > TIER_TOP - 0.5 and ai.is_on_floor():
			_check("AIPAD", true, "frames=%d launches=%d" % [_f - int(_v.chase_t), st.get("launch", 0)])
			_next()
		elif _f - int(_v.chase_t) > 1200:
			_check("AIPAD", false, "launches=%d ai_pos=%s" % [st.get("launch", 0), ai.global_position])
			_next()
	elif _f >= 3000:
		if OS.get_environment("FM_DEBUG") != "":
			print(st)
		_check("AIMOVES", false, "frames=%d run_thrust=%d sweep=%d air_slash=%d"
				% [_f, st.get("move_run_thrust", 0), st.get("move_sweep", 0), st.get("move_air_slash", 0)])
		_next()


var _shot_done := {}


func _shot_once(shot_name: String) -> void:
	if _shot_done.has(shot_name):
		return
	_shot_done[shot_name] = true
	_shot(shot_name)


func _shot(shot_name: String) -> void:
	if _shots_dir == "":
		return
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_shots_dir, shot_name])
