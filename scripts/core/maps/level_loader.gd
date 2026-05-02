class_name LevelLoader

## Applies a LevelData onto a HexGrid + ActorRegistry that the controller has
## already painted and initialized. The controller is still responsible for
## tile_set assignment, set_cell painting, and grid.initialize() — see
## godmode_controller's "queued level" branch in _ready().
##
## Why split? grid.initialize() reads custom_data from the painted tile_map,
## building HexTile objects (incl. base object_id). Setting custom-objects
## via set_tile_object_id BEFORE initialize would be overwritten by
## _build_tile_map. So: paint → initialize → THEN apply_to.
##
## apply_to performs:
##   1. for each LevelData.objects entry: grid.set_tile_object_id(coord, id)
##   2. grid.rebuild_pathfinder() — once, after the batch
##   3. for each LevelData.spawners entry: instantiate scene, place actor

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const PLAYER_SCENE: PackedScene = preload("res://scenes/dev/player.tscn")
const MANEKIN_SCENE: PackedScene = preload("res://scenes/dev/manekin.tscn")
const BUSH_SCENE: PackedScene = preload("res://scenes/dev/bush.tscn")

# enemy_id → PackedScene mapping. New enemies plug in here as we add prefabs.
# data/enemies/<id>.json files declare existence; this table maps id → scene.
const ENEMY_SCENES: Dictionary = {
	&"manekin": MANEKIN_SCENE,
	&"bush": BUSH_SCENE,
}

const PLAYER_ID: StringName = &"player"


## Returns the spawned player Actor (or null if no player spawner present).
## Caller is responsible for storing the reference (e.g. for camera follow).
##
## actors_node: the parent Node that should own actor instances. Typically
## grid.get_node("Actors") if it exists, else grid itself.
##
## skip_enemies (024-wave-editor): when true, only the player spawner from
## wave 0 is consumed; enemy spawners are left for WaveController to manage
## as countdown placeholders. Default false preserves legacy single-wave
## "everything spawns now" behavior for callers that don't yet integrate
## with WaveController.
static func apply_to(grid: HexGrid, registry: ActorRegistry, level: LevelData,
		actors_node: Node = null, skip_enemies: bool = false) -> Actor:
	if grid == null:
		GameLogger.error("LevelLoader", "apply_to: grid is null")
		return null
	if registry == null:
		GameLogger.error("LevelLoader", "apply_to: registry is null")
		return null
	if level == null:
		GameLogger.error("LevelLoader", "apply_to: level is null")
		return null

	# 1. Tile objects — written through HexGrid setter so HexTile.object_id
	# is updated for pathfinder + resolver consumers.
	for entry in level.objects:
		var coord: Vector2i = entry.get("coord", Vector2i(-1, -1))
		var obj_id: StringName = entry.get("object_id", &"")
		if obj_id == &"":
			continue
		grid.set_tile_object_id(coord, obj_id)

	# 2. Rebuild pathfinder once — accounts for blocks_movement objects.
	grid.rebuild_pathfinder()

	# 3. Spawners — actors_node defaults to the same convention godmode uses.
	if actors_node == null:
		actors_node = grid.get_node_or_null("Actors")
	if actors_node == null:
		actors_node = grid

	var player: Actor = null
	var enemy_idx: int = 1
	for spawner in level.spawners:
		var coord: Vector2i = spawner.get("coord", Vector2i(-1, -1))
		var kind: StringName = spawner.get("kind", &"")
		var ref: StringName = spawner.get("ref", &"")
		match kind:
			&"player":
				if player != null:
					GameLogger.warn("LevelLoader", "Duplicate player spawner — keeping first")
					continue
				player = _spawn_player(grid, registry, actors_node, coord)
			&"enemy":
				if skip_enemies:
					continue  # 024: WaveController handles enemy spawners
				_spawn_enemy(grid, registry, actors_node, coord, ref, enemy_idx)
				enemy_idx += 1
			_:
				GameLogger.warn("LevelLoader", "Unknown spawner kind: %s" % kind)

	GameLogger.info("LevelLoader", "Applied '%s': %d objects / %d spawners (skip_enemies=%s)" % [
		level.name, level.objects.size(), level.spawners.size(), skip_enemies
	])
	return player


