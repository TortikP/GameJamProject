extends Node
## CastFsm — multi-step player cast collection state machine.
##
## See specs/026-skill-system-v3/plan.md §"Player cast state-machine".
##
## State: IDLE → AWAIT_TARGET / AWAIT_SELF_CONFIRM → ... → _commit_cast
## Cancel paths reset to IDLE without firing Skill.cast.


const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

var _ctrl: Node = null

# 026: multi-step cast collection state. Phase-1 (per-ability target picker)
# lives here; phase-2 is Skill.cast(player, ctxs).
var _in_progress: bool = false
var _skill: Skill = null
var _step: int = 0                  # current ability index in skill.abilities
var _ctxs: Array[Dictionary] = []   # collected so far (length == _step)


func _ready() -> void:
	_ctrl = get_parent()


func is_in_progress() -> bool:
	return _in_progress


func is_self_step() -> bool:
	if not _in_progress or _skill == null:
		return false
	if _step >= _skill.abilities.size():
		return false
	return _skill.abilities[_step].target is SelfTarget


# 031 phase 13: which ability should overlays preview "right now"?
# - During FSM cast: abilities[_step] (the step the next click resolves).
# - Idle slot active: abilities[0] (the step the FSM will resolve first).
# - No active slot: null (caller paints nothing).
# Used by both controller.refresh_overlay (target-range paint) and
# hover_dispatcher.update_castability (zone-area paint) so the two stay in
# sync — same source of truth, no chance of one preview showing step N
# while the other shows step 0.
func current_preview_ability() -> Ability:
	if _in_progress and _skill != null and _step < _skill.abilities.size():
		return _skill.abilities[_step]
	var slot_bar: Node = _ctrl.slot_bar
	if slot_bar == null:
		return null
	var active: int = slot_bar.get_active()
	if active == -1:
		return null
	var sk := slot_bar.get_slot(active) as Skill
	if sk == null or sk.abilities.is_empty():
		return null
	return sk.abilities[0]


## Entry point — called when player presses LMB with an active slot.
## Pre-checks `skill.can_apply(player, mouse_ctx)` against abilities[0] (021
## semantics). If false, slot stays greyed and FSM does not start.
func start(slot_index: int) -> void:
	var slot_bar: Node = _ctrl.slot_bar
	var grid: HexGrid = _ctrl.grid
	var registry: ActorRegistry = _ctrl.registry
	var player: Actor = _ctrl.player
	if slot_bar == null:
		return
	var skill := slot_bar.get_slot(slot_index) as Skill
	if skill == null:
		GameLogger.info("Godmode", "slot %d empty" % slot_index)
		return
	if skill.abilities.is_empty():
		GameLogger.warn("Godmode", "slot %d skill '%s' has no abilities" % [slot_index, skill.id])
		return
	if grid._moving or _ctrl.ai.is_world_processing() or _ctrl._is_wave_transitioning():
		return

	# Pre-check using mouse position. Cheap and matches 021 grey-out semantics.
	var coord := grid.coord_under_mouse()
	if coord == Vector2i(-1, -1):
		GameLogger.info("Godmode", "no target (off-grid)")
		return
	var pre_ctx: Dictionary = {
		"registry": registry, "grid": grid,
		"target_id": grid.get_actor_at(coord), "target_coord": coord,
		# 041: required by CreateEffect for actor- and object-spawn paths.
		"actors_node": grid.get_node_or_null("Actors"),
		"resolver": _ctrl.tile_object_resolver,
	}
	if not skill.can_apply(player, pre_ctx):
		return

	_skill = skill
	_step = 0
	_ctxs = []
	_in_progress = true
	# 026 fix: hide MoveRangeOverlay's slot-activation attack-range paint
	# so CastRangeOverlay's per-step paint doesn't render on top of it.
	# Restored on FSM exit via refresh_overlay (in _commit_cast/cancel).
	if _ctrl.overlay != null and _ctrl.overlay.has_method("clear"):
		_ctrl.overlay.clear()
	_begin_step()


