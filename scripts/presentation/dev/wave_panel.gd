extends PanelContainer

## WavePanel — top docked panel in the map editor (v2 layout).
##
## Two rows in a VBox:
##   1. HeaderRow — status label "Wave N of M [special]" + per-wave action
##      buttons (Copy from prev / Toggle special / Delete). Status updates
##      on bind_level + set_active_wave.
##   2. TimelineRow — WaveTimeline (Mode.EDIT). Anchors are clickable to
##      switch active wave; ttn LineEdits commit on blur/enter.
##
## All wave operations route via the EditorController (which owns _level
## + history + autosave). This panel is a thin signal hub + status display.
##
## Wired by MapEditorController via _wire_wave_panel.

const UiThemeScript = preload("res://scripts/presentation/ui_theme.gd")

signal anchor_clicked(wave_index: int)
signal anchor_context_requested(wave_index: int, screen_pos: Vector2)
signal gap_context_requested(after_idx: int, screen_pos: Vector2)
signal turns_to_next_changed(wave_index: int, new_value: int)
signal add_wave_pressed
signal copy_from_prev_pressed
signal toggle_special_pressed
signal delete_wave_pressed   # v2: dedicated button, was RMB-anchor only

@onready var _timeline: WaveTimeline = $VBox/TimelineRow/Timeline as WaveTimeline
@onready var _status_label: Label = $VBox/HeaderRow/StatusLabel as Label
@onready var _copy_btn: Button = $VBox/HeaderRow/CopyBtn as Button
@onready var _special_btn: Button = $VBox/HeaderRow/SpecialBtn as Button
@onready var _delete_btn: Button = $VBox/HeaderRow/DeleteBtn as Button

# Cached so we can refresh button state on set_active_wave without
# re-reading from the timeline.
var _level: LevelData = null


func _ready() -> void:
	add_theme_stylebox_override("panel", UiThemeScript.make_panel_stylebox())
	if _status_label != null:
		# Status reads as primary metadata — give it bigger font + accent
		# colour so designer sees "which wave am I editing" at a glance.
		_status_label.add_theme_font_size_override("font_size", UiThemeScript.FS_BODY + 2)
		_status_label.add_theme_color_override("font_color", UiThemeScript.TEXT)
	for btn: Button in [_copy_btn, _special_btn, _delete_btn]:
		if btn != null:
			UiThemeScript.apply_button_styling(btn)
	if _copy_btn != null:
		_copy_btn.pressed.connect(func() -> void: copy_from_prev_pressed.emit())
	if _special_btn != null:
		_special_btn.pressed.connect(func() -> void: toggle_special_pressed.emit())
	if _delete_btn != null:
		_delete_btn.pressed.connect(func() -> void: delete_wave_pressed.emit())
	# Timeline relays.
	if _timeline != null:
		_timeline.mode = WaveTimeline.Mode.EDIT
		_timeline.anchor_clicked.connect(func(idx: int) -> void: anchor_clicked.emit(idx))
		_timeline.anchor_context_requested.connect(
			func(idx: int, pos: Vector2) -> void: anchor_context_requested.emit(idx, pos))
		_timeline.gap_context_requested.connect(
			func(after: int, pos: Vector2) -> void: gap_context_requested.emit(after, pos))
		_timeline.turns_to_next_changed.connect(
			func(idx: int, v: int) -> void: turns_to_next_changed.emit(idx, v))
		_timeline.add_wave_pressed.connect(func() -> void: add_wave_pressed.emit())


## Bind a level to the contained timeline + refresh button enablement.
## Called by editor on every dirty event (cheap — timeline rebuilds child
## controls in O(num_waves), deferred internally).
func bind_level(level: LevelData) -> void:
	_level = level
	if _timeline != null:
		_timeline.bind_level(level)
	_refresh_header()


## Set which wave is highlighted as "active" in the timeline. Called when
## the editor controller's _active_wave_index changes (anchor click or
## programmatic switch).
func set_active_wave(idx: int) -> void:
	if _timeline != null:
		_timeline.set_edit_active_wave(idx)
	_refresh_header()


func _refresh_header() -> void:
	if _level == null:
		return
	var active: int = _level.get_active_wave_index()
	var total: int = _level.waves.size()
	var is_special: bool = false
	var is_last: bool = active == total - 1
	if active >= 0 and active < total:
		is_special = bool(_level.waves[active].get("is_special", false))

	# Status — "Wave 1 of 3" + tags. Designer reads this as the first
	# line of HUD metadata.
	if _status_label != null:
		var tag: String = ""
		if is_special:
			tag += "  ★ special"
		if is_last:
			tag += "  ⏹ final"
		_status_label.text = Localization.tf("Wave %d of %d%s", [active + 1, total, tag], "Wave %d of %d%s")

	# Copy from prev — disabled on wave 0 (nothing to copy from).
	if _copy_btn != null:
		_copy_btn.disabled = (active <= 0)

	# Special — text reflects current state.
	if _special_btn != null:
		_special_btn.text = Localization.t("★ Special (on)", "★ Special (on)") if is_special else Localization.t("Make Special", "Make Special")

	# Delete — disabled on wave 0 (Wave 0 must always exist; player spawner
	# lives there). Single-wave levels also can't delete (would leave none).
	if _delete_btn != null:
		_delete_btn.disabled = (active <= 0 or total <= 1)
