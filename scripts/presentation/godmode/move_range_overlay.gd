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

# Edge index → Godot CELL_NEIGHBOR_* enum. Maps polygon edge i (between
# corners[i] and corners[(i+1)%6]) to the neighbor cell on the other side
# of that edge. Used for boundary-edge detection in _draw_zone_outline:
# an edge is on the zone border iff the corresponding neighbor is NOT in
# the zone.
#
# Polygon corner layout from HexGeometry.flat_top_polygon (CCW screen-space):
#   0=R, 1=BR, 2=BL, 3=L, 4=TL, 5=TR
# Edge 0(R→BR) faces BOTTOM_RIGHT_SIDE; edge 1(BR→BL) faces BOTTOM_SIDE; etc.
const _EDGE_NEIGHBOR_DIRS: Array = [
	TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,  # edge 0
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,        # edge 1
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,   # edge 2
	TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE,      # edge 3
	TileSet.CELL_NEIGHBOR_TOP_SIDE,           # edge 4
	TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,     # edge 5
]

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


func setup(grid: Node) -> void:
	_grid = grid


func _ready() -> void:
	z_index = 2
	EventBus.ui_theme_reloaded.connect(queue_redraw)


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


## Wipe everything (move zone, attack range, AoE preview).
func clear() -> void:
	if _zone_coords.is_empty() and _attack_coords.is_empty() and _zone_preview.is_empty():
		return
	_zone_coords = {}
	_attack_coords = []
	_zone_preview = []
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
	_draw_zone_outline(layer, corners)

	# 2) Self-hex marker — small dot at actor center. Subtle, just a "you are
	#    here" affordance. The boundary outline already implies "inside the
	#    zone is where you stand"; a full hex highlight on self competes with it.
	if _self_coord != Vector2i(-1, -1):
		var center: Vector2 = layer.map_to_local(_self_coord)
		draw_circle(center, 3.5, Color(UiTheme.SEM_HEAL.r, UiTheme.SEM_HEAL.g, UiTheme.SEM_HEAL.b, 0.9))

	# 3) Attack-range — per-hex thin outlines (paint_preview style).
	var attack_line: Color = Color(_attack_color.r, _attack_color.g, _attack_color.b, 0.55)
	for c in _attack_coords:
		var cen: Vector2 = layer.map_to_local(c)
		for i in 6:
			draw_line(cen + corners[i], cen + corners[(i + 1) % 6],
					attack_line, 1.5, true)

	# 4) AoE preview — per-hex thin outlines, slightly brighter alpha than
	#    attack range so the cursor-anchored preview pops over the static
	#    range overlay underneath.
	var aoe_line: Color = Color(_zone_preview_color.r, _zone_preview_color.g, _zone_preview_color.b, 0.80)
	for c in _zone_preview:
		var cen: Vector2 = layer.map_to_local(c)
		for i in 6:
			draw_line(cen + corners[i], cen + corners[(i + 1) % 6],
					aoe_line, 2.0, true)


## 029 / req-3: outline ONLY the boundary edges of the zone (not per-hex).
## For each cell in the zone, for each of its 6 edges, draw the edge IFF
## the neighbor on the other side of that edge is NOT in the zone. Result:
## one continuous contour around the entire walkable region.
##
## Cost: O(N * 6) where N = zone size. For typical reach (≤12 hexes) that's
## ~72 edge tests per redraw — cheap. queue_redraw is only called on
## show_for / theme reload, not per-frame.
func _draw_zone_outline(layer: TileMapLayer, corners: PackedVector2Array) -> void:
	if _zone_coords.is_empty():
		return
	# Outline color: team color, high alpha so the contour reads clearly.
	# Width 2.5 px reads as "intentional UI element" vs the 1.5 px brush outlines.
	var outline: Color = Color(_zone_color.r, _zone_color.g, _zone_color.b, 0.90)
	for coord_v in _zone_coords.keys():
		var coord: Vector2i = coord_v
		var center: Vector2 = layer.map_to_local(coord)
		for edge_idx in 6:
			var neighbor_dir: int = _EDGE_NEIGHBOR_DIRS[edge_idx]
			var neighbor: Vector2i = layer.get_neighbor_cell(coord, neighbor_dir)
			if _zone_coords.has(neighbor):
				continue   # internal edge — neighbor is also in the zone
			# Boundary edge — draw it.
			draw_line(center + corners[edge_idx], center + corners[(edge_idx + 1) % 6],
					outline, 2.5, true)
