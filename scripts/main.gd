class_name Game
extends Node3D
## 게임 전체: 경기장(하늘, 바닥, 울타리, 나무)을 만들고, 모드에 따라
## 연습(허수아비) 또는 대결(AI 결투사)을 시작한다.

const HUD_SCRIPT := preload("res://scripts/hud.gd")

## 다시 불러올 때 시작할 모드. "" 이면 처음 켠 것이라 시작 화면을 보여준다.
static var next_mode := ""

var mode := "practice"
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
	_build_arena()
	_build_props()

	var first_launch := next_mode == ""
	mode = "practice" if first_launch else next_mode

	player = Player.new()
	add_child(player)

	hud = HUD_SCRIPT.new()
	add_child(hud)
	hud.menu_choice.connect(_on_menu_choice)
	player.stamina_changed.connect(hud.set_stamina)
	player.hp_changed.connect(hud.set_player_hp)
	player.took_damage.connect(hud.on_player_damaged)
	player.combat_event.connect(hud.show_event)

	if mode == "duel":
		_setup_duel()
	else:
		_setup_practice()

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
	player.position = Vector3(0, 0.1, 3.5)
	hud.set_mode("duel")
	duelist = Duelist.new()
	duelist.position = Vector3(0, 0.1, -5.5)
	add_child(duelist)
	duelist.target = player
	player.attack_started.connect(duelist.on_target_attack)
	duelist.hp_changed.connect(hud.set_enemy_hp)
	duelist.combat_event.connect(hud.show_event)
	duelist.died.connect(_on_round_end.bind(true))
	player.died.connect(_on_round_end.bind(false))
	player.controls_enabled = false


func _countdown() -> void:
	player.controls_enabled = false
	for t in ["3", "2", "1"]:
		hud.show_big(t, Color(1, 1, 1))
		await get_tree().create_timer(0.7, false).timeout
	hud.show_big("싸워라!", Color(1.0, 0.8, 0.35))
	player.controls_enabled = true
	duelist.active = true


func _on_round_end(player_won: bool) -> void:
	if round_over:
		return
	round_over = true
	duelist.active = false
	player.controls_enabled = false
	# 결정타 슬로모션
	Engine.time_scale = 0.3
	await get_tree().create_timer(0.9, true, false, true).timeout
	Engine.time_scale = 1.0
	hud.show_big("승리!" if player_won else "패배", Color(1.0, 0.85, 0.3) if player_won else Color(1.0, 0.35, 0.3))
	await get_tree().create_timer(1.4, false).timeout
	hud.show_menu("win" if player_won else "lose")


func _on_menu_choice(choice: String) -> void:
	match choice:
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
	sky_mat.sky_top_color = Color(0.32, 0.52, 0.80)
	sky_mat.sky_horizon_color = Color(0.78, 0.80, 0.82)
	sky_mat.ground_horizon_color = Color(0.62, 0.62, 0.58)
	sky_mat.ground_bottom_color = Color(0.25, 0.27, 0.22)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.85)
	env.fog_density = 0.006
	env.fog_aerial_perspective = 0.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


# ---------------- 바닥과 경기장 ----------------

