class_name DialogueTrigger
## Pure value object: one entry in LevelData.dialogue_triggers[].
## No Node, no signals. Converted from/to Dictionary for JSON storage.
## Owner: 039-dialogue-triggers (Andrey).

const VALID_PLAY_MODES: Array[String] = ["request", "play"]

var id: StringName = &""
var event: StringName = &""
var dialogue_id: StringName = &""
var play_mode: String = "request"
var conditions: Dictionary = {}


static func from_dict(d: Dictionary) -> DialogueTrigger:
	var t := DialogueTrigger.new()
	t.id = StringName(str(d.get("id", "")))
	t.event = StringName(str(d.get("event", "")))
	t.dialogue_id = StringName(str(d.get("dialogue_id", "")))
	t.play_mode = str(d.get("play_mode", "request"))
	t.conditions = d.get("conditions", {}) as Dictionary
	return t


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"event": String(event),
		"dialogue_id": String(dialogue_id),
		"play_mode": play_mode,
		"conditions": conditions.duplicate(),
	}


## Returns array of error/warning strings. Empty = valid.
## Warnings are prefixed "WARN: " and don't block save.
## Hard errors block save.
func validate() -> Array[String]:
	var errs: Array[String] = []
	if id == &"":
		errs.append(Localization.t("ui_dialogue_validate_id_empty", "trigger id must not be empty"))
	if event == &"":
		errs.append(Localization.tf("ui_dialogue_validate_event_empty", [str(id)], "trigger '%s': event must not be empty"))
	if play_mode not in VALID_PLAY_MODES:
		errs.append(Localization.tf("ui_dialogue_validate_play_mode_invalid", [str(id), play_mode], "trigger '%s': play_mode '%s' invalid (expected request|play)"))
	var c: Dictionary = conditions
	if c.has("chance"):
		var ch: float = float(c["chance"])
		if ch < 0.0 or ch > 1.0:
			errs.append(Localization.tf("ui_dialogue_validate_chance_range", [str(id), ch], "trigger '%s': chance %f out of [0.0, 1.0]"))
	if c.has("absolute_turn"):
		if int(c["absolute_turn"]) < 0:
			errs.append(Localization.tf("ui_dialogue_validate_absolute_turn", [str(id)], "trigger '%s': absolute_turn must be >= 0"))
	# Condition applicability warnings
	if c.has("cleared_in_turns_lt") and event != &"wave_cleared":
		errs.append("WARN: " + Localization.tf("ui_dialogue_validate_cleared_turns_event", [str(id)], "trigger '%s': cleared_in_turns_lt only applies to wave_cleared event"))
	if c.has("absolute_turn") and event != &"world_turn_ended":
		errs.append("WARN: " + Localization.tf("ui_dialogue_validate_absolute_turn_event", [str(id)], "trigger '%s': absolute_turn only applies to world_turn_ended event"))
	# dialogue_id existence validated at LevelData level (needs DialogueDB access)
	return errs
