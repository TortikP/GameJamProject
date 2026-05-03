extends Node
## GodmodeInput — owns _unhandled_input switchboard + small player action helpers
## (_request_move, _wait_turn, _request_cast_active). Dispatches LMB to CastFsm
## or to controller's selection facade.


const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const PLAYER_ID: StringName = &"player"

var _ctrl: Node = null


func _ready() -> void:
	_ctrl = get_parent()


func _unhandled_input(event: InputEvent) -> void:
	var slot_bar: Node = _ctrl.slot_bar
	var grid: HexGrid = _ctrl.grid
	var player: Actor = _ctrl.player
	var cast_fsm: Node = _ctrl.cast_fsm
	var campaign_mode: bool = ActiveGame.has_active_game()
	# 045-intro-cutscene: lock all gameplay input on intro levels except ESC
	# (pause menu remains the player's escape hatch). Cutscene/dialogue/move
	# is fully scripted by IntroDirector.
	if campaign_mode and ActiveGame.current_is_intro():
		var is_esc: bool = event is InputEventKey \
			and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE
		if is_esc:
			return  # let pause-menu handler pick it up
		get_viewport().set_input_as_handled()
		return
	if campaign_mode and player != null and not player.is_alive():
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			# 026: priority 0 — cancel multi-step cast in progress.
			# Slot-toggle path below is now unreachable while cast-FSM owns input.
			if cast_fsm.is_in_progress():
				cast_fsm.cancel()
				get_viewport().set_input_as_handled()
				return
			# 009-T051 priority chain (post-026):
			#   1. active cast slot → toggle off
			#   2. selection != player → reset selection to player
			#   3. otherwise → open pause menu
			if slot_bar != null and slot_bar.get_active() != -1:
				slot_bar.activate(slot_bar.get_active())  # toggle off
				get_viewport().set_input_as_handled()
				return
			if _ctrl._selected != null and _ctrl._selected != player:
				_ctrl.deselect_to_player()
				get_viewport().set_input_as_handled()
				return
			# No selection to clear, no active cast — open pause menu if mounted.
			var pause_menu: Node = get_node_or_null("../../HUD/PauseMenu")
			if pause_menu != null and pause_menu.has_method("open"):
				pause_menu.open()
				get_viewport().set_input_as_handled()
				return
			# Last-resort fallback: original behavior (no-op deselect).
			_ctrl.deselect_to_player()
			get_viewport().set_input_as_handled()
			return
	if not campaign_mode and event.is_action_pressed("godmode_spawn_dummy"):
		_ctrl.manekin_spawner.spawn()
		get_viewport().set_input_as_handled()
		return
	if not campaign_mode and event.is_action_pressed("godmode_clear"):
		_ctrl.manekin_spawner.clear_all()
		get_viewport().set_input_as_handled()
		return
	if not campaign_mode and event.is_action_pressed("dev_open_editor"):
		# 020 — global hotkey: jump straight to the map editor from any battle.
		# If this run originated from the editor's Playtest (ActiveLevel marks
		# the path), queue it back so the editor reopens with the same map
		# instead of a fresh canvas.
		if ActiveLevel.can_return_to_editor():
			ActiveLevel.queue(ActiveLevel.get_playtest_origin())
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file("res://scenes/dev/map_editor.tscn")
		return
	if event.is_action_pressed("wait_turn"):
		_wait_turn()
		get_viewport().set_input_as_handled()
		return
	for i in 4:
		if event.is_action_pressed("cast_slot_%d" % i):
			# 027: stunned player can't enter cast FSM. _update_castability
			# already greys the slot visually; this guards the keyboard path.
			if player != null and player.is_stunned() and not cast_fsm.is_in_progress():
				get_viewport().set_input_as_handled()
				return
			# 026: when an FSM cast is in progress, slot keys gate through it.
			if cast_fsm.is_in_progress() and slot_bar != null:
				var active_now: int = slot_bar.get_active()
				if i == active_now:
					# Same slot pressed again — alternate keyboard path.
					# On a self-step, this commits; otherwise it cancels (toggle off).
					if cast_fsm.is_self_step():
						var caster_coord: Vector2i = grid.get_coord(player.actor_id)
						cast_fsm.commit_step(caster_coord, player.actor_id)
					else:
						cast_fsm.cancel()
						slot_bar.activate(i)  # toggle off
				else:
					# Different slot — drop current cast, switch slot. New entry happens
					# only on the next LMB (matches 021 — slot key just selects, doesn't fire).
					cast_fsm.cancel()
					slot_bar.activate(i)
				get_viewport().set_input_as_handled()
				return
			# Default: activate() in SlotBar toggles selection.
			if slot_bar != null:
				slot_bar.activate(i)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			# 026: RMB cancels an in-progress cast instead of moving.
			if cast_fsm.is_in_progress():
				cast_fsm.cancel()
				get_viewport().set_input_as_handled()
				return
			_request_move()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			# 026: LMB during cast FSM — commit step or no-op (out-of-range click).
			if cast_fsm.is_in_progress():
				cast_fsm.handle_lmb()
				get_viewport().set_input_as_handled()
				return
			_request_cast_active()
			get_viewport().set_input_as_handled()


