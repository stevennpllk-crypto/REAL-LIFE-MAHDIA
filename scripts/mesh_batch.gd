extends RefCounted
class_name MahdiaMeshBatch

# Collects many small procedural shapes into one mesh surface per material.
# One MeshInstance3D per material instead of one node per box keeps the draw
# call count low on phones while allowing far denser facade and prop detail.

var tools: Dictionary = {}
var materials: Dictionary = {}

func _tool(key: String, material: Material) -> SurfaceTool:
	if not tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[key] = st
		materials[key] = material
	return tools[key] as SurfaceTool

func is_empty() -> bool:
	return tools.is_empty()

# Adds one triangle; the winding is chosen from the supplied normals so callers
# never have to think about Godot's clockwise front-face convention.
func tri(key: String, material: Material, p: Array, n: Array, uv: Array, color := Color.WHITE) -> void:
	var st := _tool(key, material)
	var a: Vector3 = p[0]
	var b: Vector3 = p[1]
	var c: Vector3 = p[2]
	var avg: Vector3 = (n[0] as Vector3) + (n[1] as Vector3) + (n[2] as Vector3)
	var order := [0, 1, 2]
	if (b - a).cross(c - a).dot(avg) > 0.0:
		order = [0, 2, 1]
	for i in order:
		st.set_color(color)
		st.set_normal(n[i])
		st.set_uv(uv[i])
		st.add_vertex(p[i])

func quad(key: String, material: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, uv_size := Vector2.ONE, color := Color.WHITE) -> void:
	var uv0 := Vector2(0, 0)
	var uv1 := Vector2(uv_size.x, 0)
	var uv2 := Vector2(uv_size.x, uv_size.y)
	var uv3 := Vector2(0, uv_size.y)
	tri(key, material, [a, b, c], [normal, normal, normal], [uv0, uv1, uv2], color)
	tri(key, material, [a, c, d], [normal, normal, normal], [uv0, uv2, uv3], color)

func box(key: String, material: Material, xf: Transform3D, size: Vector3, skip_bottom := false, color := Color.WHITE) -> void:
	var h := size * 0.5
	for n in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]:
		if skip_bottom and n == Vector3.DOWN:
			continue
		var an: Vector3 = (n as Vector3).abs()
		var u := Vector3(an.y, an.z, an.x)
		var v := an.cross(u).abs()
		var center: Vector3 = n * h.dot(an)
		var eu := u * h.dot(u)
		var ev := v * h.dot(v)
		var world_n: Vector3 = (xf.basis * n).normalized()
		quad(key, material, xf * (center - eu - ev), xf * (center + eu - ev), xf * (center + eu + ev), xf * (center - eu + ev), world_n, Vector2(size.dot(u), size.dot(v)), color)

# Surface of revolution around the local Y axis. profile holds (radius, y).
func lathe(key: String, material: Material, xf: Transform3D, profile: PackedVector2Array, segments: int, color := Color.WHITE) -> void:
	var count := profile.size()
	var normals2: Array[Vector2] = []
	for i in range(count):
		var prev := profile[maxi(i - 1, 0)]
		var next := profile[mini(i + 1, count - 1)]
		var t := next - prev
		var n2 := Vector2(t.y, -t.x).normalized()
		if n2.x < 0.0:
			n2 = -n2
		normals2.append(n2)
	for s in range(segments):
		var a0 := TAU * float(s) / float(segments)
		var a1 := TAU * float(s + 1) / float(segments)
		for i in range(count - 1):
			var r0 := profile[i]
			var r1 := profile[i + 1]
			var p00 := Vector3(cos(a0) * r0.x, r0.y, sin(a0) * r0.x)
			var p01 := Vector3(cos(a1) * r0.x, r0.y, sin(a1) * r0.x)
			var p10 := Vector3(cos(a0) * r1.x, r1.y, sin(a0) * r1.x)
			var p11 := Vector3(cos(a1) * r1.x, r1.y, sin(a1) * r1.x)
			var n0 := normals2[i]
			var n1 := normals2[i + 1]
			var n00 := Vector3(cos(a0) * n0.x, n0.y, sin(a0) * n0.x)
			var n01 := Vector3(cos(a1) * n0.x, n0.y, sin(a1) * n0.x)
			var n10 := Vector3(cos(a0) * n1.x, n1.y, sin(a0) * n1.x)
			var n11 := Vector3(cos(a1) * n1.x, n1.y, sin(a1) * n1.x)
			var b := xf.basis
			var u0 := float(s) / float(segments)
			var u1 := float(s + 1) / float(segments)
			if r0.x > 0.0001 or r1.x > 0.0001:
				tri(key, material, [xf * p00, xf * p10, xf * p11], [(b * n00).normalized(), (b * n10).normalized(), (b * n11).normalized()], [Vector2(u0, r0.y), Vector2(u0, r1.y), Vector2(u1, r1.y)], color)
				tri(key, material, [xf * p00, xf * p11, xf * p01], [(b * n00).normalized(), (b * n11).normalized(), (b * n01).normalized()], [Vector2(u0, r0.y), Vector2(u1, r1.y), Vector2(u1, r0.y)], color)

