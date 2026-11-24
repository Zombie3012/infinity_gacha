class_name PlanetLODController
extends Node
## Solar-Scale 5-Stage / 4-Tier LOD Controller (P1).
##
## - Separates tactical grid labels cleanly from regional/continental labels:
##   region_label_alpha == 0.0 at Tactical Chiến Khu zoom (>= 0.68) so labels NEVER overlap tiles!
## - Drives GPU micro-terrain detail_strength (1.0 at local zoom -> 0.0 at continent/globe zoom)
## - Drives soft swirling planetary fog_opacity (0.92 dense cloud mist up close -> 0.36 mythic haze in 3D orbit)

enum LodTier {
	LOD_0_TACTICAL = 0,
	LOD_1_REGIONAL = 1,
	LOD_2_CONTINENTAL = 2,
	LOD_3_PLANETARY = 3,
}

const TIER_LABELS := {
	LodTier.LOD_0_TACTICAL: "Chiến khu",
	LodTier.LOD_1_REGIONAL: "Đại lục",
	LodTier.LOD_2_CONTINENTAL: "Toàn bản đồ",
	LodTier.LOD_3_PLANETARY: "Hành tinh 3D",
}

signal lod_tier_changed(new_tier: int, tier_label: String)

var current_tier: int = LodTier.LOD_0_TACTICAL
var stage_label: String = "Chiến khu"
var normal_strength: float = 0.72
var magic_strength: float = 1.15
var cloud_opacity: float = 0.06
var atmosphere_alpha: float = 0.0
var detail_strength: float = 1.0
var fog_opacity: float = 0.92
var tactical_overlay_alpha: float = 1.0
var fleet_overlay_alpha: float = 1.0
var region_label_alpha: float = 0.0
var region_border_alpha: float = 0.0
var continent_label_alpha: float = 0.0
var show_detail_markers: bool = true

func evaluate_for_zoom(zoom_level: float, morph_factor: float, renderer: Node3D = null) -> Dictionary:
	var z := clampf(zoom_level, 0.0, 1.0)
	var next_tier := LodTier.LOD_3_PLANETARY
	if z >= 0.62:
		next_tier = LodTier.LOD_0_TACTICAL
	elif z >= 0.36:
		next_tier = LodTier.LOD_1_REGIONAL
	elif z >= 0.16:
		next_tier = LodTier.LOD_2_CONTINENTAL
	else:
		next_tier = LodTier.LOD_3_PLANETARY

	if z >= 0.76:
		stage_label = "Chiến khu"
	elif z >= 0.58:
		stage_label = "Tỉnh / Vùng"
	elif z >= 0.34:
		stage_label = "Đại lục"
	elif z >= 0.14:
		stage_label = "Toàn bản đồ"
	else:
		stage_label = "Hành tinh 3D"

	# Continuous GPU shader parameters
	normal_strength = lerpf(0.28, 0.72, smoothstep_val(0.08, 0.65, z))
	magic_strength = lerpf(0.75, 1.15, smoothstep_val(0.08, 0.62, z))
	cloud_opacity = lerpf(0.32, 0.0, smoothstep_val(0.18, 0.56, z))
	atmosphere_alpha = smoothstep_val(0.30, 0.04, z)
	detail_strength = smoothstep_val(0.44, 0.70, z)
	# Crisp soft fog over unexplored tactical tiles (0.86), lifting completely to 0.0 at 3D Globe so all 5 continents shine crystal-clear!
	fog_opacity = lerpf(0.0, 0.86, smoothstep_val(0.24, 0.66, z))

	# Clean non-overlapping overlay alphas
	tactical_overlay_alpha = smoothstep_val(0.60, 0.74, z)
	# Active Fleets stay continuously visible from Tactical through Continent view, overlapping 3D Beacons at 0.24..0.42 (ZERO dead-zone!)
	fleet_overlay_alpha = smoothstep_val(0.24, 0.36, z)
	# Region labels strictly hidden at tactical zoom (>= 0.68) so zero text overlaps the grid!
	region_label_alpha = smoothstep_val(0.26, 0.42, z) * (1.0 - smoothstep_val(0.58, 0.68, z))
	region_border_alpha = region_label_alpha * 0.78
	continent_label_alpha = smoothstep_val(0.54, 0.28, z)
	show_detail_markers = z >= 0.60 and morph_factor < 0.15

	if renderer != null and renderer.has_method("set_lod_params"):
		renderer.call("set_lod_params", normal_strength, magic_strength, cloud_opacity, atmosphere_alpha, detail_strength, fog_opacity)

	if next_tier != current_tier:
		current_tier = next_tier
		lod_tier_changed.emit(current_tier, get_tier_label())

	return get_snapshot()

func get_tier_label() -> String:
	return stage_label

func get_snapshot() -> Dictionary:
	return {
		"tier": current_tier,
		"label": stage_label,
		"normal_strength": normal_strength,
		"magic_strength": magic_strength,
		"cloud_opacity": cloud_opacity,
		"atmosphere_alpha": atmosphere_alpha,
		"detail_strength": detail_strength,
		"fog_opacity": fog_opacity,
		"tactical_overlay_alpha": tactical_overlay_alpha,
		"fleet_overlay_alpha": fleet_overlay_alpha,
		"region_label_alpha": region_label_alpha,
		"region_border_alpha": region_border_alpha,
		"continent_label_alpha": continent_label_alpha,
		"show_detail_markers": show_detail_markers,
	}

static func smoothstep_val(edge0: float, edge1: float, x: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 1.0 if x >= edge1 else 0.0
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
