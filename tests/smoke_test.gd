extends SceneTree
## 자동 점검.
##  1) 연습장: 앞으로 걸어가 허수아비를 베어 본다.
##  2) 벽 타기: 기둥을 타고 올라가고, 건물 벽을 따라 달려 본다.
##  3) 추격: 지붕, 기둥 위로 올라간 플레이어를 AI 가 찾아 올라오는지 본다.
##  4) 대결: AI 가 다가와 공격하는지, 막기/튕겨내기가 되는지, AI 를 때릴 수 있는지 본다.
##     (자동 조종: 상대 칼이 빛나면 막고, 빈틈이 보이면 벤다)
##  5) 수싸움(only=rps): 가위바위보(공격>잡기>막기>공격), 방향 막기, 속임수, 던져서 벽꽝을 하나씩 확인한다.
## 자동 조종(bot=): good 방향을 읽고 막고 섞어 공격 / masher 옆 베기만 연타 / blocker 옆으로만 막고 버팀
##                  grabber 잡기만 / dodger 옆으로 피하고 반격
## 실행: godot --headless --fixed-fps 60 -s res://tests/smoke_test.gd
## 사진 남기기: 끝에 -- shots=폴더   /  대결만: -- only=duel

const GAME := preload("res://scenes/main.tscn")

var _game: Node
var _frame := 0
var _shots_dir := ""
var _only := ""
var _phase := "practice"
var _fail := []
var _results := {}
var _min_dist := 99.0
var _parries := 0
var _bot := "good"   # good: 막고 튕겨내는 자동 조종, masher: 막지 않고 마구 베기만, dodger: 옆으로 피하고 반격
var _moves := {}
var _counters := 0
var _dodge_side := 1.0
var _ai_preset := "검객"
var _my_preset := ""
var _my_weapon := ""   # weapon=창 처럼 내 무기 (sword/greatsword/daggers/spear)
var _ai_weapon := ""   # aiweapon=... AI 무기
var _trace := false   # trace=1: 대결 중 AI 상태 변화와 결과를 한 줄씩 출력


func _initialize() -> void:
	var seed_value := 20261124
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seed="):
			seed_value = int(a.substr(5))
		if a.begins_with("shots="):
			_shots_dir = a.substr(6)
		elif a.begins_with("bot="):
			_bot = a.substr(4)
		elif a.begins_with("only="):
			_only = a.substr(5)
		elif a.begins_with("preset="):
			_ai_preset = a.substr(7)
		elif a.begins_with("me="):
			_my_preset = a.substr(3)
		elif a.begins_with("weapon="):
			_my_weapon = a.substr(7)
		elif a.begins_with("aiweapon="):
			_ai_weapon = a.substr(9)
		elif a.begins_with("linger="):
			_linger = int(a.substr(7))
		elif a == "trace=1":
			_trace = true
	seed(seed_value)
	# 매번 같은 결과가 나오도록 상대와 내 캐릭터를 정해 둔다
	Game.opponent_mode = "preset"
	Game.opponent_preset = _ai_preset
	Game.current_opponent = null
	Game.test_player_build = CharacterBuild.new() if _my_preset == "" else CharacterBuild.preset(_my_preset)
	if _my_weapon != "":
		Game.test_player_build.weapon = _my_weapon
	if _ai_weapon != "":
		Game.current_opponent = CharacterBuild.preset(_ai_preset)
		Game.current_opponent.weapon = _ai_weapon
	_check_build_rules()
	_check_weapon_table()
	if _only == "duel":
		_start_duel()
	elif _only == "parkour":
		_start_parkour()
	elif _only == "chase":
		_start_chase()
	elif _only == "skills":
		_start_skills()
	elif _only == "rps":
		_start_rps()
	elif _only == "weapons":
		_start_weapons()
	else:
		Game.next_mode = "practice"
		_game = GAME.instantiate()
		root.add_child(_game)


func _start_duel() -> void:
	_phase = "duel"
	_frame = 0
	Game.next_mode = "duel"
	_game = GAME.instantiate()
	root.add_child(_game)


var _linger := 0
var _last_us := 0
var _spikes := []


func _process(_delta: float) -> bool:
	_frame += 1
	var now := Time.get_ticks_usec()
	if _last_us > 0 and _frame > 20:
		var ms := (now - _last_us) / 1000.0
		_spikes.append([ms, "%s#%d" % [_phase, _frame]])
	_last_us = now
	if _phase == "practice":
		_practice_step()
	elif _phase == "parkour":
		_parkour_step()
	elif _phase == "chase":
		_chase_step()
	elif _phase == "skills":
		_skills_step()
	elif _phase == "rps":
		_rps_step()
	elif _phase == "weapons":
		_weapons_step()
	elif _phase == "duel":
		_duel_step()
	return false


