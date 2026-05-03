extends CanvasLayer
## KeybindOverlay — full-screen reference card listing all keybinds in two
## columns. Toggled by the `?` key (or `/` on US layout — same physical key).
##
## NOT pause-triggering — the overlay is reference material, the player can
## absorb it without freezing the world. Still gets emit_modal_opened so
## tooltips suppress while it's up (cleaner).

const UiHelpers = preload("res://scripts/presentation/ui_signal_helpers.gd")
const MODAL_ID: StringName = &"keybind_overlay"

const _BINDS: Array = [
	["QWER / 1234", "ui_keybind_cast_slots", "Cast slot 1-4"],
	["LMB",         "ui_keybind_cast_hex", "Cast at hex (with slot active)"],
	["RMB",         "ui_keybind_move_step", "Move 1 step"],
	["MMB drag",    "ui_keybind_pan_camera", "Pan camera (release to keep view)"],
	["Wheel",       "ui_keybind_zoom", "Zoom"],
	["C",           "ui_keybind_recenter", "Recenter on player"],
	["SPACE",       "ui_keybind_wait_turn", "Wait turn"],
	["ESC",         "ui_keybind_cancel_pause", "Cancel cast / open pause"],
	["L",           "ui_keybind_toggle_combat_log", "Toggle combat log"],
	["?",           "ui_keybind_toggle_overlay", "Toggle this overlay"],
	["F1",          "ui_keybind_spawn_dummy", "Spawn dummy (godmode)"],
	["F2",          "ui_keybind_clear_actors", "Clear actors (godmode)"],
	["F5",          "ui_keybind_reload_speed_config", "Reload speed config"],
	["F6",          "ui_keybind_toggle_crt", "Toggle CRT effect"],
]

@onready var _panel: PanelContainer = $Center/Panel
@onready var _title: Label = $Center/Panel/VBox/Title
@onready var _grid: GridContainer = $Center/Panel/VBox/Grid
@onready var _hint: Label = $Center/Panel/VBox/Hint


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	_build_grid()


func _apply_theme() -> void:
	if _panel:
		_panel.add_theme_stylebox_override("panel", UiTheme.make_modal_stylebox())
	UiTheme.apply_label_kind(_title, "header")
	UiTheme.apply_label_kind(_hint, "small")
	for c in _grid.get_children():
		if c is Label:
			UiTheme.apply_label_kind(c, "body")


func _build_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for pair in _BINDS:
		var key_lbl := Label.new()
		key_lbl.text = pair[0]
		UiTheme.apply_label_kind(key_lbl, "body")
		key_lbl.add_theme_color_override("font_color", UiTheme.FOCUS)
		_grid.add_child(key_lbl)
		var desc_lbl := Label.new()
		desc_lbl.text = Localization.t(String(pair[1]), String(pair[2]))
		UiTheme.apply_label_kind(desc_lbl, "body")
		_grid.add_child(desc_lbl)


func toggle() -> void:
	visible = not visible
	if visible:
		# Emit modal-opened (suppresses tooltips) but DO NOT pause world.
		EventBus.ui_modal_opened.emit(MODAL_ID)
	else:
		EventBus.ui_modal_closed.emit(MODAL_ID)


## Listen for `?` globally. Use _unhandled_input so other widgets get first dibs.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	if (event as InputEventKey).echo:
		return
	# `?` is shift+/ on US layout — match by unicode rather than keycode to
	# survive layout differences. ASCII 63 = '?'.
	if (event as InputEventKey).unicode == 63:
		get_viewport().set_input_as_handled()
		toggle()
