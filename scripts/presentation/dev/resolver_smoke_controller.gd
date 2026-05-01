extends Node
## 019-resolver smoke test (scenes/dev/resolver_smoke.tscn).
##
## F5 this scene. Check the Output panel for PASS / FAIL lines.
## No TileMap, no GUI — pure logic test over real registries + real Actor nodes.
##
## Scenarios covered:
##   A. applies_on_enter  : step onto lava_pool → damage_zone (5 dmg)
##   B. applies_on_turn_end : stand on lava → turn_ended → damage_zone again
##   C. linger             : exit lava → linger pushed → 2 turns of burning (2 dmg each)
##   D. aura heal          : stand near heal_fountain → turn_ended → heal_fountain (3 hp)
##   E. damage_object      : 2 hits on wooden_barrel → destroy → overlay placed
##
## Stub grid satisfies the interface HexGrid exposes to TileObjectResolver
## without needing a TileMapLayer or asset files.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

# ── Stub HexGrid ─────────────────────────────────────────────────────────────
## Extends HexGrid so the typed var _grid: HexGrid in TileObjectResolver
## accepts it. Overrides only the 6 methods the resolver actually calls.
class HexGridStub extends HexGrid:
	var _obj_map: Dictionary = {}      # Vector2i → StringName
	var _actor_coord: Dictionary = {}  # StringName → Vector2i
	var _coord_actor: Dictionary = {}  # Vector2i → StringName
	var _overlays: Dictionary = {}     # Vector2i → StringName

	func get_tile_object_id(coord: Vector2i) -> StringName:
		return _obj_map.get(coord, &"")

	func set_tile_object_id(coord: Vector2i, id: StringName) -> void:
		_obj_map[coord] = id

	func get_all_tile_object_ids() -> Dictionary:
		var result: Dictionary = {}
		for c: Variant in _obj_map:
			var cv: Vector2i = c as Vector2i
			if _obj_map[c] != &"":
				result[cv] = _obj_map[c]
		return result

	func get_coord(id: StringName) -> Vector2i:
		return _actor_coord.get(id, Vector2i(-1, -1))

	func get_actor_at(coord: Vector2i) -> StringName:
		return _coord_actor.get(coord, &"")

	## For aura test: return all coords that have actors, except 'from' itself.
	## Sufficient for a radius-1 fountain with one adjacent actor.
	func reachable_within(from: Vector2i, _max_steps: int, _occupied: Array) -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		for c: Variant in _coord_actor:
			var cv: Vector2i = c as Vector2i
			if cv != from:
				result.append(cv)
		return result

	func add_overlay_effect(coord: Vector2i, effect_id: StringName) -> void:
		_overlays[coord] = effect_id

	# ── Test helpers ──────────────────────────────────────────────────────────
	func place_object(coord: Vector2i, obj_id: StringName) -> void:
		_obj_map[coord] = obj_id

	func place_actor(actor_id: StringName, coord: Vector2i) -> bool:
		_actor_coord[actor_id] = coord
		_coord_actor[coord] = actor_id
		return true
	func move_actor_to(actor_id: StringName, new_coord: Vector2i) -> void:
		var old: Vector2i = _actor_coord.get(actor_id, Vector2i(-1, -1))
		if old != Vector2i(-1, -1):
			_coord_actor.erase(old)
		_actor_coord[actor_id] = new_coord
		_coord_actor[new_coord] = actor_id


# ── Smoke harness ─────────────────────────────────────────────────────────────

var _object_registry: TileObjectRegistry
var _effect_registry: TileEffectRegistry
var _actor_registry: ActorRegistry
var _grid: HexGridStub
var _resolver: TileObjectResolver
var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	GameLogger.info("019-smoke", "════ TileObjectResolver smoke ════")
	_setup_registries()
	_setup_grid()
	_setup_resolver()
	_run_all_scenarios()
	_print_summary()


# ── Setup ─────────────────────────────────────────────────────────────────────

