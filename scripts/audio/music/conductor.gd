## Conductor — sample-accurate beat/bar clock.
## Converts BPM → samples-per-beat. advance(n) returns events fired in that window.
## No allocations in hot path: reuses _events array (cleared each call).
##
## Event shape: [kind: StringName, idx: int]
##   kind ∈ { &"beat", &"bar" }

class_name Conductor

const MIX_RATE: int = 11025
const BEATS_PER_BAR: int = 4

var bpm: float = 96.0
var samples_per_beat: float = 0.0

var _sample_pos: int = 0     # absolute samples since last reset
var _beat_idx:   int = -1    # last beat index emitted
var _bar_idx:    int = -1    # last bar index emitted

var _events: Array = []       # reused each advance() call

func reset(new_bpm: float, _seed: int) -> void:
	bpm             = clampf(new_bpm, 40.0, 200.0)
	samples_per_beat = 60.0 / bpm * float(MIX_RATE)
	_sample_pos     = 0
	_beat_idx       = -1
	_bar_idx        = -1

## Advance clock by num_samples. Returns Array of [kind, idx] events
## that fall within [sample_pos, sample_pos + num_samples).
## The returned Array is reused each call — copy if needed across frames.
func advance(num_samples: int) -> Array:
	_events.clear()
	var end_pos: int = _sample_pos + num_samples

	while true:
		var next_beat_sample: int = int(float(_beat_idx + 1) * samples_per_beat)
		if next_beat_sample >= end_pos:
			break
		_beat_idx += 1
		_events.append([&"beat", _beat_idx])

		var bar: int = _beat_idx / BEATS_PER_BAR
		if bar > _bar_idx:
			_bar_idx = bar
			_events.append([&"bar", _bar_idx])

	_sample_pos = end_pos
	return _events

## Samples elapsed since reset (for determinism checks).
func sample_pos() -> int:
	return _sample_pos

## Current beat index (−1 before first beat).
func current_beat() -> int:
	return _beat_idx

## Current bar index (−1 before first bar).
func current_bar() -> int:
	return _bar_idx
