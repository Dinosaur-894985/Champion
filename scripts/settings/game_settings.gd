class_name GameSettings
extends RefCounted
## 게임 설정: 마우스 감도, 조작키, 화질. user://settings.cfg 에 저장되어 다음에 켜도 그대로다.
## (소리 크기도 같은 파일의 "volume" 칸에 scripts/audio/audio_director.gd 가 저장한다.)
## 장면을 다시 불러와도(다시 대결) 값이 남도록 전부 static 이다.
##
## - 조작키: ACTIONS 의 각 행동에 키/마우스 버튼을 하나 이상 묶는다. 한 키는 한 행동에만.
## - 화질: QUALITY 표 ("low"/"medium"/"high"). main.gd 가 하늘과 해를 만들 때 register_world 로 알려 준다.

const PATH := "user://settings.cfg"

## 바꿀 수 있는 행동: [이름, 화면에 보일 이름, 기본 키들]
## 기본 키는 "key:키번호" 또는 "mouse:버튼번호".
const ACTIONS := [
	["move_forward", "앞으로", ["key:%d" % KEY_W, "key:%d" % KEY_UP]],
	["move_back", "뒤로", ["key:%d" % KEY_S, "key:%d" % KEY_DOWN]],
	["move_left", "왼쪽", ["key:%d" % KEY_A, "key:%d" % KEY_LEFT]],
	["move_right", "오른쪽", ["key:%d" % KEY_D, "key:%d" % KEY_RIGHT]],
	["jump", "점프", ["key:%d" % KEY_SPACE]],
	["sprint", "달리기", ["key:%d" % KEY_SHIFT]],
	["crouch", "앉기 / 슬라이딩", ["key:%d" % KEY_C, "key:%d" % KEY_CTRL]],
	["attack", "공격", ["mouse:%d" % MOUSE_BUTTON_LEFT]],
	["block", "막기", ["mouse:%d" % MOUSE_BUTTON_RIGHT]],
	["heavy_attack", "내려찍기 (강공격)", ["key:%d" % KEY_Q]],
	["grab", "잡기", ["key:%d" % KEY_F]],
	["skill1", "스킬 1", ["key:%d" % KEY_E]],
	["skill2", "스킬 2", ["key:%d" % KEY_R]],
	["special", "무기 필살기", ["key:%d" % KEY_V]],
]
## 누르고 있어야 하는 행동은 마우스 휠에 묶을 수 없다 (휠은 '딸깍' 한 번뿐이라)
const HELD := ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "attack", "block"]

## 화질 단계. shadow: 해 그림자 (0 = 끔), soft: 그림자 테두리 부드럽게(0~5),
## msaa: 물체 테두리 계단 줄이기, scale: 3D 화면 해상도 (낮으면 빠름. 웹은 항상 1)
const QUALITY := {
	"low": {"name": "낮음", "desc": "그림자와 빛 번짐을 끄고 화면을 조금 거칠게 그려요. 느린 컴퓨터용",
		"shadow": 0, "soft": 0, "ssao": false, "glow": false, "msaa": Viewport.MSAA_DISABLED, "scale": 0.75},
	"medium": {"name": "보통", "desc": "그림자는 조금 거칠게, 구석 그늘은 꺼요",
		"shadow": 2048, "soft": 1, "ssao": false, "glow": true, "msaa": Viewport.MSAA_2X, "scale": 1.0},
	"high": {"name": "높음", "desc": "부드러운 그림자, 구석 그늘, 빛 번짐 모두 켜요 (기본)",
		"shadow": 4096, "soft": 3, "ssao": true, "glow": true, "msaa": Viewport.MSAA_2X, "scale": 1.0},
	"ultra": {"name": "최고", "desc": "테두리 계단을 더 매끄럽게 하고 그림자도 가장 고와요. 좋은 그래픽 카드용",
		"shadow": 4096, "soft": 4, "ssao": true, "glow": true, "msaa": Viewport.MSAA_4X, "scale": 1.0},
}
const QUALITY_ORDER := ["low", "medium", "high", "ultra"]

const SENS_MIN := 0.2
const SENS_MAX := 3.0
const FOV_MIN := 65.0
const FOV_MAX := 100.0
const FOV_DEFAULT := 78.0

## 마우스 감도 배율 (1 = 기본)
static var mouse_sens := 1.0
static var invert_y := false
## 시야 넓이 (도). 달리기 등에서 넓어지는 효과는 이 값 위에 더해진다.
static var fov := FOV_DEFAULT
static var quality := "high"
static var fullscreen := false
static var show_fps := false
## 휘두를 때 남는 빛 자취(검기). 끄면 자취 없이 칼만 보인다 (맞는 순간 멈춤은 그대로)
static var trails := true
## 행동 이름 -> ["key:87", "mouse:1", ...]. 비어 있으면 기본 키.
static var bindings := {}

