## BassGen — triangle wave bass, pattern-driven.
## Pattern is Array[4] of semitone offsets from chord root, applied per beat.
## Octave shift (-12) keeps it below the chord. Deterministic — no RNG.

class_name BassGen

# ADSR in samples @ 11025 Hz
const A: int   = 110
const D: int   = 551
const S: float = 0.6
const R: int   = 1102
const GAIN: float = 0.5
const OCTAVE_OFFSET: int = -12   # one octave below chord root

const DEFAULT_PATTERN: StringName = &"root_fifth"

var _enabled: bool = true
var _pattern_id: StringName = DEFAULT_PATTERN
var _pattern: Array = BassPatterns.get_pattern(DEFAULT_PATTERN)

var _last_voice: int = -1

func set_enabled(v: bool) -> void:
	_enabled = v

func set_pattern(id: StringName) -> void:
	_pattern_id = id
	_pattern    = BassPatterns.get_pattern(id)

## Called once per beat event by MusicDirector.
## beat_in_bar = beat_idx % 4 (0-based).
func tick_beat(beat_in_bar: int, harmony: Harmony, voice_pool: VoicePool,
		noise_rng: RandomNumberGenerator) -> void:
	if not _enabled:
		return

	# Release previous bass note.
	if _last_voice >= 0:
		voice_pool.release(_last_voice)
		_last_voice = -1

	var idx: int = clamp(beat_in_bar, 0, _pattern.size() - 1)
	var offset: int = int(_pattern[idx])
	if offset == BassPatterns.REST:
		return

	var root_midi: int = harmony.current_root() + OCTAVE_OFFSET
	var midi: int = root_midi + offset
	var freq: float = Harmony.midi_to_freq(midi)
	_last_voice = voice_pool.note_on(
		VoicePool.OSC_TRIANGLE, freq,
		[A, D, S, R], GAIN, &"bass", noise_rng
	)
