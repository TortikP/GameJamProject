## PanelLockHandler — lock/unlock behavior for BasePanel.
##
## Composition handler. Owned by BasePanel; not a public API.
##
## Lock state gates drag and resize at the handler level (they call
## base_panel.is_locked() at input time — see panel_drag_handler and
## panel_resize_handler). Collapse is intentionally NOT gated by lock —
## per spec 055 §5.4, the lock button itself remains the only escape from
## a locked state, but collapse/expand stays available so the user can
## still tuck a locked panel out of the way.
##
## Default application at startup goes through set_locked(true, emit=false)
## from BasePanel._ready — silent, no signal during scene init.

class_name PanelLockHandler
extends Node

const _ICON_UNLOCKED := preload("res://assets/icons/ui/lock_unlocked.png")
const _ICON_LOCKED   := preload("res://assets/icons/ui/lock_locked.png")

var _base_panel: BasePanel
var _lock_button: Button

var _is_locked: bool = false


func setup(base_panel: BasePanel, lock_button: Button) -> void:
	_base_panel = base_panel
	_lock_button = lock_button
	if not _lock_button.pressed.is_connected(_on_pressed):
		_lock_button.pressed.connect(_on_pressed)


func is_locked() -> bool:
	return _is_locked


func toggle() -> void:
	set_locked(not _is_locked, true)


## set_locked(value, emit_signal_flag)
##
## emit_signal_flag = false reserved for Phase 6 persistence load-time
## (silent state restore without triggering an autosave debounce).
## Phase 4 default-application uses the default true: resize_handler
## listens to locked_changed and needs the signal to hide ResizeFrame.
func set_locked(value: bool, emit_signal_flag: bool = true) -> void:
	if value == _is_locked:
		return
	_is_locked = value
	_lock_button.icon = _ICON_LOCKED if _is_locked else _ICON_UNLOCKED
	if emit_signal_flag:
		_base_panel.locked_changed.emit(_is_locked)


func _on_pressed() -> void:
	toggle()
