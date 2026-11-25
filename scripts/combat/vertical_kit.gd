class_name VerticalKit
extends RefCounted
## 높이와 관련된 공통 규칙. 플레이어와 AI 가 똑같이 쓴다.
##   - 밀려 떨어지기: 맞거나 던져진 직후 높은 곳에서 떨어지면 떨어진 높이만큼 피해 + 넘어짐
##   - 낭떠러지: 경기장 밖(아래 허공)으로 떨어지면 큰 피해를 입고 안전한 곳에서 다시 시작
##   - 날려 보내기: 강한 공격에 맞으면 공중으로 붕 떠서 밀려난다 (낭떠러지로 밀어 떨어뜨릴 수 있다)
##   - 난간 잡기: 떨어지다 눈앞에 난간이 있으면 매달린다
##   - 높은 곳 아이템: 회복, 기력, 힘
## 맞는 쪽 코드(_resolve_attack, _take_hit)는 건드리지 않고, 그 바깥(receive_attack, take_hit)에서 이 규칙을 붙인다.

const VOID_Y := -6.0               # 이보다 아래로 떨어지면 낭떠러지
const VOID_DAMAGE := 0.3           # 낭떠러지에 떨어지면 최대 체력의 30%
const KNOCK_TIME := 1.3            # 날려진 뒤 이 시간 안에 떨어지면 '밀려 떨어진 것'
const FLINCH_KNOCK_TIME := 0.6     # 가볍게 맞고 비틀거리다 떨어져도 조금
const FALL_SAFE := 2.4             # 이 높이까지는 괜찮다
const FALL_DMG_PER_M := 4.0
const FALL_DMG_MIN := 6
const FALL_DMG_MAX := 28

## 날려 보내는 공격: [수평 힘, 위로 뜨는 힘]
const LAUNCH := {
	"heavy": Vector2(8.5, 3.6),
	"charge": Vector2(10.5, 4.2),
	"slash3": Vector2(5.0, 2.4),
	"plunge": Vector2(6.5, 4.6),
	"counter": Vector2(4.5, 2.0),
	"ledge_slash": Vector2(7.5, 3.4),
}

## 높은 곳에 생기는 아이템
const PICKUPS := {
	"heal": {"name": "회복", "color": Color(0.35, 0.95, 0.5), "amount": 25},
	"energy": {"name": "기력", "color": Color(0.4, 0.75, 1.0)},
	"power": {"name": "힘", "color": Color(1.0, 0.55, 0.2), "time": 10.0, "damage": 1.3, "launch": 1.4},
}

## 난간 매달리기
const HANG_MAX := 3.5              # 이 시간이 지나면 손을 놓친다
const HANG_COST := 9.0             # 초당 기력
const HANG_COOLDOWN := 0.7         # 놓친 뒤 다시 잡기까지

var body: CharacterBody3D
var knocked := 0.0                 # 남은 '날려진' 시간
var power_left := 0.0
var _airborne := false
var _peak := 0.0
var _knocked_in_air := false
var _ray := PhysicsRayQueryParameters3D.new()


func _init(owner: CharacterBody3D) -> void:
	body = owner
	_ray.collision_mask = 1


## 매 프레임 (move_and_slide 다음). 돌려주는 값: 0 아무 일 없음, -1 낭떠러지, 그 밖에는 떨어져서 입은 피해
func tick(delta: float, on_floor: bool) -> int:
	knocked = maxf(knocked - delta, 0.0)
	power_left = maxf(power_left - delta, 0.0)
	var y := body.global_position.y
	if y < VOID_Y:
		return -1
	if on_floor:
		var dmg := 0
		if _airborne and _knocked_in_air:
			var h := _peak - y
			if h > FALL_SAFE:
				dmg = clampi(int((h - FALL_SAFE) * FALL_DMG_PER_M) + FALL_DMG_MIN, FALL_DMG_MIN, FALL_DMG_MAX)
		_airborne = false
		_knocked_in_air = false
		_peak = y
		return dmg
	if not _airborne:
		_airborne = true
		_peak = y
	_peak = maxf(_peak, y)
	if knocked > 0.0:
		_knocked_in_air = true
	return 0


## 다시 놓였을 때 (낭떠러지에서 돌아옴, 순간이동 등) 떨어진 기록을 지운다
func reset_fall() -> void:
	_airborne = false
	_knocked_in_air = false
	_peak = body.global_position.y
	knocked = 0.0


func knock(time: float = KNOCK_TIME) -> void:
	knocked = maxf(knocked, time)


