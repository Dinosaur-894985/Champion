class_name Game
extends Node3D
## 게임 전체: 하늘과 빛, 경기장(scripts/arena.gd)을 만들고, 모드에 따라
## 연습(허수아비) 또는 대결(AI 결투사)을 시작한다.

const HUD_SCRIPT := preload("res://scripts/hud.gd")

## 다시 불러올 때 시작할 모드. "" 이면 처음 켠 것이라 시작 화면을 보여준다.
static var next_mode := ""
## AI 상대 고르는 방식: "random" 랜덤, "preset" 지정(미리 만든 캐릭터), "mirror" 거울(내 캐릭터와 같음)
static var opponent_mode := "random"
static var opponent_preset := "검객"
## 지금 대결 중인 상대. '다시 대결' 하면 같은 상대가 나온다.
static var current_opponent: CharacterBuild = null
## AI 난이도 "easy" / "normal" / "hard". 비어 있으면 기록 파일에서 읽는다 (처음엔 보통)
static var difficulty := ""
## 대결 결과를 전적에 남기나 (점검에서 끌 수 있다)
static var record_results := true
## 점검용: 정해 두면 저장된 캐릭터 대신 이 캐릭터로 시작한다
static var test_player_build: CharacterBuild = null

var mode := "practice"
var arena: Arena
var player: Player
var duelist: Duelist
var tutorial: Tutorial
var hud: CanvasLayer
var hits := 0
var knockdowns := 0
var round_over := false
## 이번 판 기록 (결과 화면에 보여 준다)
var stats := {"dealt": 0, "taken": 0, "hits": 0, "perfect": 0, "dodged": 0, "combo": 0, "specials": 0}
var round_time := 0.0
var _enemy_hp_seen := 0
## 끝내기 연출: 실제 흐른 시간(초)으로 진행한다 (게임 시간은 느려지니까)
var _cine_t := -1.0
var _cine_step := 0
var _cine_won := false
var _cine_cam: Camera3D
var _cine_from := Vector3.ZERO
var _cine_to := Vector3.ZERO


func _ready() -> void:
	Engine.time_scale = 1.0
	_setup_inputs()
	_build_environment()
	arena = Arena.new()
	add_child(arena)

	var first_launch := next_mode == ""
	mode = "practice" if first_launch else next_mode

	player = Player.new()
	player.build = test_player_build.duplicate_build() if test_player_build else CharacterBuild.load_saved()
	player.arena = arena
	add_child(player)

	hud = HUD_SCRIPT.new()
	add_child(hud)
	hud.menu_choice.connect(_on_menu_choice)
	player.stamina_changed.connect(hud.set_stamina)
	player.hp_changed.connect(hud.set_player_hp)
	player.took_damage.connect(hud.on_player_damaged)
	player.combat_event.connect(hud.show_event)
	player.counter_window.connect(hud.set_counter_window)
	hud.set_player(player)
	hud.set_stamina(player.stamina, player.max_stamina)
	hud.set_player_hp(player.hp, player.max_hp)

	if mode == "duel":
		_setup_duel()
	elif mode == "tutorial":
		_setup_tutorial()
	else:
		_setup_practice()
	_setup_arena_events()

	_warmup()

	# 배경음악: 처음 화면과 연습장은 차분한 곡, 대결은 숫자 세기와 함께 긴박한 곡
	if first_launch or mode in ["practice", "tutorial"]:
		Audio.music("menu")
	if first_launch:
		hud.show_menu("start")
	else:
		hud.hide_menu()
		if mode == "duel":
			_countdown()


func _setup_practice() -> void:
	player.position = Vector3(0, 0.1, 7.5)
	hud.set_mode("practice")
	_spawn_dummies()
	hud.set_stats(hits, knockdowns)


func _spawn_dummies() -> void:
	for i in 3:
		var d := TrainingDummy.new()
		var x := (i - 1) * 3.2
		d.position = Vector3(x, 0.1, -1.0 - absf(i - 1) * 1.2)
		d.rotation.y = -x * 0.12
		add_child(d)
		d.hit_taken.connect(_on_hit)
		d.knocked_down.connect(_on_knockdown)


