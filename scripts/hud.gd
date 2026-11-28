extends CanvasLayer
## 화면 표시: 조준점, 체력과 기력, 상대 체력, 알림 글자, 맞았을 때 붉은 테두리, 메뉴.

signal menu_choice(choice: String)

const FONT := preload("res://fonts/NanumGothic-Bold.ttf")
const BUILD_EDITOR := preload("res://scripts/ui/build_editor.gd")
const DIR_INDICATOR := preload("res://scripts/ui/dir_indicator.gd")
const SETTINGS_MENU := preload("res://scripts/ui/settings_menu.gd")

## '뒤로' 를 누르면 돌아갈 메뉴 (start / pause / win / lose)
var menu_return := "start"
var _player: Player
var _slots := []          # 스킬 칸: {"skill", "panel", "fill", "name", "key", "time"}
var _haste_label: Label
var _enemy_name: Label
var _enemy_stamina: ProgressBar
var _editor: Control
var _settings: Control
var _fps: Label

var _root: Control
var _crosshair: Control
var _dir_ind: Control
var _stamina_bar: ProgressBar
var _gauge_bar: ProgressBar
var _gauge_label: Label
var _gauge_ready := false
var _ammo_label: Label
var _enemy_gauge: ProgressBar
var _hp_bar: ProgressBar
var _hp_box: Control
var _enemy_box: Control
var _enemy_bar: ProgressBar
var _stats: Label
var _help: Label
var _event_label: Label
var _big_label: Label
var _vignette: TextureRect
var _counter_vignette: TextureRect
var _counter := 0.0
var _overlay: Control
var _menu_title: Label
var _menu_sub: Label
var _menu_buttons: VBoxContainer
var _pulse := 0.0
var _damage_flash := 0.0
var _low_hp := false
var _mode := "practice"
var _menu_kind := ""


