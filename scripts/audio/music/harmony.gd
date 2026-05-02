## Harmony — A natural minor progression Am–F–C–G cycling every 4 bars.
## Provides chord tones and scale tones for generators.
##
## MIDI note number 69 = A4 (440 Hz). Octave offsets shift root up/down.

class_name Harmony

# Progression: [root_midi, [interval0, interval1, interval2]]
# Root MIDI values: A=21+48=69 (A4), F=65 (F4), C=60 (C4), G=67 (G4)
const PROGRESSION_AM: Array = [
	[69, [0, 3, 7]],   # A minor:  A  C  E
	[65, [0, 4, 7]],   # F major:  F  A  C
	[60, [0, 4, 7]],   # C major:  C  E  G
	[67, [0, 4, 7]],   # G major:  G  B  D
]

# A natural minor scale intervals from root A (MIDI offsets within octave)
const SCALE_MINOR: Array = [0, 2, 3, 5, 7, 8, 10]

var _current_chord_idx: int = 0
var _rng: RandomNumberGenerator = null   # not used by Harmony itself, placeholder

func reset(_seed: int) -> void:
	_current_chord_idx = 0

## Called by MusicDirector on each bar event.
func tick_bar(bar_idx: int) -> void:
	_current_chord_idx = bar_idx % 4

## Returns MIDI note numbers for current chord, transposed by octave_offset semitones.
func get_chord_tones(octave_offset: int = 0) -> Array:
	var entry: Array = PROGRESSION_AM[_current_chord_idx]
	var root: int    = int(entry[0]) + octave_offset
	var intervals    = entry[1]
	var out: Array   = []
	for interval in intervals:
		out.append(root + int(interval))
	return out

## Returns full A minor scale tones (7 notes) starting at root + octave_offset.
func get_scale_tones(octave_offset: int = 0) -> Array:
	var root: int  = int(PROGRESSION_AM[_current_chord_idx][0]) + octave_offset
	var out: Array = []
	for interval in SCALE_MINOR:
		out.append(root + int(interval))
	return out

## Current root MIDI (no offset).
func current_root() -> int:
	return int(PROGRESSION_AM[_current_chord_idx][0])

## Convert MIDI note number to frequency (Hz).
static func midi_to_freq(midi: int) -> float:
	return 440.0 * pow(2.0, float(midi - 69) / 12.0)
