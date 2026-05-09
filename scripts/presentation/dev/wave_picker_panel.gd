class_name WavePickerPanel
extends BasePanel

## Small standalone panel with the active-wave switcher and add/copy/delete
## buttons. Lives separately from WaveSettingsPanel (which is now tabbed
## and has no room for a sticky switcher). EditorController routes the
## user-driven signals to the same wave-mutation code.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")

signal wave_switch_requested(idx: int)
signal wave_add_requested(after_idx: int)
signal wave_copy_requested(after_idx: int)
signal wave_delete_requested(idx: int)

var _level: LevelData = null
var _active_wave: int = 0
var _refreshing: bool = false

var _list: ItemList
var _add_btn: Button
var _copy_btn: Button
var _delete_btn: Button


func _ready() -> void:
	super._ready()
	_build()
	_refresh()


func bind_level(level: LevelData) -> void:
	_level = level
	if level != null:
		_active_wave = level.get_active_wave_index()
	_refresh()


func set_active_wave(idx: int) -> void:
	_active_wave = idx
	_refresh()


# ── Build ───────────────────────────────────────────────────────────────────

func _build() -> void:
	var body := get_body_container()
	if body == null:
		push_error("[WavePickerPanel] body container not available")
		return
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(wrap)

	_list = ItemList.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 110)
	_list.item_selected.connect(_on_item_selected)
	wrap.add_child(_list)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	wrap.add_child(btn_row)
	_add_btn = _make_btn(
		Localization.t("ui_wavesettings_switcher_add", "+ Wave"),
		_on_add_pressed)
	btn_row.add_child(_add_btn)
	_copy_btn = _make_btn(
		Localization.t("ui_wavesettings_switcher_copy", "Copy from prev"),
		_on_copy_pressed)
	btn_row.add_child(_copy_btn)
	_delete_btn = _make_btn(
		Localization.t("ui_wavesettings_switcher_delete", "Delete"),
		_on_delete_pressed)
	btn_row.add_child(_delete_btn)


func _make_btn(text: String, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	UiTheme.apply_button_styling(btn)
	btn.pressed.connect(on_pressed)
	return btn


# ── Refresh ─────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if _list == null or _level == null:
		return
	_refreshing = true
	_list.clear()
	for i in _level.waves.size():
		var w: Dictionary = _level.waves[i]
		var spec_str: String = String(w.get("is_special", "normal"))
		var spec_seg: String = "" if spec_str == "normal" else (" · " + spec_str)
		var ttn: int = int(w.get("turns_to_next", 0))
		_list.add_item("Wave %d%s · ttn=%d" % [i, spec_seg, ttn])
	if _active_wave >= 0 and _active_wave < _list.item_count:
		_list.select(_active_wave)
	if _copy_btn != null:
		_copy_btn.disabled = (_active_wave <= 0)
	if _delete_btn != null:
		_delete_btn.disabled = (_level.waves.size() <= 1)
	_refreshing = false


# ── Signal handlers ─────────────────────────────────────────────────────────

func _on_item_selected(idx: int) -> void:
	if _refreshing:
		return
	wave_switch_requested.emit(idx)


func _on_add_pressed() -> void:
	wave_add_requested.emit(_active_wave)


func _on_copy_pressed() -> void:
	wave_copy_requested.emit(_active_wave)


func _on_delete_pressed() -> void:
	wave_delete_requested.emit(_active_wave)