## 튜토리얼: 허수아비로 이동·공격을 배우고, 연습 상대(천천히 공격함)로 막기·피하기·필살기를 배운다
func _setup_tutorial() -> void:
	player.position = Vector3(0, 0.1, 7.5)
	hud.set_mode("tutorial")
	_spawn_dummies()
	# 연습 상대는 처음엔 옆에서 기다리다가 막기 단계에서 다가온다
	duelist = Duelist.new()
	var b := CharacterBuild.preset("검객")
	b.contrast_with(player.build)
	duelist.build = b
	duelist.tutor = true
	duelist.position = Vector3(5.5, 0.1, 2.5)
	var look := player.position - duelist.position
	duelist.rotation.y = atan2(-look.x, -look.z)
	duelist.arena = arena
	add_child(duelist)
	duelist.target = player
	hud.set_opponent(duelist)
	duelist.combat_event.connect(hud.show_event)
	tutorial = Tutorial.new()
	tutorial.setup(self, duelist)
	add_child(tutorial)
	tutorial.finished.connect(func():
		hud.show_big("튜토리얼 완료!", Color(1.0, 0.85, 0.3))
		Audio.stinger("victory", "menu")
		get_tree().create_timer(1.6, false).timeout.connect(func(): hud.show_menu("tutorial_done")))


func _setup_duel() -> void:
	player.position = Vector3(0, 0.1, 6.0)
	hud.set_mode("duel")
	duelist = Duelist.new()
	if current_opponent == null:
		current_opponent = make_opponent(opponent_mode, player.build)
	# 같은 색끼리 맞붙으면(거울 모드 등) 상대 옷 색을 바꿔 알아보기 쉽게 한다
	var ob: CharacterBuild = current_opponent.duplicate_build()
	ob.contrast_with(player.build)
	duelist.build = ob
	duelist.difficulty = ai_difficulty()
	duelist.position = Vector3(0, 0.1, -6.0)
	duelist.arena = arena
	add_child(duelist)
	duelist.target = player
	player.attack_started.connect(duelist.on_target_attack)
	player.charge_started.connect(duelist.on_target_charge)
	player.feinted.connect(duelist.on_target_feint)
	player.opponent = duelist
	hud.set_opponent(duelist)
	duelist.hp_changed.connect(hud.set_enemy_hp)
	duelist.stamina_changed.connect(hud.set_enemy_stamina)
	hud.set_enemy(duelist.build)
	duelist.combat_event.connect(hud.show_event)
	duelist.died.connect(_on_round_end.bind(true))
	player.died.connect(_on_round_end.bind(false))
	# 결과 화면에 쓸 이번 판 기록
	_enemy_hp_seen = duelist.hp
	duelist.hp_changed.connect(_on_enemy_hp)
	var seen := [player.hp]
	player.hp_changed.connect(func(v: int, _m: int):
		if v < seen[0]:
			stats.taken += seen[0] - v   # 넘치는 피해는 세지 않는다
		seen[0] = v)
	player.attack_received.connect(func(r: String):
		if r in ["blocked", "parried"]:
			stats.perfect += 1
		elif r == "dodged":
			stats.dodged += 1)
	player.attack_started.connect(func(kind: String):
		if kind == "special":
			stats.specials += 1
		else:
			stats.combo = maxi(stats.combo, player._combo_step))
	player.controls_enabled = false


## 효과(불꽃, 파편, 피해 숫자, 번쩍임)를 시작 전에 한 번씩 몰래 그려 둔다.
## 처음 그릴 때 그래픽 준비(셰이더 컴파일)로 화면이 멈칫하는데, 특히 웹에서 심하다.
## 그래서 싸우는 도중이 아니라 시작 화면이 가려진 동안 미리 해 둔다.
## 지금 고른 AI 난이도
static func ai_difficulty() -> String:
	if difficulty == "":
		difficulty = str(Progress.get_value("ai", "difficulty", "normal"))
		if not Duelist.DIFFICULTY.has(difficulty):
			difficulty = "normal"
	return difficulty


static func set_ai_difficulty(d: String) -> void:
	if Duelist.DIFFICULTY.has(d):
		difficulty = d
		Progress.set_value("ai", "difficulty", d)


## 모드에 맞는 AI 상대 캐릭터를 만든다
static func make_opponent(how: String, mine: CharacterBuild) -> CharacterBuild:
	match how:
		"mirror":
			var b := mine.duplicate_build()
			b.name = "거울"
			return b
		"preset":
			return CharacterBuild.preset(opponent_preset)
	return CharacterBuild.random_build()


func _warmup() -> void:
	hud.cover(0.5)
	var cam := player.camera
	var p := cam.global_position - cam.global_transform.basis.z * 2.5
	Fx.sparks(self, p, Vector3.UP, 4)
	Fx.sparks(self, p, Vector3.UP, 4, Color(0.7, 0.9, 1.0))
	Fx.impact(self, p, Vector3.UP, Color(0.75, 0.1, 0.08), 4)
	player.warmup()
	if duelist:
		duelist.warmup(p)
	for d in get_children():
		if d is TrainingDummy:
			d.warmup(p)


