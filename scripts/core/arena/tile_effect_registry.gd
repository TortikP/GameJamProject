class_name TileEffectRegistry

## Loads tile effect definitions from data/tile_effects/*.json at startup.
## Usage: create an instance on the scene, call load_from_dir once.
## Query with get_effect(id). Returns empty dict if unknown.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

var _effects: Dictionary = {}   # StringName -> Dictionary


func load_from_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		GameLogger.warn("TileEffectRegistry", "Cannot open dir: %s" % dir_path)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			_load_file(dir_path.path_join(fname))
		fname = dir.get_next()
	dir.list_dir_end()
	GameLogger.info("TileEffectRegistry", "Loaded %d tile effects" % _effects.size())


func _load_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		GameLogger.warn("TileEffectRegistry", "Cannot read: %s" % path)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		GameLogger.warn("TileEffectRegistry", "JSON parse error in %s: %s" % [path, json.get_error_message()])
		return
	var data: Dictionary = json.get_data()
	if not data.has("id"):
		GameLogger.warn("TileEffectRegistry", "Missing 'id' in %s" % path)
		return
	_effects[StringName(data["id"])] = data


func get_effect(id: StringName) -> Dictionary:
	return _effects.get(id, {})


func has_effect(id: StringName) -> bool:
	return _effects.has(id)
