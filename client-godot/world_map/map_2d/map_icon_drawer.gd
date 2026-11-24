class_name MapIconDrawer
extends RefCounted
## Stylized Vector Map Icon Drawer (P2).
## Draws crisp Fantasy Strategy motifs onto the WorldRtsMap canvas:
## - 3-Tower Castle Citadel for Player Base
## - Runic Portal Gate with glowing rank vortex for Emerging Dungeons (D/C/B/A/S)
## - Subtle cartographic terrain motifs (Forest, Mountain, Hills, Ruins, Marsh)
## - Golden Imperial Wonder Spire

static func draw_castle_base(canvas: Control, center: Vector2, r: float, pulse: float, alpha: float) -> void:
	if alpha <= 0.02 or r < 4.0:
		return
	var s := clampf(r, 8.0, 34.0)
	# Outer pulsing protective aura
	canvas.draw_circle(center, s * (1.18 + pulse * 0.12), Color(0.20, 0.78, 1.0, 0.22 * alpha))
	canvas.draw_arc(center, s * 1.08, 0.0, TAU, 28, Color(0.55, 0.92, 1.0, 0.65 * alpha), 1.6)

	var stone := Color(0.84, 0.89, 0.96, alpha)
	var stone_dark := Color(0.42, 0.50, 0.64, alpha)
	var roof := Color(0.18, 0.62, 0.96, alpha)
	var gold := Color(1.0, 0.84, 0.34, alpha)

	# Curtain wall base
	var wall_rect := Rect2(center + Vector2(-s * 0.68, -s * 0.12), Vector2(s * 1.36, s * 0.72))
	canvas.draw_rect(wall_rect, stone_dark, true)
	canvas.draw_rect(Rect2(wall_rect.position + Vector2(1.0, 1.0), wall_rect.size - Vector2(2.0, 2.0)), stone, true)

	# Left & Right side towers
	for side_x in [-0.62, 0.36]:
		var tw := Rect2(center + Vector2(s * side_x, -s * 0.44), Vector2(s * 0.28, s * 0.96))
		canvas.draw_rect(tw, stone, true)
		canvas.draw_rect(tw, stone_dark, false, 1.0)
		var tri := PackedVector2Array([
			Vector2(tw.position.x - s * 0.04, tw.position.y),
			Vector2(tw.position.x + tw.size.x * 0.5, tw.position.y - s * 0.28),
			Vector2(tw.position.x + tw.size.x + s * 0.04, tw.position.y),
		])
		canvas.draw_colored_polygon(tri, roof)

	# Central tall Keep
	var keep := Rect2(center + Vector2(-s * 0.24, -s * 0.68), Vector2(s * 0.48, s * 1.24))
	canvas.draw_rect(keep, stone, true)
	canvas.draw_rect(keep, stone_dark, false, 1.2)
	var keep_roof := PackedVector2Array([
		Vector2(keep.position.x - s * 0.06, keep.position.y),
		Vector2(center.x, keep.position.y - s * 0.40),
		Vector2(keep.position.x + keep.size.x + s * 0.06, keep.position.y),
	])
	canvas.draw_colored_polygon(keep_roof, roof.lightened(0.12))

	# Golden pennant flag at spire peak
	var mast_base := Vector2(center.x, keep.position.y - s * 0.38)
	var mast_top := mast_base + Vector2(0.0, -s * 0.32)
	canvas.draw_line(mast_base, mast_top, gold, 1.4)
	var wave_x := sin(pulse * 2.4) * s * 0.06
	var flag_pts := PackedVector2Array([
		mast_top,
		mast_top + Vector2(s * 0.34, s * 0.08 + wave_x),
		mast_top + Vector2(0.0, s * 0.18),
	])
	canvas.draw_colored_polygon(flag_pts, gold)

	# Glowing arched castle gate
	var gate_rect := Rect2(center + Vector2(-s * 0.14, s * 0.18), Vector2(s * 0.28, s * 0.40))
	canvas.draw_rect(gate_rect, Color(0.14, 0.20, 0.34, alpha), true)
	canvas.draw_circle(center + Vector2(0.0, s * 0.20), s * 0.14, Color(0.32, 0.92, 1.0, (0.72 + pulse * 0.25) * alpha))

static func draw_dungeon_portal(canvas: Control, center: Vector2, r: float, rank: String, rank_col: Color, pulse: float, alpha: float) -> void:
	if alpha <= 0.02 or r < 4.0:
		return
	var s := clampf(r, 8.0, 30.0)
	var font := ThemeDB.fallback_font

	# Pulsing vortex aura
	canvas.draw_circle(center, s * (1.14 + pulse * 0.14), Color(rank_col.r, rank_col.g, rank_col.b, 0.24 * alpha))

	# Ancient stone archway pillars
	var stone := Color(0.28, 0.26, 0.34, alpha)
	var stone_hi := Color(0.56, 0.54, 0.66, alpha)
	var arch_pts := PackedVector2Array([
		center + Vector2(-s * 0.64, s * 0.56),
		center + Vector2(-s * 0.56, -s * 0.32),
		center + Vector2(0.0, -s * 0.78),
		center + Vector2(s * 0.56, -s * 0.32),
		center + Vector2(s * 0.64, s * 0.56),
	])
	canvas.draw_colored_polygon(arch_pts, stone)
	canvas.draw_polyline(arch_pts, stone_hi, 1.6)

	# Inner glowing portal rift
	canvas.draw_circle(center + Vector2(0.0, s * 0.06), s * 0.44, Color(0.05, 0.04, 0.10, 0.92 * alpha))
	canvas.draw_circle(center + Vector2(0.0, s * 0.06), s * (0.34 + pulse * 0.06), Color(rank_col.r, rank_col.g, rank_col.b, 0.88 * alpha))
	canvas.draw_circle(center + Vector2(0.0, s * 0.06), s * 0.16, Color(1.0, 0.96, 0.90, 0.92 * alpha))
	canvas.draw_arc(center + Vector2(0.0, s * 0.06), s * 0.46, 0.0, TAU, 20, Color(rank_col.r, rank_col.g, rank_col.b, 0.90 * alpha), 1.6)

	# Compact rank badge pill below arch
	if s >= 10.0:
		var pill_w := s * 1.15
		var pill_h := 14.0
		var pill_rect := Rect2(center + Vector2(-pill_w * 0.5, s * 0.46), Vector2(pill_w, pill_h))
		canvas.draw_rect(pill_rect, Color(0.05, 0.06, 0.11, 0.86 * alpha), true)
		canvas.draw_rect(pill_rect, Color(rank_col.r, rank_col.g, rank_col.b, 0.85 * alpha), false, 1.2)
		canvas.draw_string(font, pill_rect.position + Vector2(pill_w * 0.22, 11.0), "D-%s" % rank, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(1.0, 0.98, 0.94, alpha))

