## DialogueLine — immutable data-class for a single dialogue entry.
## No class_name — use explicit preload in consumers.
## Usage: var line = DialogueLine.from_dict(d)

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

## Required fields
var id: StringName
var speaker: StringName
var text: String

## Optional display
var portrait: String        # path or "" (null from JSON becomes "")
var image: String           # path or ""
var text_fx: String         # reserved, no-op + warn if set

## Audio
var audio_layer: String     # "sfx" | "ai_voice" | "human" | ""
var audio_clip: String      # path or ""

## Selector metadata
var tags: Array[StringName]
var priority: int
var conditions: Dictionary  # min_run, max_run, flags_required, flags_forbidden
var once_per_run: bool
var once_per_session: bool

## Navigation
var next: StringName        # id or &""
var choices: Array          # Array[Dictionary{label, next}]


static func from_dict(d: Dictionary) -> Object:
	var line := load("res://scripts/core/dialogue/dialogue_line.gd").new()

	# Validate required fields
	if not d.has("id") or str(d["id"]).strip_edges() == "":
		GameLogger.warn("DialogueLine", "missing 'id' in dict — skip")
		return null
	if not d.has("speaker") or str(d["speaker"]).strip_edges() == "":
		GameLogger.warn("DialogueLine", "missing 'speaker' in '%s' — skip" % d.get("id", "?"))
		return null
	if not d.has("text"):
		GameLogger.warn("DialogueLine", "missing 'text' in '%s' — skip" % d.get("id", "?"))
		return null

	line.id              = StringName(str(d["id"]))
	line.speaker         = StringName(str(d["speaker"]))
	line.text            = str(d["text"])
	line.portrait        = str(d.get("portrait", "")) if d.get("portrait") != null else ""
	line.image           = str(d.get("image", "")) if d.get("image") != null else ""
	line.text_fx         = str(d.get("text_fx", "")) if d.get("text_fx") != null else ""
	line.audio_layer     = str(d.get("audio_layer", "")) if d.get("audio_layer") != null else ""
	line.audio_clip      = str(d.get("audio_clip", "")) if d.get("audio_clip") != null else ""
	line.priority        = int(d.get("priority", 0))
	line.once_per_run    = bool(d.get("once_per_run", false))
	line.once_per_session = bool(d.get("once_per_session", false))
	line.next            = StringName(str(d["next"])) if d.get("next") != null else &""

	# tags
	line.tags = [] as Array[StringName]
	for t in d.get("tags", []):
		line.tags.append(StringName(str(t)))

	# conditions with defaults
	var cond: Dictionary = d.get("conditions", {})
	line.conditions = {
		"min_run":         int(cond.get("min_run", 0)),
		"max_run":         int(cond.get("max_run", 999)),
		"flags_required":  cond.get("flags_required", []),
		"flags_forbidden": cond.get("flags_forbidden", []),
	}

	# choices
	line.choices = []
	for ch in d.get("choices", []):
		line.choices.append({
			"label": str(ch.get("label", "")),
			"next":  StringName(str(ch["next"])) if ch.get("next") != null else &"",
		})
	if line.choices.size() > 3:
		GameLogger.warn("DialogueLine", "'%s' has %d choices — max 3; extras ignored" % [line.id, line.choices.size()])
		line.choices = line.choices.slice(0, 3)

	# Warn on reserved features
	if line.text_fx != "":
		GameLogger.warn("DialogueLine", "'%s' uses text_fx '%s' — reserved, no-op" % [line.id, line.text_fx])
	if line.image != "":
		pass  # image slot is supported visually, no warn needed

	# Warn if both choices and next are set
	if line.choices.size() > 0 and line.next != &"":
		GameLogger.warn("DialogueLine", "'%s' has both choices and next — next ignored (choices win)" % line.id)
		line.next = &""

	return line