## Public spawn helper used by 024-wave-editor's WaveController to instantiate
## an enemy from a spawner dict at countdown=0. Mirrors the private path used
## by apply_to — same id pattern, same registry registration, same place_actor
## semantics. Returns the spawned Actor (or null on failure).
static func spawn_enemy_at(grid: HexGrid, registry: ActorRegistry,
		actors_node: Node, coord: Vector2i, enemy_id: StringName,
		idx_for_id: int) -> Actor:
	if not ENEMY_SCENES.has(enemy_id):
		GameLogger.warn("LevelLoader", "spawn_enemy_at: unknown enemy_id '%s' at %s" % [enemy_id, coord])
		return null
	var scene: PackedScene = ENEMY_SCENES[enemy_id]
	var enemy: Actor = scene.instantiate() as Actor
	if enemy == null:
		GameLogger.warn("LevelLoader", "spawn_enemy_at: scene for %s did not instantiate as Actor" % enemy_id)
		return null
	enemy.actor_id = StringName("%s_%03d" % [enemy_id, idx_for_id])
	enemy.position = grid.tile_map_layer.map_to_local(coord)
	actors_node.add_child(enemy)
	if not grid.place_actor(enemy.actor_id, coord):
		GameLogger.warn("LevelLoader", "spawn_enemy_at: place_actor failed for %s at %s" % [enemy.actor_id, coord])
		enemy.queue_free()
		return null
	registry.register(enemy)
	return enemy


# ── Internal ────────────────────────────────────────────────────────────────

static func _spawn_player(grid: HexGrid, registry: ActorRegistry,
		actors_node: Node, coord: Vector2i) -> Actor:
	# Prefer a player Actor that's already in the scene tree (godmode.tscn
	# instances one at edit time). Fall back to a fresh prefab.
	var player: Actor = grid.get_node_or_null("Actors/Player") as Actor
	if player == null:
		player = PLAYER_SCENE.instantiate() as Actor
		actors_node.add_child(player)
	player.actor_id = PLAYER_ID
	player.team = &"player"
	if not grid.place_actor(PLAYER_ID, coord):
		GameLogger.error("LevelLoader", "Failed to place player at %s" % coord)
		return null
	player.position = grid.tile_map_layer.map_to_local(coord)
	registry.register(player)
	GameLogger.info("LevelLoader", "Player spawned at %s" % coord)
	return player


static func _spawn_enemy(grid: HexGrid, registry: ActorRegistry,
		actors_node: Node, coord: Vector2i, enemy_id: StringName, idx: int) -> void:
	if not ENEMY_SCENES.has(enemy_id):
		GameLogger.warn("LevelLoader", "Unknown enemy_id '%s' — skipping spawner at %s" % [enemy_id, coord])
		return
	var scene: PackedScene = ENEMY_SCENES[enemy_id]
	var enemy: Actor = scene.instantiate() as Actor
	if enemy == null:
		GameLogger.warn("LevelLoader", "Scene for %s did not instantiate as Actor" % enemy_id)
		return
	# id pattern follows godmode's _spawn_manekin convention.
	enemy.actor_id = StringName("%s_%03d" % [enemy_id, idx])
	enemy.position = grid.tile_map_layer.map_to_local(coord)
	actors_node.add_child(enemy)
	if not grid.place_actor(enemy.actor_id, coord):
		GameLogger.warn("LevelLoader", "Failed to place enemy %s at %s" % [enemy.actor_id, coord])
		enemy.queue_free()
		return
	registry.register(enemy)