## 026: dispatch LMB while cast FSM is active.
##   - self-step: any LMB anywhere commits with caster's coord (per spec AC-C4).
##   - non-self : LMB on a hex within ability.target.range commits; otherwise
##                no-op (overlay stays, player keeps the step).
func handle_lmb() -> void:
	if not _in_progress or _skill == null:
		return
	if _step >= _skill.abilities.size():
		return
	var grid: HexGrid = _ctrl.grid
	var player: Actor = _ctrl.player
	var ab: Ability = _skill.abilities[_step]
	if ab.target is SelfTarget:
		var caster_coord: Vector2i = grid.get_coord(player.actor_id)
		commit_step(caster_coord, player.actor_id)
		return
	var coord: Vector2i = grid.coord_under_mouse()
	if coord == Vector2i(-1, -1):
		return  # off-grid click — stay on step
	var from_coord: Vector2i = grid.get_coord(player.actor_id)
	var valid_hexes: Array[Vector2i] = ab.effective_range_hexes(player, grid,
			_skill.level, _skill.passive_mods_for(player))
	if coord in valid_hexes:
		commit_step(coord, grid.get_actor_at(coord))
	# else: invalid range click — neither commit nor cancel; stay on step


func commit_step(coord: Vector2i, target_id: StringName) -> void:
	var ctx: Dictionary = {
		"registry": _ctrl.registry, "grid": _ctrl.grid,
		"target_id": target_id, "target_coord": coord,
		# 041: required by CreateEffect for actor- and object-spawn paths.
		"actors_node": _ctrl.grid.get_node_or_null("Actors"),
		"resolver": _ctrl.tile_object_resolver,
	}
	_ctxs.append(ctx)
	_step += 1
	if _ctrl.cast_overlay != null and _ctrl.cast_overlay.has_method("hide_range"):
		_ctrl.cast_overlay.hide_range()
	if _step == _skill.abilities.size():
		await _commit_cast()
	else:
		_begin_step()


func cancel() -> void:
	if _ctrl.cast_overlay != null and _ctrl.cast_overlay.has_method("hide_range"):
		_ctrl.cast_overlay.hide_range()
	_reset_state()
	# 026 fix: restore MoveRangeOverlay slot paint after FSM cancels.
	_ctrl.refresh_overlay()
	# no cooldown, no commit, no turn advance


func _begin_step() -> void:
	if _skill == null or _step >= _skill.abilities.size():
		return
	var ab: Ability = _skill.abilities[_step]
	var cast_overlay: Node = _ctrl.cast_overlay
	if cast_overlay == null:
		return
	if ab.target is SelfTarget:
		var caster_coord: Vector2i = _ctrl.grid.get_coord(_ctrl.player.actor_id)
		if cast_overlay.has_method("show_self_confirm"):
			cast_overlay.show_self_confirm(caster_coord)
	else:
		if cast_overlay.has_method("show_range_for_ability"):
			cast_overlay.show_range_for_ability(_ctrl.player, ab, _skill.level,
					_skill.passive_mods_for(_ctrl.player))


func _commit_cast() -> void:
	# Snapshot then reset BEFORE Skill.cast so EventBus subscribers see clean state.
	var skill: Skill = _skill
	var ctxs: Array[Dictionary] = _ctxs
	_reset_state()
	# 047-skill-fx-system: skill.cast is now a coroutine — must await. Pass
	# FxDirector so per-ability anim+sound+collision FX play between resolve
	# and apply. Without the await, did_cast would not be a real bool.
	var did_cast: bool = await skill.cast(_ctrl.player, ctxs, FxDirector)
	# 029 req-2 / 031 phase 11: deselect ability after a successful cast.
	# Forces the player to consciously re-arm before next attack — no
	# held-trigger spam. Using activate(active) (toggle off) emits
	# slot_activated(-1), which also clears the PSP spell description
	# (set_active(-1) alone wouldn't trigger that signal).
	# 031 phase 12: must run BEFORE _ctrl.refresh_overlay() — otherwise
	# refresh reads the still-active slot and re-paints its range, leaving
	# stale overlay paint until the next refresh trigger (end of enemy turn).
	var slot_bar: Node = _ctrl.slot_bar
	if did_cast and slot_bar != null and slot_bar.get_active() != -1:
		slot_bar.activate(slot_bar.get_active())  # toggle off
	# 026 fix: restore MoveRangeOverlay slot paint after FSM exits.
	_ctrl.refresh_overlay()
	if did_cast:
		await GameSpeed.wait("godmode", "ability_cast_delay")
		TurnManager.advance()


func _reset_state() -> void:
	_in_progress = false
	_skill = null
	_step = 0
	_ctxs = []