## 조작법. {행동} 자리에는 설정에서 고른 키 이름이 들어간다 (scripts/settings/game_settings.gd)
const HELP_TEXT := "{move}  이동    {jump}  점프\n{sprint}  달리기 (누르고 있으면 점점 빨라짐)\n{move_left} / {move_right} / {move_back} 두 번 빠르게  그쪽으로 피하기\n{crouch}  앉기 — 달리다 누르면 슬라이딩 (슬라이딩 중 {jump}: 점프)\n벽을 보고 {move_forward} + {jump}  벽 타고 오르기 / 벽 옆을 달리다 {jump}  벽 달리기\n{attack} 연타  연속기 — 이어 누를 때 마우스를 위/아래로 움직이면 갈래가 바뀜\n    옆 네 번: 회전 베기 / 위로 이어: 쪼개기 / 아래로 이어: 꿰뚫기\n달리며 {attack}  달려 찌르기 / 슬라이딩 중 {attack}  다리 베기(넘어뜨림)\n벽을 달리다(벽 차고 뛴 직후) {attack}  벽 차고 베기\n{attack} 길게  차지 베기    {heavy_attack}  내려찍기 (막기를 깨뜨림)\n수리검: {heavy_attack} 던지기 (6장, 떨어진 것을 지나가며 주움 · 공중에서도 던짐) · {attack} 길게 놓으면 세 장 · 맨몸: 주먹과 발차기\n{block}  막기 — 그냥 막아도 피해 절반 · 위/옆/아래 방향까지 맞추면 완벽 막기(상대 휘청, 바로 반격)\n{grab}  잡아 던지기 · 금 간 돌기둥을 쳐서 상대 쪽으로 쓰러뜨리기\n바람 발판을 밟으면 높이 날아오름 → 날아가며 {attack}하면 낙하 찍기\n휘두르기 시작 직후 {block}/{grab}/{sprint}  속임수 · 아슬하게 피한 직후 {attack}  반격\n{skill1} / {skill2}  특수 스킬    {special}  무기 필살기    Esc  메뉴"
const HELP2_TEXT := "높은 곳에서 {attack} (아래를 보며)  낙하 찍기\n공중에서 {attack}  공중 베기\n난간에 매달림  {jump} 올라서기 / {attack} 뛰어올라 베기 / {move_back} 놓기\n공중에서 줄에 닿으면  짚라인 ({jump} 뛰어내리기)\n강한 공격으로 상대를 낭떠러지로 밀어 떨어뜨리기"


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

	# 회피 반격 기회: 화면 가장자리가 푸르게 빛난다
	var cgrad := Gradient.new()
	cgrad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	cgrad.colors = PackedColorArray([Color(0.3, 0.8, 1, 0), Color(0.3, 0.8, 1, 0), Color(0.35, 0.85, 1.0, 0.75)])
	var ctex := GradientTexture2D.new()
	ctex.gradient = cgrad
	ctex.fill = GradientTexture2D.FILL_RADIAL
	ctex.fill_from = Vector2(0.5, 0.5)
	ctex.fill_to = Vector2(1.05, 1.05)
	ctex.width = 256
	ctex.height = 256
	_counter_vignette = TextureRect.new()
	_counter_vignette.texture = ctex
	_counter_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_counter_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_counter_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter_vignette.modulate.a = 0.0
	_root.add_child(_counter_vignette)

	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)
	# 공격/막기 방향 표시 (조준점 둘레)
	_dir_ind = DIR_INDICATOR.new()
	_dir_ind.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dir_ind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dir_ind)

	# 기력 막대 (화면 아래 가운데)
	_stamina_bar = _make_bar(Color(0.95, 0.80, 0.35), Vector2(320, 10))
	_stamina_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stamina_bar.position = Vector2(-160, -48)
	_root.add_child(_stamina_bar)
	var st_label := _small_label("기력")
	st_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	st_label.position = Vector2(-160, -72)
	_root.add_child(st_label)

	# 필살기 게이지 (기력 막대 아래, 금색). 다 차면 빛난다.
	_gauge_bar = _make_bar(Color(1.0, 0.72, 0.15), Vector2(320, 8))
	_gauge_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_gauge_bar.position = Vector2(-160, -32)
	_gauge_bar.value = 0
	_root.add_child(_gauge_bar)
	_gauge_label = _small_label("")
	_gauge_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_gauge_label.position = Vector2(-160, -72)
	_gauge_label.size = Vector2(320, 20)
	_gauge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gauge_label.add_theme_constant_override("outline_size", 4)
	_root.add_child(_gauge_label)
	# 수리검 수 (던지는 무기일 때만 보인다)
	_ammo_label = _small_label("")
	_ammo_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ammo_label.position = Vector2(-160, -72)
	_ammo_label.size = Vector2(200, 20)
	_ammo_label.add_theme_constant_override("outline_size", 4)
	_root.add_child(_ammo_label)

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
	_enemy_name = _small_label("결투사")
	_enemy_name.size = Vector2(440, 20)
	_enemy_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enemy_box.add_child(_enemy_name)
	_enemy_bar = _make_bar(Color(0.1, 0.65, 0.66), Vector2(440, 14))
	_enemy_bar.position = Vector2(0, 26)
	_enemy_box.add_child(_enemy_bar)
	_enemy_stamina = _make_bar(Color(0.95, 0.80, 0.35, 0.85), Vector2(440, 5))
	_enemy_stamina.position = Vector2(0, 44)
	_enemy_box.add_child(_enemy_stamina)
	_enemy_gauge = _make_bar(Color(1.0, 0.72, 0.15, 0.9), Vector2(440, 4))
	_enemy_gauge.position = Vector2(0, 52)
	_enemy_gauge.value = 0
	_enemy_box.add_child(_enemy_gauge)

	# 특수 스킬 칸 (오른쪽 아래)
	for i in 2:
		_slots.append(_make_slot(i))
	_haste_label = Label.new()
	_haste_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_haste_label.position = Vector2(-160, -100)
	_haste_label.size = Vector2(320, 24)
	_haste_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_haste_label.add_theme_font_size_override("font_size", 18)
	_haste_label.modulate = Color(0.55, 1.0, 0.7)
	_root.add_child(_haste_label)

	# 조작법 (왼쪽 위)
	_help = Label.new()
	_help.text = GameSettings.fill(HELP_TEXT)
	_help.add_theme_font_size_override("font_size", 15)
	_help.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	_help.add_theme_constant_override("outline_size", 5)   # 밝은 경기장에서도 읽히게
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

	# 초당 화면 수 (설정에서 켰을 때만, 왼쪽 아래 구석)
	_fps = Label.new()
	_fps.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_fps.position = Vector2(24, -36)
	_fps.add_theme_font_size_override("font_size", 15)
	_fps.visible = false
	_root.add_child(_fps)

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


