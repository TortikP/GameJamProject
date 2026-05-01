extends Node
## GodmodeController — drives the godmode sandbox scene.
##
## Wires together: HexGrid (instance), ActorRegistry (sibling), Player (Actor in
## HexGrid/Actors), SlotBar UI, TurnManager autoload. Owns input handling.
##
## Init order (matches arena_demo_controller convention):
##   1. resolve nodes
##   2. _paint_grid()   ← set_cell BEFORE grid.initialize()
##   3. grid.initialize()
##   4. _place_player()
##   5. _seed_slots()   ← populate slot 0 with debug_punch
##
## Input:
##   RMB                  → grid.move_actor(player, coord) → tick after move
##   LMB                  → cast active slot at coord-under-mouse → tick
##   cast_slot_0..3       → activate slot + cast at coord-under-mouse → tick
##   godmode_spawn_dummy  → spawn manekin (no tick)
##   godmode_clear        → remove all manekins (no tick)

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const MANEKIN_SCENE := preload("res://scenes/dev/manekin.tscn")
const PLAYER_SCENE := preload("res://scenes/dev/player.tscn")
const GODMODE_TERRAIN := preload("res://scenes/dev/godmode_terrain.tres")
const PLAYER_ID: StringName = &"player"
const GRID_W := 14
const GRID_H := 9

@export var grid: HexGrid
@export var registry: ActorRegistry
@export var player: Actor
@export var slot_bar: NodePath  # path to HBoxContainer with slot_bar.gd
@export var inspector_path: NodePath
@export var overlay_path: NodePath

var _slot_bar_node: Node
var _inspector: Node      # ActorInspector
var _overlay: Node        # MoveRangeOverlay
var _selected: Actor      # currently inspected actor (default: player)
var _next_manekin_idx: int = 1
var _world_processing: bool = false  # true while AI takes its turn — locks player input


func _ready() -> void:
	# 1. Resolve
	if grid == null:
		grid = get_node_or_null("../HexGrid") as HexGrid
	if grid == null:
		GameLogger.error("Godmode", "HexGrid not found")
		return

	if grid.tile_map_layer == null:
		grid.tile_map_layer = grid.get_node_or_null("Terrain") as TileMapLayer
	if grid.vfx_overlay == null:
		grid.vfx_overlay = grid.get_node_or_null("VFXOverlay") as TileMapLayer

	if registry == null:
		registry = get_node_or_null("../ActorRegistry") as ActorRegistry
	if registry == null:
		GameLogger.error("Godmode", "ActorRegistry not found")
		return

	if player == null:
		player = grid.get_node_or_null("Actors/Player") as Actor
	if player == null:
		# Not present in scene tree → spawn from prefab
		var actors_node: Node = grid.get_node_or_null("Actors")
		if actors_node == null:
			actors_node = grid
		player = PLAYER_SCENE.instantiate() as Actor
		actors_node.add_child(player)

	if not slot_bar.is_empty():
		_slot_bar_node = get_node_or_null(slot_bar)
	if _slot_bar_node == null:
		_slot_bar_node = get_tree().root.find_child("SlotBar", true, false)
	if _slot_bar_node == null:
		GameLogger.warn("Godmode", "SlotBar not found — abilities won't be visible")

	# 2. Paint, 3. Initialize, 4. Place
	# Godmode uses its own tileset (128×112 hexes, single grass tile) — keeps
	# arena_demo's 64×56 untouched.
	grid.tile_map_layer.tile_set = GODMODE_TERRAIN
	if grid.vfx_overlay != null:
		grid.vfx_overlay.tile_set = GODMODE_TERRAIN
	_paint_grid()
	grid.actor_step_started.connect(_on_step_started)
	grid.initialize()
	_place_player()

	# 5. Seed slots — DEFERRED. Sibling order in scene tree means SlotBar._ready
	#    fires AFTER GodmodeController._ready (HUD is a later sibling), so its
	#    buttons array is empty when we get here. call_deferred runs after the
	#    rest of the frame's _ready calls.
	_seed_slots.call_deferred()
	if _slot_bar_node != null and _slot_bar_node.has_signal("slot_activated"):
		_slot_bar_node.slot_activated.connect(_on_slot_activated)

	# Inspector + overlay — resolve
	if not inspector_path.is_empty():
		_inspector = get_node_or_null(inspector_path)
	if _inspector == null:
		_inspector = get_tree().root.find_child("ActorInspector", true, false)
	if not overlay_path.is_empty():
		_overlay = get_node_or_null(overlay_path)
	if _overlay == null:
		_overlay = grid.get_node_or_null("MoveRangeOverlay")
	if _overlay != null and _overlay.has_method("setup"):
		_overlay.setup(grid)
	# CastRangeOverlay (009-T033) — present in godmode.tscn as sibling under HexGrid.
	# Wire its grid ref now; show_range/hide_range calls follow once cast_mode is
	# explicit (007 ownership). For Phase 2 it stays inert.
	var _cast_overlay: Node = grid.get_node_or_null("CastRangeOverlay")
	if _cast_overlay != null and _cast_overlay.has_method("setup"):
		_cast_overlay.setup(grid)
	if _inspector != null and _inspector.has_signal("speed_changed"):
		_inspector.speed_changed.connect(_on_inspector_speed_changed)

	# Reset turn counter for this session
	TurnManager.reset()
	# Force HUD to show initial value — also deferred so TurnLabel has connected.
	_emit_initial_turn.call_deferred()

	# Default selection = player (deferred so player node is fully initialised)
	_select_deferred.call_deferred()

	# AI: enemies act each world turn
	EventBus.world_turn_ended.connect(_on_world_turn_ended)
	EventBus.actor_died.connect(_on_actor_died_for_selection)

	GameLogger.info("Godmode", "ready. RMB=move, LMB/QWER/1234=select, LMB=cast, F1=spawn, F2=clear")
	# 009-T038: bind PlayerStatusPanel if it's mounted in HUD. Uses get_node_or_null
	# so godmode keeps booting if the HUD layout drops the panel.
	var psp: Node = get_node_or_null("../HUD/PlayerStatusPanel")
	if psp != null and psp.has_method("bind_player"):
		psp.bind_player(player)


