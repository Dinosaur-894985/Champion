class_name Records
extends RefCounted
## 전적: AI 와 싸운 결과를 무기별·난이도별로 모아 기록 파일(scripts/progress.gd)에 저장한다.
##   weapons: {무기: [이긴 수, 진 수]}   diffs: {난이도: [이긴 수, 진 수]}
##   streak: 지금 연승(진 뒤로는 0)       best_streak: 가장 긴 연승
##   fastest: {난이도: 가장 빨리 이긴 시간(초)}
##   chars: {저장 칸 번호(글자): [이긴 수, 진 수]}  (캐릭터 3개 저장. 칸을 지우면 그 칸 전적도 지운다)

const SECTION := "record"
const KEY := "data"


static func load_all() -> Dictionary:
	var d: Variant = Progress.get_value(SECTION, KEY, {})
	var out: Dictionary = d if d is Dictionary else {}
	for k in ["weapons", "diffs", "fastest", "chars"]:
		if not out.get(k) is Dictionary:
			out[k] = {}
	out["streak"] = int(out.get("streak", 0))
	out["best_streak"] = int(out.get("best_streak", 0))
	return out


## 한 판 결과를 더하고 저장한다. 결과 화면에 쓸 요약을 돌려준다.
## slot: 내 캐릭터 저장 칸 (-1 이면 캐릭터 전적은 남기지 않는다)
static func add_result(weapon: String, difficulty: String, won: bool, seconds: float, slot := -1) -> Dictionary:
	var r := load_all()
	var cr: Array = r.chars.get(str(slot), [0, 0])
	var wr: Array = r.weapons.get(weapon, [0, 0])
	var dr: Array = r.diffs.get(difficulty, [0, 0])
	var i := 0 if won else 1
	wr[i] = int(wr[i]) + 1
	dr[i] = int(dr[i]) + 1
	r.weapons[weapon] = wr
	r.diffs[difficulty] = dr
	if slot >= 0:
		cr[i] = int(cr[i]) + 1
		r.chars[str(slot)] = cr
	var new_fastest := false
	if won:
		r.streak += 1
		r.best_streak = maxi(r.best_streak, r.streak)
		var best := float(r.fastest.get(difficulty, 0.0))
		if best <= 0.0 or seconds < best:
			# 첫 승은 기록만 하고 '새 기록'이라고 하진 않는다
			new_fastest = best > 0.0
			r.fastest[difficulty] = snappedf(seconds, 0.1)
	else:
		r.streak = 0
	Progress.set_value(SECTION, KEY, r)
	return {"weapon": wr, "diff": dr, "char": cr if slot >= 0 else [], "streak": r.streak, "best_streak": r.best_streak,
		"new_fastest": new_fastest, "fastest": float(r.fastest.get(difficulty, 0.0))}


## 캐릭터 칸을 지웠을 때 그 칸 전적도 지운다 (새 캐릭터가 이어받지 않게)
static func forget_character(slot: int) -> void:
	var r := load_all()
	if r.chars.has(str(slot)):
		r.chars.erase(str(slot))
		Progress.set_value(SECTION, KEY, r)


## [이긴 수, 진 수] 의 합계
static func totals(r: Dictionary) -> Vector2i:
	var t := Vector2i.ZERO
	for v in r.weapons.values():
		t += Vector2i(int(v[0]), int(v[1]))
	return t


## "7승 3패 · 70%"
static func line(rec: Array) -> String:
	var w := int(rec[0])
	var l := int(rec[1])
	if w + l == 0:
		return "기록 없음"
	return "%d승 %d패 · %d%%" % [w, l, roundi(100.0 * w / float(w + l))]


## 0:42 처럼
static func clock(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
