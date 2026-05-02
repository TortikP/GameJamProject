class_name GameSerializer

## Reads/writes GameData ↔ JSON file. Mirrors LevelSerializer (020).
## Errors logged via GameLogger; callers get bool / null to drive UI feedback.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const GAMES_DIR: String = "res://data/games/"
const FILE_EXT: String = ".game.json"


## Sanitize a human name into a safe basename. Mirrors 020 pattern:
##   lower → replace [^a-z0-9_-] with _ → trim leading _ → "untitled" on empty
static func sanitize(name: String) -> String:
	var s: String = name.strip_edges().to_lower()
	var out: String = ""
	for i: int in range(s.length()):
		var c: String = s[i]
		var ch: int = c.unicode_at(0)
		var is_lower: bool = ch >= 0x61 and ch <= 0x7A   # a-z
		var is_digit: bool = ch >= 0x30 and ch <= 0x39   # 0-9
		var is_safe: bool = c == "_" or c == "-"
		if is_lower or is_digit or is_safe:
			out += c
		else:
			out += "_"
	# Collapse repeats and strip leading _
	while out.begins_with("_"):
		out = out.substr(1)
	if out == "":
		out = "untitled"
	return out


## Builds full save path under GAMES_DIR for a given GameData. Used by editor's
## Save flow when no explicit path is given.
static func default_path_for(game: GameData) -> String:
	return GAMES_DIR + sanitize(game.name) + FILE_EXT


## Saves game to path. Returns true on success.
static func save(game: GameData, path: String) -> bool:
	if game == null:
		GameLogger.error("GameSerializer", "save: game is null")
		return false
	# Ensure directory exists (res:// is writable in editor / dev builds).
	if not DirAccess.dir_exists_absolute(GAMES_DIR):
		var err := DirAccess.make_dir_recursive_absolute(GAMES_DIR)
		if err != OK:
			GameLogger.error("GameSerializer", "Cannot create %s: error %d" % [GAMES_DIR, err])
			return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		var open_err := FileAccess.get_open_error()
		GameLogger.error("GameSerializer", "Cannot write %s: error %d" % [path, open_err])
		return false
	f.store_string(JSON.stringify(game.to_dict(), "\t"))
	f.close()
	GameLogger.info("GameSerializer", "Saved %s (%d levels)" % [path, game.size()])
	return true


## Loads game from path. Returns null on read or parse failure.
static func load_from(path: String) -> GameData:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		GameLogger.error("GameSerializer", "Cannot read %s: error %d" % [path, FileAccess.get_open_error()])
		return null
	var text := f.get_as_text()
	f.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		GameLogger.error("GameSerializer", "JSON parse error in %s: %s" % [path, json.get_error_message()])
		return null
	var raw: Variant = json.get_data()
	if typeof(raw) != TYPE_DICTIONARY:
		GameLogger.error("GameSerializer", "Top-level JSON in %s is not a dict" % path)
		return null

	var game := GameData.from_dict(raw)
	if game == null:
		GameLogger.error("GameSerializer", "from_dict returned null for %s" % path)
		return null
	GameLogger.info("GameSerializer", "Loaded %s (%d levels)" % [path, game.size()])
	return game


## Lists all *.game.json files under GAMES_DIR. Used by Load Game FileDialog
## and Game Editor's preview / autoselect. Excludes the editor's autosave
## scratch file. Returns absolute res:// paths.
static func list_game_files() -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(GAMES_DIR):
		return out
	var dir := DirAccess.open(GAMES_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(FILE_EXT):
			if fname != "__autosave_game__" + FILE_EXT and fname != "__playtest_game__" + FILE_EXT:
				out.append(GAMES_DIR + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
