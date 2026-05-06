extends Node
## HoverDispatcher — owns per-frame _process. Dispatches: slot castability tints,
## hp-bar damage preview on hovered enemy, AoE zone preview on cursor, hover-path
## preview, hex-tooltip multi-row build, and enemy-details-panel binding.
##
## 049: replaces 029's single-actor `refresh_intent_tooltip` with two
## hover dispatches:
##   - refresh_hex_tooltip(coord)  — cursor-anchored multi-row table aggregating
##                                    every action targeting `coord`.
##   - refresh_enemy_details(id)   — top-right panel bound to whichever enemy
##                                    the cursor is over.
## Both are state-tracked (`_last_hex_tooltip_coord`, `_last_enemy_details_id`)
## so movement within a single hex / cursor over the same enemy doesn't spam
## rebuilds.

const SkillFormatter = preload("res://scripts/presentation/skill_formatter.gd")

var _ctrl: Node = null

# 049 / AC-4: state guard on the enemy-details panel — re-binding the same
# actor would trip signal disconnect/reconnect cycles, so we only call
# bind/unbind on transitions. (Hex-tooltip dropped its similar guard in
# 049b T037 — see refresh_hex_tooltip.)
var _last_enemy_details_id: StringName = &""


func _ready() -> void:
	_ctrl = get_parent()


func _process(_delta: float) -> void:
	update_castability()
	# 049 / AC-2 + AC-4 + T020: dispatch hex-tooltip + enemy-details after
	# the castability pass. coord_under_mouse is cheap (single sample) and
	# update_castability already calls it internally — recomputing here
	# keeps each dispatch self-contained without threading the value down.
	var grid: HexGrid = _ctrl.grid
	if grid == null:
		return
	var coord: Vector2i = grid.coord_under_mouse()
	var target_id: StringName = grid.get_actor_at(coord) if coord != Vector2i(-1, -1) else &""
	refresh_hex_tooltip(coord)
	refresh_enemy_details(target_id)


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

	# Zone AoE preview — compute FIRST (051): the zone drives both the
	# overlay paint AND the per-enemy HP preview below. One source of
	# truth — players can't see a hex highlighted "in zone" without the
	# enemy on it ALSO showing their predicted HP, and vice versa.
	#
	# 031 phase 13 invariant retained: paint only the *current* ability's
	# area (FSM step or abilities[0] when idle). cast_fsm is the shared
	# truth with controller.refresh_overlay.
	var zone_hexes: Array[Vector2i] = []
	var active_idx: int = slot_bar.get_active()
	var active_skill := slot_bar.get_slot(active_idx) as Skill
	var preview_ability: Ability = _ctrl.cast_fsm.current_preview_ability()
	if preview_ability != null and preview_ability.area != null and coord != Vector2i(-1, -1):
		var caster_coord: Vector2i = grid.get_coord(player.actor_id)
		var anchor: Vector2i = coord
		if preview_ability.target != null:
			anchor = preview_ability.target.preview_anchor_coord(caster_coord, coord)
		zone_hexes = preview_ability.area.get_affected_hexes(caster_coord, anchor, grid)
	if overlay != null and overlay.has_method("show_zone_preview"):
		overlay.show_zone_preview(zone_hexes)

	# Damage preview on enemies (051): every enemy whose coord is in
	# zone_hexes gets a preview, not just the one literally under the
	# cursor. For radius-1 coffee that means BOTH neighbours of the
	# anchor light up, so the player sees the full splash before the
	# click. Outside-zone enemies always cleared to 0.
	#
	# Skill must (a) exist, (b) pass can_apply at the cursor ctx — same
	# gate used by FSM commit, so preview matches what a click actually
	# does. Non-damage skills naturally yield 0 from predicted_damage_to,
	# so heal/buff abilities don't paint a phantom red strip.
	var preview_active: bool = (
		active_skill != null
		and not stunned
		and active_skill.can_apply(player, ctx)
		and not zone_hexes.is_empty()
	)
	var zone_set: Dictionary = {}
	if preview_active:
		for zc in zone_hexes:
			zone_set[zc] = true
	for actor in registry.all():
		if not (actor is Actor):
			continue
		var a: Actor = actor
		var hp_bar: Node = a.get_node_or_null("HealthBar")
		if hp_bar == null or not hp_bar.has_method("set_preview_damage"):
			continue
		# 051b: dispatch enemies AND player. Enemy preview is the existing
		# AoE behaviour (preview > 0 if in zone, else 0). Player preview
		# fires only when player would actually be hit by their own spell
		# (hex-target AoE landing on player.coord). Self-warning flag
		# triggers the big red "!" glyph in HealthBar — visually distinct
		# so the player can't miss the misclick before committing.
		var dmg: int = 0
		var self_warning: bool = false
		if preview_active:
			var coord_a: Vector2i = grid.get_coord(a.actor_id)
			if zone_set.has(coord_a):
				if a.team == &"enemy":
					dmg = active_skill.predicted_damage_to(player, a, ctx)
				elif a == player:
					# Self-hit only meaningful when the spell deals damage
					# AND friendly-fire is structurally possible. Caster
					# exclusion (Self+Zone) drops victims pre-cast → preview
					# without warning would lie. Conservative gate: damage
					# > 0 AND ability.target is NOT a SelfTarget (those
					# exclude caster from zone in Ability.resolve, see ability.gd).
					var dmg_self: int = active_skill.predicted_damage_to(player, player, ctx)
					if dmg_self > 0 and preview_ability != null and not (preview_ability.target is SelfTarget):
						dmg = dmg_self
						self_warning = true
		hp_bar.set_preview_damage(dmg, self_warning)

	# 029 / bonus-2: hover-path preview. Show the route the player would take
	# IFF the cursor is over a reachable hex (within effective_speed) AND
	# isn't blocked. Skipped during cast FSM and stun — neither is "I'm
	# considering moving here" mode. Path is recomputed via find_path_around
	# with live actor blocks so it bends around enemies — same set the move
	# zone was computed against, so reachability and path agree.
	refresh_hover_path(coord)


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


