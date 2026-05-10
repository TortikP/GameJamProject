extends SceneTree
## Spec 061 — auto-tests for v2→v3 migration roundtrip and per-wave invariants.
##
## Covers smoke items T-061-74, T-061-75, T-061-76 in their data-integrity
## aspect (load → migrate → save-as-JSON → reload → save-again → idempotent).
## Does NOT cover editor UI behaviour (switcher, wave count display, errors
## in console) — those stay manual.
##
## Run: godot --headless --script tests/test_061_migration.gd
## Exit code: 0 = green, 1 = at least one failure.

const MAPS_DIR := "res://data/maps/"
const BASELINE_PATH := "res://tests/maps_validate_baseline.txt"

# Filename patterns to skip (transient editor state, scratch saves, non-map configs).
# Convention: __NAME__.json = autosave/playtest scratch (BasePanel pattern);
# "Untitled*" / "untitled.json" = unsaved editor sessions; "maps_*_name.json" = test-data
# detritus from spec 040 era; "music_track_*" = music configs that share schema
# with maps but aren't game-playable maps (per data/maps/_schema.md).
const SKIP_PREFIXES: Array[String] = ["__", "Untitled", "untitled", "maps_", "music_track_"]

var _failures: Array[String] = []
var _checked: int = 0
var _skipped: int = 0
var _validate_baseline: Dictionary = {}  # filename → reason


# `_initialize()` runs after the engine has bound autoloads, so any class_name
# script that uses Localization (e.g. DialogueTrigger.validate via LevelData)
# can resolve at parse time. Using `_init()` here would fire before autoloads.
func _initialize() -> void:
	print("[test_061_migration] starting")
	_load_baseline()
	_run_all()
	if _failures.is_empty():
		print("[test_061_migration] OK — %d maps checked, %d skipped (scratch/baseline)" % [_checked, _skipped])
		quit(0)
	else:
		print("[test_061_migration] FAIL — %d failures across %d maps (%d skipped):" % [_failures.size(), _checked, _skipped])
		for f in _failures:
			print("  - " + f)
		quit(1)


func _load_baseline() -> void:
	var f := FileAccess.open(BASELINE_PATH, FileAccess.READ)
	if f == null:
		return  # baseline is optional
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		# Format: "filename.json: reason"
		var parts := line.split(":", false, 1)
		var fname: String = parts[0].strip_edges()
		var reason: String = parts[1].strip_edges() if parts.size() > 1 else "(no reason)"
		_validate_baseline[fname] = reason
	f.close()
	print("[test_061_migration] baseline: %d files exempt from validate" % _validate_baseline.size())


func _run_all() -> void:
	var dir := DirAccess.open(MAPS_DIR)
	if dir == null:
		_failures.append("can't open " + MAPS_DIR)
		return
	dir.list_dir_begin()
	var files: Array[String] = []
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			files.append(name)
		name = dir.get_next()
	files.sort()
	for f in files:
		_test_file(f)


func _test_file(fname: String) -> void:
	for pref in SKIP_PREFIXES:
		if fname.begins_with(pref):
			_skipped += 1
			return

	var path := MAPS_DIR + fname
	var raw_dict: Variant = _load_json(path)
	if not (raw_dict is Dictionary):
		_fail(fname, "JSON parse failed or root is not a dict")
		return
	# Defensive skip: data/maps/ should hold map files only, but a stray
	# non-map JSON shouldn't crash the suite.
	if not (raw_dict.has("tileset_path") or raw_dict.has("waves") or raw_dict.has("floor")):
		print("[skip] %s — no map markers" % fname)
		_skipped += 1
		return

	_checked += 1
	var lvl: LevelData = LevelData.from_dict(raw_dict)
	if lvl == null:
		_fail(fname, "from_dict returned null on first load")
		return

	# I1. Post-migration version must equal current schema version.
	if lvl.version != LevelData.SCHEMA_VERSION:
		_fail(fname, "version=%d after from_dict (expected %d)" % [lvl.version, LevelData.SCHEMA_VERSION])

	# I2. validate() must produce no non-WARN errors. Skipped for files in
	# the baseline (legacy authoring issues tracked in tech-debt).
	if _validate_baseline.has(fname):
		print("[baseline] %s — validate skipped: %s" % [fname, _validate_baseline[fname]])
	else:
		var errors := lvl.validate()
		for e in errors:
			if not e.begins_with("WARN:"):
				_fail(fname, "validate: " + e)

	# I3. Per-wave shape invariants.
	for i in lvl.waves.size():
		var w: Dictionary = lvl.waves[i]
		if not (w.get("is_special") is String):
			_fail(fname, "wave %d: is_special is not String" % i)
		var am: String = String(w.get("advance_mode", ""))
		if not (am in LevelData.VALID_ADVANCE_MODES):
			_fail(fname, "wave %d: advance_mode '%s' not in valid set" % [i, am])
		if not (w.get("music_config") is Dictionary):
			_fail(fname, "wave %d: music_config is not Dictionary" % i)

	# I4. Idempotent roundtrip through real save path:
	#   to_dict → JSON.stringify → JSON.parse_string → from_dict → to_dict
	# Mirrors level_serializer.gd:21 1:1. F-061-IMPL-1 catch — if any bool() cast
	# on is_special re-creeps in, dict2 will diverge from dict1.
	var dict1: Dictionary = lvl.to_dict()
	var json1: String = JSON.stringify(dict1, "\t")
	var parsed: Variant = JSON.parse_string(json1)
	if not (parsed is Dictionary):
		_fail(fname, "JSON.parse_string failed on first to_dict output")
		return
	var lvl2: LevelData = LevelData.from_dict(parsed)
	if lvl2 == null:
		_fail(fname, "second from_dict returned null")
		return
	var dict2: Dictionary = lvl2.to_dict()
	if not _deep_eq(dict1, dict2):
		_fail(fname, "save→reload roundtrip not idempotent")
		_print_diff(dict1, dict2)


func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)


func _fail(fname: String, msg: String) -> void:
	_failures.append("%s — %s" % [fname, msg])


func _deep_eq(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		var ka: Array = (a as Dictionary).keys()
		var kb: Array = (b as Dictionary).keys()
		ka.sort()
		kb.sort()
		if ka != kb:
			return false
		for k in ka:
			if not _deep_eq(a[k], b[k]):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _deep_eq(a[i], b[i]):
				return false
		return true
	return a == b


func _print_diff(a: Dictionary, b: Dictionary) -> void:
	var seen: Dictionary = {}
	var reported := 0
	var all_keys: Array = a.keys() + b.keys()
	for k in all_keys:
		if seen.has(k):
			continue
		seen[k] = true
		if not _deep_eq(a.get(k), b.get(k)):
			print("    diff at key '%s':" % k)
			print("      dict1: %s" % str(a.get(k)).left(200))
			print("      dict2: %s" % str(b.get(k)).left(200))
			reported += 1
			if reported >= 5:
				print("    (...further diffs suppressed)")
				return
