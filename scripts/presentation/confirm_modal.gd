extends CanvasLayer
## ConfirmModal — overlays a centered panel with title / body / Confirm+Cancel
## buttons. Pauses the world while open.
##
## Usage (awaitable):
##   var ok: bool = await confirm_modal.ask("Quit run?", "Progress will be lost.")
##   if ok: ...
##
## Pauses via setup_modal_pause helper. Pause is released on close (single
## modal stack — multiple confirms in flight aren't supported; jam scope).

const UiHelpers = preload("res://scripts/presentation/ui_signal_helpers.gd")
const MODAL_ID: StringName = &"confirm_modal"

signal answered(ok: bool)

@onready var _panel: PanelContainer = $Center/Panel
@onready var _title_label: Label = $Center/Panel/VBox/TitleLabel
@onready var _body_label: Label = $Center/Panel/VBox/BodyLabel
@onready var _confirm_btn: Button = $Center/Panel/VBox/ButtonRow/ConfirmButton
@onready var _cancel_btn: Button = $Center/Panel/VBox/ButtonRow/CancelButton

var _danger: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	_confirm_btn.pressed.connect(_on_confirm)
	_cancel_btn.pressed.connect(_on_cancel)


func _apply_theme() -> void:
	if _panel:
		_panel.add_theme_stylebox_override("panel", UiTheme.make_modal_stylebox())
	UiTheme.apply_label_kind(_title_label, "header")
	UiTheme.apply_label_kind(_body_label, "body")
	UiTheme.apply_button_styling(_cancel_btn)
	UiTheme.apply_button_styling(_confirm_btn)
	# Highlight confirm button — focus tint normally, danger color when destructive.
	if _danger:
		_confirm_btn.add_theme_color_override("font_color", UiTheme.SEM_DAMAGE)
	else:
		_confirm_btn.add_theme_color_override("font_color", UiTheme.FOCUS)


## Show the modal and await the user's choice. Returns true on Confirm,
## false on Cancel (or ESC).
func ask(title: String, body: String, confirm_label: String = "OK",
		cancel_label: String = "Cancel", danger: bool = false) -> bool:
	_title_label.text = Localization.t(title, title)
	_body_label.text = Localization.t(body, body)
	_confirm_btn.text = Localization.t(confirm_label, confirm_label)
	_cancel_btn.text = Localization.t(cancel_label, cancel_label)
	_danger = danger
	_apply_theme()  # repaint confirm button color for danger state
	visible = true
	UiHelpers.emit_modal_opened(MODAL_ID, true)
	_confirm_btn.grab_focus()
	var ok: bool = await answered
	visible = false
	UiHelpers.emit_modal_closed(MODAL_ID, true)
	return ok


func _on_confirm() -> void:
	answered.emit(true)


func _on_cancel() -> void:
	answered.emit(false)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_cancel()
		elif k == KEY_ENTER or k == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_on_confirm()