static var _loaded := false
static var _env: Environment
static var _sun: DirectionalLight3D


## 처음 부를 때 저장된 설정을 읽는다
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	mouse_sens = clampf(float(cfg.get_value("controls", "mouse_sens", 1.0)), SENS_MIN, SENS_MAX)
	invert_y = bool(cfg.get_value("controls", "invert_y", false))
	fov = clampf(float(cfg.get_value("controls", "fov", FOV_DEFAULT)), FOV_MIN, FOV_MAX)
	var q := str(cfg.get_value("graphics", "quality", "high"))
	quality = q if QUALITY.has(q) else "high"
	fullscreen = bool(cfg.get_value("graphics", "fullscreen", false))
	show_fps = bool(cfg.get_value("graphics", "show_fps", false))
	trails = bool(cfg.get_value("graphics", "trails", true))
	bindings = {}
	if cfg.has_section("keys"):
		for a in cfg.get_section_keys("keys"):
			var list = cfg.get_value("keys", a, [])
			if _action_index(a) >= 0 and list is Array and not list.is_empty():
				var good := []
				for code in list:
					if _make_event(str(code)) != null:
						good.append(str(code))
				if not good.is_empty():
					bindings[a] = good


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)   # 소리 크기 등 다른 칸은 그대로 둔다
	cfg.set_value("controls", "mouse_sens", mouse_sens)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "fov", fov)
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("graphics", "show_fps", show_fps)
	cfg.set_value("graphics", "trails", trails)
	if cfg.has_section("keys"):
		cfg.erase_section("keys")
	for a in bindings:
		cfg.set_value("keys", a, bindings[a])
	cfg.save(PATH)


# ---------------- 조작키 ----------------

## 모든 행동을 InputMap 에 (다시) 등록한다
static func apply_inputs() -> void:
	ensure_loaded()
	for row in ACTIONS:
		var a: String = row[0]
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		InputMap.action_erase_events(a)
		for code in codes_for(a):
			var ev := _make_event(code)
			if ev:
				InputMap.action_add_event(a, ev)


## 이 행동에 지금 묶인 키들
static func codes_for(action: String) -> Array:
	ensure_loaded()
	if bindings.has(action):
		return bindings[action]
	var i := _action_index(action)
	if i < 0:
		return []
	var list: Array = ACTIONS[i][2].duplicate()
	# 웹에서는 Ctrl+W 가 탭을 닫아 버리므로 Ctrl 은 쓰지 않는다
	if OS.has_feature("web"):
		list.erase("key:%d" % KEY_CTRL)
	return list


## 키/버튼 입력을 저장용 글자로. 묶을 수 없는 입력이면 "".
static func code_from_event(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k: int = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
		if k == KEY_NONE or k == KEY_ESCAPE:
			return ""
		return "key:%d" % k
	if ev is InputEventMouseButton:
		return "mouse:%d" % ev.button_index
	return ""


## 묶을 수 없는 이유 (괜찮으면 "")
static func reject_reason(action: String, code: String) -> String:
	if code == "":
		return "그 키는 쓸 수 없어요"
	if code.begins_with("mouse:"):
		var b := int(code.substr(6))
		if b in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT] \
				and action in HELD:
			return "누르고 있어야 하는 행동은 마우스 휠에 둘 수 없어요"
	if OS.has_feature("web") and code in ["key:%d" % KEY_CTRL, "key:%d" % KEY_META]:
		return "웹에서는 Ctrl 을 쓰면 브라우저 탭이 닫힐 수 있어요"
	return ""


## action 을 code 하나로 바꾼다. 다른 행동이 이 키를 쓰고 있었으면 그 행동은
## 이 행동이 쓰던 키를 넘겨받는다 (서로 맞바꿈). 바뀐 다른 행동 이름을 돌려준다 ("" = 없음).
static func rebind(action: String, code: String) -> String:
	ensure_loaded()
	var old: Array = codes_for(action)
	var swapped := ""
	for row in ACTIONS:
		var other: String = row[0]
		if other == action:
			continue
		var list: Array = codes_for(other).duplicate()
		if not code in list:
			continue
		list.erase(code)
		if list.is_empty():
			# 그 행동에 다른 키가 없으면 내 예전 키를 준다
			for c in old:
				if c != code and reject_reason(other, c) == "":
					list.append(c)
					break
		bindings[other] = list
		swapped = other
	bindings[action] = [code]
	apply_inputs()
	save()
	return swapped


