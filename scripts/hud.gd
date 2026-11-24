extends CanvasLayer
## 화면 표시: 조준점, 체력과 기력, 상대 체력, 알림 글자, 맞았을 때 붉은 테두리, 메뉴.

signal menu_choice(choice: String)

const FONT := preload("res://fonts/NanumGothic-Bold.ttf")

var _root: Control
var _crosshair: Control
var _stamina_bar: ProgressBar
var _hp_bar: ProgressBar
var _hp_box: Control
var _enemy_box: Control
var _enemy_bar: ProgressBar
var _stats: Label
var _help: Label
var _event_label: Label
var _big_label: Label
var _vignette: TextureRect
var _overlay: Control
var _menu_title: Label
var _menu_sub: Label
var _menu_buttons: VBoxContainer
var _pulse := 0.0
var _damage_flash := 0.0
var _low_hp := false
var _mode := "practice"
var _menu_kind := ""


class Crosshair extends Control:
	var pulse := 0.0

	func _draw() -> void:
		var c := size * 0.5
		var gap := 5.0 + pulse * 6.0
		var arm := 7.0
		var col := Color(1, 1, 1, 0.9).lerp(Color(1.0, 0.55, 0.3), pulse)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * gap + Vector2(1, 1), c + d * (gap + arm) + Vector2(1, 1), Color(0, 0, 0, 0.5), 2.0)
			draw_line(c + d * gap, c + d * (gap + arm), col, 2.0)
		draw_circle(c, 1.5, col)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)

	# 맞았을 때 화면 가장자리가 붉어진다
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([Color(0.7, 0, 0, 0), Color(0.7, 0, 0, 0), Color(0.6, 0, 0, 0.85)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 1.05)
	tex.width = 256
	tex.height = 256
	_vignette = TextureRect.new()
	_vignette.texture = tex
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	_root.add_child(_vignette)

	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)

	# 기력 막대 (화면 아래 가운데)
	_stamina_bar = _make_bar(Color(0.95, 0.80, 0.35), Vector2(320, 10))
	_stamina_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stamina_bar.position = Vector2(-160, -48)
	_root.add_child(_stamina_bar)
	var st_label := _small_label("기력")
	st_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	st_label.position = Vector2(-160, -72)
	_root.add_child(st_label)

	# 내 체력 (왼쪽 아래)
	_hp_box = Control.new()
	_hp_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hp_box.position = Vector2(32, -76)
	_hp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hp_box)
	_hp_box.add_child(_small_label("체력"))
	_hp_bar = _make_bar(Color(0.85, 0.22, 0.2), Vector2(300, 16))
	_hp_bar.position = Vector2(0, 26)
	_hp_box.add_child(_hp_bar)

	# 상대 체력 (위 가운데)
	_enemy_box = Control.new()
	_enemy_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_enemy_box.position = Vector2(-220, 24)
	_enemy_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_enemy_box)
	var en := _small_label("결투사")
	en.size = Vector2(440, 20)
	en.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enemy_box.add_child(en)
	_enemy_bar = _make_bar(Color(0.1, 0.65, 0.66), Vector2(440, 14))
	_enemy_bar.position = Vector2(0, 26)
	_enemy_box.add_child(_enemy_bar)

	# 조작법 (왼쪽 위)
	_help = Label.new()
	_help.text = "W A S D  이동\nShift  대시 (누르고 있으면 달리기)\nSpace  점프\n왼쪽 클릭  베기 (연속으로 누르면 연속 베기)\nQ  내려찍기 (느리지만 강함, 막기를 깨뜨림)\n오른쪽 클릭  막기 (맞기 직전에 누르면 튕겨내기)\nEsc  메뉴"
	_help.add_theme_font_size_override("font_size", 15)
	_help.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_help.position = Vector2(24, 20)
	_root.add_child(_help)

	# 기록 (오른쪽 위)
	_stats = Label.new()
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats.add_theme_font_size_override("font_size", 18)
	_stats.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stats.position = Vector2(-264, 20)
	_stats.size = Vector2(240, 60)
	_root.add_child(_stats)

	# 알림 글자 ("튕겨내기!" 등, 조준점 아래)
	_event_label = Label.new()
	_event_label.set_anchors_preset(Control.PRESET_CENTER)
	_event_label.size = Vector2(600, 40)
	_event_label.position = Vector2(-300, 40)
	_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_event_label.add_theme_font_size_override("font_size", 28)
	_event_label.add_theme_constant_override("outline_size", 8)
	_event_label.modulate.a = 0.0
	_root.add_child(_event_label)

	# 큰 글자 (3, 2, 1, 싸워라!, 승리!)
	_big_label = Label.new()
	_big_label.set_anchors_preset(Control.PRESET_CENTER)
	_big_label.size = Vector2(800, 120)
	_big_label.position = Vector2(-400, -200)
	_big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big_label.add_theme_font_size_override("font_size", 88)
	_big_label.add_theme_constant_override("outline_size", 14)
	_big_label.pivot_offset = Vector2(400, 60)
	_big_label.modulate.a = 0.0
	_root.add_child(_big_label)

	_overlay = _make_overlay()
	_root.add_child(_overlay)
	set_mode("practice")