# ── Setup ────────────────────────────────────────────────────────────────────

func _paint_grid() -> void:
	# All grass, no walls. Godmode sandbox = clean slate.
	for row in GRID_H:
		for col in GRID_W:
			grid.tile_map_layer.set_cell(Vector2i(col, row), 0, Vector2i(0, 0))


func _place_player() -> void:
	var start := Vector2i(GRID_W / 2, GRID_H / 2)
	grid.place_actor(PLAYER_ID, start)
	player.actor_id = PLAYER_ID
	player.team = &"player"
	player.position = grid.tile_map_layer.map_to_local(start)
	registry.register(player)
	GameLogger.info("Godmode", "Player at %s" % str(start))


func _seed_slots() -> void:
	if _slot_bar_node == null:
		return
	var debug_punch: Ability = AbilityDatabase.get_ability(&"debug_punch")
	if debug_punch != null:
		_slot_bar_node.set_slot(0, debug_punch)
	else:
		GameLogger.warn("Godmode", "debug_punch not found in AbilityDatabase")
	var melee_punch: Ability = AbilityDatabase.get_ability(&"melee_punch")
	if melee_punch != null:
		_slot_bar_node.set_slot(1, melee_punch)
	var knockback_punch: Ability = AbilityDatabase.get_ability(&"knockback_punch")
	if knockback_punch != null:
		_slot_bar_node.set_slot(2, knockback_punch)
	_slot_bar_node.set_active(0)
	# Sync player abilities for inspector display
	var ids: Array[StringName] = []
	for i in 4:
		var ab: Ability = _slot_bar_node.get_slot(i) as Ability
		if ab != null:
			ids.append(ab.id)
	player.set_abilities(ids)


func _emit_initial_turn() -> void:
	EventBus.world_turn_ended.emit(TurnManager.current())


func _select_deferred() -> void:
	_select(player)


# ── Selection / Inspector / Overlay ──────────────────────────────────────────

