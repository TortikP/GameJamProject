## Wavetables — static 256-sample lookup tables baked once at startup.
## Sine / triangle / square via nearest-neighbor phase lookup.
## Linear interp left for T-POLISH if perf allows.
##
## Usage:  WaveTables.sine(phase01)   phase01 ∈ [0, 1)
##         WaveTables.triangle(phase01)
##         WaveTables.square(phase01)

class_name WaveTables

const TABLE_SIZE: int = 256

static var _sine:     PackedFloat32Array
static var _triangle: PackedFloat32Array
static var _square:   PackedFloat32Array
static var _baked: bool = false

# ── Bake ────────────────────────────────────────────────────────────────────

## Call once before first use (MusicDirector._ready calls this).
static func bake() -> void:
	if _baked:
		return
	_baked = true

	_sine.resize(TABLE_SIZE)
	_triangle.resize(TABLE_SIZE)
	_square.resize(TABLE_SIZE)

	for i in TABLE_SIZE:
		var t: float = float(i) / float(TABLE_SIZE)

		# Sine
		_sine[i] = sin(t * TAU)

		# Triangle: 0→1 in first half, 1→-1 in second half
		if t < 0.5:
			_triangle[i] = 4.0 * t - 1.0
		else:
			_triangle[i] = 3.0 - 4.0 * t

		# Square: ±1
		_square[i] = 1.0 if t < 0.5 else -1.0

# ── Lookup ───────────────────────────────────────────────────────────────────

## phase01 ∈ [0, 1) — caller manages wrap via fmod.
static func sine(phase01: float) -> float:
	return _sine[int(phase01 * TABLE_SIZE) & (TABLE_SIZE - 1)]

static func triangle(phase01: float) -> float:
	return _triangle[int(phase01 * TABLE_SIZE) & (TABLE_SIZE - 1)]

static func square(phase01: float) -> float:
	return _square[int(phase01 * TABLE_SIZE) & (TABLE_SIZE - 1)]
