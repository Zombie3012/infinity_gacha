class_name LocalTerrainPatch
extends MeshInstance3D
## Single Floating-Origin 64x64 Clipmap Mesh (1 Draw Call) for Solar-Scale Level 1-2 views.
## Dynamically scales to cover 1.48x the current camera frustum, binding 512x512 seamless ground detail
## albedo/normal textures, server Terrain Splatting, and dual-resolution Soft Cloud Fog-of-War.

const LOCAL_PATCH_SHADER := preload("res://world_map/shaders/local_terrain_patch.gdshader")
const DETAIL_ALBEDO_PATH := "res://world_map/textures/fantasy_planet/ground_detail_albedo.png"
const DETAIL_NORMAL_PATH := "res://world_map/textures/fantasy_planet/ground_detail_normal.png"

var patch_material: ShaderMaterial
var _planet_radius: float = 10.0

func setup(planet_radius: float = 10.0, grid_subdiv: int = 64) -> void:
	_planet_radius = maxf(1.0, planet_radius)
	mesh = _build_unit_grid_mesh(grid_subdiv)
	patch_material = ShaderMaterial.new()
	patch_material.shader = LOCAL_PATCH_SHADER
	patch_material.set_shader_parameter("planet_radius", _planet_radius)
	patch_material.set_shader_parameter("patch_alpha", 1.0)
	material_override = patch_material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bind_ground_detail_textures()

func _load_tex(res_path: String) -> Texture2D:
	if ResourceLoader.exists(res_path):
		var loaded := ResourceLoader.load(res_path)
		if loaded is Texture2D:
			return loaded
	var abs_p := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_p):
		var img := Image.load_from_file(abs_p)
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	return null

func _bind_ground_detail_textures() -> void:
	if patch_material == null:
		return
	var da := _load_tex(DETAIL_ALBEDO_PATH)
	var dn := _load_tex(DETAIL_NORMAL_PATH)
	if da != null:
		patch_material.set_shader_parameter("ground_detail_albedo", da)
	if dn != null:
		patch_material.set_shader_parameter("ground_detail_normal", dn)

func apply_textures(layers: Dictionary) -> void:
	if patch_material == null:
		return
	if layers.get("albedo", null) != null:
		patch_material.set_shader_parameter("albedo_map", layers["albedo"])
	if layers.get("height", null) != null:
		patch_material.set_shader_parameter("height_map", layers["height"])
	if layers.get("biome", null) != null:
		patch_material.set_shader_parameter("biome_map", layers["biome"])
	if layers.get("ocean", null) != null:
		patch_material.set_shader_parameter("ocean_mask", layers["ocean"])
	if layers.get("magic", null) != null:
		patch_material.set_shader_parameter("magic_mask", layers["magic"])
	_bind_ground_detail_textures()

func apply_fog(local_fog_tex: Texture2D, global_fog_tex: Texture2D, local_bounds: Vector4) -> void:
	if patch_material == null:
		return
	if local_fog_tex != null:
		patch_material.set_shader_parameter("local_fog_mask", local_fog_tex)
	if global_fog_tex != null:
		patch_material.set_shader_parameter("global_fog_mask", global_fog_tex)
	patch_material.set_shader_parameter("local_fog_bounds", local_bounds)

func apply_terrain_splat(splat_tex: Texture2D, splat_bounds: Vector4, tile_deg_size: float = 0.06) -> void:
	if patch_material == null:
		return
	if splat_tex != null:
		patch_material.set_shader_parameter("terrain_splat_map", splat_tex)
		patch_material.set_shader_parameter("terrain_splat_bounds", splat_bounds)
		patch_material.set_shader_parameter("tile_deg_size", maxf(0.005, tile_deg_size))
		patch_material.set_shader_parameter("use_terrain_splat", 1.0)

func sync_to_camera(
	focus_lat_deg: float,
	focus_lon_deg: float,
	flat_altitude: float,
	fov_deg: float,
	patch_alpha: float,
	detail_strength: float,
	fog_opacity: float
) -> void:
	var active := patch_alpha > 0.01
	visible = active
	if not active or patch_material == null:
		return

	var lat_rad := deg_to_rad(focus_lat_deg)
	var lon_rad := deg_to_rad(focus_lon_deg)
	position = Vector3(0.0, _planet_radius + 0.0010, -_planet_radius * lat_rad)

	var half_z := maxf(0.04, flat_altitude * tan(deg_to_rad(fov_deg * 0.5)) * 1.85)
	var half_x := half_z * 2.15
	patch_material.set_shader_parameter("focus_lat_rad", lat_rad)
	patch_material.set_shader_parameter("focus_lon_rad", lon_rad)
	patch_material.set_shader_parameter("patch_half_x", half_x)
	patch_material.set_shader_parameter("patch_half_z", half_z)
	patch_material.set_shader_parameter("patch_alpha", clampf(patch_alpha, 0.0, 1.0))
	patch_material.set_shader_parameter("detail_strength", clampf(detail_strength, 0.0, 1.0))
	patch_material.set_shader_parameter("fog_opacity", clampf(fog_opacity, 0.0, 1.0))

static func _build_unit_grid_mesh(subdiv: int) -> ArrayMesh:
	var seg := maxi(8, subdiv)
	var stride := seg + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	verts.resize(stride * stride)
	normals.resize(stride * stride)
	tangents.resize(stride * stride * 4)
	uvs.resize(stride * stride)

	var idx := 0
	for iz in range(stride):
		var v := float(iz) / float(seg)
		var pz := lerpf(-1.0, 1.0, v)
		for ix in range(stride):
			var u := float(ix) / float(seg)
			var px := lerpf(-1.0, 1.0, u)
			verts[idx] = Vector3(px, 0.0, pz)
			normals[idx] = Vector3.UP
			var t4 := idx * 4
			tangents[t4] = 1.0
			tangents[t4 + 1] = 0.0
			tangents[t4 + 2] = 0.0
			tangents[t4 + 3] = 1.0
			uvs[idx] = Vector2(u, v)
			idx += 1

	var indices := PackedInt32Array()
	indices.resize(seg * seg * 6)
	var ptr := 0
	for iz in range(seg):
		var r0 := iz * stride
		var r1 := (iz + 1) * stride
		for ix in range(seg):
			var a := r0 + ix
			var b := r0 + ix + 1
			var c := r1 + ix
			var d := r1 + ix + 1
			indices[ptr] = a; indices[ptr + 1] = b; indices[ptr + 2] = d
			indices[ptr + 3] = a; indices[ptr + 4] = d; indices[ptr + 5] = c
			ptr += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.custom_aabb = AABB(Vector3(-40.0, -2.0, -40.0), Vector3(80.0, 4.0, 80.0))
	return m