func _practice_step() -> void:
	var player: Player = _game.player
	if _frame == 3:
		_game.hud.hide_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_shot("p1_start")
	if _frame > 3 and _frame < 100:
		Input.action_press("move_forward")
	if _frame == 100:
		Input.action_release("move_forward")
	if _frame == 4:
		player.attack_started.connect(func(m): _moves[m] = _moves.get(m, 0) + 1)
	# 연속 베기: 짧게 세 번 클릭
	if _frame in [110, 122, 134]:
		_click(player, true)
	if _frame in [113, 125, 137]:
		_click(player, false)
	if _frame == 117:
		_shot("p2_swing")
	if _frame == 145:
		_shot("p3_finisher")
	# 차지 베기: 길게 눌렀다 떼기
	if _frame == 175:
		_click(player, true)
	if _frame == 215:
		_shot("p4_charge")
	if _frame == 250:
		_click(player, false)
	if _frame == 290:
		player._request_attack("heavy")
	# 옆으로 대시
	if _frame == 340:
		Input.action_press("move_left")
		player.try_dash()
	if _frame == 344:
		_shot("p5_dash_left")
	if _frame == 350:
		Input.action_release("move_left")
	if _frame == 380:
		var ok: bool = _game.hits >= 3 and _moves.has("slash3") and _moves.has("charge") \
				and player.sm.counts.get("dash", 0) >= 1
		print("PRACTICE hits=%d moves=%s  => %s" % [_game.hits, _moves, "OK" if ok else "FAIL"])
		if not ok:
			_fail.append("practice moves")
		_game.queue_free()
		_start_parkour()


# ---------------- 벽 타기 ----------------

var _max_y := 0.0


func _start_parkour() -> void:
	_phase = "parkour"
	_frame = 0
	Game.next_mode = "practice"
	_game = GAME.instantiate()
	root.add_child(_game)


func _parkour_step() -> void:
	var player: Player = _game.player
	if _frame == 3:
		_game.hud.hide_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# 북동쪽 기둥 남쪽 면 앞에서, 기둥을 바라본다
		player.global_position = Vector3(7, 0.1, -4.8)
		player.rotation.y = 0.0
		player.head.rotation.x = deg_to_rad(10)
	if _frame == 6:
		Input.action_press("move_forward")
	if _frame == 22:
		Input.action_press("jump")
	if _frame == 24:
		Input.action_release("jump")
	if player.sm.state == "climb":
		_shot_once("k1_climb")
	_max_y = maxf(_max_y, player.global_position.y)
	if _frame < 170 and player.is_on_floor() and player.global_position.y > 5.5:
		Input.action_release("move_forward")   # 꼭대기에 올라섰으면 멈춘다
	if _frame == 170:
		Input.action_release("move_forward")
		player.head.rotation.x = deg_to_rad(-15)
		player.rotation.y = deg_to_rad(150)
		_shot("k2_pillar_top")
	if _frame == 180:
		var ok: bool = player.global_position.y > 5.5 and player.sm.counts.get("climb", 0) >= 1
		print("CLIMB max_y=%.2f now_y=%.2f climbs=%d  => %s" % [_max_y, player.global_position.y,
				player.sm.counts.get("climb", 0), "OK" if ok else "FAIL"])
		if not ok:
			_fail.append("wall climb")
		# 서쪽 건물 동쪽 벽 옆에서 벽을 따라 달린다
		player.global_position = Vector3(-10.9, 0.1, 4.0)
		player.velocity = Vector3.ZERO
		player.rotation.y = 0.0
		player.head.rotation.x = 0.0
		_max_y = 0.0
	if _frame == 182:
		Input.action_press("move_forward")
		Input.action_press("sprint")
	if _frame == 194:
		Input.action_press("move_left")
		Input.action_press("jump")
	if _frame == 196:
		Input.action_release("jump")
	if player.sm.state == "wallrun" and player.sm.time > 0.25:
		_shot_once("k3_wallrun")
	if _frame == 260:
		for a in ["move_forward", "sprint", "move_left"]:
			Input.action_release(a)
		var ok: bool = player.sm.counts.get("wallrun", 0) >= 1
		print("WALLRUN runs=%d  => %s" % [player.sm.counts.get("wallrun", 0), "OK" if ok else "FAIL"])
		if not ok:
			_fail.append("wall run")
		_game.queue_free()
		if _only == "parkour":
			_report_and_quit()
		else:
			_start_chase()


# ---------------- 추격 ----------------

## [플레이어 자리, AI 가 이 높이 위로 올라오면 성공, AI 가 벽을 탈 수 있나, 이름]
const CHASE_GOALS := [
	[Vector3(-14, 3.6, -1), 3.4, true, "west_roof"],
	[Vector3(-7, 6.6, -7), 6.1, true, "pillar_top"],
	[Vector3(13, 3.1, -2.5), 2.95, false, "east_roof_by_stairs"],
	[Vector3(-2, 6.6, 7), 6.1, false, "bridge_by_lift"],
]
var _goal := 0
var _goal_start := 0


func _start_chase() -> void:
	_phase = "chase"
	_frame = 0
	_goal = 0
	Game.next_mode = "duel"
	_game = GAME.instantiate()
	root.add_child(_game)


