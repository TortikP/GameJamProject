extends BasePanel
## ToolPanel — paint-tool picker. Lives at the left edge of the editor; sister
## to FloorPalettePanel/ObjectPalettePanel on the right.
##
## Two paint tools today:
##   Brush (default) — single-cell or disk paint following drag-paint semantics
##                     (LMB held + motion). Size 1..9; size N paints a hex disk
##                     of radius (N-1) centered on the cursor.
##   Rect            — click-and-drag to fill an axis-aligned rect of cells.
##                     Press at A, release at B; all cells with coord in
##                     [min(A,B)..max(A,B)] are painted in one undo transaction.
##
## Spec 057: migrated from extends PanelContainer + DraggablePanel mixin to
## extends BasePanel. Body content lives in get_body_container(); header,
## drag, resize, collapse, lock, persistence are handled by BasePanel.
##
## Signals (consumed by MapEditorController):
##   tool_changed(tool: int)              — TOOL_BRUSH / TOOL_RECT
##   brush_size_changed(size: int)        — 1..9, only meaningful for brush

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")

const TOOL_BRUSH: int = 0
const TOOL_RECT: int = 1

const MIN_SIZE: int = 1
const MAX_SIZE: int = 9

signal tool_changed(tool: int)
signal brush_size_changed(size: int)

var _controller: Node = null

var _brush_btn: Button
var _rect_btn: Button
var _size_label: Label
var _size_spin: SpinBox
var _hint: Label

var _current_tool: int = TOOL_BRUSH


func _ready() -> void:
	# In Godot 4, parent _ready() is NOT auto-called when subclass overrides.
	# super._ready() invokes BasePanel: resolve nodes, apply theme, install
	# drag/resize/collapse/lock/persistence handlers. Then build our body.
	super._ready()
	_build_body()


func setup(controller: Node) -> void:
	_controller = controller


func _build_body() -> void:
	var body := get_body_container()
	if body == null:
		push_error("[ToolPanel] body container not available")
		return
	var vbox := VBoxContainer.new()
	vbox.name = "ContentVBox"
	vbox.add_theme_constant_override("separation", UiTheme.SP_2)
	body.add_child(vbox)

	# Mode toggle row
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", UiTheme.SP_1)
	_brush_btn = _make_mode_btn(Localization.t("ui_tool_panel_brush", "Brush"), TOOL_BRUSH, true)
	_rect_btn = _make_mode_btn(Localization.t("ui_tool_panel_rect", "Rect"),  TOOL_RECT,  false)
	mode_row.add_child(_brush_btn)
	mode_row.add_child(_rect_btn)
	vbox.add_child(mode_row)

	# Brush size row (visible only on Brush mode)
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", UiTheme.SP_1)
	_size_label = Label.new()
	_size_label.text = Localization.t("ui_tool_panel_size", "Size:")
	size_row.add_child(_size_label)
	_size_spin = SpinBox.new()
	_size_spin.min_value = MIN_SIZE
	_size_spin.max_value = MAX_SIZE
	_size_spin.step = 1
	_size_spin.value = 1
	_size_spin.editable = true
	# 120px so the LineEdit and the +/- arrow column don't collide. Center
	# alignment keeps the value readable; size_flags=EXPAND_FILL grows into
	# any extra space the panel offers.
	_size_spin.custom_minimum_size = Vector2(120, 0)
	_size_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_size_spin.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_size_spin.value_changed.connect(_on_size_changed)
	size_row.add_child(_size_spin)
	vbox.add_child(size_row)

	# Tool hint — short usage line, updated per-mode
	_hint = Label.new()
	UiTheme.apply_label_kind(_hint, "small")
	_hint.modulate = UiTheme.TEXT_DIM
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(180, 0)
	vbox.add_child(_hint)
	_update_hint()


func _make_mode_btn(text: String, tool: int, default_pressed: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.toggle_mode = true
	btn.button_pressed = default_pressed
	btn.set_meta("tool", tool)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.apply_button_styling(btn)
	btn.pressed.connect(_on_mode_pressed.bind(tool, btn))
	return btn


func _on_mode_pressed(tool: int, btn: Button) -> void:
	# Force toggle group (ButtonGroup would also work but is overkill for 2).
	# set_pressed_no_signal on the OTHER button — un-press shouldn't re-fire
	# anything; we already know which mode the user picked.
	btn.button_pressed = true
	if tool == TOOL_BRUSH:
		_rect_btn.set_pressed_no_signal(false)
	else:
		_brush_btn.set_pressed_no_signal(false)
	if tool == _current_tool:
		return
	_current_tool = tool
	_size_label.visible = (tool == TOOL_BRUSH)
	_size_spin.visible = (tool == TOOL_BRUSH)
	_update_hint()
	tool_changed.emit(tool)


func _on_size_changed(value: float) -> void:
	brush_size_changed.emit(int(value))


func _update_hint() -> void:
	if _hint == null:
		return
	match _current_tool:
		TOOL_BRUSH:
			_hint.text = Localization.t("ui_tool_panel_brush_hint", "LMB drag to paint. Size 2 = 7 hexes, size 3 = 19, etc.")
		TOOL_RECT:
			_hint.text = Localization.t("ui_tool_panel_rect_hint", "Press LMB at corner A, release at corner B. Fills axis-aligned rect.")
