extends SceneTree
## '자유롭게 움직이며 싸우기' 소개 영상용 자동 연출 (한 판 안에서 장면을 이어 간다).
## 실행: godot --write-movie 파일.avi --fixed-fps 30 -s res://tests/free_move_video.gd
##  1) 달리기 → 슬라이딩 → 다리 베기로 넘어뜨리기
##  2) 연속기 갈래: 베기 → 올려베기 → 쪼개기 / 베기 → 되베기 → 휩쓸기 → 회전 베기
##  3) 달리며 찌르기
##  4) 벽 달리기 → 벽 차고 베기
##  5) 상자 베어 날리기, 상자 들어 던지기
##  6) 금 간 돌기둥을 쳐서 상대에게 쓰러뜨리기
##  7) AI 가 상자를 차고, 미끄러져 들어온다

const GAME := preload("res://scenes/main.tscn")

var _game: Node
var _f := 0
var _scene := 0
var _t := 0          # 지금 장면이 시작된 뒤 지난 프레임 (초당 30)
var _v := {}


func _initialize() -> void:
	seed(5)
	Game.opponent_mode = "preset"
	Game.opponent_preset = "검객"
	Game.test_player_build = CharacterBuild.new()
	Game.current_opponent = null
	Game.next_mode = "duel"
	_game = GAME.instantiate()
	root.add_child(_game)


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump", "attack", "sprint", "crouch", "grab"]:
		Input.action_release(a)


func _hold_ai(ai: Duelist, pos: Vector3, face: Vector3) -> void:
	ai.active = false
	ai.global_position = pos
	ai.rotation.y = atan2(-face.x, -face.z)
	ai.velocity = Vector3.ZERO
	ai._push = Vector3.ZERO
	ai.hp = 100000
	ai.max_hp = 100000
	ai.sm.go("idle")
	ai.rig.set_pose(MoveSet.BODY_POSES.guard, 10.0)


func _place(p: Player, pos: Vector3, look_at_pos: Vector3, pitch := -6.0) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	_face(p, look_at_pos)
	p.head.rotation.x = deg_to_rad(pitch)
	p.stamina = p.max_stamina


func _face(p: Player, at: Vector3) -> void:
	var d := at - p.global_position
	p.rotation.y = atan2(-d.x, -d.z)


func _turn_to(p: Player, at: Vector3, k: float) -> void:
	var d := at - p.global_position
	p.rotation.y = lerp_angle(p.rotation.y, atan2(-d.x, -d.z), k)


func _click(p: Player, dir := "") -> void:
	p.attack_pressed(dir, 0.0)
	p.attack_released()


func _next_scene() -> void:
	_scene += 1
	_t = 0
	_v = {}
	_release_all()


func _process(_delta: float) -> bool:
	var p: Player = _game.player
	var ai: Duelist = _game.duelist
	if not p.controls_enabled:
		return false
	_f += 1
	_t += 1
	if _f == 1:
		_game.arena.director.running = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		p.hp = 100000
		p.max_hp = 100000
		_next_scene()
	p.hp = 100000
	match _scene:
		1: _slide_sweep(p, ai)
		2: _combo(p, ai)
		3: _run_thrust(p, ai)
		4: _wall(p, ai)
		5: _crates(p, ai)
		6: _pillar(p, ai)
		7: _ai_free(p, ai)
		_:
			quit()
	return false


func _banner(text: String) -> void:
	_game.hud.show_event(text, Color(1.0, 0.92, 0.6))


