class_name LevelData

## Pure data container for a hand-authored map. Serialized 1:1 to JSON via
## LevelSerializer. Built up by the map editor (020/024) and consumed by
## LevelLoader → HexGrid + ActorRegistry at scene start.
##
## No node ops, no signals — this is a value object.
##
## ─── Wave model (024) ───────────────────────────────────────────────────────
## A level is a sequence of *waves*. Each wave is a full snapshot of the world
## at the start of that wave (floor + objects + spawners), plus `turns_to_next`
## (how many turns until auto-advance) and `is_special` (visual tag).
##
## In-memory state of LevelData mirrors the *active wave* in:
##   - `floor_cells`, `objects`, `spawners`  ← THIS WAVE only
## Plus the full sequence in:
##   - `waves: Array[Dictionary]`            ← ALL waves (incl. active)
##
## Editor switching active wave: call `set_active_wave_index(new_idx)`. This
## syncs current root fields → waves[old_idx], then waves[new_idx] → root.
##
## On to_dict(): root fields are first synced into waves[active] so the
## serialized form is canonical. JSON contains only `waves[]` plus top-level
## name/version/tileset_path. Legacy v1 files (root floor/objects/spawners) are
## migrated on from_dict() into a single-wave `waves = [wave0_from_root]`.
##
## Spawner schema gains a `timer: int >= 1` field — see 024 spec, section
## "Расширение LevelData". Legacy spawners default to timer=1 on migration.

const SCHEMA_VERSION: int = 2  # 024: bump from 1 (added waves[]).

# Defaults match hex_terrain.tres source 0 atlas (0,0) = grass tile (post-032
# tileset consolidation; godmode_terrain.tres deleted).
const DEFAULT_TILESET_PATH: String = "res://scenes/arena/tilesets/hex_terrain.tres"

# Per-wave defaults used when synthesizing new waves (e.g. legacy migration,
# editor "+ Wave"). DEFAULT_TURNS_TO_NEXT only applies to non-final waves.
const DEFAULT_TURNS_TO_NEXT: int = 5
const DEFAULT_SPAWNER_TIMER: int = 1

var name: String = "Untitled"
var version: int = SCHEMA_VERSION
var tileset_path: String = DEFAULT_TILESET_PATH

# Active-wave-view fields (legacy shape, used by the editor as a read/write
# scratchpad for `_active_wave_index`). On save these get folded back into
# waves[_active_wave_index] before serialization.
#
# Floor entries:    {"coord": Vector2i, "source_id": int, "atlas_coord": Vector2i}
# Object entries:   {"coord": Vector2i, "object_id": StringName}
# Spawner entries:  {"coord": Vector2i, "kind": StringName, "ref": StringName, "timer": int}
#   kind ∈ {&"player", &"enemy"}. For player, ref is &"". For enemy, ref = enemy_id.
var floor_cells: Array[Dictionary] = []
var objects: Array[Dictionary] = []
var spawners: Array[Dictionary] = []

# All waves in order. Each entry is a Dictionary with keys:
#   "index" (int), "is_special" (bool), "turns_to_next" (int),
#   "floor" (Array of floor-cell dicts),
#   "objects" (Array of object dicts),
#   "spawners" (Array of spawner dicts incl. "timer").
# Wave 0 = initial state. Last wave's turns_to_next must be 0.
# Defaults to a single empty wave so a freshly-constructed LevelData is valid
# under the new model without explicit init. Inline literal (not _make_empty_wave)
# to avoid a static-call-in-member-initializer parse edge case.
# 039-dialogue-triggers: per-level event→dialogue bindings. Each entry is a
# Dictionary matching DialogueTrigger schema. Stored as raw dicts (not
# DialogueTrigger objects) so LevelSerializer can round-trip JSON directly.
var dialogue_triggers: Array[Dictionary] = []

## 042: per-level procedural music config. Optional — empty dict → defaults.
## Schema: see data/maps/_schema.md §music_config and specs/042-proc-music/spec.md §3.
var music_config: Dictionary = {}

var waves: Array[Dictionary] = [{
	"index": 0,
	"is_special": false,
	"turns_to_next": 0,
	"floor": [],
	"objects": [],
	"spawners": [],
}]

# Which wave the root view fields (floor_cells/objects/spawners) currently
# represent. Editor mutates this via set_active_wave_index() to switch context.
var _active_wave_index: int = 0


# ── Wave navigation API ─────────────────────────────────────────────────────

