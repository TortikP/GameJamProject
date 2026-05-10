class_name WaveSettingsSkillOfferSection
extends VBoxContainer

## Skill-offer section of WaveSettingsPanel. Ported verbatim from the
## monolithic panel (Spec 061 + tabbed rework). Designer toggles whether
## the active wave triggers a skill-offer screen on completion, picks a
## pool, count and policy flags. "Preview" requests host to launch SO UI
## with current settings.
##
## Reads pool list from /root/SkillOfferController autoload (get_pool_ids
## + get_pool_label). Empty if autoload missing — designer's wave just
## stores whatever pool string was picked, runtime resolves at use time.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")

const SLOT_PICK_MIN: int = 1
const SLOT_PICK_MAX: int = 5
const SLOT_PICK_DEFAULT_COUNT: int = 3

signal skill_offer_changed(idx: int, offer: Variant)
signal skill_offer_preview_requested(idx: int)

var _level: LevelData = null
var _active_wave: int = 0
var _refreshing: bool = false

var _enable_cb: CheckBox
var _preview_btn: Button
var _body: VBoxContainer
var _pool_dd: OptionButton
var _count_sb: SpinBox
var _allow_upgrade_cb: CheckBox
var _allow_replace_cb: CheckBox
var _allow_skip_cb: CheckBox
var _exclude_owned_cb: CheckBox


func _ready() -> void:
	add_theme_constant_override("separation", 4)
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
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 4)
	add_child(header_row)

	_enable_cb = CheckBox.new()
	_enable_cb.text = Localization.t("ui_wave_panel_skill_offer", "Skill offer after this wave")
	_enable_cb.toggled.connect(_on_enable_toggled)
	header_row.add_child(_enable_cb)

	_preview_btn = Button.new()
	_preview_btn.text = Localization.t("ui_wave_panel_skill_offer_preview", "Preview")
	UiTheme.apply_button_styling(_preview_btn)
	_preview_btn.pressed.connect(_on_preview_pressed)
	header_row.add_child(_preview_btn)

	_body = VBoxContainer.new()
	add_child(_body)

	var pool_row := HBoxContainer.new()
	_body.add_child(pool_row)
	var pool_lbl := _make_label("ui_wave_panel_skill_offer.pool", "Pool")
	pool_lbl.custom_minimum_size = Vector2(80, 0)
	pool_row.add_child(pool_lbl)
	_pool_dd = OptionButton.new()
	_pool_dd.custom_minimum_size = Vector2(160, 0)
	_pool_dd.item_selected.connect(_on_field_changed_int)
	pool_row.add_child(_pool_dd)

	var count_row := HBoxContainer.new()
	_body.add_child(count_row)
	var count_lbl := _make_label("ui_wave_panel_skill_offer.count", "Count")
	count_lbl.custom_minimum_size = Vector2(80, 0)
	count_row.add_child(count_lbl)
	_count_sb = SpinBox.new()
	_count_sb.min_value = SLOT_PICK_MIN
	_count_sb.max_value = SLOT_PICK_MAX
	_count_sb.step = 1
	_count_sb.value = SLOT_PICK_DEFAULT_COUNT
	_count_sb.value_changed.connect(_on_field_changed_float)
	count_row.add_child(_count_sb)

	_allow_upgrade_cb = _make_toggle(_body,
		"ui_wave_panel_skill_offer.allow_upgrade", "Allow upgrade")
	_allow_replace_cb = _make_toggle(_body,
		"ui_wave_panel_skill_offer.allow_replace", "Allow replace")
	_allow_skip_cb = _make_toggle(_body,
		"ui_wave_panel_skill_offer.allow_skip", "Allow skip")
	_exclude_owned_cb = _make_toggle(_body,
		"ui_wave_panel_skill_offer.exclude_owned", "Exclude owned")

	_populate_pool_dropdown()
	_set_body_visible(false)


func _make_toggle(parent: Node, key: String, fallback: String) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = Localization.t(key, fallback)
	cb.toggled.connect(_on_field_changed_bool)
	parent.add_child(cb)
	return cb


