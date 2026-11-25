extends Control
## 조준점 둘레의 방향 표시 (수싸움).
##   위 / 왼·오른쪽 / 아래 호 = 위 공격, 옆 공격, 찌르기 (마우스를 움직이는 방향과 같다)
##   주황→빨강으로 차오름 : 상대가 그 방향으로 공격을 준비 중 (꽉 차면 휘두른다)
##   보라 고리             : 상대가 잡으려 한다 → 막지 말고 때리거나 피하라
##   하얀 굵은 호           : 내가 막고 있는 방향
##   바깥쪽 청록 호         : 상대가 막고 있는 방향 → 다른 방향으로 베거나 잡아라

const R := 40.0          # 안쪽 호 반지름
const R_OUT := 54.0      # 상대 막기 표시 반지름
const SPAN := 0.62       # 호 하나의 폭 (라디안의 절반)

var player: Player
var opponent: Duelist

var _enemy_dir := ""
var _enemy_k := 0.0
var _flash := 0.0


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 3.0, 0.0)
	var d := ""
	var k := 0.0
	if opponent and is_instance_valid(opponent) and not opponent.dead:
		d = opponent.attack_dir()
		if d != "":
			k = opponent.windup_progress()
	if d != _enemy_dir and d != "":
		_flash = 1.0   # 방향이 바뀌면 번쩍 (속임수 알아차리기)
	_enemy_dir = d
	_enemy_k = k
	queue_redraw()


## dir 의 호 중심 각도들 (화면 기준: 0 = 오른쪽, -PI/2 = 위)
static func _angles(dir: String) -> Array:
	match dir:
		"high":
			return [-PI / 2.0]
		"mid":
			return [PI / 2.0]
		"side":
			return [PI, 0.0]
	return []


func _arc(c: Vector2, r: float, dir: String, col: Color, width: float) -> void:
	for a in _angles(dir):
		draw_arc(c + Vector2(1, 1), r, a - SPAN, a + SPAN, 14, Color(0, 0, 0, col.a * 0.45), width + 2.0)
		draw_arc(c, r, a - SPAN, a + SPAN, 14, col, width)


func _draw() -> void:
	if player == null or not is_instance_valid(player) or player.dead:
		return
	var c := size * 0.5
	# 바탕: 세 방향 자리를 옅게
	for dir in AttackDir.ALL:
		_arc(c, R, dir, Color(1, 1, 1, 0.13), 2.0)
	# 내 막기
	if player.blocking:
		_arc(c, R, player.guard_dir, Color(1, 1, 1, 0.95), 5.0)
	# 상대 막기
	if opponent and is_instance_valid(opponent) and opponent.state == "block":
		_arc(c, R_OUT, opponent.guard_dir, Color(0.3, 0.95, 0.9, 0.9), 4.0)
	# 상대 공격 예고
	if _enemy_dir == "grab":
		var a := 0.45 + 0.55 * _enemy_k
		draw_arc(c, R + 6.0, 0, TAU, 40, Color(0.8, 0.35, 1.0, a), 3.0 + 4.0 * _enemy_k)
	elif _enemy_dir != "":
		var col := Color(1.0, 0.7, 0.2).lerp(Color(1.0, 0.15, 0.1), _enemy_k)
		col.a = 0.55 + 0.45 * _enemy_k
		_arc(c, R + 7.0, _enemy_dir, col, 4.0 + 6.0 * _enemy_k + _flash * 4.0)