func _select(actor: Actor) -> void:
	_selected = actor
	if _inspector != null and _inspector.has_method("bind"):
		_inspector.bind(actor)
	# Also show hex layer for this actor's current position
	if actor != null:
		var coord: Vector2i = grid.get_coord(actor.actor_id)
		_bind_hex_at(coord)
	_refresh_overlay()


func _deselect_to_player() -> void:
	_select(player)


func _inspect_hex(coord: Vector2i) -> void:
	# Click on empty hex → inspector shows hex info, actor section hides.
	# Selection state and player's move/cast overlay are NOT touched
	# (009-ui-kit decoupling: overlay tracks player, not _selected).
	# Note: we deliberately don't change _selected — leaving it on the
	# player so subsequent overlay refreshes have a sensible source if
	# anything ever re-introduces selection-driven logic.
	if _inspector != null and _inspector.has_method("unbind"):
		_inspector.unbind()
	_bind_hex_at(coord)


func _bind_hex_at(coord: Vector2i) -> void:
	if _inspector == null or not _inspector.has_method("bind_hex"):
		return
	if coord == Vector2i(-1, -1):
		_inspector.unbind_hex()
		return
	var tile_kind: StringName = grid.get_tile_kind(coord)
	var effect_id: StringName = grid.get_effect_id(coord)
	_inspector.bind_hex(coord, tile_kind, effect_id)


func _refresh_overlay() -> void:
	# Decoupled from _selected: the move-range and cast-range overlays are
	# always for the PLAYER. Selecting an enemy/hex (LMB on actor, click on
	# tile) should not hide the player's tactical info (Pillar 1 visibility).
	# Inspector binding still follows _selected — that's the "what am I
	# looking at" panel, separate concern from "what can I do this turn".
	if _overlay == null or player == null:
		return
	var ability_ids: Array = []
	if _slot_bar_node != null:
		var active: int = _slot_bar_node.get_active()
		if active != -1:
			var ab := _slot_bar_node.get_slot(active) as Ability
			if ab != null:
				ability_ids = [ab.id]
	_overlay.show_for(player, registry, ability_ids)


func _on_inspector_speed_changed(_actor: Actor) -> void:
	_refresh_overlay()


func _on_actor_died_for_selection(id: StringName) -> void:
	if _selected != null and _selected.actor_id == id:
		_deselect_to_player()


# ── Input ────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	_update_castability()


func _update_castability() -> void:
	if _slot_bar_node == null or grid == null or registry == null or player == null:
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
	# Slot castability tints
	for i in 4:
		var ability := _slot_bar_node.get_slot(i) as Ability
		var castable: bool = ability != null and ability.can_apply(player, ctx)
		_slot_bar_node.set_castable(i, castable)

	# Damage preview on enemies — only the hovered one shows red strip,
	# others get cleared. Active slot's ability is the source.
	var active_idx: int = _slot_bar_node.get_active()
	var active_ability := _slot_bar_node.get_slot(active_idx) as Ability
	var hover_target: Actor = registry.get_actor(target_id) if target_id != &"" else null
	var preview_for_hover: int = 0
	if active_ability != null and hover_target != null and hover_target.team == &"enemy":
		if active_ability.can_apply(player, ctx):
			preview_for_hover = active_ability.predicted_damage_to(player, hover_target, ctx)
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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			# 009-T051 priority chain:
			#   1. active cast slot → cancel cast (deactivate slot)
			#   2. selection != player → reset selection to player
			#   3. otherwise → open pause menu
			# Modal close (priority 2 in plan) is decentralized — each modal
			# self-closes on ESC via its own _unhandled_input. They also call
			# set_input_as_handled, so by the time this fires the modal stack
			# is empty.
			if _slot_bar_node != null and _slot_bar_node.get_active() != -1:
				_slot_bar_node.activate(_slot_bar_node.get_active())  # toggle off
				get_viewport().set_input_as_handled()
				return
			if _selected != null and _selected != player:
				_deselect_to_player()
				get_viewport().set_input_as_handled()
				return
			# No selection to clear, no active cast — open pause menu if mounted.
			var pause_menu: Node = get_node_or_null("../HUD/PauseMenu")
			if pause_menu != null and pause_menu.has_method("open"):
				pause_menu.open()
				get_viewport().set_input_as_handled()
				return
			# Last-resort fallback: original behavior (no-op deselect).
			_deselect_to_player()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("godmode_spawn_dummy"):
		_spawn_manekin()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("godmode_clear"):
		_clear_manekins()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("wait_turn"):
		_wait_turn()
		get_viewport().set_input_as_handled()
		return
	for i in 4:
		if event.is_action_pressed("cast_slot_%d" % i):
			# activate() in SlotBar toggles: press active slot again = deselect (-1)
			if _slot_bar_node != null:
				_slot_bar_node.activate(i)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_request_move()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_request_cast_active()
			get_viewport().set_input_as_handled()


