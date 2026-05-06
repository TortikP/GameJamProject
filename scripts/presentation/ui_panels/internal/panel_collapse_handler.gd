## PanelCollapseHandler — collapse/expand behavior for BasePanel.
##
## Composition handler. Owned by BasePanel; not a public API.
##
## On collapse:
##   1. Snapshot current base_panel.size into _pre_collapse_size (in-memory,
##      separate from persistence — see spec 055 §5.3).
##   2. Hide BodyPanel (the visible body frame). VBoxContainer stops reserving
##      its vertical slot.
##   3. Hide ResizeFrame entirely — collapsed panels can't be resized regardless
##      of `resizable` export. Re-shown on expand iff resize is allowed.
##   4. Resize base_panel to header-only height: EDGE_THICKNESS + CORNER_SIZE
##      + EDGE_THICKNESS = 56px. Width is preserved.
##   5. Swap icon to plus, emit collapsed_changed.
##
## On expand: reverse — restore _pre_collapse_size, show BodyPanel, show
## ResizeFrame iff base_panel.is_resizable() (lock-aware caller manages further
## visibility through locked_changed).
##
## Lock interaction (per spec §5.4): lock disables drag/resize but NOT collapse.
## So this handler does NOT gate on is_locked().

class_name PanelCollapseHandler
extends Node

const _ICON_MINUS := preload("res://assets/icons/ui/collapse_minus.png")
const _ICON_PLUS  := preload("res://assets/icons/ui/expand_plus.png")

var _base_panel: BasePanel
var _collapse_button: Button
var _body_panel: Control
var _resize_frame: Control

var _is_collapsed: bool = false
var _pre_collapse_size: Vector2 = Vector2.ZERO


func setup(base_panel: BasePanel, collapse_button: Button, body_panel: Control, resize_frame: Control) -> void:
	_base_panel = base_panel
	_collapse_button = collapse_button
	_body_panel = body_panel
	_resize_frame = resize_frame
	if not _collapse_button.pressed.is_connected(_on_pressed):
		_collapse_button.pressed.connect(_on_pressed)


func is_collapsed() -> bool:
	return _is_collapsed


func toggle() -> void:
	set_collapsed(not _is_collapsed, true)


## set_collapsed(value, emit_signal_flag)
##
## emit_signal_flag = false reserved for Phase 6 persistence load-time
## (silent state restore without triggering an autosave debounce).
## Phase 4 default-application uses the default true: visual side-effects
## (hide BodyPanel, resize panel, etc.) all happen inside _collapse()
## regardless of emit; the flag only gates the signal emit itself.
func set_collapsed(value: bool, emit_signal_flag: bool = true) -> void:
	if value == _is_collapsed:
		return
	if value:
		_collapse()
	else:
		_expand()
	_is_collapsed = value
	if emit_signal_flag:
		_base_panel.collapsed_changed.emit(_is_collapsed)


func _on_pressed() -> void:
	toggle()


func _collapse() -> void:
	_pre_collapse_size = _base_panel.size

	if _body_panel != null:
		_body_panel.visible = false
	if _resize_frame != null:
		_resize_frame.visible = false

	# Header-only height: top inset + header + bottom inset.
	var collapsed_height: float = float(BasePanel.EDGE_THICKNESS * 2 + BasePanel.CORNER_SIZE)
	_base_panel.size = Vector2(_base_panel.size.x, collapsed_height)

	_collapse_button.icon = _ICON_PLUS


func _expand() -> void:
	if _body_panel != null:
		_body_panel.visible = true
	# Resize frame visibility is also gated by lock state (resize handler
	# listens to locked_changed). Show iff resizable AND not locked.
	if _resize_frame != null:
		_resize_frame.visible = _base_panel.is_resizable() and not _base_panel.is_locked()

	if _pre_collapse_size != Vector2.ZERO:
		_base_panel.size = _pre_collapse_size

	_collapse_button.icon = _ICON_MINUS