# 049 / AC-2 / T018 + 049b / T037: hex-tooltip dispatch. Builds the row list
# (player preview when active slot's ability would land here, plus every
# enemy whose intent's primary or AoE area covers `coord`) and pushes to the
# HexTooltip widget.
#
# 049b note on guarding: we deliberately rebuild every frame rather than
# state-guarding on `coord`. Slot toggle-off (player presses Q again to
# deselect) doesn't change the hovered coord but DOES change the rows
# (player preview row should disappear), and the per-frame cost is trivial
# (≤10 actors × O(1) checks). Same applies to enemy intent changes mid-frame.
func refresh_hex_tooltip(coord: Vector2i) -> void:
	var tip: Node = get_node_or_null("../../HUD/HexTooltip")
	if tip == null:
		return
	# Off-grid → instant hide.
	if coord == Vector2i(-1, -1):
		if tip.has_method("hide_tooltip"):
			tip.hide_tooltip()
		return
	var rows: Array = _build_hex_tooltip_rows(coord)
	if rows.is_empty():
		if tip.has_method("hide_tooltip"):
			tip.hide_tooltip()
		return
	if tip.has_method("show_for"):
		tip.show_for(rows, _ctrl.get_viewport().get_mouse_position())


# 049 / AC-2 / T018: produce {actor_name, skill, consequence} rows for one
# hex coord. Sources:
#   - Player preview (if active slot can_apply on this coord — ability[0]
#     just like idle slot preview in MoveRangeOverlay).
#   - Every AI-controlled actor whose cast_intent covers `coord`, either
#     as its primary target_coord OR via its ability area.
func _build_hex_tooltip_rows(coord: Vector2i) -> Array:
	var rows: Array = []
	var grid: HexGrid = _ctrl.grid
	var registry: ActorRegistry = _ctrl.registry
	var player: Actor = _ctrl.player
	if grid == null or registry == null:
		return rows

	# Player preview — only when a slot is active. abilities[0] mirrors
	# CastFsm.current_preview_ability when idle (refresh_overlay path).
	var slot_bar: Node = _ctrl.slot_bar
	var active_idx: int = slot_bar.get_active() if slot_bar != null else -1
	if active_idx != -1 and player != null:
		var pskill: Skill = slot_bar.get_slot(active_idx) as Skill
		if pskill != null and not pskill.abilities.is_empty():
			var pab: Ability = pskill.abilities[0]
			if _coord_in_ability_effect(player, pskill, pab, coord):
				rows.append({
					"actor_name": String(player.actor_id),
					"skill": pskill,
					"consequence": SkillFormatter.format_consequence(pskill),
				})

	# Enemy intents.
	for actor_v in registry.all():
		if not (actor_v is Actor):
			continue
		var enemy: Actor = actor_v
		if enemy == player or not enemy.is_alive() or enemy.cast_intent == null:
			continue
		var ci: CastIntent = enemy.cast_intent as CastIntent
		if ci == null or not ci.is_valid():
			continue
		var eskill: Skill = SkillDatabase.get_skill(ci.skill_id)
		if eskill == null:
			continue
		if not _intent_covers_coord(enemy, ci, eskill, coord):
			continue
		rows.append({
			"actor_name": String(enemy.actor_id),
			"skill": eskill,
			"consequence": SkillFormatter.format_consequence(eskill),
		})
	return rows