func get_active_wave_index() -> int:
	return _active_wave_index


## Sync current root fields → waves[old], then load waves[new] → root.
## Idempotent if new_idx == _active_wave_index.
func set_active_wave_index(new_idx: int) -> void:
	if new_idx < 0 or new_idx >= waves.size():
		return
	if new_idx == _active_wave_index:
		return
	_sync_root_to_active_wave()
	_active_wave_index = new_idx
	_sync_active_wave_to_root()


## Push current root fields into waves[_active_wave_index]. Caller-side
## save/serialization helper. Idempotent.
func sync_root_to_active_wave() -> void:
	_sync_root_to_active_wave()


## Pull waves[_active_wave_index] into root fields. Caller-side load helper.
func sync_active_wave_to_root() -> void:
	_sync_active_wave_to_root()


## Sum of turns_to_next from waves[0..idx-1]. Used by WaveTimeline to position
## the runtime cursor and by editor for displaying absolute turn numbers.
func get_wave_start_turn(idx: int) -> int:
	var t: int = 0
	for i in range(mini(idx, waves.size())):
		t += int(waves[i].get("turns_to_next", 0))
	return t


# ── Validation ──────────────────────────────────────────────────────────────

## Returns array of error messages. Empty array means valid.
## Hard errors block save/load. Warnings are prefixed "WARN: " and don't
## block save but should be surfaced to the user.
func validate() -> Array[String]:
	var errors: Array[String] = []
	# Make sure root view is folded back into waves before validation — caller
	# may have made edits via root fields without an explicit sync.
	_sync_root_to_active_wave()

	if waves.is_empty():
		errors.append("Уровень не содержит ни одной волны")
		return errors

	# Contiguous index 0..N-1.
	for i in waves.size():
		var w: Dictionary = waves[i]
		var idx_v: int = int(w.get("index", -1))
		if idx_v != i:
			errors.append("Wave %d has index %d (expected %d)" % [i, idx_v, i])

	# turns_to_next: >= 1 for all but last; last == 0.
	for i in waves.size():
		var w: Dictionary = waves[i]
		var ttn: int = int(w.get("turns_to_next", 0))
		if i < waves.size() - 1:
			if ttn < 1:
				errors.append("Wave %d turns_to_next must be >= 1 (got %d)" % [i, ttn])
		else:
			if ttn != 0:
				errors.append("Last wave (%d) turns_to_next must be 0 (got %d)" % [i, ttn])

	# Per-wave content checks.
	var total_player_spawners: int = 0
	for i in waves.size():
		var w: Dictionary = waves[i]
		var floor_set: Dictionary = {}
		for f in w.get("floor", []):
			floor_set[f.get("coord", Vector2i(-1, -1))] = true

		var occupancy: Dictionary = {}  # coord → "object" | "spawner"
		for o in w.get("objects", []):
			var c: Vector2i = o.get("coord", Vector2i(-1, -1))
			if not floor_set.has(c):
				errors.append("Wave %d: object %s on unpainted tile %s" % [i, o.get("object_id", &""), c])
			if occupancy.has(c):
				errors.append("Wave %d: tile %s already occupied" % [i, c])
			occupancy[c] = "object"

		var ttn: int = int(w.get("turns_to_next", 0))
		for s in w.get("spawners", []):
			var c: Vector2i = s.get("coord", Vector2i(-1, -1))
			if not floor_set.has(c):
				errors.append("Wave %d: spawner %s on unpainted tile %s" % [i, s.get("kind", &""), c])
			if occupancy.has(c):
				errors.append("Wave %d: tile %s already occupied" % [i, c])
			occupancy[c] = "spawner"
			if s.get("kind", &"") == &"player":
				total_player_spawners += 1
			var timer_v: int = int(s.get("timer", DEFAULT_SPAWNER_TIMER))
			if timer_v < 1:
				errors.append("Wave %d: spawner timer must be >= 1 (got %d)" % [i, timer_v])
			# Soft warn: timer larger than turns_to_next means the spawner will
			# never fire in this wave's window. Not blocking — designers might
			# intentionally use this to defer a spawn that auto-clear will skip.
			if i < waves.size() - 1 and timer_v > ttn:
				errors.append("WARN: Wave %d: spawner timer (%d) > turns_to_next (%d) — won't trigger" % [i, timer_v, ttn])

	if total_player_spawners == 0:
		errors.append("No player spawner — set Player Spawn in some wave before saving")
	elif total_player_spawners > 1:
		errors.append("Multiple player spawners (%d) across waves — only one allowed total" % total_player_spawners)

	# 039: dialogue_triggers validation (AC-D3).
	var trigger_ids: Dictionary = {}
	for raw in dialogue_triggers:
		if not (raw is Dictionary):
			errors.append("dialogue_triggers entry is not a Dictionary")
			continue
		var t: DialogueTrigger = DialogueTrigger.from_dict(raw)
		var t_errs: Array[String] = t.validate()
		for e in t_errs:
			errors.append(e)
		if t.id != &"":
			if trigger_ids.has(t.id):
				errors.append("dialogue_triggers: duplicate id '%s'" % t.id)
			trigger_ids[t.id] = true
		if t.conditions.has("wave_index"):
			var wi: int = int(t.conditions["wave_index"])
			if wi < 0 or wi >= waves.size():
				errors.append("WARN: trigger '%s': wave_index %d out of range [0, %d)" % [t.id, wi, waves.size()])
		# Soft warn if dialogue_id not in DB (DB may not be loaded in editor context).
		if t.dialogue_id != &"" and Engine.has_singleton("DialogueDB"):
			# DialogueDB is an autoload node — can't call static, access via node.
			# Use has_method check to be safe.
			pass  # Actual check done in LevelDialogueDirector at runtime.

	# 042: music_config soft validation (warn-only, doesn't block save).
	if music_config.has("bpm"):
		var bpm: float = float(music_config["bpm"])
		if bpm < 40.0 or bpm > 200.0:
			errors.append("WARN: music_config.bpm %.1f out of [40, 200] — will be clamped" % bpm)

	return errors


