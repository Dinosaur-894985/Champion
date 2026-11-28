class_name CharacterBuild
extends RefCounted
## 캐릭터 빌드: 무기 1개 + 능력치 5개 + 특수 스킬 2개.
## 무기는 점수를 먹지 않는다 (무기 표는 scripts/combat/weapons.gd).
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
	"agi": ["민첩", "이동 속도, 대시 거리, 대시 기력 절약"],
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
	"검객": {"weapon": "sword", "stats": {"str": 5, "vit": 5, "agi": 5, "tec": 6, "end": 5}, "skills": ["wall", "haste"]},
	"탱커": {"weapon": "greatsword", "stats": {"str": 8, "vit": 9, "agi": 2, "tec": 3, "end": 5}, "skills": ["iron_guard"]},
	"암살자": {"weapon": "daggers", "stats": {"str": 4, "vit": 3, "agi": 8, "tec": 7, "end": 3}, "skills": ["wall", "blink"]},
	"사냥꾼": {"weapon": "spear", "stats": {"str": 6, "vit": 4, "agi": 6, "tec": 4, "end": 7}, "skills": ["grapple", "double_jump"]},
	"광전사": {"weapon": "greatsword", "stats": {"str": 10, "vit": 6, "agi": 4, "tec": 3, "end": 3}, "skills": ["haste", "iron_guard"]},
	"봉술가": {"weapon": "staff", "stats": {"str": 5, "vit": 6, "agi": 5, "tec": 6, "end": 6}, "skills": ["double_jump"]},
	"수리검사": {"weapon": "shuriken", "stats": {"str": 4, "vit": 4, "agi": 6, "tec": 6, "end": 5}, "skills": ["wall", "blink"]},
	"격투가": {"weapon": "fists", "stats": {"str": 6, "vit": 6, "agi": 6, "tec": 6, "end": 3}, "skills": ["haste", "double_jump"]},
}
const PRESET_ORDER := ["검객", "탱커", "암살자", "사냥꾼", "광전사", "봉술가", "수리검사", "격투가"]
## 정해진 상대의 겉모습 [색, 피부, 머리, 옷 한 벌]
const PRESET_LOOKS := {
	"검객": [0, 1, 0, "knight"], "탱커": [3, 2, 3, "heavy"], "암살자": [4, 0, 1, "rogue"], "사냥꾼": [5, 3, 2, "lancer"],
	"광전사": [1, 2, 2, "heavy"], "봉술가": [6, 1, 1, "monk"], "수리검사": [2, 0, 0, "shadow"], "격투가": [7, 3, 3, "brawler"],
}

## 옷과 장비: 부위마다 따로 고른다 (무기와 상관없다). 모양 이름은 BodyRig 가 그린다.
const PART_ORDER := ["head", "torso", "arms", "legs", "feet"]
const PART_LABELS := {"head": "모자", "torso": "몸통", "arms": "팔", "legs": "다리", "feet": "신발"}
const STYLE_ORDER := ["knight", "heavy", "rogue", "lancer", "monk", "shadow", "brawler"]
## 부위마다 모양 이름 (STYLE_ORDER 순서)
const PART_NAMES := {
	"head": ["반투구", "닫힌 투구", "두건", "볏 투구", "머리띠", "복면", "맨머리"],
	"torso": ["기사 가슴판", "중갑과 망토", "가죽 조끼", "비늘 갑옷", "도복", "목도리 옷", "민소매"],
	"arms": ["팔 보호대", "철 팔갑옷", "가죽 토시", "천 소매", "넓은 소매", "검은 토시", "맨팔"],
	"legs": ["무릎 갑옷", "다리 갑옷", "가죽 바지", "정강이받이", "도복 바지", "감은 바지", "넉넉한 바지"],
	"feet": ["가죽 장화", "철 장화", "검은 장화", "쇠코 장화", "짚신", "끈 신", "맨발"],
}
## 옷 한 벌로 맞춰 입을 때의 이름
const SET_NAMES := ["기사", "중갑", "도적", "창병", "무도가", "그림자", "싸움꾼"]

