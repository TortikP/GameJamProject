## BassGen — triangle wave, root on beat 1 & 3, fifth on beat 2 & 4.
## Low octave (chord root − 12 semitones → one octave below).
## Deterministic — no RNG.

class_name BassGen

# ADSR in samples @ 22050 Hz
const A: int   = 441    # 20 ms
const D: int   = 2205   # 100 ms
const S: float = 0.6
const R: int   = 4410   # 200 ms
const GAIN: float = 0.5
const OCTAVE_OFFSET: int = -12  # one octave below chord root

var _enabled: bool = true
var _last_voice: int = -1

func set_enabled(v: bool) -> void:
	_enabled = v

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

	var chord: Array  = harmony.get_chord_tones(OCTAVE_OFFSET)
	var root_midi: int = int(chord[0])
	# Beat 0 & 2 → root. Beat 1 & 3 → fifth (root + 7 semitones, same octave).
	var midi: int
	if beat_in_bar % 2 == 0:
		midi = root_midi
	else:
		midi = root_midi + 7

	var freq: float = Harmony.midi_to_freq(midi)
	_last_voice = voice_pool.note_on(
		VoicePool.OSC_TRIANGLE, freq,
		[A, D, S, R], GAIN, &"bass", noise_rng
	)