static func reset_keys() -> void:
	bindings = {}
	apply_inputs()
	save()


static func action_title(action: String) -> String:
	var i := _action_index(action)
	return ACTIONS[i][1] if i >= 0 else action


## 화면에 보일 키 이름. 예) "Q", "왼쪽 클릭", "Q / E"
static func key_label(action: String, all := false) -> String:
	var list := codes_for(action)
	if list.is_empty():
		return "(없음)"
	if not all:
		return code_label(list[0])
	var names := []
	for c in list:
		names.append(code_label(c))
	return " / ".join(names)


## 이동 네 방향을 한 번에. 기본이면 "W A S D"
static func move_label() -> String:
	return "%s %s %s %s" % [key_label("move_forward"), key_label("move_left"), key_label("move_back"), key_label("move_right")]


static func code_label(code: String) -> String:
	if code.begins_with("mouse:"):
		match int(code.substr(6)):
			MOUSE_BUTTON_LEFT: return "왼쪽 클릭"
			MOUSE_BUTTON_RIGHT: return "오른쪽 클릭"
			MOUSE_BUTTON_MIDDLE: return "휠 클릭"
			MOUSE_BUTTON_WHEEL_UP: return "휠 위로"
			MOUSE_BUTTON_WHEEL_DOWN: return "휠 아래로"
			MOUSE_BUTTON_WHEEL_LEFT: return "휠 왼쪽"
			MOUSE_BUTTON_WHEEL_RIGHT: return "휠 오른쪽"
			MOUSE_BUTTON_XBUTTON1: return "마우스 옆 버튼 1"
			MOUSE_BUTTON_XBUTTON2: return "마우스 옆 버튼 2"
		return "마우스 버튼 %s" % code.substr(6)
	var k := int(code.substr(4))
	match k:
		KEY_UP: return "↑"
		KEY_DOWN: return "↓"
		KEY_LEFT: return "←"
		KEY_RIGHT: return "→"
		KEY_CTRL: return "Ctrl"
		KEY_SHIFT: return "Shift"
		KEY_ALT: return "Alt"
	var s := OS.get_keycode_string(k)
	return s if s != "" else "키 %d" % k


## 글 속의 {행동이름} 을 지금 키 이름으로 바꾼다. {move} 는 이동 네 방향.
static func fill(text: String) -> String:
	var out := text.replace("{move}", move_label())
	for row in ACTIONS:
		out = out.replace("{%s}" % row[0], key_label(row[0]))
	return out


static func _action_index(action: String) -> int:
	for i in ACTIONS.size():
		if ACTIONS[i][0] == action:
			return i
	return -1


static func _make_event(code: String) -> InputEvent:
	if code.begins_with("key:"):
		var k := int(code.substr(4))
		if k <= 0:
			return null
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		return ev
	if code.begins_with("mouse:"):
		var b := int(code.substr(6))
		if b <= 0:
			return null
		var ev := InputEventMouseButton.new()
		ev.button_index = b
		return ev
	return null


# ---------------- 화질 ----------------

## main.gd 가 하늘(Environment)과 해를 만든 뒤 알려 준다
static func register_world(env: Environment, sun: DirectionalLight3D) -> void:
	_env = env
	_sun = sun
	apply_graphics()


static func is_compat() -> bool:
	return RenderingServer.get_rendering_device() == null


static func apply_graphics() -> void:
	ensure_loaded()
	var q: Dictionary = QUALITY[quality]
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var vp := tree.root
	vp.msaa_3d = q.msaa
	if not is_compat():
		# 웹(호환 렌더러)은 해상도 낮추기를 지원하지 않는다
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if q.scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = q.scale
	if q.shadow > 0:
		RenderingServer.directional_shadow_atlas_set_size(q.shadow, true)
		RenderingServer.directional_soft_shadow_filter_set_quality(q.soft)
	if is_instance_valid(_sun):
		_sun.shadow_enabled = q.shadow > 0
	if _env:
		_env.ssao_enabled = q.ssao
		_env.glow_enabled = q.glow


## 전체 화면. 웹에서는 버튼을 누른 순간에만 브라우저가 허락해서, 켤 때 저장값으로 바꾸지 않는다.
static func apply_window() -> void:
	ensure_loaded()
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


## 게임을 켤 때 한 번 (main.gd)
static func apply_startup() -> void:
	apply_inputs()
	if not OS.has_feature("web"):
		apply_window()
