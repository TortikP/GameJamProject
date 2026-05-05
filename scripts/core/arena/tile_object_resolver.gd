class_name TileObjectResolver
extends Node

## Runtime resolver for static tile objects (019-tile-object-resolver).
## Drives applies_on_enter, applies_on_turn_end, aura, linger DoT,
## breakable HP tracking, and on_destroy side effects.
##
## Scene-local — NOT an autoload. The arena controller creates one instance
## and calls setup() after grid.initialize() so registries are populated.
## Connects to EventBus in setup(); disconnects automatically on free().

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

var _grid: HexGrid
var _object_registry: TileObjectRegistry
var _effect_registry: TileEffectRegistry
var _actor_registry: ActorRegistry

# coord (Vector2i) -> int. Lazy-initialised on first damage from TileObject.hp.
# Cleared on destruction.
var _runtime_hp: Dictionary = {}

# actor_id (StringName) -> Array[Dictionary {effect_id: StringName, turns_left: int}]
# Populated by _on_tile_object_actor_exited; ticked down each player_turn_ended.
var _linger_stack: Dictionary = {}

# 041: coord (Vector2i) -> int turns_left. >0 ticks down each player_turn_ended;
# -1 means infinite (never ticks). Populated by add_summon_timer (called from
# CreateEffect on object summon). Cleared on natural expire OR on
# tile_object_destroyed (cleanup listener — handles combat-destroy before expire).
var _summon_timers: Dictionary = {}


# ────────────────────────────────────────────────────────────────────────────
# Public API
# ────────────────────────────────────────────────────────────────────────────

## Initialise and subscribe to EventBus. Call after grid.initialize().
func setup(
		grid: HexGrid,
		object_reg: TileObjectRegistry,
		effect_reg: TileEffectRegistry,
		actor_reg: ActorRegistry
) -> void:
	_grid = grid
	_object_registry = object_reg
	_effect_registry = effect_reg
	_actor_registry = actor_reg
	_connect_signals()
	GameLogger.info("TileObjectResolver", "setup complete")


## Apply raw damage to the breakable object at coord.
## Called by the spell/ability system when an attack targets a tile that has an object.
## attacker_id: actor that triggered the hit; &"" if no specific attacker (AoE, chain, etc.).
func damage_object(coord: Vector2i, amount: int, attacker_id: StringName = &"") -> void:
	if _grid == null:
		return
	var obj_id: StringName = _grid.get_tile_object_id(coord)
	if obj_id == &"":
		return
	var obj: TileObject = _object_registry.get_object(obj_id)
	if not obj.breakable:
		return

	# Lazy-init runtime HP from the object definition's base hp.
	if not _runtime_hp.has(coord):
		_runtime_hp[coord] = obj.hp

	var hp: int = max(0, int(_runtime_hp[coord]) - amount)
	_runtime_hp[coord] = hp
	EventBus.tile_object_damaged.emit(coord, hp)
	GameLogger.info("TileObjectResolver", "%s at %s took %d damage (hp=%d)" % [obj_id, str(coord), amount, hp])

	if obj.applies_on_attacked and obj.behavior_effect_id != &"":
		var attacker: Actor = _actor_registry.get_actor(attacker_id)
		if attacker != null:
			_apply_effect_to_actor(obj.behavior_effect_id, attacker, coord)

	if hp <= 0:
		_destroy_object(coord, obj)


# ────────────────────────────────────────────────────────────────────────────
# Signal handlers
# ────────────────────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	EventBus.tile_entered.connect(_on_tile_entered)
	EventBus.player_turn_ended.connect(_on_player_turn_ended)
	EventBus.tile_object_actor_exited.connect(_on_tile_object_actor_exited)
	# 041: clean up summon timers when object is destroyed (combat or other path)
	# before its summoned timer expires — avoids double-destroy on later tick.
	EventBus.tile_object_destroyed.connect(_on_tile_object_destroyed_summon_cleanup)


## applies_on_enter: actor stepped onto tile -> apply behavior_effect_id once.
func _on_tile_entered(actor_id: StringName, coord: Vector2i) -> void:
	if _grid == null:
		return
	var obj_id: StringName = _grid.get_tile_object_id(coord)
	if obj_id == &"":
		return
	var obj: TileObject = _object_registry.get_object(obj_id)
	if not obj.applies_on_enter or obj.behavior_effect_id == &"":
		return
	var actor: Actor = _actor_registry.get_actor(actor_id)
	if actor == null:
		return
	_apply_effect_to_actor(obj.behavior_effect_id, actor, coord)


## Fired once per player action. Drives: applies_on_turn_end, aura, linger tick.
## 041: also ticks summon timers for transient objects.
func _on_player_turn_ended(_turn: int) -> void:
	_tick_turn_end_effects()
	_tick_aura_effects()
	_tick_linger_stacks()
	_tick_summon_timers()


