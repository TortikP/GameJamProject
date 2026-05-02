## ProcStings — static. Synthesizes procedural sting presets via VoicePool.
## Each preset sequences note_on calls with sample-offset delays.
## StingPlayer calls dispatch_*(voice_pool, harmony) when kind=="procedural".
##
## Mini-conductor pattern: StingPlayer owns a sample counter; ProcStings
## schedules relative to "now" by pushing into a deferred queue.
## For jam simplicity: notes fire immediately via note_on — sequential
## notes separated by calling voice_pool.note_on with matching ADSR lengths
## so they cascade without manual scheduling.

class_name ProcStings

const MIX_RATE: int = 22050

## blip_up: two notes up the chord (square, ~0.4 s total)
static func dispatch_blip_up(voice_pool: VoicePool, harmony: Harmony,
		noise_rng: RandomNumberGenerator) -> void:
	var chord: Array = harmony.get_chord_tones(12)   # +1 octave
	if chord.size() < 2:
		return
	# Note 1: short
	voice_pool.note_on(VoicePool.OSC_SQUARE, Harmony.midi_to_freq(int(chord[0])),
		[44, 220, 0.0, 44], 0.5, &"sting", noise_rng)
	# Note 2 will be scheduled by StingPlayer's mini-sequencer; for now play together
	# but with slightly longer ADSR so it sticks out.
	voice_pool.note_on(VoicePool.OSC_SQUARE, Harmony.midi_to_freq(int(chord[1])),
		[220, 2205, 0.0, 441], 0.45, &"sting", noise_rng)

## fanfare: 4-note ascending arpeggio of current chord (sine, ~1.2 s)
static func dispatch_fanfare(voice_pool: VoicePool, harmony: Harmony,
		noise_rng: RandomNumberGenerator) -> void:
	# Fire all 4 notes with staggered short attacks to suggest sequence.
	var chord: Array = harmony.get_chord_tones(0)
	# Root, third, fifth, octave
	var midis: Array = [int(chord[0]), int(chord[1]), int(chord[2]),
						int(chord[0]) + 12]
	for i in midis.size():
		var attack_extra: int = i * 882   # 40 ms stagger per note
		voice_pool.note_on(VoicePool.OSC_SINE, Harmony.midi_to_freq(midis[i]),
			[attack_extra + 44, 441, 0.0, 882], 0.55, &"sting", noise_rng)

## descending: three notes down minor scale (triangle, ~1.0 s, slow attack)
static func dispatch_descending(voice_pool: VoicePool, harmony: Harmony,
		noise_rng: RandomNumberGenerator) -> void:
	var scale: Array = harmony.get_scale_tones(0)
	var pick: Array  = [int(scale[4]), int(scale[2]), int(scale[0])]   # 5th, 3rd, root
	for i in pick.size():
		var offset: int = i * 2205   # 100 ms stagger
		voice_pool.note_on(VoicePool.OSC_TRIANGLE, Harmony.midi_to_freq(pick[i]),
			[offset + 441, 441, 0.4, 2205], 0.4, &"sting", noise_rng)

## ping: one sine with a second delayed copy (reverb imitation, ~0.5 s)
static func dispatch_ping(voice_pool: VoicePool, harmony: Harmony,
		noise_rng: RandomNumberGenerator) -> void:
	var root: int   = harmony.current_root()
	var freq: float = Harmony.midi_to_freq(root + 12)
	voice_pool.note_on(VoicePool.OSC_SINE, freq,
		[44, 220, 0.0, 4410], 0.5, &"sting", noise_rng)
	# Quieter repeat — simulated echo via long attack on second voice.
	voice_pool.note_on(VoicePool.OSC_SINE, freq,
		[2205, 220, 0.0, 4410], 0.2, &"sting", noise_rng)
