extends Node2D
## MoveRangeOverlay — visualizes "where can the player go this turn" + the
## active ability's reach + the AoE zone the cursor would land. All three
## layers are now drawn in a single _draw() pass (no per-hex Polygon2D + Line2D
## nodes). Same Node2D parent / z-index conventions, just lighter on allocs
## and the visual is a clean editor-brush style.
##
## 029 / req-3, req-4:
##   - MOVE RANGE: drawn as a SINGLE BOUNDARY OUTLINE around the whole
##     reachable region (not a fill or per-hex outline). Reads as "this is the
##     area you can walk inside" — matches how a typical CRPG paints movement
##     zones. Uses team color.
##   - ATTACK RANGE: per-hex thin outlines, paint_preview style (mirrors
##     CastRangeOverlay). Active slot's abilities[] feed in. Uses SEM_DEBUFF.
##   - AOE ZONE PREVIEW (cursor hover): per-hex thin outlines too. Uses
##     SEM_CONTROL — purple is the "this is what would be hit" semantic.
##
## Pathfinding around enemies/obstacles is already correct (occupied list
## passed to HexGrid.reachable_within); this rewrite is presentation-only.
##
## Z-index: 2 (set in scene). Below CastRangeOverlay (z=4), below cursor (z=7).

const HexGeometry = preload("res://scripts/infrastructure/hex_geometry.gd")

# 029 / B-003: removed the polygon-edge-index → CELL_NEIGHBOR_*_SIDE enum table.
# The mapping was correct for tile_shape = HEXAGON but Godot returns different
# neighbor coords for the same enums on tile_shape = HALF_OFFSET_SQUARE, which
# is what hex_terrain.tres currently uses. Now boundary detection works
# geometrically: for each polygon edge, project a sample point just past the
# edge midpoint and ask the layer which cell owns that point via local_to_map.
# Independent of tile_shape interpretation — works on either tileset. Slightly
# more work per edge (vec math + one local_to_map call) but still O(N * 6),
# negligible for N ≤ 20 typical zone sizes.

var _grid: Node = null  # HexGrid

# Move-range zone (drawn as boundary outline). Includes the actor's own hex.
var _zone_coords: Dictionary = {}   # Vector2i → true (set semantics for fast neighbor lookups)
var _self_coord: Vector2i = Vector2i(-1, -1)
var _zone_color: Color = Color.WHITE

# Attack-range hexes (per-hex outlines).
var _attack_coords: Array[Vector2i] = []
var _attack_color: Color = Color.WHITE

# AoE preview (per-hex outlines, refreshed every frame from controller).
var _zone_preview: Array[Vector2i] = []
var _zone_preview_color: Color = Color.WHITE

# 029 / bonus-2: hover-path preview. Coords from the actor to the cursor's
# hex (inclusive). Empty when the cursor isn't over a reachable hex (or hover
# is on the actor's own coord). Pushed by godmode_controller every frame from
# _update_castability.
var _hover_path: Array[Vector2i] = []

# 029 / bonus-3: breathing alpha on the move-zone boundary outline. Phase
# advances in _process; alpha modulates as a sine across BREATH_PERIOD_S.
# Costs one queue_redraw per frame while the zone is active — _draw is cheap
# for typical zone sizes (~12 hexes × 6 edges = 72 line draws max).
const BREATH_PERIOD_S: float = 1.6
const BREATH_AMP: float = 0.18           # peak ± from mid-alpha
const BREATH_MID_ALPHA: float = 0.78     # average alpha — boundary is ALWAYS visible
var _breath_phase: float = 0.0


func setup(grid: Node) -> void:
	_grid = grid


func _ready() -> void:
	z_index = 2
	EventBus.ui_theme_reloaded.connect(queue_redraw)


# 029 / bonus-3: advance breath phase + redraw while a zone is shown. No-op
# when no zone — saves a per-frame draw call when the player has no movement
# (cleared zone, e.g. during AI turn or stunned).
func _process(delta: float) -> void:
	if _zone_coords.is_empty():
		return
	_breath_phase += delta
	queue_redraw()


# ── Public API (same surface as before — controller calls untouched) ────────

## AoE preview around the cursor; called every frame from _update_castability.
## Pass [] to erase. Color: SEM_CONTROL ("this is the area that would be hit").
func show_zone_preview(hexes: Array[Vector2i]) -> void:
	if _zone_preview == hexes:
		return
	_zone_preview = hexes
	_zone_preview_color = UiTheme.SEM_CONTROL
	queue_redraw()


func clear_zone_preview() -> void:
	if _zone_preview.is_empty():
		return
	_zone_preview = []
	queue_redraw()