## 맞은 공격이 날려 보내는 공격이면 [수평 힘, 위 힘], 아니면 ZERO
static func launch_for(info: Dictionary) -> Vector2:
	var mv: String = info.get("move", "")
	var v: Vector2 = LAUNCH.get(mv, Vector2.ZERO)
	if mv == "charge" and info.get("guard", "") != "break":
		v *= 0.55   # 끝까지 모으지 않은 차지 베기는 조금만
	# 무기 필살기는 날려 보내는 힘을 직접 정한다. 무기 동작은 더 세게 밀 수 있다 (Weapons 표)
	if float(info.get("push", 0.0)) > 0.0:
		v = Vector2(float(info.push), float(info.get("lift", 2.0)))
	elif float(info.get("push_add", 0.0)) > 0.0:
		v += Vector2(float(info.push_add), float(info.push_add) * 0.35)
	if v == Vector2.ZERO:
		return v
	if info.get("power", false):
		v *= float(PICKUPS.power.launch)
	return v


## 공격하는 쪽: '힘' 아이템이 켜져 있으면 피해 배율
func damage_mult() -> float:
	return float(PICKUPS.power.damage) if power_left > 0.0 else 1.0


func powered() -> bool:
	return power_left > 0.0


## 아이템을 먹었다. 몸(플레이어/AI)의 체력, 기력, 스킬 쿨타임을 바꾼다.
func apply_pickup(kind: String) -> void:
	var b: Object = body
	match kind:
		"heal":
			b.hp = mini(b.hp + int(PICKUPS.heal.amount), b.max_hp)
			b.hp_changed.emit(b.hp, b.max_hp)
		"energy":
			b.stamina = b.max_stamina
			b.stamina_changed.emit(b.stamina, b.max_stamina)
			var sk: SkillKit = b.skills
			for k in sk._cd:
				sk._cd[k] = 0.0
		"power":
			power_left = float(PICKUPS.power.time)


# ---------------- 난간 찾기 ----------------

## 앞(fwd, 수평) 쪽에 잡을 수 있는 난간이 있으면 {"y": 난간 높이, "n": 벽이 바라보는 방향, "point": 벽에 닿은 곳}
## reach_low/high: 발 기준으로 난간이 이 높이 사이에 있어야 잡는다
func find_ledge(fwd: Vector3, reach_low: float = 1.2, reach_high: float = 2.4) -> Dictionary:
	var space := body.get_world_3d().direct_space_state
	var pos := body.global_position
	_ray.exclude = [body.get_rid()]
	fwd.y = 0.0
	if fwd.length() < 0.1:
		return {}
	fwd = fwd.normalized()
	# 1) 가슴 높이 앞에 벽이 있어야 한다
	_ray.from = pos + Vector3.UP * 1.1
	_ray.to = _ray.from + fwd * 1.2
	var wall := space.intersect_ray(_ray)
	if wall.is_empty():
		# 손 높이에서도 한 번 (난간이 머리 근처일 때)
		_ray.from = pos + Vector3.UP * 1.7
		_ray.to = _ray.from + fwd * 1.2
		wall = space.intersect_ray(_ray)
		if wall.is_empty():
			return {}
	var n: Vector3 = wall.normal
	if absf(n.y) > 0.35:
		return {}
	n.y = 0.0
	n = n.normalized()
	var hit: Vector3 = wall.position
	# 2) 벽 꼭대기(난간) 높이를 위에서 아래로 재어 본다
	_ray.from = Vector3(hit.x, pos.y + reach_high + 0.3, hit.z) - n * 0.3
	_ray.to = _ray.from + Vector3.DOWN * (reach_high - reach_low + 0.5)
	var top := space.intersect_ray(_ray)
	if top.is_empty() or (top.normal as Vector3).y < 0.7:
		return {}
	var ledge_y: float = (top.position as Vector3).y
	var rel := ledge_y - pos.y
	if rel < reach_low or rel > reach_high:
		return {}
	# 3) 난간 위에 몸이 올라설 자리가 있어야 한다 (천장에 막혀 있지 않게)
	_ray.from = Vector3(hit.x, ledge_y + 0.2, hit.z) - n * 0.45
	_ray.to = _ray.from + Vector3.UP * 1.6
	if not space.intersect_ray(_ray).is_empty():
		return {}
	return {"y": ledge_y, "n": n, "point": hit}


## 발밑 아래로 얼마나 높이 떠 있나 (max_d 까지 바닥이 없으면 max_d)
func height_above_ground(max_d: float = 30.0) -> float:
	var space := body.get_world_3d().direct_space_state
	_ray.exclude = [body.get_rid()]
	_ray.from = body.global_position + Vector3.UP * 0.1
	_ray.to = _ray.from + Vector3.DOWN * max_d
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		return max_d
	return body.global_position.y - (hit.position as Vector3).y


## p 아래에 drop 이내로 딛을 바닥이 있나 (AI 가 낭떠러지로 걸어가지 않게)
func ground_near(p: Vector3, drop: float = 3.2) -> bool:
	var space := body.get_world_3d().direct_space_state
	_ray.exclude = [body.get_rid()]
	_ray.from = p + Vector3.UP * 0.6
	_ray.to = p + Vector3.DOWN * drop
	return not space.intersect_ray(_ray).is_empty()
