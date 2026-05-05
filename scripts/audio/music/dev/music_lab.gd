## MusicLab — dev scene. Run via F6 / "Run Specific Scene".
## UI built in code at _ready — no @onready, no editor-time freeze.

extends Control

const _PresetResolver  = preload("res://scripts/audio/music/preset_resolver.gd")
const _Harmony         = preload("res://scripts/audio/music/harmony.gd")
const _DrumPatterns    = preload("res://scripts/audio/music/drum_patterns.gd")
const _BassPatterns    = preload("res://scripts/audio/music/bass_patterns.gd")
const _PadGenSrc       = preload("res://scripts/audio/music/generators/pad_gen.gd")
const STINGS_PATH: String = "res://data/music/stings.json"

const BARS_PER_CHORD_OPTS: Array = [1, 2, 4, 8]

var _director: Node = null
var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _slot_a: Dictionary = {}
var _slot_b: Dictionary = {}
var _current_ab: StringName = &"none"

var _state_dropdown:        OptionButton = null
var _seed_spin:             SpinBox = null
var _preset_dropdown:       OptionButton = null
var _progression_dropdown:  OptionButton = null
var _scale_dropdown:        OptionButton = null
var _bars_dropdown:         OptionButton = null
var _drum_dropdown:         OptionButton = null
var _bass_dropdown:         OptionButton = null
var _voicing_dropdown:      OptionButton = null

var _stings_hbox: HFlowContainer = null

