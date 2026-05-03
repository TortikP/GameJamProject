class_name WaveController
extends Node

## WaveController — drives a multi-wave level at runtime.
##
## Owned by the battle scene (godmode.tscn for now). Lifecycle:
##
##   1. Battle scene loads a LevelData (via LevelLoader.apply_to with
##      skip_enemies=true) which spawns the player and paints wave-0 floor.
##   2. Scene calls wave_controller.start_level(level).
##   3. WaveController applies wave 0's enemy placeholders and starts the
##      countdown, emits wave_started(0, …).
##   4. Each EventBus.world_turn_ended → decrement pending timers → spawn
##      any that hit 0 → check turns_to_next → advance wave when reached.
##   5. Each EventBus.actor_died → call_deferred check-auto-clear: if no
##      living enemies AND no pending placeholders, credit unused turns to
##      RunScore, emit wave_cleared, advance.
##   6. Advancing past the last wave emits level_completed(RunScore.total)
##      and parks the controller.
##
## The controller does NOT touch the player Actor. The player is permanent
## across all waves (placed by LevelLoader before start_level).
##
## NO-OP mode: if start_level is never called (procedural godmode sandbox
## without a queued level), the controller stays inert — connected to the
## EventBus signals but with _level = null gating every handler.
##
## Architecture note: this lives under scripts/runtime/ which is a new
## bucket. It's "runtime engine glue" — sits above core (uses LevelData,
## HexGrid, EventBus) but below presentation (no UI references). It does
## instantiate a presentation scene (spawner_placeholder.tscn) which is a
## known compromise pattern in this codebase (CLAUDE.md §Accepted compromises).

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const SPAWNER_PLACEHOLDER_SCENE: PackedScene = preload("res://scenes/runtime/spawner_placeholder.tscn")


# ── External wiring (set via @export or assigned at scene load) ─────────────

@export var grid: HexGrid
@export var registry: ActorRegistry
# Where to mount placeholder + spawned actor nodes. Defaults to
# grid/Actors at start_level if unset (matches LevelLoader convention).
@export var actors_node_path: NodePath


# ── Internal state ──────────────────────────────────────────────────────────

var _level: LevelData = null
var _current_wave_index: int = -1   # -1 = not started
var _turns_into_wave: int = 0

# Pending enemy spawners with countdown — copies of waves[idx].spawners
# (kind=enemy only). Each entry: {coord, ref, timer, placeholder}. timer
# decrements each world_turn_ended; placeholder is the SpawnerPlaceholder
# node visualizing the wait.
var _pending_spawners: Array[Dictionary] = []

# Auto-incremented per-spawn id suffix so multiple manekins from different
# waves don't collide in the actor registry. Mirrors LevelLoader's
# enemy_idx but spans the whole level lifetime.
var _enemy_id_counter: int = 1

var _actors_node: Node = null
var _check_clear_queued: bool = false  # debounce repeated _check_auto_clear

# 024 / T53e — wave transition input lock. Set true at the start of
# _advance_wave's snapshot apply; cleared after wave_transition_sec via
# GameSpeed.wait. Owners (godmode_controller) gate _unhandled_input on
# is_transitioning() so player can't act mid-snapshot.
var _is_transitioning: bool = false


# ── Setup / lifecycle ───────────────────────────────────────────────────────

func _ready() -> void:
	# Subscribe even if start_level isn't called — handlers no-op when
	# _level is null. This way scenes that don't use waves don't pay any
	# cost beyond an empty function call.
	EventBus.world_turn_ended.connect(_on_world_turn_ended)
	EventBus.actor_died.connect(_on_actor_died)


## Begin running a level. Wave 0 applies immediately (placeholder spawn +
## emit wave_started). Player must already be on the grid (LevelLoader's
## responsibility — see class docstring step 1).
##
## start_level is idempotent on the same level only at boot — calling it a
## second time mid-run resets the controller to wave 0, which is almost
## certainly a bug. Caller-side responsibility.
func start_level(level: LevelData) -> void:
	if level == null:
		GameLogger.warn("WaveController", "start_level called with null level")
		return
	_level = level
	_current_wave_index = -1
	_turns_into_wave = 0
	_resolve_actors_node()
	# 039: signal that the battle is now beginning (Director connects handlers).
	EventBus.battle_started.emit(StringName(level.name))
	_advance_wave()


# ── Wave transitions ────────────────────────────────────────────────────────

