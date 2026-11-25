extends SceneTree
## 자동 점검.
##  1) 연습장: 앞으로 걸어가 허수아비를 베어 본다.
##  2) 대결: AI 가 다가와 공격하는지, 막기/튕겨내기가 되는지, AI 를 때릴 수 있는지 본다.
##     (자동 조종: 상대 칼이 빛나면 막고, 빈틈이 보이면 벤다)
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
	seed(seed_value)
	if _only == "duel":
		_start_duel()
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
		_start_duel()


func _duel_step() -> void:
	var player: Player = _game.player
	var ai: Duelist = _game.duelist
	if _frame == 3:
		_game.hud.hide_menu()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.attack_received.connect(func(r): _results[r] = _results.get(r, 0) + 1)
	if _frame == 150:
		_shot("d1_face")
	if not is_instance_valid(ai) or ai.dead or player.dead or _frame > 1500:
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
	var threat := ai.state == "windup"
	var time_left := 1.0
	if threat:
		time_left = MoveSet.MOVES[ai._attack].ai_windup - ai._state_t
	# 막기: 앞쪽 공격은 칼이 닿기 직전에 눌러서 튕겨내기를 노린다
	if threat and time_left < 0.12 and dist < 3.2:
		Input.action_press("block")
	elif ai.state != "strike":
		Input.action_release("block")
	# 거리 조절
	if dist > 2.3 and not threat:
		Input.action_press("move_forward")
	else:
		Input.action_release("move_forward")
	# 빈틈 공격
	if ai.state in ["stagger", "recover"] and dist < 2.6 and not player.blocking and _frame % 6 == 0:
		player._request_attack("light")


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
		var left: float = MoveSet.MOVES[ai._attack].ai_windup - ai._state_t
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
	elif ai_hp >= Duelist.MAX_HP:
		_fail.append("could not damage AI")
	if _bot == "good" and not (_results.has("blocked") or _results.has("parried")):
		_fail.append("block/parry never worked")
	if is_instance_valid(ai):
		print("AI stats ", ai.stats)
	_spikes.sort_custom(func(a, b): return a[0] > b[0])
	var med: float = _spikes[_spikes.size() / 2][0] if _spikes.size() > 0 else 0.0
	print("FRAMES median=%.1fms worst=%s" % [med, _spikes.slice(0, 8)])
	print("SMOKE => %s %s" % ["OK" if _fail.is_empty() else "FAIL", _fail])
	_phase = "done"
	quit(0 if _fail.is_empty() else 1)


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
