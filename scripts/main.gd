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
## 점검용: 정해 두면 저장된 캐릭터 대신 이 캐릭터로 시작한다
static var test_player_build: CharacterBuild = null

var mode := "practice"
var arena: Arena
var player: Player
var duelist: Duelist
var hud: CanvasLayer
var hits := 0
var knockdowns := 0
var round_over := false


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
	else:
		_setup_practice()
	_setup_arena_events()

	_warmup()

	# 배경음악: 처음 화면과 연습장은 차분한 곡, 대결은 숫자 세기와 함께 긴박한 곡
	if first_launch or mode == "practice":
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
	for i in 3:
		var d := TrainingDummy.new()
		var x := (i - 1) * 3.2
		d.position = Vector3(x, 0.1, -1.0 - absf(i - 1) * 1.2)
		d.rotation.y = -x * 0.12
		add_child(d)
		d.hit_taken.connect(_on_hit)
		d.knocked_down.connect(_on_knockdown)
	hud.set_stats(hits, knockdowns)


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
	player.controls_enabled = false


## 효과(불꽃, 파편, 피해 숫자, 번쩍임)를 시작 전에 한 번씩 몰래 그려 둔다.
## 처음 그릴 때 그래픽 준비(셰이더 컴파일)로 화면이 멈칫하는데, 특히 웹에서 심하다.
## 그래서 싸우는 도중이 아니라 시작 화면이 가려진 동안 미리 해 둔다.
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


func _on_round_end(player_won: bool) -> void:
	if round_over:
		return
	round_over = true
	arena.director.running = false
	duelist.active = false
	player.controls_enabled = false
	# 결정타 슬로모션
	Audio.ui("ko")
	Audio.music("", 0.8)
	Engine.time_scale = 0.3
	await get_tree().create_timer(0.9, true, false, true).timeout
	Engine.time_scale = 1.0
	hud.show_big("승리!" if player_won else "패배", Color(1.0, 0.85, 0.3) if player_won else Color(1.0, 0.35, 0.3))
	Audio.stinger("victory" if player_won else "defeat", "menu")
	await get_tree().create_timer(1.4, false).timeout
	hud.show_menu("win" if player_won else "lose")


func _on_menu_choice(choice: String) -> void:
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
		"sound":
			hud.show_menu("sound")
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
		"practice", "duel":
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

func _setup_inputs() -> void:
	_bind_keys("move_forward", [KEY_W, KEY_UP])
	_bind_keys("move_back", [KEY_S, KEY_DOWN])
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("sprint", [KEY_SHIFT])
	_bind_keys("jump", [KEY_SPACE])
	_bind_keys("heavy_attack", [KEY_Q])
	_bind_keys("skill1", [KEY_E])
	_bind_keys("skill2", [KEY_R])
	_bind_keys("grab", [KEY_F])
	_bind_keys("special", [KEY_V])
	# 앉기/슬라이딩. 웹에서는 Ctrl+W 가 탭을 닫아 버리므로 C 만 쓴다
	_bind_keys("crouch", [KEY_C] if OS.has_feature("web") else [KEY_C, KEY_CTRL])
	_bind_mouse("attack", MOUSE_BUTTON_LEFT)
	_bind_mouse("block", MOUSE_BUTTON_RIGHT)


func _bind_keys(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _bind_mouse(action: String, button: MouseButton) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


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
