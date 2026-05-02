## PadGen — two sine voices sustaining the 3rd and 5th of the current chord.
## Released and re-triggered on each bar (chord change). Slow attack avoids clicks.
## Deterministic — no RNG.

class_name PadGen

# ADSR in samples @ 22050 Hz
const A: int   = 13230  # 600 ms — softer entry
const D: int   = 441
const S: float = 0.4
const R: int   = 17640  # 800 ms — smooth release
const GAIN: float = 0.3
const OCTAVE_OFFSET: int = 0

var _enabled: bool = true

func set_enabled(v: bool) -> void:
	_enabled = v

## Called on each bar event (chord changes every bar in our 4-bar cycle).
func tick_bar(harmony: Harmony, voice_pool: VoicePool,
		noise_rng: RandomNumberGenerator) -> void:
	# Release previous pad voices before new chord.
	voice_pool.release_all_layer(&"pad")

	if not _enabled:
		return

	var chord: Array = harmony.get_chord_tones(OCTAVE_OFFSET)
	# chord[0] = root, chord[1] = 3rd, chord[2] = 5th
	# Play 3rd and 5th (indices 1 and 2).
	for i in [1, 2]:
		if i >= chord.size():
			continue
		var freq: float = Harmony.midi_to_freq(int(chord[i]))
		voice_pool.note_on(
			VoicePool.OSC_SINE, freq,
			[A, D, S, R], GAIN, &"pad", noise_rng
		)
