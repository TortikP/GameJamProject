class_name WaveTimeline
extends Control

## WaveTimeline — horizontal "1 turn = 1 px" timeline of waves.
##
## Modes:
##   - Mode.RUNTIME: read-only. Used in the battle HUD. A clock cursor
##     slides left→right as turns elapse, anchors before the current wave
##     dim, the current wave highlights, special waves render as larger
##     discs. Subscribes to EventBus.wave_started / wave_cleared /
##     world_turn_ended (for the cursor) and re-renders on each.
##   - Mode.EDIT: anchors are clickable (LMB → switch active wave, RMB →
##     context menu), turns_to_next numbers are editable LineEdits, "+ Wave"
##     button at the bar's right end appends. Editor wires up via signals.
##
## Geometry: bar length = sum of turns_to_next + paddings. Anchor at every
## wave; turns_to_next number drawn between anchor[i] and anchor[i+1].
##
## Re-render strategy: rebuild the child Controls (anchors, numbers, "+ Wave"
## button, cursor) every bind_level / set_runtime_state to keep the code
## simple. Cheap — at most a few dozen children.
##
## Custom drawing: bar trough + anchor discs go through _draw. LineEdits
## and the "+ Wave" button are real Control children (need event handling).

const UiThemeScript = preload("res://scripts/presentation/ui_theme.gd")

enum Mode { EDIT, RUNTIME }

@export var mode: Mode = Mode.EDIT

# EDIT-mode signals (wired by editor's WavePanel).
signal anchor_clicked(wave_index: int)
signal anchor_context_requested(wave_index: int, screen_pos: Vector2)
signal gap_context_requested(after_idx: int, screen_pos: Vector2)
signal turns_to_next_changed(wave_index: int, new_value: int)
signal add_wave_pressed
signal special_toggled(wave_index: int)

# Visual layout constants.
const PADDING_LEFT: float = 32.0     # space before wave 0 anchor
const PADDING_RIGHT: float = 32.0    # space after last anchor (before "+ Wave")
const PIXELS_PER_TURN: float = 1.0   # spec: 1 turn = 1 px
const BAR_Y: float = 24.0            # vertical center of the bar within widget
const NUMBER_OFFSET_Y: float = -22.0 # number drawn above the bar between anchors
const PLUS_BUTTON_OFFSET_X: float = 24.0  # gap between last anchor and + button

var _level: LevelData = null
var _runtime_current_wave: int = 0
var _runtime_turns_into_wave: int = 0

# EDIT-mode active wave (highlighted with WAVE_ANCHOR_CURRENT).
var _edit_active_wave: int = 0

# Track per-anchor screen positions so the right-click handler can map
# screen_pos → wave_idx without re-walking layout.
var _anchor_positions: Array[float] = []  # x coordinates of each anchor
var _bar_end_x: float = 0.0


func _ready() -> void:
	# Listen to wave events even in EDIT mode (no-op when _level is null).
	# RUNTIME mode benefits; EDIT mode just ignores.
	if mode == Mode.RUNTIME:
		EventBus.wave_started.connect(_on_wave_started)
		EventBus.wave_cleared.connect(_on_wave_cleared)
		EventBus.world_turn_ended.connect(_on_world_turn_ended)
	# Apply theme stylebox to the widget background.
	_apply_theme()
	# Default size — widget grows to fit content on bind_level / runtime
	# updates, but give it a sensible minimum so it shows up empty too.
	custom_minimum_size = Vector2(64, 56)
	queue_redraw()


# ── Public API ──────────────────────────────────────────────────────────────

## Bind a LevelData to display. Called by editor (each repaint) and by
## runtime (once at battle start). Triggers a full rebuild + redraw.
func bind_level(level: LevelData) -> void:
	_level = level
	_rebuild()


## Pull active wave from EDIT-side controllers. Triggers redraw of the
## active-wave outline only.
func set_edit_active_wave(idx: int) -> void:
	_edit_active_wave = idx
	queue_redraw()


## RUNTIME-only: update the cursor position. Called externally if the
## owner wants to drive the cursor without going through the EventBus
## (e.g. during scrubbing or test scenes).
func set_runtime_state(current_wave: int, turns_into_wave: int) -> void:
	_runtime_current_wave = current_wave
	_runtime_turns_into_wave = turns_into_wave
	queue_redraw()


# ── Rebuild ─────────────────────────────────────────────────────────────────

