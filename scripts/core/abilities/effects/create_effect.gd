class_name CreateEffect
extends AbilityEffect
## Spawns an entity (tile-object or actor) at ctx["target_coord"] for `duration` turns.
##
## entity_id resolved via TileObjectRegistry first (objects), then EnemyDatabase
## (actors via data/enemies/<id>.json existence). Object summon writes through
## HexGrid.set_tile_object_id + TileObjectResolver.add_summon_timer. Actor summon
## delegates to LevelLoader.spawn_enemy_at, then copies caster.team onto the
## spawned actor and applies a `summoned(duration)` status that drives lifetime.
##
## See specs/041-effect-create-entity/.
##
## Required ctx:
##   target_coord: Vector2i  — spawn hex (per 026 area resolution)
##   grid:         HexGrid
##   registry:     ActorRegistry  — only for actor branch
##   actors_node:  Node           — only for actor branch (fallback to grid.get_node("Actors") or grid)
##   resolver:     TileObjectResolver  — only for object branch
##
## 021: field renamed game_object_id → entity_id.
## 026: discriminator key in effect dict (no `kind` field).
## 041: real implementation; entity_id JSON value is now "id(duration)" not bare id.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@export var entity_id: StringName = &""
@export var duration: int = 0   # 0 invalid (parser rejects); >0 turns; -1 infinite

# 041: shared counter for unique actor ids on summon. Starts at 9999 to keep a
# wide gap from WaveController._enemy_id_counter (starts at 1) — both build the
# same `<entity_id>_NNN` pattern, and ActorRegistry.register would warn on
# overwrite. The 9999 offset is enough for jam-scale runs.
static var _summon_counter: int = 9999

# 041: id-collision validator runs once per HexGrid instance. Key = grid
# instance id (cheap, unique). Re-running per-grid is OK if scene reloads.
static var _collision_check_done_for: Dictionary = {}


func _init() -> void:
	requires_alive_target = false   # hexes don't "die"


func apply(caster: Actor, _target: Variant, ctx: Dictionary) -> void:
	# Coord comes from ctx — area resolution already broke multi-target into
	# per-hex CreateEffect.apply calls.
	var coord_var: Variant = ctx.get("target_coord")
	if not coord_var is Vector2i:
		return
	var coord: Vector2i = coord_var

	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		GameLogger.warn("CreateEffect", "no grid in ctx — skip")
		return

	if entity_id == &"":
		return
	if duration == 0:
		# Parser already filters; defensive in case of programmatic instances.
		return

	_validate_id_collisions_once(grid)

	# AC-E5 (unchanged): occupied actor blocks both object and actor spawns.
	if grid.get_actor_at(coord) != &"":
		var caster_id: StringName = caster.actor_id if caster != null else &"<null>"
		GameLogger.info("CreateEffect", "%s: actor on hex %s — skip spawn '%s'" %
				[caster_id, str(coord), entity_id])
		return

	# Resolution: tile-object first, actor fallback.
	var object_reg: TileObjectRegistry = grid.get_object_registry()
	if object_reg != null and object_reg.has_object(entity_id):
		_spawn_object(coord, grid, ctx)
		return
	if LevelLoader.enemy_data_exists(entity_id):
		_spawn_actor(coord, caster, ctx)
		return
	GameLogger.warn("CreateEffect", "unknown entity_id '%s' (not in TileObjectRegistry nor data/enemies/)" % entity_id)


# ── Object branch ───────────────────────────────────────────────────────────

func _spawn_object(coord: Vector2i, grid: HexGrid, ctx: Dictionary) -> void:
	if grid.get_tile_object_id(coord) != &"":
		GameLogger.info("CreateEffect", "tile %s already has object — skip object-spawn '%s'" %
				[str(coord), entity_id])
		return
	var resolver: TileObjectResolver = ctx.get("resolver")
	if resolver == null:
		GameLogger.warn("CreateEffect", "no resolver in ctx — skip object-spawn '%s' at %s" %
				[entity_id, str(coord)])
		return
	grid.set_tile_object_id(coord, entity_id)
	resolver.add_summon_timer(coord, duration)
	EventBus.tile_object_summoned.emit(coord, entity_id, duration)
	GameLogger.info("CreateEffect", "summoned object '%s' at %s for %d turns" %
			[entity_id, str(coord), duration])


# ── Actor branch ────────────────────────────────────────────────────────────

func _spawn_actor(coord: Vector2i, caster: Actor, ctx: Dictionary) -> void:
	var grid: HexGrid = ctx["grid"]
	var registry: ActorRegistry = ctx.get("registry")
	if registry == null:
		GameLogger.warn("CreateEffect", "no registry in ctx — skip actor-spawn '%s'" % entity_id)
		return
	var actors_node: Node = ctx.get("actors_node")
	if actors_node == null:
		actors_node = grid.get_node_or_null("Actors")
	if actors_node == null:
		actors_node = grid

	_summon_counter += 1
	var spawned: Actor = LevelLoader.spawn_enemy_at(grid, registry, actors_node, coord, entity_id, _summon_counter)
	if spawned == null:
		# spawn_enemy_at already warned; nothing more to do.
		return

	# Universal team override — spawned inherits caster's team.
	if caster != null:
		spawned.team = caster.team

	# Apply summoned status (drives lifetime via SummonedRuntime.on_remove).
	var inst := StatusInstance.new()
	inst.status_id = &"summoned"
	inst.duration = duration
	var args_typed: Array[int] = [duration]
	inst.args = args_typed
	inst.source_id = caster.actor_id if caster != null else &""
	spawned.add_status(inst)

	EventBus.actor_spawned.emit(spawned.actor_id)
	GameLogger.info("CreateEffect", "summoned actor '%s' (id=%s, team=%s) at %s for %d turns" %
			[entity_id, spawned.actor_id, spawned.team, str(coord), duration])


# ── Collision check (once per grid) ─────────────────────────────────────────

# Logs a one-shot warn if any tile-object id is also a known enemy id.
# Designer-facing surface: dispatch is deterministic (object wins) but the
# duplicate is almost certainly a typo.
static func _validate_id_collisions_once(grid: HexGrid) -> void:
	var key: int = grid.get_instance_id()
	if _collision_check_done_for.has(key):
		return
	_collision_check_done_for[key] = true
	var object_reg: TileObjectRegistry = grid.get_object_registry()
	if object_reg == null:
		return
	for obj_id_v: Variant in object_reg.get_all_ids():
		var obj_id: StringName = obj_id_v
		if obj_id == &"":
			continue
		if LevelLoader.enemy_data_exists(obj_id):
			GameLogger.warn("CreateEffect",
					"id collision: '%s' is BOTH a tile-object and an enemy — runtime picks tile-object" % obj_id)
