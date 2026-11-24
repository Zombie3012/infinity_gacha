class_name PlanetData
extends Resource
## Configuration & data container for a Fantasy Stylized Planet.
## Holds radius, coordinate sector mapping, 7 equirectangular texture paths,
## and hierarchical Continent -> Region dictionary lookups.

const PlanetCoordinatesScript := preload("res://world_map/core/planet_coordinates.gd")

@export var planet_id: String = "aethelgard_01"
@export var planet_name: String = "Aethelgard — Hành Tinh Viễn Chinh"
@export var planet_radius: float = 10.0
@export var virtual_radius_km: float = 696000.0

@export_group("Expedition Sector Mapping")
@export var sector_grid_origin: Vector2 = Vector2(100.0, 100.0)
@export var sector_grid_span: Vector2 = Vector2(11.0, 11.0)
@export var sector_lat_min: float = 18.67
@export var sector_lat_max: float = 19.33
@export var sector_lon_min: float = -11.33
@export var sector_lon_max: float = -10.67
@export var wonder_grid_coord: Vector2 = Vector2(500.0, 500.0)
@export var wonder_lat_lon: Vector2 = Vector2(6.0, 32.0)

@export_group("Equirectangular Texture Layers")
@export var albedo_path: String = "res://world_map/textures/fantasy_planet/albedo.png"
@export var height_path: String = "res://world_map/textures/fantasy_planet/height.png"
@export var normal_path: String = "res://world_map/textures/fantasy_planet/normal.png"
@export var biome_path: String = "res://world_map/textures/fantasy_planet/biome.png"
@export var ocean_path: String = "res://world_map/textures/fantasy_planet/ocean.png"
@export var magic_path: String = "res://world_map/textures/fantasy_planet/magic.png"
@export var clouds_path: String = "res://world_map/textures/fantasy_planet/clouds.png"

@export_group("Geographic Hierarchy Data")
@export var regions_json_path: String = "res://world_map/data/regions/fantasy_world_regions.json"

var continents: Array[Dictionary] = []
var continents_by_id: Dictionary = {}
var regions: Array[Dictionary] = []
var regions_by_id: Dictionary = {}
var regions_by_continent: Dictionary = {}
var _regions_loaded: bool = false
var _texture_cache: Dictionary = {}

func get_sector_bounds() -> Dictionary:
	return {
		"grid_origin_x": sector_grid_origin.x,
		"grid_origin_y": sector_grid_origin.y,
		"grid_span_x": sector_grid_span.x,
		"grid_span_y": sector_grid_span.y,
		"lat_min": sector_lat_min,
		"lat_max": sector_lat_max,
		"lon_min": sector_lon_min,
		"lon_max": sector_lon_max,
		"wonder_grid_x": wonder_grid_coord.x,
		"wonder_grid_y": wonder_grid_coord.y,
		"wonder_lat": wonder_lat_lon.x,
		"wonder_lon": wonder_lat_lon.y,
	}

func load_texture_layer(layer_path: String) -> Texture2D:
	if layer_path.is_empty():
		return null
	if _texture_cache.has(layer_path):
		return _texture_cache[layer_path] as Texture2D

	var tex: Texture2D = null
	if ResourceLoader.exists(layer_path):
		var loaded := ResourceLoader.load(layer_path)
		if loaded is Texture2D:
			tex = loaded
	if tex == null:
		var abs_path := ProjectSettings.globalize_path(layer_path)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null and not img.is_empty():
				tex = ImageTexture.create_from_image(img)
	if tex != null:
		_texture_cache[layer_path] = tex
	return tex

func get_all_texture_layers() -> Dictionary:
	return {
		"albedo": load_texture_layer(albedo_path),
		"height": load_texture_layer(height_path),
		"normal": load_texture_layer(normal_path),
		"biome": load_texture_layer(biome_path),
		"ocean": load_texture_layer(ocean_path),
		"magic": load_texture_layer(magic_path),
		"clouds": load_texture_layer(clouds_path),
	}

func ensure_regions_loaded() -> bool:
	if _regions_loaded:
		return true
	return load_regions_data()

func load_regions_data() -> bool:
	continents.clear()
	continents_by_id.clear()
	regions.clear()
	regions_by_id.clear()
	regions_by_continent.clear()
	_regions_loaded = false

	var path := regions_json_path
	if not FileAccess.file_exists(path):
		path = ProjectSettings.globalize_path(regions_json_path)
	if not FileAccess.file_exists(path):
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var raw_text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(raw_text)
	if not (parsed is Dictionary):
		return false

	var raw_continents: Array = parsed.get("continents", [])
	for c in raw_continents:
		if c is Dictionary:
			var cid := str(c.get("id", ""))
			if cid.is_empty():
				continue
			continents.append(c)
			continents_by_id[cid] = c
			regions_by_continent[cid] = []

	var raw_regions: Array = parsed.get("regions", [])
	for r in raw_regions:
		if r is Dictionary:
			var rid := str(r.get("id", ""))
			if rid.is_empty():
				continue
			regions.append(r)
			regions_by_id[rid] = r
			var cid := str(r.get("continent_id", ""))
			if not regions_by_continent.has(cid):
				regions_by_continent[cid] = []
			(regions_by_continent[cid] as Array).append(r)

	_regions_loaded = true
	return true

func get_continent(continent_id: String) -> Dictionary:
	ensure_regions_loaded()
	return continents_by_id.get(continent_id, {})

func get_region(region_id: String) -> Dictionary:
	ensure_regions_loaded()
	return regions_by_id.get(region_id, {})

func get_regions_in_continent(continent_id: String) -> Array:
	ensure_regions_loaded()
	return regions_by_continent.get(continent_id, [])

func find_nearest_region(lat_deg: float, lon_deg: float) -> Dictionary:
	ensure_regions_loaded()
	var best: Dictionary = {}
	var best_dist := 1e9
	for r in regions:
		var d: float = PlanetCoordinatesScript.great_circle_distance_deg(
			lat_deg,
			lon_deg,
			float(r.get("latitude", 0.0)),
			float(r.get("longitude", 0.0))
		)
		if d < best_dist:
			best_dist = d
			best = r
	return best
