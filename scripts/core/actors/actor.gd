class_name Actor
extends Node2D
## Actor — minimal HP-bearing entity. Player and dummies share this contract.
##
## Responsibilities:
##   - Own hp / max_hp.
##   - Expose take_damage(amount) and emit `damaged` / `died` signals.
##   - Emit EventBus.actor_died on death (one-shot, idempotent).
##
## NON-responsibilities:
##   - Movement (HexGrid handles position by id).
##   - AI (separate component, not on this PR).
##   - Visuals (subclass adds Polygon2D / Sprite2D as child).

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

signal damaged(id: StringName, amount: int, hp_left: int)
signal died(id: StringName)

@export var actor_id: StringName = &""
@export var max_hp: int = 100
@export var team: StringName = &"neutral"   # &"player" / &"enemy" / &"neutral"

var hp: int = 0
var _dead: bool = false


func _ready() -> void:
	hp = max_hp
	if actor_id == &"":
		GameLogger.warn("Actor", "spawned with empty actor_id — abilities can't target it")


func take_damage(amount: int) -> void:
	if _dead or amount <= 0:
		return
	hp = max(0, hp - amount)
	damaged.emit(actor_id, amount, hp)
	GameLogger.info("Actor", "%s -%d hp (%d/%d)" % [actor_id, amount, hp, max_hp])
	if hp == 0:
		_dead = true
		died.emit(actor_id)
		EventBus.actor_died.emit(actor_id)


func is_alive() -> bool:
	return not _dead