func _add_button(text: String, choice: String, primary: bool = false, width: int = 340) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 52 if primary else 44)
	b.add_theme_font_size_override("font_size", 20 if primary else 17)
	b.pressed.connect(func(): menu_choice.emit(choice))
	# 누를 때 소리 (scripts/audio/audio.gd 가 버튼마다 자동으로 붙인다)
	b.set_meta("sfx", "ui_back" if choice == "back" else ("ui_confirm" if primary else "ui_click"))
	_menu_buttons.add_child(b)


## kind: "start", "pause", "win", "lose", "opponent"(상대 고르기), "presets"(정해진 상대 목록),
## "tutorial_done"(튜토리얼을 마쳤다)
func show_menu(kind: String) -> void:
	if kind in ["start", "pause", "win", "lose", "tutorial_done"]:
		menu_return = kind
	_menu_kind = kind
	for c in _menu_buttons.get_children():
		c.queue_free()
	var my_build := _player.build.summary() if _player else ""
	match kind:
		"start":
			_menu_title.text = "챔피언"
			_menu_sub.text = "1대1 칼싸움\n\n내 캐릭터:  " + my_build
			var first_time := not Tutorial.is_done()
			if first_time:
				# 처음 하는 사람: 튜토리얼을 맨 위에, 눈에 띄게
				_add_button("튜토리얼  ·  처음이라면 여기부터!", "tutorial", true)
			_add_button("AI와 대결", "opponent", not first_time)
			_add_button("캐릭터 만들기", "build")
			_add_button("연습장 (허수아비)", "practice")
			if not first_time:
				_add_button("튜토리얼 (조작 배우기)", "tutorial")
			_add_button("전적 (무기별 승률)", "records")
			_add_button("설정 (감도 · 키 · 화질 · 소리)", "settings")
		"pause":
			_menu_title.text = "일시정지"
			if _mode == "tutorial":
				_menu_sub.text = "튜토리얼 중"
				_add_button("계속하기", "resume", true)
				_add_button("이 단계 건너뛰기", "tut_skip")
				_add_button("튜토리얼 그만두기 (처음 화면)", "home")
				_add_button("설정 (감도 · 키 · 화질 · 소리)", "settings")
			else:
				_menu_sub.text = ("AI와 대결 중" if _mode == "duel" else "연습장") + "\n\n내 캐릭터:  " + my_build
				_add_button("계속하기", "resume", true)
				_add_button("처음부터 다시", "retry")
				_add_button("캐릭터 만들기", "build")
				if _mode == "duel":
					_add_button("다른 상대 고르기", "opponent")
					_add_button("연습장으로", "practice")
				else:
					_add_button("AI와 대결", "opponent")
				_add_button("설정 (감도 · 키 · 화질 · 소리)", "settings")
		"win":
			_menu_title.text = "승리!"
			_menu_sub.text = "%s을(를) 쓰러뜨렸어요  ·  %s" % [_enemy_title, Duelist.DIFFICULTY_NAMES.get(Game.ai_difficulty(), "")]
			_add_result_panel(true)
			if Game.ai_difficulty() != "hard":
				_add_note("이번엔 '%s'에 도전해 볼까요? (다른 상대 고르기 → 난이도)" % Duelist.DIFFICULTY_NAMES["hard" if Game.ai_difficulty() == "normal" else "normal"])
			_add_button("다시 대결", "retry", true)
			_add_button("다른 상대 고르기", "opponent")
			_add_button("캐릭터 만들기", "build")
			_add_button("연습장으로", "practice")
		"lose":
			_menu_title.text = "패배"
			_menu_sub.text = "%s에게 졌어요  ·  %s" % [_enemy_title, Duelist.DIFFICULTY_NAMES.get(Game.ai_difficulty(), "")]
			_add_result_panel(false)
			_add_note(GameSettings.fill("빛나는 칼을 보면 막거나({block}) 옆으로 피하세요({move_left} 또는 {move_right} 두 번 빠르게)"))
			if Game.ai_difficulty() != "easy":
				_add_note("너무 어렵다면 난이도를 낮춰 보세요 (다른 상대 고르기 → 난이도)")
			_add_button("다시 대결", "retry", true)
			_add_button("다른 상대 고르기", "opponent")
			_add_button("캐릭터 만들기", "build")
			_add_button("연습장으로", "practice")
		"records":
			_add_records()
			_add_button("뒤로", "back")
		"tutorial_done":
			_menu_title.text = "튜토리얼 끝!"
			_menu_sub.text = GameSettings.fill("이제 AI와 붙어 보세요.\n잊어버린 조작은 연습장 왼쪽 위에 늘 적혀 있어요.\n{grab} 잡기, {crouch} 슬라이딩, {skill1}/{skill2} 스킬도 있어요.")
			_add_button("AI와 대결", "opponent", true)
			_add_button("연습장 (허수아비)", "practice")
			_add_button("튜토리얼 다시 하기", "retry")
			_add_button("처음 화면", "home")
		"opponent":
			_menu_title.text = "상대 고르기"
			_menu_sub.text = "AI 도 나와 같은 규칙(점수 %d점, 스킬 2개)으로 만들어져요" % CharacterBuild.POINTS
			_add_difficulty_row()
			_add_arena_row()
			_add_button("랜덤 상대", "vs_random", true)
			_add_button("정해진 상대 고르기", "presets")
			_add_button("거울 (내 캐릭터와 똑같은 상대)", "vs_mirror")
			_add_button("뒤로", "back")
		"presets":
			_menu_title.text = "정해진 상대"
			_menu_sub.text = "누구와 싸울까요?"
			for n in CharacterBuild.PRESET_ORDER:
				var b := CharacterBuild.preset(n)
				_add_button("%s   ·   %s" % [n, b.summary()], "vs_preset:" + n, false, 760)
			_add_button("뒤로", "back")
	if kind in ["start", "pause", "win", "lose", "tutorial_done"] and not OS.has_feature("web"):
		_add_button("게임 종료", "quit")
	_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	if kind == "pause":
		Audio.duck(true)


