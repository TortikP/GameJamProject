extends CanvasLayer
## KeybindOverlay — full-screen reference card listing all keybinds in two
## columns. Toggled by the `?` key (or `/` on US layout — same physical key).
##
## NOT pause-triggering — the overlay is reference material, the player can
## absorb it without freezing the world. Still gets emit_modal_opened so
## tooltips suppress while it's up (cleaner).

const UiHelpers = preload("res://scripts/presentation/ui_signal_helpers.gd")
const SlotBarScript = preload("res://scripts/presentation/slot_bar.gd")
const MODAL_ID: StringName = &"keybind_overlay"

const MOVE_STEP_COUNT := 1
const DEBUG_DUMMY_COUNT := 1

@onready var _panel: PanelContainer = $Center/Panel
@onready var _title: Label = $Center/Panel/VBox/Title
@onready var _grid: GridContainer = $Center/Panel/VBox/Grid
@onready var _hint: Label = $Center/Panel/VBox/Hint


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	Localization.locale_changed.connect(_on_locale_changed)
	_refresh_texts()


static func binds() -> Array:
	return [
		{"keys": "QWER / 1234", "label_key": "ui_keybind_cast_slots", "fallback": "Cast slot %d-%d", "args": [1, SlotBarScript.SLOT_COUNT]},
		{"keys": "LMB", "label_key": "ui_keybind_cast_hex", "fallback": "Cast at hex (with slot active)", "args": []},
		{"keys": "RMB", "label_key": "ui_keybind_move_step", "fallback": "Move %d step", "args": [MOVE_STEP_COUNT]},
		{"keys": "MMB drag", "label_key": "ui_keybind_pan_camera", "fallback": "Pan camera (release to keep view)", "args": []},
		{"keys": "Wheel", "label_key": "ui_keybind_zoom", "fallback": "Zoom", "args": []},
		{"keys": "C", "label_key": "ui_keybind_recenter", "fallback": "Recenter on player", "args": []},
		{"keys": "SPACE", "label_key": "ui_keybind_wait_turn", "fallback": "Wait turn", "args": []},
		{"keys": "ESC", "label_key": "ui_keybind_cancel_pause", "fallback": "Cancel cast / open pause", "args": []},
		{"keys": "L", "label_key": "ui_keybind_toggle_combat_log", "fallback": "Toggle combat log", "args": []},
		{"keys": "?", "label_key": "ui_keybind_toggle_overlay", "fallback": "Toggle this overlay", "args": []},
		{"keys": "F1", "label_key": "ui_keybind_spawn_dummy", "fallback": "Spawn %d dummy (godmode)", "args": [DEBUG_DUMMY_COUNT]},
		{"keys": "F2", "label_key": "ui_keybind_clear_actors", "fallback": "Clear actors (godmode)", "args": []},
		{"keys": "F5", "label_key": "ui_keybind_reload_speed_config", "fallback": "Reload speed config", "args": []},
		{"keys": "F6", "label_key": "ui_keybind_toggle_crt", "fallback": "Toggle CRT effect", "args": []},
	]


static func localized_bind_description(bind: Dictionary) -> String:
	var label_key := String(bind.get("label_key", ""))
	var fallback := String(bind.get("fallback", ""))
	var args: Array = bind.get("args", [])
	if args.is_empty():
		return Localization.t(label_key, fallback)
	return Localization.tf(label_key, args, fallback)


static func localized_keybinds_body() -> String:
	var lines: Array[String] = []
	for bind in binds():
		lines.append("%s - %s" % [String(bind.get("keys", "")), localized_bind_description(bind)])
	return "\n".join(lines)


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
		_grid.remove_child(c)
		c.queue_free()
	for bind in binds():
		var key_lbl := Label.new()
		key_lbl.text = String(bind.get("keys", ""))
		UiTheme.apply_label_kind(key_lbl, "body")
		key_lbl.add_theme_color_override("font_color", UiTheme.FOCUS)
		_grid.add_child(key_lbl)
		var desc_lbl := Label.new()
		desc_lbl.text = localized_bind_description(bind)
		UiTheme.apply_label_kind(desc_lbl, "body")
		_grid.add_child(desc_lbl)


func _refresh_texts() -> void:
	_title.text = Localization.t("ui_keybind_overlay_title_text", "Keybinds")
	_hint.text = Localization.t("ui_keybind_overlay_hint_text", "(press ? to close)")
	_build_grid()


func _on_locale_changed(_locale: String) -> void:
	_refresh_texts()


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
