## VoicePool — 6-voice polyphony. Each voice = oscillator + ADSR + layer gain.
## All voices pre-allocated; no new() in hot path.
##
## Oscillator types (int constants):
##   OSC_SINE = 0, OSC_TRIANGLE = 1, OSC_SQUARE = 2, OSC_NOISE = 3
##
## Layers: StringName — "bass" / "pad" / "lead" / "drums" / "sting"
## Layer gains are queried from StateMixer per mix call.

class_name VoicePool

const OSC_SINE:     int = 0
const OSC_TRIANGLE: int = 1
const OSC_SQUARE:   int = 2
const OSC_NOISE:    int = 3

const POOL_SIZE: int = 6
const MIX_RATE:  int = 22050

## External reference set by MusicDirector.
var state_mixer: StateMixer = null

class Voice:
	var active:    bool       = false
	var osc:       int        = 0
	var freq:      float      = 440.0
	var phase:     float      = 0.0
	var phase_inc: float      = 0.0
	var adsr:      ADSR
	var gain:      float      = 1.0
	var layer:     StringName = &""
	var birth_sample: int     = 0   # for steal heuristic
	var noise_rng:    RandomNumberGenerator  # shared ref from Director
	# noise_rng is same instance across voices; ADSR state keeps them out of sync.

	func _init() -> void:
		adsr = ADSR.new()

var _voices: Array = []   # Array[Voice] — typed array issues with Resource → plain Array
var _global_sample: int = 0

func _init() -> void:
	for _i in POOL_SIZE:
		_voices.append(Voice.new())

## Reset all voices (e.g. on level load).
func reset() -> void:
	for v: Voice in _voices:
		v.active = false
		v.phase  = 0.0
	_global_sample = 0

## Trigger a new note. Returns voice index or -1 if steal failed (shouldn't happen).
## adsr_params: [attack_smp, decay_smp, sustain, release_smp]
func note_on(osc: int, freq: float, adsr_params: Array, gain: float,
		layer: StringName, noise_rng: RandomNumberGenerator) -> int:
	# Find free slot.
	var slot: int = _find_free_slot()
	var v: Voice = _voices[slot]
	v.active        = true
	v.osc           = osc
	v.freq          = freq
	v.phase_inc     = freq / float(MIX_RATE)
	v.phase         = 0.0
	v.gain          = gain
	v.layer         = layer
	v.birth_sample  = _global_sample
	v.noise_rng     = noise_rng
	v.adsr.setup(int(adsr_params[0]), int(adsr_params[1]),
			float(adsr_params[2]), int(adsr_params[3]))
	v.adsr.gate_on()
	return slot

## Release a voice by index (begin release phase).
func release(id: int) -> void:
	if id < 0 or id >= POOL_SIZE:
		return
	_voices[id].adsr.gate_off()

## Release all voices on a given layer (e.g. pad changes chord).
func release_all_layer(layer: StringName) -> void:
	for v: Voice in _voices:
		if v.active and v.layer == layer:
			v.adsr.gate_off()

## Mix all active voices into buf[0..n-1]. buf is PackedVector2Array (stereo).
func mix(buf: PackedVector2Array, n: int) -> void:
	for v: Voice in _voices:
		if not v.active:
			continue
		var layer_gain: float = 1.0
		if state_mixer != null:
			layer_gain = state_mixer.get_layer_gain(v.layer)

		for i in n:
			var env: float = v.adsr.tick()
			if env <= 0.0 and v.adsr.is_finished():
				v.active = false
				break
			var s: float
			match v.osc:
				OSC_SINE:     s = WaveTables.sine(v.phase)
				OSC_TRIANGLE: s = WaveTables.triangle(v.phase)
				OSC_SQUARE:   s = WaveTables.square(v.phase)
				OSC_NOISE:    s = v.noise_rng.randf_range(-1.0, 1.0)
				_:            s = 0.0
			s *= env * v.gain * layer_gain
			buf[i] += Vector2(s, s)
			v.phase = fmod(v.phase + v.phase_inc, 1.0)

	_global_sample += n

# ── Private ──────────────────────────────────────────────────────────────────

func _find_free_slot() -> int:
	# 1. Find IDLE / DONE voice.
	for i in POOL_SIZE:
		var v: Voice = _voices[i]
		if not v.active or v.adsr.is_finished():
			return i
	# 2. Steal oldest voice in Release.
	var oldest_release: int = -1
	var oldest_birth:   int = 0x7fffffff
	for i in POOL_SIZE:
		var v: Voice = _voices[i]
		if v.adsr._phase == ADSR.Phase.RELEASE and v.birth_sample < oldest_birth:
			oldest_release = i
			oldest_birth   = v.birth_sample
	if oldest_release >= 0:
		return oldest_release
	# 3. Steal oldest any voice.
	var oldest: int = 0
	for i in POOL_SIZE:
		if _voices[i].birth_sample < _voices[oldest].birth_sample:
			oldest = i
	return oldest
