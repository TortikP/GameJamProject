## StateMixer — manages per-layer target gains and smooth ramps between states.
## Ramp speed: target reached over 1 bar (tick_bar() advances by one step).
## VoicePool queries get_layer_gain() per voice sample.
##
## Layers: &"bass" / &"pad" / &"lead" / &"drums" / &"sting"
## States: &"calm" / &"battle" / &"menu" / &"stopped"

class_name StateMixer

# State → {layer → target_gain}
const STATE_GAINS: Dictionary = {
	&"calm": {
		&"bass":  1.0,
		&"pad":   1.0,
		&"lead":  1.0,
		&"drums": 0.0,
		&"sting": 1.0,
	},
	&"battle": {
		&"bass":  1.0,
		&"pad":   1.0,
		&"lead":  1.0,
		&"drums": 1.0,
		&"sting": 1.0,
	},
	&"menu": {
		&"bass":  1.0,
		&"pad":   1.0,
		&"lead":  0.6,
		&"drums": 0.0,
		&"sting": 1.0,
	},
	&"stopped": {
		&"bass":  0.0,
		&"pad":   0.0,
		&"lead":  0.0,
		&"drums": 0.0,
		&"sting": 0.0,
	},
}

const RAMP_BARS: int = 1   # transition completes in N bars

var _current: Dictionary = {}     # {layer → current_gain}
var _target:  Dictionary = {}     # {layer → target_gain}
var _step:    Dictionary = {}     # {layer → step_per_bar}
var _state: StringName = &"stopped"

# Per-layer dB overrides (from music_config).
var _layer_db: Dictionary = {}    # {layer → db_offset}

func _init() -> void:
	var layers: Array = [&"bass", &"pad", &"lead", &"drums", &"sting"]
	for l in layers:
		_current[l] = 0.0
		_target[l]  = 0.0
		_step[l]    = 0.0

## Apply new state. Targets update immediately; actual gain ramps via tick_bar().
func set_state(state: StringName) -> void:
	_state = state
	var gains: Dictionary = STATE_GAINS.get(state, STATE_GAINS[&"stopped"])
	for layer in _target.keys():
		var tgt: float = float(gains.get(layer, 0.0)) * _db_to_linear(layer)
		_target[layer] = tgt
		var diff: float = tgt - _current[layer]
		_step[layer] = diff / float(RAMP_BARS) if RAMP_BARS > 0 else diff

## Set dB override for a layer (called from per-level config).
## Applied on top of state gain.
func set_layer_db(layer: StringName, db: float) -> void:
	_layer_db[layer] = db
	# Recompute target with new db.
	set_state(_state)

## Called once per bar by Conductor flow in MusicDirector. Steps gains toward target.
func tick_bar() -> void:
	for layer in _current.keys():
		var cur: float = _current[layer]
		var tgt: float = _target[layer]
		if absf(tgt - cur) < 0.001:
			_current[layer] = tgt
		else:
			_current[layer] = cur + _step[layer]
			_current[layer] = clampf(_current[layer], 0.0, 2.0)

## VoicePool calls this per sample per voice.
func get_layer_gain(layer: StringName) -> float:
	return _current.get(layer, 0.0)

# ── Private ──────────────────────────────────────────────────────────────────

func _db_to_linear(layer: StringName) -> float:
	var db: float = float(_layer_db.get(layer, 0.0))
	return pow(10.0, db / 20.0)