## linger push: actor left a tile whose object has linger_effect_id set.
func _on_tile_object_actor_exited(coord: Vector2i, actor_id: StringName, obj_id: StringName) -> void:
	var obj: TileObject = _object_registry.get_object(obj_id)
	if obj.linger_effect_id == &"":
		return
	var eff: Dictionary = _effect_registry.get_effect(obj.linger_effect_id)
	if eff.is_empty():
		GameLogger.warn("TileObjectResolver", "linger effect '%s' not in registry — skipping" % obj.linger_effect_id)
		return
	var duration: int = int(eff.get("duration", 0))
	if duration <= 0:
		GameLogger.warn("TileObjectResolver", "linger effect '%s' has duration<=0 — skipping" % obj.linger_effect_id)
		return
	if not _linger_stack.has(actor_id):
		_linger_stack[actor_id] = []
	_linger_stack[actor_id].append({"effect_id": obj.linger_effect_id, "turns_left": duration})
	GameLogger.info("TileObjectResolver", "linger '%s' pushed on %s for %d turns (exited %s)" % [
		obj.linger_effect_id, actor_id, duration, str(coord)
	])


# ────────────────────────────────────────────────────────────────────────────
# Turn-end processing
# ────────────────────────────────────────────────────────────────────────────

## applies_on_turn_end: for every living actor, check if their tile has an object
## with applies_on_turn_end=true and fire its effect.
func _tick_turn_end_effects() -> void:
	for actor: Variant in _actor_registry.all():
		var a: Actor = actor as Actor
		if not a.is_alive():
			continue
		var coord: Vector2i = _grid.get_coord(a.actor_id)
		if coord == Vector2i(-1, -1):
			continue
		var obj_id: StringName = _grid.get_tile_object_id(coord)
		if obj_id == &"":
			continue
		var obj: TileObject = _object_registry.get_object(obj_id)
		if obj.applies_on_turn_end and obj.behavior_effect_id != &"":
			_apply_effect_to_actor(obj.behavior_effect_id, a, coord)


## aura: for every tile with an object that has aura_radius>=1, find all actors
## within that radius via reachable_within and apply behavior_effect_id to each.
## reachable_within starts BFS from coord (even if coord itself is non-walkable) so
## LARGE objects like heal_fountain correctly radiate to neighbouring walkable tiles.
func _tick_aura_effects() -> void:
	var all_obj_coords: Dictionary = _grid.get_all_tile_object_ids()
	for coord: Variant in all_obj_coords:
		var c: Vector2i = coord as Vector2i
		var obj_id: StringName = StringName(all_obj_coords[coord])
		var obj: TileObject = _object_registry.get_object(obj_id)
		if obj.aura_radius <= 0 or obj.behavior_effect_id == &"":
			continue
		var in_range: Array[Vector2i] = _grid.reachable_within(c, obj.aura_radius, [])
		for rc: Vector2i in in_range:
			var occupant_id: StringName = _grid.get_actor_at(rc)
			if occupant_id == &"":
				continue
			var a: Actor = _actor_registry.get_actor(occupant_id)
			if a == null or not a.is_alive():
				continue
			_apply_effect_to_actor(obj.behavior_effect_id, a, c)


## linger tick: each turn decrement turns_left, apply effect if actor is alive,
## remove stack entry when turns_left reaches 0.
func _tick_linger_stacks() -> void:
	var done: Array[StringName] = []
	for actor_id: Variant in _linger_stack:
		var id: StringName = StringName(actor_id)
		var a: Actor = _actor_registry.get_actor(id)
		var stacks: Array = _linger_stack[id]
		var remaining: Array = []
		for entry: Variant in stacks:
			var e: Dictionary = entry as Dictionary
			var effect_id: StringName = StringName(e.get("effect_id", ""))
			var turns_left: int = int(e.get("turns_left", 0))
			if a != null and a.is_alive():
				# apply effect without coord — linger travels with the actor.
				_apply_effect_to_actor_no_coord(effect_id, a)
			turns_left -= 1
			if turns_left > 0:
				remaining.append({"effect_id": effect_id, "turns_left": turns_left})
		if remaining.is_empty():
			done.append(id)
		else:
			_linger_stack[id] = remaining
	for id: StringName in done:
		_linger_stack.erase(id)


# ────────────────────────────────────────────────────────────────────────────
# Object destruction
# ────────────────────────────────────────────────────────────────────────────

func _destroy_object(coord: Vector2i, obj: TileObject) -> void:
	_runtime_hp.erase(coord)
	_grid.set_tile_object_id(coord, &"")
	EventBus.tile_object_destroyed.emit(coord, obj.id)
	GameLogger.info("TileObjectResolver", "destroyed %s at %s" % [obj.id, str(coord)])

	if obj.on_destroy_effect_id != &"":
		_grid.add_overlay_effect(coord, obj.on_destroy_effect_id)
		GameLogger.info("TileObjectResolver", "overlay effect %s placed at %s" % [obj.on_destroy_effect_id, str(coord)])

	if obj.on_destroy_spawn_object_id != &"":
		if _object_registry.has_object(obj.on_destroy_spawn_object_id):
			_grid.set_tile_object_id(coord, obj.on_destroy_spawn_object_id)
			GameLogger.info("TileObjectResolver", "spawned %s at %s" % [obj.on_destroy_spawn_object_id, str(coord)])
		else:
			GameLogger.warn("TileObjectResolver", "on_destroy_spawn '%s' not in registry" % obj.on_destroy_spawn_object_id)