# 1) 달리다 슬라이딩, 다리 베기
func _slide_sweep(p: Player, ai: Duelist) -> void:
	if _t == 1:
		_hold_ai(ai, Vector3(0, 0.1, -2.0), Vector3(0, 0, 1))
		_place(p, Vector3(0, 0.1, 9.0), ai.global_position + Vector3.UP)
		_banner("Shift 달리기 — 순간 돌진 없이 점점 빨라진다")
	if _t == 6:
		Input.action_press("move_forward")
	if _t == 12:
		Input.action_press("sprint")
	var gap := p.global_position.z - ai.global_position.z
	if not _v.has("slide") and gap < 5.6 and _t > 12:
		_v.slide = true
		Input.action_press("crouch")
		p.crouch_pressed()
		_banner("달리다 C — 슬라이딩")
	if _v.has("slide") and not _v.has("sweep") and gap < 2.9:
		_v.sweep = true
		_click(p)
		_banner("슬라이딩 중 클릭 — 다리 베기 (넘어뜨림)")
	if _v.has("sweep"):
		_release_all()
		_turn_to(p, ai.global_position, 0.2)
	if _t == 110:
		_next_scene()


# 2) 연속기 갈래
func _combo(p: Player, ai: Duelist) -> void:
	if _t == 1:
		_hold_ai(ai, Vector3(0, 0.1, -1.0), Vector3(0, 0, 1))
		_place(p, Vector3(0, 0.1, 1.0), ai.global_position + Vector3.UP * 1.2)
		_banner("연속기 — 이어 누를 때 마우스를 위로: 올려베기 → 쪼개기")
	ai.global_position = Vector3(0, 0.1, -1.0)
	p.stamina = p.max_stamina
	var a := {8: "", 15: "high", 22: "high"}
	var b := {66: "", 73: "", 80: "", 87: ""}
	if a.has(_t):
		_click(p, a[_t])
	if _t == 60:
		_banner("옆으로 네 번 — 베기, 되베기, 휩쓸기, 회전 베기")
	if b.has(_t):
		_click(p, b[_t])
	if _t == 130:
		_next_scene()


# 3) 달리며 찌르기
func _run_thrust(p: Player, ai: Duelist) -> void:
	if _t == 1:
		_hold_ai(ai, Vector3(0, 0.1, -4.0), Vector3(0, 0, 1))
		_place(p, Vector3(0, 0.1, 6.0), ai.global_position + Vector3.UP)
		_banner("달리며 클릭 — 달려 찌르기")
	if _t == 6:
		Input.action_press("move_forward")
		Input.action_press("sprint")
	if not _v.has("hit") and p.global_position.z - ai.global_position.z < 3.4 and _t > 6:
		_v.hit = true
		_click(p)
		_release_all()
	if _t == 60:
		_next_scene()


# 4) 벽 달리기 → 벽 차고 베기
func _wall(p: Player, ai: Duelist) -> void:
	if _t == 1:
		_hold_ai(ai, Vector3(-8.2, 0.1, -3.0), Vector3(-1, 0, 0))
		p.global_position = Vector3(-10.9, 0.1, 4.5)
		p.velocity = Vector3.ZERO
		p.rotation.y = 0.0
		p.head.rotation.x = deg_to_rad(-4)
		_banner("벽 달리기 → 클릭: 벽 차고 베기")
	if _t == 4:
		Input.action_press("move_forward")
		Input.action_press("sprint")
	if _t == 10:
		Input.action_press("move_left")
		Input.action_press("jump")
	if _t == 12:
		Input.action_release("jump")
	if p.sm.state == "wallrun":
		_v.ran = _v.get("ran", 0) + 1
		_turn_to(p, ai.global_position, 0.12)
	if not _v.has("slash") and ((p.sm.state == "wallrun" and _v.get("ran", 0) >= 9) or (_t > 40 and not p.is_on_floor())):
		_v.slash = true
		_face(p, ai.global_position)
		_click(p)
	if _v.has("slash"):
		_release_all()
		_turn_to(p, ai.global_position, 0.2)
	if _t == 85:
		_next_scene()


