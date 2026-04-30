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
const PLAYER_ID: StringName = &"player"
const GRID_W := 10
const GRID_H := 10

@export var grid: HexGrid
@export var registry: ActorRegistry
@export var player: Actor
@export var slot_bar: NodePath  # path to HBoxContainer with slot_bar.gd

var _slot_bar_node: Node
var _next_manekin_idx: int = 1


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
	_paint_grid()
	grid.actor_step_started.connect(_on_step_started)
	grid.initialize()
	_place_player()

	# 5. Seed slots
	_seed_slots()
	if _slot_bar_node != null and _slot_bar_node.has_signal("slot_activated"):
		_slot_bar_node.slot_activated.connect(_on_slot_activated)

	# Reset turn counter for this session
	TurnManager.reset()
	# Force HUD to show initial value
	EventBus.world_turn_ended.emit(TurnManager.current())

	GameLogger.info("Godmode", "ready. RMB=move, LMB/QWER/1234=cast, F1=spawn dummy, F2=clear")


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
	if debug_punch == null:
		GameLogger.warn("Godmode", "debug_punch not found in AbilityDatabase")
		return
	_slot_bar_node.set_slot(0, debug_punch)
	_slot_bar_node.set_active(0)


# ── Input ────────────────────────────────────────────────────────────────────

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
			_activate_and_cast(i)
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
	if grid._moving:
		return
	var coord := grid.coord_under_mouse()
	if coord == Vector2i(-1, -1):
		return
	if not grid.is_walkable(coord):
		GameLogger.info("Godmode", "unreachable: %s" % str(coord))
		return
	if grid.get_actor_at(coord) == PLAYER_ID:
		return
	if grid.get_actor_at(coord) != &"":
		GameLogger.info("Godmode", "occupied: %s" % str(coord))
		return
	var from: Vector2i = grid.get_coord(PLAYER_ID)
	await grid.move_actor(PLAYER_ID, coord)
	# Only tick if we actually moved (path may have been empty / unreachable mid-move)
	if grid.get_coord(PLAYER_ID) != from:
		TurnManager.advance()


func _activate_and_cast(slot_index: int) -> void:
	if _slot_bar_node == null:
		return
	_slot_bar_node.set_active(slot_index)
	_cast_slot(slot_index)


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
	if grid._moving:
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
	if actor_id != PLAYER_ID:
		return
	var pos: Vector2 = grid.tile_map_layer.map_to_local(to)
	var duration: float = GameSpeed.get_value("arena", "step_duration", 0.18) * grid.get_move_cost(to)
	create_tween().tween_property(player, "position", pos, duration)
