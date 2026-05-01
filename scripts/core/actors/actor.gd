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
@export var behavior_id: StringName = &""   # 008: id in BehaviorDatabase. &"" → fallback default_melee.
@export var speed: int = 1                  # hex steps per turn (0 = immobile)
@export var damage_bonus: int = 0           # flat bonus added to any DamageEffect cast by this actor

var hp: int = 0
var _dead: bool = false
var _ability_ids: Array[StringName] = []
var _skills: Array = []   # Array[Skill] — plain Array to avoid typed-array Variant edge cases (CLAUDE.md trap)
# 008: AI-planned (or player-issued) cast for the next resolve tick. null = no cast this turn.
# Type intentionally untyped (Variant) — CastIntent class is loaded lazily; keeping this as a
# concrete type would force every Actor consumer to preload it. Read via `actor.cast_intent`.
var cast_intent: Resource = null
var move_intent_coord: Vector2i = Vector2i(-1, -1)   # 008: planned move target. (-1,-1) = no move.


## Returns ability ids available to this actor (set externally by controller or subclass).
func get_abilities() -> Array[StringName]:
	return _ability_ids


## Called by controller/subclass to declare which abilities this actor has.
func set_abilities(ids: Array[StringName]) -> void:
	_ability_ids = ids


## Returns Skill objects on this actor. Controllers call tick_skills() each turn.
func get_skills() -> Array:
	return _skills


func set_skills(skills: Array) -> void:
	_skills = skills


## Reduce cooldown on all skills by 1. Call from controller on each turn advance.
func tick_skills(by: int = 1) -> void:
	for s in _skills:
		s.tick_cooldown(by)


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


## Restore a fixed amount of HP. Clamps to max_hp. No-op on dead actors.
func heal(amount: int) -> void:
	if _dead or amount <= 0:
		return
	var old_hp: int = hp
	hp = mini(max_hp, hp + amount)
	var healed: int = hp - old_hp
	if healed <= 0:
		return
	# Reuse damaged signal with negative amount as "healed" convention.
	# hp_left is the new hp. Listeners use amount <= 0 to detect heals.
	damaged.emit(actor_id, -healed, hp)
	GameLogger.info("Actor", "%s +%d hp (%d/%d)" % [actor_id, healed, hp, max_hp])


func is_alive() -> bool:
	return not _dead


## Restore HP to max and clear death state. Used by godmode reset (F2),
## debug/cheat tooling, fountain-tile heal effects, etc.
func heal_to_full() -> void:
	_dead = false
	hp = max_hp
	# Piggyback existing signal so HealthBar (and anything else listening)
	# repaints. Amount=0, hp_left=hp — semantic 'state changed, redraw'.
	damaged.emit(actor_id, 0, hp)
	GameLogger.info("Actor", "%s healed to full (%d/%d)" % [actor_id, hp, max_hp])
