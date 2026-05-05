extends Node
## DialogueDB — autoload. Scans data/dialogues/*.json, parses into memory.
## Must be registered before DialogueManager in project.godot.

const GameLogger    = preload("res://scripts/infrastructure/game_logger.gd")
const DialogueLine  = preload("res://scripts/core/dialogue/dialogue_line.gd")

const DIALOGUES_DIR  := "res://data/dialogues/"
const SPEAKERS_FILE  := "res://data/dialogues/_speakers.json"

var _lines:   Dictionary = {}   # StringName -> DialogueLine
var _speakers: Dictionary = {}  # StringName -> Dictionary
var _story_triggers: Dictionary = {}  # StringName trigger -> Array or mood map

const STORY_MOOD_NEUTRAL: StringName = &"neutral"


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
	_story_triggers.clear()
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
		if entry.has("trigger") and entry.has("mode"):
			_load_story_entry(entry, path)
			continue
		var line = DialogueLine.from_dict(entry)
		if line == null:
			continue
		if _lines.has(line.id):
			GameLogger.warn("DialogueDB", "duplicate id '%s' in '%s' — overriding previous" % [line.id, path])
		_lines[line.id] = line


# ── Public API ────────────────────────────────────────────────────────────────

func get_line(id: StringName) -> Object:  # DialogueLine | null
	if _story_triggers.has(id):
		var starts: Array = _resolve_story_starts(_story_triggers[id])
		if starts.is_empty():
			return null
		var picked: StringName = starts[randi() % starts.size()]
		return _lines.get(picked, null)
	return _lines.get(id, null)


func has_line(id: StringName) -> bool:
	return _lines.has(id) or _story_triggers.has(id)


func get_all_ids() -> Array:
	# Used by dialogue_preview and other dev tools.
	# Returned array is a copy — caller may sort/filter without affecting DB.
	var ids: Array = _lines.keys()
	for trigger in _story_triggers.keys():
		if trigger not in ids:
			ids.append(trigger)
	return ids


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


func _load_story_entry(entry: Dictionary, path: String) -> void:
	var id: String = str(entry.get("id", "")).strip_edges()
	var trigger: StringName = StringName(str(entry.get("trigger", id)))
	var mode: String = str(entry.get("mode", "sequence"))
	if id == "" or trigger == &"":
		GameLogger.warn("DialogueDB", "story entry in '%s' missing id/trigger" % path)
		return
	if entry.has("moods") and entry["moods"] is Dictionary:
		_load_story_mood_entry(id, trigger, mode, entry, path)
		return

	match mode:
		"sequence":
			var start: StringName = _register_story_sequence(id, trigger, entry.get("lines", []), "seq", path)
			if start != &"":
				_story_triggers[trigger] = [start]
		"random":
			var starts: Array[StringName] = []
			var options: Array = entry.get("options", [])
			for i in options.size():
				var line_dict: Dictionary = options[i] if options[i] is Dictionary else {}
				var start: StringName = _register_story_sequence(id, trigger, [line_dict], "opt_%d" % i, path)
				if start != &"":
					starts.append(start)
			if not starts.is_empty():
				_story_triggers[trigger] = starts
		"random_sequence":
			var starts: Array[StringName] = []
			var options: Array = entry.get("options", [])
			for i in options.size():
				var opt: Dictionary = options[i] if options[i] is Dictionary else {}
				var start: StringName = _register_story_sequence(id, trigger, opt.get("lines", []), "opt_%d" % i, path)
				if start != &"":
					starts.append(start)
			if not starts.is_empty():
				_story_triggers[trigger] = starts
		_:
			GameLogger.warn("DialogueDB", "story entry '%s' has unknown mode '%s'" % [id, mode])


func _load_story_mood_entry(id: String, trigger: StringName, mode: String,
		entry: Dictionary, path: String) -> void:
	var moods_raw: Dictionary = entry["moods"]
	var mood_map: Dictionary = {}
	for mood_key in moods_raw.keys():
		var mood_id: StringName = StringName(str(mood_key))
		var mood_entry: Dictionary = moods_raw[mood_key] if moods_raw[mood_key] is Dictionary else {}
		if mood_entry.is_empty():
			GameLogger.warn("DialogueDB", "story entry '%s' mood '%s' has no data" % [id, mood_id])
			mood_map[mood_id] = []
			continue
		var starts: Array = _register_story_mode(id, trigger, mode, mood_entry,
			"mood_%s" % str(mood_id), path, mood_id)
		mood_map[mood_id] = starts
	if mood_map.is_empty():
		GameLogger.warn("DialogueDB", "story entry '%s' in '%s' has no mood variants" % [id, path])
		return
	var fallback_raw: String = str(entry.get("moodFallback", entry.get("mood_fallback", STORY_MOOD_NEUTRAL)))
	_story_triggers[trigger] = {
		"moods": mood_map,
		"fallback": StringName(fallback_raw),
	}