func _make_theme() -> Theme:
	# 한글 글꼴을 게임에 넣어 두어서 어떤 컴퓨터, 웹에서도 똑같이 보인다.
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 16
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.75))
	theme.set_constant("outline_size", "Label", 4)
	return theme


func _make_bar(color: Color, bar_size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = 100
	bar.custom_minimum_size = bar_size
	bar.size = bar_size
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(int(bar_size.y / 2))
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(int(bar_size.y / 2))
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	return bar


func _small_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	return l


func _make_overlay() -> Control:
	var panel := ColorRect.new()
	panel.color = Color(0.03, 0.04, 0.06, 0.66)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	_menu_title = Label.new()
	_menu_title.add_theme_font_size_override("font_size", 64)
	_menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_menu_title)
	_menu_sub = Label.new()
	_menu_sub.add_theme_font_size_override("font_size", 20)
	_menu_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_menu_sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	box.add_child(spacer)
	_menu_buttons = VBoxContainer.new()
	_menu_buttons.add_theme_constant_override("separation", 10)
	box.add_child(_menu_buttons)
	return panel


func _add_button(text: String, choice: String, primary: bool = false) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 52 if primary else 44)
	b.add_theme_font_size_override("font_size", 20 if primary else 17)
	b.pressed.connect(func(): menu_choice.emit(choice))
	_menu_buttons.add_child(b)


## kind: "start", "pause", "win", "lose"
func show_menu(kind: String) -> void:
	_menu_kind = kind
	for c in _menu_buttons.get_children():
		c.queue_free()
	match kind:
		"start":
			_menu_title.text = "챔피언"
			_menu_sub.text = "1대1 칼싸움"
			_add_button("AI와 대결", "duel", true)
			_add_button("연습장 (허수아비)", "practice")
		"pause":
			_menu_title.text = "일시정지"
			_menu_sub.text = "AI와 대결 중" if _mode == "duel" else "연습장"
			_add_button("계속하기", "resume", true)
			_add_button("처음부터 다시", "retry")
			if _mode == "duel":
				_add_button("연습장으로", "practice")
			else:
				_add_button("AI와 대결", "duel")
		"win":
			_menu_title.text = "승리!"
			_menu_sub.text = "결투사를 쓰러뜨렸어요"
			_add_button("다시 대결", "retry", true)
			_add_button("연습장으로", "practice")
		"lose":
			_menu_title.text = "패배"
			_menu_sub.text = "빛나는 칼을 보면 막거나(오른쪽 클릭) 옆으로 대시(Shift)하세요"
			_add_button("다시 대결", "retry", true)
			_add_button("연습장으로", "practice")
	if not OS.has_feature("web"):
		_add_button("게임 종료", "quit")
	_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func hide_menu() -> void:
	_overlay.visible = false
	_menu_kind = ""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().paused = false


func set_mode(m: String) -> void:
	_mode = m
	_enemy_box.visible = m == "duel"
	_hp_box.visible = m == "duel"
	_stats.visible = m == "practice"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if _menu_kind == "pause":
			hide_menu()
		elif _menu_kind == "":
			show_menu("pause")
	elif event is InputEventMouseButton and event.pressed and not _overlay.visible \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _overlay and not _overlay.visible:
		show_menu("pause")


func set_stamina(value: float, max_value: float) -> void:
	_stamina_bar.max_value = max_value
	_stamina_bar.value = value


func set_player_hp(value: int, max_value: int) -> void:
	_hp_bar.max_value = max_value
	_hp_bar.value = value
	_low_hp = value > 0 and value <= max_value * 0.3


func set_enemy_hp(value: int, max_value: int) -> void:
	_enemy_bar.max_value = max_value
	var tw := create_tween()
	tw.tween_property(_enemy_bar, "value", float(value), 0.15)


func on_player_damaged(_amount: int) -> void:
	_damage_flash = 1.0


func set_stats(hits: int, knockdowns: int) -> void:
	_stats.text = "맞힌 횟수  %d\n쓰러뜨린 허수아비  %d" % [hits, knockdowns]


func pulse_crosshair() -> void:
	_pulse = 1.0


func show_event(text: String, color: Color) -> void:
	_event_label.text = text
	_event_label.modulate = color
	_event_label.scale = Vector2.ONE
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(_event_label, "modulate:a", 0.0, 0.35)


func show_big(text: String, color: Color) -> void:
	_big_label.text = text
	_big_label.modulate = color
	_big_label.scale = Vector2(1.4, 1.4)
	var tw := create_tween()
	tw.tween_property(_big_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.35)
	tw.tween_property(_big_label, "modulate:a", 0.0, 0.2)


func _process(delta: float) -> void:
	_pulse = maxf(_pulse - delta * 5.0, 0.0)
	var ch := _crosshair as Crosshair
	ch.pulse = _pulse
	ch.queue_redraw()
	# 붉은 테두리: 맞은 순간 번쩍 + 체력이 낮으면 심장 박동처럼 깜빡임
	_damage_flash = maxf(_damage_flash - delta * 2.2, 0.0)
	var low := 0.0
	if _low_hp:
		low = 0.35 + sin(Time.get_ticks_msec() / 1000.0 * 6.0) * 0.15
	_vignette.modulate.a = maxf(_damage_flash, low)
