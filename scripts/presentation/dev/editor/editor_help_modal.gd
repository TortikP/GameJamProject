class_name EditorHelpModal
extends BasePanel

## Hardcoded keyboard-shortcut reference for the level editor. Opens
## via show_help() from EditorController on F1 / ?. Closes on Esc / F1
## / ? (any of the open keys also closes — convenient toggle).
##
## Not a true modal (doesn't pause the editor) — just a panel that
## floats above the rest of the HUD. The user can keep editing while
## it's open if they want; closing is one keystroke.
##
## Loc-keys for shortcut entries land in Φ-11.

const _SHORTCUTS: Array = [
	[&"ui_help_key_q",         "Q",         &"ui_help_desc_layer_hexes",     "Hexes layer"],
	[&"ui_help_key_w",         "W",         &"ui_help_desc_layer_spawners",  "Spawners layer"],
	[&"ui_help_key_e",         "E",         &"ui_help_desc_layer_objects",   "Objects layer"],
	[&"ui_help_key_tab",       "Tab",       &"ui_help_desc_cycle_layers",    "Cycle layers forward"],
	[&"ui_help_key_1_9",       "1–9",       &"ui_help_desc_quick_select",    "Quick-select palette item"],
	[&"ui_help_key_lmb",       "LMB",       &"ui_help_desc_paint",           "Paint"],
	[&"ui_help_key_rmb",       "RMB",       &"ui_help_desc_erase",           "Erase on active layer"],
	[&"ui_help_key_shift_rmb", "Shift+LMB/RMB", &"ui_help_desc_cascade",         "Drag-cascade — erase all layers (no undo)"],
	[&"ui_help_key_esc",       "Esc",       &"ui_help_desc_cancel_drag",     "Cancel current drag"],
	[&"ui_help_key_f1",        "F1 / ?",    &"ui_help_desc_help",            "Show / hide this help"],
]


func _ready() -> void:
	super._ready()
	_build_body()
	visible = false


func _build_body() -> void:
	var grid := GridContainer.new()
	grid.name = "HelpGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	get_body_container().add_child(grid)
	for entry in _SHORTCUTS:
		var k_label := Label.new()
		k_label.text = Localization.t(entry[0], entry[1])
		var d_label := Label.new()
		d_label.text = Localization.t(entry[2], entry[3])
		grid.add_child(k_label)
		grid.add_child(d_label)


## Toggle / close on Esc, F1, ? while visible. Consumes the event so
## the dispatcher doesn't see the same key as a layer-switch.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_ESCAPE or k == KEY_F1 or k == KEY_QUESTION:
			visible = false
			get_viewport().set_input_as_handled()