func _build_arena() -> void:
	var grass := LowPoly.mat(Color(0.36, 0.50, 0.27), 0.95)
	var grass2 := LowPoly.mat(Color(0.42, 0.55, 0.30), 0.95)
	var dirt := LowPoly.mat(Color(0.58, 0.48, 0.36), 0.95)
	var stone := LowPoly.mat(Color(0.56, 0.55, 0.52), 0.9)
	var stone_dark := LowPoly.mat(Color(0.44, 0.43, 0.41), 0.9)

	# 넓은 풀밭 (울퉁불퉁하게)
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(120, 120)
	ground_mesh.subdivide_width = 30
	ground_mesh.subdivide_depth = 30
	var ground := LowPoly.part(self, ground_mesh, grass, Vector3(0, -0.05, 0), Vector3.ZERO, 0.0)
	ground.mesh = _bumpy_ground(ground_mesh)
	_static_box(Vector3(0, -0.5, 0), Vector3(120, 1, 120))

	# 가운데 흙 마당 (원형)
	LowPoly.part(self, LowPoly.cyl(14.0, 14.2, 0.1, 28), dirt, Vector3(0, 0.0, 0), Vector3.ZERO, 0.04, 3)
	# 돌로 된 원형 단
	LowPoly.part(self, LowPoly.cyl(6.5, 6.8, 0.12, 20), stone, Vector3(0, 0.04, -1.5))
	LowPoly.part(self, LowPoly.cyl(6.0, 6.0, 0.03, 20), stone_dark, Vector3(0, 0.095, -1.5))
	var platform := StaticBody3D.new()
	var pcol := CollisionShape3D.new()
	var pshape := CylinderShape3D.new()
	pshape.radius = 6.6
	pshape.height = 0.2
	pcol.shape = pshape
	platform.position = Vector3(0, 0.0, -1.5)
	platform.add_child(pcol)
	add_child(platform)

	# 풀 덤불
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 140:
		var a := rng.randf() * TAU
		var r := rng.randf_range(15.0, 45.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var h := rng.randf_range(0.25, 0.6)
		LowPoly.part(self, LowPoly.cyl(0.0, rng.randf_range(0.2, 0.45), h, 5), grass2 if i % 2 else grass,
				p + Vector3(0, h * 0.5 - 0.05, 0), Vector3(0, rng.randf() * 90, 0), 0.05, i)


func _bumpy_ground(src: PlaneMesh) -> ArrayMesh:
	var arrays := src.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		var d := Vector2(v.x, v.z).length()
		var hill := clampf((d - 16.0) / 30.0, 0.0, 1.0)
		v.y = (sin(v.x * 0.21) * cos(v.z * 0.17) * 0.6 + sin(v.x * 0.07 + v.z * 0.05) * 1.5) * hill + hill * hill * 3.0
		verts[i] = v
	arrays[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return LowPoly.flat(am)


func _static_box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.position = pos
	body.add_child(col)
	add_child(body)


# ---------------- 울타리, 나무, 바위 ----------------

func _build_props() -> void:
	var wood := LowPoly.mat(Color(0.47, 0.33, 0.21), 0.9)
	var wood_dark := LowPoly.mat(Color(0.35, 0.24, 0.15), 0.9)
	var bark := LowPoly.mat(Color(0.33, 0.24, 0.17), 0.95)
	var leaf := LowPoly.mat(Color(0.25, 0.42, 0.22), 0.9)
	var leaf2 := LowPoly.mat(Color(0.31, 0.48, 0.24), 0.9)
	var rock := LowPoly.mat(Color(0.5, 0.5, 0.48), 0.9)
	var cloth := LowPoly.mat(Color(0.66, 0.16, 0.14), 0.85)

	# 둥근 나무 울타리
	var fence_r := 13.0
	var posts := 28
	for i in posts:
		var a := TAU * i / posts
		var p := Vector3(cos(a) * fence_r, 0, sin(a) * fence_r)
		LowPoly.part(self, LowPoly.cyl(0.09, 0.11, 1.3, 6), wood_dark, p + Vector3(0, 0.65, 0), Vector3.ZERO, 0.01, i)
		var a2 := TAU * (i + 1) / posts
		var p2 := Vector3(cos(a2) * fence_r, 0, sin(a2) * fence_r)
		var mid := (p + p2) * 0.5
		var length := p.distance_to(p2)
		for y in [0.55, 1.0]:
			var rail := LowPoly.part(self, LowPoly.box(Vector3(length + 0.1, 0.1, 0.06)), wood,
					mid + Vector3(0, y, 0), Vector3.ZERO, 0.008, i * 3 + int(y * 10))
			rail.look_at_from_position(rail.position, p2 + Vector3(0, y, 0), Vector3.UP)
			rail.rotate_object_local(Vector3.UP, PI * 0.5)
	# 울타리 충돌 (둥글게 기둥 대신 벽 상자)
	for i in posts:
		var a := TAU * (i + 0.5) / posts
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.3, 1.5, TAU * fence_r / posts + 0.2)
		col.shape = shape
		body.add_child(col)
		body.position = Vector3(cos(a) * fence_r, 0.75, sin(a) * fence_r)
		body.rotation.y = -a
		add_child(body)

	# 깃발 두 개
	for side in [-1.0, 1.0]:
		var base := Vector3(side * 6.5, 0, -8.5)
		LowPoly.part(self, LowPoly.cyl(0.06, 0.08, 4.2, 6), wood_dark, base + Vector3(0, 2.1, 0))
		LowPoly.part(self, LowPoly.sphere(0.1, 6, 4), wood, base + Vector3(0, 4.25, 0))
		var flag := LowPoly.part(self, LowPoly.box(Vector3(0.9, 1.4, 0.03)), cloth, base + Vector3(side * -0.5, 3.4, 0),
				Vector3(0, 0, 0), 0.04, int(side * 5))
		flag.rotation_degrees.y = side * 8.0

	# 무기 거치대 (장식)
	var rack := Node3D.new()
	rack.position = Vector3(-9.0, 0, 3.0)
	rack.rotation_degrees.y = 70
	add_child(rack)
	LowPoly.part(rack, LowPoly.box(Vector3(2.0, 0.1, 0.1)), wood, Vector3(0, 1.0, 0))
	LowPoly.part(rack, LowPoly.box(Vector3(2.0, 0.1, 0.1)), wood, Vector3(0, 0.35, 0))
	for x in [-0.95, 0.95]:
		LowPoly.part(rack, LowPoly.box(Vector3(0.12, 1.2, 0.3)), wood_dark, Vector3(x, 0.6, 0))
	var steel := LowPoly.mat(Color(0.7, 0.72, 0.75), 0.35, 0.8)
	for i in 4:
		var x := -0.6 + i * 0.4
		LowPoly.part(rack, LowPoly.box(Vector3(0.05, 1.1, 0.012)), steel, Vector3(x, 0.95, 0.07), Vector3(0, 0, 4 - i * 3))
		LowPoly.part(rack, LowPoly.box(Vector3(0.2, 0.03, 0.04)), wood_dark, Vector3(x, 0.42, 0.07))
	_static_box(rack.position + Vector3(0, 0.6, 0), Vector3(1.0, 1.2, 1.0))

	# 나무들 (울타리 밖)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(18.0, 40.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var tree := Node3D.new()
		tree.position = p
		tree.rotation.y = rng.randf() * TAU
		var sc := rng.randf_range(0.8, 1.4)
		tree.scale = Vector3.ONE * sc
		add_child(tree)
		LowPoly.part(tree, LowPoly.cyl(0.16, 0.24, 2.0, 6), bark, Vector3(0, 1.0, 0), Vector3.ZERO, 0.03, i)
		if i % 3 == 0:
			# 둥근 활엽수
			LowPoly.part(tree, LowPoly.sphere(1.3, 7, 5), leaf2, Vector3(0, 2.8, 0), Vector3.ZERO, 0.22, i + 100)
			LowPoly.part(tree, LowPoly.sphere(0.9, 6, 4), leaf, Vector3(0.6, 3.4, 0.3), Vector3.ZERO, 0.15, i + 200)
		else:
			# 뾰족한 침엽수
			for k in 3:
				var rad := 1.5 - k * 0.38
				LowPoly.part(tree, LowPoly.cyl(0.0, rad, 1.6, 7), leaf if k % 2 == 0 else leaf2,
						Vector3(0, 2.0 + k * 0.95, 0), Vector3(0, k * 20, 0), 0.08, i * 10 + k)
		_static_box(p + Vector3(0, 1.0, 0), Vector3(0.5, 2.0, 0.5) * sc)

	# 바위
	for i in 18:
		var a := rng.randf() * TAU
		var r := rng.randf_range(14.5, 35.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var s := rng.randf_range(0.4, 1.3)
		var rk := LowPoly.part(self, LowPoly.sphere(s, 7, 5), rock, p + Vector3(0, s * 0.3, 0),
				Vector3(rng.randf() * 30, rng.randf() * 180, 0), s * 0.22, i + 500)
		rk.scale = Vector3(1.0, rng.randf_range(0.55, 0.9), rng.randf_range(0.8, 1.2))
