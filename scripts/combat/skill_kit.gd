class_name SkillKit
extends RefCounted
## 특수 스킬의 쿨타임, 기력, 지속 효과(질풍)를 관리한다. 플레이어와 AI 가 같이 쓴다.
## 실제로 무엇을 하는지(순간이동, 줄 걸기...)는 각자 몸을 움직이는 쪽(Player, Duelist)이 한다.
## 수치는 CharacterBuild.SKILLS 표에 있다.
##
## 주인(owner)에게 필요한 것: stamina 변수, spend_stamina(양) 함수, velocity (CharacterBody3D)

signal used(skill: String)

var build: CharacterBuild
var _owner: Object
var _cd := {}            # 스킬 → 남은 쿨타임
var _haste_t := 0.0
var _double_jump_used := false


func _init(owner: Object, b: CharacterBuild) -> void:
	_owner = owner
	build = b
	for s in b.skills:
		_cd[s] = 0.0


func tick(delta: float) -> void:
	for s in _cd:
		_cd[s] = maxf(_cd[s] - delta, 0.0)
	_haste_t = maxf(_haste_t - delta, 0.0)


func has(skill: String) -> bool:
	return build.has(skill)


static func info(skill: String) -> Dictionary:
	return CharacterBuild.SKILLS[skill]


## 지금 쓸 수 있나 (가지고 있고, 쿨타임이 끝났고, 기력이 충분)
func can_use(skill: String) -> bool:
	if not has(skill) or not info(skill).active:
		return false
	return _cd[skill] <= 0.0 and float(_owner.stamina) >= float(info(skill).stamina)


## 쓸 수 있으면 기력과 쿨타임을 쓰고 true. 실제 효과는 부른 쪽이 낸다.
func use(skill: String) -> bool:
	if not can_use(skill):
		return false
	var d := info(skill)
	if float(d.stamina) > 0.0:
		_owner.spend_stamina(float(d.stamina))
	_cd[skill] = float(d.cooldown)
	if skill == "haste":
		_haste_t = float(d.duration)
	used.emit(skill)
	return true


func cooldown_left(skill: String) -> float:
	return _cd.get(skill, 0.0)


## 0 = 쓸 수 있음, 1 = 막 썼음
func cooldown_ratio(skill: String) -> float:
	var full := float(info(skill).cooldown)
	return cooldown_left(skill) / full if full > 0.0 else 0.0


# ---------------- 이중 점프 ----------------

## 공중에서 한 번 더 뛴다. 땅에 닿으면 다시 쓸 수 있다.
func try_double_jump(jump_velocity: float = 5.2) -> bool:
	if not has("double_jump") or _double_jump_used:
		return false
	var cost := float(info("double_jump").stamina)
	if float(_owner.stamina) < cost * 0.5:
		return false
	_double_jump_used = true
	_owner.spend_stamina(cost)
	var v: Vector3 = _owner.velocity
	v.y = jump_velocity
	_owner.velocity = v
	used.emit("double_jump")
	return true


func double_jump_left() -> bool:
	return has("double_jump") and not _double_jump_used


func landed() -> void:
	_double_jump_used = false


# ---------------- 질풍 ----------------

func haste_active() -> bool:
	return _haste_t > 0.0


func haste_left() -> float:
	return _haste_t


func speed_mult() -> float:
	return float(info("haste").speed_mult) if _haste_t > 0.0 else 1.0


func attack_mult() -> float:
	return float(info("haste").attack_mult) if _haste_t > 0.0 else 1.0


func regen_mult() -> float:
	return 1.6 if _haste_t > 0.0 else 1.0
