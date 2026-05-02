## MusicLab — dev scene. Запускай через Project → Run Specific Scene.
## UI строится кодом в _ready — никаких @onready, никакого зависания редактора.

extends Control

const _PresetResolver = preload("res://scripts/audio/music/preset_resolver.gd")
const STINGS_PATH: String = "res://data/music/stings.json"

var _director: Node = null
var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _slot_a: Dictionary = {}
var _slot_b: Dictionary = {}
var _current_ab: StringName = &"none"
var _state_dropdown: OptionButton = null
var _seed_spin: SpinBox = null
var _preset_dropdown: OptionButton = null
var _stings_hbox: HFlowContainer = null

func _ready() -> void:
	_director = get_node_or_null("/root/MusicDirector")
	if _director == null:
		push_error("[MusicLab] MusicDirector not found")
		return
	_build_ui()
	_director.set_state(&"calm")
	_director._ensure_playing()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var header := Label.new()
	header.text = "Music Lab — тюнинг музыки"
	vbox.add_child(header)

	var params_hbox := HBoxContainer.new()
	params_hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(params_hbox)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	params_hbox.add_child(left)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	params_hbox.add_child(right)

	_make_slider(left,  "bpm",                40.0, 200.0, 72.0)
	_make_slider(left,  "lead_density_calm",   0.0,   1.0, 0.2)
	_make_slider(left,  "lead_density_battle", 0.0,   1.0, 0.5)
	_make_slider(right, "pad_gain_db",       -24.0,   6.0, 0.0)
	_make_slider(right, "drums_gain_db",     -24.0,   6.0, 0.0)
	_make_slider(right, "master_gain_db",    -24.0,   6.0, 0.0)

	var state_row := HBoxContainer.new()
	vbox.add_child(state_row)
	_lbl(state_row, "State: ")

	_state_dropdown = OptionButton.new()
	for s in ["calm", "battle", "menu"]:
		_state_dropdown.add_item(s)
	_state_dropdown.item_selected.connect(_on_state)
	state_row.add_child(_state_dropdown)

	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0
	_seed_spin.max_value = 2147483647
	_seed_spin.value = 42
	_seed_spin.value_changed.connect(func(v): _director.set_seed(int(v)))
	state_row.add_child(_seed_spin)

	var reroll := Button.new()
	reroll.text = "Reroll seed"
	reroll.pressed.connect(func():
		var s := randi() & 0x7fffffff
		_seed_spin.value = float(s)
		_director.set_seed(s))
	state_row.add_child(reroll)

	var preset_row := HBoxContainer.new()
	vbox.add_child(preset_row)
	_lbl(preset_row, "Preset: ")

	_preset_dropdown = OptionButton.new()
	for id in _PresetResolver.list_preset_ids():
		_preset_dropdown.add_item(id)
	preset_row.add_child(_preset_dropdown)

	var apply_btn := Button.new()
	apply_btn.text = "Apply"
	apply_btn.pressed.connect(_on_apply_preset)
	preset_row.add_child(apply_btn)

	var save_a := Button.new(); save_a.text = "Save A"
	save_a.pressed.connect(func(): _slot_a = _gather(); _current_ab = &"A")
	preset_row.add_child(save_a)

	var save_b := Button.new(); save_b.text = "Save B"
	save_b.pressed.connect(func(): _slot_b = _gather(); _current_ab = &"B")
	preset_row.add_child(save_b)

	var sw := Button.new(); sw.text = "Switch A<>B"
	sw.pressed.connect(_on_switch)
	preset_row.add_child(sw)

	_lbl(vbox, "Стинги:")
	_stings_hbox = HFlowContainer.new()
	vbox.add_child(_stings_hbox)
	_build_stings()

	var export_row := HBoxContainer.new()
	vbox.add_child(export_row)

	var copy_btn := Button.new(); copy_btn.text = "Copy JSON"
	copy_btn.pressed.connect(func():
		DisplayServer.clipboard_set(JSON.stringify({"music_config": _gather()}, "  "))
		EventBus.ui_toast_requested.emit("Copied!", 2.0, &"info"))
	export_row.add_child(copy_btn)

	var stop_btn := Button.new(); stop_btn.text = "Stop"
	stop_btn.pressed.connect(func(): _director._stop())
	export_row.add_child(stop_btn)

	var start_btn := Button.new(); start_btn.text = "Start"
	start_btn.pressed.connect(func(): _director._ensure_playing())
	export_row.add_child(start_btn)

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
	out["seed"] = int(_seed_spin.value)
	out["base_state"] = _state_dropdown.get_item_text(_state_dropdown.selected)
	return out

func _apply(params: Dictionary) -> void:
	for p in _sliders:
		if params.has(p): _sliders[p].value = float(params[p])
	if params.has("seed"): _seed_spin.value = float(int(params["seed"]))
	if params.has("base_state"):
		var idx := ["calm","battle","menu"].find(String(params["base_state"]))
		if idx >= 0: _state_dropdown.selected = idx; _on_state(idx)
