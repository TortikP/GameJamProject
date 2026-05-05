## ADSR envelope. Sample-accurate, no allocations in hot path.
## Caller: create once, call gate_on() before use, tick() per sample.
##
## All timings in *samples* — Conductor converts ms → samples using MIX_RATE.

class_name ADSR

enum Phase { IDLE, ATTACK, DECAY, SUSTAIN, RELEASE, DONE }

var attack_samples: int  = 441   # 20 ms @ 22050
var decay_samples: int   = 2205  # 100 ms
var sustain_level: float = 0.7
var release_samples: int = 4410  # 200 ms

var _phase: int = Phase.IDLE
var _counter: int = 0
var _level: float = 0.0

# ── Init helpers ─────────────────────────────────────────────────────────────

## Configure and immediately gate on.
func setup(a_smp: int, d_smp: int, sustain: float, r_smp: int) -> void:
	attack_samples  = maxi(a_smp, 1)
	decay_samples   = maxi(d_smp, 1)
	sustain_level   = clampf(sustain, 0.0, 1.0)
	release_samples = maxi(r_smp, 1)

## Begin attack.
func gate_on() -> void:
	_phase   = Phase.ATTACK
	_counter = 0
	# Keep _level from previous value to avoid click if re-triggered mid-release.

## Begin release.
func gate_off() -> void:
	if _phase == Phase.IDLE or _phase == Phase.DONE:
		return
	_phase   = Phase.RELEASE
	_counter = 0

func is_finished() -> bool:
	return _phase == Phase.DONE

func is_active() -> bool:
	return _phase != Phase.IDLE and _phase != Phase.DONE

# ── Tick ─────────────────────────────────────────────────────────────────────

## Returns current envelope value [0, 1]. Advances state by 1 sample.
func tick() -> float:
	match _phase:
		Phase.IDLE, Phase.DONE:
			return 0.0

		Phase.ATTACK:
			_level = float(_counter) / float(attack_samples)
			_counter += 1
			if _counter >= attack_samples:
				_phase   = Phase.DECAY
				_counter = 0
				_level   = 1.0

		Phase.DECAY:
			var t: float = float(_counter) / float(decay_samples)
			_level = lerp(1.0, sustain_level, t)
			_counter += 1
			if _counter >= decay_samples:
				_phase   = Phase.SUSTAIN
				_counter = 0
				_level   = sustain_level

		Phase.SUSTAIN:
			_level = sustain_level

		Phase.RELEASE:
			# Snapshot release start level on first tick.
			if _counter == 0:
				_release_start = _level
			var t: float = float(_counter) / float(release_samples)
			_level = lerp(_release_start, 0.0, t)
			_counter += 1
			if _counter >= release_samples:
				_phase = Phase.DONE
				_level = 0.0

	return _level

# Private: snapshot of level at gate_off for smooth release from any point.
var _release_start: float = 0.0