const DIFFICULTY_INFO := {
	"easy": "쉬움 · 느리게 휘두르고 잘 안 막아요. 처음 연습할 때",
	"normal": "보통 · 막고, 피하고, 버릇을 읽어요",
	"hard": "어려움 · 빨리 읽고 잘 막고, 속임수도 자주 써요",
}


## 상대 고르기 화면: 경기장 고르기 (고른 것이 밝게)
func _add_arena_row() -> void:
	var items := []
	for t in Arena.THEME_ORDER:
		items.append([Arena.theme_name(t), "arena_" + t, t])
	items.append(["랜덤", "arena_random", "random"])
	_choice_row("경기장", items, Game.get_arena_choice(), 128)


## [글자, 고르면 보낼 것, 값] 버튼 줄. now 와 값이 같은 버튼이 밝다.
func _choice_row(title: String, items: Array, now: String, width: int) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var head := Label.new()
	head.text = title
	head.add_theme_font_size_override("font_size", 17)
	head.custom_minimum_size = Vector2(70, 0)
	row.add_child(head)
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.custom_minimum_size = Vector2(width, 40)
		b.add_theme_font_size_override("font_size", 17)
		b.toggle_mode = true
		b.button_pressed = it[2] == now
		if it[2] == now:
			for k in ["font_color", "font_pressed_color", "font_hover_pressed_color"]:
				b.add_theme_color_override(k, Color(1.0, 0.85, 0.4))
		var choice: String = it[1]
		b.pressed.connect(func(): menu_choice.emit(choice))
		b.set_meta("sfx", "ui_click")
		row.add_child(b)
	_menu_buttons.add_child(row)


## 상대 고르기 화면 맨 위: 쉬움 / 보통 / 어려움 (고른 것이 밝게)
func _add_difficulty_row() -> void:
	var now := Game.ai_difficulty()
	var items := []
	for d in ["easy", "normal", "hard"]:
		items.append([Duelist.DIFFICULTY_NAMES[d], "diff_" + d, d])
	_choice_row("난이도", items, now, 88)
	var info := Label.new()
	info.text = DIFFICULTY_INFO[now]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	_menu_buttons.add_child(info)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	_menu_buttons.add_child(gap)


# ---------------- 결과 화면, 전적 ----------------

## 이번 판 결과 (Game 이 대결이 끝날 때 채운다): {"stats", "time", "record"}
var result := {}


