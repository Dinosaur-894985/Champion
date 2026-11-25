extends Node
## 게임 소리 담당 (실제로 소리를 내는 부분). project.godot 에 "AudioDirector" 로 자동 등록된다.
## 다른 코드는 이 파일 대신 scripts/audio/audio.gd 의 Audio.play("이름") 처럼 부른다.
## 장면을 다시 불러와도(다시 대결) 사라지지 않아서 배경음악이 끊기지 않는다.
##
## - 효과음 목록은 scripts/audio/sound_bank.gd (tools/audio/make_sfx.py 가 만든다)
## - 같은 소리를 연달아 내면 여러 버전 중 하나를 고르고, 음 높이를 살짝 바꿔서 덜 기계적으로 들린다
## - 음량(전체/음악/효과음)은 user://settings.cfg 에 저장된다
## - 웹에서는 처음 소리를 낼 때 멈칫하지 않게 시작할 때 모든 소리를 미리 등록해 둔다

const SETTINGS_PATH := "user://settings.cfg"
const BUSES := ["Music", "SFX", "UI"]
const POOL_3D := 24
const POOL_2D := 16
## 같은 소리를 이 시간(초) 안에 또 내면 무시한다 (한 번에 두 번 겹쳐 들리는 것 방지)
const REPEAT_GUARD := 0.035
const MUSIC_DB := -2.0
## 효과음 전체를 조금 낮춰서 여러 소리가 겹쳐도 찢어지지 않게 한다
const SFX_DB := -3.0

## 0~1. 화면의 음량 조절 막대와 같다.
var volumes := {"Master": 0.85, "Music": 0.75, "SFX": 0.9}

## 점검용: 지금까지 낸 소리별 횟수
var counts := {}
var _p3: Array[AudioStreamPlayer3D] = []
var _p2: Array[AudioStreamPlayer] = []
var _i3 := 0
var _i2 := 0
var _last_variant := {}
var _last_time := {}
var _music: Array[AudioStreamPlayer] = []
var _music_i := 0
var _music_name := ""
var _music_tweens: Array[Tween] = [null, null]
var _duck := 0.0
var _stinger: AudioStreamPlayer
var _after_stinger := 0
var _loops := {}
var _pending_music := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	load_settings()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 7.0
		p.max_distance = 70.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 0.8
		add_child(p)
		_p3.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_p2.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	_stinger = AudioStreamPlayer.new()
	_stinger.bus = "Music"
	add_child(_stinger)
	_prepare_streams()
	get_tree().node_added.connect(_on_node_added)
	if _pending_music != "":
		music(_pending_music)


# ---------------- 효과음 ----------------

## 효과음을 낸다.
## at: Vector3 또는 Node3D 면 그 자리에서 (멀면 작게, 왼쪽이면 왼쪽에서), null 이면 내 귀에서 바로.
## vol_db: 기본 음량에서 더하거나 뺄 값. pitch: 음 높이 (1 = 그대로).
func play(sound: String, at: Variant = null, vol_db := 0.0, pitch := 1.0) -> void:
	var info: Dictionary = SoundBank.SFX.get(sound, {})
	if info.is_empty():
		push_warning("효과음 없음: " + sound)
		return
	if not is_inside_tree():
		return
	counts[sound] = int(counts.get(sound, 0)) + 1
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_time.get(sound, -1.0)) < REPEAT_GUARD:
		return
	_last_time[sound] = now
	var stream := _pick(sound, info.streams)
	var p: Node
	var pos: Variant = null
	if at is Node3D:
		pos = (at as Node3D).global_position
	elif at is Vector3:
		pos = at
	if pos != null and is_inside_tree() and get_viewport().get_camera_3d() != null:
		p = _next_3d()
		(p as AudioStreamPlayer3D).global_position = pos
	else:
		p = _next_2d()
	p.stream = stream
	p.volume_db = float(info.vol) + vol_db + SFX_DB
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.bus = info.bus
	p.play()


