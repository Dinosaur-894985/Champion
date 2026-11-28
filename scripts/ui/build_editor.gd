extends ColorRect
## 캐릭터 만들기 화면: 무기를 고르고, 점수를 능력치 5개에 나눠 주고, 특수 스킬을 2개까지 고른다.
## 오른쪽에는 내 결투사가 빙글 돌며 보인다. 색, 피부, 머리 모양, 그리고 부위마다 옷(머리, 몸통, 팔, 다리, 신발)을
## 무기와 따로 고를 수 있다 (점수를 먹지 않는다). 몸집은 힘/체력/민첩을 따라 바뀐다.
## 캐릭터는 3칸까지 저장한다 (맨 위 칸 버튼). 칸마다 이름을 붙이고, 저장하면 그 칸이 '지금 쓰는 캐릭터'가 된다.
## 저장하면 user://build.cfg 에 남아서 다음에 켜도 그대로다 (웹은 브라우저 저장소).

signal finished(saved: bool)

const C_ON := Color(1.0, 0.78, 0.35)
const C_OFF := Color(1, 1, 1, 0.14)
const C_TEXT_DIM := Color(1, 1, 1, 0.65)

var build: CharacterBuild
var _points: Label
var _rows := {}           # 능력치 → {"pips": [ColorRect], "value": Label, "minus": Button, "plus": Button}
var _skill_buttons := {}  # 스킬 → Button
var _weapon_buttons := {} # 무기 → Button
var _weapon_desc: Label
var _desc: Label
var _preview: Label
var _vp: SubViewport
var _turntable: Node3D
var _rig: BodyRig
var _rig_key := ""
var _look_buttons := {}   # "color"/"skin"/"hair" → [Button]
var _part_labels := {}    # 부위 → Label (지금 고른 모양 이름)
var _set_i := 0
var _slot := 0
var _drafts := {}          # 칸 → 고치던 캐릭터 (칸을 옮겨 다녀도 저장 전까지 남는다)
var _saved: Array = []     # 칸 → 저장된 캐릭터 또는 null
var _slot_buttons: Array[Button] = []
var _name_edit: LineEdit
var _delete_button: Button
var _delete_armed := false
var _roster_changed := false   # 칸을 지웠다 → 닫을 때 새로 불러와야 한다


## slot: 처음 열 칸 (-1 이면 지금 쓰는 칸)
func setup(b: CharacterBuild, slot := -1) -> void:
	_saved = CharacterBuild.load_all_slots()
	_slot = slot if slot >= 0 else CharacterBuild.active_slot()
	if _saved[_slot]:
		build = (_saved[_slot] as CharacterBuild).duplicate_build()
	elif slot < 0:
		build = b.duplicate_build()   # 아직 아무것도 저장 안 함: 지금 쓰는 기본 캐릭터
		build.name = CharacterBuild.default_name(_slot)
	else:
		build = _fresh(_slot)


func _fresh(slot: int) -> CharacterBuild:
	var b := CharacterBuild.new()
	b.name = CharacterBuild.default_name(slot)
	b.color = slot * 3 % CharacterBuild.COLORS.size()   # 새 칸은 색을 달리해 알아보기 쉽게
	return b


func _ready() -> void:
	color = Color(0.03, 0.04, 0.06, 0.92)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 24)
	center.add_child(split)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(860, 0)
	box.add_theme_constant_override("separation", 10)
	split.add_child(box)
	split.add_child(_make_preview())

	var title := _label("캐릭터 만들기", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(_slot_row())
	var sub := _label("점수 %d점을 능력치와 특수 스킬에 나눠 쓰세요. 하나를 올리면 다른 게 약해져요." % CharacterBuild.POINTS, 17)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = C_TEXT_DIM
	box.add_child(sub)
	_points = _label("", 26)
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_points)

	# ---- 무기 (점수를 먹지 않는다) ----
	var wrow := HBoxContainer.new()
	wrow.alignment = BoxContainer.ALIGNMENT_CENTER
	wrow.add_theme_constant_override("separation", 6)
	var wl := _label("무기", 22)
	wl.custom_minimum_size = Vector2(60, 0)
	wrow.add_child(wl)
	for w in Weapons.ORDER:
		var wb := Button.new()
		wb.toggle_mode = true
		wb.custom_minimum_size = Vector2(108, 48)
		wb.add_theme_font_size_override("font_size", 17)
		wb.text = Weapons.display_name(w)
		wb.pressed.connect(_on_weapon.bind(w))
		wrow.add_child(wb)
		_weapon_buttons[w] = wb
	box.add_child(wrow)
	_weapon_desc = _label("", 16)
	_weapon_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weapon_desc.modulate = Color(0.75, 0.9, 1.0)
	_weapon_desc.custom_minimum_size = Vector2(0, 44)
	box.add_child(_weapon_desc)

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
	_delete_button = _button("이 칸 지우기", _on_delete)
	buttons.add_child(_delete_button)
	buttons.add_child(_button("취소", func(): finished.emit(_roster_changed)))
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