## 결과 화면 가운데: 이번 판 숫자들 + 이 무기 전적 한 줄
func _add_result_panel(won: bool) -> void:
	if result.is_empty():
		return
	var st: Dictionary = result.stats
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	var rows := [
		["걸린 시간", Records.clock(float(result.time))], ["준 피해", str(st.dealt)],
		["받은 피해", str(st.taken)], ["최고 연속기", "%d연속" % st.combo],
		["완벽 막기", "%d번" % st.perfect], ["피하기", "%d번" % st.dodged],
	]
	for r in rows:
		var k := Label.new()
		k.text = r[0]
		k.add_theme_font_size_override("font_size", 16)
		k.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		k.custom_minimum_size = Vector2(110, 0)
		grid.add_child(k)
		var v := Label.new()
		v.text = r[1]
		v.add_theme_font_size_override("font_size", 20)
		v.custom_minimum_size = Vector2(90, 0)
		grid.add_child(v)
	var center := CenterContainer.new()
	center.add_child(grid)
	_menu_buttons.add_child(center)
	var rec: Dictionary = result.get("record", {})
	if not rec.is_empty():
		var parts := ["%s 전적  %s" % [Weapons.display_name(_player.weapon) if _player else "", Records.line(rec.weapon)]]
		if won and int(rec.streak) >= 2:
			parts.append("%d연승!" % rec.streak)
		if won and rec.new_fastest:
			parts.append("가장 빨리 이겼어요! %s" % Records.clock(float(rec.fastest)))
		var l := Label.new()
		l.text = "   ·   ".join(parts)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45) if won else Color(1, 1, 1, 0.85))
		_menu_buttons.add_child(l)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	_menu_buttons.add_child(gap)


func _add_note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	_menu_buttons.add_child(l)
	_menu_buttons.move_child(l, _menu_buttons.get_child_count() - 1)


## 전적 화면: 무기별 승률 막대 + 난이도별 + 연승·가장 빠른 승리
func _add_records() -> void:
	var r := Records.load_all()
	var t := Records.totals(r)
	_menu_title.text = "전적"
	_menu_sub.text = "모두 %d승 %d패   ·   지금 %d연승   ·   가장 긴 연승 %d" % [t.x, t.y, r.streak, r.best_streak]
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	for w in Weapons.ORDER:
		_record_row(grid, Weapons.display_name(w), r.weapons.get(w, [0, 0]))
	for i in 3:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 10)
		grid.add_child(gap)
	for d in ["easy", "normal", "hard"]:
		var name: String = Duelist.DIFFICULTY_NAMES[d]
		var fast := float(r.fastest.get(d, 0.0))
		if fast > 0.0:
			name += "  (최단 %s)" % Records.clock(fast)
		_record_row(grid, name, r.diffs.get(d, [0, 0]))
	var center := CenterContainer.new()
	center.add_child(grid)
	_menu_buttons.add_child(center)


func _record_row(grid: GridContainer, title: String, rec: Array) -> void:
	var k := Label.new()
	k.text = title
	k.add_theme_font_size_override("font_size", 17)
	k.custom_minimum_size = Vector2(190, 0)
	grid.add_child(k)
	var games := int(rec[0]) + int(rec[1])
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.step = 0.0
	bar.value = float(rec[0]) / games if games > 0 else 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(220, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.1)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.8, 0.4)
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	grid.add_child(bar)
	var v := Label.new()
	v.text = Records.line(rec)
	v.add_theme_font_size_override("font_size", 17)
	v.add_theme_color_override("font_color", Color(1, 1, 1, 0.9 if games > 0 else 0.45))
	v.custom_minimum_size = Vector2(150, 0)
	grid.add_child(v)


# ---------------- 끝내기 연출 ----------------

var _bars: Array[ColorRect] = []


