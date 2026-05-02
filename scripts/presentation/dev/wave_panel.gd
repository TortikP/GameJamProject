extends PanelContainer

## WavePanel — top docked panel in the map editor. Wraps a WaveTimeline
## (Mode.EDIT) with the wave-management buttons documented in 024 spec
## section "Editor integration":
##   - "+ Wave" — provided by the timeline itself.
##   - Copy from previous wave — button (disabled on wave 0).
##   - Toggle special — button (mirrors RMB-context option for discoverability).
##
## All wave operations route via the EditorController (which holds _level
## + does autosave). This panel is a thin signal hub.
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

@onready var _timeline: WaveTimeline = $HBox/Timeline as WaveTimeline
@onready var _copy_btn: Button = $HBox/CopyBtn as Button
@onready var _special_btn: Button = $HBox/SpecialBtn as Button

# Cached so we can refresh button state on set_active_wave without
# re-reading from the timeline.
var _level: LevelData = null


func _ready() -> void:
	# Style + button theming.
	add_theme_stylebox_override("panel", UiThemeScript.make_panel_stylebox())
	if _copy_btn != null:
		UiThemeScript.apply_button_styling(_copy_btn)
		_copy_btn.pressed.connect(func() -> void: copy_from_prev_pressed.emit())
	if _special_btn != null:
		UiThemeScript.apply_button_styling(_special_btn)
		_special_btn.pressed.connect(func() -> void: toggle_special_pressed.emit())
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
## controls in O(num_waves)).
func bind_level(level: LevelData) -> void:
	_level = level
	if _timeline != null:
		_timeline.bind_level(level)
	_refresh_buttons()


## Set which wave is highlighted as "active" in the timeline. Called when
## the editor controller's _active_wave_index changes (anchor click or
## programmatic switch).
func set_active_wave(idx: int) -> void:
	if _timeline != null:
		_timeline.set_edit_active_wave(idx)
	_refresh_buttons()


func _refresh_buttons() -> void:
	if _level == null:
		return
	var active: int = _level.get_active_wave_index()
	if _copy_btn != null:
		_copy_btn.disabled = (active <= 0)
	if _special_btn != null and active >= 0 and active < _level.waves.size():
		var is_sp: bool = bool(_level.waves[active].get("is_special", false))
		_special_btn.text = "★ Special" if is_sp else "Make Special"
