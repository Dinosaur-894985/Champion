extends ColorRect
## 설정 화면: 조작(마우스 감도, 위아래 반전, 시야), 키 바꾸기, 화질, 소리.
## 바꾸는 즉시 적용되고 user://settings.cfg 에 저장된다 (scripts/settings/game_settings.gd).
## 시작 화면과 일시정지 메뉴의 '설정' 에서 열린다.

signal closed

const C_ON := Color(1.0, 0.78, 0.35)
const C_DIM := Color(1, 1, 1, 0.65)
const TABS := [["controls", "조작"], ["keys", "키 바꾸기"], ["graphics", "화질"], ["sound", "소리"]]

var tab := "controls"
var _tab_buttons := {}
var _content: VBoxContainer
var _note: Label
var _key_buttons := {}    # 행동 → Button
var _quality_buttons := {}
var _quality_desc: Label
## 지금 새 키를 기다리는 행동 ("" = 아님)
var _listening := ""


func _ready() -> void:
	color = Color(0.03, 0.04, 0.06, 0.92)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(900, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := _label("설정", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _label("바꾸면 바로 적용되고, 다음에 켜도 그대로예요", 17)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = C_DIM
	box.add_child(sub)

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	for t in TABS:
		var b := _button(t[1], 150, 46, 19)
		b.toggle_mode = true
		b.pressed.connect(show_tab.bind(t[0]))
		tabs.add_child(b)
		_tab_buttons[t[0]] = b
	box.add_child(tabs)

	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(22)
	frame.add_theme_stylebox_override("panel", sb)
	frame.custom_minimum_size = Vector2(900, 440)
	box.add_child(frame)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	frame.add_child(_content)

	_note = _label("", 17)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.custom_minimum_size = Vector2(0, 26)
	_note.modulate = Color(0.75, 0.9, 1.0)
	box.add_child(_note)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 16)
	var reset := _button("이 칸 기본값으로", 240, 46, 17)
	reset.pressed.connect(_reset_tab)
	bottom.add_child(reset)
	var close := _button("닫기", 240, 50, 20)
	close.set_meta("sfx", "ui_back")
	close.pressed.connect(close_menu)
	bottom.add_child(close)
	box.add_child(bottom)

	show_tab(tab)


func show_tab(t: String) -> void:
	_cancel_listen()
	tab = t
	for k in _tab_buttons:
		var b: Button = _tab_buttons[k]
		b.set_pressed_no_signal(k == t)
		b.modulate = C_ON if k == t else Color(1, 1, 1)
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_key_buttons.clear()
	_quality_buttons.clear()
	_note.text = ""
	match t:
		"controls":
			_build_controls()
		"keys":
			_build_keys()
		"graphics":
			_build_graphics()
		"sound":
			_build_sound()


func close_menu() -> void:
	if _listening != "":
		_cancel_listen()
		return
	GameSettings.save()
	Audio.save_settings()
	closed.emit()


# ---------------- 조작 ----------------

func _build_controls() -> void:
	_slider_row("마우스 감도", GameSettings.SENS_MIN, GameSettings.SENS_MAX, 0.05, GameSettings.mouse_sens,
		func(v: float) -> String: return "%.2f배" % v,
		func(v: float): GameSettings.mouse_sens = v)
	_slider_row("시야 넓이", GameSettings.FOV_MIN, GameSettings.FOV_MAX, 1.0, GameSettings.fov,
		func(v: float) -> String: return "%d도" % int(v),
		func(v: float):
			GameSettings.fov = v
			_apply_fov_now())
	_check_row("마우스 위아래 반대로", GameSettings.invert_y, func(on: bool): GameSettings.invert_y = on)
	var tip := _label("감도가 1배면 처음 그대로예요. 화면이 너무 빨리 돌면 낮추고, 느리면 올리세요.\n시야를 넓히면 옆이 더 보이지만 상대가 작아 보여요 (처음 78도).", 16)
	tip.modulate = C_DIM
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(tip)


## 경기 중이면 카메라 시야를 바로 바꿔 본다
func _apply_fov_now() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		cam.fov = GameSettings.fov


# ---------------- 키 바꾸기 ----------------

func _build_keys() -> void:
	var tip := _label("바꿀 행동의 버튼을 누른 뒤, 새 키나 마우스 버튼을 누르세요 (Esc: 취소).\n이미 쓰는 키를 고르면 두 행동의 키를 서로 바꿔요.", 16)
	tip.modulate = C_DIM
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(tip)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	for row in GameSettings.ACTIONS:
		var a: String = row[0]
		var name_label := _label(row[1], 18)
		name_label.custom_minimum_size = Vector2(170, 0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(name_label)
		var b := _button("", 240, 40, 17)
		b.pressed.connect(_start_listen.bind(a))
		grid.add_child(b)
		_key_buttons[a] = b
	var gc := CenterContainer.new()
	gc.add_child(grid)
	_content.add_child(gc)
	_refresh_keys()


func _refresh_keys() -> void:
	for a in _key_buttons:
		var b: Button = _key_buttons[a]
		if a == _listening:
			b.text = "키를 누르세요…"
			b.modulate = C_ON
		else:
			b.text = GameSettings.key_label(a, true)
			b.modulate = Color(1, 1, 1)


func _start_listen(action: String) -> void:
	_listening = action
	_note.text = "'%s' 에 쓸 키를 누르세요" % GameSettings.action_title(action)
	_refresh_keys()


func _cancel_listen() -> void:
	if _listening == "":
		return
	_listening = ""
	_note.text = ""
	_refresh_keys()


func _input(event: InputEvent) -> void:
	if _listening == "":
		return
	var pressed := false
	if event is InputEventKey:
		pressed = event.pressed and not event.echo
	elif event is InputEventMouseButton:
		pressed = event.pressed
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
		_cancel_listen()
		return
	var code := GameSettings.code_from_event(event)
	var why := GameSettings.reject_reason(_listening, code)
	if why != "":
		_note.text = why
		return
	var action := _listening
	_listening = ""
	var swapped := GameSettings.rebind(action, code)
	if swapped != "":
		_note.text = "'%s' 와(과) 키를 맞바꿨어요. '%s' 은(는) 이제 %s" % [
			GameSettings.action_title(swapped), GameSettings.action_title(swapped), GameSettings.key_label(swapped, true)]
	else:
		_note.text = "'%s' → %s" % [GameSettings.action_title(action), GameSettings.code_label(code)]
	Audio.ui("ui_confirm")
	_refresh_keys()


# ---------------- 화질 ----------------

func _build_graphics() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var l := _label("화질", 20)
	l.custom_minimum_size = Vector2(80, 0)
	row.add_child(l)
	for q in GameSettings.QUALITY_ORDER:
		var b := _button(GameSettings.QUALITY[q].name, 150, 48, 19)
		b.toggle_mode = true
		b.pressed.connect(_set_quality.bind(q))
		row.add_child(b)
		_quality_buttons[q] = b
	_content.add_child(row)
	_quality_desc = _label("", 17)
	_quality_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quality_desc.modulate = Color(0.75, 0.9, 1.0)
	_content.add_child(_quality_desc)
	if OS.has_feature("web"):
		var w := _label("웹에서는 전체 화면을 브라우저의 F11 로 켜세요.", 16)
		w.modulate = C_DIM
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_content.add_child(w)
	else:
		_check_row("전체 화면", GameSettings.fullscreen, func(on: bool):
			GameSettings.fullscreen = on
			GameSettings.apply_window())
	_check_row("휘두를 때 빛 자취 (검기)", GameSettings.trails, func(on: bool): GameSettings.trails = on)
	_check_row("화면 흔들림 (걷기·착지·손 따라오기)", GameSettings.view_motion, func(on: bool): GameSettings.view_motion = on)
	_check_row("초당 화면 수(FPS) 보기", GameSettings.show_fps, func(on: bool): GameSettings.show_fps = on)
	var tip := _label("게임이 끊기면 화질을 낮춰 보세요. FPS 가 60 근처면 부드러운 거예요.", 16)
	tip.modulate = C_DIM
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(tip)
	_refresh_quality()


func _set_quality(q: String) -> void:
	GameSettings.quality = q
	GameSettings.apply_graphics()
	GameSettings.save()
	_refresh_quality()


func _refresh_quality() -> void:
	for q in _quality_buttons:
		var b: Button = _quality_buttons[q]
		b.set_pressed_no_signal(q == GameSettings.quality)
		b.modulate = C_ON if q == GameSettings.quality else Color(1, 1, 1)
	_quality_desc.text = GameSettings.QUALITY[GameSettings.quality].desc


# ---------------- 소리 ----------------

func _build_sound() -> void:
	for row in [["전체", "Master"], ["배경음악", "Music"], ["효과음", "SFX"]]:
		var bus: String = row[1]
		_slider_row(row[0], 0.0, 1.0, 0.05, Audio.get_volume(bus),
			func(v: float) -> String: return "%d%%" % roundi(v * 100),
			func(v: float): Audio.set_volume(bus, v))


# ---------------- 기본값 ----------------

func _reset_tab() -> void:
	match tab:
		"controls":
			GameSettings.mouse_sens = 1.0
			GameSettings.invert_y = false
			GameSettings.fov = GameSettings.FOV_DEFAULT
			_apply_fov_now()
		"keys":
			GameSettings.reset_keys()
		"graphics":
			GameSettings.quality = "high"
			GameSettings.show_fps = false
			GameSettings.trails = true
			GameSettings.view_motion = true
			if GameSettings.fullscreen:
				GameSettings.fullscreen = false
				GameSettings.apply_window()
			GameSettings.apply_graphics()
		"sound":
			var d: Dictionary = Audio.director().DEFAULT_VOLUMES
			for bus in d:
				Audio.set_volume(bus, d[bus])
			Audio.save_settings()
	GameSettings.save()
	show_tab(tab)
	_note.text = "기본값으로 되돌렸어요"


# ---------------- 만들기 도우미 ----------------

func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


func _button(text: String, w: int, h: int, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", font_size)
	b.set_meta("sfx", "ui_click")
	return b


## 이름 + 막대 + 값. fmt: 값 → 보일 글자, on_change: 값이 바뀔 때
func _slider_row(text: String, lo: float, hi: float, step: float, value: float, fmt: Callable, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var name_label := _label(text, 19)
	name_label.custom_minimum_size = Vector2(180, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(420, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var val := _label(fmt.call(value), 18)
	val.custom_minimum_size = Vector2(90, 0)
	row.add_child(val)
	slider.value_changed.connect(func(v: float):
		on_change.call(v)
		val.text = fmt.call(v))
	_content.add_child(row)
	return slider


func _check_row(text: String, on: bool, on_change: Callable) -> CheckButton:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.custom_minimum_size = Vector2(420, 40)
	c.add_theme_font_size_override("font_size", 19)
	c.toggled.connect(func(v: bool): on_change.call(v))
	row.add_child(c)
	_content.add_child(row)
	return c
