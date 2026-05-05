extends Node2D
## CastRangeOverlay — distinct from MoveRangeOverlay. Highlights ONLY the
## valid target hexes for the active ability of the active caster — no
## reachable-walk hexes, no self-position marker.
##
## 029 / req-4: visualization style switched from filled hexes (per-hex
## Polygon2D + Line2D nodes) to per-hex THIN OUTLINES drawn in a single
## _draw() pass, mirroring scripts/presentation/dev/paint_preview.gd. This
## reads cleanly without obscuring tile content underneath, and matches the
## editor's brush preview for visual continuity (UI-kit cohesion).
##
## 049 / AC-6: range hexes are split into VALID (target.resolve returns non-
## null for that coord's ctx) and INVALID (no actor, wrong team, blocked
## etc.). Valid → SEM_DEBUFF outline (existing look). Invalid → dim grey
## outline. Click on invalid hex is already a no-op upstream (CastFsm /
## godmode_input range guards); the visual just makes the rule legible.
##
## Use case: while a slot is active (player has Q/W/E/R selected), this
## overlay paints the outlines of all hexes that ability could land on,
## colour-coded by validity.
##
## Wiring: parent it to the same HexGrid node as MoveRangeOverlay. The host
## controller calls setup(grid, registry), then show_range(caster, ability_id)
## when cast_mode enters "selecting target", and hide_range() when leaving.
##
## Z-index 4 — below cursor (z=7), above terrain, above move overlay (z=2).

## Hex polygon dimensions come from the live tileset's tile_size — see
## scripts/infrastructure/hex_geometry.gd. tile_size in the .tres is the
## single source of truth.
const HexGeometry = preload("res://scripts/infrastructure/hex_geometry.gd")

var _grid: Node = null  # HexGrid
var _registry: Node = null  # ActorRegistry — needed for AC-6 validity check
# 049 / AC-6: split list. Legacy `_coords` is gone; callers use the typed
# valid/invalid lists. show_range_for_ability fills both; show_range (legacy
# multi-ability variant) leaves _coords_invalid empty (validity per-ability
# isn't well-defined for the union).
var _coords_valid: Array[Vector2i] = []
var _coords_invalid: Array[Vector2i] = []
var _color: Color = Color.WHITE
var _self_coord: Vector2i = Vector2i(-1, -1)  # special-case highlight (self-confirm step)


func setup(grid: Node, registry: Node = null) -> void:
	_grid = grid
	_registry = registry


func _ready() -> void:
	# Match scene z_index but assert here too in case future scene rewrites
	# omit it. Cursor (z=7) stays on top, MoveRangeOverlay (z=2) underneath.
	z_index = 4
	EventBus.ui_theme_reloaded.connect(_on_theme_reloaded)


## Show valid target hexes for a skill or ability cast by caster. Accepts
## either a Skill object (post-007 — iterates its abilities[]) or a single
## ability_id StringName (legacy lookup via AbilityDatabase). Pass null to
## clear via hide_range().
##
## 049 / AC-6: this multi-ability variant does NOT classify validity — it
## paints the union of all reachable target hexes as "valid". Per-ability
## validity is computed in show_range_for_ability (the FSM step path). The
## legacy union variant is kept for callers that don't drive an FSM.
func show_range(caster: Actor, skill_or_id) -> void:
	hide_range()
	if _grid == null or caster == null or skill_or_id == null:
		return
	var caster_coord: Vector2i = _grid.get_coord(caster.actor_id)
	if caster_coord == Vector2i(-1, -1):
		return
	# Collect target hexes from one or many abilities.
	var hexes: Dictionary = {}  # Vector2i → true (dedup across abilities)
	if "abilities" in skill_or_id:
		for ab in skill_or_id.abilities:
			if ab == null or ab.target == null:
				continue
			for c in ab.target.get_range_hexes(caster_coord, _grid):
				hexes[c] = true
	else:
		var ability: Ability = AbilityDatabase.get_ability(StringName(str(skill_or_id)))
		if ability == null or ability.target == null:
			return
		for c in ability.target.get_range_hexes(caster_coord, _grid):
			hexes[c] = true
	for c in hexes.keys():
		_coords_valid.append(c)
	_color = UiTheme.SEM_DEBUFF
	queue_redraw()


