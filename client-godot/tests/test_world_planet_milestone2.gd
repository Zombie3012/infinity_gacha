extends Node
## Targeted headless verification for Expedition Fantasy Planet — Milestone 2:
## Shaders (surface morph, atmosphere, clouds), PlanetMeshBuilder, PlanetRenderer, and PlanetPreview.

const PlanetMeshBuilderScript := preload("res://world_map/planet_3d/planet_mesh_builder.gd")
const PlanetRendererScript := preload("res://world_map/planet_3d/planet_renderer.gd")

var _checks := 0
var _failures := 0

func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func():
		printerr("WATCHDOG_TIMEOUT: test_world_planet_milestone2")
		get_tree().quit(1)
	)
	_run_tests()

func _expect(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: %s" % msg)

func _run_tests() -> void:
	# 1. Verify all 3 shaders load cleanly with non-empty code
	for shader_path in [
		"res://world_map/shaders/planet_surface_morph.gdshader",
		"res://world_map/shaders/planet_atmosphere.gdshader",
		"res://world_map/shaders/planet_clouds.gdshader",
	]:
		var sh = load(shader_path)
		_expect(sh is Shader, "Shader must load: %s" % shader_path)
		if sh is Shader:
			_expect(not sh.code.strip_edges().is_empty(), "Shader code must not be empty: %s" % shader_path)

	# 2. Verify PlanetMeshBuilder grid topology, UVs, and generous custom_aabb
	var mesh: ArrayMesh = PlanetMeshBuilderScript.build_morph_grid_mesh(192, 96, 10.0)
	_expect(mesh != null and mesh.get_surface_count() == 1, "GridMesh must have 1 surface")
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_expect(verts.size() == 193 * 97, "Expected 18721 vertices, got %d" % verts.size())
	_expect(uvs.size() == verts.size(), "UV count must match vertex count")
	_expect(indices.size() == 192 * 96 * 6, "Expected 221184 indices, got %d" % indices.size())
	_expect(uvs[0].is_equal_approx(Vector2(0.0, 0.0)), "First UV must be (0,0)")
	_expect(uvs[uvs.size() - 1].is_equal_approx(Vector2(1.0, 1.0)), "Last UV must be (1,1)")
	var aabb: AABB = mesh.custom_aabb
	_expect(aabb.has_point(Vector3(31.0, 10.0, 15.0)) and aabb.has_point(Vector3(-31.0, -10.0, -15.0)),
		"Custom AABB must cover full flat map and 3D sphere bounds")

	var atmo_mesh: SphereMesh = PlanetMeshBuilderScript.build_atmosphere_mesh(10.0, 1.052)
	_expect(atmo_mesh != null and absf(atmo_mesh.radius - 10.52) < 1e-3,
		"Atmosphere mesh radius must be 10.52, got %.3f" % (atmo_mesh.radius if atmo_mesh else -1.0))

	# 3. Verify PlanetRenderer binds all 7 textures & transitions morph + LOD cleanly
	var renderer: Node3D = PlanetRendererScript.new()
	add_child(renderer)
	await get_tree().process_frame

	_expect(renderer.surface_mesh_instance != null and renderer.surface_material != null, "Surface mesh & material must exist")
	_expect(renderer.cloud_mesh_instance != null and renderer.cloud_material != null, "Cloud mesh & material must exist")
	_expect(renderer.atmosphere_mesh_instance != null and renderer.atmosphere_material != null, "Atmosphere mesh & material must exist")

	for uniform_name in ["albedo_map", "height_map", "normal_map", "biome_map", "ocean_mask", "magic_mask"]:
		var bound = renderer.surface_material.get_shader_parameter(uniform_name)
		_expect(bound is Texture2D, "Surface shader parameter '%s' must be bound to Texture2D" % uniform_name)
	_expect(renderer.cloud_material.get_shader_parameter("cloud_map") is Texture2D, "Cloud shader 'cloud_map' must be bound")

	# Morph = 0.0 (2D flat): atmosphere hidden
	renderer.set_morph_factor(0.0)
	_expect(not renderer.atmosphere_mesh_instance.visible, "Atmosphere must stay hidden in 2D flat mode (morph=0)")
	_expect(is_equal_approx(float(renderer.surface_material.get_shader_parameter("morph_factor")), 0.0), "Surface morph must be 0.0")

	# Morph = 1.0 (3D globe): atmosphere visible & alpha synced
	renderer.set_lod_params(0.30, 0.90, 0.55, 1.0)
	renderer.set_morph_factor(1.0)
	_expect(renderer.atmosphere_mesh_instance.visible, "Atmosphere must become visible in 3D globe mode (morph=1)")
	_expect(float(renderer.atmosphere_material.get_shader_parameter("atmosphere_alpha")) > 0.9, "Atmosphere alpha must be active at morph=1")
	_expect(is_equal_approx(float(renderer.surface_material.get_shader_parameter("normal_strength")), 0.30), "LOD normal_strength must apply")

	# Center longitude wrap update
	renderer.set_center_lon_deg(-11.0)
	_expect(absf(float(renderer.surface_material.get_shader_parameter("center_lon_rad")) - deg_to_rad(-11.0)) < 1e-4,
		"center_lon_rad must sync cleanly")
	renderer.queue_free()

	# 4. Verify PlanetPreview showcase scene instantiates cleanly
	var preview_scene: PackedScene = load("res://world_map/scenes/planet_preview.tscn")
	_expect(preview_scene != null, "planet_preview.tscn must load")
	if preview_scene != null:
		var preview := preview_scene.instantiate()
		add_child(preview)
		await get_tree().process_frame
		_expect(preview.get_node_or_null("WorldMap3D/PlanetRenderer") != null, "PlanetPreview must host WorldMap3D/PlanetRenderer")
		preview.queue_free()

	print("PLANET_MILESTONE2: %d checks, %s" % [_checks, "PASS" if _failures == 0 else ("FAILED (%d)" % _failures)])
	get_tree().quit(0 if _failures == 0 else 1)
