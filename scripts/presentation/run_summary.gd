extends CanvasLayer
## RunSummary — end-of-run modal with stats grid and moral-compass viz.
##
## Q-UI-2 closure: stacked horizontal bars (not radar). Faster to build,
## scales cleanly when Stasyan adds a new compass axis post-jam.
##
## API:
##   show_summary(stats: Dictionary, compass: Dictionary)
##     stats   — { &"turns_played": int, &"damage_dealt": int, ... }
##     compass — { &"order": float, &"chaos": float, ... } (each in [-1, 1])

signal restart_requested
signal main_menu_requested

const BAR_HEIGHT: int = 12
const BAR_WIDTH: int = 360

@onready var _panel: PanelContainer = $Center/Panel
@onready var _title: Label = $Center/Panel/VBox/Title
@onready var _stats_title: Label = $Center/Panel/VBox/StatsTitle
@onready var _stats_grid: GridContainer = $Center/Panel/VBox/StatsGrid
@onready var _compass_title: Label = $Center/Panel/VBox/CompassTitle
@onready var _compass_bars: VBoxContainer = $Center/Panel/VBox/CompassBars
@onready var _restart_btn: Button = $Center/Panel/VBox/ButtonRow/RestartButton
@onready var _menu_btn: Button = $Center/Panel/VBox/ButtonRow/MainMenuButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	_restart_btn.pressed.connect(_on_restart)
	_menu_btn.pressed.connect(_on_menu)


func _apply_theme() -> void:
	if _panel:
		_panel.add_theme_stylebox_override("panel", UiTheme.make_modal_stylebox())
	UiTheme.apply_label_kind(_title, "display")
	UiTheme.apply_label_kind(_stats_title, "header")
	UiTheme.apply_label_kind(_compass_title, "header")
	UiTheme.apply_button_styling(_restart_btn)
	UiTheme.apply_button_styling(_menu_btn)


func show_summary(stats: Dictionary, compass: Dictionary = {}) -> void:
	_render_stats(stats)
	_render_compass(compass)
	visible = true
	EventBus.run_summary_shown.emit({"stats": stats, "compass": compass})
	_restart_btn.grab_focus()


func _render_stats(stats: Dictionary) -> void:
	for c in _stats_grid.get_children():
		c.queue_free()
	for k in stats.keys():
		var label_lbl := Label.new()
		label_lbl.text = String(k).replace("_", " ").capitalize()
		UiTheme.apply_label_kind(label_lbl, "small")
		_stats_grid.add_child(label_lbl)
		var value_lbl := Label.new()
		value_lbl.text = str(stats[k])
		UiTheme.apply_label_kind(value_lbl, "num_small")
		_stats_grid.add_child(value_lbl)


func _render_compass(compass: Dictionary) -> void:
	for c in _compass_bars.get_children():
		c.queue_free()
	if compass.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "(no compass data)"
		UiTheme.apply_label_kind(none_lbl, "small")
		_compass_bars.add_child(none_lbl)
		return
	for axis in compass.keys():
		_compass_bars.add_child(_make_compass_row(axis, float(compass[axis])))


## One row per axis: label + horizontal stacked bar centered at zero.
## value ∈ [-1, +1] → bar fills from center outward; positive = right
## (SEM_HEAL tint), negative = left (SEM_DEBUFF tint).
func _make_compass_row(axis: StringName, value: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SP_3)

	var name_lbl := Label.new()
	name_lbl.text = String(axis).capitalize()
	name_lbl.custom_minimum_size = Vector2(96, 0)
	UiTheme.apply_label_kind(name_lbl, "small")
	row.add_child(name_lbl)

	var bar := _make_bar(value)
	row.add_child(bar)

	var num_lbl := Label.new()
	num_lbl.text = "%+0.2f" % value
	UiTheme.apply_label_kind(num_lbl, "num_small")
	row.add_child(num_lbl)
	return row


func _make_bar(value: float) -> Control:
	var v: float = clampf(value, -1.0, 1.0)
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	# Background panel (track)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.BG_PANEL_2
	sb.border_color = UiTheme.BORDER
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	holder.add_theme_stylebox_override("panel", sb)

	# Fill via Control with custom _draw — simpler than nested StyleBoxes.
	var fill := Control.new()
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.set_meta("value", v)
	fill.draw.connect(_draw_bar_fill.bind(fill))
	holder.add_child(fill)
	return holder


func _draw_bar_fill(fill: Control) -> void:
	var v: float = float(fill.get_meta("value", 0.0))
	var rect := fill.get_rect()
	var cx: float = rect.size.x * 0.5
	# Width from center, proportional to |v|.
	var half_w: float = (rect.size.x * 0.5) * absf(v)
	var color: Color
	var x0: float
	if v >= 0.0:
		color = UiTheme.SEM_HEAL
		x0 = cx
	else:
		color = UiTheme.SEM_DEBUFF
		x0 = cx - half_w
	fill.draw_rect(Rect2(x0, 0, half_w, rect.size.y), color, true)
	# Center tick
	fill.draw_line(Vector2(cx, 0), Vector2(cx, rect.size.y), UiTheme.BORDER_STRONG, 1.0)


func _on_restart() -> void:
	visible = false
	restart_requested.emit()
	EventBus.run_started_requested.emit()


func _on_menu() -> void:
	visible = false
	main_menu_requested.emit()
	EventBus.main_menu_entered.emit()