## 겉모습 (점수를 먹지 않는다). 옷은 아래 PARTS 에서 부위마다 고른다. 몸집은 능력치(힘, 체력, 민첩)를 따라 저절로 바뀐다.
## 색: 옷과 무기 감개, 술에 쓰인다. [이름, 색]
const COLORS := [
	["청록", Color(0.08, 0.55, 0.56)], ["진홍", Color(0.72, 0.13, 0.16)], ["남색", Color(0.16, 0.24, 0.62)],
	["황금", Color(0.82, 0.6, 0.16)], ["보라", Color(0.46, 0.22, 0.62)], ["숲", Color(0.22, 0.48, 0.22)],
	["주황", Color(0.9, 0.42, 0.1)], ["먹색", Color(0.2, 0.21, 0.24)],
]
const SKINS := [Color(0.96, 0.8, 0.66), Color(0.87, 0.67, 0.5), Color(0.66, 0.46, 0.3), Color(0.42, 0.28, 0.18)]
const HAIRS := ["짧은 머리", "묶은 머리", "뻗친 머리", "민머리"]
const HAIR_COLORS := [Color(0.1, 0.08, 0.07), Color(0.35, 0.2, 0.1), Color(0.75, 0.6, 0.35), Color(0.55, 0.55, 0.58)]

var name := "캐릭터 1"
var weapon := "sword"
var stats := {"str": 5, "vit": 5, "agi": 5, "tec": 5, "end": 5}
var skills: Array = ["wall", "double_jump"]
var color := 0
var skin := 1
var hair := 0
var parts := {"head": "knight", "torso": "knight", "arms": "knight", "legs": "knight", "feet": "knight"}


## 부위가 고른 모양 (없거나 틀리면 기사)
func part(p: String) -> String:
	var v := str(parts.get(p, "knight"))
	return v if v in STYLE_ORDER else "knight"


func part_name(p: String) -> String:
	return PART_NAMES[p][STYLE_ORDER.find(part(p))]


## 모든 부위를 한 벌로 맞춘다
func wear_set(style: String) -> void:
	for p in PART_ORDER:
		parts[p] = style if style in STYLE_ORDER else "knight"


func accent() -> Color:
	return COLORS[clampi(color, 0, COLORS.size() - 1)][1]


func skin_color() -> Color:
	return SKINS[clampi(skin, 0, SKINS.size() - 1)]


## 머리색은 색과 머리 모양으로 정해진다 (따로 고르지 않아도 다양하게)
func hair_color() -> Color:
	return HAIR_COLORS[(color + hair * 3) % HAIR_COLORS.size()]


## 같은 모습끼리 맞붙을 때(거울 모드 등) 상대를 알아보기 쉽게 색을 바꾼다
func contrast_with(other: CharacterBuild) -> void:
	if other != null and other.color == color:
		color = (color + 4) % COLORS.size()


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
	b.weapon = weapon
	b.stats = stats.duplicate()
	b.skills = skills.duplicate()
	b.color = color
	b.skin = skin
	b.hair = hair
	b.parts = parts.duplicate()
	return b


# ---------------- 능력치가 실제로 바꾸는 값 ----------------
# 5 가 기준(지금까지의 게임과 같은 값). 1 은 약하고 10 은 강하다.
# 8 을 넘는 점수는 효과가 절반이다 (9 는 8.5, 10 은 9 만큼) → 한 곳에 몰아 찍기보다 섞는 편이 낫다.
# 점수 1점의 값이 능력치마다 비슷하도록 맞춰 두었다 (자동 대결로 확인: tools/balance_sim.sh).

const SOFT_CAP := 8.0


## 실제로 쓰이는 능력치 값 (8 넘으면 절반만 오른다)
func effective(stat: String) -> float:
	var v := float(stats[stat])
	return v if v <= SOFT_CAP else SOFT_CAP + (v - SOFT_CAP) * 0.5


func _d(stat: String) -> float:
	return effective(stat) - 5.0


## 힘: 공격 피해 배율 (1: 0.72배, 5: 1배, 10: 1.28배)
func damage_mult() -> float:
	return 1.0 + 0.07 * _d("str")


## 힘: 상대가 내 공격을 막을 때 줄어드는 기력 배율
func guard_pressure() -> float:
	return 1.0 + 0.08 * _d("str")


## 체력: 최대 체력 (1: 80, 5: 100, 10: 120)
func max_hp() -> int:
	return int(100 + 5 * _d("vit"))


## 체력: 맞았을 때 휘청이는 시간 배율 (높을수록 덜 휘청임)
func stun_mult() -> float:
	return 1.0 - 0.035 * _d("vit")


## 민첩: 이동 속도 배율 (1: 0.84, 10: 1.16)
func speed_mult() -> float:
	return 1.0 + 0.04 * _d("agi")


## 민첩: 대시 거리 배율
func dash_mult() -> float:
	return 1.0 + 0.06 * _d("agi")


## 민첩: 대시(피하기)에 드는 기력 배율 (1: 1.28, 5: 1, 10: 0.72) → 민첩이 높으면 더 자주 피한다
func dash_cost_mult() -> float:
	return 1.0 - 0.07 * _d("agi")


