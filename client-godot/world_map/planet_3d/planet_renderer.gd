class_name PlanetRenderer
extends Node3D
## Dual-Tier Render-Budget Fantasy Planet Renderer (<= 3 Draw Calls at every zoom altitude!).
##
## Level 1-2 (zoom > 0.60): Renders ONLY LocalTerrainPatch (1 Draw Call, 64x64 Floating Origin).
## Crossfade (0.50..0.60): Blends smoothly between LocalTerrainPatch & Global PlanetSurface (2 Draw Calls).
## Level 3-5 (zoom < 0.50): Disables LocalTerrainPatch; renders PlanetSurface + CloudLayer + AtmosphereShell (2-3 Draw Calls).

const PlanetDataScript := preload("res://world_map/core/planet_data.gd")
const PlanetMeshBuilderScript := preload("res://world_map/planet_3d/planet_mesh_builder.gd")
const LocalTerrainPatchScript := preload("res://world_map/planet_3d/local_terrain_patch.gd")

const SURFACE_SHADER := preload("res://world_map/shaders/planet_surface_morph.gdshader")
const ATMOSPHERE_SHADER := preload("res://world_map/shaders/planet_atmosphere.gdshader")
const CLOUDS_SHADER := preload("res://world_map/shaders/planet_clouds.gdshader")

@export var planet_data: Resource
@export var surface_cols: int = 192
@export var surface_rows: int = 96
@export var cloud_cols: int = 64
@export var cloud_rows: int = 32
@export var auto_initialize_default: bool = true

var planet_pivot: Node3D
var surface_mesh_instance: MeshInstance3D
var cloud_mesh_instance: MeshInstance3D
var atmosphere_mesh_instance: MeshInstance3D
var local_terrain_patch: MeshInstance3D

var surface_material: ShaderMaterial
var cloud_material: ShaderMaterial
var atmosphere_material: ShaderMaterial

var _planet_radius: float = 10.0
var _morph_factor: float = 0.0
var _center_lon_deg: float = 0.0
var _lod_atmosphere_alpha: float = 1.0
var _lod_cloud_opacity: float = 0.45
var _lod_detail_strength: float = 1.0
var _lod_fog_opacity: float = 0.38
var _local_patch_alpha: float = 0.0
var _clouds_enabled: bool = true
var _built: bool = false

func _ready() -> void:
	if auto_initialize_default and not _built:
		var data := planet_data
		if data == null and ResourceLoader.exists("res://world_map/resources/fantasy_planet.tres"):
			data = ResourceLoader.load("res://world_map/resources/fantasy_planet.tres")
		if data == null:
			data = PlanetDataScript.new()
		setup(data)

func setup(data: Resource) -> void:
	planet_data = data
	_planet_radius = float(data.get("planet_radius")) if data != null else 10.0
	if _planet_radius <= 0.0:
		_planet_radius = 10.0

	_ensure_nodes()
	_build_meshes_and_materials()
	if data != null and data.has_method("get_all_texture_layers"):
		apply_textures(data.call("get_all_texture_layers"))
	set_morph_factor(_morph_factor)
	set_center_lon_deg(_center_lon_deg)
	_built = true

func _ensure_nodes() -> void:
	if planet_pivot == null:
		planet_pivot = get_node_or_null("PlanetPivot") as Node3D
	if planet_pivot == null:
		planet_pivot = Node3D.new()
		planet_pivot.name = "PlanetPivot"
		add_child(planet_pivot)

	if surface_mesh_instance == null:
		surface_mesh_instance = planet_pivot.get_node_or_null("PlanetSurface") as MeshInstance3D
	if surface_mesh_instance == null:
		surface_mesh_instance = MeshInstance3D.new()
		surface_mesh_instance.name = "PlanetSurface"
		planet_pivot.add_child(surface_mesh_instance)

	if local_terrain_patch == null:
		local_terrain_patch = planet_pivot.get_node_or_null("LocalTerrainPatch") as MeshInstance3D
	if local_terrain_patch == null:
		local_terrain_patch = LocalTerrainPatchScript.new()
		local_terrain_patch.name = "LocalTerrainPatch"
		planet_pivot.add_child(local_terrain_patch)

	if cloud_mesh_instance == null:
		cloud_mesh_instance = planet_pivot.get_node_or_null("CloudLayer") as MeshInstance3D
	if cloud_mesh_instance == null:
		cloud_mesh_instance = MeshInstance3D.new()
		cloud_mesh_instance.name = "CloudLayer"
		cloud_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		planet_pivot.add_child(cloud_mesh_instance)

	if atmosphere_mesh_instance == null:
		atmosphere_mesh_instance = planet_pivot.get_node_or_null("AtmosphereShell") as MeshInstance3D
	if atmosphere_mesh_instance == null:
		atmosphere_mesh_instance = MeshInstance3D.new()
		atmosphere_mesh_instance.name = "AtmosphereShell"
		atmosphere_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		planet_pivot.add_child(atmosphere_mesh_instance)

