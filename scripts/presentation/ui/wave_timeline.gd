class_name WaveTimeline
extends Control

## WaveTimeline -- horizontal "1 turn = 1 px" timeline of waves.
##
## Modes:
##   - Mode.RUNTIME: read-only. Used in the battle HUD. A clock cursor
##     slides left->right as turns elapse, anchors before the current wave
##     dim, the current wave highlights, special waves render as larger
##     discs. Subscribes to EventBus.wave_started / wave_cleared /
##     world_turn_ended (for the cursor) and re-renders on each.
##   - Mode.EDIT: anchors are clickable (LMB -> switch active wave, RMB ->
##     context menu), turns_to_next numbers are editable LineEdits, the add-wave
##     button at the bar's right end appends. Editor wires up via signals.
##
## Geometry: bar length = sum of turns_to_next + paddings. Anchor at every
## wave; turns_to_next number drawn between anchor[i] and anchor[i+1].
##
## Re-render strategy: rebuild the child Controls (anchors, numbers, "+ Wave"
## button, cursor) every bind_level / set_runtime_state to keep the code
## simple. Cheap -- at most a few dozen children.
##
## Custom drawing: bar trough + anchor discs go through _draw. LineEdits
## and the add-wave button are real Control children (need event handling).

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
const PADDING_LEFT: float = 24.0     # space before wave 0 anchor
const PADDING_RIGHT: float = 32.0    # space after last anchor (before "+ Wave")
# Spec called for "1 turn = 1 px"; that's mathematically tidy but visually
# unreadable at jam-scale ttn values (5?6 turns = anchors overlap, numbers
# illegible). Bumped to 24 px/turn so anchors of radius 10 don't collide
# at the minimum legal ttn=1 and the inter-anchor number has room to read.
const PIXELS_PER_TURN: float = 24.0
const BAR_Y: float = 28.0            # vertical center of the bar within widget
const NUMBER_OFFSET_Y: float = -28.0 # number drawn above the bar between anchors
const PLUS_BUTTON_OFFSET_X: float = 24.0  # gap between last anchor and + button

var _level: LevelData = null
var _runtime_current_wave: int = 0
var _runtime_turns_into_wave: int = 0

# 048: once the final wave is cleared, freeze the cursor at the end of
# the final wave's bar segment. Without this, world_turn_ended ticks during
# the absorption ritual / post-level dialogue would keep advancing the
# playhead past the end. Reset on wave_started(0) (new run) or bind_level.
var _runtime_finished: bool = false

# EDIT-mode active wave (highlighted with WAVE_ANCHOR_CURRENT).
var _edit_active_wave: int = 0

# 039: dialogue trigger markers for EDIT mode.
# Each entry: {trigger_id: StringName, x: float, y: float, summary: String}
var _trigger_markers: Array = []
signal dialogue_trigger_marker_clicked(trigger_id: StringName)

# 040: skill-offer markers. Visible in BOTH modes (EDIT for designers,
# RUNTIME for player planning). Each entry: {wave_index, x, y, label}.
# Position: in the gap between waves[i] and waves[i+1], pinned closer to
# anchor[i+1] so it visually announces "after wave i, next wave brings an
# offer". On the final wave with offer — placed to the right of its anchor.
var _skill_offer_markers: Array = []
signal skill_offer_marker_clicked(wave_index: int)

# Track per-anchor screen positions so the right-click handler can map
# screen_pos -> wave_idx without re-walking layout.
var _anchor_positions: Array[float] = []  # x coordinates of each anchor
var _bar_end_x: float = 0.0

# T72c -- wave_index -> Label/LineEdit currently rendering its turns_to_next.
# Used to pulse the current wave's number on each world_turn_ended tick.
var _turns_widgets: Dictionary = {}  # int wave_idx -> Control

# Bug-fix guard: bind_level -> _rebuild can be triggered from inside a
# child LineEdit's focus_exited signal (commit-on-blur). Godot 4 then
# rejects add_child with "Parent node is busy setting up children". We
# defer the actual rebuild via call_deferred and coalesce repeated
# requests in the same frame.
var _rebuild_pending: bool = false