func _countdown() -> void:
	player.controls_enabled = false
	Audio.music("arena", 0.6)
	for t in ["3", "2", "1"]:
		hud.show_big(t, Color(1, 1, 1))
		Audio.ui("countdown")
		await get_tree().create_timer(0.7, false).timeout
	hud.show_big("싸워라!", Color(1.0, 0.8, 0.35))
	Audio.ui("fight")
	player.controls_enabled = true
	duelist.active = true
	arena.director.running = true


func _on_enemy_hp(v: int, _m: int) -> void:
	if v < _enemy_hp_seen:
		stats.dealt += _enemy_hp_seen - v
		stats.hits += 1
	_enemy_hp_seen = v


func _process(delta: float) -> void:
	if mode == "duel" and not round_over and duelist and duelist.active:
		round_time += delta
	if _cine_t >= 0.0:
		_cine_t += delta / maxf(Engine.time_scale, 0.01)   # 실제 흐른 시간
		_cine_update()


## 판이 끝났다: 전적을 남기고, 끝내기 연출(느린 화면) 뒤 결과 화면
func _on_round_end(player_won: bool) -> void:
	if round_over:
		return
	round_over = true
	arena.director.running = false
	duelist.active = false
	player.controls_enabled = false
	var rec := {}
	if record_results:
		rec = Records.add_result(player.weapon, ai_difficulty(), player_won, round_time)
	hud.result = {"stats": stats.duplicate(), "time": round_time, "record": rec}
	Audio.ui("ko")
	Audio.music("", 0.8)
	_cine_won = player_won
	Engine.time_scale = 0.22 if player_won else 0.3
	hud.cinematic(true)
	hud.flash(Color(1, 1, 1, 0.5) if player_won else Color(0.55, 0.0, 0.0, 0.45), 0.25)
	if player_won:
		_start_kill_cam()
	_cine_t = 0.0
	_cine_step = 0


## 이겼을 때: 1인칭 눈에서 빠져나와, 쓰러지는 상대를 옆에서 느리게 비춘다
func _start_kill_cam() -> void:
	var cam := player.camera
	_cine_cam = Camera3D.new()
	_cine_cam.fov = cam.fov
	add_child(_cine_cam)
	_cine_cam.global_transform = cam.global_transform
	_cine_cam.current = true
	player._weapon_root.visible = false   # 1인칭 칼은 내 눈 앞에만 그려 두는 것이라 숨긴다
	_cine_from = cam.global_position
	var target := duelist.global_position + Vector3.UP
	var dir := target - _cine_from
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var side := Vector3(-dir.z, 0.0, dir.x)
	# 상대 옆쪽 비스듬한 자리 (벽에 막히면 막힌 곳 조금 앞)
	var space := get_world_3d().direct_space_state
	var best := Vector3.ZERO
	var best_len := -1.0
	for s in [1.0, -1.0]:
		var want: Vector3 = target - dir * 2.4 + side * s * 1.9 + Vector3.UP * 0.45
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(target, want, 1))
		var pos: Vector3 = want if hit.is_empty() else target.lerp(hit.position, 0.8)
		var len := pos.distance_to(target)
		if len > best_len:
			best_len = len
			best = pos
	_cine_to = best


func _cine_update() -> void:
	const SLOW := 1.7    # 이만큼 (실제 초) 느린 화면
	const BACK := 0.45   # 그 뒤 이만큼 동안 제 빠르기로 돌아온다
	var slow := 0.22 if _cine_won else 0.3
	if _cine_t < SLOW:
		Engine.time_scale = slow
	else:
		Engine.time_scale = lerpf(slow, 1.0, clampf((_cine_t - SLOW) / BACK, 0.0, 1.0))
	if _cine_cam and is_instance_valid(duelist):
		var k := clampf(_cine_t / (SLOW + BACK), 0.0, 1.0)
		k = 1.0 - pow(1.0 - k, 3.0)   # 처음엔 빠르게, 끝엔 천천히 멈춘다
		var look := duelist.rig.global_position + Vector3.UP * lerpf(1.1, 0.6, k)
		_cine_cam.global_position = _cine_from.lerp(_cine_to, k)
		if _cine_cam.global_position.distance_to(look) > 0.2:
			_cine_cam.look_at(look)
	if _cine_step == 0 and _cine_t >= SLOW + 0.15:
		_cine_step = 1
		hud.show_big("승리!" if _cine_won else "패배", Color(1.0, 0.85, 0.3) if _cine_won else Color(1.0, 0.35, 0.3), 1.0)
		Audio.stinger("victory" if _cine_won else "defeat", "menu")
	if _cine_step == 1 and _cine_t >= SLOW + 1.9:
		_cine_step = 2
		_cine_t = -1.0
		Engine.time_scale = 1.0
		hud.show_menu("win" if _cine_won else "lose")