# ── Actions ──────────────────────────────────────────────────────────────────

func _wait_turn() -> void:
	var grid: HexGrid = _ctrl.grid
	if grid._moving or _ctrl.ai.is_world_processing() or _ctrl._is_wave_transitioning():
		return
	GameLogger.info("Godmode", "player skipped turn")
	TurnManager.advance()


func _request_move() -> void:
	var grid: HexGrid = _ctrl.grid
	var player: Actor = _ctrl.player
	if grid._moving or _ctrl.ai.is_world_processing() or _ctrl._is_wave_transitioning():
		return
	if player.is_stunned():
		# 027: pill icon over player explains why; no log spam.
		return
	var coord := grid.coord_under_mouse()
	if coord == Vector2i(-1, -1):
		return
	if not grid.is_walkable(coord):
		GameLogger.info("Godmode", "unreachable: %s" % str(coord))
		return
	var from: Vector2i = grid.get_coord(PLAYER_ID)
	if coord == from:
		return
	if grid.get_actor_at(coord) != &"":
		GameLogger.info("Godmode", "occupied: %s" % str(coord))
		return
	if player.effective_speed() <= 0:
		# 027: rooted or speed=0. Pill icon explains.
		GameLogger.info("Godmode", "cannot move (effective_speed=0)")
		return
	var path: Array = grid.find_path(from, coord)
	var dist: int = path.size() - 1
	if dist > player.effective_speed():
		GameLogger.info("Godmode", "too far (effective_speed=%d, distance=%d)" % [player.effective_speed(), dist])
		return
	await grid.move_actor(PLAYER_ID, coord)
	if grid.get_coord(PLAYER_ID) != from:
		TurnManager.advance()
		_ctrl.refresh_overlay()


func _request_cast_active() -> void:
	var slot_bar: Node = _ctrl.slot_bar
	var grid: HexGrid = _ctrl.grid
	var registry: ActorRegistry = _ctrl.registry
	var player: Actor = _ctrl.player
	var cast_fsm: Node = _ctrl.cast_fsm
	if slot_bar == null:
		return
	if player != null and player.is_stunned():
		# 027: cast slots are greyed via _update_castability; this guards the
		# direct LMB-to-cast path when an active slot is already selected.
		return
	var coord := grid.coord_under_mouse()
	if coord == Vector2i(-1, -1):
		return
	var target_id: StringName = grid.get_actor_at(coord)
	var ctx: Dictionary = {
		"registry": registry, "grid": grid,
		"target_id": target_id, "target_coord": coord,
		# 041: required by CreateEffect for actor- and object-spawn paths.
		"actors_node": grid.get_node_or_null("Actors"),
		"resolver": _ctrl.tile_object_resolver,
	}
	var active_idx: int = slot_bar.get_active()
	# If a spell is selected and can cast → start the FSM
	if active_idx != -1:
		var skill := slot_bar.get_slot(active_idx) as Skill
		if skill != null and skill.can_apply(player, ctx):
			cast_fsm.start(active_idx)
			# 026 fix: the entry LMB also acts as the commit click for step 0.
			# Without this, the player would have to click twice (once to enter
			# FSM, once to commit). handle_lmb is safe to call when FSM
			# isn't active (early-returns).
			if cast_fsm.is_in_progress():
				cast_fsm.handle_lmb()
		# Skill slot active → never inspect/deselect on a failed cast.
		return
	# No active skill: inspect hovered actor or hex
	var target_actor: Actor = registry.get_actor(target_id) if target_id != &"" else null
	if target_actor != null:
		_ctrl.select(target_actor)
	elif grid.is_walkable(coord):
		_ctrl.inspect_hex(coord)