func _on_weapon(w: String) -> void:
	build.weapon = w
	_refresh()


func _on_skill(s: String) -> void:
	if not build.toggle_skill(s):
		_desc.text = "스킬은 %d개까지예요. 하나를 먼저 빼세요." % CharacterBuild.MAX_SKILLS
	_refresh()


func _on_random() -> void:
	var nm := build.name
	build = CharacterBuild.random_build()
	build.name = nm
	_refresh()


func _on_reset() -> void:
	var nm := build.name
	build = CharacterBuild.new()
	build.name = nm
	_refresh()


func _on_save() -> void:
	if not build.is_valid():
		return
	build.save_to_slot(_slot)
	finished.emit(true)


# ---------------- 저장 칸 ----------------

## 맨 위: 칸 1 / 2 / 3 버튼
func _slot_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for i in CharacterBuild.SLOTS:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(250, 46)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_on_slot.bind(i))
		row.add_child(b)
		_slot_buttons.append(b)
	return row


func _on_slot(i: int) -> void:
	if i == _slot:
		_refresh()
		return
	_drafts[_slot] = build
	_slot = i
	if _drafts.has(i):
		build = _drafts[i]
	elif _saved[i]:
		build = (_saved[i] as CharacterBuild).duplicate_build()
	else:
		build = _fresh(i)
	_delete_armed = false
	_rig_key = ""
	_refresh()


func _on_name(text: String) -> void:
	build.name = text


## 두 번 눌러야 지운다 (실수 막기)
func _on_delete() -> void:
	if not _delete_armed:
		_delete_armed = true
		_refresh()
		return
	_delete_armed = false
	if CharacterBuild.delete_slot(_slot):
		_roster_changed = true
		_saved = CharacterBuild.load_all_slots()
		_drafts.erase(_slot)
		build = _fresh(_slot)
		_rig_key = ""
	_refresh()


func _saved_count() -> int:
	var n := 0
	for b in _saved:
		if b:
			n += 1
	return n


func _refresh_slots() -> void:
	var active := CharacterBuild.active_slot()
	for i in _slot_buttons.size():
		var b: Button = _slot_buttons[i]
		var nm: String
		if i == _slot:
			nm = build.name if build.name.strip_edges() != "" else CharacterBuild.default_name(i)
		elif _drafts.has(i):
			nm = (_drafts[i] as CharacterBuild).name
		elif _saved[i]:
			nm = (_saved[i] as CharacterBuild).name
		else:
			nm = "빈 칸"
		var tag := ""
		if _saved[i] and i == active:
			tag = "  ·  쓰는 중"
		elif _saved[i] == null and (i == _slot or _drafts.has(i)):
			tag = "  ·  저장 전"
		b.text = "%d   %s%s" % [i + 1, nm, tag]
		b.set_pressed_no_signal(i == _slot)
		b.modulate = Color(1.0, 0.85, 0.5) if i == _slot else (Color(1, 1, 1) if _saved[i] else Color(1, 1, 1, 0.6))
	if _name_edit and _name_edit.text != build.name:
		_name_edit.text = build.name
	if _delete_button:
		var can := _saved[_slot] != null and _saved_count() > 1
		_delete_button.disabled = not can
		_delete_button.text = "정말 지울까요?" if _delete_armed and can else "이 칸 지우기"
		_delete_button.modulate = Color(1.0, 0.55, 0.5) if _delete_armed and can else Color(1, 1, 1)