func _ready() -> void:
	# Listen to wave events even in EDIT mode (no-op when _level is null).
	# RUNTIME mode benefits; EDIT mode just ignores.
	if mode == Mode.RUNTIME:
		EventBus.wave_started.connect(_on_wave_started)
		EventBus.wave_cleared.connect(_on_wave_cleared)
		EventBus.world_turn_ended.connect(_on_world_turn_ended)
		# 048: extra safety net — if wave_cleared on final wave is missed for
		# any reason, level_completed still freezes the cursor.
		EventBus.level_completed.connect(_on_level_completed)
		# 051d: in battle/HUD this widget is purely visual — never eat input.
		# .tscn root has mouse_filter = STOP (needed for EDIT-mode anchor
		# clicks); flip to IGNORE in RUNTIME so clicks on the top strip fall
		# through to the hex grid below. Children get the same treatment in
		# _do_rebuild via _propagate_mouse_filter_ignore.
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Apply theme stylebox to the widget background.
	_apply_theme()
	# Default size -- widget grows to fit content on bind_level / runtime
	# updates, but give it a sensible minimum so it shows up empty too.
	custom_minimum_size = Vector2(64, 56)
	queue_redraw()


# -- Public API --------------------------------------------------------------

## Bind a LevelData to display. Called by editor (each repaint) and by
## runtime (once at battle start). Triggers a full rebuild + redraw.
func bind_level(level: LevelData) -> void:
	_level = level
	# 048: new level → cursor unfrozen.
	_runtime_finished = false
	_rebuild()
	# 040: skill-offer markers depend on _anchor_positions which are
	# computed inside the deferred _do_rebuild. Layout once anchors are
	# fresh — call on the same deferred channel so order is stable.
	_layout_skill_offer_markers.call_deferred()


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


## 039: Update dialogue trigger markers for EDIT mode.
## triggers is an Array[Dictionary] (raw LevelData.dialogue_triggers entries).
## level is the active LevelData (for turns_to_next lookup).
## Pass an empty array to clear.
func set_dialogue_trigger_markers(triggers: Array, level: LevelData) -> void:
	if mode != Mode.EDIT:
		_trigger_markers.clear()
		queue_redraw()
		return
	_trigger_markers = _layout_trigger_markers(triggers, level)
	queue_redraw()


# 040: layout skill_offer markers from _level.waves. No external trigger
# list — markers are intrinsic to the level data. Called from bind_level
# after _do_rebuild has populated _anchor_positions.
func _layout_skill_offer_markers() -> void:
	_skill_offer_markers.clear()
	if _level == null:
		queue_redraw()
		return
	for i in _level.waves.size():
		var w: Dictionary = _level.waves[i]
		if not w.has("skill_offer") or w["skill_offer"] == null:
			continue
		if i >= _anchor_positions.size():
			continue
		# Position: 85% of the way from anchor[i] to anchor[i+1] for
		# inter-wave offers; just-right-of-anchor for offer on final wave.
		var x: float
		var anchor_x: float = _anchor_positions[i]
		if i < _level.waves.size() - 1 and i + 1 < _anchor_positions.size():
			var next_x: float = _anchor_positions[i + 1]
			x = anchor_x + (next_x - anchor_x) * 0.85
		else:
			x = anchor_x + 16.0
		var y: float = BAR_Y - UiThemeScript.WAVE_ANCHOR_RADIUS - 6.0
		var so: Dictionary = w["skill_offer"]
		var pool_id: String = str(so.get("pool", ""))
		var count_n: int = int(so.get("count", 3))
		var label: String = "Offer %d from %s" % [count_n, pool_id]
		_skill_offer_markers.append({
			"wave_index": i,
			"x": x,
			"y": y,
			"label": label,
		})
	queue_redraw()


func _layout_trigger_markers(triggers: Array, level: LevelData) -> Array:
	var out: Array = []
	# Stack counters per x-bucket (to offset multiple markers at same x).
	var stack: Dictionary = {}  # int(x_bucket) -> int count
	var misc_x: float = _bar_end_x + 8.0
	for d in triggers:
		if not (d is Dictionary):
			continue
		var ev: StringName = StringName(str(d.get("event", "")))
		var tid: StringName = StringName(str(d.get("id", "")))
		var did: StringName = StringName(str(d.get("dialogue_id", "")))
		var c: Dictionary = d.get("conditions", {})
		var mx: float = misc_x
		if ev in [&"level_started", &"level_completed"]:
			if not _anchor_positions.is_empty():
				mx = _anchor_positions[0] if ev == &"level_started" else _anchor_positions[-1]
		elif ev in [&"wave_started", &"wave_cleared", &"wave_about_to_start",
				&"skill_offer_about_to_open", &"skill_offer_closed"]:
			var wi: int = int(c.get("wave_index", -1))
			if wi >= 0 and wi < _anchor_positions.size():
				mx = _anchor_positions[wi]
		elif ev == &"world_turn_ended":
			var at: int = int(c.get("absolute_turn", -1))
			if at >= 0:
				mx = PADDING_LEFT + float(at) * PIXELS_PER_TURN
		var bucket: int = int(mx)
		var stack_idx: int = stack.get(bucket, 0)
		stack[bucket] = stack_idx + 1
		var my: float = BAR_Y - UiThemeScript.WAVE_ANCHOR_RADIUS - 6.0 \
				- float(stack_idx) * (UiThemeScript.DIALOGUE_TRIGGER_MARKER_RADIUS * 2.5)
		var summary: String = "%s . %s . %s" % [tid, ev, did]
		out.append({"trigger_id": tid, "x": mx, "y": my, "summary": summary})
	return out