func _chase_step() -> void:
	var player: Player = _game.player
	var ai: Duelist = _game.duelist
	if _frame == 3:
		_game.hud.hide_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.hp = 100000
	if not ai.active:
		return
	if _goal_start == 0:
		_goal_start = _frame
		_set_goal(player, ai)
	var g: Array = CHASE_GOALS[_goal]
	var to_ai := ai.global_position - player.global_position
	player.rotation.y = atan2(-to_ai.x, -to_ai.z)
	if ai.state == "climb":
		_shot_once("c_climb_" + g[3])
	var took := _frame - _goal_start
	if ai.global_position.y > g[1] or took > 1200:
		var ok: bool = ai.global_position.y > g[1]
		print("CHASE %s frames=%d ai_y=%.2f climbs=%d unstuck=%d  => %s" % [g[3], took, ai.global_position.y,
				ai.stats.get("climb", 0), ai.stats.get("unstuck", 0), "OK" if ok else "FAIL"])
		if not ok:
			_fail.append("AI chase " + g[3])
		_shot("c_reached_" + g[3])
		_goal += 1
		if _goal >= CHASE_GOALS.size():
			_game.queue_free()
			if _only == "chase":
				_report_and_quit()
			else:
				_start_skills()
			return
		_goal_start = _frame
		_set_goal(player, ai)


func _set_goal(player: Player, ai: Duelist) -> void:
	var g: Array = CHASE_GOALS[_goal]
	player.global_position = g[0]
	player.velocity = Vector3.ZERO
	ai.traits["wall_climb"] = g[2]
	ai.skills._cd["grapple"] = 999.0   # 갈고리 지름길 없이 길찾기만 본다
	ai.global_position = Vector3(0, 0.1, 0)
	ai.velocity = Vector3.ZERO
	ai._repath_t = 0.0


func _report_and_quit() -> void:
	print("SMOKE => %s %s" % ["OK" if _fail.is_empty() else "FAIL", _fail])
	_phase = "done"
	quit(0 if _fail.is_empty() else 1)


func _duel_step() -> void:
	var player: Player = _game.player
	var ai: Duelist = _game.duelist
	if _frame == 3:
		_game.hud.hide_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.attack_received.connect(func(r): _results[r] = _results.get(r, 0) + 1)
		if _trace:
			ai.sm.changed.connect(func(_a, b): print("  %4d AI %-8s %s d=%.1f" % [_frame, b, ai._attack if b in ["windup", "strike"] else "", ai._dist]))
			player.attack_received.connect(func(r): print("  %4d   me <- %s" % [_frame, r]))
			player.sm.changed.connect(func(_a, b): print("  %4d   me %s %s" % [_frame, b, player._move]))
	if _frame == 150:
		_shot("d1_face")
	if not is_instance_valid(ai) or ai.dead or player.dead or _frame > 1500:
		# 영상용: 끝난 뒤 승리/패배 음악까지 담으려고 조금 더 기다린다 (-- linger=프레임)
		if _linger > 0:
			_linger -= 1
			Input.action_release("attack")
			Input.action_release("block")
			Input.action_release("move_forward")
			return
		_finish_duel(player, ai)
		return
	if not ai.active:
		return
	_autopilot(player, ai)
	if _frame % 90 == 0:
		_shot("d_%04d" % _frame)
	# 새 동작이 처음 나올 때 한 장씩
	if player.counter_ready():
		_shot_once("e_counter_window")
	if ai.state == "windup" and ai._attack == "charge" and ai._state_t > 0.7:
		_shot_once("e_ai_charge")
	if ai.state == "windup" and ai._attack == "slash3":
		_shot_once("e_ai_combo3")
	if ai.state == "stagger" and ai._state_t > 0.1:
		_shot_once("e_ai_stagger")
	if player.sm.state == "stagger" and player._stun_kind == "stagger":
		_shot_once("e_player_stagger")
	# 수싸움 장면
	var adir := ai.attack_dir()
	if adir != "" and ai.windup_progress() > 0.6 and ai.state == "windup":
		_shot_once("m_ai_windup_" + adir)
	if ai.state == "block" and ai._state_t > 0.15:
		_shot_once("m_ai_block_" + ai.guard_dir)
	if player.blocking and player.sm.time > 0.1:
		_shot_once("m_me_block_" + player.guard_dir)
	if player.sm.state == "stagger" and player._stun_kind == "thrown" and player.sm.time > 0.2:
		_shot_once("m_me_thrown")


