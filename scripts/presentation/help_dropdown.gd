extends PanelContainer
## HelpDropdown — small semi-transparent keybind reference that drops down
## from the HELP button in the top-right HUD strip. Sibling presentation of
## KeybindOverlay (the centered `?` modal) — same source-of-truth binds(),
## different placement.
##
## Click-through: root has mouse_filter = MOUSE_FILTER_IGNORE so clicks
## land on whatever is underneath (hex grid, HUD widgets, etc). The HELP
## button itself is the only way to dismiss — it just toggles visible.
##
## Owner: Andrey / minor UX tweak, no spec.

const KbOverlayScript = preload("res://scripts/presentation/keybind_overlay.gd")

@onready var _grid: GridContainer = $VBox/Grid
@onready var _title: Label = $VBox/Title


func _ready() -> void:
	# Survives pause — the HELP button stays usable while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	# Click-through: never absorbs mouse events. Keeps the gameplay area
	# fully interactive even when the panel is open over it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	EventBus.help_dropdown_toggle_requested.connect(_on_toggle_requested)
	Localization.locale_changed.connect(_on_locale_changed)
	_refresh_texts()


func _apply_theme() -> void:
	var sb := UiTheme.make_panel_stylebox(true)
	# Semi-transparent background so the world reads through. Slightly
	# stronger border than make_panel_stylebox so the dropdown still has
	# a visible frame against bright tiles.
	sb.bg_color = Color(UiTheme.BG_PANEL.r, UiTheme.BG_PANEL.g,
		UiTheme.BG_PANEL.b, 0.78)
	sb.border_color = UiTheme.BORDER_STRONG
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	add_theme_stylebox_override("panel", sb)
	if _title:
		UiTheme.apply_label_kind(_title, "header")
	if _grid:
		for c in _grid.get_children():
			if c is Label:
				UiTheme.apply_label_kind(c, "small")


func _build_grid() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for bind in KbOverlayScript.binds():
		var key_lbl := Label.new()
		key_lbl.text = String(bind.get("keys", ""))
		key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiTheme.apply_label_kind(key_lbl, "small")
		key_lbl.add_theme_color_override("font_color", UiTheme.FOCUS)
		_grid.add_child(key_lbl)
		var desc_lbl := Label.new()
		desc_lbl.text = KbOverlayScript.localized_bind_description(bind)
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiTheme.apply_label_kind(desc_lbl, "small")
		_grid.add_child(desc_lbl)


func _refresh_texts() -> void:
	if _title:
		_title.text = Localization.t("ui_help_dropdown_title_text", "Keybinds")
	_build_grid()


func _on_locale_changed(_locale: String) -> void:
	_refresh_texts()


func _on_toggle_requested() -> void:
	visible = not visible
