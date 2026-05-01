extends PanelContainer
## CombatLog — ring-buffer log of last N battle events (damage / heal / status).
## Toggled by L key. Disabled by default in production; enabled in Godmode.
##
## Wire-up: EventBus.damage_dealt / heal_done exist since 013-refactor-wave-1.
## status_applied is still a forward-compat lazy-bind (waits for status engine).

const RING_SIZE: int = 50

@onready var _title: Label = $VBox/Title
@onready var _lines: VBoxContainer = $VBox/Scroll/Lines
@onready var _scroll: ScrollContainer = $VBox/Scroll

var _line_pool: Array[Label] = []  # active labels, oldest first


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	# Lazy signal binding (post-007/008 EventBus extensions).
	if EventBus.has_signal("damage_dealt"):
		EventBus.connect("damage_dealt", _on_damage_dealt)
	if EventBus.has_signal("heal_done"):
		EventBus.connect("heal_done", _on_heal_done)
	if EventBus.has_signal("status_applied"):
		EventBus.connect("status_applied", _on_status_applied)


func _apply_theme() -> void:
	add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	UiTheme.apply_label_kind(_title, "small")


## Append a structured log line. Pre-007 callers can use this directly:
##   log.append(turn, &"player", &"hits", &"manekin_1", 12, &"damage")
func append(turn: int, actor_id: StringName, verb: StringName,
		target_id: StringName, amount: int, semantic: StringName) -> void:
	var sign: String = ""
	if semantic == &"damage":
		sign = "-"
	elif semantic == &"heal":
		sign = "+"
	var num_part: String = "" if amount == 0 else " %s%d" % [sign, abs(amount)]
	var text: String = "T%d  %s %s %s%s" % [turn, actor_id, verb, target_id, num_part]
	_append_line(text, semantic)


## Plain-text variant — for less structured events (e.g. "wave 3 spawned").
func append_text(text: String, semantic: StringName = &"") -> void:
	_append_line(text, semantic)


func _append_line(text: String, semantic: StringName) -> void:
	var lbl := Label.new()
	lbl.text = text
	UiTheme.apply_label_kind(lbl, "small")
	if semantic != &"":
		lbl.add_theme_color_override("font_color", UiTheme.semantic_color(semantic))
	_lines.add_child(lbl)
	_line_pool.append(lbl)
	# Trim ring
	while _line_pool.size() > RING_SIZE:
		var oldest := _line_pool.pop_front() as Label
		if is_instance_valid(oldest):
			oldest.queue_free()
	# Scroll to bottom on next frame
	call_deferred("_scroll_to_bottom")


func _scroll_to_bottom() -> void:
	if _scroll == null:
		return
	# get_v_scroll_bar().max_value updates after layout; nudge scroll to max.
	var bar: VScrollBar = _scroll.get_v_scroll_bar()
	if bar != null:
		_scroll.scroll_vertical = int(bar.max_value)


func toggle() -> void:
	visible = not visible


# ── Signal handlers ──────────────────────────────────────────────────────────
# damage_dealt / heal_done — wired by EventBus connect in _ready (013).
# status_applied — still lazy-bound, waits for status engine.

# 013/F-003: handlers accept world_pos to match EventBus signal arity. CombatLog
# doesn't render in world space, so the position is ignored — leading underscore
# silences GDScript's unused-parameter warning.

func _on_damage_dealt(target_id: StringName, amount: int, _world_pos: Vector2) -> void:
	var turn: int = TurnManager.current() if TurnManager.has_method("current") else 0
	append(turn, &"?", &"hits", target_id, amount, &"damage")


func _on_heal_done(target_id: StringName, amount: int, _world_pos: Vector2) -> void:
	var turn: int = TurnManager.current() if TurnManager.has_method("current") else 0
	append(turn, &"?", &"heals", target_id, amount, &"heal")


func _on_status_applied(target_id: StringName, status_id: StringName) -> void:
	var turn: int = TurnManager.current() if TurnManager.has_method("current") else 0
	append_text("T%d  %s gained %s" % [turn, target_id, status_id], &"buff")


## L-key toggle. We don't claim L globally — the host controller dispatches.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	if (event as InputEventKey).echo:
		return
	if (event as InputEventKey).keycode == KEY_L:
		# Avoid swallowing if a LineEdit is focused (e.g. typing "L" into search).
		var fc := get_viewport().gui_get_focus_owner()
		if fc != null and (fc is LineEdit or fc is TextEdit):
			return
		get_viewport().set_input_as_handled()
		toggle()
