extends Node

## 018 smoke controller (scenes/dev/tile_objects_smoke.tscn).
##
## Goal: F5 the scene and verify three things from the console:
##   1. TileObjectRegistry loaded all 6 sample JSONs without WARN spam.
##   2. TileEffectRegistry got `burning` (the new duration-bearing effect).
##   3. Pressing F1–F4 emits the four new EventBus tile_object_* signals,
##      and this controller's listeners log them — proving the contract holds
##      end-to-end before the resolver (019) is written.
##
## What this scene does NOT do:
##   - Paint actual tile-objects on a TileMap. That requires (a) adding the
##     `object_id` custom data layer to the hex_terrain TileSet (T005a, manual
##     in editor), (b) atlas tile metadata. Once T005a is done, drop a HexGrid
##     instance into this scene next to the controller and the registry query
##     in HexGrid._build_tile_map will populate HexTile.object_id automatically.
##   - Drive applies_on_enter / aura / linger. That's the resolver (019),
##     intentionally out of scope per spec.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

# 049 / T027: 018 smoke controller is still wired into scenes/dev/tile_objects_smoke.tscn
# (we don't want to delete a working sanity-check), but its 19 GameLogger.info
# calls were spamming the console for every Godmode boot that pulled tile-object
# infrastructure. Default off; flip the const to debug 018 issues.
const _SMOKE_LOG_ENABLED: bool = false

const _OBJECTS_DIR := "res://data/tile_objects/"
const _EFFECTS_DIR := "res://data/tile_effects/"

const _EXPECTED_OBJECTS: Array[StringName] = [
	&"mountain", &"lava_pool", &"heal_fountain",
	&"wooden_barrel", &"wooden_table", &"boulder",
]

var _object_registry: TileObjectRegistry
var _effect_registry: TileEffectRegistry


func _ready() -> void:
	_load_registries()
	_dump_loaded_objects()
	_verify_burning_effect()
	_connect_signal_listeners()
	_print_help()


# ── Setup ────────────────────────────────────────────────────────────────────

func _load_registries() -> void:
	_object_registry = TileObjectRegistry.new()
	_object_registry.load_from_dir(_OBJECTS_DIR)

	_effect_registry = TileEffectRegistry.new()
	_effect_registry.load_from_dir(_EFFECTS_DIR)


func _dump_loaded_objects() -> void:
	if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", "── TileObjectRegistry sanity ─────────────────")
	var missing: Array[StringName] = []
	for id in _EXPECTED_OBJECTS:
		if not _object_registry.has_object(id):
			missing.append(id)
			continue
		var obj := _object_registry.get_object(id)
		if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", " %-15s level=%2d  blocks_move=%s  breakable=%s  triggers=[on_enter=%s on_turn_end=%s aura=%d on_attacked=%s]  linger=%s  on_destroy_effect=%s  tags=%s" % [
			obj.id, obj.level,
			obj.blocks_movement, obj.breakable,
			obj.applies_on_enter, obj.applies_on_turn_end, obj.aura_radius, obj.applies_on_attacked,
			obj.linger_effect_id if obj.linger_effect_id != &"" else "—",
			obj.on_destroy_effect_id if obj.on_destroy_effect_id != &"" else "—",
			obj.tags,
		])
	if not missing.is_empty():
		GameLogger.error("018-smoke", "MISSING expected objects: %s" % str(missing))
	else:
		if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", " all 6 expected objects present.")


func _verify_burning_effect() -> void:
	if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", "── TileEffectRegistry / burning sanity ───────")
	if not _effect_registry.has_effect(&"burning"):
		GameLogger.error("018-smoke", " burning effect NOT loaded — check data/tile_effects/burning.json")
		return
	var eff := _effect_registry.get_effect(&"burning")
	var duration := int(eff.get("duration", 0))
	if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", " burning: kind=%s amount=%s duration=%d (expected duration=2)" % [
		eff.get("kind", "?"), str(eff.get("amount", "?")), duration
	])
	if duration != 2:
		GameLogger.error("018-smoke", " burning.duration=%d, expected 2" % duration)


# ── EventBus listeners (proves AC-O7 contract) ───────────────────────────────

func _connect_signal_listeners() -> void:
	EventBus.tile_object_damaged.connect(_on_damaged)
	EventBus.tile_object_destroyed.connect(_on_destroyed)
	EventBus.tile_object_effect_triggered.connect(_on_effect_triggered)
	EventBus.tile_object_actor_exited.connect(_on_actor_exited)


func _on_damaged(coord: Vector2i, hp_remaining: int) -> void:
	if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", "EventBus.tile_object_damaged   coord=%s hp=%d" % [str(coord), hp_remaining])


func _on_destroyed(coord: Vector2i, object_id: StringName) -> void:
	if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", "EventBus.tile_object_destroyed coord=%s id=%s" % [str(coord), object_id])


func _on_effect_triggered(coord: Vector2i, target_actor_id: StringName, effect_id: StringName) -> void:
	if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", "EventBus.tile_object_effect_triggered coord=%s actor=%s effect=%s" % [str(coord), target_actor_id, effect_id])


func _on_actor_exited(coord: Vector2i, actor_id: StringName, object_id: StringName) -> void:
	if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", "EventBus.tile_object_actor_exited coord=%s actor=%s object=%s" % [str(coord), actor_id, object_id])


# ── Manual signal injection — proves listeners + signal shapes ───────────────

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return
	match (event as InputEventKey).keycode:
		KEY_F1:
			if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", "F1: emitting tile_object_damaged …")
			EventBus.tile_object_damaged.emit(Vector2i(2, 3), 1)
		KEY_F2:
			if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", "F2: emitting tile_object_destroyed …")
			EventBus.tile_object_destroyed.emit(Vector2i(2, 3), &"wooden_barrel")
		KEY_F3:
			if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", "F3: emitting tile_object_effect_triggered …")
			EventBus.tile_object_effect_triggered.emit(Vector2i(4, 5), &"player", &"damage_zone")
		KEY_F4:
			if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", "F4: emitting tile_object_actor_exited …")
			EventBus.tile_object_actor_exited.emit(Vector2i(4, 5), &"player", &"lava_pool")


func _print_help() -> void:
	if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", "── Manual signal smoke (F1–F4) ───────────────")
	if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", " F1 — tile_object_damaged           F2 — tile_object_destroyed")
	if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", " F3 — tile_object_effect_triggered  F4 — tile_object_actor_exited")
	if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", " AC-O8 in-scene smoke (lava walk, barrel break, fountain aura)")
	if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", " requires T005a (TileSet 'object_id' custom data layer) and a")
	if _SMOKE_LOG_ENABLED: GameLogger.info("018-smoke", " painted TileMap — manual in editor, see specs/018-tile-objects/tasks.md.")
