class_name TileObjectRegistry

## Loads tile object definitions from data/tile_objects/*.json at startup.
## Pattern mirrors TileEffectRegistry — load_from_dir / get / has.
## Adds AC-O2 validation: level rules, force-correct blocks_* and triggers,
## force-empty linger for non-SMALL-walkable, warn on inconsistent JSON.
##
## Usage:
##   var reg := TileObjectRegistry.new()
##   reg.load_from_dir("res://data/tile_objects/")
##   var obj := reg.get(tile.object_id)   # returns shared empty TileObject if unknown

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const _LEVEL_LARGE := -1
const _LEVEL_SMALL := 0
const _LEVEL_ELEVATION := 1

var _objects: Dictionary = {}             # StringName -> TileObject
var _empty: TileObject = TileObject.new({})  # shared sentinel for unknown ids


func load_from_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		GameLogger.warn("TileObjectRegistry", "Cannot open dir: %s" % dir_path)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			_load_file(dir_path.path_join(fname))
		fname = dir.get_next()
	dir.list_dir_end()
	GameLogger.info("TileObjectRegistry", "Loaded %d tile objects" % _objects.size())


func get_object(id: StringName) -> TileObject:
	return _objects.get(id, _empty)


func has_object(id: StringName) -> bool:
	return _objects.has(id)


## 020 — enumeration API for the map editor's object palette. Returns all
## loaded object ids in registry order. Additive, read-only.
func get_all_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for id: Variant in _objects:
		result.append(id)
	return result


# ── Internal ─────────────────────────────────────────────────────────────────

func _load_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		GameLogger.warn("TileObjectRegistry", "Cannot read: %s" % path)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		GameLogger.warn("TileObjectRegistry", "JSON parse error in %s: %s" % [path, json.get_error_message()])
		return
	var raw: Variant = json.get_data()
	if typeof(raw) != TYPE_DICTIONARY:
		GameLogger.warn("TileObjectRegistry", "Top-level JSON must be object in %s" % path)
		return
	var data: Dictionary = _validate_and_normalize(raw, path)
	if data.is_empty():
		return  # validator already warned, skip silently here
	var obj := TileObject.new(data)
	if _objects.has(obj.id):
		GameLogger.warn("TileObjectRegistry", "%s: duplicate id '%s' — overwriting" % [path, obj.id])
	_objects[obj.id] = obj