## 아주 단순한 자동 조종: 상대를 바라보고, 칼이 빛나면 막고, 빈틈에 벤다.
func _autopilot(player: Player, ai: Duelist) -> void:
	var to_ai := ai.global_position - player.global_position
	to_ai.y = 0
	var dist := to_ai.length()
	_min_dist = minf(_min_dist, dist)
	player.rotation.y = atan2(-to_ai.x, -to_ai.z)
	player.head.rotation.x = deg_to_rad(-6)

	if _bot == "dodger":
		_dodger(player, ai, dist)
		return
	if _bot == "masher":
		if dist > 2.0:
			Input.action_press("move_forward")
		else:
			Input.action_release("move_forward")
		if dist < 2.6 and _frame % 25 == 0:
			player._request_attack("light")
		return
	if _bot == "blocker":
		# 옆으로만 막고 버티다가, 막아낸 뒤 한 번 벤다
		Input.action_press("move_forward") if dist > 2.2 else Input.action_release("move_forward")
		if ai.state in ["stagger", "recover"] and dist < 2.6 and _frame % 10 == 0:
			Input.action_release("block")
			player._request_attack("light")
		elif player.sm.state == "free":
			player.guard_dir = "side"
			Input.action_press("block")
		return
	if _bot == "grabber":
		Input.action_press("move_forward") if dist > 1.5 else Input.action_release("move_forward")
		if dist < 1.9 and player.sm.state == "free" and _frame % 12 == 0:
			player.try_grab()
		return
	var threat := ai.state == "windup"
	var time_left := 1.0
	if threat:
		time_left = ai._windup_len - ai._state_t
	var adir := ai.attack_dir()
	if adir == "grab":
		# 잡으려 한다: 막지 말고 먼저 벤다 (공격 > 잡기)
		Input.action_release("block")
		if player.sm.state in ["free", "block"] and dist < 2.6:
			player.attack_pressed("mid")
			player.attack_released()
		return
	# 막기: 상대 공격 방향을 보고, 칼이 닿기 직전에 눌러서 튕겨내기를 노린다
	if threat and time_left < 0.14 and dist < 3.2:
		player.set_guard(adir)
		Input.action_press("block")
	elif player.blocking and adir != "" and adir != player.guard_dir:
		player.set_guard(adir)   # 속임수로 방향이 바뀌면 다시 맞춘다
	elif ai.state != "strike":
		Input.action_release("block")
	# 거리 조절
	if dist > 2.3 and not threat:
		Input.action_press("move_forward")
	else:
		Input.action_release("move_forward")
	# 상대가 막고 서 있으면 잡는다 (잡기 > 막기)
	if ai.state == "block" and dist < 1.9 and player.sm.state == "free" and _frame % 10 == 0:
		player.try_grab()
		return
	# 빈틈 공격: 방향을 섞는다
	if ai.state in ["stagger", "recover"] and dist < 2.6 and not player.blocking and _frame % 6 == 0:
		player.attack_pressed(["side", "high", "mid"][randi() % 3])
		player.attack_released()


func _click(player: Player, down: bool) -> void:
	if down:
		Input.action_press("attack")
		player.attack_pressed()
	else:
		Input.action_release("attack")
		player.attack_released()


## 상대가 휘두르기 직전에 옆으로 대시하고, 반격 기회가 오면 바로 벤다.
func _dodger(player: Player, ai: Duelist, dist: float) -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	if player.counter_ready():
		_counters += 1
		player.attack_pressed()
		player.attack_released()
		return
	if ai.state == "windup":
		var left: float = Weapons.move(ai.weapon, ai._attack).ai_windup - ai._state_t
		if left < 0.08 and dist < 3.4 and player.sm.state == "free":
			_dodge_side = -_dodge_side
			Input.action_press("move_right" if _dodge_side > 0 else "move_left")
			player.try_dash()
			return
	if dist > 2.3 and ai.state != "windup":
		Input.action_press("move_forward")
	else:
		Input.action_release("move_forward")
	if ai.state in ["stagger", "recover"] and dist < 2.6 and _frame % 8 == 0:
		player._request_attack("combo")


## 수싸움 결과 출력용
func _ai_summary(ai: Duelist) -> String:
	var keys := ["move_grab", "grab_thrown", "grab_beaten", "feint", "feint_grab", "feint_switch", "feint_stop",
			"move_overhead", "move_thrust", "move_slash1", "wrong_guard", "got_blocked", "got_parried", "got_hit",
			"got_grab_thrown", "got_grab_beaten", "charge_cancel", "wall_slam"]
	var out := []
	for k in keys:
		if ai.stats.has(k):
			out.append("%s=%d" % [k, ai.stats[k]])
	return " ".join(out)


