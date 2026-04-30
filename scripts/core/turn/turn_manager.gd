extends Node
## TurnManager — global turn counter for the current scene.
##
## One tick = one player action (one move-completion or one cast). Manekins
## and AI listen on `world_turn_ended` to act after the player.
##
## Reset between scene loads: scenes that use turn-based logic call
## `reset()` in their controller's `_ready()`. Autoload state survives scene
## changes by design — the turn counter is a property of the active session.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

var _turn: int = 1


func current() -> int:
	return _turn


func reset() -> void:
	_turn = 1
	GameLogger.info("TurnManager", "reset → 1")


## Call after every confirmed player action (move finished, ability cast).
## Order: emit player_turn_ended (turn that just ended), increment, emit world_turn_ended (new turn).
func advance() -> void:
	EventBus.player_turn_ended.emit(_turn)
	_turn += 1
	EventBus.world_turn_ended.emit(_turn)
