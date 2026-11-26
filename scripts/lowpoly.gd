class_name LowPoly
extends RefCounted
## 로우폴리 모양을 만드는 도우미 모음.
## 기본 도형(상자, 원기둥, 구 등)을 각진 면(플랫 셰이딩)으로 바꾸고,
## 원하면 꼭짓점을 살짝 흔들어 돌, 나무처럼 자연스러운 모양을 만든다.


## 도형을 각진 면으로 바꾼다. jitter > 0 이면 꼭짓점을 무작위로 흔든다.
static func flat(mesh: Mesh, jitter: float = 0.0, seed_value: int = 0) -> ArrayMesh:
	var arrays: Array = (mesh as PrimitiveMesh).get_mesh_arrays() if mesh is PrimitiveMesh else mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices.resize(verts.size())
		for i in verts.size():
			indices[i] = i

	# 같은 위치의 꼭짓점은 같은 만큼 흔들어야 틈이 생기지 않는다.
	var moved := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var shifted := PackedVector3Array()
	shifted.resize(verts.size())
	for i in verts.size():
		var v := verts[i]
		if jitter > 0.0:
			var key := Vector3i(roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0))
			if not moved.has(key):
				moved[key] = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * jitter
			v += moved[key]
		shifted[i] = v

	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	for t in range(0, indices.size(), 3):
		var ia := indices[t]
		var ib := indices[t + 1]
		var ic := indices[t + 2]
		var a := shifted[ia]
		var b := shifted[ib]
		var c := shifted[ic]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		var orig := normals[ia] + normals[ib] + normals[ic]
		if orig.dot(n) < 0.0:
			n = -n
		out_v.append(a)
		out_v.append(b)
		out_v.append(c)
		out_n.append(n)
		out_n.append(n)
		out_n.append(n)

	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = out_v
	out[Mesh.ARRAY_NORMAL] = out_n
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return result


static func mat(color: Color, roughness: float = 0.85, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


## 각진 도형 하나를 MeshInstance3D 로 만들어 parent 아래에 붙인다.
static func part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO, jitter: float = 0.0, seed_value: int = 0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = flat(mesh, jitter, seed_value)
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func cyl(top: float, bottom: float, height: float, segments: int = 8, rings: int = 1) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = rings
	return m


static func sphere(radius: float, segments: int = 8, rings: int = 5) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = rings
	return m


static func prism(size: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = size
	return m


## node 아래의 각진 도형(MeshInstance3D)들을 재질별로 한 덩어리로 합친다.
## 웹(WebGL) 버전은 그릴 물체가 약 1000개를 넘으면 화면 전체가 안 그려진다.
## 그래서 따로 움직이지 않는 장식은 합쳐서 물체 수를 줄인다.
##   deep: 손자 노드 아래까지 합친다 (false 면 바로 아래 자식만)
##   skip: 합치지 않을 것 (나중에 따로 다루는 것)
## 그림자를 끈 것, 숨긴 것, 자식이 달린 것은 그대로 둔다. 합친 MeshInstance3D 를 돌려준다.
static func merge_children(node: Node3D, deep := true, skip: Array = []) -> MeshInstance3D:
	var groups := {}       # 재질 -> [꼭짓점, 법선]
	var order: Array = []
	var stack: Array = [[node, Transform3D.IDENTITY]]
	var parts: Array = []
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		for c in (it[0] as Node).get_children():
			var n3 := c as Node3D
			if n3 == null:
				continue
			var xf: Transform3D = it[1] * n3.transform
			var mi := c as MeshInstance3D
			if mi != null and mi.mesh != null and mi.get_child_count() == 0 and mi.visible \
					and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and not skip.has(mi) \
					and _plain(mi.mesh):
				parts.append(mi)
				var basis_n := xf.basis.inverse().transposed()
				for s in mi.mesh.get_surface_count():
					var m: Material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(s)
					if not groups.has(m):
						groups[m] = [PackedVector3Array(), PackedVector3Array()]
						order.append(m)
					var arr := mi.mesh.surface_get_arrays(s)
					var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
					var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
					var g: Array = groups[m]
					if idx.is_empty():
						for i in vs.size():
							g[0].append(xf * vs[i])
							g[1].append((basis_n * ns[i]).normalized())
					else:
						for i in idx:
							g[0].append(xf * vs[i])
							g[1].append((basis_n * ns[i]).normalized())
			elif deep and mi == null:
				stack.append([c, xf])
	var out := ArrayMesh.new()
	for m in order:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = groups[m][0]
		a[Mesh.ARRAY_NORMAL] = groups[m][1]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		out.surface_set_material(out.get_surface_count() - 1, m)
	for p in parts:
		p.get_parent().remove_child(p)
		p.free()
	var res := MeshInstance3D.new()
	res.mesh = out
	node.add_child(res)
	return res


## 꼭짓점과 법선만 있는 삼각형 도형인가 (색, 무늬 좌표가 있으면 합치지 않는다)
static func _plain(mesh: Mesh) -> bool:
	for s in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		var arr := mesh.surface_get_arrays(s)
		if arr[Mesh.ARRAY_COLOR] != null or arr[Mesh.ARRAY_TEX_UV] != null:
			return false
	return true