func _finish_duel(player: Player, ai: Duelist) -> void:
	Input.action_release("block")
	Input.action_release("move_forward")
	_shot("d9_end")
	var ai_hp: int = ai.hp if is_instance_valid(ai) else 0
	print("DUEL frames=%d min_dist=%.2f player_hp=%d ai_hp=%d results=%s" % [
		_frame, _min_dist, player.hp, ai_hp, _results])
	if _min_dist > 3.0:
		_fail.append("AI never approached")
	if _results.is_empty():
		_fail.append("AI never attacked")
	if _bot == "dodger":
		print("COUNTERS ", _counters, " player states ", player.sm.counts)
		_fail.clear()
		if _counters == 0:
			_fail.append("counter never happened")
	if _bot == "masher":
		_fail.clear()
		if _results.is_empty():
			_fail.append("AI never attacked")
	elif ai_hp >= ai.max_hp:
		_fail.append("could not damage AI")
	if _bot == "good" and not (_results.has("blocked") or _results.has("parried")):
		_fail.append("block/parry never worked")
	if _bot in ["blocker", "grabber"]:
		# 한 가지만 하는 상대는 AI 가 읽고 이겨야 한다
		_fail.clear()
		if ai_hp <= 0:
			_fail.append("AI lost to one-trick " + _bot)
	if is_instance_valid(ai):
		print("AI stats ", ai.stats)
		print("MIND bot=%s %s  block_ratio=%.2f grab_rate=%.2f guard_skill=%.2f" % [_bot, _ai_summary(ai),
				ai.mind.block_ratio, ai.mind.grab_rate, ai.mind.guard_skill()])
	_spikes.sort_custom(func(a, b): return a[0] > b[0])
	var med: float = _spikes[_spikes.size() / 2][0] if _spikes.size() > 0 else 0.0
	print("FRAMES median=%.1fms worst=%s" % [med, _spikes.slice(0, 8)])
	_report_and_quit()


var _shot_done := {}


func _shot_once(shot_name: String) -> void:
	if _shot_done.has(shot_name):
		return
	_shot_done[shot_name] = true
	_shot(shot_name)


func _shot(shot_name: String) -> void:
	if _shots_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(_shots_dir.path_join(shot_name + ".png"))


# ---------------- 빌드 규칙 ----------------

func _check_build_rules() -> void:
	var bad := []
	for n in CharacterBuild.PRESET_ORDER:
		if not CharacterBuild.preset(n).is_valid():
			bad.append("preset " + n)
	if not CharacterBuild.new().is_valid():
		bad.append("default")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 200:
		var b := CharacterBuild.random_build(rng)
		if not b.is_valid() or b.remaining() != 0:
			bad.append("random %s" % b.summary())
			break
	# 비싼 스킬을 고르면 능력치가 깎여서 점수 안에 들어온다
	var t := CharacterBuild.new()
	for k in CharacterBuild.STAT_ORDER:
		t.stats[k] = 6   # 30점 모두 능력치에
	t.skills = []
	t.toggle_skill("blink")
	t.toggle_skill("iron_guard")
	if not t.is_valid() or t.skills.size() != 2 or t.remaining() != 0:
		bad.append("toggle %s" % t.summary())
	if t.toggle_skill("haste"):
		bad.append("third skill allowed")
	print("BUILD rules presets=%d  => %s %s" % [CharacterBuild.PRESET_ORDER.size(), "OK" if bad.is_empty() else "FAIL", bad])
	if not bad.is_empty():
		_fail.append("build rules")


# ---------------- 특수 스킬 ----------------
# 1) 점멸 + 갈고리 (연습장)  2) 이중 점프 + 질풍 (연습장)  3) 철벽 (대결: AI 공격을 막는다)

var _sk_part := 0
var _sk := {}


func _start_skills() -> void:
	_phase = "skills"
	_frame = 0
	_sk_part += 1
	var b := CharacterBuild.new()
	match _sk_part:
		1:
			b.skills = ["blink", "grapple"]
			Game.next_mode = "practice"
		2:
			b.skills = ["double_jump", "haste"]
			Game.next_mode = "practice"
		3:
			b.skills = ["iron_guard", "haste"]
			Game.next_mode = "duel"
	Game.test_player_build = b
	_game = GAME.instantiate()
	root.add_child(_game)


func _skills_step() -> void:
	var player: Player = _game.player
	if _frame == 3:
		_game.hud.hide_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.rotation.y = 0.0
		player.head.rotation.x = 0.0
	match _sk_part:
		1:
			_skills_blink_grapple(player)
		2:
			_skills_jump_haste(player)
		3:
			_skills_iron(player)


func _skills_blink_grapple(player: Player) -> void:
	if _frame == 6:
		_sk.z0 = player.global_position.z
		player.use_skill_slot(0)
	if _frame == 8:
		_shot("s1_blink")
		var moved: float = _sk.z0 - player.global_position.z
		var again := player.use_skill("blink")   # 쿨타임이라 안 돼야 한다
		var ok := moved > 4.0 and not again
		print("SKILL blink moved=%.2f second_use=%s  => %s" % [moved, again, "OK" if ok else "FAIL"])
		if not ok:
			_fail.append("blink")
		# 북동쪽 기둥을 올려다보고 갈고리
		player.global_position = Vector3(7, 0.1, 3.0)
		player.velocity = Vector3.ZERO
		player.rotation.y = 0.0
		player.head.rotation.x = deg_to_rad(15)
		_max_y = 0.0
	if _frame == 12:
		player.use_skill_slot(1)
		_sk.grap = player.sm.state
	if player.sm.state == "grapple" and player.sm.time > 0.2:
		_shot_once("s2_grapple")
	_max_y = maxf(_max_y, player.global_position.y)
	if _frame == 120:
		var ok: bool = _sk.grap == "grapple" and player.global_position.z < -2.0 and _max_y > 2.0
		print("SKILL grapple state=%s z=%.2f max_y=%.2f  => %s" % [_sk.grap, player.global_position.z, _max_y, "OK" if ok else "FAIL"])
		if not ok:
			_fail.append("grapple")
		_game.queue_free()
		_start_skills()


