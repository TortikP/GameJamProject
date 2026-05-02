extends Node
## HoverDispatcher — owns per-frame _process. Dispatches: slot castability tints,
## hp-bar damage preview on hovered enemy, AoE zone preview on cursor, hover-path
## preview, and cast-intent tooltip on hovered enemy.

const SkillFormatter = preload("res://scripts/presentation/skill_formatter.gd")

var _ctrl: Node = null

# 029 / req-6: track which enemy is currently under cursor (or &"") so we can
# show/hide the cast-intent tooltip with no flicker on idle frames.
var _hover_intent_actor_id: StringName = &""


func _ready() -> void:
	_ctrl = get_parent()


func _process(_delta: float) -> void:
	update_castability()


func update_castability() -> void:
	var slot_bar: Node = _ctrl.slot_bar
	var grid: HexGrid = _ctrl.grid
	var registry: ActorRegistry = _ctrl.registry
	var player: Actor = _ctrl.player
	var overlay: Node = _ctrl.overlay
	if slot_bar == null or grid == null or registry == null or player == null:
		return
	var coord := grid.coord_under_mouse()
	var target_id: StringName = &""
	if coord != Vector2i(-1, -1):
		target_id = grid.get_actor_at(coord)
	var ctx: Dictionary = {
		"registry": registry,
		"grid": grid,
		"target_id": target_id,
		"target_coord": coord,
	}
	# Slot castability tints. 027: stunned player → all slots greyed.
	var stunned: bool = player.is_stunned()
	for i in 4:
		var skill := slot_bar.get_slot(i) as Skill
		var castable: bool = skill != null and not stunned and skill.can_apply(player, ctx)
		slot_bar.set_castable(i, castable)

	# Damage preview on enemies — only the hovered one shows red strip,
	# others get cleared. Active slot's ability is the source.
	var active_idx: int = slot_bar.get_active()
	var active_skill := slot_bar.get_slot(active_idx) as Skill
	var hover_target: Actor = registry.get_actor(target_id) if target_id != &"" else null
	var preview_for_hover: int = 0
	if active_skill != null and hover_target != null and hover_target.team == &"enemy":
		if active_skill.can_apply(player, ctx):
			preview_for_hover = active_skill.predicted_damage_to(player, hover_target, ctx)
	for actor in registry.all():
		if not (actor is Actor):
			continue
		var a: Actor = actor
		if a.team != &"enemy":
			continue
		var hp_bar: Node = a.get_node_or_null("HealthBar")
		if hp_bar == null or not hp_bar.has_method("set_preview_damage"):
			continue
		hp_bar.set_preview_damage(preview_for_hover if a == hover_target else 0)

	# Zone AoE preview — repaint every frame so it follows the cursor.
	if overlay != null and overlay.has_method("show_zone_preview"):
		var zone_hexes: Array[Vector2i] = []
		# 031 phase 13: paint only the *current* ability's area, not the union
		# of every ability in the skill. Previously the loop merged every
		# ability's affected hexes into one dedup'd dictionary → always
		# painted the largest radius across the skill (paper_jam: 3
		# abilities with radii 1/1/2 → 2-radius blob always shown).
		# During the FSM the "current" ability is the step the next click
		# resolves; idle preview falls back to abilities[0]. cast_fsm is
		# the shared source of truth with controller.refresh_overlay.
		var preview_ability: Ability = _ctrl.cast_fsm.current_preview_ability()
		if preview_ability != null and preview_ability.area != null and coord != Vector2i(-1, -1):
			var caster_coord: Vector2i = grid.get_coord(player.actor_id)
			var anchor: Vector2i = coord
			if preview_ability.target != null:
				anchor = preview_ability.target.preview_anchor_coord(caster_coord, coord)
			zone_hexes = preview_ability.area.get_affected_hexes(caster_coord, anchor, grid)
		overlay.show_zone_preview(zone_hexes)

	# 029 / bonus-2: hover-path preview. Show the route the player would take
	# IFF the cursor is over a reachable hex (within effective_speed) AND
	# isn't blocked. Skipped during cast FSM and stun — neither is "I'm
	# considering moving here" mode. Path is recomputed via find_path_around
	# with live actor blocks so it bends around enemies — same set the move
	# zone was computed against, so reachability and path agree.
	refresh_hover_path(coord)

	# 029 / req-6: tooltip on enemy hover that shows their planned cast.
	# Only fires for enemies that have a non-null cast_intent — moving-only
	# turns or idle holds get no tooltip (nothing to telegraph). The hex
	# already shows the intent visually; tooltip adds the "what is this
	# spell exactly" detail.
	refresh_intent_tooltip(target_id)