func _on_menu_choice(choice: String) -> void:
	if choice.begins_with("diff_"):
		# 난이도 바꾸기 (상대 고르기 화면): 저장하고 화면을 새로 그린다
		set_ai_difficulty(choice.substr(5))
		hud.show_menu("opponent")
		return
	if choice.begins_with("vs_"):
		# 상대 고르기: vs_random, vs_mirror, vs_preset:이름
		if choice.begins_with("vs_preset:"):
			opponent_mode = "preset"
			opponent_preset = choice.substr(10)
		else:
			opponent_mode = choice.substr(3)
		current_opponent = null
		restart("duel")
		return
	match choice:
		"opponent":
			hud.show_menu("opponent")
		"presets":
			hud.show_menu("presets")
		"settings":
			hud.open_settings()
		"records":
			hud.show_menu("records")
		"back":
			hud.go_back()
		"build":
			hud.open_build_editor(player.build)
		"build_saved":
			# 캐릭터를 바꿨다: 새 캐릭터로 지금 모드를 다시 시작 (처음 화면이었으면 연습장)
			if opponent_mode == "mirror":
				current_opponent = null
			restart(mode)
		"build_cancel":
			hud.show_menu(hud.menu_return)
		"resume":
			hud.hide_menu()
		"tut_skip":
			hud.hide_menu()
			if tutorial:
				tutorial.skip()
		"home":
			restart("")
		"practice", "duel", "tutorial":
			if choice == mode and next_mode == "" and not round_over:
				# 처음 켠 화면에서 지금 모드를 고른 경우: 그대로 시작
				next_mode = mode
				hud.hide_menu()
				if mode == "duel":
					_countdown()
			else:
				restart(choice)
		"retry":
			restart(mode)
		"quit":
			get_tree().quit()


func restart(new_mode: String) -> void:
	next_mode = new_mode
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()


## 경기장 소식(바닥 붕괴, 아이템)을 화면에 띄운다
func _setup_arena_events() -> void:
	arena.set_fighters([player, duelist] if duelist else [player])
	arena.director.announce.connect(func(text: String, color: Color, big: bool):
		if big:
			hud.show_big(text, color)
		else:
			hud.show_event(text, color))
	arena.director.status.connect(hud.set_arena_status)
	hud.add_vertical_help()


func _on_hit(_damage: int) -> void:
	hits += 1
	hud.set_stats(hits, knockdowns)
	hud.pulse_crosshair()


func _on_knockdown() -> void:
	knockdowns += 1
	hud.set_stats(hits, knockdowns)


# ---------------- 조작키 ----------------

## 조작키는 설정(scripts/settings/game_settings.gd)에서 등록한다. 키 바꾸기도 거기서.
func _setup_inputs() -> void:
	GameSettings.apply_startup()


# ---------------- 하늘과 빛 ----------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.58, 0.90)
	sky_mat.sky_horizon_color = Color(0.86, 0.90, 0.93)
	sky_mat.ground_horizon_color = Color(0.80, 0.82, 0.78)
	sky_mat.ground_bottom_color = Color(0.45, 0.52, 0.40)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# 주변광은 하늘색을 반만 섞고 나머지는 따뜻한 흰빛 → 밝은 바닥이 파랗게 물들지 않는다
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.45
	env.ambient_light_color = Color(0.86, 0.84, 0.80)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.85
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.84, 0.88, 0.93)
	env.fog_density = 0.004
	env.fog_aerial_perspective = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08

	# 웹(호환 렌더러)에서는 같은 설정이 더 밝고 물빠져 보여서 조금 눌러 준다
	var compat: bool = RenderingServer.get_rendering_device() == null   # 웹, 또는 그래픽 카드가 오래돼 호환 모드로 켜진 경우
	if compat:
		env.tonemap_exposure = 0.62
		env.ambient_light_energy = 0.5
		env.adjustment_saturation = 1.2
		env.adjustment_contrast = 1.08

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -30, 0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 0.75 if compat else 1.0
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)
	# 화질 설정(그림자, 구석 그늘, 빛 번짐, 테두리 매끄럽게)을 적용한다
	GameSettings.register_world(env, sun)
