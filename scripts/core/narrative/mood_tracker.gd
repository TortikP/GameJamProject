extends Node
## MoodTracker — narrative character tracker driven by equipped player skills.
##
## State derived from current Skill list (typically the player's slot-bar dedup'd
## copy via Actor._skills). Recomputed on every set_skills call from
## godmode_controller.sync_player_skills_from_slots; no listeners on its own.
##
## Per-skill weight = 1 + max(0, skill.level). Current world (level=0 across all
## JSONs) → weight=1. Future single-instance-per-slot model: duplicate pickups
## bump level on the existing slot copy → mood contribution scales 1:1.
##
## Consumer (DialogueManager line picker) reads via get_dominant() or the
## EventBus.player_mood_changed signal. Out of scope here — see spec 038.
##
## Vocabulary (canonical, code-side):
##   - MOODS_SKILL: neutral / tranquility / burnout / ascended — attachable to skills.
##   - MOOD_CHIMERA: chimera — meta-only, returned by get_dominant on a tie
##     between non-zero leaders. Never appears on a Skill.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const MOODS_SKILL: Array[StringName] = [&"neutral", &"tranquility", &"burnout", &"ascended"]
const MOOD_CHIMERA: StringName = &"chimera"

var _counts: Dictionary = {}             # StringName -> int, keys = MOODS_SKILL
var _prev_counts: Dictionary = {}        # snapshot before last recompute, for delta logging
var _prev_dominant: StringName = &""     # empty before first recompute → suppresses transition log
var _warned_unknown: Dictionary = {}     # StringName "skill_id/mood" -> true, warn-once dedup


func _ready() -> void:
	_zero_counts()
	_prev_counts = _counts.duplicate()


## Recompute mood counters from a deduped skills list and emit
## EventBus.player_mood_changed. Called by godmode_controller after every
## slot-bar mutation. Empty list → all zeros → dominant = neutral.
func recompute_from_skills(skills: Array) -> void:
	_prev_counts = _counts.duplicate()
	_zero_counts()
	for s in skills:
		var sk: Skill = s as Skill
		if sk == null:
			continue
		# Weight scales 1:1 with skill.level, +1 base. maxi(0, level) is
		# defensive against negative level data.
		var weight: int = 1 + maxi(0, sk.level)
		for m in sk.mood:
			var key: StringName = m
			if MOODS_SKILL.has(key):
				_counts[key] = (_counts[key] as int) + weight
			else:
				_warn_unknown(sk.id, key)
	var dom: StringName = get_dominant()
	_log_change(dom)
	_prev_dominant = dom
	EventBus.player_mood_changed.emit(get_counts(), dom)


## Returns a defensive copy of the count map. Keys are always all of MOODS_SKILL
## (zero-filled if a mood has no contributors). Chimera is never in the map.
func get_counts() -> Dictionary:
	return _counts.duplicate()


## Picks one mood from MOODS_SKILL ∪ {chimera}.
##   all-zero       → neutral
##   single max > 0 → that mood
##   multi max  > 0 → chimera (tie-breaker, "mixed character")
func get_dominant() -> StringName:
	var max_v: int = 0
	for m in MOODS_SKILL:
		var v: int = _counts[m]
		if v > max_v:
			max_v = v
	if max_v == 0:
		return &"neutral"
	var winners: Array[StringName] = []
	for m in MOODS_SKILL:
		if (_counts[m] as int) == max_v:
			winners.append(m)
	if winners.size() > 1:
		return MOOD_CHIMERA
	return winners[0]


# ── Internals ────────────────────────────────────────────────────────────────

func _zero_counts() -> void:
	for m in MOODS_SKILL:
		_counts[m] = 0


# Compact one-liner with per-channel deltas. Goes to Godot's output console
# via GameLogger → print(). WARN level on dominant flip so it stands out
# in a noisy combat log; INFO otherwise.
func _log_change(dom: StringName) -> void:
	var parts: Array[String] = []
	for m in MOODS_SKILL:
		var cur: int = _counts[m]
		var prev: int = int(_prev_counts.get(m, 0))
		if cur == prev:
			parts.append("%s=%d" % [m, cur])
		else:
			parts.append("%s=%d(%+d)" % [m, cur, cur - prev])
	var line: String = "%s | dominant=%s" % [", ".join(parts), dom]
	if _prev_dominant != &"" and _prev_dominant != dom:
		GameLogger.warn("MoodTracker", "DOMINANT %s → %s | %s" % [_prev_dominant, dom, line])
	else:
		GameLogger.info("MoodTracker", line)


func _warn_unknown(skill_id: StringName, mood: StringName) -> void:
	var key: StringName = StringName("%s/%s" % [skill_id, mood])
	if _warned_unknown.has(key):
		return
	_warned_unknown[key] = true
	GameLogger.warn("MoodTracker", "skill %s has unknown mood '%s' — skipped" % [skill_id, mood])
