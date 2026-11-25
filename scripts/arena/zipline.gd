class_name Zipline
extends Node3D
## 짚라인: 높은 곳(a)에서 낮은 곳(b)으로 이어진 줄. 공중에서 줄에 손이 닿으면 매달려 미끄러져 내려간다.
## 타는 쪽(플레이어/AI)이 매달리기와 내리기를 직접 처리하고, 여기서는 줄의 모양과 위치 계산만 한다.

const SPEED := 13.0          # 미끄러지는 빠르기 (m/초)
const HANG := 2.05           # 줄에서 발까지 거리
const GRAB_DIST := 1.0       # 손(발 위 HANG 높이)이 줄에서 이만큼 가까우면 잡는다

var id := ""
var a := Vector3.ZERO        # 높은 쪽 끝
var b := Vector3.ZERO        # 낮은 쪽 끝
var alive := true
var rider_count := 0


func setup(zip_id: String, from: Vector3, to: Vector3, mats: Dictionary) -> void:
	id = zip_id
	a = from
	b = to
	# 줄
	var cable := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.05, 0.05, 1.0)
	cable.mesh = m
	cable.material_override = mats.navy
	cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cable)
	var mid := (a + b) * 0.5
	cable.global_transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), mid)
	cable.scale = Vector3(1, 1, a.distance_to(b))
	# 양 끝 기둥 (줄을 거는 문 모양)
	for end in [a, b]:
		var p: Vector3 = end
		var post_h := HANG + 0.5
		var side := (b - a)
		side.y = 0
		side = Vector3(-side.z, 0, side.x).normalized()
		for s in [-1.0, 1.0]:
			LowPoly.part(self, LowPoly.box(Vector3(0.16, post_h, 0.16)), mats.navy,
					p + side * s * 0.7 + Vector3.DOWN * (post_h * 0.5 - 0.35))
		var beam := LowPoly.part(self, LowPoly.box(Vector3(1.6, 0.14, 0.16)), mats.coral, p + Vector3.UP * 0.32)
		beam.basis = Basis(side, Vector3.UP, side.cross(Vector3.UP)).orthonormalized()
		LowPoly.part(self, LowPoly.cyl(0.12, 0.12, 0.1, 8), mats.gold, p + Vector3.UP * 0.12, Vector3(90, 0, 0))
	# 줄을 따라 작은 깃발 (멀리서도 줄이 보이게)
	var n := int(a.distance_to(b) / 3.0)
	for i in range(1, n):
		var t := float(i) / n
		var q := a.lerp(b, t)
		var flag := LowPoly.part(self, LowPoly.prism(Vector3(0.3, 0.32, 0.02)), mats.coral if i % 2 == 0 else mats.gold,
				q + Vector3.DOWN * 0.2, Vector3(0, 0, 180))
		flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func length() -> float:
	return a.distance_to(b)


func dir() -> Vector3:
	return (b - a).normalized()


func closest_t(p: Vector3) -> float:
	var ab := b - a
	return clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)


func point(t: float) -> Vector3:
	return a.lerp(b, t)


## 발 위치 feet 의 손이 줄에 닿나. 닿으면 줄 위 위치(0~1), 아니면 -1
func grab_t(feet: Vector3) -> float:
	if not alive:
		return -1.0
	var hands := feet + Vector3.UP * HANG
	var t := closest_t(hands)
	if t > 0.93:
		return -1.0
	if point(t).distance_to(hands) <= GRAB_DIST:
		return t
	return -1.0


## 줄 위 위치 t 에 매달린 몸의 발 위치
func feet_at(t: float) -> Vector3:
	return point(t) + Vector3.DOWN * HANG


func remove() -> void:
	alive = false
	var tw := create_tween()
	tw.tween_property(self, "position:y", -40.0, 2.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(queue_free)
