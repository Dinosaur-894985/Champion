class_name MindReader
extends RefCounted
## AI 가 상대의 버릇을 기억하고 읽는다. (수싸움)
##
## 무엇을 기억하나
##   - 상대가 어느 방향으로 자주 베나      → 막기 방향을 미리 짐작한다
##   - 내 공격을 어느 방향에서 잘 막나     → 덜 막히는 방향으로 벤다
##   - 얼마나 자주 막고 서 있나            → 많이 막으면 잡기와 속임수를 늘린다
##   - 얼마나 자주 잡기를 쓰나             → 자주 잡으면 먼저 휘둘러 끊는다
##   - 얼마나 자주 공격을 멈추나(속임수)    → 자주 속이면 덜 속는다 (서둘러 막지 않는다)
## 오래된 기억은 조금씩 흐려진다 (MEMORY). 그래서 상대가 버릇을 바꾸면 AI 도 따라 바꾼다.

const MEMORY := 0.9   # 새 일이 생길 때마다 옛 기억에 곱하는 값

var attack_dirs := {"high": 1.0, "side": 1.5, "mid": 1.0}
## 내(AI) 공격 방향별 [막힘, 시도]
var guarded := {"high": [0.5, 1.0], "side": [0.5, 1.0], "mid": [0.5, 1.0]}
var block_ratio := 0.3      # 최근에 막고 서 있던 시간 비율 (0~1)
var grab_rate := 0.0        # 최근 상대 행동 중 잡기 비율
var feint_rate := 0.0       # 최근 상대 공격 중 멈춘 비율
var _actions := 0.0


func tick(delta: float, target_blocking: bool) -> void:
	# 약 5초 동안의 평균
	block_ratio = lerpf(block_ratio, 1.0 if target_blocking else 0.0, clampf(delta / 5.0, 0.0, 1.0))


## 상대가 공격(또는 잡기)을 시작했다
func saw_attack(dir: String) -> void:
	for k in attack_dirs:
		attack_dirs[k] *= MEMORY
	if dir in attack_dirs:
		attack_dirs[dir] += 1.0
	grab_rate *= MEMORY
	feint_rate *= MEMORY


func saw_grab() -> void:
	grab_rate = grab_rate * MEMORY + (1.0 - MEMORY)
	feint_rate *= MEMORY


func saw_feint() -> void:
	feint_rate = feint_rate * MEMORY + (1.0 - MEMORY) * 1.5


## 내 공격이 어떻게 되었나 (상대 쪽 결과: blocked, parried, hit, wrong_guard, dodged ...)
func my_attack_result(dir: String, result: String) -> void:
	if not guarded.has(dir):
		return
	for k in guarded:
		guarded[k][0] *= MEMORY
		guarded[k][1] *= MEMORY
	guarded[dir][1] += 1.0
	if result in ["blocked", "parried"]:
		guarded[dir][0] += 1.0


func block_rate(dir: String) -> float:
	var g: Array = guarded[dir]
	return g[0] / maxf(g[1], 0.01)


## 상대가 전체적으로 얼마나 잘 막나 (0~1)
func guard_skill() -> float:
	var ok := 0.0
	var tries := 0.0
	for k in guarded:
		ok += guarded[k][0]
		tries += guarded[k][1]
	return ok / maxf(tries, 0.01)


## 상대가 다음에 벨 방향 짐작 (자주 쓰는 방향일수록 잘 고른다)
func guess_dir() -> String:
	return _pick(attack_dirs)


## 내가 벨 방향 고르기. 상대가 지금 막고 있는 방향은 피하고, 잘 안 막히는 방향을 고른다.
func choose_dir(current_guard: String) -> String:
	var w := {}
	for k in guarded:
		w[k] = 0.25 + (1.0 - block_rate(k))
		if k == current_guard:
			w[k] *= 0.2
	return _pick(w)


## 잡기를 쓰고 싶은 정도 (0~1): 상대가 많이 막을수록
func grab_urge() -> float:
	return clampf(block_ratio * 0.9 + guard_skill() * 0.35 - 0.1, 0.0, 1.0)


## 속임수를 쓰고 싶은 정도 (0~1): 상대가 잘 막을수록
func feint_urge() -> float:
	return clampf(guard_skill() * 0.9 + block_ratio * 0.3, 0.0, 1.0)


static func _pick(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return weights.keys()[0]