func _advance_wave() -> void:
	if _level == null:
		return
	# Discard any placeholders from the wave we're leaving — their wave
	# closed without them.
	_clear_pending_spawners()

	var prev: int = _current_wave_index
	_current_wave_index += 1
	if _current_wave_index >= _level.waves.size():
		# Past the last wave — level complete.
		_current_wave_index = prev   # park; do not roll over
		GameLogger.info("WaveController", "level_completed (score=%d)" % RunScore.total)
		EventBus.level_completed.emit(RunScore.total)
		EventBus.battle_ended.emit(true)  # 039: clean teardown for Director
		return

	# T53e — gate input across the snapshot apply + visual settle window.
	# Owners (godmode_controller) read is_transitioning() in their input
	# handlers to drop player events during this period.
	_is_transitioning = true
	# 039: synthesized event — fires BEFORE snapshot so triggers can react
	# to "wave N is about to begin" while the previous wave content is still live.
	if _current_wave_index > 0:
		EventBus.wave_about_to_start.emit(_current_wave_index)
	_apply_wave_snapshot(_current_wave_index)
	_turns_into_wave = 0
	var w: Dictionary = _level.waves[_current_wave_index]
	GameLogger.info("WaveController", "wave_started %d (special=%s, ttn=%d)" % [
		_current_wave_index, bool(w.get("is_special", false)),
		int(w.get("turns_to_next", 0))
	])
	EventBus.wave_started.emit(_current_wave_index, bool(w.get("is_special", false)))
	# Settle window — visuals tween, placeholders pop in. Clears the lock
	# automatically. Spec AC-W16: GameSpeed.wait("battle", "wave_transition_sec").
	_release_transition_lock_after_delay()


## Returns true while a wave snapshot is being applied + the settle window
## hasn't elapsed. Owners use this to gate player input.
func is_transitioning() -> bool:
	return _is_transitioning


func _release_transition_lock_after_delay() -> void:
	# Plain SceneTreeTimer here is intentional: GameSpeed.wait() awaits
	# inside the calling function which would force _advance_wave to be
	# async (and thus every of its many sync callers — _on_actor_died
	# deferred, _on_world_turn_ended). Using a one-shot timer keeps
	# _advance_wave synchronous while still honouring the GameSpeed
	# config key (we read the value via get_value, not wait()).
	var dur: float = float(GameSpeed.get_value("battle", "wave_transition_sec", 0.15))
	if dur <= 0.0:
		_is_transitioning = false
		return
	var timer: SceneTreeTimer = get_tree().create_timer(dur)
	timer.timeout.connect(func() -> void: _is_transitioning = false)


## Apply waves[idx]'s snapshot (floor + objects + spawners) to the live
## scene. For wave 0 this is mostly a no-op on floor/objects (godmode
## controller already painted them from the loaded LevelData) — only enemy
## placeholders are instantiated.
##
## For wave N>0:
##   1. Floor diff: erase missing tiles + push-out residents, set new tiles.
##   2. Object diff: remove gone objects, add new objects, push-out residents
##      who landed on a newly-impassable hex.
##   3. Build placeholders for the wave's enemy spawners, copy into pending.
func _apply_wave_snapshot(idx: int) -> void:
	if grid == null or _level == null:
		return
	if idx < 0 or idx >= _level.waves.size():
		return
	var new_wave: Dictionary = _level.waves[idx]
	var prev_wave: Dictionary = _level.waves[idx - 1] if idx > 0 else {}

	if idx > 0:
		_apply_floor_diff(prev_wave.get("floor", []), new_wave.get("floor", []))
		_apply_object_diff(prev_wave.get("objects", []), new_wave.get("objects", []))

	_install_pending_spawners(new_wave.get("spawners", []))

	# Visual settle pause — one frame is enough for tweens to start, full
	# transition delay handled by GameSpeed.wave_transition_sec on the
	# scene-controller side. We don't await here (called from sync paths).


# ── Floor diff ──────────────────────────────────────────────────────────────

func _apply_floor_diff(prev_floor: Array, new_floor: Array) -> void:
	# Build coord sets for fast lookup.
	var prev_coords: Dictionary = {}
	for f in prev_floor:
		prev_coords[f.get("coord", Vector2i(-1, -1))] = f
	var new_coords: Dictionary = {}
	for f in new_floor:
		new_coords[f.get("coord", Vector2i(-1, -1))] = f

	# Erased cells: in prev, not in new. Push-out residents, then erase.
	# Cells about to be erased must be excluded from displacement targets —
	# otherwise we could push actor X to cell Y, then erase Y next iteration
	# and leave X on a non-existent floor.
	var to_erase: Array[Vector2i] = []
	for c in prev_coords:
		if not new_coords.has(c):
			to_erase.append(c)
	# Build exclusion list for the BFS: every coord we're about to erase.
	var exclude: Array = []
	for c in to_erase:
		exclude.append(c)
	for c in to_erase:
		var occupant_id: StringName = grid.get_actor_at(c)
		if occupant_id != &"":
			var occupant: Actor = _resolve_actor(occupant_id)
			if occupant != null:
				grid.displace_actor(occupant, exclude)
		# Erase visually + logically. HexGrid._tiles still has the entry
		# until reinitialize_tiles_only is called below — for now, erase
		# the tilemap cell so the next BFS sees it as missing.
		grid.tile_map_layer.erase_cell(c)

	# Added/changed cells: in new (regardless of prev). Set the cell.
	for c in new_coords:
		var entry: Dictionary = new_coords[c]
		grid.tile_map_layer.set_cell(c,
			int(entry.get("source_id", 0)),
			entry.get("atlas_coord", Vector2i.ZERO))

	# Re-init grid so HexTile dictionary picks up new cells / loses erased
	# ones. reinitialize_tiles_only preserves TileObject + TileEffect
	# registries so 019's TileObjectResolver keeps its bindings intact.
	grid.reinitialize_tiles_only()