# ── Serialization ───────────────────────────────────────────────────────────

## Serialize to JSON-friendly dict. Vector2i → [x, y] arrays. Always emits
## the wave-format (no root floor/objects/spawners). Legacy readers will get
## a graceful empty result on those keys; load path handles the conversion.
func to_dict() -> Dictionary:
	# Fold current editor edits back into waves[active] before serializing.
	_sync_root_to_active_wave()
	var waves_out: Array = []
	for i in waves.size():
		var w: Dictionary = waves[i]
		waves_out.append({
			"index": int(w.get("index", i)),
			"is_special": bool(w.get("is_special", false)),
			"turns_to_next": int(w.get("turns_to_next", 0)),
			"floor": _floor_to_arr(w.get("floor", [])),
			"objects": _objects_to_arr(w.get("objects", [])),
			"spawners": _spawners_to_arr(w.get("spawners", [])),
		})
	return {
		"name": name,
		"version": version,
		"tileset_path": tileset_path,
		"waves": waves_out,
		"dialogue_triggers": dialogue_triggers.duplicate(true),
		"music_config": music_config.duplicate(true),
	}


## Parse from JSON-decoded dict. Returns null if d is malformed at the top
## level. Soft-malformed entries (missing fields, wrong types) are dropped
## with warnings. v1 files (root floor/objects/spawners, no waves[]) are
## migrated to a single-wave shape transparently.
static func from_dict(d: Dictionary) -> LevelData:
	if d == null or typeof(d) != TYPE_DICTIONARY:
		return null
	var lvl := LevelData.new()
	lvl.name = String(d.get("name", "Untitled"))
	lvl.version = int(d.get("version", SCHEMA_VERSION))
	lvl.tileset_path = String(d.get("tileset_path", DEFAULT_TILESET_PATH))
	# 035 fix — pre-032 saves still reference the deleted godmode_terrain.tres.
	# Silently rewrite to the canonical tileset so old autosaves / playtest
	# scratch files don't fail to load (which would drop us into procedural
	# sandbox with no WaveController → no enemy spawning).
	if lvl.tileset_path == "res://scenes/dev/godmode_terrain.tres":
		lvl.tileset_path = DEFAULT_TILESET_PATH
	lvl.waves = []

	if d.has("waves") and d["waves"] is Array:
		for entry in d["waves"]:
			if entry is Dictionary:
				lvl.waves.append(_wave_dict_from_arr(entry))
	else:
		# Legacy v1: pack root floor/objects/spawners into a single wave[0].
		# turns_to_next=0 makes it the only/final wave — runtime fires
		# level_completed once auto-clear or default flow finishes it.
		lvl.waves.append({
			"index": 0,
			"is_special": false,
			"turns_to_next": 0,
			"floor": _floor_arr_to_dicts(d.get("floor", [])),
			"objects": _objects_arr_to_dicts(d.get("objects", [])),
			"spawners": _spawners_arr_to_dicts_with_default_timer(d.get("spawners", [])),
		})
		lvl.version = SCHEMA_VERSION  # silently bump — file on disk is legacy
	if lvl.waves.is_empty():
		# Defensive: empty waves list → synthesize an empty wave 0 so the
		# rest of the codebase can rely on waves.size() >= 1.
		lvl.waves.append(_make_empty_wave(0))
	# Reindex defensively (file may have non-contiguous indices; we trust order).
	for i in lvl.waves.size():
		lvl.waves[i]["index"] = i
	lvl._active_wave_index = 0
	lvl._sync_active_wave_to_root()
	# 039: dialogue_triggers — default empty for legacy files (AC-D2).
	if d.has("dialogue_triggers") and d["dialogue_triggers"] is Array:
		for entry in d["dialogue_triggers"]:
			if entry is Dictionary:
				lvl.dialogue_triggers.append(entry.duplicate())
	# 042: music_config — optional, default empty.
	if d.has("music_config") and d["music_config"] is Dictionary:
		lvl.music_config = (d["music_config"] as Dictionary).duplicate(true)
	return lvl


