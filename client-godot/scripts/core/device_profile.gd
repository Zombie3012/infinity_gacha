class_name DeviceProfile
extends RefCounted
## Automatic Hardware & Platform Detection (PC vs Mobile) + Graphics Preset Table.
##
## Rules:
## - Mobile (Android / iOS / Web): locked safely to HYBRID streaming mode (R <= 12, MSAA <= 2x, FPS <= 60)
##   to protect battery, thermals, and RAM.
## - PC (Windows / macOS / Linux): unlocks ALL graphics presets (LOW -> ULTRA -> PLANET_WIDE)
##   and full Render Distance / 3D Props density / MSAA / FPS sliders.

const PLATFORM_MOBILE := "MOBILE"
const PLATFORM_PC := "PC"

const GPU_TIER_LOW := "LOW"
const GPU_TIER_MID := "MID"
const GPU_TIER_HIGH := "HIGH"

const MOBILE_ALLOWED_PRESETS := ["LOW", "MEDIUM", "HIGH"]
const PC_ALLOWED_PRESETS := ["LOW", "MEDIUM", "HIGH", "ULTRA", "PLANET_WIDE"]

static func detect_hardware() -> Dictionary:
	var os_name := OS.get_name()
	var is_mobile_flag := (
		OS.has_feature("mobile")
		or OS.has_feature("android")
		or OS.has_feature("ios")
		or OS.has_feature("web")
		or os_name in ["Android", "iOS", "Web"]
	)
	var gpu_name := ""
	var gpu_vendor := ""
	if DisplayServer.get_name() != "headless":
		gpu_name = str(RenderingServer.get_video_adapter_name())
		gpu_vendor = str(RenderingServer.get_video_adapter_vendor())
	if gpu_name.is_empty():
		gpu_name = "Headless / Generic GPU"
	var cpu_threads := maxi(1, OS.get_processor_count())
	var info := classify_hardware(os_name, is_mobile_flag, gpu_name, cpu_threads)
	info["gpu_vendor"] = gpu_vendor
	return info

## Pure deterministic classifier (easy to unit-test across Android, iOS, iGPU, and RTX hardware).
static func classify_hardware(os_name: String, is_mobile_flag: bool, gpu_name: String, cpu_threads: int) -> Dictionary:
	var is_mobile := is_mobile_flag or (os_name in ["Android", "iOS", "Web"])
	var g_up := gpu_name.to_upper()
	var gpu_tier := GPU_TIER_MID

	if is_mobile:
		var high_mobile := (
			g_up.contains("ADRENO 7") or g_up.contains("ADRENO 65") or g_up.contains("ADRENO 66")
			or g_up.contains("APPLE A15") or g_up.contains("APPLE A16") or g_up.contains("APPLE A17") or g_up.contains("APPLE A18")
			or g_up.contains("APPLE M") or g_up.contains("IMMORTALIS") or g_up.contains("MALI-G71") or g_up.contains("MALI-G72")
		)
		var low_mobile := (
			cpu_threads <= 4
			or g_up.contains("ADRENO 5") or g_up.contains("ADRENO 61")
			or g_up.contains("MALI-G5") or g_up.contains("MALI-T") or g_up.contains("POWERVR")
			or g_up.contains("SWIFTSHADER") or g_up.contains("LLVMPIPE")
		)
		if high_mobile:
			gpu_tier = GPU_TIER_HIGH
		elif low_mobile:
			gpu_tier = GPU_TIER_LOW
		else:
			gpu_tier = GPU_TIER_MID
	else:
		var high_pc := (
			g_up.contains("RTX") or g_up.contains("GTX 16") or g_up.contains("GTX 107") or g_up.contains("GTX 108")
			or g_up.contains("RX 5") or g_up.contains("RX 6") or g_up.contains("RX 7") or g_up.contains("RX 8")
			or g_up.contains("RADEON PRO") or g_up.contains("ARC A") or g_up.contains("ARC B")
			or g_up.contains("APPLE M1") or g_up.contains("APPLE M2") or g_up.contains("APPLE M3") or g_up.contains("APPLE M4")
		)
		var low_pc := (
			g_up.contains("UHD 6") or g_up.contains("HD GRAPHICS") or g_up.contains("VEGA 3")
			or g_up.contains("LLVMPIPE") or g_up.contains("SWIFTSHADER") or g_up.contains("BASIC RENDER")
			or g_up.contains("HEADLESS") or cpu_threads <= 2
		)
		if high_pc:
			gpu_tier = GPU_TIER_HIGH
		elif low_pc:
			gpu_tier = GPU_TIER_LOW
		else:
			gpu_tier = GPU_TIER_MID

	var recommended := "HIGH"
	if is_mobile:
		recommended = "LOW" if gpu_tier == GPU_TIER_LOW else "MEDIUM"
	else:
		if gpu_tier == GPU_TIER_HIGH:
			recommended = "ULTRA"
		elif gpu_tier == GPU_TIER_LOW:
			recommended = "MEDIUM"
		else:
			recommended = "HIGH"

	return {
		"platform": PLATFORM_MOBILE if is_mobile else PLATFORM_PC,
		"is_mobile": is_mobile,
		"os_name": os_name,
		"gpu_name": gpu_name,
		"gpu_tier": gpu_tier,
		"cpu_threads": cpu_threads,
		"can_unlock_planet_wide": not is_mobile,
		"recommended_preset": recommended,
	}