func _ready() -> void:
	_director = get_node_or_null("/root/MusicDirector")
	if _director == null:
		push_error("[MusicLab] MusicDirector not found")
		return
	_build_ui()
	# Push current UI defaults into director BEFORE starting playback.
	# Without this, Conductor.samples_per_beat stays at 0.0 → infinite loop
	# in advance() on first _process tick. (See spec 042 retro.)
	_director.set_seed(int(_seed_spin.value))
	_director.set_bpm(_sliders["bpm"].value)
	_director.set_lead_density(
		_sliders["lead_density_calm"].value,
		_sliders["lead_density_battle"].value)
	_director.set_layer_db(&"pad",   _sliders["pad_gain_db"].value)
	_director.set_layer_db(&"drums", _sliders["drums_gain_db"].value)
	_director.set_progression(_dropdown_value(_progression_dropdown))
	_director.set_scale(_dropdown_value(_scale_dropdown))
	_director.set_bars_per_chord(BARS_PER_CHORD_OPTS[_bars_dropdown.selected])
	_director.set_drum_pattern(_dropdown_value(_drum_dropdown))
	_director.set_bass_pattern(_dropdown_value(_bass_dropdown))
	_director.set_pad_voicing(_dropdown_value(_voicing_dropdown))
	# Immediate, not pending — first bar event hasn't been emitted yet.
	_director._apply_state(&"calm")
	_director._ensure_playing()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var header := Label.new()
	header.text = Localization.t("ui_music_lab_title", "Music Lab - music tuning")
	vbox.add_child(header)

	# ── Sliders ──────────────────────────────────────────────────────────────
	var params_hbox := HBoxContainer.new()
	params_hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(params_hbox)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	params_hbox.add_child(left)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	params_hbox.add_child(right)

	_make_slider(left,  "bpm",                40.0, 200.0, 96.0)
	_make_slider(left,  "lead_density_calm",   0.0,   1.0, 0.3)
	_make_slider(left,  "lead_density_battle", 0.0,   1.0, 0.7)
	_make_slider(right, "pad_gain_db",       -24.0,   6.0, 0.0)
	_make_slider(right, "drums_gain_db",     -24.0,   6.0, 0.0)
	_make_slider(right, "master_gain_db",    -24.0,   6.0, 0.0)

	# ── State + seed ─────────────────────────────────────────────────────────
	var state_row := HBoxContainer.new()
	vbox.add_child(state_row)
	_lbl(state_row, Localization.t("ui_music_lab_state_label", "State: "))

	_state_dropdown = OptionButton.new()
	for s in ["calm", "battle", "menu"]:
		_state_dropdown.add_item(s)
	_state_dropdown.item_selected.connect(_on_state)
	state_row.add_child(_state_dropdown)

	_lbl(state_row, Localization.t("ui_music_lab_seed_label", "  Seed: "))
	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0
	_seed_spin.max_value = 2147483647
	_seed_spin.value = 42
	_seed_spin.value_changed.connect(func(v): _director.set_seed(int(v)))
	state_row.add_child(_seed_spin)

	var reroll := Button.new()
	reroll.text = Localization.t("ui_music_lab_reroll", "Reroll")
	reroll.pressed.connect(func():
		var s := randi() & 0x7fffffff
		_seed_spin.value = float(s)
		_director.set_seed(s))
	state_row.add_child(reroll)

	# ── Music structure dropdowns ────────────────────────────────────────────
	var struct_row1 := HBoxContainer.new()
	vbox.add_child(struct_row1)

	_progression_dropdown = _make_dropdown(struct_row1, Localization.t("ui_music_lab_progression_label", "Progression:"),
			_Harmony.list_progression_ids(), "am_f_c_g",
			func(id): _director.set_progression(StringName(id)))
	_scale_dropdown = _make_dropdown(struct_row1, Localization.t("ui_music_lab_scale_label", "  Scale:"),
			_Harmony.list_scale_ids(), "natural_minor",
			func(id): _director.set_scale(StringName(id)))

	var struct_row2 := HBoxContainer.new()
	vbox.add_child(struct_row2)

	_bars_dropdown = _make_dropdown(struct_row2, Localization.t("ui_music_lab_bars_label", "Bars/chord:"),
			["1", "2", "4", "8"], "1",
			func(s): _director.set_bars_per_chord(int(s)))
	_drum_dropdown = _make_dropdown(struct_row2, Localization.t("ui_music_lab_drums_label", "  Drums:"),
			_DrumPatterns.list_ids(), "march",
			func(id): _director.set_drum_pattern(StringName(id)))

	var struct_row3 := HBoxContainer.new()
	vbox.add_child(struct_row3)

	_bass_dropdown = _make_dropdown(struct_row3, Localization.t("ui_music_lab_bass_label", "Bass:"),
			_BassPatterns.list_ids(), "root_fifth",
			func(id): _director.set_bass_pattern(StringName(id)))
	_voicing_dropdown = _make_dropdown(struct_row3, Localization.t("ui_music_lab_pad_voicing_label", "  Pad voicing:"),
			_PadGenSrc.list_voicing_ids(), "triad",
			func(id): _director.set_pad_voicing(StringName(id)))

	# ── Presets + A/B ────────────────────────────────────────────────────────
	var preset_row := HBoxContainer.new()
	vbox.add_child(preset_row)
	_lbl(preset_row, Localization.t("ui_music_lab_preset_label", "Preset: "))

	_preset_dropdown = OptionButton.new()
	for id in _PresetResolver.list_preset_ids():
		_preset_dropdown.add_item(id)
	preset_row.add_child(_preset_dropdown)

	var apply_btn := Button.new()
	apply_btn.text = Localization.t("ui_music_lab_apply", "Apply")
	apply_btn.pressed.connect(_on_apply_preset)
	preset_row.add_child(apply_btn)

	var save_a := Button.new(); save_a.text = Localization.t("ui_music_lab_save_a", "Save A")
	save_a.pressed.connect(func(): _slot_a = _gather(); _current_ab = &"A")
	preset_row.add_child(save_a)

	var save_b := Button.new(); save_b.text = Localization.t("ui_music_lab_save_b", "Save B")
	save_b.pressed.connect(func(): _slot_b = _gather(); _current_ab = &"B")
	preset_row.add_child(save_b)

	var sw := Button.new(); sw.text = Localization.t("ui_music_lab_switch_ab", "Switch A<>B")
	sw.pressed.connect(_on_switch)
	preset_row.add_child(sw)

	# ── Stings ───────────────────────────────────────────────────────────────
	_lbl(vbox, Localization.t("ui_music_lab_stings_label", "Stings:"))
	_stings_hbox = HFlowContainer.new()
	vbox.add_child(_stings_hbox)
	_build_stings()

	# ── Export / transport ───────────────────────────────────────────────────
	var export_row := HBoxContainer.new()
	vbox.add_child(export_row)

	var copy_btn := Button.new(); copy_btn.text = Localization.t("ui_music_lab_copy_json", "Copy JSON")
	copy_btn.pressed.connect(func():
		DisplayServer.clipboard_set(JSON.stringify({"music_config": _gather()}, "  "))
		EventBus.ui_toast_requested.emit(Localization.t("ui_music_lab_copied", "Copied!"), 2.0, &"info"))
	export_row.add_child(copy_btn)

	var stop_btn := Button.new(); stop_btn.text = Localization.t("ui_music_lab_stop", "Stop")
	stop_btn.pressed.connect(func(): _director._stop())
	export_row.add_child(stop_btn)

	var start_btn := Button.new(); start_btn.text = Localization.t("ui_music_lab_start", "Start")
	start_btn.pressed.connect(func(): _director._ensure_playing())
	export_row.add_child(start_btn)

# ── Helpers ──────────────────────────────────────────────────────────────────

func _lbl(parent: Node, text: String) -> void:
	var l := Label.new(); l.text = text; parent.add_child(l)

func _make_slider(parent: VBoxContainer, param: String,
		mn: float, mx: float, def: float) -> void:
	var row := HBoxContainer.new(); parent.add_child(row)
	var lbl := Label.new(); lbl.text = param
	lbl.custom_minimum_size = Vector2(190, 0); row.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = mn; sl.max_value = mx; sl.value = def; sl.step = 0.01
	sl.custom_minimum_size = Vector2(160, 0); row.add_child(sl)
	var vl := Label.new(); vl.text = "%.2f" % def
	vl.custom_minimum_size = Vector2(50, 0); row.add_child(vl)
	_sliders[param] = sl; _value_labels[param] = vl
	sl.value_changed.connect(_on_slider.bind(param))