## 029 / bonus-2: set hover-path preview — line through hex centers from the
## actor to the hovered hex. Pass [] to clear. Caller pushes new coords every
## frame; we no-op when unchanged to skip redundant queue_redraw calls (the
## breathing _process triggers redraws anyway, so visual updates are immediate
## either way).
func set_hover_path(coords: Array[Vector2i]) -> void:
	if _hover_path == coords:
		return
	_hover_path = coords
	queue_redraw()


## Wipe everything (move zone, attack range, AoE preview, hover path).
func clear() -> void:
	if _zone_coords.is_empty() and _attack_coords.is_empty() and _zone_preview.is_empty() and _hover_path.is_empty():
		return
	_zone_coords = {}
	_attack_coords = []
	_zone_preview = []
	_hover_path = []
	_self_coord = Vector2i(-1, -1)
	queue_redraw()


## Show reachable hexes for `actor`. `registry` is ActorRegistry — used to
## build the occupied list so BFS doesn't route through other actors.
## `ability_items` — Ability instances (or legacy StringName ids) for the
## currently active slot's skill. Pass [] to skip attack-range layer.
func show_for(actor: Actor, registry: Node, ability_items: Array) -> void:
	if _grid == null or actor == null:
		clear()
		return
	var actor_coord: Vector2i = _grid.get_coord(actor.actor_id)
	if actor_coord == Vector2i(-1, -1):
		clear()
		return

	# ── Build occupied list (other actors block pathing) ───────────────────
	var occupied: Array = []
	if registry != null and registry.has_method("all"):
		for a in registry.all():
			if a is Actor and (a as Actor).actor_id != actor.actor_id:
				var c: Vector2i = _grid.get_coord((a as Actor).actor_id)
				if c != Vector2i(-1, -1):
					occupied.append(c)

	# ── Move zone ─────────────────────────────────────────────────────────
	# 027: effective_speed accounts for slowed (×0.5) and rooted (→0).
	var reachable: Array[Vector2i] = _grid.reachable_within(
			actor_coord, actor.effective_speed(), occupied)
	_zone_coords = {}
	# Always include the actor's own hex so the boundary closes around it
	# (player standing inside the zone, not on an island).
	_zone_coords[actor_coord] = true
	for c in reachable:
		_zone_coords[c] = true
	_self_coord = actor_coord
	_zone_color = UiTheme.team_color(actor.team)

	# ── Attack range ──────────────────────────────────────────────────────
	# Item is either an Ability object (preferred — direct ref) or a
	# StringName id (legacy enemy path). Object route avoids AbilityDatabase
	# collisions when multiple skills share an ability id.
	var attack_set: Dictionary = {}
	for item in ability_items:
		var ability: Ability
		if item is Ability:
			ability = item as Ability
		else:
			ability = AbilityDatabase.get_ability(StringName(str(item)))
		if ability == null or ability.target == null:
			continue
		for c in ability.target.get_range_hexes(actor_coord, _grid):
			attack_set[c] = true
	_attack_coords = []
	for c in attack_set.keys():
		_attack_coords.append(c)
	_attack_color = UiTheme.SEM_DEBUFF

	queue_redraw()


# ── Drawing ─────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _grid == null:
		return
	var layer: TileMapLayer = _grid.tile_map_layer
	if layer == null or layer.tile_set == null:
		return
	var corners: PackedVector2Array = HexGeometry.flat_top_polygon(Vector2(layer.tile_set.tile_size))
	if corners.is_empty():
		return

	# 1) Move zone — single boundary outline around the whole reachable region.
	#    Alpha breathes via _breath_phase (bonus-3).
	_draw_zone_outline(layer, corners)

	# 2) Self-hex marker — small dot at actor center. Subtle, just a "you are
	#    here" affordance. The boundary outline already implies "inside the
	#    zone is where you stand"; a full hex highlight on self competes with it.
	if _self_coord != Vector2i(-1, -1):
		var center: Vector2 = layer.map_to_local(_self_coord)
		draw_circle(center, 3.5, Color(UiTheme.SEM_HEAL.r, UiTheme.SEM_HEAL.g, UiTheme.SEM_HEAL.b, 0.9))

	# 3) Hover-path preview (bonus-2). Drawn AFTER the zone outline (so the
	#    line sits on top) but BEFORE attack/AoE outlines (so range overlays
	#    aren't crossed by it). Skip when only one coord (player on themselves)
	#    or empty.
	if _hover_path.size() >= 2:
		_draw_hover_path(layer)

	# 4) Attack-range — per-hex thin outlines (paint_preview style).
	var attack_line: Color = Color(_attack_color.r, _attack_color.g, _attack_color.b, 0.55)
	for c in _attack_coords:
		var cen: Vector2 = layer.map_to_local(c)
		for i in 6:
			draw_line(cen + corners[i], cen + corners[(i + 1) % 6],
					attack_line, 1.5, true)

	# 5) AoE preview — per-hex thin outlines, slightly brighter alpha than
	#    attack range so the cursor-anchored preview pops over the static
	#    range overlay underneath.
	var aoe_line: Color = Color(_zone_preview_color.r, _zone_preview_color.g, _zone_preview_color.b, 0.80)
	for c in _zone_preview:
		var cen: Vector2 = layer.map_to_local(c)
		for i in 6:
			draw_line(cen + corners[i], cen + corners[(i + 1) % 6],
					aoe_line, 2.0, true)


