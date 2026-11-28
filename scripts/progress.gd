class_name Progress
extends RefCounted
## 기록 파일 (user://progress.cfg): 튜토리얼을 마쳤나, 고른 AI 난이도.
## 칸을 더할 때는 [구역] 이름만 새로 정하면 된다. 다른 칸은 지키고 덧붙인다.

const PATH := "user://progress.cfg"


static func get_value(section: String, key: String, default: Variant = null) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return default
	return cfg.get_value(section, key, default)


static func set_value(section: String, key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(section, key, value)
	cfg.save(PATH)
