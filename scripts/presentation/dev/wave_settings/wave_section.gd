class_name WaveSettingsWaveSection
extends VBoxContainer

## Wave-section of WaveSettingsPanel (Spec 061 + tabbed rework).
## Fields specific to one wave:
##   - is_special (enum dropdown — see IS_SPECIAL_PRESETS)
##   - turns_to_next
##   - advance_mode (enum dropdown)
##   - music_config (raw JSON)
##
## Updates emit `wave_field_changed(idx, field, value)` for the host panel to
## relay onward. _refreshing guard suppresses programmatic emit cascade.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")
const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

# 061 post-review: switched from free-form LineEdit (design.md D5) to fixed enum.
# Free-form was never used in maps; runtime collapses everything to bool via
# is_wave_special() anyway. F-061-IMPL-5. Need a new tag? Add to this list.
const IS_SPECIAL_PRESETS: Array[String] = ["normal", "boss", "miniboss", "elite"]

signal wave_field_changed(idx: int, field: String, value: Variant)

var _level: LevelData = null
var _active_wave: int = 0
var _refreshing: bool = false

var _is_special_dd: OptionButton
var _ttn_spin: SpinBox
var _advance_mode_dd: OptionButton
var _music_config_edit: LineEdit


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_build()


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
	# is_special — enum dropdown (post-061 UX review, see IS_SPECIAL_PRESETS doc).
	var spec_row := HBoxContainer.new()
	add_child(spec_row)
	var spec_lbl := _make_label("ui_wavesettings_is_special", "is_special:")
	spec_lbl.custom_minimum_size = Vector2(120, 0)
	spec_lbl.tooltip_text = Localization.t("ui_wavesettings_is_special_hint",
		"Wave category tag. Runtime treats anything except \"normal\" as special.")
	spec_row.add_child(spec_lbl)
	_is_special_dd = OptionButton.new()
	_is_special_dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in IS_SPECIAL_PRESETS.size():
		var v: String = IS_SPECIAL_PRESETS[i]
		_is_special_dd.add_item(Localization.t("ui_wavesettings_is_special_" + v, v), i)
		_is_special_dd.set_item_metadata(i, v)
	_is_special_dd.item_selected.connect(_on_is_special_selected)
	spec_row.add_child(_is_special_dd)

	# turns_to_next.
	var ttn_row := HBoxContainer.new()
	add_child(ttn_row)
	var ttn_lbl := _make_label("ui_wavesettings_ttn", "turns_to_next:")
	ttn_lbl.custom_minimum_size = Vector2(120, 0)
	ttn_row.add_child(ttn_lbl)
	_ttn_spin = SpinBox.new()
	_ttn_spin.min_value = 0
	_ttn_spin.max_value = 999
	_ttn_spin.step = 1
	_ttn_spin.value_changed.connect(_on_ttn_changed)
	ttn_row.add_child(_ttn_spin)

	# advance_mode.
	var am_row := HBoxContainer.new()
	add_child(am_row)
	var am_lbl := _make_label("ui_wavesettings_advance_mode", "advance_mode:")
	am_lbl.custom_minimum_size = Vector2(120, 0)
	am_row.add_child(am_lbl)
	_advance_mode_dd = OptionButton.new()
	_advance_mode_dd.add_item(Localization.t("ui_wavesettings_advance_timer", "timer"), 0)
	_advance_mode_dd.set_item_metadata(0, "timer")
	_advance_mode_dd.add_item(Localization.t("ui_wavesettings_advance_clear", "clear"), 1)
	_advance_mode_dd.set_item_metadata(1, "clear")
	_advance_mode_dd.item_selected.connect(_on_advance_mode_selected)
	am_row.add_child(_advance_mode_dd)

	# music_config — raw JSON.
	var mc_row := HBoxContainer.new()
	add_child(mc_row)
	var mc_lbl := _make_label("ui_wavesettings_music_config", "music_config:")
	mc_lbl.custom_minimum_size = Vector2(120, 0)
	mc_lbl.tooltip_text = Localization.t("ui_wavesettings_music_config_hint",
		"Raw JSON object overriding level music_config. Empty = fallback.")
	mc_row.add_child(mc_lbl)
	_music_config_edit = LineEdit.new()
	_music_config_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_music_config_edit.placeholder_text = "{}"
	_music_config_edit.text_submitted.connect(_on_music_config_submitted)
	_music_config_edit.focus_exited.connect(
		func() -> void: _on_music_config_submitted(_music_config_edit.text))
	mc_row.add_child(_music_config_edit)


# ── Refresh ─────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if _level == null or _active_wave < 0 or _active_wave >= _level.waves.size():
		return
	_refreshing = true
	var w: Dictionary = _level.waves[_active_wave]
	if _is_special_dd != null:
		var current: String = String(w.get("is_special", "normal"))
		var found: int = -1
		for i in _is_special_dd.item_count:
			if String(_is_special_dd.get_item_metadata(i)) == current:
				found = i
				break
		if found < 0:
			# Legacy free-form value not in current preset enum (none in shipping
			# maps, but possible if someone hand-edited JSON). Display as "normal";
			# saving overwrites only if user touches the dropdown.
			GameLogger.warn("WaveSection",
				"is_special '%s' not in preset enum, displaying as 'normal'" % current)
			found = 0
		_is_special_dd.select(found)
	if _ttn_spin != null:
		_ttn_spin.set_value_no_signal(int(w.get("turns_to_next", 0)))
	if _advance_mode_dd != null:
		var am: String = String(w.get("advance_mode", "timer"))
		for i in _advance_mode_dd.item_count:
			if String(_advance_mode_dd.get_item_metadata(i)) == am:
				_advance_mode_dd.select(i)
				break
	if _music_config_edit != null:
		var mc_v: Variant = w.get("music_config", {})
		var mc: Dictionary = mc_v if mc_v is Dictionary else {}
		_music_config_edit.text = "" if mc.is_empty() else JSON.stringify(mc)
	_refreshing = false


# ── Helpers ─────────────────────────────────────────────────────────────────

func _make_label(loc_key: String, fallback: String) -> Label:
	var lbl := Label.new()
	lbl.text = Localization.t(loc_key, fallback)
	UiTheme.apply_label_kind(lbl, "dim")
	return lbl


func _emit_field(field: String, value: Variant) -> void:
	if _refreshing:
		return
	wave_field_changed.emit(_active_wave, field, value)


# ── Signal handlers ─────────────────────────────────────────────────────────

func _on_is_special_selected(idx: int) -> void:
	_emit_field("is_special", String(_is_special_dd.get_item_metadata(idx)))


func _on_ttn_changed(v: float) -> void:
	_emit_field("turns_to_next", int(v))


func _on_advance_mode_selected(idx: int) -> void:
	_emit_field("advance_mode", String(_advance_mode_dd.get_item_metadata(idx)))


func _on_music_config_submitted(text: String) -> void:
	var trimmed: String = text.strip_edges()
	if trimmed == "":
		_emit_field("music_config", {})
		return
	var parsed: Variant = JSON.parse_string(trimmed)
	if not (parsed is Dictionary):
		GameLogger.warn("WaveSettingsWaveSection",
			"music_config edit rejected — invalid JSON object: " + trimmed)
		return
	_emit_field("music_config", parsed)