## 029 / bonus-2: hover-path computation + push to overlay. Cheap when no
## change (overlay early-returns on identical array) so calling per frame is OK.
func refresh_hover_path(hover_coord: Vector2i) -> void:
	var overlay: Node = _ctrl.overlay
	var grid: HexGrid = _ctrl.grid
	var registry: ActorRegistry = _ctrl.registry
	var player: Actor = _ctrl.player
	if overlay == null or not overlay.has_method("set_hover_path"):
		return
	if player == null or grid == null:
		overlay.set_hover_path([] as Array[Vector2i])
		return
	# Skip during cast FSM (player is targeting, not considering movement) and
	# during AI turns / stun.
	if _ctrl.cast_fsm.is_in_progress() or _ctrl.ai.is_world_processing() or player.is_stunned():
		overlay.set_hover_path([] as Array[Vector2i])
		return
	var from: Vector2i = grid.get_coord(player.actor_id)
	if from == Vector2i(-1, -1) or hover_coord == Vector2i(-1, -1) or hover_coord == from:
		overlay.set_hover_path([] as Array[Vector2i])
		return
	if not grid.is_walkable(hover_coord) or grid.get_actor_at(hover_coord) != &"":
		overlay.set_hover_path([] as Array[Vector2i])
		return
	# Build live actor-block list — same convention as _resolve_move_intent
	# and the move-zone occupied list, so paths match the boundary visually.
	var blocked: Array = []
	for actor_v in registry.all():
		if not (actor_v is Actor):
			continue
		var a: Actor = actor_v
		if a == player or not a.is_alive():
			continue
		var c: Vector2i = grid.get_coord(a.actor_id)
		if c != Vector2i(-1, -1):
			blocked.append(c)
	var path: Array = grid.find_path_around(from, hover_coord, blocked)
	if path.size() < 2:
		overlay.set_hover_path([] as Array[Vector2i])
		return
	# Cap to effective_speed — only show preview if it's actually reachable
	# THIS turn (path.size() - 1 = number of steps).
	if path.size() - 1 > player.effective_speed():
		overlay.set_hover_path([] as Array[Vector2i])
		return
	# Re-type Array → Array[Vector2i] for the typed setter.
	var typed: Array[Vector2i] = []
	for c in path:
		typed.append(c)
	overlay.set_hover_path(typed)


## 029 / req-6: hover-on-enemy → cast-intent tooltip dispatch. State-tracked so
## moving the cursor between hexes doesn't spam show_tooltip every frame —
## tooltip only re-renders when the hovered actor id actually changes.
func refresh_intent_tooltip(hovered_id: StringName) -> void:
	var registry: ActorRegistry = _ctrl.registry
	# Resolve to "do we have an enemy with a planned cast under cursor?"
	var new_id: StringName = &""
	if hovered_id != &"" and registry != null:
		var hov: Actor = registry.get_actor(hovered_id)
		if hov != null and hov.team == &"enemy" and hov.is_alive() and hov.cast_intent != null:
			new_id = hovered_id
	if new_id == _hover_intent_actor_id:
		return  # no transition — current tooltip state is correct
	_hover_intent_actor_id = new_id
	var tooltip: Node = get_node_or_null("../../HUD/TooltipPanel")
	if tooltip == null:
		return
	if new_id == &"":
		if tooltip.has_method("hide_tooltip"):
			tooltip.hide_tooltip()
		return
	# Render: skill id headline + formatted body. SkillFormatter is the same
	# helper PSP/inspector use — single source of truth, so a buff/CD note
	# changes everywhere at once.
	var actor: Actor = registry.get_actor(new_id)
	var ci: CastIntent = actor.cast_intent as CastIntent
	if ci == null:
		return
	var skill: Skill = SkillDatabase.get_skill(ci.skill_id)
	if skill == null:
		return
	var title: String = "%s → %s" % [String(actor.actor_id), String(skill.id)]
	var body: String = SkillFormatter.format_skill(skill)
	if tooltip.has_method("show_tooltip"):
		# anchor=null → tooltip places itself near the mouse pointer (see
		# tooltip_panel.gd::_place_near).
		tooltip.show_tooltip(null, title, body)
