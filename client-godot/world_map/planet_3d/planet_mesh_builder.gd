class_name PlanetMeshBuilder
extends RefCounted
## Procedural mesh builder for the morphable equirectangular planet grid and atmosphere shell.

## Builds an indexed GridMesh with UV in [0, 1]^2 and generous custom AABB
## so vertex-shader morphing from flat plane to 3D sphere is never frustum-culled.
static func build_morph_grid_mesh(cols: int = 192, rows: int = 96, planet_radius: float = 10.0) -> ArrayMesh:
	var seg_x := maxi(8, cols)
	var seg_y := maxi(4, rows)
	var vert_x := seg_x + 1
	var vert_y := seg_y + 1
	var vert_count := vert_x * vert_y

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	verts.resize(vert_count)
	normals.resize(vert_count)
	tangents.resize(vert_count * 4)
	uvs.resize(vert_count)

	var idx := 0
	for iy in range(vert_y):
		var v := float(iy) / float(seg_y)
		var lat := (0.5 - v) * PI
		var z := -planet_radius * lat
		for ix in range(vert_x):
			var u := float(ix) / float(seg_x)
			var lon := (u - 0.5) * TAU
			var x := planet_radius * lon

			verts[idx] = Vector3(x, planet_radius, z)
			normals[idx] = Vector3.UP
			var t4 := idx * 4
			tangents[t4] = 1.0
			tangents[t4 + 1] = 0.0
			tangents[t4 + 2] = 0.0
			tangents[t4 + 3] = 1.0
			uvs[idx] = Vector2(u, v)
			idx += 1

	var indices := PackedInt32Array()
	indices.resize(seg_x * seg_y * 6)
	var ptr := 0
	for iy in range(seg_y):
		var row0 := iy * vert_x
		var row1 := (iy + 1) * vert_x
		for ix in range(seg_x):
			var a := row0 + ix
			var b := row0 + ix + 1
			var c := row1 + ix
			var d := row1 + ix + 1
			# Front-facing (+Y normal in Godot clockwise winding viewed from +Y)
			indices[ptr] = a
			indices[ptr + 1] = b
			indices[ptr + 2] = d
			indices[ptr + 3] = a
			indices[ptr + 4] = d
			indices[ptr + 5] = c
			ptr += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Encompass both full flat map (+/- PI*R, +R, +/- 0.5*PI*R) and full 3D sphere (+/- R)
	var half_x := planet_radius * PI + 2.0
	var half_y := planet_radius * 1.6 + 2.0
	var half_z := planet_radius * (PI * 0.5) + 2.0
	mesh.custom_aabb = AABB(
		Vector3(-half_x, -half_y, -half_z),
		Vector3(half_x * 2.0, half_y * 2.0, half_z * 2.0)
	)
	return mesh

static func build_atmosphere_mesh(planet_radius: float = 10.0, scale_mult: float = 1.052) -> SphereMesh:
	var sphere := SphereMesh.new()
	var r := planet_radius * scale_mult
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	return sphere