## 결정타 연출: 위아래 검은 띠가 들어오고, 싸울 때 쓰던 막대와 조준점은 숨긴다
func cinematic(on: bool) -> void:
	var view := get_viewport().get_visible_rect().size
	if on and _bars.is_empty():
		for i in 2:
			var b := ColorRect.new()
			b.color = Color(0, 0, 0)
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.position = Vector2(0, 0.0 if i == 0 else view.y)
			b.size = Vector2(view.x, 0)
			_root.add_child(b)
			_root.move_child(b, _big_label.get_index())
			_bars.append(b)
	for c in _root.get_children():
		if c == _big_label or c == _overlay or c in _bars or c == _vignette or c == _flash_rect:
			continue
		if c is CanvasItem:
			c.visible = not on
	var h := view.y * 0.1 if on else 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.set_speed_scale(1.0 / maxf(Engine.time_scale, 0.05))   # 느린 화면에서도 제 빠르기로
	for i in _bars.size():
		tw.tween_property(_bars[i], "size:y", h, 0.35)
		if i == 1:
			tw.tween_property(_bars[i], "position:y", view.y - h, 0.35)


var _flash_rect: ColorRect


## 화면이 번쩍 (결정타)
func flash(color: Color, seconds: float) -> void:
	if _flash_rect == null:
		_flash_rect = ColorRect.new()
		_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(_flash_rect)
		_root.move_child(_flash_rect, _overlay.get_index())
	_flash_rect.color = color
	_flash_rect.modulate.a = 1.0
	var tw := create_tween()
	tw.set_speed_scale(1.0 / maxf(Engine.time_scale, 0.05))
	tw.tween_property(_flash_rect, "modulate:a", 0.0, seconds)


## 잠깐 화면을 검게 가린다 (그 사이 효과를 미리 그려 둠).
func cover(seconds: float) -> void:
	var rect := ColorRect.new()
	rect.color = Color(0.03, 0.04, 0.06)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)
	var tw := rect.create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(rect, "modulate:a", 0.0, 0.2)
	tw.tween_callback(rect.queue_free)


## 메뉴에서 '뒤로'
func go_back() -> void:
	show_menu("opponent" if _menu_kind == "presets" else menu_return)


## 캐릭터 만들기 화면을 연다
func open_build_editor(b: CharacterBuild) -> void:
	_overlay.visible = false
	_menu_kind = "build"
	_editor = BUILD_EDITOR.new()
	_editor.setup(b)
	_editor.finished.connect(_on_editor_finished)
	_root.add_child(_editor)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


## 설정 화면을 연다 (시작 화면, 일시정지 메뉴에서)
func open_settings() -> void:
	_overlay.visible = false
	_menu_kind = "settings"
	_settings = SETTINGS_MENU.new()
	_settings.closed.connect(_on_settings_closed)
	_root.add_child(_settings)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func _on_settings_closed() -> void:
	_settings.queue_free()
	_settings = null
	refresh_keys()
	show_menu(menu_return)


## 튜토리얼 안내판처럼 화면에 붙는 것 (메뉴보다 아래에 깔린다)
func add_panel(c: Control) -> void:
	_root.add_child(c)
	_root.move_child(c, _overlay.get_index())


## 키를 바꾼 뒤 조작법과 스킬 칸의 키 이름을 새로 쓴다
func refresh_keys() -> void:
	get_tree().call_group("key_labels", "refresh_keys")
	_help.text = GameSettings.fill(HELP_TEXT)
	if _help2:
		_help2.text = GameSettings.fill(HELP2_TEXT)
		_help2.position = Vector2(0, _help.get_minimum_size().y + 6)
	if _player:
		set_player_slots()


func _on_editor_finished(saved: bool) -> void:
	_editor.queue_free()
	_editor = null
	_overlay.visible = true
	menu_choice.emit("build_saved" if saved else "build_cancel")


func hide_menu() -> void:
	_overlay.visible = false
	_menu_kind = ""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().paused = false
	Audio.duck(false)


func set_mode(m: String) -> void:
	_mode = m
	_enemy_box.visible = m == "duel"
	_enemy_stamina.visible = m == "duel"
	_hp_box.visible = m in ["duel", "tutorial"]
	_stats.visible = m == "practice"
	_help.visible = m != "tutorial"   # 튜토리얼은 단계마다 필요한 조작만 보여 준다


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if _menu_kind == "build" and _editor:
			_on_editor_finished(false)
		elif _menu_kind == "settings" and _settings:
			_settings.close_menu()
		elif _menu_kind in ["opponent", "presets"]:
			go_back()
		elif _menu_kind == "pause":
			hide_menu()
		elif _menu_kind == "":
			show_menu("pause")
	elif event is InputEventMouseButton and event.pressed and not _overlay.visible \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _overlay and not _overlay.visible:
		show_menu("pause")