# ── Actions ──────────────────────────────────────────────────────────────────

func _wait_turn() -> void:
	if grid._moving or _world_processing:
		return
	GameLogger.info("Godmode", "player skipped turn")
	TurnManager.advance()


func _request_move() -> void:
	if grid._moving or _world_processing:
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
	if player.speed <= 0:
		GameLogger.info("Godmode", "cannot move (speed=0)")
		return
	var path: Array = grid.find_path(from, coord)
	var dist: int = path.size() - 1
	if dist > player.speed:
		GameLogger.info("Godmode", "too far (speed=%d, distance=%d)" % [player.speed, dist])
		return
	await grid.move_actor(PLAYER_ID, coord)
	if grid.get_coord(PLAYER_ID) != from:
		TurnManager.advance()
		_refresh_overlay()


func _request_cast_active() -> void:
	if _slot_bar_node == null:
		return
	var coord := grid.coord_under_mouse()
	if coord == Vector2i(-1, -1):
		return
	var target_id: StringName = grid.get_actor_at(coord)
	var ctx: Dictionary = {
		"registry": registry, "grid": grid,
		"target_id": target_id, "target_coord": coord,
	}
	var active_idx: int = _slot_bar_node.get_active()
	# If a spell is selected and can cast → cast
	if active_idx != -1:
		var ability := _slot_bar_node.get_slot(active_idx) as Ability
		if ability != null and ability.can_apply(player, ctx):
			_cast_slot(active_idx)
			return
	# No cast: inspect hovered actor or hex
	var target_actor: Actor = registry.get_actor(target_id) if target_id != &"" else null
	if target_actor != null:
		_select(target_actor)
	elif grid.is_walkable(coord):
		_inspect_hex(coord)
	# Off-grid or impassable with no actor → no-op


func _cast_slot(slot_index: int) -> void:
	if _slot_bar_node == null:
		return
	var ability := _slot_bar_node.get_slot(slot_index) as Ability
	if ability == null:
		GameLogger.info("Godmode", "slot %d empty" % slot_index)
		return
	if grid._moving or _world_processing:
		return
	var coord := grid.coord_under_mouse()
	if coord == Vector2i(-1, -1):
		GameLogger.info("Godmode", "no target (off-grid)")
		return
	var target_id: StringName = grid.get_actor_at(coord)
	var ctx: Dictionary = {
		"registry": registry,
		"grid": grid,
		"target_id": target_id,
		"target_coord": coord,
	}
	var did_cast: bool = ability.cast(player, ctx)
	if not did_cast:
		return
	await GameSpeed.wait("godmode", "ability_cast_delay")
	TurnManager.advance()


func _on_slot_activated(_index: int) -> void:
	_refresh_overlay()
	# 009-T044+: push active spell into PlayerStatusPanel description block.
	# -1 = deselect → pass null which collapses the spell section.
	var psp: Node = get_node_or_null("../HUD/PlayerStatusPanel")
	if psp != null and psp.has_method("set_active_spell"):
		var ability = null
		if _index != -1 and _slot_bar_node != null:
			ability = _slot_bar_node.get_slot(_index)
		psp.set_active_spell(ability)


# ── Spawning ─────────────────────────────────────────────────────────────────