# 049 / AC-2 + 049b / T036: would the player's active ability ACTUALLY land
# on `coord` if cast right now? We need three things, all true:
#   1. coord ∈ ability.target.get_range_hexes (= reachable at all).
#   2. ability.target.resolve(caster, ctx) != null for the *cursor* coord
#      (= the cast would commit, not just visually be in range — e.g. the
#      hex has a valid actor of the right team, not blocked, not out-of-LOS).
#      This is the same check CastRangeOverlay uses for AC-6 grey-out.
#   3. coord ∈ ability.area.affected (when area exists; otherwise step 2 is
#      sufficient — coord is the anchor and we already know it's valid).
#
# Without step 2 the tooltip used to surface a player-preview row over
# blocked / off-team hexes inside the ability's range circle (e.g. ranged
# damage on an empty grass tile). 049b T036 adds the resolve gate.
func _coord_in_ability_effect(caster: Actor, skill: Skill, ability: Ability, coord: Vector2i) -> bool:
	if ability == null or ability.target == null:
		return false
	var grid: HexGrid = _ctrl.grid
	var registry: ActorRegistry = _ctrl.registry
	var caster_coord: Vector2i = grid.get_coord(caster.actor_id)
	if caster_coord == Vector2i(-1, -1):
		return false
	# Step 1: range gate. Cursor must be on a hex the ability can reach.
	var passive_mods: Dictionary = skill.passive_mods_for(caster) if skill != null else {}
	var level: int = skill.level if skill != null else 0
	var range_hexes: Array[Vector2i] = ability.effective_range_hexes(caster, grid, level, passive_mods)
	if not (coord in range_hexes):
		return false
	# Step 2: validity gate. Mirror CastRangeOverlay's per-hex resolve check
	# (049 AC-6) — same ctx shape (registry / grid / target_id / target_coord).
	# actors_node + resolver are only needed at apply-time (CreateEffect),
	# which we never run here — resolve() is pure inspection.
	var ctx: Dictionary = {
		"registry":     registry,
		"grid":         grid,
		"target_id":    grid.get_actor_at(coord),
		"target_coord": coord,
	}
	if not ability.can_apply(caster, ctx, level, passive_mods):
		return false
	# Step 3: area expansion. Single-target / null-area abilities terminate
	# at step 2 — coord is the anchor and it's valid.
	if ability.area == null:
		return true
	var anchor: Vector2i = ability.target.preview_anchor_coord(caster_coord, coord)
	var affected: Array[Vector2i] = ability.area.get_affected_hexes(caster_coord, anchor, grid)
	return coord in affected


# True if the enemy's planned cast covers `coord` — primary target_coord OR
# any of the ability's area-affected hexes.
func _intent_covers_coord(enemy: Actor, ci: CastIntent, skill: Skill, coord: Vector2i) -> bool:
	var grid: HexGrid = _ctrl.grid
	# Live target coord — same logic TelegraphRenderer.refresh uses (target
	# may have moved since intent was set).
	var primary: Vector2i = ci.target_coord
	if ci.target_id != &"":
		var live: Vector2i = grid.get_coord(ci.target_id)
		if live != Vector2i(-1, -1):
			primary = live
	if coord == primary:
		return true
	var caster_coord: Vector2i = grid.get_coord(enemy.actor_id)
	if caster_coord == Vector2i(-1, -1):
		return false
	for ab in skill.abilities:
		var ability := ab as Ability
		if ability == null or ability.area == null:
			continue
		var anchor: Vector2i = primary
		if ability.target != null:
			anchor = ability.target.preview_anchor_coord(caster_coord, primary)
		var affected: Array[Vector2i] = ability.area.get_affected_hexes(caster_coord, anchor, grid)
		if coord in affected:
			return true
	return false


# 049 / AC-4 / T019: enemy-details panel binding. Cursor over a live enemy
# → bind. Anywhere else → unbind. State-guarded so re-hovering the same
# actor doesn't trip rebinds (which would disconnect/reconnect signals).
func refresh_enemy_details(target_id: StringName) -> void:
	var registry: ActorRegistry = _ctrl.registry
	var panel: Node = get_node_or_null("../../HUD/EnemyDetailsPanel")
	if panel == null:
		return
	var new_id: StringName = &""
	if target_id != &"" and registry != null:
		var hov: Actor = registry.get_actor(target_id)
		if hov != null and hov.team == &"enemy" and hov.is_alive():
			new_id = target_id
	if new_id == _last_enemy_details_id:
		return
	_last_enemy_details_id = new_id
	if new_id == &"":
		if panel.has_method("unbind"):
			panel.unbind()
		return
	if panel.has_method("bind"):
		panel.bind(registry.get_actor(new_id))
