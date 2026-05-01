class_name LevelData

## Pure data container for a hand-authored map. Serialized 1:1 to JSON via
## LevelSerializer. Built up by the map editor (020) and consumed by
## LevelLoader → HexGrid + ActorRegistry at scene start.
##
## No node ops, no signals — this is a value object.

const SCHEMA_VERSION: int = 1

# Defaults match godmode_terrain.tres (single grass tile, source 0 atlas (0,0)).
const DEFAULT_TILESET_PATH: String = "res://scenes/dev/godmode_terrain.tres"

var name: String = "Untitled"
var version: int = SCHEMA_VERSION
var tileset_path: String = DEFAULT_TILESET_PATH

# Floor entries: {"coord": Vector2i, "source_id": int, "atlas_coord": Vector2i}
var floor_cells: Array[Dictionary] = []

# Object entries: {"coord": Vector2i, "object_id": StringName}
var objects: Array[Dictionary] = []

# Spawner entries: {"coord": Vector2i, "kind": StringName, "ref": StringName}
# kind ∈ {&"player", &"enemy"}. For player, ref is &"". For enemy, ref = enemy_id.
var spawners: Array[Dictionary] = []


## Returns array of error messages. Empty array means valid.
## Hard errors block save/load. Soft issues (out-of-floor objects) drop the
## entry on apply but are flagged here for user feedback.
func validate() -> Array[String]:
	var errors: Array[String] = []
	var floor_set: Dictionary = {}
	for f in floor_cells:
		floor_set[f.get("coord", Vector2i(-1, -1))] = true

	var occupancy: Dictionary = {}  # coord → "object" | "spawner"
	for o in objects:
		var c: Vector2i = o.get("coord", Vector2i(-1, -1))
		if not floor_set.has(c):
			errors.append("Object %s on unpainted tile %s" % [o.get("object_id", &""), c])
		if occupancy.has(c):
			errors.append("Tile %s already occupied" % c)
		occupancy[c] = "object"

	var player_count: int = 0
	for s in spawners:
		var c: Vector2i = s.get("coord", Vector2i(-1, -1))
		if not floor_set.has(c):
			errors.append("Spawner %s on unpainted tile %s" % [s.get("kind", &""), c])
		if occupancy.has(c):
			errors.append("Tile %s already occupied" % c)
		occupancy[c] = "spawner"
		if s.get("kind", &"") == &"player":
			player_count += 1

	if player_count == 0:
		errors.append("No player spawner — set Player Spawn before saving")
	elif player_count > 1:
		errors.append("Multiple player spawners (%d) — only one allowed" % player_count)
	return errors


## Serialize to JSON-friendly dict. Vector2i → [x, y] arrays.
func to_dict() -> Dictionary:
	return {
		"name": name,
		"version": version,
		"tileset_path": tileset_path,
		"floor": floor_cells.map(func(f: Dictionary) -> Dictionary:
			return {
				"coord": _v2i_to_arr(f.get("coord", Vector2i.ZERO)),
				"source_id": int(f.get("source_id", 0)),
				"atlas_coord": _v2i_to_arr(f.get("atlas_coord", Vector2i.ZERO)),
			}),
		"objects": objects.map(func(o: Dictionary) -> Dictionary:
			return {
				"coord": _v2i_to_arr(o.get("coord", Vector2i.ZERO)),
				"object_id": String(o.get("object_id", &"")),
			}),
		"spawners": spawners.map(func(s: Dictionary) -> Dictionary:
			return {
				"coord": _v2i_to_arr(s.get("coord", Vector2i.ZERO)),
				"kind": String(s.get("kind", &"")),
				"ref": String(s.get("ref", &"")),
			}),
	}


## Parse from JSON-decoded dict. Returns null if d is malformed at the top level.
## Soft-malformed entries (missing fields, wrong types) are dropped with warnings.
static func from_dict(d: Dictionary) -> LevelData:
	if d == null or typeof(d) != TYPE_DICTIONARY:
		return null
	var lvl := LevelData.new()
	lvl.name = String(d.get("name", "Untitled"))
	lvl.version = int(d.get("version", SCHEMA_VERSION))
	lvl.tileset_path = String(d.get("tileset_path", DEFAULT_TILESET_PATH))

	var floor_raw: Variant = d.get("floor", [])
	if floor_raw is Array:
		for entry in floor_raw:
			if entry is Dictionary:
				var coord_v := _arr_to_v2i(entry.get("coord", [0, 0]))
				lvl.floor_cells.append({
					"coord": coord_v,
					"source_id": int(entry.get("source_id", 0)),
					"atlas_coord": _arr_to_v2i(entry.get("atlas_coord", [0, 0])),
				})

	var objects_raw: Variant = d.get("objects", [])
	if objects_raw is Array:
		for entry in objects_raw:
			if entry is Dictionary:
				lvl.objects.append({
					"coord": _arr_to_v2i(entry.get("coord", [0, 0])),
					"object_id": StringName(entry.get("object_id", "")),
				})

	var spawners_raw: Variant = d.get("spawners", [])
	if spawners_raw is Array:
		for entry in spawners_raw:
			if entry is Dictionary:
				lvl.spawners.append({
					"coord": _arr_to_v2i(entry.get("coord", [0, 0])),
					"kind": StringName(entry.get("kind", "")),
					"ref": StringName(entry.get("ref", "")),
				})

	return lvl


# ── Internal helpers ────────────────────────────────────────────────────────

static func _v2i_to_arr(v: Vector2i) -> Array:
	return [v.x, v.y]


static func _arr_to_v2i(a: Variant) -> Vector2i:
	if a is Array and a.size() >= 2:
		return Vector2i(int(a[0]), int(a[1]))
	return Vector2i.ZERO