static func get_allowed_presets(is_mobile: bool) -> Array[String]:
	if is_mobile:
		var m: Array[String] = ["LOW", "MEDIUM", "HIGH"]
		return m
	var p: Array[String] = ["LOW", "MEDIUM", "HIGH", "ULTRA", "PLANET_WIDE"]
	return p

static func get_preset_label(preset_key: String, is_mobile: bool) -> String:
	match preset_key.to_upper():
		"LOW":
			return "🔋 Thấp (Tiết kiệm pin)" if is_mobile else "🔋 Thấp (Low)"
		"MEDIUM":
			return "⚖️ Hybrid Cân bằng (Khuyên dùng)" if is_mobile else "⚖️ Trung bình (Medium)"
		"HIGH":
			return "✨ Hybrid Cao" if is_mobile else "✨ Cao (High)"
		"ULTRA":
			return "🔥 Cực đại (PC)"
		"PLANET_WIDE":
			return "🌍 Toàn Hành Tinh (PC)"
		_:
			return "✨ Cao (High)"

static func get_preset_settings(preset_key: String, is_mobile: bool) -> Dictionary:
	var key := preset_key.to_upper()
	if is_mobile and not (key in MOBILE_ALLOWED_PRESETS):
		key = "HIGH"
	elif not is_mobile and not (key in PC_ALLOWED_PRESETS):
		key = "HIGH"

	var cfg: Dictionary
	match key:
		"LOW":
			cfg = {
				"quality": "LOW",
				"streaming_mode": "HYBRID",
				"world_render_radius": 8,
				"props_density": 0.50,
				"props_cull_zoom": 0.68,
				"chunk_request_radius": 8,
				"msaa_3d": Viewport.MSAA_DISABLED,
				"enable_clouds_3d": false,
				"enable_glow": false,
				"max_fps": 30 if is_mobile else 60,
				"poll_interval_sec": 5.0 if is_mobile else 3.5,
			}
		"MEDIUM":
			cfg = {
				"quality": "MEDIUM",
				"streaming_mode": "HYBRID",
				"world_render_radius": 10 if is_mobile else 12,
				"props_density": 0.75 if is_mobile else 1.0,
				"props_cull_zoom": 0.62,
				"chunk_request_radius": 12,
				"msaa_3d": Viewport.MSAA_2X,
				"enable_clouds_3d": true,
				"enable_glow": true,
				"max_fps": 60,
				"poll_interval_sec": 4.0 if is_mobile else 3.0,
			}
		"ULTRA":
			cfg = {
				"quality": "ULTRA",
				"streaming_mode": "HYBRID",
				"world_render_radius": 24,
				"props_density": 1.35,
				"props_cull_zoom": 0.50,
				"chunk_request_radius": 16,
				"msaa_3d": Viewport.MSAA_4X,
				"enable_clouds_3d": true,
				"enable_glow": true,
				"max_fps": 120,
				"poll_interval_sec": 2.5,
			}
		"PLANET_WIDE":
			cfg = {
				"quality": "PLANET_WIDE",
				"streaming_mode": "PLANET_WIDE",
				"world_render_radius": 32,
				"props_density": 1.50,
				"props_cull_zoom": 0.42,
				"chunk_request_radius": 16,
				"msaa_3d": Viewport.MSAA_4X,
				"enable_clouds_3d": true,
				"enable_glow": true,
				"max_fps": 120,
				"poll_interval_sec": 2.0,
			}
		_: # HIGH
			cfg = {
				"quality": "HIGH",
				"streaming_mode": "HYBRID",
				"world_render_radius": 12 if is_mobile else 16,
				"props_density": 1.0,
				"props_cull_zoom": 0.58 if is_mobile else 0.54,
				"chunk_request_radius": 12 if is_mobile else 16,
				"msaa_3d": Viewport.MSAA_2X,
				"enable_clouds_3d": true,
				"enable_glow": true,
				"max_fps": 60,
				"poll_interval_sec": 3.0,
			}

	return sanitize_settings(cfg, is_mobile)

