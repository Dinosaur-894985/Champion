class_name CharacterBuild
extends RefCounted
## 캐릭터 빌드: 능력치 5개 + 특수 스킬 2개.
## 플레이어와 AI 가 똑같은 규칙을 쓴다. 숫자를 바꾸고 싶으면 이 파일의 표만 고치면 된다.
##
## 점수 규칙
##   총 POINTS 점을 능력치와 스킬에 나눠 쓴다. 능력치는 1~10.
##   스킬도 점수를 먹는다 (강한 스킬일수록 비싸다) → 강한 스킬을 고르면 능력치가 조금 깎인다.

const POINTS := 30
const STAT_MIN := 1
const STAT_MAX := 10
const MAX_SKILLS := 2
const SAVE_PATH := "user://build.cfg"

## 능력치: [이름, 짧은 설명]
const STATS := {
	"str": ["힘", "공격력, 막기 깨는 힘"],
	"vit": ["체력", "최대 체력, 덜 휘청임"],
	"agi": ["민첩", "이동 속도, 대시 거리"],
	"tec": ["기술", "공격 속도, 튕겨내기 타이밍 여유"],
	"end": ["지구력", "기력 최대치와 회복 속도"],
}
const STAT_ORDER := ["str", "vit", "agi", "tec", "end"]

## 특수 스킬
##   cost     : 능력치 점수를 얼마나 먹는지
##   active   : true 면 키(E / R)로 쓰는 스킬, false 면 늘 켜져 있는 스킬
##   cooldown : 다시 쓰기까지 (초)
##   stamina  : 쓸 때 드는 기력
const SKILLS := {
	"wall": {
		"name": "벽타기", "cost": 2, "active": false, "cooldown": 0.0, "stamina": 0.0,
		"desc": "벽을 보고 점프하면 타고 오르고, 벽 옆을 달리다 점프하면 벽을 달린다",
	},
	"double_jump": {
		"name": "이중 점프", "cost": 1, "active": false, "cooldown": 0.0, "stamina": 10.0,
		"desc": "공중에서 Space 를 한 번 더 누르면 한 번 더 뛴다",
	},
	"blink": {
		"name": "점멸", "cost": 3, "active": true, "cooldown": 6.0, "stamina": 18.0,
		"range": 6.5,
		"desc": "누르는 방향으로 순간이동. 이동하는 순간은 맞지 않는다",
	},
	"grapple": {
		"name": "갈고리", "cost": 2, "active": true, "cooldown": 7.0, "stamina": 12.0,
		"range": 24.0, "speed": 24.0,
		"desc": "조준한 곳(벽, 지붕, 상대)으로 줄을 걸고 날아간다",
	},
	"haste": {
		"name": "질풍", "cost": 1, "active": true, "cooldown": 12.0, "stamina": 0.0,
		"duration": 3.5, "speed_mult": 1.35, "attack_mult": 0.82,
		"desc": "잠깐 이동과 공격이 빨라지고 기력이 빨리 찬다",
	},
	"iron_guard": {
		"name": "철벽", "cost": 3, "active": true, "cooldown": 14.0, "stamina": 0.0,
		"duration": 1.3,
		"desc": "잠깐 어느 방향 공격이든 막는다. 기력이 줄지 않고 막기가 깨지지 않는다",
	},
}
const SKILL_ORDER := ["wall", "double_jump", "blink", "grapple", "haste", "iron_guard"]

## 미리 만들어 둔 캐릭터 (AI '지정' 모드, 랜덤의 참고)
const PRESETS := {
	"검객": {"stats": {"str": 5, "vit": 5, "agi": 5, "tec": 6, "end": 5}, "skills": ["wall", "haste"]},
	"탱커": {"stats": {"str": 8, "vit": 9, "agi": 2, "tec": 3, "end": 5}, "skills": ["iron_guard"]},
	"암살자": {"stats": {"str": 4, "vit": 3, "agi": 8, "tec": 7, "end": 3}, "skills": ["wall", "blink"]},
	"사냥꾼": {"stats": {"str": 6, "vit": 4, "agi": 6, "tec": 4, "end": 7}, "skills": ["grapple", "double_jump"]},
	"광전사": {"stats": {"str": 10, "vit": 6, "agi": 4, "tec": 3, "end": 3}, "skills": ["haste", "iron_guard"]},
}
const PRESET_ORDER := ["검객", "탱커", "암살자", "사냥꾼", "광전사"]

var name := "나"
var stats := {"str": 5, "vit": 5, "agi": 5, "tec": 5, "end": 5}
var skills: Array = ["wall", "double_jump"]


# ---------------- 점수 ----------------

func spent() -> int:
	var total := 0
	for k in STAT_ORDER:
		total += int(stats[k])
	for s in skills:
		total += int(SKILLS[s].cost)
	return total


func remaining() -> int:
	return POINTS - spent()


func is_valid() -> bool:
	for k in STAT_ORDER:
		if int(stats[k]) < STAT_MIN or int(stats[k]) > STAT_MAX:
			return false
	return skills.size() <= MAX_SKILLS and remaining() >= 0


func can_raise(stat: String) -> bool:
	return int(stats[stat]) < STAT_MAX and remaining() > 0


func can_lower(stat: String) -> bool:
	return int(stats[stat]) > STAT_MIN


