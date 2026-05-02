## Harmony — chord progression + scale, configurable per-level.
## Progressions loaded from data/music/progressions.json (content-driven).
## Scales hardcoded (math, not content).
## Chord changes every `bars_per_chord` bars (1, 2, 4, or 8).
##
## MIDI note number 69 = A4 (440 Hz).

class_name Harmony

const PROGRESSIONS_PATH: String = "res://data/music/progressions.json"

# ── Scales (intervals within an octave from root) ─────────────────────────────
# Hardcoded — these are theory, not content.
const SCALES: Dictionary = {
	&"natural_minor":   [0, 2, 3, 5, 7, 8, 10],
	&"dorian":          [0, 2, 3, 5, 7, 9, 10],   # minor with major 6
	&"phrygian":        [0, 1, 3, 5, 7, 8, 10],   # minor with flat 2 (eastern)
	&"harmonic_minor":  [0, 2, 3, 5, 7, 8, 11],   # minor with raised 7 (dramatic)
	&"pentatonic_minor": [0, 3, 5, 7, 10],         # 5-note (asian/bluesy)
}

const DEFAULT_PROGRESSION: StringName = &"am_f_c_g"
const DEFAULT_SCALE:       StringName = &"natural_minor"

# Fallback progression baked in — used if JSON is missing or unknown id.
const FALLBACK_CHORDS: Array = [
	[69, [0, 3, 7]],   # A minor
	[65, [0, 4, 7]],   # F major
	[60, [0, 4, 7]],   # C major
	[67, [0, 4, 7]],   # G major
]

# ── Lazy JSON cache ───────────────────────────────────────────────────────────

static var _progressions_cache: Dictionary = {}
static var _loaded: bool = false
static var _warned_missing: Dictionary = {}

# ── Per-instance state ────────────────────────────────────────────────────────

var _chords: Array = FALLBACK_CHORDS         # current progression chords
var _scale_intervals: Array = SCALES[DEFAULT_SCALE]
var _scale_id: StringName = DEFAULT_SCALE
var _progression_id: StringName = DEFAULT_PROGRESSION
var _bars_per_chord: int = 1                  # 1, 2, 4, 8 — how long each chord lasts

var _current_chord_idx: int = 0

func reset(_seed: int) -> void:
	_current_chord_idx = 0

## Called by MusicDirector on each bar event.
func tick_bar(bar_idx: int) -> void:
	if _chords.is_empty():
		return
	var bpc: int = max(1, _bars_per_chord)
	_current_chord_idx = (bar_idx / bpc) % _chords.size()

## Set progression by id. Falls back silently to default on unknown id.
func set_progression(id: StringName) -> void:
	_ensure_loaded()
	var key: String = String(id)
	if _progressions_cache.has(key):
		_chords = _progressions_cache[key]
		_progression_id = id
	else:
		if not _warned_missing.has(key):
			push_warning("[Harmony] unknown progression '%s' — using fallback" % key)
			_warned_missing[key] = true
		_chords = FALLBACK_CHORDS
		_progression_id = DEFAULT_PROGRESSION
	_current_chord_idx = 0

func set_scale(id: StringName) -> void:
	if SCALES.has(id):
		_scale_intervals = SCALES[id]
		_scale_id = id
	else:
		if not _warned_missing.has(String(id)):
			push_warning("[Harmony] unknown scale '%s' — using natural_minor" % id)
			_warned_missing[String(id)] = true
		_scale_intervals = SCALES[DEFAULT_SCALE]
		_scale_id = DEFAULT_SCALE

## bars_per_chord ∈ {1, 2, 4, 8}. Other values clamped to nearest power of 2 in range.
func set_bars_per_chord(n: int) -> void:
	if n <= 1: _bars_per_chord = 1
	elif n <= 2: _bars_per_chord = 2
	elif n <= 4: _bars_per_chord = 4
	else: _bars_per_chord = 8

## Returns MIDI note numbers for current chord, transposed by octave_offset semitones.
func get_chord_tones(octave_offset: int = 0) -> Array:
	if _chords.is_empty():
		return []
	var entry: Array = _chords[_current_chord_idx]
	var root: int    = int(entry[0]) + octave_offset
	var intervals    = entry[1]
	var out: Array   = []
	for interval in intervals:
		out.append(root + int(interval))
	return out

## Returns scale tones starting at current chord root + octave_offset.
func get_scale_tones(octave_offset: int = 0) -> Array:
	if _chords.is_empty():
		return []
	var root: int  = int(_chords[_current_chord_idx][0]) + octave_offset
	var out: Array = []
	for interval in _scale_intervals:
		out.append(root + int(interval))
	return out

## Current root MIDI (no offset).
func current_root() -> int:
	if _chords.is_empty():
		return 69
	return int(_chords[_current_chord_idx][0])

## Convert MIDI note number to frequency (Hz).
static func midi_to_freq(midi: int) -> float:
	return 440.0 * pow(2.0, float(midi - 69) / 12.0)

## Returns sorted list of progression IDs (for Music Lab dropdown).
static func list_progression_ids() -> Array:
	_ensure_loaded()
	var ids: Array = _progressions_cache.keys()
	ids.sort()
	return ids

static func list_scale_ids() -> Array:
	var ids: Array = []
	for k in SCALES.keys():
		ids.append(String(k))
	ids.sort()
	return ids

# ── Private ──────────────────────────────────────────────────────────────────

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PROGRESSIONS_PATH):
		push_warning("[Harmony] progressions.json missing — only fallback available")
		return
	var f: FileAccess = FileAccess.open(PROGRESSIONS_PATH, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		push_warning("[Harmony] progressions.json malformed")
		return
	var raw: Dictionary = d.get("progressions", {})
	for id in raw.keys():
		var entry: Dictionary = raw[id]
		var chords: Array = entry.get("chords", [])
		if chords.is_empty():
			continue
		_progressions_cache[id] = chords
