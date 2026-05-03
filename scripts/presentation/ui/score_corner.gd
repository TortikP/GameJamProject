extends Control

## ScoreCorner — minimal HUD widget showing RunScore.total in the top-right
## of the battle scene's CanvasLayer.
##
## On RunScore.score_changed → repaint label + run a punch tween (scale 1.0
## → 1.2 → 1.0 over GameSpeed ui.score_punch_sec). Anchored top-right via
## the .tscn so it stays put across resolution changes.
##
## Visibility doctrine (CLAUDE.md): UiTheme.FS_NUM_HUGE for the digits +
## strong outline so it reads against any background.

const UiThemeScript = preload("res://scripts/presentation/ui_theme.gd")

@onready var _label: Label = $Label

# Pivot for the punch tween — set on first ready, kept up to date if the
# label resizes (e.g. score grows from 1 to 4 digits).
var _last_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	if _label == null:
		return
	UiThemeScript.apply_label_kind(_label, "num_huge")
	UiThemeScript.apply_world_text_outline(_label)
	_label.text = str(RunScore.total)
	_update_pivot()
	# Connect via a guarded ready helper — RunScore is an autoload, so it's
	# always alive by the time this _ready fires.
	if not RunScore.score_changed.is_connected(_on_score_changed):
		RunScore.score_changed.connect(_on_score_changed)
	# 047: score lives in the bottom-right corner; the dialogue panel is
	# 280px tall full-width at the bottom and would cover the score
	# whenever a story beat fires. Hide for the duration of the beat,
	# show again when it ends. EventBus is an autoload — always alive.
	if EventBus.has_signal("dialogue_started") and not EventBus.dialogue_started.is_connected(_on_dialogue_started):
		EventBus.dialogue_started.connect(_on_dialogue_started)
	if EventBus.has_signal("dialogue_finished") and not EventBus.dialogue_finished.is_connected(_on_dialogue_finished):
		EventBus.dialogue_finished.connect(_on_dialogue_finished)


func _on_dialogue_started(_dialogue_id: StringName) -> void:
	visible = false


func _on_dialogue_finished(_dialogue_id: StringName) -> void:
	visible = true


func _on_score_changed(total: int, delta: int) -> void:
	if _label == null:
		return
	_label.text = str(total)
	_update_pivot()
	if delta != 0:
		_punch()


func _update_pivot() -> void:
	# Center pivot inside the label's text bounds so the tween scales
	# around the digit rather than from the top-left corner.
	if _label == null:
		return
	if _label.size != _last_size:
		_last_size = _label.size
		_label.pivot_offset = _label.size * 0.5


func _punch() -> void:
	if _label == null:
		return
	var dur: float = float(GameSpeed.get_value("ui", "score_punch_sec", 0.25))
	var t: Tween = create_tween()
	t.tween_property(_label, "scale", Vector2(1.2, 1.2), dur * 0.5)
	t.tween_property(_label, "scale", Vector2(1.0, 1.0), dur * 0.5)