## 필살기 게이지
func set_gauge(value: float, max_value: float) -> void:
	_gauge_bar.max_value = max_value
	_gauge_bar.value = value
	_gauge_ready = value >= max_value
	if _player:
		var sp: Dictionary = Weapons.get_weapon(_player.weapon).special
		_gauge_label.text = ("V  %s  준비!" if _gauge_ready else "필살기  %s") % sp.name


func set_ammo(value: int, max_value: int) -> void:
	_ammo_label.visible = max_value > 0
	_ammo_label.text = "수리검 %s" % ("●".repeat(value) + "○".repeat(maxi(max_value - value, 0)))
	_ammo_label.modulate = Color(1, 1, 1) if value > 0 else Color(1.0, 0.5, 0.4)


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


func set_enemy_stamina(value: float, max_value: float) -> void:
	_enemy_stamina.max_value = max_value
	_enemy_stamina.value = value


var _enemy_title := "결투사"


## 상대 이름과 스킬을 위에 보여준다
func set_enemy(b: CharacterBuild) -> void:
	_enemy_title = b.name
	var sk := []
	for s in b.skills:
		sk.append(CharacterBuild.SKILLS[s].name)
	_enemy_name.text = b.name + "   ·   " + Duelist.DIFFICULTY_NAMES.get(Game.ai_difficulty(), "") + "   ·   " + Weapons.display_name(b.weapon) + ("   ·   " + ", ".join(sk) if not sk.is_empty() else "")
	set_enemy_hp(b.max_hp(), b.max_hp())
	_enemy_bar.value = b.max_hp()
	set_enemy_stamina(b.max_stamina(), b.max_stamina())


## 대결 상대: 방향 표시에 상대 공격/막기를 보여 준다
func set_opponent(d: Duelist) -> void:
	_dir_ind.opponent = d
	_enemy_gauge.value = 0
	d.gauge_changed.connect(func(v, m):
		_enemy_gauge.max_value = m
		_enemy_gauge.value = v)


## 내 캐릭터: 스킬 칸을 채운다
func set_player(p: Player) -> void:
	_player = p
	_dir_ind.player = p
	_gauge_bar.value = p.gauge
	set_gauge(p.gauge, Weapons.GAUGE_MAX)
	p.gauge_changed.connect(set_gauge)
	p.ammo_changed.connect(set_ammo)
	set_ammo(p.ammo, p.ammo_max)
	set_player_slots()


## 스킬 칸 (이름과 키)
func set_player_slots() -> void:
	var p := _player
	for i in _slots.size():
		var slot: Dictionary = _slots[i]
		if i >= p.build.skills.size():
			slot.panel.visible = false
			continue
		var s: String = p.build.skills[i]
		var d: Dictionary = CharacterBuild.SKILLS[s]
		slot.skill = s
		slot.panel.visible = true
		slot.name.text = d.name
		slot.key.text = GameSettings.key_label("skill%d" % (i + 1)) if d.active else "자동"


func _make_slot(i: int) -> Dictionary:
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(8)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.size = Vector2(104, 74)
	panel.position = Vector2(-248 + i * 116, -100)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	_root.add_child(panel)
	# 쿨타임: 아래에서부터 어둡게 덮였다가 줄어든다
	var fill := ColorRect.new()
	fill.color = Color(0, 0, 0, 0.55)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.position = Vector2(2, 2)
	fill.size = Vector2(100, 0)
	panel.add_child(fill)
	var key := Label.new()
	key.position = Vector2(8, 4)
	key.add_theme_font_size_override("font_size", 15)
	key.modulate = Color(1.0, 0.8, 0.4)
	panel.add_child(key)
	var nm := Label.new()
	nm.position = Vector2(0, 26)
	nm.size = Vector2(104, 24)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 18)
	panel.add_child(nm)
	var t := Label.new()
	t.position = Vector2(0, 48)
	t.size = Vector2(104, 20)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 14)
	panel.add_child(t)
	return {"skill": "", "panel": panel, "fill": fill, "name": nm, "key": key, "time": t, "style": sb}