func _build_meshes_and_materials() -> void:
	surface_mesh_instance.mesh = PlanetMeshBuilderScript.build_morph_grid_mesh(surface_cols, surface_rows, _planet_radius)
	surface_material = ShaderMaterial.new()
	surface_material.shader = SURFACE_SHADER
	surface_material.set_shader_parameter("planet_radius", _planet_radius)
	surface_material.set_shader_parameter("morph_factor", _morph_factor)
	surface_material.set_shader_parameter("center_lon_rad", deg_to_rad(_center_lon_deg))
	surface_mesh_instance.material_override = surface_material

	local_terrain_patch.call("setup", _planet_radius, 64)
	local_terrain_patch.visible = false

	cloud_mesh_instance.mesh = PlanetMeshBuilderScript.build_morph_grid_mesh(cloud_cols, cloud_rows, _planet_radius)
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = CLOUDS_SHADER
	cloud_material.set_shader_parameter("planet_radius", _planet_radius)
	cloud_material.set_shader_parameter("cloud_altitude", _planet_radius * 0.022)
	cloud_material.set_shader_parameter("morph_factor", _morph_factor)
	cloud_material.set_shader_parameter("center_lon_rad", deg_to_rad(_center_lon_deg))
	cloud_material.set_shader_parameter("cloud_opacity", _lod_cloud_opacity)
	cloud_mesh_instance.material_override = cloud_material

	atmosphere_mesh_instance.mesh = PlanetMeshBuilderScript.build_atmosphere_mesh(_planet_radius, 1.052)
	atmosphere_material = ShaderMaterial.new()
	atmosphere_material.shader = ATMOSPHERE_SHADER
	atmosphere_material.set_shader_parameter("atmosphere_alpha", 0.0)
	atmosphere_mesh_instance.material_override = atmosphere_material
	atmosphere_mesh_instance.visible = false

func apply_textures(layers: Dictionary) -> void:
	if surface_material != null:
		if layers.get("albedo", null) != null:
			surface_material.set_shader_parameter("albedo_map", layers["albedo"])
		if layers.get("height", null) != null:
			surface_material.set_shader_parameter("height_map", layers["height"])
		if layers.get("normal", null) != null:
			surface_material.set_shader_parameter("normal_map", layers["normal"])
		if layers.get("biome", null) != null:
			surface_material.set_shader_parameter("biome_map", layers["biome"])
		if layers.get("ocean", null) != null:
			surface_material.set_shader_parameter("ocean_mask", layers["ocean"])
		if layers.get("magic", null) != null:
			surface_material.set_shader_parameter("magic_mask", layers["magic"])
		if layers.get("clouds", null) != null:
			surface_material.set_shader_parameter("cloud_map", layers["clouds"])
	if cloud_material != null and layers.get("clouds", null) != null:
		cloud_material.set_shader_parameter("cloud_map", layers["clouds"])
	if local_terrain_patch != null:
		local_terrain_patch.call("apply_textures", layers)

func apply_fog_masks(local_fog_tex: Texture2D, global_fog_tex: Texture2D, local_bounds: Vector4) -> void:
	if surface_material != null and global_fog_tex != null:
		surface_material.set_shader_parameter("global_fog_mask", global_fog_tex)
		surface_material.set_shader_parameter("use_fog_mask", 1.0)
	if local_terrain_patch != null:
		local_terrain_patch.call("apply_fog", local_fog_tex, global_fog_tex, local_bounds)

func apply_terrain_splat(splat_tex: Texture2D, splat_bounds: Vector4, tile_deg_size: float = 0.06) -> void:
	if local_terrain_patch != null and local_terrain_patch.has_method("apply_terrain_splat"):
		local_terrain_patch.call("apply_terrain_splat", splat_tex, splat_bounds, tile_deg_size)

func get_planet_radius() -> float:
	return _planet_radius