func _populate_pool_dropdown() -> void:
	if _pool_dd == null:
		return
	_pool_dd.clear()
	var ctrl: Node = get_node_or_null("/root/SkillOfferController")
	if ctrl == null or not ctrl.has_method("get_pool_ids"):
		return
	var ids: Array = ctrl.get_pool_ids()
	for i in ids.size():
		var id: StringName = StringName(str(ids[i]))
		var label: String = String(id)
		if ctrl.has_method("get_pool_label"):
			label = ctrl.get_pool_label(id)
		_pool_dd.add_item(label, i)
		_pool_dd.set_item_metadata(i, id)


func _set_body_visible(v: bool) -> void:
	if _body != null:
		_body.visible = v
	if _preview_btn != null:
		_preview_btn.disabled = not v


# ── Refresh ─────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if _enable_cb == null or _level == null:
		return
	_refreshing = true
	var so: Variant = null
	if _active_wave >= 0 and _active_wave < _level.waves.size():
		so = _level.waves[_active_wave].get("skill_offer", null)
	var enabled: bool = so != null and so is Dictionary
	_enable_cb.set_pressed_no_signal(enabled)
	_set_body_visible(enabled)
	if enabled:
		var d: Dictionary = so
		_select_pool_in_dropdown(StringName(str(d.get("pool", ""))))
		_count_sb.set_value_no_signal(int(d.get("count", SLOT_PICK_DEFAULT_COUNT)))
		_allow_upgrade_cb.set_pressed_no_signal(bool(d.get("allow_upgrade", true)))
		_allow_replace_cb.set_pressed_no_signal(bool(d.get("allow_replace", true)))
		_allow_skip_cb.set_pressed_no_signal(bool(d.get("allow_skip", false)))
		_exclude_owned_cb.set_pressed_no_signal(bool(d.get("exclude_owned", false)))
	_refreshing = false


func _select_pool_in_dropdown(pool_id: StringName) -> void:
	if _pool_dd == null:
		return
	for i in _pool_dd.item_count:
		var meta: Variant = _pool_dd.get_item_metadata(i)
		if StringName(str(meta)) == pool_id:
			_pool_dd.select(i)
			return
	if _pool_dd.item_count > 0:
		_pool_dd.select(0)


# ── Helpers ─────────────────────────────────────────────────────────────────

func _make_label(loc_key: String, fallback: String) -> Label:
	var lbl := Label.new()
	lbl.text = Localization.t(loc_key, fallback)
	UiTheme.apply_label_kind(lbl, "dim")
	return lbl


func _current_offer_dict() -> Dictionary:
	var pool_id: StringName = &""
	if _pool_dd != null and _pool_dd.selected >= 0:
		pool_id = StringName(str(_pool_dd.get_item_metadata(_pool_dd.selected)))
	return {
		"pool": String(pool_id),
		"count": int(_count_sb.value) if _count_sb != null else SLOT_PICK_DEFAULT_COUNT,
		"allow_upgrade": _allow_upgrade_cb.button_pressed if _allow_upgrade_cb != null else true,
		"allow_replace": _allow_replace_cb.button_pressed if _allow_replace_cb != null else true,
		"allow_skip":    _allow_skip_cb.button_pressed    if _allow_skip_cb    != null else false,
		"exclude_owned": _exclude_owned_cb.button_pressed if _exclude_owned_cb != null else false,
	}


func _emit_changed() -> void:
	if _refreshing or _level == null:
		return
	if not _enable_cb.button_pressed:
		skill_offer_changed.emit(_active_wave, null)
	else:
		skill_offer_changed.emit(_active_wave, _current_offer_dict())


# ── Signal handlers ─────────────────────────────────────────────────────────

func _on_enable_toggled(pressed: bool) -> void:
	_set_body_visible(pressed)
	_emit_changed()


func _on_field_changed_bool(_v: bool) -> void:
	_emit_changed()


func _on_field_changed_float(_v: float) -> void:
	_emit_changed()


func _on_field_changed_int(_v: int) -> void:
	_emit_changed()


func _on_preview_pressed() -> void:
	skill_offer_preview_requested.emit(_active_wave)
