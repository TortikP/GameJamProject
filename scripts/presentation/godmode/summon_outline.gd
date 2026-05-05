extends Node2D
## SummonOutline — hex-shaped ring drawn under a summoned actor's body.
##
## Visible iff the parent Actor carries the `summoned` status. Color
## comes from UiTheme.summon_outline_color(team): green for player-side,
## red for enemy-side. Hidden for non-summoned actors (regular wave
## enemies, manekins) so the ring stays a clean "this is a temporary
## summon" cue rather than a generic team marker — HP-bar frame already
## carries the team channel.
##
## Lifecycle:
##   1. _ready resolves parent Actor + grid (HexGrid ancestor) and
##      connects to actor.statuses_changed. Initial state polled via a
##      deferred call because CreateEffect adds the `summoned` status
##      AFTER spawn_enemy_at returns (i.e. AFTER our _ready has run).
##   2. Each statuses_changed → re-evaluate visibility + queue_redraw.
##      Cheap (Dictionary lookup + visibility flip).
##   3. Polygon comes from HexGeometry.flat_top_polygon_for_layer, so
##      the ring follows whatever tile_size the active TileMapLayer
##      reports — no hardcoded radius (CLAUDE.md hard rule #6).
##
## Z-index: set to (Body.z_index - 1) at runtime so the ring renders
## under the body sprite. Body z_index varies between enemy.tscn (4)
## and any future summon scene that overrides it.

const HexGeometry = preload("res://scripts/infrastructure/hex_geometry.gd")
const SUMMON_STATUS: StringName = &"summoned"

var _actor: Actor = null
var _grid: HexGrid = null


func _ready() -> void:
	_actor = get_parent() as Actor
	if _actor == null:
		# Test scenes / sandbox actors without an Actor parent — silent skip.
		visible = false
		return
	# Slot under the body sprite. enemy.tscn Body sits at z_index=4;
	# we fall back to 3 if Body isn't present.
	var body: Node = _actor.get_node_or_null("Body")
	z_index = (body.z_index - 1) if (body is CanvasItem) else 3
	_grid = _resolve_grid()
	visible = false
	# Per-actor signal — only fires for THIS actor, no global churn.
	_actor.statuses_changed.connect(_on_actor_statuses_changed)
	# 041 timing: CreateEffect calls add_status AFTER spawn_enemy_at's
	# add_child triggers _ready here. Defer one frame so the initial
	# state catches the status.
	_refresh.call_deferred()


func _on_actor_statuses_changed(_id: StringName) -> void:
	_refresh()


func _refresh() -> void:
	if _actor == null:
		visible = false
		return
	var has_summoned: bool = _actor.has_status(SUMMON_STATUS)
	if visible == has_summoned:
		# No state change — but still re-queue draw in case team flipped
		# (paranoid; team change post-spawn isn't a known path today).
		if has_summoned:
			queue_redraw()
		return
	visible = has_summoned
	if has_summoned:
		queue_redraw()


func _draw() -> void:
	if _actor == null:
		return
	var color: Color = UiTheme.summon_outline_color(_actor.team)
	var poly: PackedVector2Array
	if _grid != null and _grid.tile_map_layer != null:
		poly = HexGeometry.flat_top_polygon_for_layer(_grid.tile_map_layer)
	if poly.is_empty():
		# Grid not yet resolvable (early scene init) — wait for next refresh.
		return
	# draw_polyline doesn't auto-close — append the first vertex so the
	# stroke joins cleanly at vertex 0.
	var closed := PackedVector2Array(poly)
	closed.append(poly[0])
	draw_polyline(closed, color, UiTheme.SUMMON_OUTLINE_THICKNESS, true)


func _resolve_grid() -> HexGrid:
	# Walk up the scene tree; HexGrid is always an ancestor when actor is
	# placed via grid.place_actor (which is the only supported spawn path).
	var p: Node = get_parent()
	while p != null:
		if p is HexGrid:
			return p
		p = p.get_parent()
	return null
