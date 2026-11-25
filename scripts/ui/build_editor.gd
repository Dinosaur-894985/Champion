extends ColorRect
## 캐릭터 만들기 화면: 점수를 능력치 5개에 나눠 주고, 특수 스킬을 2개까지 고른다.
## 저장하면 user://build.cfg 에 남아서 다음에 켜도 그대로다.

signal finished(saved: bool)

const C_ON := Color(1.0, 0.78, 0.35)
const C_OFF := Color(1, 1, 1, 0.14)
const C_TEXT_DIM := Color(1, 1, 1, 0.65)

var build: CharacterBuild
var _points: Label
var _rows := {}           # 능력치 → {"pips": [ColorRect], "value": Label, "minus": Button, "plus": Button}
var _skill_buttons := {}  # 스킬 → Button
var _desc: Label
var _preview: Label


func setup(b: CharacterBuild) -> void:
	build = b.duplicate_build()


func _ready() -> void:
	color = Color(0.03, 0.04, 0.06, 0.92)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(860, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := _label("캐릭터 만들기", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _label("점수 %d점을 능력치와 특수 스킬에 나눠 쓰세요. 하나를 올리면 다른 게 약해져요." % CharacterBuild.POINTS, 17)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = C_TEXT_DIM
	box.add_child(sub)
	_points = _label("", 26)
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_points)

	# ---- 능력치 ----
	for k in CharacterBuild.STAT_ORDER:
		box.add_child(_stat_row(k))

	# ---- 특수 스킬 ----
	var sk_title := _label("특수 스킬  (%d개까지, 강한 스킬은 점수를 더 먹어요)" % CharacterBuild.MAX_SKILLS, 20)
	sk_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_spacer(4))
	box.add_child(sk_title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for s in CharacterBuild.SKILL_ORDER:
		var d: Dictionary = CharacterBuild.SKILLS[s]
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(280, 52)
		b.add_theme_font_size_override("font_size", 18)
		var kind := "자동" if not d.active else "쿨타임 %d초" % int(d.cooldown)
		b.text = "%s   %d점 · %s" % [d.name, d.cost, kind]
		b.pressed.connect(_on_skill.bind(s))
		b.mouse_entered.connect(func(): _desc.text = "%s: %s" % [d.name, d.desc])
		grid.add_child(b)
		_skill_buttons[s] = b
	var gc := CenterContainer.new()
	gc.add_child(grid)
	box.add_child(gc)
	_desc = _label("스킬 위에 마우스를 올리면 설명이 나와요.", 16)
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc.modulate = C_TEXT_DIM
	_desc.custom_minimum_size = Vector2(0, 24)
	box.add_child(_desc)

	_preview = _label("", 17)
	_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview.modulate = Color(0.75, 0.9, 1.0)
	box.add_child(_preview)

	# ---- 버튼 ----
	box.add_child(_spacer(4))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	buttons.add_child(_button("저장하고 시작", _on_save, true))
	buttons.add_child(_button("랜덤", _on_random))
	buttons.add_child(_button("처음 값으로", _on_reset))
	buttons.add_child(_button("취소", func(): finished.emit(false)))
	box.add_child(buttons)
	_refresh()


func _stat_row(k: String) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var name_l := _label(CharacterBuild.STATS[k][0], 22)
	name_l.custom_minimum_size = Vector2(80, 0)
	row.add_child(name_l)
	var desc := _label(CharacterBuild.STATS[k][1], 15)
	desc.modulate = C_TEXT_DIM
	desc.custom_minimum_size = Vector2(250, 0)
	row.add_child(desc)
	var minus := _small_button("−", _change.bind(k, -1))
	row.add_child(minus)
	var pips := []
	var pip_box := HBoxContainer.new()
	pip_box.add_theme_constant_override("separation", 4)
	for i in CharacterBuild.STAT_MAX:
		var p := ColorRect.new()
		p.custom_minimum_size = Vector2(24, 18)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip_box.add_child(p)
		pips.append(p)
	var pc := CenterContainer.new()
	pc.add_child(pip_box)
	row.add_child(pc)
	var plus := _small_button("+", _change.bind(k, 1))
	row.add_child(plus)
	var value := _label("", 22)
	value.custom_minimum_size = Vector2(36, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	_rows[k] = {"pips": pips, "value": value, "minus": minus, "plus": plus}
	return row


func _change(k: String, amount: int) -> void:
	if amount > 0 and build.can_raise(k):
		build.stats[k] = int(build.stats[k]) + 1
	elif amount < 0 and build.can_lower(k):
		build.stats[k] = int(build.stats[k]) - 1
	_refresh()


func _on_skill(s: String) -> void:
	if not build.toggle_skill(s):
		_desc.text = "스킬은 %d개까지예요. 하나를 먼저 빼세요." % CharacterBuild.MAX_SKILLS
	_refresh()


func _on_random() -> void:
	build = CharacterBuild.random_build()
	build.name = "나"
	_refresh()


func _on_reset() -> void:
	build = CharacterBuild.new()
	_refresh()


func _on_save() -> void:
	if not build.is_valid():
		return
	build.save()
	finished.emit(true)


func _refresh() -> void:
	var left := build.remaining()
	_points.text = "남은 점수  %d" % left
	_points.modulate = C_ON if left > 0 else Color(0.7, 0.9, 0.7)
	for k in CharacterBuild.STAT_ORDER:
		var r: Dictionary = _rows[k]
		var v := int(build.stats[k])
		for i in r.pips.size():
			(r.pips[i] as ColorRect).color = C_ON if i < v else C_OFF
		r.value.text = str(v)
		r.minus.disabled = not build.can_lower(k)
		r.plus.disabled = not build.can_raise(k)
	for s in _skill_buttons:
		var b: Button = _skill_buttons[s]
		b.set_pressed_no_signal(build.has(s))
		b.modulate = Color(1.0, 0.85, 0.5) if build.has(s) else Color(1, 1, 1)
	# 실제로 바뀌는 값 미리 보기
	var keys := []
	var slot_keys := ["E", "R"]
	for i in build.skills.size():
		var d: Dictionary = CharacterBuild.SKILLS[build.skills[i]]
		keys.append("%s %s" % [slot_keys[i] if d.active else "자동", d.name])
	_preview.text = "체력 %d   기력 %d   공격력 ×%.2f   이동 ×%.2f   공격 속도 ×%.2f   튕겨내기 여유 %.2f초\n%s" % [
		build.max_hp(), int(build.max_stamina()), build.damage_mult(), build.speed_mult(),
		1.0 / build.attack_time_mult(), build.parry_window(),
		"스킬:  " + "    ".join(keys) if not keys.is_empty() else "스킬 없음 (점수를 모두 능력치에)"]


# ---------------- 작은 도우미 ----------------

func _label(text: String, size_px: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(200 if primary else 140, 50)
	b.add_theme_font_size_override("font_size", 20 if primary else 17)
	b.pressed.connect(cb)
	return b


func _small_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(40, 36)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	return b