func _spawn_manekin() -> void:
	var coord := grid.coord_under_mouse()
	if coord == Vector2i(-1, -1) or not grid.is_walkable(coord):
		GameLogger.info("Godmode", "cannot spawn at %s" % str(coord))
		return
	if grid.get_actor_at(coord) != &"":
		GameLogger.info("Godmode", "occupied at %s" % str(coord))
		return
	var idx := _next_manekin_idx
	_next_manekin_idx += 1
	var id := StringName("dummy_%03d" % idx)
	var manekin: Actor = MANEKIN_SCENE.instantiate()
	manekin.actor_id = id
	manekin.position = grid.tile_map_layer.map_to_local(coord)
	var actors_node: Node = grid.get_node_or_null("Actors")
	if actors_node == null:
		actors_node = grid
	actors_node.add_child(manekin)
	grid.place_actor(id, coord)
	registry.register(manekin)
	manekin.died.connect(_on_actor_died)
	GameLogger.info("Godmode", "spawned %s at %s" % [id, str(coord)])
	# Plan immediately so the player sees the new manekin's intent right away,
	# without having to end their turn first. Re-plans ALL enemies because
	# adding a new one can block existing pathing.
	_replan_all_and_refresh()
	_refresh_overlay()


func _replan_all_and_refresh() -> void:
	var enemies: Array = []
	for actor in registry.all():
		if actor is Actor and (actor as Actor).team == &"enemy":
			enemies.append(actor)
	for actor in enemies:
		if actor is Actor and (actor as Actor).is_alive():
			_plan_intents(actor as Actor, enemies)
	_refresh_telegraphs()


func _clear_manekins() -> void:
	var to_remove: Array = []
	for actor in registry.all():
		if actor is Actor and (actor as Actor).team == &"enemy":
			to_remove.append(actor)
	for actor in to_remove:
		var a: Actor = actor
		grid.clear_actor(a.actor_id)
		registry.unregister(a.actor_id)
		a.queue_free()
	_clear_all_telegraphs()
	# F2 doubles as a sandbox reset: revive player and refill HP. Lets the
	# tester keep playing after death without restarting the scene.
	if player != null:
		player.heal_to_full()
	_deselect_to_player()
	GameLogger.info("Godmode", "cleared %d manekins, player reset" % to_remove.size())


func _on_actor_died(id: StringName) -> void:
	var actor: Actor = registry.get_actor(id)
	if actor == null:
		return
	grid.clear_actor(id)
	registry.unregister(id)
	actor.queue_free()
	# An enemy died → its intent is gone, refresh visuals to drop its label
	_refresh_telegraphs()


# ── Movement animation (mirror of arena_demo_controller) ─────────────────────

func _on_step_started(actor_id: StringName, _from: Vector2i, to: Vector2i) -> void:
	var actor: Actor = registry.get_actor(actor_id)
	if actor == null:
		return
	var pos: Vector2 = grid.tile_map_layer.map_to_local(to)
	var duration: float = GameSpeed.get_value("arena", "step_duration", 0.18) * grid.get_move_cost(to)
	create_tween().tween_property(actor, "position", pos, duration)


# ── AI ───────────────────────────────────────────────────────────────────────
#
# Two-stage per enemy on world_turn_ended:
#   1. RESOLVE last turn's attack intent (if any). If player still on the
#      intent hex, attack lands; else attack misses (wasted turn). Clear
#      telegraph visual either way.
#   2. PLAN this turn:
#      a. If adjacent to player → don't move (preserve attacking position).
#      b. Else → step one hex toward player.
#   3. SET intent for next turn: if adjacent (now or after the step) AND
#      has attack_ability, intent = player's current coord. Show telegraph.
#
# Sequential per enemy. _world_processing locks player input during the loop.

const TELEGRAPH_HEX_SCRIPT := preload("res://scripts/presentation/telegraph_hex.gd")
const INTENT_ARROW_SCRIPT := preload("res://scripts/presentation/intent_arrow.gd")

var _telegraph_hexes: Dictionary = {}  # Vector2i coord -> TelegraphHex node
var _intent_arrows: Dictionary = {}    # StringName actor_id -> IntentArrow node