## 스킬을 켜거나 끈다. 점수가 모자라면 가장 높은 능력치부터 1점씩 깎아 자리를 만든다.
func toggle_skill(skill: String) -> bool:
	if skill in skills:
		skills.erase(skill)
		return true
	if skills.size() >= MAX_SKILLS:
		return false
	skills.append(skill)
	while remaining() < 0:
		var top := ""
		for k in STAT_ORDER:
			if can_lower(k) and (top == "" or int(stats[k]) > int(stats[top])):
				top = k
		if top == "":
			skills.erase(skill)
			return false
		stats[top] = int(stats[top]) - 1
	return true


func has(skill: String) -> bool:
	return skill in skills


func duplicate_build() -> CharacterBuild:
	var b := CharacterBuild.new()
	b.name = name
	b.stats = stats.duplicate()
	b.skills = skills.duplicate()
	return b


# ---------------- 능력치가 실제로 바꾸는 값 ----------------
# 5 가 기준(지금까지의 게임과 같은 값). 1 은 약하고 10 은 강하다.

func _d(stat: String) -> float:
	return float(stats[stat]) - 5.0


## 힘: 공격 피해 배율 (1: 0.8배, 5: 1배, 10: 1.25배)
func damage_mult() -> float:
	return 1.0 + 0.05 * _d("str")


## 힘: 상대가 내 공격을 막을 때 줄어드는 기력 배율
func guard_pressure() -> float:
	return 1.0 + 0.08 * _d("str")


## 체력: 최대 체력 (1: 72, 5: 100, 10: 135)
func max_hp() -> int:
	return int(100 + 7 * _d("vit"))


## 체력: 맞았을 때 휘청이는 시간 배율 (높을수록 덜 휘청임)
func stun_mult() -> float:
	return 1.0 - 0.045 * _d("vit")


## 민첩: 이동 속도 배율 (1: 0.84, 10: 1.2)
func speed_mult() -> float:
	return 1.0 + 0.04 * _d("agi")


## 민첩: 대시 거리 배율
func dash_mult() -> float:
	return 1.0 + 0.06 * _d("agi")


## 기술: 공격 동작 시간 배율 (낮을수록 빠름. 1: 1.14, 10: 0.83)
func attack_time_mult() -> float:
	return 1.0 - 0.034 * _d("tec")


## 기술: 튕겨내기 타이밍 여유 (초. 1: 0.14, 5: 0.2, 10: 0.275)
func parry_window() -> float:
	return 0.2 + 0.015 * _d("tec")


## 지구력: 기력 최대치 (1: 60, 5: 100, 10: 150)
func max_stamina() -> float:
	return 100.0 + 10.0 * _d("end")


## 지구력: 기력 회복 배율
func regen_mult() -> float:
	return 1.0 + 0.07 * _d("end")


## 화면에 보여줄 한 줄 요약
func summary() -> String:
	var parts := []
	for k in STAT_ORDER:
		parts.append("%s %d" % [STATS[k][0], stats[k]])
	var sk := []
	for s in skills:
		sk.append(SKILLS[s].name)
	return "  ".join(parts) + ("   |   " + ", ".join(sk) if not sk.is_empty() else "")


# ---------------- 랜덤, 저장 ----------------

## 규칙에 맞는 랜덤 캐릭터. 한쪽으로 치우친 개성 있는 빌드가 나오게 한다.
static func random_build(rng: RandomNumberGenerator = null) -> CharacterBuild:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var b := CharacterBuild.new()
	b.name = "랜덤 결투사"
	for k in STAT_ORDER:
		b.stats[k] = STAT_MIN
	b.skills = []
	var pool := SKILL_ORDER.duplicate()
	var n := 2 if rng.randf() < 0.75 else 1
	for i in n:
		var s: String = pool[rng.randi_range(0, pool.size() - 1)]
		pool.erase(s)
		b.skills.append(s)
	# 능력치마다 무게를 정해 남은 점수를 나눈다 (무게가 큰 능력치가 높아진다)
	var weights := {}
	for k in STAT_ORDER:
		weights[k] = rng.randf_range(0.3, 1.0) + (1.2 if rng.randf() < 0.35 else 0.0)
	while b.remaining() > 0:
		var total := 0.0
		for k in STAT_ORDER:
			if b.can_raise(k):
				total += weights[k]
		if total <= 0.0:
			break
		var pick := rng.randf() * total
		for k in STAT_ORDER:
			if not b.can_raise(k):
				continue
			pick -= weights[k]
			if pick <= 0.0:
				b.stats[k] = int(b.stats[k]) + 1
				break
	return b


static func preset(preset_name: String) -> CharacterBuild:
	var p: Dictionary = PRESETS[preset_name]
	var b := CharacterBuild.new()
	b.name = preset_name
	b.stats = p.stats.duplicate()
	b.skills = p.skills.duplicate()
	return b


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("build", "stats", stats)
	cfg.set_value("build", "skills", skills)
	cfg.save(SAVE_PATH)


## 저장된 내 캐릭터. 없거나 규칙에 안 맞으면 기본 캐릭터.
static func load_saved() -> CharacterBuild:
	var b := CharacterBuild.new()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return b
	var st = cfg.get_value("build", "stats", {})
	var sk = cfg.get_value("build", "skills", [])
	if st is Dictionary and sk is Array:
		var cand := CharacterBuild.new()
		for k in STAT_ORDER:
			cand.stats[k] = int(st.get(k, 5))
		cand.skills = []
		for s in sk:
			if SKILLS.has(s) and not (s in cand.skills):
				cand.skills.append(s)
		if cand.is_valid():
			return cand
	return b