# ── Wave construction helpers ───────────────────────────────────────────────

## Returns a deep copy of waves[src_idx]'s floor + objects, with empty
## spawners. Used by editor's "Copy from previous wave" and "+ Wave" actions.
## Returns a freshly-constructed wave dict ready to be appended/inserted.
func make_wave_copy_no_spawners(src_idx: int, target_idx: int,
		turns_to_next: int = DEFAULT_TURNS_TO_NEXT) -> Dictionary:
	var src: Dictionary = waves[src_idx] if src_idx >= 0 and src_idx < waves.size() else _make_empty_wave(0)
	return {
		"index": target_idx,
		"is_special": false,
		"turns_to_next": turns_to_next,
		"floor": _deep_copy_floor(src.get("floor", [])),
		"objects": _deep_copy_objects(src.get("objects", [])),
		"spawners": [],
	}


## Snapshot the current root fields into a freshly-built wave dict (deep
## copy). Used by editor when constructing wave[0] from the initial canvas
## paint at startup, or when migrating root-only files.
func snapshot_root_as_wave(idx: int = 0, turns_to_next: int = 0,
		is_special: bool = false) -> Dictionary:
	return {
		"index": idx,
		"is_special": is_special,
		"turns_to_next": turns_to_next,
		"floor": _deep_copy_floor(floor_cells),
		"objects": _deep_copy_objects(objects),
		"spawners": _deep_copy_spawners(spawners),
	}


# ── Internal helpers ────────────────────────────────────────────────────────

func _sync_root_to_active_wave() -> void:
	if _active_wave_index < 0 or _active_wave_index >= waves.size():
		return
	var w: Dictionary = waves[_active_wave_index]
	# Deep-copy root → wave so subsequent edits don't alias.
	w["floor"] = _deep_copy_floor(floor_cells)
	w["objects"] = _deep_copy_objects(objects)
	w["spawners"] = _deep_copy_spawners(spawners)
	# Preserve wave-level metadata (index/is_special/turns_to_next) — editor
	# touches those via wave_panel signal handlers, not via root fields.
	waves[_active_wave_index] = w


func _sync_active_wave_to_root() -> void:
	if _active_wave_index < 0 or _active_wave_index >= waves.size():
		floor_cells = []
		objects = []
		spawners = []
		return
	var w: Dictionary = waves[_active_wave_index]
	floor_cells = _deep_copy_floor(w.get("floor", []))
	objects = _deep_copy_objects(w.get("objects", []))
	spawners = _deep_copy_spawners(w.get("spawners", []))


static func _make_empty_wave(idx: int) -> Dictionary:
	return {
		"index": idx,
		"is_special": false,
		"turns_to_next": 0,
		"floor": [],
		"objects": [],
		"spawners": [],
	}


# ── Deep copies (in-memory dict array → independent dict array) ─────────────
# Each element is a Dictionary; we re-create with primitive copies so callers
# can mutate without aliasing the source.

