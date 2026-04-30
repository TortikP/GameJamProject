extends Node
## DialogueDB — autoload. Scans data/dialogues/*.json, parses into memory.
## Must be registered before DialogueManager in project.godot.

const GameLogger    = preload("res://scripts/infrastructure/game_logger.gd")
const DialogueLine  = preload("res://scripts/core/dialogue/dialogue_line.gd")

const DIALOGUES_DIR  := "res://data/dialogues/"
const SPEAKERS_FILE  := "res://data/dialogues/_speakers.json"

var _lines:   Dictionary = {}   # StringName -> DialogueLine
var _speakers: Dictionary = {}  # StringName -> Dictionary


func _ready() -> void:
	_load_speakers()
	_scan_dialogues()
	GameLogger.info("DialogueDB", "loaded %d dialogues, %d speakers" % [_lines.size(), _speakers.size()])


func _load_speakers() -> void:
	if not FileAccess.file_exists(SPEAKERS_FILE):
		GameLogger.warn("DialogueDB", "_speakers.json not found — speaker lookup will return empty")
		return
	var text := FileAccess.get_file_as_string(SPEAKERS_FILE)
	var parsed = JSON.parse_string(text)
	if parsed == null:
		GameLogger.warn("DialogueDB", "_speakers.json parse failed — skipping")
		return
	for key in parsed:
		_speakers[StringName(str(key))] = parsed[key]


func _scan_dialogues() -> void:
	var dir := DirAccess.open(DIALOGUES_DIR)
	if dir == null:
		GameLogger.warn("DialogueDB", "cannot open '%s'" % DIALOGUES_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json") and not fname.begins_with("_"):
			_load_file(DIALOGUES_DIR + fname)
		fname = dir.get_next()
	dir.list_dir_end()


func _load_file(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		GameLogger.warn("DialogueDB", "empty or unreadable: '%s'" % path)
		return
	var parsed = JSON.parse_string(text)
	if parsed == null:
		GameLogger.warn("DialogueDB", "JSON parse failed: '%s'" % path)
		return

	# A file may contain a single dict or an array of dicts
	var entries: Array = []
	if parsed is Dictionary:
		entries = [parsed]
	elif parsed is Array:
		entries = parsed
	else:
		GameLogger.warn("DialogueDB", "unexpected JSON root type in '%s'" % path)
		return

	for entry in entries:
		if not entry is Dictionary:
			GameLogger.warn("DialogueDB", "non-dict entry in '%s' — skip" % path)
			continue
		var line = DialogueLine.from_dict(entry)
		if line == null:
			continue
		if _lines.has(line.id):
			GameLogger.warn("DialogueDB", "duplicate id '%s' in '%s' — overriding previous" % [line.id, path])
		_lines[line.id] = line


# ── Public API ────────────────────────────────────────────────────────────────

func get_line(id: StringName) -> Object:  # DialogueLine | null
	return _lines.get(id, null)


func has_line(id: StringName) -> bool:
	return _lines.has(id)


func get_all_ids() -> Array:
	# Used by dev tools (dialogue_preview, future dev_console `db` command).
	# Returned array is a copy — caller may sort/filter without affecting DB.
	return _lines.keys()


func get_speaker(id: StringName) -> Dictionary:
	return _speakers.get(id, {})


## find_by_event — Hades-lite selector.
## context: Dictionary with optional keys: run_count (int), flags (Array[String]).
## played: Dictionary with keys "run" -> Dictionary[StringName, bool],
##                              "session" -> Dictionary[StringName, bool].
func find_by_event(event: StringName, context: Dictionary, played: Dictionary) -> Object:
	var run_count: int  = context.get("run_count", 0)
	var flags: Array    = context.get("flags", [])
	var played_run     : Dictionary = played.get("run", {})
	var played_session : Dictionary = played.get("session", {})

	# Step 1 — filter by tag
	var candidates: Array = []
	for line in _lines.values():
		if event in line.tags:
			candidates.append(line)

	# Step 2 — filter by conditions
	var filtered: Array = []
	for c in candidates:
		var cond: Dictionary = c.conditions
		if run_count < cond.get("min_run", 0):
			continue
		if run_count > cond.get("max_run", 999):
			continue
		var ok := true
		for f in cond.get("flags_required", []):
			if f not in flags:
				ok = false
				break
		if not ok:
			continue
		for f in cond.get("flags_forbidden", []):
			if f in flags:
				ok = false
				break
		if ok:
			filtered.append(c)

	# Step 3 — drop played once-only
	var eligible: Array = []
	for c in filtered:
		if c.once_per_run and played_run.has(c.id):
			continue
		if c.once_per_session and played_session.has(c.id):
			continue
		eligible.append(c)

	# Step 4 — fallback to repeatable if eligible empty
	if eligible.is_empty():
		var repeatable: Array = []
		for c in filtered:
			if not c.once_per_session and not c.once_per_run:
				repeatable.append(c)
		if repeatable.is_empty():
			return null
		eligible = repeatable

	# Step 5-7 — pick highest priority, random among ties
	var max_pri: int = -999999
	for c in eligible:
		if c.priority > max_pri:
			max_pri = c.priority
	var top: Array = []
	for c in eligible:
		if c.priority == max_pri:
			top.append(c)

	return top[randi() % top.size()]