## Enforce Mobile Hybrid safety guardrails & PC valid bounds on any custom/loaded settings dict.
static func sanitize_settings(raw: Dictionary, is_mobile: bool) -> Dictionary:
	var q := str(raw.get("quality", "MEDIUM" if is_mobile else "HIGH")).to_upper()
	if is_mobile:
		if not (q in MOBILE_ALLOWED_PRESETS):
			q = "HIGH"
	else:
		if not (q in PC_ALLOWED_PRESETS):
			q = "HIGH"

	var streaming := str(raw.get("streaming_mode", "HYBRID")).to_upper()
	if is_mobile or streaming != "PLANET_WIDE":
		streaming = "HYBRID"

	var max_rad := 12 if is_mobile else 32
	var render_rad := clampi(int(raw.get("world_render_radius", 10 if is_mobile else 16)), 8, max_rad)
	var max_dens := 1.0 if is_mobile else 1.5
	var dens := clampf(float(raw.get("props_density", 0.75 if is_mobile else 1.0)), 0.5, max_dens)
	var cull_z := clampf(float(raw.get("props_cull_zoom", 0.60)), 0.40 if not is_mobile else 0.56, 0.72)
	var chunk_rad := clampi(int(raw.get("chunk_request_radius", 12)), 8, 12 if is_mobile else 16)
	var max_msaa := int(Viewport.MSAA_2X) if is_mobile else int(Viewport.MSAA_4X)
	var msaa := clampi(int(raw.get("msaa_3d", int(Viewport.MSAA_2X))), int(Viewport.MSAA_DISABLED), max_msaa)
	var fps_val := int(raw.get("max_fps", 60))
	if is_mobile:
		fps_val = 30 if fps_val <= 30 else 60
	elif not (fps_val in [30, 60, 120, 240]):
		fps_val = 60

	return {
		"quality": q,
		"streaming_mode": streaming,
		"world_render_radius": render_rad,
		"props_density": dens,
		"props_cull_zoom": cull_z,
		"chunk_request_radius": chunk_rad,
		"msaa_3d": msaa,
		"enable_clouds_3d": bool(raw.get("enable_clouds_3d", true)),
		"enable_glow": bool(raw.get("enable_glow", true)),
		"max_fps": fps_val,
		"poll_interval_sec": clampf(float(raw.get("poll_interval_sec", 3.0)), 2.0, 6.0),
	}