func _skills_jump_haste(player: Player) -> void:
	if _frame == 30:
		_max_y = 0.0
		_sk.y0 = player.global_position.y
		Input.action_press("jump")
	if _frame == 32:
		Input.action_release("jump")
	if _frame == 62:
		Input.action_press("jump")   # 공중에서 한 번 더
	if _frame == 64:
		Input.action_release("jump")
	_max_y = maxf(_max_y, player.global_position.y)
	if _frame == 72:
		_shot("s3_double_jump")
	if _frame == 130:
		var h: float = _max_y - _sk.y0
		var ok := h > 2.0
		print("SKILL double_jump height=%.2f  => %s" % [h, "OK" if ok else "FAIL"])
		if not ok:
			_fail.append("double jump")
		player.use_skill_slot(1)
		Input.action_press("move_forward")
		_sk.z0 = player.global_position.z
	if _frame == 190:
		Input.action_release("move_forward")
		var dist: float = _sk.z0 - player.global_position.z
		# 걷기만 하면 1초에 4.5m 쯤 → 질풍이면 5.3m 넘게
		var ok: bool = player.skills.haste_active() and dist > 5.3
		print("SKILL haste walked=%.2f  => %s" % [dist, "OK" if ok else "FAIL"])
		if not ok:
			_fail.append("haste")
		_game.queue_free()
		_start_skills()


func _skills_iron(player: Player) -> void:
	var ai: Duelist = _game.duelist
	if _frame == 3:
		# 철벽을 켜기 전에 맞은 것은 따로 센다 (켜기 전 타이밍은 컴퓨터 속도에 따라 달라진다)
		player.attack_received.connect(func(r):
			var k: String = r if player.sm.state == "iron" else "pre_" + str(r)
			_sk[k] = _sk.get(k, 0) + 1)
		player.hp = 100000
	if not ai.active:
		return
	ai._move_cd = 99.0   # 이 점검은 철벽만 본다: 달려들기/상자 차기는 쓰지 않게
	ai._kick_cd = 99.0
	var to_ai := ai.global_position - player.global_position
	to_ai.y = 0
	# 등을 돌리고 있어도 철벽은 막아야 한다
	player.rotation.y = atan2(to_ai.x, to_ai.z)
	if ai.state == "windup" and player.sm.state == "free" and to_ai.length() < 3.2:
		player.use_skill_slot(0)
	if player.sm.state == "iron":
		_shot_once("s4_iron")
	if _sk.get("blocked", 0) >= 1 or _frame > 900:
		var ok: bool = _sk.get("blocked", 0) >= 1 and _sk.get("hit", 0) == 0
		print("SKILL iron_guard results=%s  => %s" % [_sk, "OK" if ok else "FAIL"])
		if not ok:
			_fail.append("iron guard")
		_game.queue_free()
		Game.test_player_build = CharacterBuild.new() if _my_preset == "" else CharacterBuild.preset(_my_preset)
		if _only == "skills":
			_report_and_quit()
		else:
			_start_rps()


# ---------------- 수싸움 ----------------
# 가위바위보와 방향 막기를 하나씩 직접 맞붙여 본다. AI 는 멈춰 두고(active=false) 자세만 정한다.

var _rps := {}


func _start_rps() -> void:
	_phase = "rps"
	_frame = 0
	Game.next_mode = "duel"
	_game = GAME.instantiate()
	root.add_child(_game)


func _rps_check(name: String, got, want) -> void:
	var ok: bool = got == want
	print("RPS %-34s got=%s want=%s  => %s" % [name, got, want, "OK" if ok else "FAIL"])
	if not ok:
		_fail.append("rps " + name)


