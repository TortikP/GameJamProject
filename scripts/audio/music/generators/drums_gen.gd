## DrumsGen — sine kick + filtered noise snare + noise hat. Pattern-driven.
## Disabled in calm state.

class_name DrumsGen

# Kick: sine 60 Hz, sharp decay
const KICK_FREQ: float = 60.0
const KICK_A: int   = 11
const KICK_D: int   = 441
const KICK_S: float = 0.0
const KICK_R: int   = 27
const KICK_GAIN: float = 0.7

# Snare: noise burst, mid-length
const SNARE_A: int   = 5
const SNARE_D: int   = 220
const SNARE_S: float = 0.0
const SNARE_R: int   = 27
const SNARE_GAIN: float = 0.45

# Hat: short noise tick
const HAT_A: int   = 5
const HAT_D: int   = 165
const HAT_S: float = 0.0
const HAT_R: int   = 27
const HAT_GAIN: float = 0.2

const DEFAULT_PATTERN: StringName = &"march"

var _enabled: bool = false
var _pattern_id: StringName = DEFAULT_PATTERN
var _pattern: Dictionary = DrumPatterns.get_pattern(DEFAULT_PATTERN)

func set_enabled(v: bool) -> void:
	_enabled = v

func set_pattern(id: StringName) -> void:
	_pattern_id = id
	_pattern    = DrumPatterns.get_pattern(id)

## Called once per beat event.
func tick_beat(beat_in_bar: int, _harmony: Harmony, voice_pool: VoicePool,
		noise_rng: RandomNumberGenerator) -> void:
	if not _enabled:
		return
	if not _pattern.has(beat_in_bar):
		return
	for hit in _pattern[beat_in_bar]:
		match hit:
			&"kick":
				voice_pool.note_on(
					VoicePool.OSC_SINE, KICK_FREQ,
					[KICK_A, KICK_D, KICK_S, KICK_R], KICK_GAIN, &"drums", noise_rng
				)
			&"snare":
				voice_pool.note_on(
					VoicePool.OSC_NOISE, 0.0,
					[SNARE_A, SNARE_D, SNARE_S, SNARE_R], SNARE_GAIN, &"drums", noise_rng
				)
			&"hat":
				voice_pool.note_on(
					VoicePool.OSC_NOISE, 0.0,
					[HAT_A, HAT_D, HAT_S, HAT_R], HAT_GAIN, &"drums", noise_rng
				)
