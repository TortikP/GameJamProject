## DrumsGen — sine kick + noise hat. Disabled in calm state.
## Kick on beats 0,2 (bars 1,3). Hat on beats 1,3.
## Offbeat 8th hats not implemented (lead already busy on 8th grid in P2).

class_name DrumsGen

# Kick: sine 60 Hz, sharp decay
const KICK_FREQ: float = 60.0
const KICK_A: int   = 22
const KICK_D: int   = 882
const KICK_S: float = 0.0
const KICK_R: int   = 55
const KICK_GAIN: float = 0.7

# Hat: noise, very short
const HAT_A: int   = 11
const HAT_D: int   = 330
const HAT_S: float = 0.0
const HAT_R: int   = 55
const HAT_GAIN: float = 0.2

var _enabled: bool = false

func set_enabled(v: bool) -> void:
	_enabled = v

## Called once per beat event.
func tick_beat(beat_in_bar: int, _harmony: Harmony, voice_pool: VoicePool,
		noise_rng: RandomNumberGenerator) -> void:
	if not _enabled:
		return

	# Kick: beats 0 and 2
	if beat_in_bar == 0 or beat_in_bar == 2:
		voice_pool.note_on(
			VoicePool.OSC_SINE, KICK_FREQ,
			[KICK_A, KICK_D, KICK_S, KICK_R], KICK_GAIN, &"drums", noise_rng
		)

	# Hat: beats 1 and 3
	if beat_in_bar == 1 or beat_in_bar == 3:
		voice_pool.note_on(
			VoicePool.OSC_NOISE, 0.0,
			[HAT_A, HAT_D, HAT_S, HAT_R], HAT_GAIN, &"drums", noise_rng
		)