func _rps_step() -> void:
	var player: Player = _game.player
	var ai: Duelist = _game.duelist
	if _frame == 3:
		_game.hud.hide_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.controls_enabled = true
		player.hp = 100000
		ai.hp = 100000
		ai.max_hp = 100000
		ai.parry_chance = 0.0
		ai.counter_chance = 0.0
		player.feinted.connect(func(): _rps["feinted"] = true)
	if _frame == 5:
		_rps_place(player, ai, Vector3(0, 0.1, 0), 1.5)
		var hit := {"damage": 10, "react": "flinch", "guard": "normal", "pressure": 1.0}
		# 1) 막기 > 공격 (방향이 같을 때만)
		ai.guard_dir = "side"
		ai.sm.go("block")
		_rps_check("AI side guard vs side slash", ai.take_hit(_with(hit, "side"), Vector3.FORWARD, player), "blocked")
		ai.sm.go("block")
		_rps_check("AI side guard vs thrust", ai.take_hit(_with(hit, "mid"), Vector3.FORWARD, player), "hit")
		ai.guard_dir = "high"
		ai.sm.go("block")
		_rps_check("AI high guard vs overhead", ai.take_hit(_with(hit, "high"), Vector3.FORWARD, player), "blocked")
		player.guard_dir = "high"
		player.sm.go("block")
		player._guard_t = 1.0
		_rps_check("player high guard vs overhead", player.receive_attack(_with(hit, "high"), ai), "blocked")
		player.sm.go("block")
		player._guard_t = 1.0
		_rps_check("player high guard vs side", player.receive_attack(_with(hit, "side"), ai), "wrong_guard")
		player.sm.go("block")
		player.guard_dir = "mid"
		player._guard_t = 0.0
		_rps_check("player mid guard parry thrust", player.receive_attack(_with(hit, "mid"), ai), "parried")
		# 2) 잡기 > 막기
		var grab := {"damage": 12, "react": "thrown", "throw": Vector3.ZERO}
		player.sm.go("free")
		ai.sm.go("block")
		_rps_check("grab vs blocking AI", ai.take_grab(grab, player), "thrown")
		player.sm.go("block")
		_rps_check("grab vs blocking player", player.take_grab(grab, ai), "thrown")
		# 3) 공격 > 잡기
		ai._attack = "slash1"
		ai.sm.go("windup")
		_rps_check("grab vs AI winding up", ai.take_grab(grab, player), "beaten")
		player.sm.go("free")
		player._start_attack("overhead")
		_rps_check("grab vs player winding up", player.take_grab(grab, ai), "beaten")
		ai._attack = "grab"
		ai.sm.go("windup")
		player.sm.go("free")
		_rps_check("AI grab warns as grab", ai.attack_dir(), "grab")
		# 4) 속임수: 내려찍기를 준비하다 오른쪽 클릭 → 막기로
		ai.sm.go("idle")
		player.sm.go("free")
		player._start_attack("heavy")
		player.block_pressed("mid")
		_rps_check("feint heavy into block", [player.sm.state, player.guard_dir, _rps.get("feinted", false)],
				["block", "mid", true])
		# 차지 → 대시로 끊기
		player.sm.go("charge")
		_rps["feinted"] = false
		player.try_dash()
		_rps_check("charge cancel into dash", [player.sm.state, _rps.feinted], ["dash", true])
		# 마우스 방향 → 공격 동작
		player.sm.go("free")
		player.attack_pressed("high")
		_rps_check("flick up = overhead", player._move, "overhead")
		player.sm.go("free")
		player.attack_pressed("mid")
		_rps_check("flick down = thrust", player._move, "thrust")
		player.sm.go("free")
		player.attack_released()
		_rps_check("flick dir", [AttackDir.from_flick(Vector2(2, -30)), AttackDir.from_flick(Vector2(30, 5)),
				AttackDir.from_flick(Vector2(-3, 25)), AttackDir.from_flick(Vector2(3, 2))], ["high", "side", "mid", ""])
	# 5) 실제로 잡아 던지기: 서쪽 집 벽 앞에서 막고 있는 AI 를 벽 쪽으로 던진다 → 벽꽝
	if _frame == 10:
		ai.sm.go("idle")
		player.sm.go("free")
		player.global_position = Vector3(-10.2, 0.1, 0)
		player.rotation.y = PI / 2.0
		player.head.rotation.x = 0.0
		ai.global_position = Vector3(-11.6, 0.1, 0)
		ai.rotation.y = -PI / 2.0
		ai.velocity = Vector3.ZERO
		_rps["hp0"] = ai.hp
		player.stamina = player.max_stamina
	if _frame == 14:
		ai.guard_dir = "side"
		ai.sm.go("block")
		player.try_grab()
	if _frame == 22:
		_shot("r1_grab")
	if _frame == 60:
		_shot("r2_thrown")
		_rps_check("grab+throw into wall", [ai.stats.get("got_grab_thrown", 0) >= 1, ai.stats.get("wall_slam", 0) >= 1],
				[true, true])
		print("    thrown: ai at x=%.2f hp lost=%d" % [ai.global_position.x, _rps.hp0 - ai.hp])
	if _frame == 64:
		_game.queue_free()
		if _only == "rps":
			_report_and_quit()
		else:
			_start_weapons()


func _with(info: Dictionary, dir: String) -> Dictionary:
	var d := info.duplicate()
	d["dir"] = dir
	return d


func _rps_place(player: Player, ai: Duelist, at: Vector3, gap: float) -> void:
	player.global_position = at + Vector3(0, 0, gap * 0.5)
	player.rotation.y = 0.0
	ai.global_position = at - Vector3(0, 0, gap * 0.5)
	ai.rotation.y = PI
	player.velocity = Vector3.ZERO
	ai.velocity = Vector3.ZERO


# ---------------- 무기와 필살기 ----------------