## AC-O2 validation. Returns normalised dict ready for TileObject._init,
## or empty {} if the entry must be skipped. Warnings are logged for any
## auto-correction so designers see why their JSON was modified.
func _validate_and_normalize(raw: Dictionary, path: String) -> Dictionary:
	# id required
	var id_raw: Variant = raw.get("id", "")
	if typeof(id_raw) != TYPE_STRING or String(id_raw) == "":
		GameLogger.warn("TileObjectRegistry", "%s: missing or non-string 'id' — skipping" % path)
		return {}
	var id_str: String = String(id_raw)

	# level required and ∈ {-1, 0, 1}
	if not raw.has("level"):
		GameLogger.warn("TileObjectRegistry", "%s (%s): missing 'level' — skipping" % [path, id_str])
		return {}
	var level: int = int(raw["level"])
	if level != _LEVEL_LARGE and level != _LEVEL_SMALL and level != _LEVEL_ELEVATION:
		GameLogger.warn("TileObjectRegistry", "%s (%s): invalid level %d — must be -1/0/1, skipping" % [path, id_str, level])
		return {}

	var data: Dictionary = raw.duplicate(true)
	data["level"] = level

	# Force blocks_movement / blocks_abilities_through per level
	# LARGE / ELEVATION → both true regardless of JSON
	# SMALL → blocks_movement honoured from JSON; blocks_abilities_through always false
	var bm_in_json: bool = bool(data.get("blocks_movement", false))
	var bat_in_json: bool = bool(data.get("blocks_abilities_through", false))
	if level == _LEVEL_LARGE or level == _LEVEL_ELEVATION:
		if not bm_in_json:
			GameLogger.warn("TileObjectRegistry", "%s (%s): level=%d forces blocks_movement=true (was %s)" % [path, id_str, level, bm_in_json])
		if not bat_in_json:
			# Note: not warning when JSON omits the field entirely — it's expected per schema doc.
			pass
		data["blocks_movement"] = true
		data["blocks_abilities_through"] = true
	else:
		# SMALL — honour blocks_movement; force blocks_abilities_through false
		data["blocks_movement"] = bm_in_json
		if bat_in_json:
			GameLogger.warn("TileObjectRegistry", "%s (%s): SMALL objects cannot block abilities through — forcing false" % [path, id_str])
		data["blocks_abilities_through"] = false

	# ELEVATION: all behavior triggers zeroed (it's terrain, not interactive)
	if level == _LEVEL_ELEVATION:
		var had_behavior: bool = (
			String(data.get("behavior_effect_id", "")) != ""
			or bool(data.get("applies_on_enter", false))
			or bool(data.get("applies_on_turn_end", false))
			or int(data.get("aura_radius", 0)) > 0
			or bool(data.get("applies_on_attacked", false))
		)
		if had_behavior:
			GameLogger.warn("TileObjectRegistry", "%s (%s): ELEVATION cannot have behavior — zeroing triggers" % [path, id_str])
		data["behavior_effect_id"] = ""
		data["applies_on_enter"] = false
		data["applies_on_turn_end"] = false
		data["aura_radius"] = 0
		data["applies_on_attacked"] = false

	# LARGE: enter/turn_end forbidden (cannot stand on it). Aura + on_attacked allowed.
	if level == _LEVEL_LARGE:
		if bool(data.get("applies_on_enter", false)) or bool(data.get("applies_on_turn_end", false)):
			GameLogger.warn("TileObjectRegistry", "%s (%s): LARGE forbids on_enter/on_turn_end — forcing false" % [path, id_str])
		data["applies_on_enter"] = false
		data["applies_on_turn_end"] = false

	# SMALL non-walkable: same as LARGE — actor cannot step on it
	if level == _LEVEL_SMALL and bool(data.get("blocks_movement", false)):
		if bool(data.get("applies_on_enter", false)) or bool(data.get("applies_on_turn_end", false)):
			GameLogger.warn("TileObjectRegistry", "%s (%s): SMALL non-walkable forbids on_enter/on_turn_end — forcing false" % [path, id_str])
		data["applies_on_enter"] = false
		data["applies_on_turn_end"] = false

	# Trigger flags require a behavior_effect_id — otherwise zero them
	var beid: String = String(data.get("behavior_effect_id", ""))
	var any_trigger: bool = (
		bool(data.get("applies_on_enter", false))
		or bool(data.get("applies_on_turn_end", false))
		or int(data.get("aura_radius", 0)) > 0
		or bool(data.get("applies_on_attacked", false))
	)
	if beid == "" and any_trigger:
		GameLogger.warn("TileObjectRegistry", "%s (%s): triggers enabled without behavior_effect_id — zeroing" % [path, id_str])
		data["applies_on_enter"] = false
		data["applies_on_turn_end"] = false
		data["aura_radius"] = 0
		data["applies_on_attacked"] = false

	# Linger only for SMALL walkable
	var linger: String = String(data.get("linger_effect_id", ""))
	if linger != "":
		var is_small_walkable: bool = (level == _LEVEL_SMALL) and (not bool(data.get("blocks_movement", false)))
		if not is_small_walkable:
			GameLogger.warn("TileObjectRegistry", "%s (%s): linger_effect_id only valid for SMALL walkable — clearing" % [path, id_str])
			data["linger_effect_id"] = ""

	# applies_on_attacked requires breakable to be meaningful (not blocking — just warn)
	if bool(data.get("applies_on_attacked", false)) and not bool(data.get("breakable", false)):
		GameLogger.warn("TileObjectRegistry", "%s (%s): applies_on_attacked=true but breakable=false — trigger will never fire" % [path, id_str])

	return data
