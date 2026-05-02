extends Control
## HotkeyOverlay — semi-transparent cheatsheet shown over the map editor
## when the user presses H. Contents are hardcoded — this is a discoverability
## helper, not configurable. Update HOTKEYS below when shortcuts change.
##
## Used as an instance under HUD/HotkeyOverlay. Starts invisible; controller
## toggles `visible` directly. Mouse_filter forced to IGNORE so the overlay
## never eats clicks even when shown.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")

const HOTKEYS: Array[Array] = [
	["LMB",            "paint / place"],
	["LMB drag",       "paint serially (Brush) or define rect (Rect)"],
	["RMB / RMB",      "delete (2-click confirm)"],
	["Alt + LMB",      "eyedropper — pick under cursor"],
	["Ctrl + Z / Y",   "undo / redo"],
	["Ctrl + S",       "save"],
	["1–9",            "quick palette select"],
	["Tools panel",    "Brush + size, or Rect (left side)"],
	["H",              "toggle this overlay"],
]

var _bg: ColorRect
var _panel: PanelContainer
var _grid: GridContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Full-viewport stretch — anchors set in scene file, but force here too
	# in case someone instantiates this script bare.
	if anchor_right == 0.0 and anchor_bottom == 0.0:
		set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)


func _build_ui() -> void:
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# Centered panel via a CenterContainer
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UiTheme.SP_2)
	_panel.add_child(vbox)

	var header := Label.new()
	header.text = "Hotkeys"
	UiTheme.apply_label_kind(header, "header")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", UiTheme.SP_4)
	_grid.add_theme_constant_override("v_separation", UiTheme.SP_1)
	vbox.add_child(_grid)

	for pair in HOTKEYS:
		var key_lbl := Label.new()
		key_lbl.text = String(pair[0])
		UiTheme.apply_label_kind(key_lbl, "body")
		_grid.add_child(key_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = String(pair[1])
		UiTheme.apply_label_kind(desc_lbl, "body")
		desc_lbl.modulate = UiTheme.TEXT_DIM
		_grid.add_child(desc_lbl)


func _apply_theme() -> void:
	if _bg != null:
		_bg.color = UiTheme.OVERLAY
	if _panel != null:
		_panel.add_theme_stylebox_override("panel", UiTheme.make_modal_stylebox())