# A tube that follows a path (palm trunks, lamp arms). radii matches points.
func tube(key: String, material: Material, points: Array[Vector3], radii: Array[float], segments: int, color := Color.WHITE) -> void:
	var rings: Array = []
	var ring_normals: Array = []
	for i in range(points.size()):
		var prev: Vector3 = points[maxi(i - 1, 0)]
		var next: Vector3 = points[mini(i + 1, points.size() - 1)]
		var forward := (next - prev).normalized()
		var side := forward.cross(Vector3.FORWARD if absf(forward.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var up := side.cross(forward).normalized()
		var ring: Array[Vector3] = []
		var normals: Array[Vector3] = []
		for s in range(segments + 1):
			var a := TAU * float(s) / float(segments)
			var dir := side * cos(a) + up * sin(a)
			ring.append(points[i] + dir * radii[i])
			normals.append(dir)
		rings.append(ring)
		ring_normals.append(normals)
	for i in range(points.size() - 1):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		var n0: Array = ring_normals[i]
		var n1: Array = ring_normals[i + 1]
		for s in range(segments):
			var v0 := float(i) / float(points.size() - 1)
			var v1 := float(i + 1) / float(points.size() - 1)
			var u0 := float(s) / float(segments)
			var u1 := float(s + 1) / float(segments)
			tri(key, material, [r0[s], r1[s], r1[s + 1]], [n0[s], n1[s], n1[s + 1]], [Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1)], color)
			tri(key, material, [r0[s], r1[s + 1], r0[s + 1]], [n0[s], n1[s + 1], n0[s + 1]], [Vector2(u0, v0), Vector2(u1, v1), Vector2(u1, v0)], color)

# Extrudes a closed 2D outline (x = local Z, y = local Y) across local X.
# Used for car bodies and the fortress gate arch.
func extrude_profile(key: String, material: Material, xf: Transform3D, outline: PackedVector2Array, width: float, color := Color.WHITE, side_key := "", side_material: Material = null) -> void:
	var hw := width * 0.5
	var cap_key := key if side_key.is_empty() else side_key
	var cap_material := material if side_material == null else side_material
	var tris := Geometry2D.triangulate_polygon(outline)
	for side in [-1.0, 1.0]:
		var normal: Vector3 = (xf.basis * Vector3(side, 0, 0)).normalized()
		for t in range(0, tris.size(), 3):
			var pts: Array = []
			var uvs: Array = []
			for k in range(3):
				var q := outline[tris[t + k]]
				pts.append(xf * Vector3(side * hw, q.y, q.x))
				uvs.append(Vector2(q.x, q.y))
			tri(cap_key, cap_material, pts, [normal, normal, normal], uvs, color)
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var edge := b - a
		var n2 := Vector2(edge.y, -edge.x).normalized()
		# Make the edge normal point away from the polygon centre.
		var centre := Vector2.ZERO
		for q in outline:
			centre += q
		centre /= float(outline.size())
		if n2.dot((a + b) * 0.5 - centre) < 0.0:
			n2 = -n2
		var normal: Vector3 = (xf.basis * Vector3(0, n2.y, n2.x)).normalized()
		quad(key, material, xf * Vector3(-hw, a.y, a.x), xf * Vector3(hw, a.y, a.x), xf * Vector3(hw, b.y, b.x), xf * Vector3(-hw, b.y, b.x), normal, Vector2(width, edge.length()), color)

func commit_mesh(generate_tangents := true) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key in tools.keys():
		var st: SurfaceTool = tools[key]
		if generate_tangents:
			st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[key])
	return mesh

# One MeshInstance3D per material key, so callers can treat them separately
# (e.g. shadow casting or draw-distance LOD for small facade details).
func commit_instances(parent: Node3D, generate_tangents := true) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for key in tools.keys():
		var st: SurfaceTool = tools[key]
		if generate_tangents:
			st.generate_tangents()
		var mesh := st.commit()
		var item := MeshInstance3D.new()
		item.name = "Batch_" + str(key)
		item.mesh = mesh
		item.material_override = materials[key]
		parent.add_child(item)
		out.append(item)
	return out
