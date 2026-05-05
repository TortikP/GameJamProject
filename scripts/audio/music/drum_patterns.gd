## DrumPatterns — pattern table for DrumsGen.
## Each pattern is a Dictionary {beat_in_bar: [event,...]} where event is
##   &"kick" | &"snare" | &"hat".
## Beats are 0-based (0..3 in 4/4). Beat 0 = downbeat.
##
## Add new patterns here freely — DrumsGen looks them up by StringName.

class_name DrumPatterns

const DEFAULT_ID: StringName = &"march"

const PATTERNS: Dictionary = {
	# Classic march: kick on 1 & 3, hat on 2 & 4.
	&"march": {
		0: [&"kick"],
		1: [&"hat"],
		2: [&"kick"],
		3: [&"hat"],
	},
	# Driving four-on-the-floor: kick every beat, hat on offbeats (via snare on 2, 4).
	&"drive": {
		0: [&"kick"],
		1: [&"kick", &"snare"],
		2: [&"kick"],
		3: [&"kick", &"snare"],
	},
	# Halftime: kick on 1, snare on 3, hat on 2 & 4 — slow, heavy.
	&"halftime": {
		0: [&"kick"],
		1: [&"hat"],
		2: [&"snare"],
		3: [&"hat"],
	},
	# Tribal: syncopated, kick on 1 & 4 (offbeat feel), snare/hat scattered.
	&"tribal": {
		0: [&"kick"],
		1: [&"snare"],
		2: [&"hat"],
		3: [&"kick", &"hat"],
	},
}

static func get_pattern(id: StringName) -> Dictionary:
	if PATTERNS.has(id):
		return PATTERNS[id]
	return PATTERNS[DEFAULT_ID]

static func list_ids() -> Array:
	var ids: Array = []
	for k in PATTERNS.keys():
		ids.append(String(k))
	ids.sort()
	return ids
