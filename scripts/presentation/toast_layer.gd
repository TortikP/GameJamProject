extends CanvasLayer
## ToastLayer — stack of toast notifications anchored top-right.
##
## Listens to EventBus.ui_toast_requested(text, duration_sec, level). Caps
## visible toasts at 3 (additional requests queue). Deduplicates identical
## text within 500ms (prevents spam from fast successive emits).
##
## level ∈ &"info" / &"success" / &"warn" / &"error"

const MAX_VISIBLE: int = 3
const DEDUP_WINDOW_MS: int = 500
# Default toast duration lives in config/game_speed.cfg [ui]:
#   toast_default_duration_sec (default 2.5). F5-hot-reload via GameSpeed.

const ToastItemScene: PackedScene = preload("res://scenes/ui/toast_item.tscn")

@onready var _vbox: VBoxContainer = $VBox

var _visible: Array[Control] = []
var _queue: Array[Dictionary] = []
var _last_text_time_ms: Dictionary = {}  # text → ticks_msec


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # toasts don't pause with the world
	if EventBus.has_signal("ui_toast_requested"):
		EventBus.ui_toast_requested.connect(_on_request)


func _on_request(text: String, duration_sec: float, level: StringName) -> void:
	var display_text := Localization.t(text, text)
	# Dedup within window
	var now: int = Time.get_ticks_msec()
	if _last_text_time_ms.has(display_text):
		var since: int = now - int(_last_text_time_ms[display_text])
		if since < DEDUP_WINDOW_MS:
			return
	_last_text_time_ms[display_text] = now

	var default_dur: float = float(GameSpeed.get_value("ui", "toast_default_duration_sec", 2.5))
	var entry := {
		"text": display_text,
		"duration": duration_sec if duration_sec > 0.0 else default_dur,
		"level": level if level != &"" else &"info",
	}
	if _visible.size() < MAX_VISIBLE:
		_show_toast(entry)
	else:
		_queue.append(entry)


func _show_toast(entry: Dictionary) -> void:
	var t := ToastItemScene.instantiate() as Control
	_vbox.add_child(t)
	_visible.append(t)
	if t.has_method("setup"):
		t.setup(entry.text, entry.duration, entry.level)
	if t.has_signal("dismissed"):
		t.dismissed.connect(_on_dismissed.bind(t))


func _on_dismissed(t: Control) -> void:
	_visible.erase(t)
	# Pull the next queued toast if any
	if not _queue.is_empty():
		var next: Dictionary = _queue.pop_front()
		_show_toast(next)