func _register_story_mode(base_id: String, trigger: StringName, mode: String,
		entry: Dictionary, variant_prefix: String, path: String,
		mood_id: StringName) -> Array:
	var starts: Array[StringName] = []
	match mode:
		"sequence":
			var start: StringName = _register_story_sequence(
				base_id, trigger, entry.get("lines", []), "%s_seq" % variant_prefix, path, mood_id)
			if start != &"":
				starts.append(start)
		"random":
			var options: Array = entry.get("options", [])
			for i in options.size():
				var line_dict: Dictionary = options[i] if options[i] is Dictionary else {}
				var start: StringName = _register_story_sequence(
					base_id, trigger, [line_dict], "%s_opt_%d" % [variant_prefix, i], path, mood_id)
				if start != &"":
					starts.append(start)
		"random_sequence":
			var options: Array = entry.get("options", [])
			for i in options.size():
				var opt: Dictionary = options[i] if options[i] is Dictionary else {}
				var start: StringName = _register_story_sequence(
					base_id, trigger, opt.get("lines", []), "%s_opt_%d" % [variant_prefix, i], path, mood_id)
				if start != &"":
					starts.append(start)
		_:
			GameLogger.warn("DialogueDB", "story entry '%s' has unknown mode '%s'" % [base_id, mode])
	return starts


func _resolve_story_starts(story_entry: Variant) -> Array:
	if story_entry is Array:
		return story_entry
	if not (story_entry is Dictionary):
		return []
	var data: Dictionary = story_entry
	var moods: Dictionary = data.get("moods", {})
	if moods.is_empty():
		return []
	var mood: StringName = _current_dialogue_mood()
	if moods.has(mood):
		return moods[mood] if moods[mood] is Array else []
	var fallback: StringName = StringName(str(data.get("fallback", STORY_MOOD_NEUTRAL)))
	if moods.has(fallback):
		return moods[fallback] if moods[fallback] is Array else []
	return []


func _current_dialogue_mood() -> StringName:
	var mt: Node = get_node_or_null("/root/MoodTracker")
	if mt == null or not mt.has_method("get_dominant"):
		return STORY_MOOD_NEUTRAL
	return mt.get_dominant()


func _register_story_sequence(base_id: String, trigger: StringName, raw_lines: Variant,
		variant: String, path: String, mood_id: StringName = &"") -> StringName:
	if not (raw_lines is Array) or raw_lines.is_empty():
		GameLogger.warn("DialogueDB", "story entry '%s' in '%s' has no lines" % [base_id, path])
		return &""
	var start_id: StringName = &""
	var previous_id: StringName = &""
	var lines: Array = raw_lines
	for i in lines.size():
		if not (lines[i] is Dictionary):
			continue
		var src: Dictionary = lines[i]
		var def_key: String = str(src.get("def", "")).strip_edges()
		var speaker: String = str(src.get("speaker", "")).strip_edges()
		if def_key == "" or speaker == "":
			GameLogger.warn("DialogueDB", "story line in '%s' missing def/speaker" % base_id)
			continue
		var line_id: StringName = StringName("%s__%s_%d" % [base_id, variant, i])
		var line_dict := {
			"id": String(line_id),
			"speaker": speaker,
			"text": def_key,
			"audio_layer": str(src.get("audio_layer", "")) if src.get("audio_layer") != null else "",
			"audio_clip": _get_story_line_audio_clip(src),
			"tags": [String(trigger)] if i == 0 else [],
			"priority": int(src.get("priority", 100)),
			"once_per_run": bool(src.get("once_per_run", false)),
			"once_per_session": bool(src.get("once_per_session", false)),
			"next": "",
		}
		if mood_id != &"":
			line_dict["mood"] = String(mood_id)
		var line = DialogueLine.from_dict(line_dict)
		if line == null:
			continue
		_lines[line.id] = line
		if start_id == &"":
			start_id = line.id
		if previous_id != &"" and _lines.has(previous_id):
			_lines[previous_id].next = line.id
		previous_id = line.id
	return start_id


func _get_story_line_audio_clip(src: Dictionary) -> String:
	var audio_value = src.get("audio_clip", src.get("sound", ""))
	return str(audio_value) if audio_value != null else ""
