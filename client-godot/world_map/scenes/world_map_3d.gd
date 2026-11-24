class_name WorldMap3D
extends Node3D
## Reusable 3D Fantasy Planet World Scene (hosted in SubViewport by WorldRtsMap or standalone preview).
## Owns WorldEnvironment (Starfield Sky), Sun/Fill lights, PlanetRenderer, Camera3D,
## PlanetCameraController, and PlanetLODController.

const PlanetDataScript := preload("res://world_map/core/planet_data.gd")
const PlanetRendererScript := preload("res://world_map/planet_3d/planet_renderer.gd")
const PlanetCameraControllerScript := preload("res://world_map/planet_3d/planet_camera_controller.gd")
const PlanetLODControllerScript := preload("res://world_map/planet_3d/planet_lod_controller.gd")
const PlanetMarkerSystemScript := preload("res://world_map/planet_3d/planet_marker_system.gd")
const TacticalGroundPropsScript := preload("res://world_map/planet_3d/tactical_ground_props.gd")
const STARFIELD_SKY_SHADER := preload("res://world_map/shaders/starfield_sky.gdshader")

var planet_data: Resource
var world_env: WorldEnvironment
var sun_light: DirectionalLight3D
var fill_light: DirectionalLight3D
var planet_renderer: Node3D
var marker_system: Node3D
var tactical_props: Node3D
var camera: Camera3D
var camera_controller: Node
var lod_controller: Node

var _initialized := false
var external_camera_step := false

func _ready() -> void:
	if not _initialized:
		initialize_world()

func initialize_world(data: Resource = null) -> void:
	if _initialized:
		return
	planet_data = data
	if planet_data == null and ResourceLoader.exists("res://world_map/resources/fantasy_planet.tres"):
		planet_data = ResourceLoader.load("res://world_map/resources/fantasy_planet.tres")
	if planet_data == null:
		planet_data = PlanetDataScript.new()
	if planet_data.has_method("ensure_regions_loaded"):
		planet_data.call("ensure_regions_loaded")

	_setup_environment_and_lights()

	planet_renderer = PlanetRendererScript.new()
	planet_renderer.name = "PlanetRenderer"
	planet_renderer.set("auto_initialize_default", false)
	add_child(planet_renderer)
	planet_renderer.call("setup", planet_data)

	var r: float = float(planet_renderer.call("get_planet_radius"))
	marker_system = PlanetMarkerSystemScript.new()
	marker_system.name = "PlanetMarkerSystem"
	var pivot: Node3D = planet_renderer.get("planet_pivot") as Node3D
	if pivot != null:
		pivot.add_child(marker_system)
	else:
		add_child(marker_system)
	marker_system.call("setup", r)

	tactical_props = TacticalGroundPropsScript.new()
	tactical_props.name = "TacticalGroundProps3D"
	if pivot != null:
		pivot.add_child(tactical_props)
	else:
		add_child(tactical_props)
	tactical_props.call("setup", r)

	camera = Camera3D.new()
	camera.name = "PlanetCamera3D"
	camera.current = true
	add_child(camera)

	lod_controller = PlanetLODControllerScript.new()
	lod_controller.name = "PlanetLODController"
	add_child(lod_controller)

	camera_controller = PlanetCameraControllerScript.new()
	camera_controller.name = "PlanetCameraController"
	add_child(camera_controller)
	camera_controller.view_changed.connect(_on_camera_view_changed)

	camera_controller.call("setup", camera, planet_renderer, r)
	camera_controller.call("set_focus_immediate", 19.0, -11.0, 0.85)

	_sync_sun_direction()
	_initialized = true

func _setup_environment_and_lights() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = STARFIELD_SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.34, 0.48, 1.0)
	env.ambient_light_energy = 0.40
	env.glow_enabled = true
	env.glow_intensity = 0.36
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.10

	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	sun_light = DirectionalLight3D.new()
	sun_light.name = "SunLight"
	sun_light.light_color = Color(1.0, 0.96, 0.88)
	sun_light.light_energy = 1.22
	sun_light.shadow_enabled = false
	sun_light.look_at_from_position(Vector3(16.0, 22.0, 14.0), Vector3.ZERO, Vector3.UP)
	add_child(sun_light)

	# Gentle cool rim fill so far-side continents stay readable during 360-degree spin
	fill_light = DirectionalLight3D.new()
	fill_light.name = "SpaceFillLight"
	fill_light.light_color = Color(0.38, 0.52, 0.78)
	fill_light.light_energy = 0.24
	fill_light.shadow_enabled = false
	fill_light.look_at_from_position(Vector3(-18.0, -10.0, -16.0), Vector3.ZERO, Vector3.UP)
	add_child(fill_light)

func _sync_sun_direction() -> void:
	if sun_light != null and planet_renderer != null:
		var sun_dir := sun_light.global_transform.basis.z.normalized()
		planet_renderer.call("set_sun_direction", sun_dir)

func apply_graphics_settings(cfg: Dictionary) -> void:
	if world_env != null and world_env.environment != null:
		world_env.environment.glow_enabled = bool(cfg.get("enable_glow", true))
	if planet_renderer != null and planet_renderer.has_method("set_clouds_enabled"):
		planet_renderer.call("set_clouds_enabled", bool(cfg.get("enable_clouds_3d", true)))
	if tactical_props != null and tactical_props.has_method("apply_graphics_settings"):
		tactical_props.call("apply_graphics_settings", cfg)

func _on_camera_view_changed(zoom_lvl: float, morph: float, _lat: float, _lon: float) -> void:
	if lod_controller != null:
		lod_controller.call("evaluate_for_zoom", zoom_lvl, morph, planet_renderer)

func _process(delta: float) -> void:
	if not external_camera_step and camera_controller != null:
		camera_controller.call("step_update", delta)
