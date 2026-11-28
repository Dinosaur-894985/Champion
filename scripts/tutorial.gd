class_name Tutorial
extends Node
## 튜토리얼: 단계마다 짧은 안내를 보여 주고, 직접 해내면 다음 단계로 넘어간다.
## 앞 단계는 허수아비, 뒤 단계(막기, 피하기, 필살기)는 천천히 공격하는 연습 상대와 한다.
## Enter: 이 단계 건너뛰기 · Esc: 메뉴(건너뛰기, 그만두기)
##
## 단계 표 STEPS 에 줄을 더하면 새 단계가 생긴다. 해낸 것 세기는 _count_* 함수들.

signal finished

const SAVE_PATH := Progress.PATH
const NEXT_DELAY := 1.1   # 해낸 뒤 다음 단계로 넘어가기까지 (칭찬을 읽을 시간)

## id, 제목, 안내(키 이름은 {행동} 자리표시), 몇 번 해야 하나, 연습 상대가 공격하나
const STEPS := [
	{"id": "move", "title": "둘러보기와 걷기", "goal": 6,
		"text": "마우스로 둘러보고 {move} 로 걸어 보세요."},
	{"id": "jump", "title": "점프", "goal": 2,
		"text": "{jump} 로 점프해요. 벽을 보고 {move_forward} + {jump} 를 누르면 벽을 타고 오를 수도 있어요."},
	{"id": "sprint", "title": "달리기", "goal": 2,
		"text": "{sprint} 를 누른 채 움직여 보세요. 누르고 있을수록 점점 빨라져요.\n달리면 기력(아래 노란 막대)이 줄어요."},
	{"id": "dodge", "title": "피하기", "goal": 3,
		"text": "{move_left} / {move_right} / {move_back} 를 빠르게 두 번 누르면 그쪽으로 휙 피해요.\n피하는 순간에는 공격에 맞지 않아요."},
	{"id": "combo", "title": "베기와 연속기", "goal": 2,
		"text": "허수아비 앞으로 가서 {attack} 을 리듬 있게 이어 누르세요.\n세 번 이어지면 연속기! 이어 누를 때 마우스를 위/아래로 움직이면 기술이 바뀌어요."},
	{"id": "aim", "title": "공격 방향", "goal": 2,
		"text": "마우스를 살짝 위로 올리며 {attack} = 내려베기\n살짝 아래로 내리며 {attack} = 찌르기\n상대는 같은 방향으로 막아야 하니, 방향을 섞으면 잘 안 막혀요."},
	{"id": "heavy", "title": "강공격", "goal": 2, "text": ""},   # 무기마다 다르다 (_heavy_text)
	{"id": "block", "title": "막기", "goal": 2, "partner": true,
		"text": "이제 연습 상대가 천천히 공격해요.\n상대 칼이 빛나면 {block} 을 꾹 누르세요. 그냥 막기만 해도 피해가 절반이에요."},
	{"id": "perfect", "title": "완벽 막기", "goal": 2, "partner": true,
		"text": "막는 방향까지 맞추면 완벽 막기: 피해 0, 상대는 휘청!\n{block} 을 누른 채 마우스를 공격 쪽(위 / 옆 / 아래)으로 살짝 움직여요."},
	{"id": "riposte", "title": "바로 반격", "goal": 2, "partner": true,
		"text": "완벽 막기 바로 뒤에 {attack} 을 누르면 준비 동작 없이 '바로 반격!'\n막고 → 곧바로 베기."},
	{"id": "evade", "title": "공격 피하기", "goal": 2, "partner": true,
		"text": "막는 대신 피해도 돼요. 칼이 빛나다 휘두르는 순간\n{move_left} 나 {move_right} 를 두 번! 아슬하게 피하면 반격 기회가 생겨요."},
	{"id": "special", "title": "필살기", "goal": 1, "partner": true,
		"text": "싸우는 동안 아래 필살기 게이지가 차요. 지금은 가득 채워 드렸어요.\n상대를 보고 {special} !"},
]

var game: Game
var player: Player
var hud: CanvasLayer
var partner: Duelist

var index := -1
var count := 0.0           # 이번 단계에서 해낸 만큼
var step: Dictionary = {}
var _wait := -1.0          # 해냈다: 이 시간이 지나면 다음 단계
var _seen := {}            # 이번 단계에서 본 것 (공격 방향 등)
var _note_t := 0.0         # 잠깐 띄운 말이 남은 시간
var _last_pos := Vector3.ZERO
var _was_floor := true