# -- Rebuild -----------------------------------------------------------------

## Public-facing rebuild -- coalesces and defers to dodge "Parent busy
## setting up children" when triggered from inside a child Control's
## signal handler.
func _rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	_do_rebuild.call_deferred()


func _do_rebuild() -> void:
	_rebuild_pending = false
	# Drop existing dynamic children (LineEdits, +button). Keep persistent
	# nodes (none currently -- all dynamic).
	for child in get_children():
		child.queue_free()
	_anchor_positions.clear()
	_turns_widgets.clear()
	if _level == null or _level.waves.is_empty():
		_bar_end_x = PADDING_LEFT
		custom_minimum_size = Vector2(_bar_end_x + PADDING_RIGHT, 64)
		queue_redraw()
		return

	# Layout: anchor[i] at x = PADDING_LEFT + sum(turns_to_next[0..i-1]).
	# Last anchor's x = PADDING_LEFT + total_turns. End-of-bar x = that +
	# PADDING_RIGHT.
	var x: float = PADDING_LEFT
	for i in _level.waves.size():
		_anchor_positions.append(x)
		# v2 -- wave index label "W0", "W1", ... under each anchor for
		# at-a-glance identification regardless of mode.
		_add_wave_index_label(i, x)
		var ttn: int = int(_level.waves[i].get("turns_to_next", 0))
		# Number Label between anchor[i] and anchor[i+1] only if there is a
		# next anchor (i.e. not on the last wave).
		if i < _level.waves.size() - 1 and ttn > 0:
			_add_turns_label(i, x + ttn * PIXELS_PER_TURN * 0.5, ttn)
		x += float(ttn) * PIXELS_PER_TURN
	# 049b / T045: bar trough must end EXACTLY on the last anchor's centre.
	# Loop above unconditionally adds the last wave's `turns_to_next` to x,
	# so x post-loop is past the last anchor by `last_ttn * PIXELS_PER_TURN`.
	# Trough then visibly extended past the big active-wave circle. Pin to
	# the last anchor's stored position instead.
	_bar_end_x = _anchor_positions[_anchor_positions.size() - 1] \
			if not _anchor_positions.is_empty() else PADDING_LEFT

	# Add-wave button at the right end (EDIT mode only).
	if mode == Mode.EDIT:
		_add_plus_wave_button(x + PLUS_BUTTON_OFFSET_X)
		x += PLUS_BUTTON_OFFSET_X + 80.0  # rough button width

	custom_minimum_size = Vector2(x + PADDING_RIGHT, 64)
	# 051d: dynamic children (W-labels, turn-count Labels) are added every
	# rebuild and default to MOUSE_FILTER_STOP — must re-mute every pass.
	# EDIT mode keeps the LineEdits / +button responsive (skipped here).
	if mode == Mode.RUNTIME:
		_propagate_mouse_filter_ignore(self)
	queue_redraw()


# 051d: Walk every Control descendant and force MOUSE_FILTER_IGNORE so the
# whole subtree falls through. Same hammer pattern as 049b T048 used on
# skill_offer_card. Skips self if called externally on root (caller's job).
func _propagate_mouse_filter_ignore(n: Node) -> void:
	for child in n.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_propagate_mouse_filter_ignore(child)


func _add_wave_index_label(wave_idx: int, x: float) -> void:
	var lbl := Label.new()
	lbl.text = "W%d" % wave_idx
	lbl.position = Vector2(x - 18, BAR_Y + UiThemeScript.WAVE_ANCHOR_RADIUS * 1.4)
	lbl.size = Vector2(36, 24)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 056: was font_size=11 / size=Vector2(28,14). Migrated to FS_SMALL=22
	# (post-056 bump). Label box widened to 36×24 to fit the bigger glyphs.
	# Position x-offset adjusted from -14 to -18 to keep label centred over
	# its anchor at the wider box.
	lbl.add_theme_font_size_override("font_size", UiThemeScript.FS_SMALL)
	# Active wave's index label gets the focus accent for parity with the
	# anchor outline. Other waves stay muted.
	var col: Color = UiThemeScript.WAVE_ANCHOR_CURRENT \
		if (mode == Mode.EDIT and wave_idx == _edit_active_wave) \
		else UiThemeScript.WAVE_ANCHOR_PASSED
	lbl.add_theme_color_override("font_color", col)
	add_child(lbl)


