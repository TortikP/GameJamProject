## BassPatterns — table of bass note offsets per beat-in-bar.
## Each pattern: Array[4] of int — semitone offset from chord root (or -1 = rest).
## Octave offset (-12) is applied separately by BassGen.
##
## Useful offsets within a chord:
##   0  = root
##   3  = minor 3rd
##   4  = major 3rd
##   7  = fifth
##   12 = octave
##   -1 = REST (no note this beat)
##
## Add patterns here freely.

class_name BassPatterns

const DEFAULT_ID: StringName = &"root_fifth"
const REST: int = 0xDEAD   # sentinel — using -1 collides with semitone math

const PATTERNS: Dictionary = {
	# Root every beat. Driving, simple.
	&"root":         [0, 0, 0, 0],
	# Root on 1, 3 — fifth on 2, 4. Classic. (Was the only pattern in v1.)
	&"root_fifth":   [0, 7, 0, 7],
	# Walking: root, third, fifth, octave. Jazzy.
	&"walking":      [0, 3, 7, 12],
	# Syncopated: root, rest, fifth, root-an-octave-up. Sparse, tense.
	&"syncopated":   [0, REST, 7, 12],
}

static func get_pattern(id: StringName) -> Array:
	if PATTERNS.has(id):
		return PATTERNS[id]
	return PATTERNS[DEFAULT_ID]

static func list_ids() -> Array:
	var ids: Array = []
	for k in PATTERNS.keys():
		ids.append(String(k))
	ids.sort()
	return ids