func _on_world_turn_ended(_turn: int) -> void:
	if _world_processing:
		return
	if player == null or not player.is_alive():
		return
	_world_processing = true
	await _run_enemy_turn()
	_world_processing = false
	_refresh_overlay()


func _run_enemy_turn() -> void:
	var enemies: Array = []
	for actor in registry.all():
		if actor is Actor and (actor as Actor).team == &"enemy":
			enemies.append(actor)
	_clear_all_telegraphs()

	# Phase 1: RESOLVE — execute everyone's planned move, then planned attack.
	# Movement first so attacks happen from the post-move position.
	for actor in enemies:
		if not (actor is Actor):
			continue
		var enemy: Actor = actor
		if not enemy.is_alive() or registry.get_actor(enemy.actor_id) == null:
			continue
		await _resolve_move_intent(enemy)
		if not enemy.is_alive():
			continue
		await _resolve_attack_intent(enemy)

	# Phase 2: PLAN — pick next move (route around other actors) and next
	# attack (if would be adjacent after move). Sets data only; visuals
	# rebuilt at the end of this loop.
	for actor in enemies:
		if not (actor is Actor):
			continue
		var enemy: Actor = actor
		if not enemy.is_alive() or registry.get_actor(enemy.actor_id) == null:
			continue
		_plan_intents(enemy, enemies)

	_refresh_telegraphs()


# ── Resolve helpers ──────────────────────────────────────────────────────────

func _resolve_move_intent(enemy: Actor) -> void:
	var intent_var: Variant = enemy.get("move_intent_coord")
	if not (intent_var is Vector2i):
		return
	var intent: Vector2i = intent_var
	enemy.set("move_intent_coord", Vector2i(-1, -1))
	if intent == Vector2i(-1, -1):
		return
	var enemy_coord: Vector2i = grid.get_coord(enemy.actor_id)
	if enemy_coord == intent:
		return  # already there (somehow)
	# Check destination is still walkable + unoccupied at execute-time
	# (another enemy may have ended up there during this Phase 1)
	if grid.get_actor_at(intent) != &"":
		GameLogger.info("AI", "%s: move blocked at %s" % [enemy.actor_id, intent])
		return
	# move_actor handles validation; await ensures sequential animation
	await grid.move_actor(enemy.actor_id, intent)


func _resolve_attack_intent(enemy: Actor) -> void:
	var intent_var: Variant = enemy.get("attack_intent_coord")
	if not (intent_var is Vector2i):
		return
	var intent: Vector2i = intent_var
	enemy.set("attack_intent_coord", Vector2i(-1, -1))
	if intent == Vector2i(-1, -1):
		return
	var player_coord: Vector2i = grid.get_coord(PLAYER_ID)
	if player_coord != intent:
		GameLogger.info("AI", "%s: attack missed (player moved)" % enemy.actor_id)
		return
	var ability_id_var: Variant = enemy.get("attack_ability_id")
	if not (ability_id_var is StringName) or ability_id_var == &"":
		return
	var ability: Ability = AbilityDatabase.get_ability(ability_id_var)
	if ability == null:
		return
	var ctx: Dictionary = {
		"registry": registry, "grid": grid,
		"target_id": PLAYER_ID, "target_coord": player_coord,
	}
	# can_apply re-validates adjacency at the moment of cast — knockback /
	# disruption still neutralizes the attack correctly.
	ability.cast(enemy, ctx)
	await GameSpeed.wait("godmode", "ability_cast_delay")


# ── Plan helpers ─────────────────────────────────────────────────────────────

