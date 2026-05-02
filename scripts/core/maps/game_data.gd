class_name GameData

## Pure data container for a "game" — an ordered list of map files (LevelData
## paths) that play one after another with upgrade screens between them.
## Serialized 1:1 to JSON via GameSerializer. Composed in scenes/dev/game_editor.
## Consumed at runtime by ActiveGame + CampaignController.
##
## No node ops, no signals — value object.
##
## See specs/035-game-editor/spec.md §1 for the schema; this file is the
## canonical implementation of it.

const SCHEMA_VERSION: int = 1

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

var name: String = "Untitled"
var version: int = SCHEMA_VERSION

# Each entry:
#   {
#     "map_path":     String        — res://data/maps/<file>.json
#     "display_name": String        — what we show in HUD / cutscene title cards
#     "cutscene_id":  StringName    — &"" if no cutscene; future cutscene system
#                                     listens to EventBus.campaign_cutscene_requested
#     "is_intro":     bool          — exactly 0 or 1 levels can be intro;
#                                     marks "first level of a fresh playthrough"
#   }
var levels: Array[Dictionary] = []


# ── Construction helpers ────────────────────────────────────────────────────

static func make_level_entry(
	map_path: String,
	display_name: String = "",
	cutscene_id: StringName = &"",
	is_intro: bool = false
) -> Dictionary:
	return {
		"map_path": map_path,
		"display_name": display_name,
		"cutscene_id": cutscene_id,
		"is_intro": is_intro,
	}


# ── Validation ──────────────────────────────────────────────────────────────

## Returns array of error/warn messages. Empty array = valid.
## Mutates self for graceful fixes (drops bad entries, dedups is_intro).
## Caller decides save/load behaviour from message contents (warn vs reject).
func validate() -> Array[String]:
	var msgs: Array[String] = []

	if levels.is_empty():
		msgs.append("REJECT: game has no levels (need >= 1)")
		return msgs  # nothing else to check

	# Drop entries with missing files. Build new array to preserve order.
	var kept: Array[Dictionary] = []
	for i: int in range(levels.size()):
		var lv: Dictionary = levels[i]
		var path: String = String(lv.get("map_path", ""))
		if path == "":
			msgs.append("WARN: level %d has empty map_path; dropped" % i)
			continue
		if not path.ends_with(".json"):
			msgs.append("WARN: level %d map_path %s missing .json suffix; dropped" % [i, path])
			continue
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			msgs.append("WARN: level %d map_path %s not found; dropped" % [i, path])
			continue
		kept.append(lv)
	levels = kept

	if levels.is_empty():
		msgs.append("REJECT: all levels dropped during validation")
		return msgs

	# is_intro deduplication: keep first, clear the rest.
	var seen_intro: bool = false
	for i: int in range(levels.size()):
		var is_intro: bool = bool(levels[i].get("is_intro", false))
		if is_intro:
			if seen_intro:
				msgs.append("WARN: level %d had is_intro=true (already set on earlier level); cleared" % i)
				levels[i]["is_intro"] = false
			else:
				seen_intro = true

	return msgs


## True if validate() returned no REJECT messages. Convenience for callers
## that don't need the message list.
func is_valid() -> bool:
	for msg: String in validate():
		if msg.begins_with("REJECT"):
			return false
	return true


# ── Indexing ────────────────────────────────────────────────────────────────

func size() -> int:
	return levels.size()


func get_level(index: int) -> Dictionary:
	if index < 0 or index >= levels.size():
		return {}
	return levels[index]


func is_last_index(index: int) -> bool:
	return index == levels.size() - 1


# ── Mutators (used by editor) ───────────────────────────────────────────────

func add_level(entry: Dictionary) -> void:
	levels.append(entry)


func remove_at(index: int) -> bool:
	if index < 0 or index >= levels.size():
		return false
	levels.remove_at(index)
	return true


func swap(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a >= levels.size() or b >= levels.size() or a == b:
		return false
	var tmp: Dictionary = levels[a]
	levels[a] = levels[b]
	levels[b] = tmp
	return true


## Sets is_intro=true on the given index, clears it on every other level.
## No-op if index out of range.
func set_intro(index: int) -> void:
	if index < 0 or index >= levels.size():
		return
	for i: int in range(levels.size()):
		levels[i]["is_intro"] = (i == index)


## Clears is_intro on every level (no level is the intro).
func clear_intro() -> void:
	for i: int in range(levels.size()):
		levels[i]["is_intro"] = false


# ── Serialization (called by GameSerializer) ────────────────────────────────

func to_dict() -> Dictionary:
	var levels_out: Array = []
	for lv: Dictionary in levels:
		levels_out.append({
			"map_path": String(lv.get("map_path", "")),
			"display_name": String(lv.get("display_name", "")),
			# StringName serializes as plain string in JSON; restore on load.
			"cutscene_id": String(lv.get("cutscene_id", &"")),
			"is_intro": bool(lv.get("is_intro", false)),
		})
	return {
		"name": name,
		"version": version,
		"levels": levels_out,
	}


static func from_dict(raw: Dictionary) -> GameData:
	var g := GameData.new()
	g.name = String(raw.get("name", "Untitled"))
	g.version = int(raw.get("version", SCHEMA_VERSION))
	if g.version != SCHEMA_VERSION:
		GameLogger.warn("GameData", "from_dict: schema version mismatch (got %d, expected %d) — proceeding optimistically" % [g.version, SCHEMA_VERSION])

	var raw_levels: Variant = raw.get("levels", [])
	if typeof(raw_levels) != TYPE_ARRAY:
		GameLogger.error("GameData", "from_dict: 'levels' is not an array")
		return null

	for entry: Variant in raw_levels:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = entry
		g.levels.append({
			"map_path": String(d.get("map_path", "")),
			"display_name": String(d.get("display_name", "")),
			"cutscene_id": StringName(String(d.get("cutscene_id", ""))),
			"is_intro": bool(d.get("is_intro", false)),
		})
	return g