func _setup_registries() -> void:
	_object_registry = TileObjectRegistry.new()
	_object_registry.load_from_dir("res://data/tile_objects/")
	_effect_registry = TileEffectRegistry.new()
	_effect_registry.load_from_dir("res://data/tile_effects/")
	_actor_registry = ActorRegistry.new()
	add_child(_actor_registry)


func _setup_grid() -> void:
	_grid = HexGridStub.new()
	_grid.name = "HexGridStub"
	add_child(_grid)


func _setup_resolver() -> void:
	_resolver = TileObjectResolver.new()
	_resolver.name = "TileObjectResolver"
	add_child(_resolver)
	_resolver.setup(_grid, _object_registry, _effect_registry, _actor_registry)


func _make_actor(id: StringName, team: StringName, max_hp: int = 100) -> Actor:
	var a := Actor.new()
	a.actor_id = id
	a.team = team
	a.max_hp = max_hp
	add_child(a)           # _ready fires → a.hp = max_hp
	_actor_registry.register(a)
	return a


# ── Scenarios ─────────────────────────────────────────────────────────────────

func _run_all_scenarios() -> void:
	_scenario_a_on_enter()
	_scenario_b_on_turn_end()
	_scenario_c_linger()
	_scenario_d_aura_heal()
	_scenario_e_damage_object()


## A. applies_on_enter: tile_entered → lava_pool behavior_effect_id=damage_zone (5 dmg)
func _scenario_a_on_enter() -> void:
	GameLogger.info("019-smoke", "── A: applies_on_enter ──────────────────────")
	var actor := _make_actor(&"actor_a", &"player")
	var coord := Vector2i(0, 0)
	_grid.place_object(coord, &"lava_pool")
	_grid.place_actor(&"actor_a", coord)
	var hp_before := actor.hp

	EventBus.tile_entered.emit(&"actor_a", coord)

	# lava_pool.behavior_effect_id = damage_zone, amount = 5
	_check("A.on_enter: hp reduced by 5", actor.hp == hp_before - 5)

	# cleanup
	_grid.place_object(coord, &"")
	_actor_registry.unregister(&"actor_a")
	actor.queue_free()


## B. applies_on_turn_end: player standing on lava → player_turn_ended → damage
func _scenario_b_on_turn_end() -> void:
	GameLogger.info("019-smoke", "── B: applies_on_turn_end ───────────────────")
	var actor := _make_actor(&"actor_b", &"player")
	var coord := Vector2i(1, 0)
	_grid.place_object(coord, &"lava_pool")
	_grid.place_actor(&"actor_b", coord)
	var hp_before := actor.hp

	EventBus.player_turn_ended.emit(1)

	# lava_pool has applies_on_turn_end=true → damage_zone applied (5 dmg)
	# also aura, linger ticks run but no linger stack yet → net -5
	_check("B.on_turn_end: hp reduced by 5", actor.hp == hp_before - 5)

	_grid.place_object(coord, &"")
	_actor_registry.unregister(&"actor_b")
	actor.queue_free()


## C. linger: exit lava → linger pushed → two turn_end ticks of burning (2 dmg each)
func _scenario_c_linger() -> void:
	GameLogger.info("019-smoke", "── C: linger (burning 2 dmg × 2 turns) ─────")
	var actor := _make_actor(&"actor_c", &"player")
	var coord := Vector2i(2, 0)
	_grid.place_object(coord, &"lava_pool")
	_grid.place_actor(&"actor_c", coord)

	# Actor exits lava tile → linger_effect_id = burning (duration=2) pushed
	EventBus.tile_object_actor_exited.emit(coord, &"actor_c", &"lava_pool")
	_grid.place_object(coord, &"")
	_grid.move_actor_to(&"actor_c", Vector2i(2, 1))  # moved away

	var hp_after_exit := actor.hp

	# Turn 1 tick: burning applied (2 dmg), turns_left becomes 1
	EventBus.player_turn_ended.emit(2)
	_check("C.linger turn1: -2 dmg", actor.hp == hp_after_exit - 2)

	# Turn 2 tick: burning applied again (2 dmg), then removed
	var hp_after_t1 := actor.hp
	EventBus.player_turn_ended.emit(3)
	_check("C.linger turn2: -2 dmg", actor.hp == hp_after_t1 - 2)

	# Turn 3: linger stack empty, no more damage
	var hp_after_t2 := actor.hp
	EventBus.player_turn_ended.emit(4)
	_check("C.linger turn3: no more dmg", actor.hp == hp_after_t2)

	_actor_registry.unregister(&"actor_c")
	actor.queue_free()


