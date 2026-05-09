class_name WaveSettingsSpawnersSection
extends VBoxContainer

## Spawners section of WaveSettingsPanel. ItemList of active wave's spawners
## + edit form for the selected one. kind is read-only (kind change goes
## through delete + paint per AC12). amount/delay tagged "(schema-only)"
## when > 1 — runtime ignores them in 061.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")
const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

signal spawner_field_changed(coord: Vector2i, fields: Dictionary)

var _level: LevelData = null
var _active_wave: int = 0
var _selected_idx: int = -1
var _refreshing: bool = false

var _list: ItemList
var _form_box: VBoxContainer
var _form_kind_label: Label
var _form_ref_dd: OptionButton
var _form_timer_spin: SpinBox
var _form_amount_spin: SpinBox
var _form_amount_tag: Label
var _form_delay_spin: SpinBox
var _form_delay_tag: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_build()


func bind_level(level: LevelData) -> void:
	_level = level
	if level != null:
		_active_wave = level.get_active_wave_index()
	_selected_idx = -1
	_refresh()


func set_active_wave(idx: int) -> void:
	_active_wave = idx
	_selected_idx = -1
	_refresh()


# ── Build ───────────────────────────────────────────────────────────────────

func _build() -> void:
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 90)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	add_child(_list)

	_form_box = VBoxContainer.new()
	_form_box.visible = false
	add_child(_form_box)

	# kind (read-only)
	var kind_row := HBoxContainer.new()
	_form_box.add_child(kind_row)
	var kind_lbl := _make_label("ui_spawner_form_kind", "kind:")
	kind_lbl.custom_minimum_size = Vector2(80, 0)
	kind_row.add_child(kind_lbl)
	_form_kind_label = Label.new()
	kind_row.add_child(_form_kind_label)

	# ref dropdown
	var ref_row := HBoxContainer.new()
	_form_box.add_child(ref_row)
	var ref_lbl := _make_label("ui_spawner_form_ref", "ref:")
	ref_lbl.custom_minimum_size = Vector2(80, 0)
	ref_row.add_child(ref_lbl)
	_form_ref_dd = OptionButton.new()
	_form_ref_dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form_ref_dd.item_selected.connect(_on_ref_selected)
	ref_row.add_child(_form_ref_dd)
	_populate_ref_dropdown()

	# timer
	var t_row := HBoxContainer.new()
	_form_box.add_child(t_row)
	var t_lbl := _make_label("ui_spawner_form_timer", "timer:")
	t_lbl.custom_minimum_size = Vector2(80, 0)
	t_row.add_child(t_lbl)
	_form_timer_spin = SpinBox.new()
	_form_timer_spin.min_value = 1
	_form_timer_spin.max_value = 999
	_form_timer_spin.step = 1
	_form_timer_spin.value_changed.connect(_on_timer_changed)
	t_row.add_child(_form_timer_spin)

	# amount + tag
	var a_row := HBoxContainer.new()
	_form_box.add_child(a_row)
	var a_lbl := _make_label("ui_spawner_form_amount", "amount:")
	a_lbl.custom_minimum_size = Vector2(80, 0)
	a_row.add_child(a_lbl)
	_form_amount_spin = SpinBox.new()
	_form_amount_spin.min_value = 1
	_form_amount_spin.max_value = 99
	_form_amount_spin.step = 1
	_form_amount_spin.value_changed.connect(_on_amount_changed)
	a_row.add_child(_form_amount_spin)
	_form_amount_tag = Label.new()
	_form_amount_tag.text = Localization.t(
		"ui_spawner_form_amount_schema_only", "(schema-only)")
	UiTheme.apply_label_kind(_form_amount_tag, "dim")
	_form_amount_tag.visible = false
	a_row.add_child(_form_amount_tag)

	# delay + tag
	var d_row := HBoxContainer.new()
	_form_box.add_child(d_row)
	var d_lbl := _make_label("ui_spawner_form_delay", "delay:")
	d_lbl.custom_minimum_size = Vector2(80, 0)
	d_row.add_child(d_lbl)
	_form_delay_spin = SpinBox.new()
	_form_delay_spin.min_value = 1
	_form_delay_spin.max_value = 99
	_form_delay_spin.step = 1
	_form_delay_spin.value_changed.connect(_on_delay_changed)
	d_row.add_child(_form_delay_spin)
	_form_delay_tag = Label.new()
	_form_delay_tag.text = Localization.t(
		"ui_spawner_form_amount_schema_only", "(schema-only)")
	UiTheme.apply_label_kind(_form_delay_tag, "dim")
	_form_delay_tag.visible = false
	d_row.add_child(_form_delay_tag)