var _panel: PanelContainer
var _step_label: Label
var _title: Label
var _body: Label
var _live: Label
var _bar: ProgressBar


static func is_done() -> bool:
	return bool(Progress.get_value("tutorial", "done", false))


static func mark_done() -> void:
	Progress.set_value("tutorial", "done", true)


func setup(g: Game, p: Duelist) -> void:
	game = g
	player = g.player
	hud = g.hud
	partner = p


func _ready() -> void:
	add_to_group("key_labels")
	_build_panel()
	player.attack_started.connect(_on_attack_started)
	player.attack_received.connect(_on_attack_received)
	player.combat_event.connect(_on_combat_event)
	player.sm.changed.connect(_on_state_changed)
	go_to(0)


# ---------------- 단계 ----------------

func go_to(i: int) -> void:
	index = i
	count = 0.0
	_wait = -1.0
	_seen.clear()
	if index >= STEPS.size():
		_finish()
		return
	step = STEPS[index]
	_last_pos = player.global_position
	_was_floor = player.is_on_floor()
	# 새 단계는 기력을 가득 채우고 시작한다
	player.stamina = player.max_stamina
	player.stamina_changed.emit(player.stamina, player.max_stamina)
	var uses_partner: bool = step.get("partner", false)
	if uses_partner:
		_wake_partner()
	partner.tutor_attacks = uses_partner and step.id != "special"
	partner.tutor_gap = 1.3 if step.id in ["riposte", "evade"] else 1.6
	if step.id == "special":
		player.add_gauge(Weapons.GAUGE_MAX)
	_show_step()


func skip() -> void:
	if index < STEPS.size():
		go_to(index + 1)


func _progress(amount: float, tick := true) -> void:
	if _wait >= 0.0 or step.is_empty():
		return
	count = minf(count + amount, float(step.goal))
	_bar.value = count / float(step.goal)
	if count >= float(step.goal):
		_wait = NEXT_DELAY
		_title.text = "좋아요!"
		_title.modulate = Color(0.55, 1.0, 0.6)
		Audio.ui("ui_confirm")
	elif tick:
		Audio.ui("ui_tick")


func _finish() -> void:
	mark_done()
	partner.tutor_attacks = false
	_panel.visible = false
	finished.emit()


func _physics_process(delta: float) -> void:
	if step.is_empty() or index >= STEPS.size():
		return
	if _wait >= 0.0:
		_wait -= delta
		if _wait < 0.0:
			go_to(index + 1)
		return
	# 튜토리얼에선 쓰러지지 않는다: 체력이 줄면 다시 채운다
	if player.hp < player.max_hp * 0.5:
		player.hp = player.max_hp
		player.hp_changed.emit(player.hp, player.max_hp)
	if partner.hp < partner.max_hp * 0.5:
		partner.hp = partner.max_hp
		partner.hp_changed.emit(partner.hp, partner.max_hp)
	var pos := player.global_position
	match step.id:
		"move":
			var d := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
			if player.is_on_floor() and d < 1.0:
				_progress(d, false)   # 걸은 거리(m)
		"jump":
			var floor_now := player.is_on_floor()
			if _was_floor and not floor_now and player.velocity.y > 2.0:
				_progress(1.0)
			_was_floor = floor_now
		"sprint":
			var spd := Vector2(player.velocity.x, player.velocity.z).length()
			if player._sprinting and spd > Player.WALK_SPEED + 0.3:
				_progress(delta, false)   # 달린 시간(초)
	_last_pos = pos
	# 파란 한 줄: 방금 일에 대한 말(잠깐) → 아니면 지금 도움말
	_note_t -= delta
	if _note_t <= 0.0:
		var hint := ""
		if step.get("partner", false):
			hint = _partner_hint()
		elif step.id in ["combo", "aim", "heavy", "dodge"] and player.stamina < 20.0:
			hint = "기력(노란 막대)이 바닥! 잠깐 쉬면 다시 차요"
		_live.text = hint
		_live.visible = hint != ""


## 연습 상대가 무엇을 하려는지 알려 준다 (방향 맞추기 연습용)
func _partner_hint() -> String:
	if step.id == "special":
		return ""
	var d := partner.attack_dir()
	if d == "":
		return "상대를 바라보고 기다리세요"
	if step.id in ["block", "evade"]:
		return "칼이 빛난다 — 지금!"
	match d:
		AttackDir.HIGH:
			return "위에서 내려벤다 — 막으며 마우스를 위로 살짝"
		AttackDir.MID:
			return "찌른다 — 막으며 마우스를 아래로 살짝"
	return "옆에서 벤다 — 막으며 마우스를 옆으로 살짝"