func _add_turns_label(wave_idx: int, x: float, ttn: int) -> void:
	if mode == Mode.RUNTIME:
		# Read-only label.
		var lbl := Label.new()
		lbl.text = str(ttn)
		lbl.position = Vector2(x - 12, BAR_Y + NUMBER_OFFSET_Y)
		lbl.size = Vector2(24, 18)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.pivot_offset = Vector2(12, 9)  # center for scale tweens
		lbl.add_theme_font_size_override("font_size", UiThemeScript.WAVE_NUMBER_FONT_SIZE)
		lbl.add_theme_color_override("font_color", UiThemeScript.WAVE_NUMBER_COLOR)
		add_child(lbl)
		_turns_widgets[wave_idx] = lbl
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
	_turns_widgets[wave_idx] = le


func _add_plus_wave_button(x: float) -> void:
	var btn := Button.new()
	btn.text = Localization.t("ui_wave_timeline_add_wave", "+ Wave")
	btn.position = Vector2(x, BAR_Y - 12)
	btn.size = Vector2(76, 24)
	UiThemeScript.apply_button_styling(btn)
	btn.pressed.connect(func() -> void: add_wave_pressed.emit())
	add_child(btn)


func _apply_theme() -> void:
	# Lightweight panel-ish background -- keep transparent, the bar itself
	# draws its trough.
	pass


# -- Drawing -----------------------------------------------------------------

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
		# Active wave (EDIT) or current wave (RUNTIME) gets an outer
		# focus ring so it reads as "selected" on top of any background.
		# The fill colour alone wasn't enough -- at small radii on dark
		# panels the colour shift was hard to spot.
		var is_active: bool = (mode == Mode.EDIT and i == _edit_active_wave) \
				or (mode == Mode.RUNTIME and i == _runtime_current_wave)
		if is_active:
			draw_arc(Vector2(ax, BAR_Y), radius + 4.0, 0.0, TAU, 28,
					UiThemeScript.WAVE_ANCHOR_CURRENT, 2.5, true)
		draw_circle(Vector2(ax, BAR_Y), radius, fill)
		draw_arc(Vector2(ax, BAR_Y), radius, 0.0, TAU, 24,
				UiThemeScript.WAVE_ANCHOR_OUTLINE, 1.5, true)

	# RUNTIME cursor.
	# _anchor_positions is populated by _do_rebuild which is call_deferred'd
	# (see _rebuild). On the first frame after bind_level there's a paint
	# pass where _level is set but _anchor_positions is still empty --
	# without this guard, `clampi(0, 0, -1)` returns -1 and `_anchor_positions[-1]`
	# blows up (98 errors per second flooding the debugger). Skipping the
	# cursor for that one frame is invisible to the user.
	if mode == Mode.RUNTIME and _level.waves.size() > 0 and not _anchor_positions.is_empty():
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


	# 039: dialogue trigger markers (EDIT mode only, AC-D20).
	if mode == Mode.EDIT:
		for m in _trigger_markers:
			draw_circle(Vector2(m.x, m.y), UiThemeScript.DIALOGUE_TRIGGER_MARKER_RADIUS,
					UiThemeScript.DIALOGUE_TRIGGER_MARKER_COLOR)

	# 040: skill-offer markers (BOTH modes — see Mode-comment above).
	# Disc with the SKILL_OFFER_MARKER_GLYPH centered. Offset Y from any
	# dialogue triggers stacked at the same x by drawing slightly higher.
	for m in _skill_offer_markers:
		var pos: Vector2 = Vector2(m.x, m.y)
		draw_circle(pos, UiThemeScript.SKILL_OFFER_MARKER_RADIUS,
				UiThemeScript.SKILL_OFFER_MARKER_COLOR)
		# Outline ring so it reads against busy bg + dialogue trigger overlap.
		draw_arc(pos, UiThemeScript.SKILL_OFFER_MARKER_RADIUS, 0.0, TAU, 18,
				UiThemeScript.WAVE_ANCHOR_OUTLINE, 1.5, true)