func _refresh() -> void:
	_refresh_slots()
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
	for w in _weapon_buttons:
		var wb: Button = _weapon_buttons[w]
		wb.set_pressed_no_signal(build.weapon == w)
		wb.modulate = Color(1.0, 0.85, 0.5) if build.weapon == w else Color(1, 1, 1)
	var wd := Weapons.get_weapon(build.weapon)
	_weapon_desc.text = "%s\n필살기 (%s)  %s: %s" % [wd.desc, GameSettings.key_label("special"), wd.special.name, wd.special.desc]
	for s in _skill_buttons:
		var b: Button = _skill_buttons[s]
		b.set_pressed_no_signal(build.has(s))
		b.modulate = Color(1.0, 0.85, 0.5) if build.has(s) else Color(1, 1, 1)
	# 실제로 바뀌는 값 미리 보기
	var keys := []
	var slot_keys := [GameSettings.key_label("skill1"), GameSettings.key_label("skill2")]
	for i in build.skills.size():
		var d: Dictionary = CharacterBuild.SKILLS[build.skills[i]]
		keys.append("%s %s" % [slot_keys[i] if d.active else "자동", d.name])
	_refresh_look()
	_preview.text = "체력 %d   기력 %d   공격력 ×%.2f   이동 ×%.2f   대시 기력 ×%.2f   공격 속도 ×%.2f   튕겨내기 여유 %.2f초\n%s" % [
		build.max_hp(), int(build.max_stamina()), build.damage_mult(), build.speed_mult(), build.dash_cost_mult(),
		1.0 / build.attack_time_mult(), build.parry_window(),
		"스킬:  " + "    ".join(keys) if not keys.is_empty() else "스킬 없음 (점수를 모두 능력치에)"]


# ---------------- 겉모습 미리보기 ----------------

func _make_preview() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(300, 0)
	col.add_theme_constant_override("separation", 8)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_row.add_child(_label("이름", 17))
	_name_edit = LineEdit.new()
	_name_edit.max_length = CharacterBuild.NAME_MAX
	_name_edit.placeholder_text = "이름을 지어 주세요"
	_name_edit.custom_minimum_size = Vector2(250, 38)
	_name_edit.add_theme_font_size_override("font_size", 18)
	_name_edit.text = build.name
	_name_edit.text_changed.connect(_on_name)
	_name_edit.text_changed.connect(func(_t): _refresh_slots())
	name_row.add_child(_name_edit)
	col.add_child(name_row)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(300, 330)
	col.add_child(svc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.82, 0.78)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.15
	_vp.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.45
	rim.light_color = Color(0.7, 0.85, 1.0)
	_vp.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 34
	cam.position = Vector3(0, 1.1, 5.0)
	_vp.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 0.92, 0))
	LowPoly.part(_vp_root(), LowPoly.cyl(0.62, 0.68, 0.08, 10), LowPoly.mat(Color(0.25, 0.27, 0.32), 0.7), Vector3(0, -0.04, 0))
	_turntable = Node3D.new()
	_turntable.rotation.y = PI + 0.5
	_vp_root().add_child(_turntable)

	col.add_child(_look_row("색", "color", CharacterBuild.COLORS.size(), func(i): return CharacterBuild.COLORS[i][1]))
	col.add_child(_look_row("피부", "skin", CharacterBuild.SKINS.size(), func(i): return CharacterBuild.SKINS[i]))
	col.add_child(_look_row("머리", "hair", CharacterBuild.HAIRS.size(), Callable()))
	col.add_child(_cycle_row("한 벌", "set"))
	for p in CharacterBuild.PART_ORDER:
		col.add_child(_cycle_row(CharacterBuild.PART_LABELS[p], p))
	var hint := _label("옷은 무기와 따로 골라요. 몸집은 힘·체력·민첩을 따라요", 14)
	hint.modulate = C_TEXT_DIM
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(300, 0)
	col.add_child(hint)
	return col


var _world: Node3D


func _vp_root() -> Node3D:
	if _world == null:
		_world = Node3D.new()
		_vp.add_child(_world)
	return _world


