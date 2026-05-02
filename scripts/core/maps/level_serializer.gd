class_name LevelSerializer

## Reads/writes LevelData ↔ JSON file. All errors logged via GameLogger; callers
## get a bool / null result to decide UI feedback.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")


## Saves level to path. Returns true on success.
## Path is res://-prefixed; FileAccess.WRITE handles user:// translation in
## exported builds, but in the editor / dev build res:// is writable.
static func save(level: LevelData, path: String) -> bool:
	if level == null:
		GameLogger.error("LevelSerializer", "save: level is null")
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		var err := FileAccess.get_open_error()
		GameLogger.error("LevelSerializer", "Cannot write %s: error %d" % [path, err])
		return false
	f.store_string(JSON.stringify(level.to_dict(), "\t"))
	f.close()
	GameLogger.info("LevelSerializer", "Saved %s (%d waves, %d/%d/%d active floor/obj/spawn)" % [
		path, level.waves.size(),
		level.floor_cells.size(), level.objects.size(), level.spawners.size()
	])
	return true


## Loads level from path. Returns null on read or parse failure.
static func load_from(path: String) -> LevelData:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		GameLogger.error("LevelSerializer", "Cannot read %s: error %d" % [path, FileAccess.get_open_error()])
		return null
	var text := f.get_as_text()
	f.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		GameLogger.error("LevelSerializer", "JSON parse error in %s: %s" % [path, json.get_error_message()])
		return null
	var raw: Variant = json.get_data()
	if typeof(raw) != TYPE_DICTIONARY:
		GameLogger.error("LevelSerializer", "Top-level JSON in %s is not a dict" % path)
		return null

	var level := LevelData.from_dict(raw)
	if level == null:
		GameLogger.error("LevelSerializer", "from_dict returned null for %s" % path)
		return null
	GameLogger.info("LevelSerializer", "Loaded %s (%d waves, %d/%d/%d active floor/obj/spawn)" % [
		path, level.waves.size(),
		level.floor_cells.size(), level.objects.size(), level.spawners.size()
	])
	return level