## Build labelled OptionButton with default-by-text-match.
## on_change signature: func(id_string: String) -> void
func _make_dropdown(parent: Node, label: String, ids: Array, default: String,
		on_change: Callable) -> OptionButton:
	_lbl(parent, label)
	var dd := OptionButton.new()
	var default_idx := 0
	for i in ids.size():
		dd.add_item(String(ids[i]))
		if String(ids[i]) == default:
			default_idx = i
	dd.selected = default_idx
	dd.item_selected.connect(func(idx: int):
		on_change.call(dd.get_item_text(idx)))
	parent.add_child(dd)
	return dd

func _dropdown_value(dd: OptionButton) -> StringName:
	if dd == null or dd.item_count == 0:
		return &""
	return StringName(dd.get_item_text(dd.selected))

func _build_stings() -> void:
	if not FileAccess.file_exists(STINGS_PATH): return
	var f := FileAccess.open(STINGS_PATH, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary: return
	for name in d.get("stings", {}).keys():
		var btn := Button.new(); btn.text = name
		btn.pressed.connect(func(): _director.play_sting(StringName(name)))
		_stings_hbox.add_child(btn)

func _on_slider(value: float, param: String) -> void:
	if _value_labels.has(param):
		_value_labels[param].text = "%.2f" % value
	if _director == null: return
	match param:
		"bpm": _director.set_bpm(value)
		"lead_density_calm", "lead_density_battle":
			_director.set_lead_density(
				_sliders["lead_density_calm"].value,
				_sliders["lead_density_battle"].value)
		"pad_gain_db":   _director.set_layer_db(&"pad", value)
		"drums_gain_db": _director.set_layer_db(&"drums", value)
		"master_gain_db":
			var bus := AudioServer.get_bus_index("Music")
			if bus >= 0: AudioServer.set_bus_volume_db(bus, value)

func _on_state(idx: int) -> void:
	var states := [&"calm", &"battle", &"menu"]
	if _director != null: _director._apply_state(states[idx])

func _on_apply_preset() -> void:
	if _preset_dropdown.item_count == 0: return
	_apply(_PresetResolver.resolve({"preset": _preset_dropdown.get_item_text(_preset_dropdown.selected)}))

func _on_switch() -> void:
	if _current_ab == &"A" and not _slot_b.is_empty():
		_apply(_slot_b); _current_ab = &"B"
	elif _current_ab == &"B" and not _slot_a.is_empty():
		_apply(_slot_a); _current_ab = &"A"

func _gather() -> Dictionary:
	var out := {}
	for p in _sliders: out[p] = _sliders[p].value
	out["seed"]           = int(_seed_spin.value)
	out["base_state"]     = _state_dropdown.get_item_text(_state_dropdown.selected)
	out["progression"]    = _progression_dropdown.get_item_text(_progression_dropdown.selected)
	out["scale"]          = _scale_dropdown.get_item_text(_scale_dropdown.selected)
	out["bars_per_chord"] = BARS_PER_CHORD_OPTS[_bars_dropdown.selected]
	out["drum_pattern"]   = _drum_dropdown.get_item_text(_drum_dropdown.selected)
	out["bass_pattern"]   = _bass_dropdown.get_item_text(_bass_dropdown.selected)
	out["pad_voicing"]    = _voicing_dropdown.get_item_text(_voicing_dropdown.selected)
	return out

func _apply(params: Dictionary) -> void:
	for p in _sliders:
		if params.has(p): _sliders[p].value = float(params[p])
	if params.has("seed"): _seed_spin.value = float(int(params["seed"]))
	if params.has("base_state"):
		var idx := ["calm","battle","menu"].find(String(params["base_state"]))
		if idx >= 0: _state_dropdown.selected = idx; _on_state(idx)
	_apply_dropdown(_progression_dropdown, params, "progression",
			func(s): _director.set_progression(StringName(s)))
	_apply_dropdown(_scale_dropdown, params, "scale",
			func(s): _director.set_scale(StringName(s)))
	if params.has("bars_per_chord"):
		var n := int(params["bars_per_chord"])
		var bidx := BARS_PER_CHORD_OPTS.find(n)
		if bidx >= 0:
			_bars_dropdown.selected = bidx
			_director.set_bars_per_chord(n)
	_apply_dropdown(_drum_dropdown, params, "drum_pattern",
			func(s): _director.set_drum_pattern(StringName(s)))
	_apply_dropdown(_bass_dropdown, params, "bass_pattern",
			func(s): _director.set_bass_pattern(StringName(s)))
	_apply_dropdown(_voicing_dropdown, params, "pad_voicing",
			func(s): _director.set_pad_voicing(StringName(s)))

func _apply_dropdown(dd: OptionButton, params: Dictionary, key: String,
		on_apply: Callable) -> void:
	if not params.has(key) or dd == null:
		return
	var target := String(params[key])
	for i in dd.item_count:
		if dd.get_item_text(i) == target:
			dd.selected = i
			on_apply.call(target)
			return
