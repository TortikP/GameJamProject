## PresetResolver — static. Merges preset fields + explicit overrides.
## Resolution order: hardcoded defaults → preset → explicit fields in raw.
##
## Usage: var cfg = PresetResolver.resolve(level.music_config)
## No Node required — preload and call statically.

class_name PresetResolver

const PRESETS_PATH: String = "res://data/music/presets.json"

static var _presets_cache: Dictionary = {}
static var _loaded: bool = false
static var _warned_missing: Dictionary = {}

## Returns a merged Dictionary with all known music config keys resolved.
## Caller uses .get("key", default) for any remaining unspecified fields.
static func resolve(raw: Dictionary) -> Dictionary:
	_ensure_loaded()
	var out: Dictionary = {}

	var preset_id: String = String(raw.get("preset", ""))
	if preset_id != "":
		if _presets_cache.has(preset_id):
			# Layer 1: preset fields.
			for key in _presets_cache[preset_id]:
				out[key] = _presets_cache[preset_id][key]
		else:
			if not _warned_missing.has(preset_id):
				push_warning("[PresetResolver] unknown preset '%s' — using defaults" % preset_id)
				_warned_missing[preset_id] = true

	# Layer 2: explicit fields override preset (skip "preset" key itself).
	for key in raw.keys():
		if key == "preset":
			continue
		out[key] = raw[key]

	return out

## Returns sorted list of known preset IDs (for Music Lab dropdown).
static func list_preset_ids() -> Array:
	_ensure_loaded()
	var ids: Array = _presets_cache.keys()
	ids.sort()
	return ids

# ── Private ──────────────────────────────────────────────────────────────────

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PRESETS_PATH):
		push_warning("[PresetResolver] %s missing — no presets available" % PRESETS_PATH)
		return
	var f: FileAccess = FileAccess.open(PRESETS_PATH, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text())
	if d is Dictionary and d.has("presets") and d["presets"] is Dictionary:
		_presets_cache = d["presets"]
	else:
		push_warning("[PresetResolver] presets.json malformed — no presets loaded")