## D. aura: actor adjacent to heal_fountain (aura_radius=1) → heal 3 per turn_end
func _scenario_d_aura_heal() -> void:
	GameLogger.info("019-smoke", "── D: aura heal ─────────────────────────────")
	var actor := _make_actor(&"actor_d", &"player")
	actor.take_damage(20)       # wound actor so heal has room
	var fountain_coord := Vector2i(5, 0)
	var actor_coord    := Vector2i(5, 1)  # adjacent
	_grid.place_object(fountain_coord, &"heal_fountain")
	_grid.place_actor(&"actor_d", actor_coord)
	var hp_before := actor.hp

	EventBus.player_turn_ended.emit(5)

	# heal_fountain: behavior_effect_id=heal_fountain (kind=heal, amount=3)
	# applies_to=["player"] → actor_d qualifies
	_check("D.aura: hp increased by 3", actor.hp == hp_before + 3)

	_grid.place_object(fountain_coord, &"")
	_actor_registry.unregister(&"actor_d")
	actor.queue_free()


## E. damage_object: wooden_barrel (hp=2) takes 1+1 damage → destroyed → overlay set
func _scenario_e_damage_object() -> void:
	GameLogger.info("019-smoke", "── E: breakable / on_destroy ────────────────")
	var barrel_coord := Vector2i(10, 0)
	_grid.place_object(barrel_coord, &"wooden_barrel")

	var destroyed_signal_fired := false
	var destroyed_id: StringName = &""
	EventBus.tile_object_destroyed.connect(
		func(coord: Vector2i, obj_id: StringName) -> void:
			if coord == barrel_coord:
				destroyed_signal_fired = true
				destroyed_id = obj_id,
		CONNECT_ONE_SHOT
	)

	_resolver.damage_object(barrel_coord, 1, &"")  # hp 2→1
	_check("E.damage_1: still alive (hp=1)", _grid.get_tile_object_id(barrel_coord) == &"wooden_barrel")

	_resolver.damage_object(barrel_coord, 1, &"")  # hp 1→0 → destroy
	_check("E.damage_2: object cleared from grid", _grid.get_tile_object_id(barrel_coord) == &"")
	_check("E.damage_2: tile_object_destroyed emitted", destroyed_signal_fired)
	_check("E.damage_2: destroyed id = wooden_barrel", destroyed_id == &"wooden_barrel")
	# wooden_barrel.on_destroy_effect_id = damage_zone → overlay placed
	_check("E.on_destroy: overlay = damage_zone", _grid._overlays.get(barrel_coord, &"") == &"damage_zone")


# ── Helpers ───────────────────────────────────────────────────────────────────

func _check(label: String, condition: bool) -> void:
	if condition:
		_pass_count += 1
		GameLogger.info("019-smoke", "  PASS  %s" % label)
	else:
		_fail_count += 1
		GameLogger.error("019-smoke", "  FAIL  %s" % label)


func _print_summary() -> void:
	var total := _pass_count + _fail_count
	GameLogger.info("019-smoke", "════ %d/%d passed ════" % [_pass_count, total])
	if _fail_count == 0:
		GameLogger.info("019-smoke", "All checks PASS — resolver smoke green.")
	else:
		GameLogger.error("019-smoke", "%d check(s) FAILED — see FAIL lines above." % _fail_count)