# ────────────────────────────────────────────────────────────────────────────
# Effect application helpers
# ────────────────────────────────────────────────────────────────────────────

## Apply a tile effect to an actor; emit tile_object_effect_triggered for listeners
## (presentation floating numbers etc.). Filters by applies_to vs actor.team.
func _apply_effect_to_actor(effect_id: StringName, actor: Actor, coord: Vector2i) -> void:
	var eff: Dictionary = _effect_registry.get_effect(effect_id)
	if eff.is_empty():
		GameLogger.warn("TileObjectResolver", "effect '%s' not in registry" % effect_id)
		return
	if not _team_matches(actor, eff):
		return
	var kind: StringName = StringName(eff.get("kind", ""))
	var amount: int = int(eff.get("amount", 0))
	match kind:
		&"damage":
			actor.take_damage(amount)
			EventBus.tile_object_effect_triggered.emit(coord, actor.actor_id, effect_id)
		&"heal":
			actor.heal(amount)
			EventBus.tile_object_effect_triggered.emit(coord, actor.actor_id, effect_id)
		_:
			GameLogger.warn("TileObjectResolver", "unknown effect kind '%s' in '%s'" % [kind, effect_id])


## Variant for linger ticks where there is no meaningful source coord.
## Does NOT emit tile_object_effect_triggered (the actor emits damage_dealt/heal_done).
func _apply_effect_to_actor_no_coord(effect_id: StringName, actor: Actor) -> void:
	var eff: Dictionary = _effect_registry.get_effect(effect_id)
	if eff.is_empty():
		GameLogger.warn("TileObjectResolver", "linger effect '%s' not in registry" % effect_id)
		return
	if not _team_matches(actor, eff):
		return
	var kind: StringName = StringName(eff.get("kind", ""))
	var amount: int = int(eff.get("amount", 0))
	match kind:
		&"damage":
			actor.take_damage(amount)
		&"heal":
			actor.heal(amount)
		_:
			GameLogger.warn("TileObjectResolver", "unknown effect kind '%s' in '%s'" % [kind, effect_id])


func _team_matches(actor: Actor, eff: Dictionary) -> bool:
	var applies_to: Array = eff.get("applies_to", [])
	if applies_to.is_empty():
		return true	# no filter = all teams
	return applies_to.has(str(actor.team))


# ────────────────────────────────────────────────────────────────────────────
# 041: Summon timers (transient tile objects)
# ────────────────────────────────────────────────────────────────────────────

## Public — called by CreateEffect after grid.set_tile_object_id(coord, obj_id).
## duration > 0: object lives N turns then auto-destroys.
## duration < 0: infinite (no decrement, no auto-destroy). Stored for completeness.
## duration == 0: invalid, ignored with warn (parser already filters).
func add_summon_timer(coord: Vector2i, duration: int) -> void:
	if duration == 0:
		GameLogger.warn("TileObjectResolver", "add_summon_timer: duration=0 invalid for %s — ignored" % str(coord))
		return
	_summon_timers[coord] = duration
	GameLogger.info("TileObjectResolver", "summon timer set at %s for %d turns" % [str(coord), duration])


## Decrement all summon timers each player_turn_ended. On 0, destroy via
## the standard _destroy_object path (emits tile_object_destroyed, fires
## on_destroy_* chains). Self-cleanup on the destroyed signal keeps the
## dict consistent if combat reaches the object first.
func _tick_summon_timers() -> void:
	var done: Array[Vector2i] = []
	for coord_v: Variant in _summon_timers.keys():
		var c: Vector2i = coord_v
		var t: int = int(_summon_timers[c])
		if t < 0:
			continue   # infinite — never decrement
		t -= 1
		if t <= 0:
			done.append(c)
		else:
			_summon_timers[c] = t
	for c: Vector2i in done:
		_summon_timers.erase(c)
		var obj_id: StringName = _grid.get_tile_object_id(c)
		if obj_id == &"":
			continue   # already destroyed by combat; cleanup-listener got it first
		var obj: TileObject = _object_registry.get_object(obj_id)
		GameLogger.info("TileObjectResolver", "summoned object %s at %s expired" % [obj_id, str(c)])
		_destroy_object(c, obj)


## Cleanup: object destroyed (combat or other path) before its summon timer
## expired. Erase the entry so _tick_summon_timers doesn't fire a second
## destroy on a now-empty coord.
func _on_tile_object_destroyed_summon_cleanup(coord: Vector2i, _obj_id: StringName) -> void:
	_summon_timers.erase(coord)