## 기술: 공격 동작 시간 배율 (낮을수록 빠름. 1: 1.14, 10: 0.86)
func attack_time_mult() -> float:
	return 1.0 - 0.034 * _d("tec")


## 기술: 튕겨내기 타이밍 여유 (초. 1: 0.14, 5: 0.2, 10: 0.26)
func parry_window() -> float:
	return 0.2 + 0.015 * _d("tec")


## 지구력: 기력 최대치 (1: 60, 5: 100, 10: 140)
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
	return Weapons.display_name(weapon) + "   |   " + "  ".join(parts) + ("   |   " + ", ".join(sk) if not sk.is_empty() else "")


# ---------------- 랜덤, 저장 ----------------

## 규칙에 맞는 랜덤 캐릭터. 한쪽으로 치우친 개성 있는 빌드가 나오게 한다.
static func random_build(rng: RandomNumberGenerator = null) -> CharacterBuild:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var b := CharacterBuild.new()
	b.name = "랜덤 결투사"
	b.weapon = Weapons.ORDER[rng.randi_range(0, Weapons.ORDER.size() - 1)]
	for k in STAT_ORDER:
		b.stats[k] = STAT_MIN
	b.skills = []
	b.color = rng.randi_range(0, COLORS.size() - 1)
	b.skin = rng.randi_range(0, SKINS.size() - 1)
	b.hair = rng.randi_range(0, HAIRS.size() - 1)
	# 옷: 한 벌로 맞추거나, 부위마다 섞어 입는다
	b.wear_set(STYLE_ORDER[rng.randi_range(0, STYLE_ORDER.size() - 1)])
	if rng.randf() < 0.5:
		for p in PART_ORDER:
			if rng.randf() < 0.5:
				b.parts[p] = STYLE_ORDER[rng.randi_range(0, STYLE_ORDER.size() - 1)]
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
	b.weapon = p.get("weapon", "sword")
	b.stats = p.stats.duplicate()
	b.skills = p.skills.duplicate()
	var look: Array = PRESET_LOOKS.get(preset_name, [0, 1, 0, "knight"])
	b.color = look[0]
	b.skin = look[1]
	b.hair = look[2]
	b.wear_set(look[3])
	return b


# ---------------- 저장 칸 (캐릭터 3개) ----------------
# user://build.cfg 한 파일에 [slot0] [slot1] [slot2] 칸과 [roster] active(지금 쓰는 칸)를 둔다.
# 예전 파일([build] [look] 한 캐릭터)은 읽을 때 1번 칸으로 옮긴다. 웹에서는 브라우저 저장소에 남는다.

const SLOTS := 3
const NAME_MAX := 10


static func default_name(slot: int) -> String:
	return "캐릭터 %d" % (slot + 1)


## 지금 쓰는 칸에 저장한다
func save() -> void:
	save_to_slot(active_slot())


## 이 칸에 저장하고, 이 칸을 지금 쓰는 캐릭터로 정한다
func save_to_slot(slot: int) -> void:
	slot = clampi(slot, 0, SLOTS - 1)
	var cfg := _open()
	var sec := "slot%d" % slot
	var nm := clean_name(name)
	cfg.set_value(sec, "name", nm if nm != "" else default_name(slot))
	cfg.set_value(sec, "weapon", weapon)
	cfg.set_value(sec, "stats", stats)
	cfg.set_value(sec, "skills", skills)
	cfg.set_value(sec, "color", color)
	cfg.set_value(sec, "skin", skin)
	cfg.set_value(sec, "hair", hair)
	cfg.set_value(sec, "parts", parts)
	cfg.set_value("roster", "active", slot)
	cfg.save(SAVE_PATH)


## 이름 다듬기: 앞뒤 빈칸과 줄바꿈을 없애고 NAME_MAX 글자까지
static func clean_name(s: String) -> String:
	return s.replace("\n", " ").strip_edges().left(NAME_MAX)


## 저장 파일을 연다. 예전 한 캐릭터 파일이면 1번 칸으로 옮긴다.
static func _open() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	if cfg.has_section("build"):
		if not cfg.has_section("slot0"):
			var old := _read(cfg, "build", "look")
			if old:
				old.name = default_name(0)
				cfg.set_value("slot0", "name", old.name)
				cfg.set_value("slot0", "weapon", old.weapon)
				cfg.set_value("slot0", "stats", old.stats)
				cfg.set_value("slot0", "skills", old.skills)
				cfg.set_value("slot0", "color", old.color)
				cfg.set_value("slot0", "skin", old.skin)
				cfg.set_value("slot0", "hair", old.hair)
				cfg.set_value("slot0", "parts", old.parts)
		cfg.erase_section("build")
		if cfg.has_section("look"):
			cfg.erase_section("look")
	return cfg