## 029 / req-3 + bonus-3 + B-003: outline ONLY the boundary edges of the zone.
## For each cell in the zone, for each of its 6 polygon edges, draw the edge
## IFF the cell that owns the point JUST PAST the edge midpoint is NOT in the
## zone. Geometric — no dependency on TileSet's CellNeighbor enum semantics
## (which differ between HEXAGON and HALF_OFFSET_SQUARE shapes — see B-003).
##
## Bonus-3: alpha modulates as a sine across BREATH_PERIOD_S. Mid-alpha is
## high enough that the contour is always clearly visible — the breathing is
## a "this is alive UI" cue, not a flash that loses information.
##
## Cost: O(N * 6) where N = zone size. Per edge: 1 local_to_map call (cheap
## hash on the layer's tile grid). For typical reach (≤12 hexes) that's
## ~72 probes per redraw — still cheap, called per frame for the breath.
func _draw_zone_outline(layer: TileMapLayer, corners: PackedVector2Array) -> void:
	if _zone_coords.is_empty():
		return
	# Breathing alpha — sine across the full period, centered on
	# BREATH_MID_ALPHA, peak ±BREATH_AMP. Width 2.5 px reads as "intentional
	# UI element" vs the 1.5 px brush outlines below.
	var t: float = (_breath_phase / BREATH_PERIOD_S) * TAU
	var alpha: float = clampf(BREATH_MID_ALPHA + BREATH_AMP * sin(t), 0.0, 1.0)
	var outline: Color = Color(_zone_color.r, _zone_color.g, _zone_color.b, alpha)
	for coord_v in _zone_coords.keys():
		var coord: Vector2i = coord_v
		var center: Vector2 = layer.map_to_local(coord)
		for edge_idx in 6:
			var v_a: Vector2 = corners[edge_idx]
			var v_b: Vector2 = corners[(edge_idx + 1) % 6]
			# Probe a point past the edge midpoint, away from the cell center.
			# midpoint × 1.4 in local space lands a few pixels inside the
			# neighbor cell. local_to_map then routes through the tileset's
			# actual neighbor topology — works on HEXAGON and HALF_OFFSET_SQUARE
			# alike (no enum mapping needed).
			var probe: Vector2 = center + (v_a + v_b) * 0.5 * 1.4
			var neighbor: Vector2i = layer.local_to_map(probe)
			if neighbor == coord:
				# Probe didn't escape the cell (very squashed tile geometry).
				# Try a bigger reach as fallback.
				neighbor = layer.local_to_map(center + (v_a + v_b) * 0.5 * 2.0)
			if neighbor != coord and _zone_coords.has(neighbor):
				continue   # internal edge — neighbor is also in the zone
			# Boundary edge — draw it.
			draw_line(center + v_a, center + v_b, outline, 2.5, true)


## 029 / bonus-2: draw a thin polyline through hex centers along _hover_path.
## Source coord is the actor (path[0]), terminal is the hovered hex
## (path[-1]). Color: team-color for cohesion with the zone outline. Endpoint
## gets a small filled disc to make "this is where you'd land" unambiguous.
func _draw_hover_path(layer: TileMapLayer) -> void:
	if _hover_path.size() < 2:
		return
	# Polyline. polyline draw call would also work but draws unsmoothed —
	# explicit per-segment draw_line lets us pass antialiased=true cheaply.
	var col: Color = Color(_zone_color.r, _zone_color.g, _zone_color.b, 0.85)
	for i in range(1, _hover_path.size()):
		var a: Vector2 = layer.map_to_local(_hover_path[i - 1])
		var b: Vector2 = layer.map_to_local(_hover_path[i])
		draw_line(a, b, col, 2.0, true)
	# Endpoint marker — small filled disc at the destination so the eye lands
	# on "I will be HERE" without parsing the polyline.
	var end_pos: Vector2 = layer.map_to_local(_hover_path[_hover_path.size() - 1])
	draw_circle(end_pos, 4.5, Color(_zone_color.r, _zone_color.g, _zone_color.b, 0.95))