func _anchor_color_for(wave_idx: int) -> Color:
	if mode == Mode.EDIT:
		return UiThemeScript.WAVE_ANCHOR_CURRENT if wave_idx == _edit_active_wave else UiThemeScript.WAVE_ANCHOR_FILL
	# RUNTIME
	if wave_idx < _runtime_current_wave:
		return UiThemeScript.WAVE_ANCHOR_PASSED
	if wave_idx == _runtime_current_wave:
		return UiThemeScript.WAVE_ANCHOR_CURRENT
	return UiThemeScript.WAVE_ANCHOR_FILL


# -- Input (EDIT mode anchor click + RMB context) ----------------------------

func _gui_input(event: InputEvent) -> void:
	if mode != Mode.EDIT or _level == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event
	if not mb.pressed:
		return
	var local_pos: Vector2 = mb.position
	# 040: hit-test skill-offer markers first (small + on top, both modes).
	# Click only emits in EDIT — RUNTIME marker is read-only display.
	if mb.button_index == MOUSE_BUTTON_LEFT:
		for m in _skill_offer_markers:
			var d_so: float = local_pos.distance_to(Vector2(m.x, m.y))
			if d_so <= UiThemeScript.SKILL_OFFER_MARKER_RADIUS + 4.0:
				accept_event()
				skill_offer_marker_clicked.emit(int(m.wave_index))
				return
	# 039: hit-test dialogue trigger markers first (smaller targets, on top).
	if mb.button_index == MOUSE_BUTTON_LEFT:
		for m in _trigger_markers:
			var d: float = local_pos.distance_to(Vector2(m.x, m.y))
			if d <= UiThemeScript.DIALOGUE_TRIGGER_MARKER_RADIUS + 4.0:
				accept_event()
				dialogue_trigger_marker_clicked.emit(m.trigger_id)
				return
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
	# RMB on a gap (between anchors) -> gap context.
	if mb.button_index == MOUSE_BUTTON_RIGHT and abs(local_pos.y - BAR_Y) < 16.0:
		var after_idx: int = -1
		for i in _anchor_positions.size():
			if local_pos.x > _anchor_positions[i] + 4.0:
				after_idx = i
		if after_idx >= 0:
			accept_event()
			gap_context_requested.emit(after_idx, get_global_mouse_position())


# -- EDIT-mode LineEdit handlers ---------------------------------------------

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


# -- RUNTIME signal handlers -------------------------------------------------

func _on_wave_started(idx: int, _is_special: bool) -> void:
	# 048: wave 0 of a new run → unfreeze.
	if idx == 0:
		_runtime_finished = false
	_runtime_current_wave = idx
	_runtime_turns_into_wave = 0
	queue_redraw()


func _on_wave_cleared(idx: int, _unused: int) -> void:
	# 048: final wave cleared → freeze cursor at the end of the bar so the
	# absorption ritual (~2.5s) and any post-level dialogue don't keep the
	# playhead sliding past the end. _runtime_turns_into_wave snapped to
	# the final wave's turns_to_next so the cursor sits at the right edge.
	if _level != null and idx >= _level.waves.size() - 1:
		_runtime_finished = true
		var ttn: int = 0
		if idx >= 0 and idx < _level.waves.size():
			ttn = int(_level.waves[idx].get("turns_to_next", 0))
		_runtime_turns_into_wave = ttn
		queue_redraw()
	# Otherwise: cursor will reset on the subsequent wave_started; no
	# immediate redraw needed (legacy behaviour preserved).


func _on_level_completed(_score: int) -> void:
	# 048: belt-and-suspenders. wave_cleared on final wave already freezes;
	# this handles the case where _level is null at wave_cleared time.
	_runtime_finished = true
	queue_redraw()


func _on_world_turn_ended(_turn: int) -> void:
	if mode != Mode.RUNTIME:
		return
	# 048: cursor frozen after final wave clears.
	if _runtime_finished:
		return
	_runtime_turns_into_wave += 1
	queue_redraw()
	# T72c -- pulse the current wave's turns_to_next label so the player
	# gets a per-tick heartbeat in the timeline. The number itself stays
	# at the original ttn (the cursor's position carries the "remaining"
	# information); the pulse just announces "another turn passed".
	var lbl: Control = _turns_widgets.get(_runtime_current_wave, null)
	if lbl == null:
		return
	var dur: float = float(GameSpeed.get_value("ui", "wave_tick_anim_sec", 0.2))
	if dur <= 0.0:
		return
	# Pivot already centered for Labels in _add_turns_label; LineEdits we
	# don't pulse (EDIT mode never reaches this branch anyway).
	var t: Tween = create_tween()
	t.tween_property(lbl, "scale", Vector2(1.25, 1.25), dur * 0.5)
	t.tween_property(lbl, "scale", Vector2(1.0, 1.0), dur * 0.5)