## 칸 하나를 읽는다. 없거나 규칙에 안 맞으면 null
static func _read(cfg: ConfigFile, sec: String, look_sec: String) -> CharacterBuild:
	if not cfg.has_section(sec):
		return null
	var st = cfg.get_value(sec, "stats", {})
	var sk = cfg.get_value(sec, "skills", [])
	if not (st is Dictionary and sk is Array):
		return null
	var cand := CharacterBuild.new()
	cand.name = clean_name(str(cfg.get_value(sec, "name", "")))
	cand.weapon = Weapons.valid(str(cfg.get_value(sec, "weapon", "sword")))
	for k in STAT_ORDER:
		cand.stats[k] = int(st.get(k, 5))
	cand.skills = []
	for s in sk:
		if SKILLS.has(s) and not (s in cand.skills) and cand.skills.size() < MAX_SKILLS:
			cand.skills.append(s)
	cand.color = clampi(int(cfg.get_value(look_sec, "color", 0)), 0, COLORS.size() - 1)
	cand.skin = clampi(int(cfg.get_value(look_sec, "skin", 1)), 0, SKINS.size() - 1)
	cand.hair = clampi(int(cfg.get_value(look_sec, "hair", 0)), 0, HAIRS.size() - 1)
	var pt = cfg.get_value(look_sec, "parts", {})
	if pt is Dictionary:
		for p in PART_ORDER:
			if str(pt.get(p, "")) in STYLE_ORDER:
				cand.parts[p] = str(pt[p])
	return cand if cand.is_valid() else null


## 저장된 칸의 캐릭터. 빈 칸이면 null
static func load_slot(slot: int) -> CharacterBuild:
	if slot < 0 or slot >= SLOTS:
		return null
	var b := _read(_open(), "slot%d" % slot, "slot%d" % slot)
	if b and b.name == "":
		b.name = default_name(slot)
	return b


## 칸마다 저장된 캐릭터 (빈 칸은 null) — 메뉴에 보여 줄 때 쓴다
static func load_all_slots() -> Array:
	var cfg := _open()
	var out := []
	for i in SLOTS:
		var b := _read(cfg, "slot%d" % i, "slot%d" % i)
		if b and b.name == "":
			b.name = default_name(i)
		out.append(b)
	return out


## 지금 쓰는 칸. 그 칸이 비었으면 저장된 첫 칸, 아무것도 없으면 0
static func active_slot() -> int:
	var cfg := _open()
	var a := clampi(int(cfg.get_value("roster", "active", 0)), 0, SLOTS - 1)
	if _read(cfg, "slot%d" % a, "slot%d" % a):
		return a
	for i in SLOTS:
		if _read(cfg, "slot%d" % i, "slot%d" % i):
			return i
	return 0


## 저장된 칸을 지금 쓰는 캐릭터로 정한다. 빈 칸이면 false
static func set_active_slot(slot: int) -> bool:
	var cfg := _open()
	if slot < 0 or slot >= SLOTS or _read(cfg, "slot%d" % slot, "slot%d" % slot) == null:
		return false
	cfg.set_value("roster", "active", slot)
	cfg.save(SAVE_PATH)
	return true


## 칸을 지운다. 마지막 남은 캐릭터는 지우지 않는다 (false). 지운 칸의 전적도 지운다.
static func delete_slot(slot: int) -> bool:
	var cfg := _open()
	var sec := "slot%d" % slot
	if slot < 0 or slot >= SLOTS or not cfg.has_section(sec):
		return false
	var filled := 0
	for i in SLOTS:
		if cfg.has_section("slot%d" % i):
			filled += 1
	if filled <= 1:
		return false
	cfg.erase_section(sec)
	if int(cfg.get_value("roster", "active", 0)) == slot:
		for i in SLOTS:
			if cfg.has_section("slot%d" % i):
				cfg.set_value("roster", "active", i)
				break
	cfg.save(SAVE_PATH)
	Records.forget_character(slot)
	return true


## 지금 쓰는 내 캐릭터. 아무것도 저장 안 했으면 기본 캐릭터.
static func load_saved() -> CharacterBuild:
	var slot := active_slot()
	var b := load_slot(slot)
	if b == null:
		b = CharacterBuild.new()
		b.name = default_name(slot)
	return b