# 5) 상자: 베어 날리기, 들어 던지기
func _crates(p: Player, ai: Duelist) -> void:
	var arena: Arena = _game.arena
	var c: ArenaCrate = arena.crates[0]
	var c2: ArenaCrate = arena.crates[1]
	if _t == 1:
		_hold_ai(ai, Vector3(0, 0.1, -1.0), Vector3(0, 0, 1))
		_place(p, Vector3(0, 0.1, 6.5), ai.global_position + Vector3.UP * 0.6, -12)
		c.global_position = Vector3(0, ArenaCrate.SIZE * 0.5 + 0.05, 5.3)
		c.linear_velocity = Vector3.ZERO
		c.rotation = Vector3.ZERO
		_banner("상자를 베면 날아간다")
	if _t == 22:
		_click(p)
	if _t == 62:
		c2.global_position = p.global_position + Vector3(0.7, ArenaCrate.SIZE * 0.5, -0.9)
		c2.linear_velocity = Vector3.ZERO
		c2.rotation = Vector3.ZERO
		_face(p, c2.global_position)
		p.head.rotation.x = deg_to_rad(-25)
		_banner("F — 상자 들기")
	if _t == 72:
		p.try_grab()
	if _t > 72 and _t < 92:
		_turn_to(p, ai.global_position, 0.15)
		p.head.rotation.x = lerpf(p.head.rotation.x, deg_to_rad(-3), 0.15)
	if _t == 92:
		_banner("F 나 클릭 — 던지기")
		p.throw_crate()
	if _t == 140:
		_next_scene()


# 6) 금 간 돌기둥을 상대 쪽으로 쓰러뜨린다
func _pillar(p: Player, ai: Duelist) -> void:
	var arena: Arena = _game.arena
	var bp: BreakablePillar = arena.breakables["obelisk_nw"]
	if _t == 1:
		_hold_ai(ai, Vector3(-19.5, 0.1, -15.2), Vector3(0, 0, 1))
		_place(p, Vector3(-18.6, 0.1, -9.6), Vector3(-19.5, 2.4, -14.0), -2)
		bp.hp = 2
		_banner("금 간 돌기둥을 쳐서 상대 쪽으로 쓰러뜨리기")
	if _t == 14:
		_click(p)
	if _t == 30:
		_click(p)
	if _t > 32:
		p.head.rotation.x = lerpf(p.head.rotation.x, deg_to_rad(-12), 0.05)
	if _t == 110:
		_next_scene()


# 7) AI 도 자유롭게: 상자를 차고, 미끄러져 들어온다
func _ai_free(p: Player, ai: Duelist) -> void:
	var arena: Arena = _game.arena
	if _t == 1:
		ai.global_position = Vector3(0, 0.1, -3.0)
		ai.velocity = Vector3.ZERO
		ai.hp = 100000
		ai.active = true
		ai.sm.go("idle")
		_place(p, Vector3(0, 0.1, 6.0), ai.global_position + Vector3.UP)
		var c: ArenaCrate = arena.crates[0]
		c.global_position = Vector3(1.0, ArenaCrate.SIZE * 0.5 + 0.05, -2.2)
		c.linear_velocity = Vector3.ZERO
		_banner("상대도 상자를 차고, 미끄러져 들어온다")
		ai._kick_cd = 0.0
		ai._move_cd = 99.0
	_turn_to(p, ai.global_position + Vector3.UP, 0.25)
	if ai.stats.get("crate_kick", 0) >= 1 and not _v.has("kicked"):
		_v.kicked = _t
		ai._move_cd = 0.0
		ai._kick_cd = 99.0
	# 상대가 미끄러져 들어오게 거리를 벌려 둔다
	if _v.has("kicked") and _t - int(_v.kicked) == 40:
		var away := p.global_position - ai.global_position
		away.y = 0
		p.global_position = ai.global_position + away.normalized() * 5.0
	if ai.stats.get("move_sweep", 0) + ai.stats.get("move_run_thrust", 0) >= 1 and not _v.has("moved"):
		_v.moved = _t
	if (_v.has("moved") and _t - int(_v.moved) > 45) or _t > 420:
		_next_scene()
