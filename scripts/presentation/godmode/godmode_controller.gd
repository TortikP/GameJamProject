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
const GRID_W := 8
const GRID_H := 5

@export var grid: HexGrid
@export var registry: ActorRegistry
@export var player: Actor
@export var slot_bar: NodePath  # path to HBoxContainer with slot_bar.gd

var _slot_bar_node: Node
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

	# Reset turn counter for this session
	TurnManager.reset()
	# Force HUD to show initial value — also deferred so TurnLabel has connected.
	_emit_initial_turn.call_deferred()

	# AI: enemies act each world turn
	EventBus.world_turn_ended.connect(_on_world_turn_ended)

	GameLogger.info("Godmode", "ready. RMB=move, LMB/QWER/1234=select, LMB=cast, F1=spawn, F2=clear")


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


func _emit_initial_turn() -> void:
	EventBus.world_turn_ended.emit(TurnManager.current())


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
	if event.is_action_pressed("godmode_spawn_dummy"):
		_spawn_manekin()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("godmode_clear"):
		_clear_manekins()
		get_viewport().set_input_as_handled()
		return
	for i in 4:
		if event.is_action_pressed("cast_slot_%d" % i):
			# Key only SELECTS the slot. Cast is confirmed by LMB on target.
			if _slot_bar_node != null:
				_slot_bar_node.set_active(i)
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
	# Speed = 1: target must be an adjacent walkable hex. find_path returns
	# [from, ..., to] inclusive — exactly 2 entries means single step.
	var path: Array = grid.find_path(from, coord)
	if path.size() != 2:
		GameLogger.info("Godmode", "too far (speed=1, distance=%d)" % maxi(path.size() - 1, 0))
		return
	await grid.move_actor(PLAYER_ID, coord)
	if grid.get_coord(PLAYER_ID) != from:
		TurnManager.advance()


func _request_cast_active() -> void:
	if _slot_bar_node == null:
		return
	_cast_slot(_slot_bar_node.get_active())


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
	# UI clicked a slot → no auto-cast. Player still needs to aim and press LMB or
	# the slot key. This avoids accidental casts from clicking the icon.
	pass


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
	GameLogger.info("Godmode", "cleared %d manekins" % to_remove.size())


func _on_actor_died(id: StringName) -> void:
	var actor: Actor = registry.get_actor(id)
	if actor == null:
		return
	grid.clear_actor(id)
	registry.unregister(id)
	actor.queue_free()


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
# Each enemy takes one greedy step toward the player on world_turn_ended.
# Sequential — manekin1 awaits, then manekin2 awaits, etc. The _world_processing
# lock prevents the player from acting (and thus advancing the turn again) while
# the AI is mid-loop.

func _on_world_turn_ended(_turn: int) -> void:
	if _world_processing:
		return  # re-entry guard (shouldn't fire, but cheap insurance)
	if player == null or not player.is_alive():
		return
	_world_processing = true
	await _run_enemy_turn()
	_world_processing = false


func _run_enemy_turn() -> void:
	# Snapshot the enemy list — registry can mutate mid-turn (deaths, spawns).
	var enemies: Array = []
	for actor in registry.all():
		if actor is Actor and (actor as Actor).team == &"enemy":
			enemies.append(actor)
	for actor in enemies:
		if not (actor is Actor):
			continue
		var enemy: Actor = actor
		# Re-check each iteration: actor may have died from a previous step's tile effect
		if not enemy.is_alive():
			continue
		if registry.get_actor(enemy.actor_id) == null:
			continue
		var enemy_coord: Vector2i = grid.get_coord(enemy.actor_id)
		var player_coord: Vector2i = grid.get_coord(PLAYER_ID)
		if enemy_coord == Vector2i(-1, -1) or player_coord == Vector2i(-1, -1):
			continue
		var path: Array = grid.find_path(enemy_coord, player_coord)
		if path.size() <= 2:
			continue  # no path / already at player / already adjacent
		var next_hop: Vector2i = path[1]
		if grid.get_actor_at(next_hop) != &"":
			continue  # blocked by another actor — skip this enemy this turn
		await grid.move_actor(enemy.actor_id, next_hop)