# ── Object diff ─────────────────────────────────────────────────────────────

func _apply_object_diff(prev_objs: Array, new_objs: Array) -> void:
	var prev_at: Dictionary = {}
	for o in prev_objs:
		prev_at[o.get("coord", Vector2i(-1, -1))] = StringName(o.get("object_id", &""))
	var new_at: Dictionary = {}
	for o in new_objs:
		new_at[o.get("coord", Vector2i(-1, -1))] = StringName(o.get("object_id", &""))

	var overlay: Node = grid.get_node_or_null("ObjectsOverlay")

	# Phase 1: remove objects that are gone or being replaced.
	for c in prev_at:
		var prev_id: StringName = prev_at[c]
		var new_id: StringName = new_at.get(c, &"")
		if new_id != prev_id:
			grid.set_tile_object_id(c, &"")
			if overlay != null and overlay.has_method("clear_object"):
				overlay.clear_object(c)

	# Phase 2: install all new objects (sets blocks_movement flags). Doing
	# this before push-out makes the passability map current — the BFS will
	# correctly skip every newly-blocking cell as a target.
	var newly_blocking: Array = []
	var reg: TileObjectRegistry = grid.get_object_registry()
	for c in new_at:
		var new_id: StringName = new_at[c]
		if new_id == &"":
			continue
		grid.set_tile_object_id(c, new_id)
		if reg != null:
			var obj_def: TileObject = reg.get_object(new_id)
			if obj_def != null and obj_def.blocks_movement:
				newly_blocking.append(c)
		if overlay != null and overlay.has_method("set_object"):
			overlay.set_object(c, new_id)

	# Phase 3: push out any actor on a newly-blocking hex. Pass the full
	# blocking set as exclude so chain-push doesn't try to land on a
	# different new-wall cell.
	for c in newly_blocking:
		var occupant_id: StringName = grid.get_actor_at(c)
		if occupant_id != &"":
			var occupant: Actor = _resolve_actor(occupant_id)
			if occupant != null:
				grid.displace_actor(occupant, newly_blocking)

	grid.rebuild_pathfinder()


# ── Pending spawners ────────────────────────────────────────────────────────

func _install_pending_spawners(wave_spawners: Array) -> void:
	for s in wave_spawners:
		var kind: StringName = s.get("kind", &"")
		if kind == &"player":
			continue  # player is permanent — installed by LevelLoader
		if kind != &"enemy":
			continue  # forward-compat: unknown kinds ignored
		var coord: Vector2i = s.get("coord", Vector2i(-1, -1))
		var ref: StringName = s.get("ref", &"")
		var t: int = int(s.get("timer", 1))
		var placeholder := SPAWNER_PLACEHOLDER_SCENE.instantiate() as SpawnerPlaceholder
		if placeholder == null:
			GameLogger.warn("WaveController", "Failed to instantiate SpawnerPlaceholder")
			continue
		placeholder.bind(kind, ref, coord, t)
		placeholder.position = grid.tile_map_layer.map_to_local(coord)
		_actors_node.add_child(placeholder)
		_pending_spawners.append({
			"coord": coord,
			"ref": ref,
			"timer": t,
			"placeholder": placeholder,
		})


func _clear_pending_spawners() -> void:
	for entry in _pending_spawners:
		var ph: Node = entry.get("placeholder", null)
		if ph != null and is_instance_valid(ph):
			ph.queue_free()
	_pending_spawners.clear()


# ── World-turn handling ─────────────────────────────────────────────────────

func _on_world_turn_ended(_turn: int) -> void:
	if _level == null or _current_wave_index < 0:
		return
	_turns_into_wave += 1

	# Decrement timers + spawn anything that hit 0. Iterate over a copy so
	# we can mutate _pending_spawners safely.
	var fired: Array[Dictionary] = []
	for entry in _pending_spawners:
		var t: int = int(entry.get("timer", 1)) - 1
		entry["timer"] = t
		var ph: SpawnerPlaceholder = entry.get("placeholder", null)
		if ph != null and is_instance_valid(ph):
			ph.set_timer(t)
		if t <= 0:
			fired.append(entry)

	for entry in fired:
		_spawn_from_pending(entry)

	# Check turns_to_next for natural wave end. If auto-clear hasn't
	# already advanced earlier (via _check_auto_clear), this fires the
	# transition.
	if _current_wave_index < _level.waves.size():
		var w: Dictionary = _level.waves[_current_wave_index]
		var ttn: int = int(w.get("turns_to_next", 0))
		if ttn > 0 and _turns_into_wave >= ttn:
			_advance_wave()