static func draw_terrain_motif(canvas: Control, center: Vector2, tile_px: float, terrain: String, alpha: float) -> void:
	if alpha <= 0.04 or tile_px < 26.0:
		return
	var s := clampf(tile_px * 0.24, 5.0, 15.0)
	match terrain:
		"FOREST":
			var tree_col := Color(0.07, 0.28, 0.16, 0.58 * alpha)
			var hi_col := Color(0.18, 0.48, 0.28, 0.52 * alpha)
			for off in [Vector2(-s * 0.55, s * 0.18), Vector2(s * 0.48, s * 0.24), Vector2(0.0, -s * 0.12)]:
				var p: Vector2 = center + off
				var tri := PackedVector2Array([
					p + Vector2(0.0, -s * 0.65),
					p + Vector2(s * 0.46, s * 0.35),
					p + Vector2(-s * 0.46, s * 0.35),
				])
				canvas.draw_colored_polygon(tri, tree_col)
				canvas.draw_line(tri[0], tri[1], hi_col, 1.0)
		"MOUNTAIN":
			var m_col := Color(0.36, 0.38, 0.48, 0.64 * alpha)
			var snow := Color(0.92, 0.95, 1.0, 0.68 * alpha)
			var p1 := PackedVector2Array([
				center + Vector2(-s * 0.95, s * 0.55),
				center + Vector2(-s * 0.18, -s * 0.72),
				center + Vector2(s * 0.55, s * 0.55),
			])
			canvas.draw_colored_polygon(p1, m_col)
			var cap := PackedVector2Array([
				center + Vector2(-s * 0.18, -s * 0.72),
				center + Vector2(-s * 0.42, -s * 0.24),
				center + Vector2(s * 0.06, -s * 0.24),
			])
			canvas.draw_colored_polygon(cap, snow)
		"HILLS":
			var h_col := Color(0.55, 0.48, 0.30, 0.46 * alpha)
			canvas.draw_arc(center + Vector2(-s * 0.35, s * 0.35), s * 0.65, PI, TAU, 12, h_col, 1.6)
			canvas.draw_arc(center + Vector2(s * 0.40, s * 0.42), s * 0.52, PI, TAU, 12, h_col, 1.4)
		"RUINS":
			var r_col := Color(0.72, 0.66, 0.80, 0.52 * alpha)
			canvas.draw_rect(Rect2(center + Vector2(-s * 0.52, -s * 0.35), Vector2(s * 0.24, s * 0.75)), r_col, true)
			canvas.draw_rect(Rect2(center + Vector2(s * 0.24, -s * 0.12), Vector2(s * 0.24, s * 0.52)), r_col, true)
			canvas.draw_line(center + Vector2(-s * 0.62, s * 0.42), center + Vector2(s * 0.58, s * 0.42), r_col, 1.3)
		"MARSH":
			var w_col := Color(0.32, 0.76, 0.78, 0.42 * alpha)
			canvas.draw_line(center + Vector2(-s * 0.65, -s * 0.10), center + Vector2(s * 0.25, -s * 0.10), w_col, 1.4)
			canvas.draw_line(center + Vector2(-s * 0.20, s * 0.25), center + Vector2(s * 0.65, s * 0.25), w_col, 1.4)

static func draw_wonder_citadel(canvas: Control, center: Vector2, r: float, pulse: float, alpha: float) -> void:
	if alpha <= 0.02:
		return
	var s := clampf(r, 8.0, 26.0)
	var gold := Color(1.0, 0.86, 0.32, alpha)
	canvas.draw_circle(center, s * (1.25 + pulse * 0.18), Color(1.0, 0.82, 0.22, 0.24 * alpha))
	canvas.draw_arc(center, s * 1.15, 0.0, TAU, 28, Color(1.0, 0.90, 0.45, 0.78 * alpha), 1.6)
	var diamond := PackedVector2Array([
		center + Vector2(0.0, -s * 0.92),
		center + Vector2(s * 0.54, 0.0),
		center + Vector2(0.0, s * 0.72),
		center + Vector2(-s * 0.54, 0.0),
	])
	canvas.draw_colored_polygon(diamond, gold)
	canvas.draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color(1.0, 0.98, 0.88, alpha), 1.5)
	canvas.draw_circle(center + Vector2(0.0, -s * 0.12), s * 0.20, Color(1.0, 0.98, 0.92, alpha))
