extends CanvasLayer
## 화면 표시: 조준점, 기력 막대, 조작법, 기록, 시작/일시정지 화면.

var _crosshair: Control
var _stamina_bar: ProgressBar
var _stats: Label
var _overlay: Control
var _pulse := 0.0


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
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_crosshair)

	# 기력 막대 (화면 아래 가운데)
	_stamina_bar = ProgressBar.new()
	_stamina_bar.show_percentage = false
	_stamina_bar.max_value = 100
	_stamina_bar.value = 100
	_stamina_bar.custom_minimum_size = Vector2(320, 10)
	_stamina_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stamina_bar.position = Vector2(-160, -48)
	_stamina_bar.size = Vector2(320, 10)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(5)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.95, 0.80, 0.35)
	fg.set_corner_radius_all(5)
	_stamina_bar.add_theme_stylebox_override("background", bg)
	_stamina_bar.add_theme_stylebox_override("fill", fg)
	root.add_child(_stamina_bar)
	var st_label := Label.new()
	st_label.text = "기력"
	st_label.add_theme_font_size_override("font_size", 14)
	st_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	st_label.position = Vector2(-160, -72)
	root.add_child(st_label)

	# 조작법 (왼쪽 위)
	var help := Label.new()
	help.text = "W A S D  이동\nShift  달리기\nSpace  점프\n왼쪽 클릭  베기 (연속으로 누르면 좌우 연속 베기)\n오른쪽 클릭  내려찍기 (느리지만 강함)\nEsc  마우스 풀기"
	help.add_theme_font_size_override("font_size", 15)
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	help.position = Vector2(24, 20)
	root.add_child(help)

	# 기록 (오른쪽 위)
	_stats = Label.new()
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stats.add_theme_font_size_override("font_size", 18)
	_stats.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stats.position = Vector2(-264, 20)
	_stats.size = Vector2(240, 60)
	root.add_child(_stats)

	_overlay = _make_overlay()
	root.add_child(_overlay)
	_show_overlay(true)


func _make_theme() -> Theme:
	# 한글이 잘 나오도록 컴퓨터에 깔린 한글 글꼴을 쓴다.
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Apple SD Gothic Neo", "Noto Sans CJK KR", "NanumGothic", "sans-serif"])
	font.font_weight = 600
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 16
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.7))
	theme.set_constant("outline_size", "Label", 4)
	return theme


func _make_overlay() -> Control:
	var panel := ColorRect.new()
	panel.color = Color(0.03, 0.04, 0.06, 0.62)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := Label.new()
	title.text = "챔피언"
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "연습장 — 허수아비를 베어 보세요"
	sub.add_theme_font_size_override("font_size", 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var start := Button.new()
	start.text = "클릭해서 시작"
	start.custom_minimum_size = Vector2(260, 52)
	start.add_theme_font_size_override("font_size", 20)
	start.pressed.connect(func(): _show_overlay(false))
	box.add_child(start)
	var quit := Button.new()
	quit.text = "게임 종료"
	quit.custom_minimum_size = Vector2(260, 44)
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)
	return panel


func _show_overlay(on: bool) -> void:
	_overlay.visible = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	get_tree().paused = on


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		_show_overlay(not _overlay.visible)
	elif event is InputEventMouseButton and event.pressed and not _overlay.visible \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _overlay and not _overlay.visible:
		_show_overlay(true)


func set_stamina(value: float, max_value: float) -> void:
	_stamina_bar.max_value = max_value
	_stamina_bar.value = value


func set_stats(hits: int, knockdowns: int) -> void:
	_stats.text = "맞힌 횟수  %d\n쓰러뜨린 허수아비  %d" % [hits, knockdowns]


func pulse_crosshair() -> void:
	_pulse = 1.0


func _process(delta: float) -> void:
	_pulse = maxf(_pulse - delta * 5.0, 0.0)
	var ch := _crosshair as Crosshair
	ch.pulse = _pulse
	ch.queue_redraw()