## 발소리 (걷는 속도에 맞춰 부른다)
func step(at: Variant = null, vol_db := 0.0) -> void:
	play("step", at, vol_db, randf_range(0.92, 1.08))


## 화면(메뉴) 소리
func ui(sound: String) -> void:
	play(sound)


## 계속 나는 소리 (짚라인 도르래 등). key 로 다시 부르면 멈춘다.
func loop_start(key: String, sound: String, follow: Node3D, vol_db := 0.0) -> void:
	loop_stop(key)
	var info: Dictionary = SoundBank.SFX.get(sound, {})
	if info.is_empty() or follow == null or not follow.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = info.streams[0]
	p.bus = info.bus
	p.unit_size = 7.0
	p.volume_db = float(info.vol) + vol_db + SFX_DB
	follow.add_child(p)
	p.play()
	_loops[key] = p


func loop_stop(key: String) -> void:
	var p = _loops.get(key)
	if p != null and is_instance_valid(p):
		p.queue_free()
	_loops.erase(key)


func _pick(sound: String, streams: Array) -> AudioStream:
	if streams.size() == 1:
		return streams[0]
	var last: int = _last_variant.get(sound, -1)
	var i := randi() % streams.size()
	if i == last:
		i = (i + 1) % streams.size()
	_last_variant[sound] = i
	return streams[i]


func _next_3d() -> AudioStreamPlayer3D:
	# 쉬고 있는 것을 먼저 쓰고, 다 바쁘면 가장 오래된 것을 끊고 쓴다
	for k in POOL_3D:
		var p := _p3[(_i3 + k) % POOL_3D]
		if not p.playing:
			_i3 = (_i3 + k + 1) % POOL_3D
			return p
	var q := _p3[_i3]
	_i3 = (_i3 + 1) % POOL_3D
	return q


func _next_2d() -> AudioStreamPlayer:
	for k in POOL_2D:
		var p := _p2[(_i2 + k) % POOL_2D]
		if not p.playing:
			_i2 = (_i2 + k + 1) % POOL_2D
			return p
	var q := _p2[_i2]
	_i2 = (_i2 + 1) % POOL_2D
	return q


# ---------------- 배경음악 ----------------

## 배경음악을 바꾼다 ("menu", "arena", "" = 끄기). 이미 그 곡이면 그대로 둔다.
func music(track: String, fade := 1.2, keep_stinger := false) -> void:
	if not is_inside_tree():
		_pending_music = track
		return
	if track != "" and not keep_stinger:
		_after_stinger += 1
		if _stinger.playing:
			_stinger.stop()
	# 웹에서는 AudioStreamPlayer.playing 이 믿을 만하지 않아서 직접 기억한 곡 이름으로 판단한다
	if track == _music_name:
		return
	_music_name = track
	_fade(_music_i, -80.0, fade, true)
	if track == "":
		return
	_music_i = 1 - _music_i
	var m := _music[_music_i]
	m.stream = SoundBank.MUSIC[track]
	m.volume_db = -40.0
	m.play()
	_fade(_music_i, _music_db(), fade, false)


## 짧은 음악(승리/패배). 배경음악은 잠깐 끄고, 끝나면 then 곡을 천천히 튼다.
func stinger(track: String, then := "") -> void:
	if not is_inside_tree():
		return
	music("", 0.4)
	_stinger.stream = SoundBank.MUSIC[track]
	_stinger.volume_db = 0.0
	_stinger.play()
	_after_stinger += 1
	if then == "":
		return
	var token := _after_stinger
	var wait := maxf(_stinger.stream.get_length() - 1.0, 1.0)
	get_tree().create_timer(wait, true, false, true).timeout.connect(func():
		# 그 사이에 다른 곡을 틀었으면(다시 대결 등) 그대로 둔다
		if token == _after_stinger and _music_name == "":
			music(then, 2.5, true))


## 일시정지 메뉴가 열리면 음악을 살짝 줄인다
func duck(on: bool) -> void:
	_duck = -7.0 if on else 0.0
	if _music_name != "":
		_fade(_music_i, _music_db(), 0.3, false)


