class_name Audio
extends RefCounted
## 어디서든 소리를 낼 때 쓰는 입구. 예) Audio.play("parry"), Audio.music("arena")
## 실제 일은 자동 등록된 AudioDirector 노드(audio_director.gd)가 한다.
## (점검 스크립트처럼 자동 등록이 없는 환경에서는 처음 부를 때 알아서 만든다.)

const NODE_NAME := "AudioDirector"
const DIRECTOR := preload("res://scripts/audio/audio_director.gd")

static var _d: Node = null


static func director() -> Node:
	if is_instance_valid(_d):
		return _d
	var tree := Engine.get_main_loop() as SceneTree
	_d = tree.root.get_node_or_null(NODE_NAME)
	if _d == null:
		_d = DIRECTOR.new()
		_d.name = NODE_NAME
		tree.root.add_child.call_deferred(_d)
	return _d


## 효과음. at: Vector3/Node3D 면 그 자리에서, 없으면 귀 바로 앞에서.
static func play(sound: String, at: Variant = null, vol_db := 0.0, pitch := 1.0) -> void:
	director().play(sound, at, vol_db, pitch)


## 무기에 맞는 소리 이름. kind: swing / swing_heavy / clash / hit
static func weapon_sound(kind: String, weapon: String) -> String:
	var w := weapon if weapon in ["sword", "greatsword", "daggers", "spear"] else "sword"
	if kind == "swing_heavy":
		return "swing_%s_heavy" % w
	return "%s_%s" % [kind, w]


static func step(at: Variant = null, vol_db := 0.0) -> void:
	director().step(at, vol_db)


static func ui(sound: String) -> void:
	director().ui(sound)


static func loop_start(key: String, sound: String, follow: Node3D, vol_db := 0.0) -> void:
	director().loop_start(key, sound, follow, vol_db)


static func loop_stop(key: String) -> void:
	director().loop_stop(key)


## 배경음악: "menu", "arena", "" (끄기)
static func music(track: String, fade := 1.2) -> void:
	director().music(track, fade)


## 승리/패배 짧은 음악. then: 끝난 뒤 이어서 틀 곡
static func stinger(track: String, then := "") -> void:
	director().stinger(track, then)


static func duck(on: bool) -> void:
	director().duck(on)


static func get_volume(bus: String) -> float:
	return director().volumes[bus]


static func set_volume(bus: String, value: float) -> void:
	director().set_volume(bus, value)


static func save_settings() -> void:
	director().save_settings()