func _check_weapon_table() -> void:
	var bad := []
	var sw := Weapons.move("sword", "slash1")
	if not (Weapons.move("daggers", "slash1").windup < sw.windup and sw.windup < Weapons.move("greatsword", "slash1").windup):
		bad.append("speed order")
	if not (Weapons.move("greatsword", "heavy").damage > Weapons.move("sword", "heavy").damage):
		bad.append("greatsword damage")
	if not (Weapons.move("spear", "thrust").reach > Weapons.move("sword", "thrust").reach + 1.0):
		bad.append("spear reach")
	if not (Weapons.move("daggers", "grab").reach >= Weapons.move("sword", "grab").reach):
		bad.append("dagger grab")
	if Weapons.move("daggers", "slash3").next != "slash1":
		bad.append("dagger loop")
	for w in Weapons.ORDER:
		for m in MoveSet.MOVES:
			var d := Weapons.move(w, m)
			if float(d.windup) <= 0.0 and m != "plunge":
				bad.append("%s %s windup" % [w, m])
		if not Weapons.WEAPONS[w].has("special"):
			bad.append(w + " special")
	var rb := CharacterBuild.random_build()
	if not Weapons.WEAPONS.has(rb.weapon):
		bad.append("random weapon")
	print("WEAPON table weapons=%d  => %s %s" % [Weapons.ORDER.size(), "OK" if bad.is_empty() else "FAIL", bad])
	if not bad.is_empty():
		_fail.append("weapon table")


## 무기마다: 내 필살기가 AI 에게 맞는지, AI 필살기가 (막고 있는) 나에게 맞는지
var _wi := 0
var _wres := {}


func _start_weapons() -> void:
	_phase = "weapons"
	_frame = 0
	var w: String = Weapons.ORDER[_wi]
	Game.next_mode = "duel"
	Game.test_player_build = CharacterBuild.new()
	Game.test_player_build.weapon = w
	Game.current_opponent = CharacterBuild.preset("검객")
	Game.current_opponent.weapon = w
	_wres = {}
	_game = GAME.instantiate()
	root.add_child(_game)


func _weapons_step() -> void:
	if _frame > 170:
		if _frame == 172:
			_wi += 1
			if _wi < Weapons.ORDER.size():
				_start_weapons()
			elif _only == "weapons":
				_report_and_quit()
			else:
				Game.test_player_build = CharacterBuild.new() if _my_preset == "" else CharacterBuild.preset(_my_preset)
				_start_duel()
		return
	var player: Player = _game.player
	var ai: Duelist = _game.duelist
	var w: String = Weapons.ORDER[_wi]
	var sp := Weapons.move(w, "special")
	var gap := 2.0
	match str(sp.effect):
		"rush":
			gap = 5.0
		"shadow":
			gap = 4.5
	if _frame == 3:
		_game.hud.hide_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.controls_enabled = true
		player.hp = 100000
		player.max_hp = 100000
		ai.hp = 100000
		ai.max_hp = 100000
		player.attack_received.connect(func(r): _wres["me_" + r] = _wres.get("me_" + r, 0) + 1)
	if _frame == 5:
		ai.active = false
		ai.sm.go("idle")
		_rps_place(player, ai, Vector3(0, 0.1, 0), gap)
		player.head.rotation.x = 0.0
		player.gauge = Weapons.GAUGE_MAX
		player.try_special()
		_wres["me_state"] = player.sm.state
	if _frame == 5 + 8:
		_shot("w_%s_me_special" % w)
	if _frame == 75:
		_wres["ai_got_hit"] = ai.stats.get("got_hit", 0)
		_wres["me_gauge_reset"] = player.gauge < 10.0
		# 이번엔 AI 차례: 막고 서 있는 나에게 필살기
		player.sm.go("free")
		_rps_place(player, ai, Vector3(0, 0.1, 0), gap)
		ai.active = true
		ai.gauge = Weapons.GAUGE_MAX
		ai._dist = gap
		ai._dir = Vector3(0, 0, 1)
		ai.sm.go("idle")
		ai._start_attack("special")
		player.guard_dir = "side"
		player.sm.go("block")
	if _frame > 75 and _frame < 170:
		player.rotation.y = 0.0
		if player.sm.state == "free":
			player.sm.go("block")
		if ai.state == "windup" and ai._state_t > 0.3:
			_shot_once("w_%s_ai_windup" % w)
		if ai.state == "strike":
			_shot_once("w_%s_ai_strike" % w)
	if _frame == 170:
		var got_me := int(_wres.get("me_hit", 0)) + int(_wres.get("me_guard_broken", 0)) + int(_wres.get("me_wrong_guard", 0))
		var ok: bool = _wres.me_state == "special" and int(_wres.ai_got_hit) >= 1 and got_me >= 1 and _wres.me_gauge_reset
		print("WEAPON %-10s special=%-6s me->ai hits=%d  ai->me(blocking)=%s  => %s" % [w, sp.effect, _wres.ai_got_hit,
				_wres, "OK" if ok else "FAIL"])
		if not ok:
			_fail.append("weapon special " + w)
		_game.queue_free()
		Game.current_opponent = null
