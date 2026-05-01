extends CanvasLayer
## LoadingCover — fullscreen color rect with a centered label. Shown during
## scene transitions / async loads. NOT pause-triggering (it's a transient
## cover, not a modal — see plan.md §"Pause coordination").

@onready var _label: Label = $Center/Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)


func _apply_theme() -> void:
	UiTheme.apply_label_kind(_label, "header")


func show_with_text(text: String) -> void:
	_label.text = text
	visible = true


func hide() -> void:
	visible = false