func _rebuild() -> void:
	# Drop existing dynamic children (LineEdits, +button). Keep persistent
	# nodes (none currently — all dynamic).
	for child in get_children():
		child.queue_free()
	_anchor_positions.clear()
	if _level == null or _level.waves.is_empty():
		_bar_end_x = PADDING_LEFT
		custom_minimum_size = Vector2(_bar_end_x + PADDING_RIGHT, 56)
		queue_redraw()
		return

	# Layout: anchor[i] at x = PADDING_LEFT + sum(turns_to_next[0..i-1]).
	# Last anchor's x = PADDING_LEFT + total_turns. End-of-bar x = that +
	# PADDING_RIGHT.
	var x: float = PADDING_LEFT
	for i in _level.waves.size():
		_anchor_positions.append(x)
		var ttn: int = int(_level.waves[i].get("turns_to_next", 0))
		# Number Label between anchor[i] and anchor[i+1] only if there is a
		# next anchor (i.e. not on the last wave).
		if i < _level.waves.size() - 1 and ttn > 0:
			_add_turns_label(i, x + ttn * PIXELS_PER_TURN * 0.5, ttn)
		x += float(ttn) * PIXELS_PER_TURN
	_bar_end_x = x

	# "+ Wave" button at the right end (EDIT mode only).
	if mode == Mode.EDIT:
		_add_plus_wave_button(x + PLUS_BUTTON_OFFSET_X)
		x += PLUS_BUTTON_OFFSET_X + 80.0  # rough button width

	custom_minimum_size = Vector2(x + PADDING_RIGHT, 56)
	queue_redraw()


func _add_turns_label(wave_idx: int, x: float, ttn: int) -> void:
	if mode == Mode.RUNTIME:
		# Read-only label.
		var lbl := Label.new()
		lbl.text = str(ttn)
		lbl.position = Vector2(x - 12, BAR_Y + NUMBER_OFFSET_Y)
		lbl.size = Vector2(24, 18)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", UiThemeScript.WAVE_NUMBER_FONT_SIZE)
		lbl.add_theme_color_override("font_color", UiThemeScript.WAVE_NUMBER_COLOR)
		add_child(lbl)
		return
	# EDIT mode: editable LineEdit.
	var le := LineEdit.new()
	le.text = str(ttn)
	le.position = Vector2(x - 18, BAR_Y + NUMBER_OFFSET_Y - 2)
	le.size = Vector2(36, 22)
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.context_menu_enabled = false
	le.add_theme_font_size_override("font_size", UiThemeScript.WAVE_NUMBER_FONT_SIZE)
	le.add_theme_color_override("font_color", UiThemeScript.WAVE_NUMBER_COLOR)
	le.text_submitted.connect(_on_turns_text_submitted.bind(wave_idx, le))
	le.focus_exited.connect(_on_turns_focus_exited.bind(wave_idx, le))
	add_child(le)


func _add_plus_wave_button(x: float) -> void:
	var btn := Button.new()
	btn.text = "+ Wave"
	btn.position = Vector2(x, BAR_Y - 12)
	btn.size = Vector2(76, 24)
	UiThemeScript.apply_button_styling(btn)
	btn.pressed.connect(func() -> void: add_wave_pressed.emit())
	add_child(btn)


func _apply_theme() -> void:
	# Lightweight panel-ish background — keep transparent, the bar itself
	# draws its trough.
	pass


# ── Drawing ─────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _level == null or _level.waves.is_empty():
		# Empty placeholder line.
		draw_rect(Rect2(PADDING_LEFT, BAR_Y - UiThemeScript.WAVE_BAR_HEIGHT * 0.5,
				64.0, UiThemeScript.WAVE_BAR_HEIGHT),
				UiThemeScript.WAVE_BAR_BG, true)
		return

	# Bar trough from PADDING_LEFT to _bar_end_x.
	draw_rect(Rect2(
			PADDING_LEFT,
			BAR_Y - UiThemeScript.WAVE_BAR_HEIGHT * 0.5,
			max(0.0, _bar_end_x - PADDING_LEFT),
			UiThemeScript.WAVE_BAR_HEIGHT),
			UiThemeScript.WAVE_BAR_BG, true)

	# Anchors.
	for i in _anchor_positions.size():
		var ax: float = _anchor_positions[i]
		var w: Dictionary = _level.waves[i]
		var is_special: bool = bool(w.get("is_special", false))
		var radius: float = UiThemeScript.WAVE_ANCHOR_RADIUS
		if is_special:
			radius *= UiThemeScript.WAVE_ANCHOR_SPECIAL_RADIUS_MULT
		var fill: Color = _anchor_color_for(i)
		draw_circle(Vector2(ax, BAR_Y), radius, fill)
		draw_arc(Vector2(ax, BAR_Y), radius, 0.0, TAU, 24,
				UiThemeScript.WAVE_ANCHOR_OUTLINE, 1.5, true)

	# RUNTIME cursor.
	if mode == Mode.RUNTIME and _level.waves.size() > 0:
		var cur_anchor: float = _anchor_positions[clampi(_runtime_current_wave, 0, _anchor_positions.size() - 1)]
		var cursor_x: float = cur_anchor + float(_runtime_turns_into_wave) * PIXELS_PER_TURN
		# Vertical line glyph, thin diamond on top.
		var top: Vector2 = Vector2(cursor_x, BAR_Y - UiThemeScript.WAVE_CURSOR_HEIGHT)
		var bot: Vector2 = Vector2(cursor_x, BAR_Y + UiThemeScript.WAVE_CURSOR_HEIGHT * 0.4)
		draw_line(top, bot, UiThemeScript.WAVE_CURSOR_COLOR, 2.0, true)
		# Small triangle pointer at top.
		var pts := PackedVector2Array([
			top + Vector2(-4, -1),
			top + Vector2(4, -1),
			top + Vector2(0, 5),
		])
		draw_colored_polygon(pts, UiThemeScript.WAVE_CURSOR_COLOR)


