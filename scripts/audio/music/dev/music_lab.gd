## MusicLab — dev scene controller. F6 to run standalone.
## All sliders write through MusicDirector's public API — guaranteed identical
## to what the game hears at runtime with the same config.

extends Control

const _PresetResolver = preload("res://scripts/audio/music/preset_resolver.gd")
const STINGS_PATH: String = "res://data/music/stings.json"

# Node refs (resolved in _ready)
var _director: Node = null   # MusicDirector autoload

@onready var _params_left:     VBoxContainer   = $Margin/VBox/ParamsHBox/ParamsLeft
@onready var _params_right:    VBoxContainer   = $Margin/VBox/ParamsHBox/ParamsRight
@onready var _state_dropdown:  OptionButton    = $Margin/VBox/StateRow/StateDropdown
@onready var _seed_spin:       SpinBox         = $Margin/VBox/StateRow/SeedSpin
@onready var _reroll_btn:      Button          = $Margin/VBox/StateRow/ReRollBtn
@onready var _preset_dropdown: OptionButton    = $Margin/VBox/PresetRow/PresetDropdown
@onready var _load_preset_btn: Button          = $Margin/VBox/PresetRow/LoadPresetBtn
@onready var _save_a_btn:      Button          = $Margin/VBox/PresetRow/SaveABtn
@onready var _save_b_btn:      Button          = $Margin/VBox/PresetRow/SaveBBtn
@onready var _switch_ab_btn:   Button          = $Margin/VBox/PresetRow/SwitchABBtn
@onready var _stings_hbox:     HFlowContainer  = $Margin/VBox/StingsHBox
@onready var _copy_json_btn:   Button          = $Margin/VBox/ExportRow/CopyJsonBtn
@onready var _stop_btn:        Button          = $Margin/VBox/ExportRow/StopBtn
@onready var _start_btn:       Button          = $Margin/VBox/ExportRow/StartBtn

# Parameter storage — slider rows keyed by param name.
var _sliders: Dictionary = {}   # {param_name: HSlider}
var _value_labels: Dictionary = {}  # {param_name: Label}

# A/B memory slots.
var _slot_a: Dictionary = {}
var _slot_b: Dictionary = {}
var _current_ab: StringName = &"none"   # &"A" or &"B"

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	if not is_node_ready():
		await ready

	_director = get_node_or_null("/root/MusicDirector")
	if _director == null:
		push_error("[MusicLab] MusicDirector autoload not found — run from project root")
		return

	_build_sliders()
	_build_state_dropdown()
	_build_preset_dropdown()
	_build_sting_buttons()
	_connect_buttons()

	# Start calm.
	_director.set_state(&"calm")
	_director._ensure_playing()

# ── Sliders ───────────────────────────────────────────────────────────────────

func _build_sliders() -> void:
	var left_params: Array = [
		["bpm",              40.0, 200.0, 96.0],
		["lead_density_calm",   0.0,  1.0, 0.3],
		["lead_density_battle", 0.0,  1.0, 0.7],
	]
	var right_params: Array = [
		["pad_gain_db",    -24.0, 6.0, 0.0],
		["drums_gain_db",  -24.0, 6.0, 0.0],
		["master_gain_db", -24.0, 6.0, 0.0],
	]
	for p in left_params:
		_make_slider_row(_params_left, p[0], p[1], p[2], p[3])
	for p in right_params:
		_make_slider_row(_params_right, p[0], p[1], p[2], p[3])

func _make_slider_row(parent: VBoxContainer, param: String,
		min_v: float, max_v: float, default_v: float) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)

	var lbl: Label = Label.new()
	lbl.text = param
	lbl.custom_minimum_size = Vector2(200, 0)
	row.add_child(lbl)

	var slider: HSlider = HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.value     = default_v
	slider.step      = 0.01
	slider.custom_minimum_size = Vector2(200, 0)
	row.add_child(slider)

	var val_lbl: Label = Label.new()
	val_lbl.text = "%.2f" % default_v
	val_lbl.custom_minimum_size = Vector2(60, 0)
	row.add_child(val_lbl)

	_sliders[param]      = slider
	_value_labels[param] = val_lbl

	slider.value_changed.connect(_on_slider_changed.bind(param))

func _on_slider_changed(value: float, param: String) -> void:
	if _value_labels.has(param):
		_value_labels[param].text = "%.2f" % value
	_push_param(param, value)

func _push_param(param: String, value: float) -> void:
	if _director == null:
		return
	match param:
		"bpm":
			_director.set_bpm(value)
		"lead_density_calm", "lead_density_battle":
			var calm: float   = _sliders["lead_density_calm"].value
			var battle: float = _sliders["lead_density_battle"].value
			_director.set_lead_density(calm, battle)
		"pad_gain_db":
			_director.set_layer_db(&"pad", value)
		"drums_gain_db":
			_director.set_layer_db(&"drums", value)
		"master_gain_db":
			var bus_idx: int = AudioServer.get_bus_index("Music")
			if bus_idx >= 0:
				AudioServer.set_bus_volume_db(bus_idx, value)

