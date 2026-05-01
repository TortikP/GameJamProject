extends PanelContainer
## ToastItem — single toast notification. Auto-dismisses after `duration_sec`,
## emits dismissed when removed. ToastLayer manages the stack.

signal dismissed

@onready var _stripe: ColorRect = $HBox/LevelStripe
@onready var _text_label: Label = $HBox/TextLabel

var _level: StringName = &"info"


func _ready() -> void:
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)


func _apply_theme() -> void:
	add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox(true))
	UiTheme.apply_label_kind(_text_label, "body")
	_stripe.color = _stripe_color_for(_level)


func _stripe_color_for(level: StringName) -> Color:
	match level:
		&"success":
			return UiTheme.SEM_HEAL
		&"warn":
			return UiTheme.SEM_DEBUFF
		&"error":
			return UiTheme.SEM_DAMAGE
	return UiTheme.SEM_BUFF  # info → buff blue


## Setup + start the dismiss timer. duration_sec ≤ 0 → never auto-dismiss.
func setup(text: String, duration_sec: float, level: StringName) -> void:
	_level = level
	_text_label.text = text
	if _stripe != null:
		_stripe.color = _stripe_color_for(level)
	# Fade-in via modulate
	modulate.a = 0.0
	var fade_in := create_tween()
	var fade_in_sec: float = float(GameSpeed.get_value("ui", "toast_fade_in_sec", 0.18))
	fade_in.tween_property(self, "modulate:a", 1.0, fade_in_sec)
	if duration_sec > 0.0:
		var dismiss_timer := get_tree().create_timer(duration_sec, true, false, true)
		dismiss_timer.timeout.connect(_dismiss)


func _dismiss() -> void:
	var fade_out := create_tween()
	var fade_out_sec: float = float(GameSpeed.get_value("ui", "toast_fade_out_sec", 0.20))
	fade_out.tween_property(self, "modulate:a", 0.0, fade_out_sec)
	fade_out.tween_callback(func():
		dismissed.emit()
		queue_free()
	)