## 방금 한 일에 대한 말을 잠깐 띄운다
func _note(text: String) -> void:
	_live.text = text
	_live.visible = true
	_note_t = 1.6


func _on_attack_started(kind: String) -> void:
	if step.is_empty():
		return
	match step.id:
		"combo":
			if player._combo_step >= 3:
				_progress(1.0)
		"aim":
			var d: String = player._mv(kind).get("dir", "") if kind != "special" else ""
			if d in [AttackDir.HIGH, AttackDir.MID] and not _seen.has(d):
				_seen[d] = true
				_note("내려베기 했어요" if d == AttackDir.HIGH else "찌르기 했어요")
				_progress(1.0)
		"heavy":
			if kind == "heavy":
				_progress(1.0)


func _on_attack_received(result: String) -> void:
	if step.is_empty():
		return
	match step.id:
		"block":
			if result in ["wrong_guard", "blocked", "parried"]:
				_progress(1.0)
		"perfect":
			if result in ["blocked", "parried"]:
				_progress(1.0)
			elif result == "wrong_guard":
				_note("방향이 달라서 반만 막혔어요. 공격 쪽으로 마우스를!")
		"evade":
			if result == "dodged":
				_progress(1.0)


func _on_combat_event(text: String, _color: Color) -> void:
	if not step.is_empty() and step.id == "riposte" and text == "바로 반격!":
		_progress(1.0)


func _on_state_changed(_from: String, to: String) -> void:
	if step.is_empty():
		return
	if step.id == "dodge" and to == "dash":
		_progress(1.0)
	elif step.id == "special" and to == "special":
		_progress(1.0)


## 연습 상대를 깨운다: 허수아비를 치우고, 상대가 다가온다
func _wake_partner() -> void:
	if partner.active:
		return
	for c in game.get_children():
		if c is TrainingDummy:
			var tw := c.create_tween()
			tw.tween_property(c, "scale", Vector3(0.01, 0.01, 0.01), 0.25)
			tw.tween_callback(c.queue_free)
	partner.active = true
	player.opponent = partner   # 막는 동안 상대 쪽으로 저절로 돌아본다
	hud.show_event("연습 상대 등장!", Color(1.0, 0.85, 0.45))


func _heavy_text() -> String:
	if Weapons.move(player.weapon, "heavy").has("projectile"):
		return "{heavy_attack} 로 수리검을 던져요 (떨어진 건 지나가며 주워요).\n점프해서 공중에서도 던질 수 있어요."
	return "{heavy_attack} 는 느리지만 묵직한 내려찍기예요.\n막고 있는 상대의 막기를 깨뜨려요. 허수아비에게 써 보세요."


# ---------------- 화면 ----------------

func _show_step() -> void:
	_step_label.text = "튜토리얼  %d / %d" % [index + 1, STEPS.size()]
	_title.text = step.title
	_title.modulate = Color(1, 1, 1)
	var text: String = _heavy_text() if step.id == "heavy" else step.text
	_body.text = GameSettings.fill(text)
	_live.text = ""
	_live.visible = false
	_note_t = 0.0
	_bar.value = 0.0
	_panel.modulate.a = 0.0
	var tw := _panel.create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25)


## 키를 바꾸면 안내 글의 키 이름도 새로 쓴다
func refresh_keys() -> void:
	if not step.is_empty():
		var text: String = _heavy_text() if step.id == "heavy" else step.text
		_body.text = GameSettings.fill(text)


func _build_panel() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_panel(root)
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.78)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(16)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.border_color = Color(1.0, 0.8, 0.4, 0.55)
	style.border_width_left = 4
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(640, 0)
	# 화면 위 가운데
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -320
	_panel.offset_right = 320
	_panel.offset_top = 16
	root.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	_step_label = _label(14, Color(1.0, 0.8, 0.4))
	box.add_child(_step_label)
	_title = _label(28, Color(1, 1, 1))
	box.add_child(_title)
	_body = _label(18, Color(1, 1, 1, 0.92))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(596, 0)
	box.add_child(_body)
	_live = _label(18, Color(0.55, 0.9, 1.0))
	box.add_child(_live)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.12)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.8, 0.4)
	fill.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", fill)
	box.add_child(_bar)
	var foot := _label(13, Color(1, 1, 1, 0.55))
	foot.text = "Enter  이 단계 건너뛰기   ·   Esc  메뉴 (튜토리얼 그만두기)"
	box.add_child(foot)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 4)
	return l


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER] and _wait < 0.0:
		skip()
		get_viewport().set_input_as_handled()