func get_morph_factor() -> float:
	return _morph_factor

func set_morph_factor(morph: float) -> void:
	_morph_factor = clampf(morph, 0.0, 1.0)
	if surface_material != null:
		surface_material.set_shader_parameter("morph_factor", _morph_factor)
	if cloud_material != null:
		cloud_material.set_shader_parameter("morph_factor", _morph_factor)
	_sync_atmosphere_visibility()

func set_center_lon_deg(lon_deg: float) -> void:
	_center_lon_deg = lon_deg
	var rad := deg_to_rad(lon_deg)
	if surface_material != null:
		surface_material.set_shader_parameter("center_lon_rad", rad)
	if cloud_material != null:
		cloud_material.set_shader_parameter("center_lon_rad", rad)

func set_lod_params(
	normal_strength: float,
	magic_strength: float,
	cloud_opacity: float,
	atmosphere_alpha: float,
	detail_strength: float = 0.0,
	fog_opacity: float = 0.38
) -> void:
	_lod_cloud_opacity = clampf(cloud_opacity, 0.0, 1.0)
	_lod_atmosphere_alpha = clampf(atmosphere_alpha, 0.0, 1.0)
	_lod_detail_strength = clampf(detail_strength, 0.0, 1.0)
	_lod_fog_opacity = clampf(fog_opacity, 0.0, 1.0)
	if surface_material != null:
		surface_material.set_shader_parameter("normal_strength", normal_strength)
		surface_material.set_shader_parameter("magic_strength", magic_strength)
		surface_material.set_shader_parameter("fog_opacity", _lod_fog_opacity)
	if cloud_material != null:
		cloud_material.set_shader_parameter("cloud_opacity", _lod_cloud_opacity)
	_sync_render_budget_visibility()

## Strict Render-Budget sync called by WorldMap3D / CameraController on every view update.
func sync_local_clipmap(focus_lat: float, focus_lon: float, flat_altitude: float, fov_deg: float, zoom_level: float) -> void:
	# Crossfade between LocalTerrainPatch and Global PlanetSurface across zoom [0.50 .. 0.60]
	var raw := clampf((zoom_level - 0.50) / 0.10, 0.0, 1.0)
	_local_patch_alpha = raw * raw * (3.0 - 2.0 * raw)
	if _morph_factor > 0.02:
		_local_patch_alpha = 0.0

	if local_terrain_patch != null:
		local_terrain_patch.call(
			"sync_to_camera",
			focus_lat,
			focus_lon,
			flat_altitude,
			fov_deg,
			_local_patch_alpha,
			_lod_detail_strength,
			_lod_fog_opacity
		)
	_sync_render_budget_visibility()

func get_active_draw_call_count() -> int:
	var count := 0
	if surface_mesh_instance != null and surface_mesh_instance.visible: count += 1
	if local_terrain_patch != null and local_terrain_patch.visible: count += 1
	if cloud_mesh_instance != null and cloud_mesh_instance.visible: count += 1
	if atmosphere_mesh_instance != null and atmosphere_mesh_instance.visible: count += 1
	return count

func set_sun_direction(dir: Vector3) -> void:
	if atmosphere_material != null and dir.length_squared() > 1e-6:
		atmosphere_material.set_shader_parameter("sun_direction", dir.normalized())

func set_clouds_enabled(enabled: bool) -> void:
	_clouds_enabled = enabled
	_sync_render_budget_visibility()

func _sync_render_budget_visibility() -> void:
	# When LocalTerrainPatch is 100% opaque (Level 1-2), cull Global PlanetSurface & Orbital Clouds!
	var local_opaque := _local_patch_alpha >= 0.995
	if surface_mesh_instance != null:
		surface_mesh_instance.visible = not local_opaque
	if cloud_mesh_instance != null:
		cloud_mesh_instance.visible = _clouds_enabled and (not local_opaque) and (_lod_cloud_opacity > 0.01)
	_sync_atmosphere_visibility()

func _sync_atmosphere_visibility() -> void:
	if atmosphere_mesh_instance == null or atmosphere_material == null:
		return
	var morph_fade := clampf((_morph_factor - 0.45) / 0.50, 0.0, 1.0)
	var eff_alpha := morph_fade * morph_fade * _lod_atmosphere_alpha
	atmosphere_material.set_shader_parameter("atmosphere_alpha", eff_alpha)
	atmosphere_mesh_instance.visible = eff_alpha > 0.01 and _local_patch_alpha < 0.995