func _plan_intents(enemy: Actor, all_enemies: Array) -> void:
	var enemy_coord: Vector2i = grid.get_coord(enemy.actor_id)
	var player_coord: Vector2i = grid.get_coord(PLAYER_ID)
	if enemy_coord == Vector2i(-1, -1) or player_coord == Vector2i(-1, -1):
		return

	# Build set of coords blocked by OTHER enemies (player tile is the goal,
	# never blocked).
	var blocked: Array = []
	for other in all_enemies:
		if not (other is Actor):
			continue
		var o: Actor = other
		if o == enemy or not o.is_alive():
			continue
		var c: Vector2i = grid.get_coord(o.actor_id)
		if c != Vector2i(-1, -1):
			blocked.append(c)

	var path: Array = grid.find_path_around(enemy_coord, player_coord, blocked)

	# Default: do nothing (used when no path or already adjacent without
	# a usable attack ability).
	enemy.set("move_intent_coord", Vector2i(-1, -1))
	enemy.set("attack_intent_coord", Vector2i(-1, -1))

	if path.size() == 2:
		# Already adjacent → attack this turn, no movement.
		# (Pillar 2: symmetric with player — one action per turn.)
		var ability_id_var: Variant = enemy.get("attack_ability_id")
		if ability_id_var is StringName and ability_id_var != &"":
			var ability: Ability = AbilityDatabase.get_ability(ability_id_var)
			if ability != null:
				enemy.set("attack_intent_coord", player_coord)
	elif path.size() > 2:
		# Not yet adjacent → step one hex closer this turn, no attack.
		# Attack will happen on the NEXT plan after we arrive in adjacency.
		enemy.set("move_intent_coord", path[1])
	# else (path empty): no path through actors — stand still.


# ── Telegraph visuals ────────────────────────────────────────────────────────

func _refresh_telegraphs() -> void:
	# Clear all current visuals.
	for poly in _telegraph_hexes.values():
		if is_instance_valid(poly):
			poly.queue_free()
	_telegraph_hexes.clear()
	for arr in _intent_arrows.values():
		if is_instance_valid(arr):
			arr.queue_free()
	_intent_arrows.clear()

	# Aggregate damage per coord across all enemies' intents.
	var damage_per_coord: Dictionary = {}
	for actor in registry.all():
		if not (actor is Actor):
			continue
		var enemy: Actor = actor
		if enemy.team != &"enemy" or not enemy.is_alive():
			continue
		# Attack telegraph aggregation
		var atk_var: Variant = enemy.get("attack_intent_coord")
		if atk_var is Vector2i and atk_var != Vector2i(-1, -1):
			var dmg: int = _enemy_attack_damage(enemy)
			damage_per_coord[atk_var] = damage_per_coord.get(atk_var, 0) + dmg
		# Movement arrow — one per enemy with a planned move
		var mv_var: Variant = enemy.get("move_intent_coord")
		if mv_var is Vector2i and mv_var != Vector2i(-1, -1):
			var enemy_coord: Vector2i = grid.get_coord(enemy.actor_id)
			if enemy_coord != Vector2i(-1, -1):
				var arrow: Node2D = INTENT_ARROW_SCRIPT.new()
				arrow.position = Vector2.ZERO
				arrow.z_index = 4  # above telegraph hex, below actors
				grid.add_child(arrow)
				arrow.set("origin", grid.tile_map_layer.map_to_local(enemy_coord))
				arrow.set("target", grid.tile_map_layer.map_to_local(mv_var))
				_intent_arrows[enemy.actor_id] = arrow

	# Render one telegraph hex per unique threatened coord.
	for coord in damage_per_coord.keys():
		var hex: Node2D = TELEGRAPH_HEX_SCRIPT.new()
		hex.position = grid.tile_map_layer.map_to_local(coord)
		hex.z_index = 3
		hex.set("damage", damage_per_coord[coord])
		grid.add_child(hex)
		_telegraph_hexes[coord] = hex


func _clear_all_telegraphs() -> void:
	for poly in _telegraph_hexes.values():
		if is_instance_valid(poly):
			poly.queue_free()
	_telegraph_hexes.clear()
	for arr in _intent_arrows.values():
		if is_instance_valid(arr):
			arr.queue_free()
	_intent_arrows.clear()


## Best-effort damage forecast for one enemy's pending attack. Reads its
## attack_ability and asks the ability what damage would land.
func _enemy_attack_damage(enemy: Actor) -> int:
	var ability_id_var: Variant = enemy.get("attack_ability_id")
	if not (ability_id_var is StringName) or ability_id_var == &"":
		return 0
	var ability: Ability = AbilityDatabase.get_ability(ability_id_var)
	if ability == null:
		return 0
	return ability.predicted_damage_to(enemy, player, {})
