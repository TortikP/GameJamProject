## PadGen — sustained chord voices, configurable voicing.
## Voicing = which intervals from the chord root to play.
## Released and re-triggered on each chord change. Slow attack avoids clicks.
## Deterministic — no RNG.

class_name PadGen

# ADSR in samples @ 11025 Hz (matches MusicDirector.MIX_RATE)
const A: int   = 6615
const D: int   = 220
const S: float = 0.4
const R: int   = 8820
const GAIN: float = 0.3
const OCTAVE_OFFSET: int = 0

const DEFAULT_VOICING: StringName = &"triad"

# Voicings — semitone offsets from chord root.
# Note: chord-tone arrays from harmony already include the root, so these
# offsets are absolute (rebuild from root, ignore harmony's intervals).
const VOICINGS: Dictionary = {
	&"triad": [3, 7],         # 3rd + 5th (existing v1 behavior, minor-tinted)
	&"sus2":  [2, 7],         # 2nd + 5th — open, airy
	&"sus4":  [5, 7],         # 4th + 5th — suspended, unresolved
	&"seven": [3, 7, 10],     # 3rd + 5th + minor 7 — jazzy/dark
}

var _enabled: bool = true
var _voicing_id: StringName = DEFAULT_VOICING
var _voicing: Array = VOICINGS[DEFAULT_VOICING]

func set_enabled(v: bool) -> void:
	_enabled = v

func set_voicing(id: StringName) -> void:
	if VOICINGS.has(id):
		_voicing_id = id
		_voicing    = VOICINGS[id]
	else:
		push_warning("[PadGen] unknown voicing '%s'" % id)
		_voicing_id = DEFAULT_VOICING
		_voicing    = VOICINGS[DEFAULT_VOICING]

static func list_voicing_ids() -> Array:
	var ids: Array = []
	for k in VOICINGS.keys():
		ids.append(String(k))
	ids.sort()
	return ids

## Called on each bar event.
func tick_bar(harmony: Harmony, voice_pool: VoicePool,
		noise_rng: RandomNumberGenerator) -> void:
	# Release previous pad voices before new chord.
	voice_pool.release_all_layer(&"pad")

	if not _enabled:
		return

	var root: int = harmony.current_root() + OCTAVE_OFFSET
	for offset in _voicing:
		var midi: int  = root + int(offset)
		var freq: float = Harmony.midi_to_freq(midi)
		voice_pool.note_on(
			VoicePool.OSC_SINE, freq,
			[A, D, S, R], GAIN, &"pad", noise_rng
		)