static func _deep_copy_floor(arr: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (arr is Array):
		return out
	for entry in arr:
		if entry is Dictionary:
			out.append({
				"coord": entry.get("coord", Vector2i.ZERO),
				"source_id": int(entry.get("source_id", 0)),
				"atlas_coord": entry.get("atlas_coord", Vector2i.ZERO),
			})
	return out


static func _deep_copy_objects(arr: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (arr is Array):
		return out
	for entry in arr:
		if entry is Dictionary:
			out.append({
				"coord": entry.get("coord", Vector2i.ZERO),
				"object_id": StringName(entry.get("object_id", &"")),
			})
	return out


static func _deep_copy_spawners(arr: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (arr is Array):
		return out
	for entry in arr:
		if entry is Dictionary:
			out.append({
				"coord": entry.get("coord", Vector2i.ZERO),
				"kind": StringName(entry.get("kind", &"")),
				"ref": StringName(entry.get("ref", &"")),
				"timer": int(entry.get("timer", DEFAULT_SPAWNER_TIMER)),
			})
	return out


# ── Wave dict → JSON array forms (Vector2i → [x,y]) ─────────────────────────

static func _floor_to_arr(arr: Variant) -> Array:
	var out: Array = []
	if not (arr is Array):
		return out
	for entry in arr:
		if entry is Dictionary:
			out.append({
				"coord": _v2i_to_arr(entry.get("coord", Vector2i.ZERO)),
				"source_id": int(entry.get("source_id", 0)),
				"atlas_coord": _v2i_to_arr(entry.get("atlas_coord", Vector2i.ZERO)),
			})
	return out


static func _objects_to_arr(arr: Variant) -> Array:
	var out: Array = []
	if not (arr is Array):
		return out
	for entry in arr:
		if entry is Dictionary:
			out.append({
				"coord": _v2i_to_arr(entry.get("coord", Vector2i.ZERO)),
				"object_id": String(entry.get("object_id", &"")),
			})
	return out


static func _spawners_to_arr(arr: Variant) -> Array:
	var out: Array = []
	if not (arr is Array):
		return out
	for entry in arr:
		if entry is Dictionary:
			out.append({
				"coord": _v2i_to_arr(entry.get("coord", Vector2i.ZERO)),
				"kind": String(entry.get("kind", &"")),
				"ref": String(entry.get("ref", &"")),
				"timer": int(entry.get("timer", DEFAULT_SPAWNER_TIMER)),
			})
	return out


# ── JSON array forms → in-memory dicts (Array → Vector2i, etc.) ─────────────

static func _wave_dict_from_arr(d: Dictionary) -> Dictionary:
	return {
		"index": int(d.get("index", 0)),
		"is_special": bool(d.get("is_special", false)),
		"turns_to_next": int(d.get("turns_to_next", 0)),
		"floor": _floor_arr_to_dicts(d.get("floor", [])),
		"objects": _objects_arr_to_dicts(d.get("objects", [])),
		"spawners": _spawners_arr_to_dicts_with_default_timer(d.get("spawners", [])),
	}


static func _floor_arr_to_dicts(arr: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (arr is Array):
		return out
	for entry in arr:
		if entry is Dictionary:
			out.append({
				"coord": _arr_to_v2i(entry.get("coord", [0, 0])),
				"source_id": int(entry.get("source_id", 0)),
				"atlas_coord": _arr_to_v2i(entry.get("atlas_coord", [0, 0])),
			})
	return out


static func _objects_arr_to_dicts(arr: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (arr is Array):
		return out
	for entry in arr:
		if entry is Dictionary:
			out.append({
				"coord": _arr_to_v2i(entry.get("coord", [0, 0])),
				"object_id": StringName(entry.get("object_id", "")),
			})
	return out


static func _spawners_arr_to_dicts_with_default_timer(arr: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (arr is Array):
		return out
	for entry in arr:
		if entry is Dictionary:
			out.append({
				"coord": _arr_to_v2i(entry.get("coord", [0, 0])),
				"kind": StringName(entry.get("kind", "")),
				"ref": StringName(entry.get("ref", "")),
				"timer": int(entry.get("timer", DEFAULT_SPAWNER_TIMER)),
			})
	return out


static func _v2i_to_arr(v: Variant) -> Array:
	if v is Vector2i:
		return [v.x, v.y]
	if v is Vector2:
		return [int(v.x), int(v.y)]
	if v is Array and v.size() >= 2:
		return [int(v[0]), int(v[1])]
	return [0, 0]


static func _arr_to_v2i(a: Variant) -> Vector2i:
	if a is Vector2i:
		return a
	if a is Array and a.size() >= 2:
		return Vector2i(int(a[0]), int(a[1]))
	return Vector2i.ZERO
