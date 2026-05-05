## LeadGen — square wave melodic lead on 1/4 beat grid.
## Strong beats (beat%2==0) → chord tone. Weak → scale tone or rest.
## Density (calm/battle) controls note probability.

class_name LeadGen

# ADSR in samples @ 22050 Hz
const A: int   = 110
const D: int   = 882
const S: float = 0.4
const R: int   = 1653
const GAIN: float = 0.35
const OCTAVE_OFFSET: int = 12   # one octave above chord root

var _calm_prob:   float = 0.2
var _battle_prob: float = 0.5
var _is_battle:   bool  = false
var _enabled: bool = true
var _last_voice: int = -1

func set_enabled(v: bool) -> void:
	_enabled = v

func set_density(calm: float, battle: float) -> void:
	_calm_prob   = clampf(calm,   0.0, 1.0)
	_battle_prob = clampf(battle, 0.0, 1.0)

func set_battle(battle: bool) -> void:
	_is_battle = battle

## Called once per beat event.
func tick_beat(beat_in_bar: int, harmony: Harmony, voice_pool: VoicePool,
		rng: RandomNumberGenerator) -> void:
	# Release previous lead note.
	if _last_voice >= 0:
		voice_pool.release(_last_voice)
		_last_voice = -1

	if not _enabled:
		return

	var prob: float = _battle_prob if _is_battle else _calm_prob
	if rng.randf() > prob:
		return   # rest

	var midi: int
	if beat_in_bar % 2 == 0:
		# Strong beat → chord tone (pick one based on RNG)
		var chord: Array = harmony.get_chord_tones(OCTAVE_OFFSET)
		midi = int(chord[rng.randi() % chord.size()])
	else:
		# Weak beat → scale tone
		var scale: Array = harmony.get_scale_tones(OCTAVE_OFFSET)
		midi = int(scale[rng.randi() % scale.size()])

	var freq: float = Harmony.midi_to_freq(midi)
	_last_voice = voice_pool.note_on(
		VoicePool.OSC_TRIANGLE, freq,
		[A, D, S, R], GAIN, &"lead", rng
	)
