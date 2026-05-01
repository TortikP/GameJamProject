class_name ActorRegistry
extends Node
## Scene-local actor registry. Maps StringName id → Actor instance.
##
## Owned by the scene root (Godmode controller), destroyed with the scene.
## NOT an autoload by design — between-scene actor leaks are a class of bug
## we'd rather avoid. Each scene that needs actor lookup creates its own.
##
## Read by ability targets via `ctx.registry`. Written by spawners.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

var _by_id: Dictionary = {}  # StringName -> Actor


func register(actor: Actor) -> void:
	if actor == null:
		GameLogger.warn("ActorRegistry", "register(null) ignored")
		return
	if actor.actor_id == &"":
		GameLogger.warn("ActorRegistry", "register: actor has empty id — skipped")
		return
	if _by_id.has(actor.actor_id):
		GameLogger.warn("ActorRegistry", "register: id %s already taken — overwriting" % actor.actor_id)
	_by_id[actor.actor_id] = actor


func unregister(id: StringName) -> void:
	_by_id.erase(id)


func get_actor(id: StringName) -> Actor:
	if id == &"":
		return null
	return _by_id.get(id, null)


## Look up actor at a hex coord. Returns null if no actor or actor not registered.
func get_at(grid: HexGrid, coord: Vector2i) -> Actor:
	if grid == null:
		return null
	var id: StringName = grid.get_actor_at(coord)
	if id == &"":
		return null
	return get_actor(id)


func all() -> Array:
	return _by_id.values()


func clear() -> void:
	_by_id.clear()