func _update_slots() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var kit := _player.skills
	for slot in _slots:
		if slot.skill == "" or not slot.panel.visible:
			continue
		var s: String = slot.skill
		var d: Dictionary = CharacterBuild.SKILLS[s]
		var ratio := 0.0
		var text := ""
		var ok := true
		if d.active:
			ratio = kit.cooldown_ratio(s)
			if kit.cooldown_left(s) > 0.0:
				text = "%.0f초" % ceilf(kit.cooldown_left(s))
				ok = false
			elif _player.stamina < float(d.stamina):
				text = "기력 부족"
				ok = false
		elif s == "double_jump" and not kit.double_jump_left():
			ok = false
		slot.fill.size.y = 70.0 * ratio
		slot.fill.position.y = 2.0 + 70.0 * (1.0 - ratio)
		slot.time.text = text
		slot.panel.modulate.a = 1.0 if ok else 0.7
		(slot.style as StyleBoxFlat).border_color = Color(1.0, 0.8, 0.4, 0.8) if ok and d.active else Color(1, 1, 1, 0.25)
	_haste_label.text = "질풍  %.1f초" % kit.haste_left() if kit.haste_active() else ""


func on_player_damaged(_amount: int) -> void:
	_damage_flash = 1.0


func set_stats(hits: int, knockdowns: int) -> void:
	_stats.text = "맞힌 횟수  %d\n쓰러뜨린 허수아비  %d" % [hits, knockdowns]


func set_counter_window(open: bool) -> void:
	_counter = 1.0 if open else 0.0


func pulse_crosshair() -> void:
	_pulse = 1.0


func show_event(text: String, color: Color) -> void:
	_event_label.text = text
	_event_label.modulate = color
	_event_label.scale = Vector2.ONE
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(_event_label, "modulate:a", 0.0, 0.35)


func show_big(text: String, color: Color, hold := 0.35) -> void:
	_big_label.text = text
	_big_label.modulate = color
	_big_label.scale = Vector2(1.4, 1.4)
	var tw := create_tween()
	tw.tween_property(_big_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(hold)
	tw.tween_property(_big_label, "modulate:a", 0.0, 0.2)


func _process(delta: float) -> void:
	_update_slots()
	_fps.visible = GameSettings.show_fps
	if _fps.visible:
		_fps.text = "FPS %d" % Engine.get_frames_per_second()
	# 필살기가 준비되면 게이지가 깜빡인다
	var glow := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 8.0) if _gauge_ready else 0.0
	_gauge_bar.modulate = Color(1, 1, 1).lerp(Color(1.6, 1.4, 0.8), glow)
	_gauge_label.modulate = Color(1.0, 0.85, 0.4) if _gauge_ready else Color(1, 1, 1, 0.75)
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
	var target_a := 0.0
	if _counter > 0.0:
		target_a = 0.75 + sin(Time.get_ticks_msec() / 1000.0 * 18.0) * 0.25
	_counter_vignette.modulate.a = move_toward(_counter_vignette.modulate.a, target_a, delta * 6.0)


# ---------------- 경기장 소식, 높이 조작법 ----------------

var _arena_status: Label
var _help2: Label


## 위 가운데 (상대 체력 아래): "다음 붕괴 12초"
func set_arena_status(text: String) -> void:
	if _arena_status == null:
		_arena_status = Label.new()
		_arena_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_arena_status.position = Vector2(-150, 58)
		_arena_status.size = Vector2(300, 24)
		_arena_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_arena_status.add_theme_font_size_override("font_size", 17)
		_arena_status.add_theme_constant_override("outline_size", 6)
		_root.add_child(_arena_status)
	_arena_status.visible = _mode == "duel"
	_arena_status.text = text
	var urgent := text.begins_with("붕괴")
	_arena_status.modulate = Color(1.0, 0.45, 0.3) if urgent else Color(1, 1, 1, 0.85)


## 조작법 아래에 높이 관련 조작을 덧붙인다
func add_vertical_help() -> void:
	if _help2 != null:
		return
	_help2 = Label.new()
	_help2.text = GameSettings.fill(HELP2_TEXT)
	_help2.add_theme_font_size_override("font_size", 15)
	_help2.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7, 0.92))
	_help2.add_theme_constant_override("outline_size", 5)
	_help.add_child(_help2)
	_help2.position = Vector2(0, _help.get_minimum_size().y + 6)