func current_music() -> String:
	return _music_name


func _music_db() -> float:
	return MUSIC_DB + _duck


func _fade(i: int, to_db: float, time: float, stop_after: bool) -> void:
	if _music_tweens[i] and _music_tweens[i].is_valid():
		_music_tweens[i].kill()
	var m := _music[i]
	if m.stream == null:
		return
	var tw := create_tween()
	tw.tween_property(m, "volume_db", to_db, time).set_trans(Tween.TRANS_SINE)
	if stop_after:
		tw.tween_callback(func():
			m.stop()
			m.stream = null)
	_music_tweens[i] = tw


# ---------------- 음량 ----------------

func set_volume(bus: String, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	_apply_volume(bus)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for k in volumes:
		cfg.set_value("volume", k, volumes[k])
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for k in volumes:
			volumes[k] = clampf(float(cfg.get_value("volume", k, volumes[k])), 0.0, 1.0)
	for k in volumes:
		_apply_volume(k)


func _apply_volume(bus: String) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var v: float = volumes[bus]
	# 귀는 소리 크기를 로그로 느끼므로 막대 값을 제곱해서 dB 로 바꾼다 (가운데쯤이 '절반' 으로 들림)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v * v, 0.0001)))
	AudioServer.set_bus_mute(idx, v <= 0.001)


func _setup_buses() -> void:
	# 큰 소리가 한꺼번에 겹쳐도 찢어지는 소리가 나지 않게 마지막에 눌러 준다 (컴퓨터판. 웹은 브라우저가 처리)
	if AudioServer.get_bus_effect_count(0) == 0 and ClassDB.class_exists("AudioEffectHardLimiter"):
		var lim: AudioEffect = ClassDB.instantiate("AudioEffectHardLimiter")
		lim.set("ceiling_db", -0.5)
		AudioServer.add_bus_effect(0, lim)
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			# 화면 소리는 효과음 음량을 따른다
			AudioServer.set_bus_send(idx, "SFX" if b == "UI" else "Master")


# ---------------- 미리 준비 ----------------

## 반복 소리 설정 + 웹에서 첫 재생 때 멈칫하지 않게 모든 소리를 미리 등록
func _prepare_streams() -> void:
	for sound in SoundBank.SFX:
		var info: Dictionary = SoundBank.SFX[sound]
		if info.get("loop", false):
			for s in info.streams:
				var w := s as AudioStreamWAV
				if w:
					w.loop_mode = AudioStreamWAV.LOOP_FORWARD
					w.loop_begin = 0
					w.loop_end = w.data.size() / 2
	for track in SoundBank.MUSIC:
		var ogg := SoundBank.MUSIC[track] as AudioStreamOggVorbis
		if ogg:
			ogg.loop = track in ["menu", "arena"]
	if not OS.has_feature("web"):
		return
	for sound in SoundBank.SFX:
		for s in SoundBank.SFX[sound].streams:
			if not AudioServer.is_stream_registered_as_sample(s):
				AudioServer.register_stream_as_sample(s)
	for track in SoundBank.MUSIC:
		var s: AudioStream = SoundBank.MUSIC[track]
		if not AudioServer.is_stream_registered_as_sample(s):
			AudioServer.register_stream_as_sample(s)


# ---------------- 버튼 소리 자동 연결 ----------------

## 화면에 버튼이 생기면 자동으로 '딸깍' 소리를 붙인다 (메뉴, 캐릭터 만들기 화면 모두).
## 버튼에 meta "sfx" 를 붙이면 그 소리를 낸다 ("ui_confirm", "ui_back" 등).
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var b := node as BaseButton
		b.mouse_entered.connect(func():
			if not b.disabled:
				ui("ui_hover"))
		b.pressed.connect(func(): ui(str(b.get_meta("sfx", "ui_click"))))
	elif node is Slider:
		var s := node as Slider
		s.value_changed.connect(func(_v): ui("ui_tick"))
