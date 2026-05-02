extends Node2D

## WaveDiffOverlay — editor-only "what changed in this wave" highlight.
##
## Compares LevelData.waves[active] vs waves[active-1]. For each coord
## that's new (or whose object/spawner identity changed), draws a hex
## tint + outline using HexGeometry.flat_top_polygon and UiTheme.WAVE_DIFF_*
## constants. Wave 0 → no highlight (everything would be "new"; nothing
## to compare against).
##
## Mounted as a child of HexGrid in the map editor scene. The
## MapEditorController calls `bind_level(level)` after every wave-aware
## edit (via _mark_dirty / _apply_level / _switch_to_wave). Cheap — one
## queue_redraw per call, hex polygon math is tiny.

const HexGeometry = preload("res://scripts/infrastructure/hex_geometry.gd")
const UiThemeScript = preload("res://scripts/presentation/ui_theme.gd")

@export var grid: HexGrid

# Coords currently rendered as "new this wave". Maintained by bind_level.
var _diff_coords: Array[Vector2i] = []


func _ready() -> void:
	if grid == null:
		grid = get_parent() as HexGrid
	z_index = 1  # above floor (0), below objects/spawners (~3-10)
	queue_redraw()


## Called by MapEditorController whenever the underlying level or active
## wave may have changed. level==null clears the overlay.
func bind_level(level: LevelData) -> void:
	_diff_coords.clear()
	if level == null:
		queue_redraw()
		return
	var active: int = level.get_active_wave_index()
	# Wave 0 → no comparison source. Highlight off.
	if active <= 0 or active >= level.waves.size():
		queue_redraw()
		return
	var prev: Dictionary = level.waves[active - 1]
	var curr: Dictionary = level.waves[active]

	# Collect coords whose floor/object/spawner identity differs from prev.
	var changed: Dictionary = {}  # coord → true

	# Floor: present in current, not in prev (or different atlas).
	var prev_floor: Dictionary = {}
	for f in prev.get("floor", []):
		prev_floor[f.get("coord", Vector2i.ZERO)] = f
	for f in curr.get("floor", []):
		var c: Vector2i = f.get("coord", Vector2i.ZERO)
		var pf: Dictionary = prev_floor.get(c, {})
		if pf.is_empty():
			changed[c] = true
		else:
			# Atlas swap counts as a change too.
			if pf.get("source_id", -1) != f.get("source_id", -2) \
					or pf.get("atlas_coord", Vector2i.ZERO) != f.get("atlas_coord", Vector2i.ZERO):
				changed[c] = true

	# Objects: id-or-presence change.
	var prev_obj: Dictionary = {}
	for o in prev.get("objects", []):
		prev_obj[o.get("coord", Vector2i.ZERO)] = StringName(o.get("object_id", &""))
	for o in curr.get("objects", []):
		var c: Vector2i = o.get("coord", Vector2i.ZERO)
		var prev_id: StringName = prev_obj.get(c, &"")
		var curr_id: StringName = StringName(o.get("object_id", &""))
		if prev_id != curr_id:
			changed[c] = true

	# Spawners: kind-or-ref change. Timer alone doesn't count as "new" —
	# tweaking a number isn't a structural change.
	var prev_spawn: Dictionary = {}
	for s in prev.get("spawners", []):
		prev_spawn[s.get("coord", Vector2i.ZERO)] = "%s/%s" % [
			String(s.get("kind", &"")), String(s.get("ref", &""))
		]
	for s in curr.get("spawners", []):
		var c: Vector2i = s.get("coord", Vector2i.ZERO)
		var prev_sig: String = prev_spawn.get(c, "")
		var curr_sig: String = "%s/%s" % [
			String(s.get("kind", &"")), String(s.get("ref", &""))
		]
		if prev_sig != curr_sig:
			changed[c] = true

	for c in changed:
		_diff_coords.append(c)
	queue_redraw()


func _draw() -> void:
	if _diff_coords.is_empty() or grid == null or grid.tile_map_layer == null:
		return
	var poly: PackedVector2Array = HexGeometry.flat_top_polygon_for_layer(grid.tile_map_layer)
	if poly.is_empty():
		return
	for coord: Vector2i in _diff_coords:
		var center: Vector2 = grid.tile_map_layer.map_to_local(coord)
		var translated := PackedVector2Array()
		for v: Vector2 in poly:
			translated.append(v + center)
		draw_colored_polygon(translated, UiThemeScript.WAVE_DIFF_FILL)
		# Closed outline.
		var loop := translated.duplicate()
		loop.append(translated[0])
		draw_polyline(loop, UiThemeScript.WAVE_DIFF_OUTLINE, 2.0, true)
