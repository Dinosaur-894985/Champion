class_name ArenaPickup
extends Node3D
## 높은 곳에 생기는 아이템. 빛기둥이 솟아서 멀리서도 보인다. 가까이 가면 먹는다.
## 종류와 효과는 VerticalKit.PICKUPS 에 있다.

var kind := "heal"
var spot := {}
var taken := false
var _gem: Node3D
var _beam: MeshInstance3D
var _t := 0.0


func setup(pickup_kind: String, spot_info: Dictionary) -> void:
	kind = pickup_kind
	spot = spot_info
	position = spot_info.pos
	var color: Color = VerticalKit.PICKUPS[kind].color
	var gem_mat := StandardMaterial3D.new()
	gem_mat.albedo_color = color
	gem_mat.emission_enabled = true
	gem_mat.emission = color
	gem_mat.emission_energy_multiplier = 1.4
	gem_mat.roughness = 0.3
	_gem = Node3D.new()
	_gem.position.y = 1.0
	add_child(_gem)
	var g := LowPoly.part(_gem, LowPoly.sphere(0.3, 6, 3), gem_mat, Vector3.ZERO, Vector3.ZERO, 0.0)
	g.scale = Vector3(1.0, 1.4, 1.0)
	# 받침: 둥근 판
	var base_mat := LowPoly.mat(Color(0.95, 0.74, 0.30), 0.45, 0.35)
	LowPoly.part(self, LowPoly.cyl(0.55, 0.6, 0.08, 8), base_mat, Vector3(0, 0.04, 0))
	# 빛기둥
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(color.r, color.g, color.b, 0.28)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam = MeshInstance3D.new()
	_beam.mesh = LowPoly.cyl(0.32, 0.32, 16.0, 6)
	_beam.material_override = bm
	_beam.position.y = 8.0
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	scale = Vector3.ONE * 0.01
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	_gem.rotation.y += delta * 2.0
	_gem.position.y = 1.0 + sin(_t * 3.0) * 0.12


## 먹었을 때: 반짝이며 사라진다
func collect() -> void:
	taken = true
	Fx.sparks(get_parent(), global_position + Vector3.UP, Vector3.UP, 30, VerticalKit.PICKUPS[kind].color)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 0.01, 0.2)
	tw.tween_callback(queue_free)