# ── State dropdown ────────────────────────────────────────────────────────────

func _build_state_dropdown() -> void:
	for s in ["calm", "battle", "menu"]:
		_state_dropdown.add_item(s)
	_state_dropdown.selected = 0
	_state_dropdown.item_selected.connect(_on_state_selected)

func _on_state_selected(idx: int) -> void:
	var states: Array = [&"calm", &"battle", &"menu"]
	if _director != null:
		_director.set_state(states[idx])
		# Force immediate apply (bar boundary normally; in lab apply now).
		_director._pending_state = &""
		_director._apply_state(states[idx])

# ── Preset dropdown ───────────────────────────────────────────────────────────

func _build_preset_dropdown() -> void:
	var ids: Array = _PresetResolver.list_preset_ids()
	for id in ids:
		_preset_dropdown.add_item(id)
	_load_preset_btn.pressed.connect(_on_apply_preset)

func _on_apply_preset() -> void:
	if _preset_dropdown.item_count == 0:
		return
	var id: String = _preset_dropdown.get_item_text(_preset_dropdown.selected)
	var cfg: Dictionary = _PresetResolver.resolve({"preset": id})
	_apply_params(cfg)

# ── Sting buttons ─────────────────────────────────────────────────────────────

func _build_sting_buttons() -> void:
	if not FileAccess.file_exists(STINGS_PATH):
		return
	var f: FileAccess = FileAccess.open(STINGS_PATH, FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return
	var stings: Dictionary = d.get("stings", {})
	for name in stings.keys():
		var btn: Button = Button.new()
		btn.text = "▶ %s (%s)" % [name, String(stings[name].get("kind", "?"))]
		btn.pressed.connect(_on_sting_pressed.bind(StringName(name)))
		_stings_hbox.add_child(btn)

func _on_sting_pressed(name: StringName) -> void:
	if _director != null:
		_director.play_sting(name)

# ── A/B slots ─────────────────────────────────────────────────────────────────

func _connect_buttons() -> void:
	_reroll_btn.pressed.connect(_on_reroll)
	_seed_spin.value_changed.connect(_on_seed_changed)
	_save_a_btn.pressed.connect(_on_save_a)
	_save_b_btn.pressed.connect(_on_save_b)
	_switch_ab_btn.pressed.connect(_on_switch_ab)
	_copy_json_btn.pressed.connect(_on_copy_json)
	_stop_btn.pressed.connect(_on_stop)
	_start_btn.pressed.connect(_on_start)

func _on_reroll() -> void:
	var seed: int = randi() & 0x7fffffff
	_seed_spin.value = float(seed)
	if _director != null:
		_director.set_seed(seed)

func _on_seed_changed(value: float) -> void:
	if _director != null:
		_director.set_seed(int(value))

func _on_save_a() -> void:
	_slot_a = _gather_current_params()
	_current_ab = &"A"
	push_warning("[MusicLab] Saved to slot A")

func _on_save_b() -> void:
	_slot_b = _gather_current_params()
	_current_ab = &"B"
	push_warning("[MusicLab] Saved to slot B")

func _on_switch_ab() -> void:
	if _current_ab == &"A" and not _slot_b.is_empty():
		_apply_params(_slot_b)
		_current_ab = &"B"
	elif _current_ab == &"B" and not _slot_a.is_empty():
		_apply_params(_slot_a)
		_current_ab = &"A"
	else:
		push_warning("[MusicLab] No slot saved to switch to — use Save A / Save B first")

# ── Export ────────────────────────────────────────────────────────────────────

func _on_copy_json() -> void:
	var snippet: Dictionary = {"music_config": _gather_current_params()}
	DisplayServer.clipboard_set(JSON.stringify(snippet, "  "))
	# Toast via EventBus if available.
	if EventBus.has_signal("ui_toast_requested"):
		EventBus.ui_toast_requested.emit("Copied to clipboard", 2.0, &"info")
	else:
		push_warning("[MusicLab] Copied JSON to clipboard")

func _on_stop() -> void:
	if _director != null:
		_director._stop()

func _on_start() -> void:
	if _director != null:
		_director._ensure_playing()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _gather_current_params() -> Dictionary:
	var out: Dictionary = {}
	for param in _sliders.keys():
		out[param] = _sliders[param].value
	out["seed"]       = int(_seed_spin.value)
	out["base_state"] = _state_dropdown.get_item_text(_state_dropdown.selected)
	return out

func _apply_params(params: Dictionary) -> void:
	for param in _sliders.keys():
		if params.has(param):
			_sliders[param].value = float(params[param])
			# slider.value_changed fires automatically → _on_slider_changed → _push_param
	if params.has("seed"):
		_seed_spin.value = float(int(params["seed"]))
	if params.has("base_state"):
		var states: Array = ["calm", "battle", "menu"]
		var idx: int = states.find(String(params["base_state"]))
		if idx >= 0:
			_state_dropdown.selected = idx
			_on_state_selected(idx)
	if params.has("bpm") and _director != null:
		_director.set_bpm(float(params["bpm"]))
