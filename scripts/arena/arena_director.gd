class_name ArenaDirector
extends Node
## 대결 진행: 시간이 지나면 바깥 바닥부터 무너지고, 높은 곳에 아이템이 생긴다.
## 그래서 한곳에 숨어 있을 수 없고, 아이템을 두고 높은 곳에서 부딪치게 된다.
## 연습장에서는 켜지 않는다 (running = false).

signal announce(text: String, color: Color, big: bool)
signal status(text: String)

## 무너지는 순서: [몇 초에, 어느 고리] (3 = 맨 바깥, 1 = 가운데 바로 바깥)
const STAGES := [[30.0, 3], [60.0, 2], [90.0, 1]]
const WARN_TIME := 5.0
const PICKUP_FIRST := 6.0
const PICKUP_EVERY := 11.0
const PICKUP_MAX := 2
const GRAB_RADIUS := 1.25
## 아이템이 나오는 차례 (같은 종류가 몰리지 않게 섞어서 돈다)
const PICKUP_ORDER := ["heal", "power", "energy", "heal", "energy", "power"]

var arena: Arena
var fighters: Array = []
var running := false
var time := 0.0
var pickups: Array[ArenaPickup] = []
var collapsed := 0             # 무너진 단계 수
var _warned := 0
var _next_pickup := PICKUP_FIRST
var _order_i := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 4242


func _physics_process(delta: float) -> void:
	if not running:
		return
	time += delta
	# 바닥 무너짐
	if _warned < STAGES.size() and time >= STAGES[_warned][0] - WARN_TIME:
		var ring: int = STAGES[_warned][1]
		arena.warn_ring(ring)
		_drop_pickups_in(ring)
		announce.emit("바깥 바닥이 곧 무너진다! 가운데로!", Color(1.0, 0.45, 0.3), false)
		_warned += 1
	if collapsed < STAGES.size() and time >= STAGES[collapsed][0]:
		arena.collapse_ring(STAGES[collapsed][1])
		collapsed += 1
		announce.emit("바닥 붕괴!", Color(1.0, 0.4, 0.25), true)
	# 아이템
	if time >= _next_pickup:
		_next_pickup = time + PICKUP_EVERY
		_spawn_pickup()
	_check_pickups()
	status.emit(status_text())


func status_text() -> String:
	if collapsed >= STAGES.size():
		return "마지막 경기장"
	var left: float = STAGES[collapsed][0] - time
	if left <= WARN_TIME:
		return "붕괴 %d" % int(ceilf(left))
	return "다음 붕괴 %d초" % int(ceilf(left))


func _spawn_pickup() -> void:
	var alive: Array[ArenaPickup] = []
	for p in pickups:
		if is_instance_valid(p) and not p.taken:
			alive.append(p)
	pickups = alive
	if pickups.size() >= PICKUP_MAX:
		return
	var spots := arena.pickup_spots()
	var free := []
	for s in spots:
		var used := false
		for p in pickups:
			if p.spot.id == s.id:
				used = true
		# 누가 바로 옆에 서 있는 곳은 피한다
		for f in fighters:
			if is_instance_valid(f) and (f as Node3D).global_position.distance_to(s.pos) < 3.0:
				used = true
		if not used:
			free.append(s)
	if free.is_empty():
		return
	var spot: Dictionary = free[_rng.randi() % free.size()]
	var kind: String = PICKUP_ORDER[_order_i % PICKUP_ORDER.size()]
	_order_i += 1
	var p := ArenaPickup.new()
	p.setup(kind, spot)
	arena.add_child(p)
	pickups.append(p)
	var where: String = spot.get("name", "높은 곳")
	announce.emit("%s에 %s 아이템!" % [where, VerticalKit.PICKUPS[kind].name], VerticalKit.PICKUPS[kind].color, false)


func _check_pickups() -> void:
	for p in pickups:
		if not is_instance_valid(p) or p.taken:
			continue
		for f in fighters:
			if not is_instance_valid(f) or f.dead:
				continue
			var body := f as Node3D
			if (body.global_position + Vector3.UP * 0.9).distance_to(p.global_position + Vector3.UP * 1.0) < GRAB_RADIUS:
				f.vkit.apply_pickup(p.kind)
				p.collect()
				var name: String = VerticalKit.PICKUPS[p.kind].name
				var col: Color = VerticalKit.PICKUPS[p.kind].color
				if f is Player:
					announce.emit("%s 획득!" % name, col, false)
				else:
					announce.emit("상대가 %s 획득!" % name, Color(1.0, 0.6, 0.45), false)
				if f.has_method("on_pickup"):
					f.on_pickup(p.kind)
				break


## 무너질 고리 위 아이템은 없앤다
func _drop_pickups_in(ring: int) -> void:
	for p in pickups:
		if is_instance_valid(p) and not p.taken and int(p.spot.ring) >= ring:
			p.taken = true
			p.queue_free()


## AI 가 노릴 만한 아이템 (없으면 null). 가깝고, 상대보다 먼저 닿을 수 있는 것.
func best_pickup_for(me: Node3D, other: Node3D) -> ArenaPickup:
	var best: ArenaPickup = null
	var best_score := INF
	for p in pickups:
		if not is_instance_valid(p) or p.taken:
			continue
		var d_me := me.global_position.distance_to(p.global_position)
		var d_other := other.global_position.distance_to(p.global_position)
		var score := d_me - d_other * 0.5
		if score < best_score:
			best_score = score
			best = p
	return best


## 무너지지 않고 남아 있는 바깥 고리 번호 (3이면 아직 안 무너짐)
func outer_ring() -> int:
	return 3 - _warned