func _populate_ref_dropdown() -> void:
	# Mirror SpawnerPalette — DirAccess scan of data/enemies/. There's no
	# EnemyDB autoload; same lex sort means same dropdown index across panels.
	if _form_ref_dd == null:
		return
	_form_ref_dd.clear()
	var dir := DirAccess.open("res://data/enemies/")
	if dir == null:
		GameLogger.warn("WaveSettingsSpawnersSection",
			"data/enemies/ not openable — ref dropdown empty")
		return
	var ids: Array[StringName] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			ids.append(StringName(fname.get_basename()))
		fname = dir.get_next()
	dir.list_dir_end()
	ids.sort_custom(func(a, b): return String(a) < String(b))
	for i in ids.size():
		var id: StringName = ids[i]
		_form_ref_dd.add_item(String(id), i)
		_form_ref_dd.set_item_metadata(i, id)


# ── Refresh ─────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if _list == null or _level == null:
		return
	_refreshing = true
	_list.clear()
	if _active_wave < 0 or _active_wave >= _level.waves.size():
		_refreshing = false
		_form_box.visible = false
		return
	var spawners: Array = _level.waves[_active_wave].get("spawners", [])
	for s in spawners:
		var coord: Vector2i = s.get("coord", Vector2i.ZERO)
		_list.add_item("%s %s @ (%d,%d) · t=%d a=%d d=%d" % [
			str(s.get("kind", &"")), str(s.get("ref", &"")),
			coord.x, coord.y,
			int(s.get("timer", 1)), int(s.get("amount", 1)), int(s.get("delay", 1)),
		])
	if _selected_idx < 0 or _selected_idx >= spawners.size():
		_form_box.visible = false
	else:
		_list.select(_selected_idx)
		_open_form(spawners[_selected_idx])
	_refreshing = false


func _open_form(s: Dictionary) -> void:
	_refreshing = true
	_form_box.visible = true
	if _form_kind_label != null:
		_form_kind_label.text = str(s.get("kind", &""))
	if _form_ref_dd != null:
		var saved_ref: StringName = StringName(str(s.get("ref", "")))
		for i in _form_ref_dd.item_count:
			if StringName(str(_form_ref_dd.get_item_metadata(i))) == saved_ref:
				_form_ref_dd.select(i)
				break
	if _form_timer_spin != null:
		_form_timer_spin.set_value_no_signal(int(s.get("timer", 1)))
	if _form_amount_spin != null:
		var amt: int = int(s.get("amount", 1))
		_form_amount_spin.set_value_no_signal(amt)
		_form_amount_tag.visible = (amt > 1)
	if _form_delay_spin != null:
		var dly: int = int(s.get("delay", 1))
		_form_delay_spin.set_value_no_signal(dly)
		_form_delay_tag.visible = (dly > 1)
	_refreshing = false


func _selected_coord() -> Vector2i:
	if _level == null or _active_wave < 0 or _active_wave >= _level.waves.size():
		return Vector2i.ZERO
	var spawners: Array = _level.waves[_active_wave].get("spawners", [])
	if _selected_idx < 0 or _selected_idx >= spawners.size():
		return Vector2i.ZERO
	return spawners[_selected_idx].get("coord", Vector2i.ZERO)


# ── Helpers ─────────────────────────────────────────────────────────────────

func _make_label(loc_key: String, fallback: String) -> Label:
	var lbl := Label.new()
	lbl.text = Localization.t(loc_key, fallback)
	UiTheme.apply_label_kind(lbl, "dim")
	return lbl


func _emit_field(field: String, value: Variant) -> void:
	if _refreshing:
		return
	if _selected_idx < 0:
		return
	spawner_field_changed.emit(_selected_coord(), {field: value})


# ── Signal handlers ─────────────────────────────────────────────────────────

func _on_selected(idx: int) -> void:
	_selected_idx = idx
	if _level == null or _active_wave < 0 or _active_wave >= _level.waves.size():
		return
	var spawners: Array = _level.waves[_active_wave].get("spawners", [])
	if idx < 0 or idx >= spawners.size():
		_form_box.visible = false
		return
	_open_form(spawners[idx])


func _on_ref_selected(idx: int) -> void:
	_emit_field("ref", StringName(str(_form_ref_dd.get_item_metadata(idx))))


func _on_timer_changed(v: float) -> void:
	_emit_field("timer", int(v))


func _on_amount_changed(v: float) -> void:
	var amt: int = int(v)
	if _form_amount_tag != null:
		_form_amount_tag.visible = (amt > 1)
	_emit_field("amount", amt)


func _on_delay_changed(v: float) -> void:
	var dly: int = int(v)
	if _form_delay_tag != null:
		_form_delay_tag.visible = (dly > 1)
	_emit_field("delay", dly)
