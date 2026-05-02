extends Node
## ManekinSpawner — F1/F2 sandbox helpers. Spawns dummy enemies on the hex
## under the cursor (F1) and clears all enemies + revives player (F2). Plans
## the new manekin immediately so its intent is visible without ending turn.


const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

# 036: single generic enemy.tscn, manekin selected by enemy_data_id JSON ref.
const ENEMY_SCENE := preload("res://scenes/dev/enemy.tscn")
const SANDBOX_ENEMY_ID: StringName = &"manekin"

var _ctrl: Node = null
var _next_idx: int = 1


func _ready() -> void:
	_ctrl = get_parent()


func spawn() -> void:
	var grid: HexGrid = _ctrl.grid
	var registry: ActorRegistry = _ctrl.registry
	var coord := grid.coord_under_mouse()
	if coord == Vector2i(-1, -1) or not grid.is_walkable(coord):
		GameLogger.info("Godmode", "cannot spawn at %s" % str(coord))
		return
	if grid.get_actor_at(coord) != &"":
		GameLogger.info("Godmode", "occupied at %s" % str(coord))
		return
	var idx := _next_idx
	_next_idx += 1
	var id := StringName("dummy_%03d" % idx)
	var manekin: Actor = ENEMY_SCENE.instantiate()
	# Set enemy_data_id BEFORE add_child so _ready loads manekin.json.
	manekin.set(&"enemy_data_id", SANDBOX_ENEMY_ID)
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
	# adding a new one can block existing pathing. Telegraphs refreshed inside
	# replan_all_and_refresh on the AiDriver.
	_ctrl.ai.replan_all_and_refresh()
	_ctrl.refresh_overlay()


func clear_all() -> void:
	var grid: HexGrid = _ctrl.grid
	var registry: ActorRegistry = _ctrl.registry
	var to_remove: Array = []
	# 044: was filtering team == &"enemy". Now wipes any non-player actor so
	# F2 also clears player-side summoned creatures (else they pile up forever
	# in the sandbox between resets). Symmetric with ai_driver's filter switch.
	for actor in registry.all():
		if actor is Actor and (actor as Actor) != _ctrl.player:
			to_remove.append(actor)
	for actor in to_remove:
		var a: Actor = actor
		grid.clear_actor(a.actor_id)
		registry.unregister(a.actor_id)
		a.queue_free()
	_ctrl.telegraphs.clear()
	# F2 doubles as a sandbox reset: revive player and refill HP. Lets the
	# tester keep playing after death without restarting the scene.
	if _ctrl.player != null:
		_ctrl.player.heal_to_full()
	_ctrl.deselect_to_player()
	GameLogger.info("Godmode", "cleared %d manekins, player reset" % to_remove.size())


func _on_actor_died(id: StringName) -> void:
	var actor: Actor = _ctrl.registry.get_actor(id)
	if actor == null:
		return
	_ctrl.grid.clear_actor(id)
	_ctrl.registry.unregister(id)
	actor.queue_free()
	# An enemy died → its intent is gone, refresh visuals to drop its label
	_ctrl.telegraphs.refresh()