## 겉모습 고르기 한 줄. swatch 가 있으면 색 칸, 없으면 글자 버튼 (머리 모양)
func _look_row(title: String, key: String, count: int, swatch: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var l := _label(title, 17)
	l.custom_minimum_size = Vector2(44, 0)
	row.add_child(l)
	var list := []
	for i in count:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		if swatch.is_valid():
			b.custom_minimum_size = Vector2(28, 28)
			var c: Color = swatch.call(i)
			for st in ["normal", "hover", "pressed", "hover_pressed"]:
				var sb := StyleBoxFlat.new()
				sb.bg_color = c if st != "hover" else c.lightened(0.15)
				sb.set_corner_radius_all(4)
				if st in ["pressed", "hover_pressed"]:
					sb.set_border_width_all(3)
					sb.border_color = C_ON
				b.add_theme_stylebox_override(st, sb)
		else:
			b.text = CharacterBuild.HAIRS[i]
			b.custom_minimum_size = Vector2(60, 30)
			b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_on_look.bind(key, i))
		row.add_child(b)
		list.append(b)
	_look_buttons[key] = list
	return row


## 옷 고르기 한 줄: ◀ 이름 ▶. key 가 "set" 이면 모든 부위를 한 벌로 맞춘다
func _cycle_row(title: String, key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var l := _label(title, 16)
	l.custom_minimum_size = Vector2(52, 0)
	row.add_child(l)
	var prev := _small_button("◀", _on_part.bind(key, -1))
	prev.custom_minimum_size = Vector2(34, 28)
	prev.add_theme_font_size_override("font_size", 14)
	prev.focus_mode = Control.FOCUS_NONE
	row.add_child(prev)
	var name_l := _label("", 15)
	name_l.custom_minimum_size = Vector2(150, 0)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(name_l)
	var next := _small_button("▶", _on_part.bind(key, 1))
	next.custom_minimum_size = Vector2(34, 28)
	next.add_theme_font_size_override("font_size", 14)
	next.focus_mode = Control.FOCUS_NONE
	row.add_child(next)
	_part_labels[key] = name_l
	return row


func _on_part(key: String, step: int) -> void:
	var n := CharacterBuild.STYLE_ORDER.size()
	if key == "set":
		_set_i = posmod(_set_i + step, n)
		build.wear_set(CharacterBuild.STYLE_ORDER[_set_i])
	else:
		var i := CharacterBuild.STYLE_ORDER.find(build.part(key))
		build.parts[key] = CharacterBuild.STYLE_ORDER[posmod(i + step, n)]
	_refresh()


func _on_look(key: String, i: int) -> void:
	build.set(key, i)
	_refresh()


func _refresh_look() -> void:
	for key in _look_buttons:
		var cur := int(build.get(key))
		for i in _look_buttons[key].size():
			(_look_buttons[key][i] as Button).set_pressed_no_signal(i == cur)
	# 옷: 모든 부위가 같으면 그 한 벌 이름, 아니면 "섞어 입음"
	var first := build.part("head")
	var same := true
	for p in CharacterBuild.PART_ORDER:
		if build.part(p) != first:
			same = false
		if _part_labels.has(p):
			(_part_labels[p] as Label).text = build.part_name(p)
	if same:
		_set_i = CharacterBuild.STYLE_ORDER.find(first)
	if _part_labels.has("set"):
		(_part_labels["set"] as Label).text = CharacterBuild.SET_NAMES[_set_i] if same else "섞어 입음"
	# 겉모습을 바꾸는 값이 바뀌었을 때만 몸을 새로 만든다
	var key2 := "%s|%d|%d|%d|%d|%d|%d|%s" % [build.weapon, build.color, build.skin, build.hair,
			int(build.stats.str), int(build.stats.vit), int(build.stats.agi), str(build.parts)]
	if key2 == _rig_key or _turntable == null:
		return
	_rig_key = key2
	if _rig:
		_rig.queue_free()
	_rig = BodyRig.new()
	_rig.build = build.duplicate_build()
	_rig.weapon = build.weapon
	_turntable.add_child(_rig)
	_rig.set_pose(MoveSet.BODY_POSES.guard, 30.0)


func _process(delta: float) -> void:
	if _turntable and is_visible_in_tree():
		_turntable.rotation.y += delta * 0.6
		if _rig and is_instance_valid(_rig):
			_rig.animate(delta, Vector3.ZERO)


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