func _anchor_color_for(wave_idx: int) -> Color:
	if mode == Mode.EDIT:
		return UiThemeScript.WAVE_ANCHOR_CURRENT if wave_idx == _edit_active_wave else UiThemeScript.WAVE_ANCHOR_FILL
	# RUNTIME
	if wave_idx < _runtime_current_wave:
		return UiThemeScript.WAVE_ANCHOR_PASSED
	if wave_idx == _runtime_current_wave:
		return UiThemeScript.WAVE_ANCHOR_CURRENT
	return UiThemeScript.WAVE_ANCHOR_FILL


# ── Input (EDIT mode anchor click + RMB context) ────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if mode != Mode.EDIT or _level == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed:
		return
	var local_pos: Vector2 = mb.position
	# Hit-test against anchor discs.
	for i in _anchor_positions.size():
		var ax: float = _anchor_positions[i]
		var w: Dictionary = _level.waves[i]
		var radius: float = UiThemeScript.WAVE_ANCHOR_RADIUS
		if bool(w.get("is_special", false)):
			radius *= UiThemeScript.WAVE_ANCHOR_SPECIAL_RADIUS_MULT
		if local_pos.distance_to(Vector2(ax, BAR_Y)) <= radius + 2.0:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				accept_event()
				_edit_active_wave = i
				anchor_clicked.emit(i)
				queue_redraw()
				return
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				accept_event()
				anchor_context_requested.emit(i, get_global_mouse_position())
				return
	# RMB on a gap (between anchors) → gap context.
	if mb.button_index == MOUSE_BUTTON_RIGHT and abs(local_pos.y - BAR_Y) < 16.0:
		var after_idx: int = -1
		for i in _anchor_positions.size():
			if local_pos.x > _anchor_positions[i] + 4.0:
				after_idx = i
		if after_idx >= 0:
			accept_event()
			gap_context_requested.emit(after_idx, get_global_mouse_position())


# ── EDIT-mode LineEdit handlers ─────────────────────────────────────────────

func _on_turns_text_submitted(text: String, wave_idx: int, le: LineEdit) -> void:
	_commit_turns(wave_idx, text, le)
	le.release_focus()


func _on_turns_focus_exited(wave_idx: int, le: LineEdit) -> void:
	_commit_turns(wave_idx, le.text, le)


func _commit_turns(wave_idx: int, text: String, le: LineEdit) -> void:
	var v: int = max(1, int(text))
	le.text = str(v)
	if _level != null and wave_idx >= 0 and wave_idx < _level.waves.size():
		_level.waves[wave_idx]["turns_to_next"] = v
	turns_to_next_changed.emit(wave_idx, v)
	queue_redraw()


# ── RUNTIME signal handlers ─────────────────────────────────────────────────

func _on_wave_started(idx: int, _is_special: bool) -> void:
	_runtime_current_wave = idx
	_runtime_turns_into_wave = 0
	queue_redraw()


func _on_wave_cleared(_idx: int, _unused: int) -> void:
	# Cursor will reset on the subsequent wave_started; no immediate
	# redraw needed.
	pass


func _on_world_turn_ended(_turn: int) -> void:
	if mode != Mode.RUNTIME:
		return
	_runtime_turns_into_wave += 1
	queue_redraw()