## 026: per-ability range — used by godmode_controller's multi-step cast FSM
## to highlight only the hexes valid for `ability` (not the whole skill).
##
## 049 / AC-6: classifies each range hex into valid/invalid via
## ability.target.resolve(caster, per_hex_ctx). Validity here mirrors the
## FSM commit-step gate — clicking a "valid" hex is guaranteed to commit the
## step (`CastFsm.handle_lmb` accepts any hex in `target.get_range_hexes`,
## while resolve gates the actual cast); the visual matches game logic.
##
## Note: actors_node + tile_object_resolver are NOT required for the
## validity check (only CreateEffect's apply path uses them, and we run only
## resolve, not cast). Skipping them keeps overlay decoupled from godmode
## sub-tree shape.
func show_range_for_ability(caster: Actor, ability: Ability) -> void:
	hide_range()
	if _grid == null or caster == null or ability == null or ability.target == null:
		return
	var caster_coord: Vector2i = _grid.get_coord(caster.actor_id)
	if caster_coord == Vector2i(-1, -1):
		return
	var range_hexes: Array[Vector2i] = ability.target.get_range_hexes(caster_coord, _grid)
	for c in range_hexes:
		var ctx: Dictionary = {
			"registry": _registry,
			"grid": _grid,
			"target_id": _grid.get_actor_at(c),
			"target_coord": c,
		}
		if ability.target.resolve(caster, ctx) != null:
			_coords_valid.append(c)
		else:
			_coords_invalid.append(c)
	_color = UiTheme.SEM_DEBUFF
	queue_redraw()


## 026: highlight caster's hex for a self-target step. LMB anywhere on
## screen confirms (handled by godmode_controller — this is just the visual).
## Color uses SEM_HEAL to distinguish from offensive range. Drawn with a
## bolder outline + faint fill so the single hex reads unambiguously as a
## confirm target (vs a field of thin outlines for a multi-hex range).
func show_self_confirm(coord: Vector2i) -> void:
	hide_range()
	if _grid == null:
		return
	_self_coord = coord
	_color = UiTheme.SEM_HEAL
	queue_redraw()


func hide_range() -> void:
	if _coords_valid.is_empty() and _coords_invalid.is_empty() and _self_coord == Vector2i(-1, -1):
		return
	_coords_valid = []
	_coords_invalid = []
	_self_coord = Vector2i(-1, -1)
	queue_redraw()


func _on_theme_reloaded() -> void:
	# Color was captured at show-time from UiTheme; rebuild on hot-reload so a
	# styling iteration is reflected without re-entering the cast FSM.
	if _self_coord != Vector2i(-1, -1):
		_color = UiTheme.SEM_HEAL
	else:
		_color = UiTheme.SEM_DEBUFF
	queue_redraw()


func _draw() -> void:
	if _grid == null:
		return
	var layer: TileMapLayer = _grid.tile_map_layer
	if layer == null or layer.tile_set == null:
		return
	var corners: PackedVector2Array = HexGeometry.flat_top_polygon(Vector2(layer.tile_set.tile_size))
	if corners.is_empty():
		return
	# 029 / req-4: paint_preview-style thin outlines per hex (no fill).
	# alpha 0.55 is visible against grid lines without competing with the
	# cursor (z=7) on top.
	var valid_color: Color = Color(_color.r, _color.g, _color.b, 0.55)
	for c in _coords_valid:
		var center: Vector2 = layer.map_to_local(c)
		for i in 6:
			draw_line(center + corners[i], center + corners[(i + 1) % 6],
					valid_color, 1.5, true)
	# 049 / AC-6: invalid hexes — dim grey outline. Same line weight, just
	# desaturated — same brush as the editor's "out-of-bounds" hint, so the
	# read across the whole game is consistent ("grey = can't act here").
	var invalid_color: Color = Color(UiTheme.INVALID_TARGET_COLOR.r, UiTheme.INVALID_TARGET_COLOR.g, UiTheme.INVALID_TARGET_COLOR.b, 0.30)
	for c in _coords_invalid:
		var center2: Vector2 = layer.map_to_local(c)
		for i in 6:
			draw_line(center2 + corners[i], center2 + corners[(i + 1) % 6],
					invalid_color, 1.5, true)
	# Self-confirm: bolder closed-loop outline + faint fill on the single hex.
	if _self_coord != Vector2i(-1, -1):
		var center3: Vector2 = layer.map_to_local(_self_coord)
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(center3 + corners[i])
		draw_colored_polygon(pts, Color(_color.r, _color.g, _color.b, 0.30))
		for i in 6:
			draw_line(pts[i], pts[(i + 1) % 6],
					Color(_color.r, _color.g, _color.b, 0.85), 2.5, true)
