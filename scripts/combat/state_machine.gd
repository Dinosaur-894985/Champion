class_name StateMachine
extends RefCounted
## 행동 상태 기계.
## 캐릭터가 지금 무엇을 하는지(가만히, 공격, 모으기, 대시, 막기, 경직...)를 한 곳에서 관리한다.
## 상태마다 "들어갈 때 / 매 프레임 / 나갈 때" 할 일을 등록해 두면,
## 새 동작을 넣을 때 다른 동작 코드를 건드리지 않고 상태 하나만 추가하면 된다.
##
##   sm.add("dash", _dash_enter, _dash_update, _dash_exit)
##   sm.go("dash", {"dir": Vector3.LEFT})

signal changed(from: String, to: String)

var state := ""
var time := 0.0                 # 지금 상태에 들어온 뒤 지난 시간
var counts := {}                # 점검용: 상태마다 들어간 횟수
var _states := {}


func add(state_name: String, enter: Callable = Callable(), update: Callable = Callable(),
		exit: Callable = Callable()) -> StateMachine:
	_states[state_name] = {"enter": enter, "update": update, "exit": exit}
	return self


func go(state_name: String, data: Dictionary = {}) -> void:
	assert(_states.has(state_name), "없는 상태: " + state_name)
	var prev := state
	if _states.has(prev):
		var ex: Callable = _states[prev].exit
		if ex.is_valid():
			ex.call()
	state = state_name
	time = 0.0
	counts[state_name] = counts.get(state_name, 0) + 1
	var en: Callable = _states[state_name].enter
	if en.is_valid():
		en.call(data)
	changed.emit(prev, state_name)


func tick(delta: float) -> void:
	time += delta
	if not _states.has(state):
		return
	var up: Callable = _states[state].update
	if up.is_valid():
		up.call(delta)


func is_in(names: Array) -> bool:
	return state in names