func _spawn_from_pending(entry: Dictionary) -> void:
	var coord: Vector2i = entry.get("coord", Vector2i(-1, -1))
	var ref: StringName = entry.get("ref", &"")
	var ph: SpawnerPlaceholder = entry.get("placeholder", null)
	# Remove placeholder visual first so the spawned actor isn't drawn over
	# a ghost on the same hex.
	if ph != null and is_instance_valid(ph):
		ph.queue_free()
	# Free the cell on the grid (placeholder didn't occupy it logically,
	# but defensive: if HexGrid ever starts treating placeholders as
	# occupants we want to clear here).
	# Spawn the actor.
	var spawned: Actor = LevelLoader.spawn_enemy_at(grid, registry, _actors_node,
			coord, ref, _enemy_id_counter)
	_enemy_id_counter += 1
	if spawned != null:
		grid.registry_lookup[spawned.actor_id] = spawned
		EventBus.actor_spawned.emit(spawned.actor_id)
	# Remove from pending.
	_pending_spawners.erase(entry)


# ── Auto-clear ──────────────────────────────────────────────────────────────

func _on_actor_died(_actor_id: StringName) -> void:
	if _level == null or _current_wave_index < 0:
		return
	# Defer the check by one frame so all death-triggered cascades settle
	# (e.g. AOE killing two enemies in one resolve — we want one auto-clear,
	# not two).
	if _check_clear_queued:
		return
	_check_clear_queued = true
	_check_auto_clear.call_deferred()


func _check_auto_clear() -> void:
	_check_clear_queued = false
	if _level == null or _current_wave_index < 0:
		return
	if _current_wave_index >= _level.waves.size():
		return
	if not _pending_spawners.is_empty():
		return  # placeholders still ticking → wait for them to fire
	if _living_enemies_count() > 0:
		return
	# All clear. Credit unused turns to score and advance.
	var w: Dictionary = _level.waves[_current_wave_index]
	var ttn: int = int(w.get("turns_to_next", 0))
	var unused: int = max(0, ttn - _turns_into_wave)
	if unused > 0:
		RunScore.add(unused)
	GameLogger.info("WaveController", "wave_cleared %d (unused=%d)" % [_current_wave_index, unused])
	var cleared_idx: int = _current_wave_index
	EventBus.wave_cleared.emit(cleared_idx, unused)
	# 040: if this wave has a skill_offer, wait for SkillOfferController
	# to run the modal flow before advancing. SkillOfferController is an
	# autoload; it always emits skill_offer_closed exactly once when
	# wave_cleared fires on a wave that has the field — we rely on its
	# emit-guard for that contract. Without this await, _advance_wave
	# would apply the next wave's snapshot (clearing enemies, painting
	# floor) while the modal is still up — visually broken.
	if _has_skill_offer_for(cleared_idx):
		await EventBus.skill_offer_closed
	_advance_wave()


# 040: cheap local check so WaveController doesn't reach into the autoload
# to ask "do we have an offer for this wave". Reads the same field that
# SkillOfferController will read.
func _has_skill_offer_for(wave_index: int) -> bool:
	if _level == null:
		return false
	if wave_index < 0 or wave_index >= _level.waves.size():
		return false
	var w: Dictionary = _level.waves[wave_index]
	var so: Variant = w.get("skill_offer", null)
	return so != null and so is Dictionary


func _living_enemies_count() -> int:
	if registry == null:
		return 0
	var count: int = 0
	for actor in registry.all():
		if actor is Actor:
			var a: Actor = actor
			if a.team == &"enemy" and a.is_alive():
				count += 1
	return count


# ── Helpers ─────────────────────────────────────────────────────────────────

func _resolve_actors_node() -> void:
	if _actors_node != null:
		return
	if not actors_node_path.is_empty():
		_actors_node = get_node_or_null(actors_node_path)
	if _actors_node == null and grid != null:
		_actors_node = grid.get_node_or_null("Actors")
	if _actors_node == null and grid != null:
		_actors_node = grid


func _resolve_actor(id: StringName) -> Actor:
	if grid != null and grid.registry_lookup.has(id):
		return grid.registry_lookup[id]
	if registry != null:
		var found: Variant = registry.get_actor(id)
		if found is Actor:
			return found
	return null
