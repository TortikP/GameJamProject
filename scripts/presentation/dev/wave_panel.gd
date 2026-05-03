extends PanelContainer

## WavePanel — top docked panel in the map editor (v2 layout).
##
## Two rows in a VBox:
##   1. HeaderRow — status label "Wave N of M [special]" + per-wave action
##      buttons (Copy from prev / Toggle special / Delete). Status updates
##      on bind_level + set_active_wave.
##   2. TimelineRow — WaveTimeline (Mode.EDIT). Anchors are clickable to
##      switch active wave; ttn LineEdits commit on blur/enter.
##   3. SkillOfferSection (040) — collapsible per-wave skill_offer config.
##      Built programmatically in _build_skill_offer_section().
##
## All wave operations route via the EditorController (which owns _level
## + history + autosave). This panel is a thin signal hub + status display.
##
## Wired by MapEditorController via _wire_wave_panel.

const UiThemeScript = preload("res://scripts/presentation/ui_theme.gd")
const SLOT_PICK_DEFAULT_COUNT: int = 3
const SLOT_PICK_MAX: int = 5
const SLOT_PICK_MIN: int = 1

signal anchor_clicked(wave_index: int)
signal anchor_context_requested(wave_index: int, screen_pos: Vector2)
signal gap_context_requested(after_idx: int, screen_pos: Vector2)
signal turns_to_next_changed(wave_index: int, new_value: int)
signal add_wave_pressed
signal copy_from_prev_pressed
signal toggle_special_pressed
signal delete_wave_pressed   # v2: dedicated button, was RMB-anchor only
# 040: emitted whenever the per-wave skill_offer config changes (enable/disable
# checkbox or any field edit). offer = Dictionary on enable, null on disable.
# Editor controller persists into _level.waves[wave_index].skill_offer.
signal skill_offer_changed(wave_index: int, offer: Variant)
# 040: dev-only — preview button opens the offer modal with current config
# without applying any pick. Editor controller handles the spawn.
signal skill_offer_preview_requested(wave_index: int)
# 040: relay from contained WaveTimeline. Editor controller listens →
# switches active wave so the section auto-refreshes onto the clicked offer.
signal skill_offer_marker_clicked(wave_index: int)

@onready var _timeline: WaveTimeline = $VBox/TimelineRow/Timeline as WaveTimeline
@onready var _status_label: Label = $VBox/HeaderRow/StatusLabel as Label
@onready var _copy_btn: Button = $VBox/HeaderRow/CopyBtn as Button
@onready var _special_btn: Button = $VBox/HeaderRow/SpecialBtn as Button
@onready var _delete_btn: Button = $VBox/HeaderRow/DeleteBtn as Button

# 040: skill-offer section UI nodes (built in _build_skill_offer_section).
var _so_section_box: VBoxContainer
var _so_enable_cb: CheckBox
var _so_pool_dd: OptionButton
var _so_count_sb: SpinBox
var _so_allow_upgrade_cb: CheckBox
var _so_allow_replace_cb: CheckBox
var _so_allow_skip_cb: CheckBox
var _so_exclude_owned_cb: CheckBox
var _so_preview_btn: Button
# Guard so programmatic refresh doesn't fire skill_offer_changed.
var _so_refreshing: bool = false

# Cached so we can refresh button state on set_active_wave without
# re-reading from the timeline.
var _level: LevelData = null

# Collapse — quick UX: hide everything below HeaderRow, keep just the top
# strip. Anchors_preset=10 with a fixed offset_bottom means the panel has
# an anchor-driven minimum height (~124px). When collapsed, drop
# offset_bottom so the PanelContainer shrinks to the header's combined min
# size; on expand restore the original offset so content drives the height.
var _collapsed: bool = false
var _orig_offset_bottom: float = 0.0
var _collapse_btn: Button


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
		# 040 — relay timeline's offer-marker click.
		if _timeline.has_signal("skill_offer_marker_clicked"):
			_timeline.skill_offer_marker_clicked.connect(
				func(idx: int) -> void: skill_offer_marker_clicked.emit(idx))
	_build_skill_offer_section()
	_build_collapse_button()
	_orig_offset_bottom = offset_bottom


# Quick-fix collapse button (left of StatusLabel). Toggles visibility of
# TimelineRow + skill-offer section so only HeaderRow stays on screen.
# Built programmatically — keeps the change off the .tscn diff, mirrors
# how _build_skill_offer_section handles its widgets.
func _build_collapse_button() -> void:
	var header_row: Node = get_node_or_null("VBox/HeaderRow")
	if header_row == null:
		return  # Test scenes — skip silently.
	_collapse_btn = Button.new()
	_collapse_btn.text = "−"
	_collapse_btn.custom_minimum_size = Vector2(32, 32)
	_collapse_btn.tooltip_text = Localization.t("ui_wave_panel_collapse", "Collapse")
	UiThemeScript.apply_button_styling(_collapse_btn)
	_collapse_btn.pressed.connect(_on_collapse_pressed)
	header_row.add_child(_collapse_btn)
	(header_row as Node).move_child(_collapse_btn, 0)


func _on_collapse_pressed() -> void:
	_collapsed = not _collapsed
	_apply_collapsed()


func _apply_collapsed() -> void:
	var timeline_row: Node = get_node_or_null("VBox/TimelineRow")
	if timeline_row is Control:
		(timeline_row as Control).visible = not _collapsed
	if _so_section_box != null:
		_so_section_box.visible = not _collapsed
	if _collapse_btn != null:
		_collapse_btn.text = "+" if _collapsed else "−"
		_collapse_btn.tooltip_text = Localization.t(
			"ui_wave_panel_expand" if _collapsed else "ui_wave_panel_collapse",
			"Expand" if _collapsed else "Collapse")
	# Anchors_preset=10 keeps anchor_bottom=0; offset_bottom is the literal
	# pixel distance from parent top. Setting it tight forces the
	# PanelContainer to size from combined_minimum_size of remaining
	# children (header only). Restoring _orig_offset_bottom hands height
	# back to content-driven sizing.
	if _collapsed:
		offset_bottom = offset_top + 1.0
	else:
		offset_bottom = _orig_offset_bottom


# 040 — programmatic build keeps the change off the .tscn diff. Section
# inserts as a new VBox row underneath the existing TimelineRow, inside
# the same VBox parent.
func _build_skill_offer_section() -> void:
	var vbox_parent: Node = get_node_or_null("VBox")
	if vbox_parent == null:
		return  # Test scenes without the standard layout — skip silently.

	_so_section_box = VBoxContainer.new()
	_so_section_box.add_theme_constant_override("separation", UiThemeScript.SP_2)
	vbox_parent.add_child(_so_section_box)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", UiThemeScript.SP_2)
	_so_section_box.add_child(header_row)

	_so_enable_cb = CheckBox.new()
	_so_enable_cb.text = Localization.t("ui_wave_panel_skill_offer", "Skill offer after this wave")
	_so_enable_cb.toggled.connect(_on_so_enable_toggled)
	header_row.add_child(_so_enable_cb)

	_so_preview_btn = Button.new()
	_so_preview_btn.text = Localization.t("ui_wave_panel_skill_offer_preview", "Preview")
	UiThemeScript.apply_button_styling(_so_preview_btn)
	_so_preview_btn.pressed.connect(_on_so_preview_pressed)
	header_row.add_child(_so_preview_btn)

	# Body — all fields, hidden when checkbox off.
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UiThemeScript.SP_1)
	_so_section_box.add_child(body)

	var pool_row := HBoxContainer.new()
	pool_row.add_theme_constant_override("separation", UiThemeScript.SP_2)
	body.add_child(pool_row)
	var pool_lbl := Label.new()
	pool_lbl.text = Localization.t("ui_wave_panel_skill_offer.pool", "Pool")
	pool_lbl.custom_minimum_size = Vector2(80, 0)
	pool_row.add_child(pool_lbl)
	_so_pool_dd = OptionButton.new()
	_so_pool_dd.custom_minimum_size = Vector2(160, 0)
	_so_pool_dd.item_selected.connect(_on_so_field_changed_int)
	pool_row.add_child(_so_pool_dd)

	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", UiThemeScript.SP_2)
	body.add_child(count_row)
	var count_lbl := Label.new()
	count_lbl.text = Localization.t("ui_wave_panel_skill_offer.count", "Count")
	count_lbl.custom_minimum_size = Vector2(80, 0)
	count_row.add_child(count_lbl)
	_so_count_sb = SpinBox.new()
	_so_count_sb.min_value = SLOT_PICK_MIN
	_so_count_sb.max_value = SLOT_PICK_MAX
	_so_count_sb.step = 1
	_so_count_sb.value = SLOT_PICK_DEFAULT_COUNT
	_so_count_sb.value_changed.connect(_on_so_field_changed_float)
	count_row.add_child(_so_count_sb)

	_so_allow_upgrade_cb = _make_toggle(body, "ui_wave_panel_skill_offer.allow_upgrade", "Allow upgrade")
	_so_allow_replace_cb = _make_toggle(body, "ui_wave_panel_skill_offer.allow_replace", "Allow replace")
	_so_allow_skip_cb    = _make_toggle(body, "ui_wave_panel_skill_offer.allow_skip", "Allow skip")
	_so_exclude_owned_cb = _make_toggle(body, "ui_wave_panel_skill_offer.exclude_owned", "Exclude owned")

	_populate_pool_dropdown()
	_set_section_body_visible(false)


func _make_toggle(parent: Node, key: String, fallback: String) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = Localization.t(key, fallback)
	cb.toggled.connect(_on_so_field_changed_bool)
	parent.add_child(cb)
	return cb


func _populate_pool_dropdown() -> void:
	if _so_pool_dd == null:
		return
	_so_pool_dd.clear()
	# SkillOfferController is an autoload — read its pool list. If absent
	# (e.g. running map_editor.tscn before autoload registers — shouldn't
	# happen post-T011), leave dropdown empty.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var ctrl: Node = tree.root.get_node_or_null("SkillOfferController")
	if ctrl == null or not ctrl.has_method("get_pool_ids"):
		return
	var ids: Array = ctrl.get_pool_ids()
	for i in ids.size():
		var id: StringName = StringName(str(ids[i]))
		var label: String = String(id)
		if ctrl.has_method("get_pool_label"):
			label = ctrl.get_pool_label(id)
		_so_pool_dd.add_item(label, i)
		_so_pool_dd.set_item_metadata(i, id)


func _set_section_body_visible(visible_body: bool) -> void:
	# Body is the second VBox child (siblings of header_row inside _so_section_box).
	if _so_section_box == null:
		return
	# Index 0 = header_row, 1 = body.
	for i in _so_section_box.get_child_count():
		if i == 0:
			continue
		var c: Node = _so_section_box.get_child(i)
		if c is Control:
			(c as Control).visible = visible_body
	if _so_preview_btn != null:
		_so_preview_btn.disabled = not visible_body


# ── Signal forwarding ──────────────────────────────────────────────────────

func _current_offer_dict() -> Dictionary:
	# Collect current UI state into a Dictionary suitable for level JSON.
	var pool_id: StringName = &""
	if _so_pool_dd != null and _so_pool_dd.selected >= 0:
		var meta: Variant = _so_pool_dd.get_item_metadata(_so_pool_dd.selected)
		pool_id = StringName(str(meta))
	return {
		"pool": String(pool_id),
		"count": int(_so_count_sb.value) if _so_count_sb != null else SLOT_PICK_DEFAULT_COUNT,
		"allow_upgrade": _so_allow_upgrade_cb.button_pressed if _so_allow_upgrade_cb != null else true,
		"allow_replace": _so_allow_replace_cb.button_pressed if _so_allow_replace_cb != null else true,
		"allow_skip":    _so_allow_skip_cb.button_pressed    if _so_allow_skip_cb    != null else false,
		"exclude_owned": _so_exclude_owned_cb.button_pressed if _so_exclude_owned_cb != null else false,
	}


func _emit_changed_for_active() -> void:
	if _so_refreshing or _level == null:
		return
	var idx: int = _level.get_active_wave_index()
	if not _so_enable_cb.button_pressed:
		skill_offer_changed.emit(idx, null)
	else:
		skill_offer_changed.emit(idx, _current_offer_dict())


func _on_so_enable_toggled(pressed: bool) -> void:
	_set_section_body_visible(pressed)
	_emit_changed_for_active()


func _on_so_field_changed_bool(_v: bool) -> void:
	_emit_changed_for_active()


func _on_so_field_changed_float(_v: float) -> void:
	_emit_changed_for_active()


func _on_so_field_changed_int(_v: int) -> void:
	_emit_changed_for_active()


func _on_so_preview_pressed() -> void:
	if _level == null:
		return
	# 040 / AC-S22: preview lives in the panel rather than the controller
	# so editor-controller delta stays small. Dev-only — no _apply_pick,
	# no event-bus emit. The modal's player_picked just frees it.
	var idx: int = _level.get_active_wave_index()
	var so: Variant = _level.waves[idx].get("skill_offer", null)
	if so == null or not (so is Dictionary):
		return
	var ctrl: Node = get_tree().root.get_node_or_null("SkillOfferController")
	if ctrl == null or not ctrl.has_method("get_pool_ids"):
		return
	var pool_id: StringName = StringName(str((so as Dictionary).get("pool", "")))
	if not ctrl.has_method("has_pool") or not ctrl.has_pool(pool_id):
		return
	# Build cards via SkillOfferController's internal builder. The fact
	# that we're reaching into a private method is acceptable for a
	# dev-only preview path; if 040 grows tests we'd promote it.
	if not ctrl.has_method("_build_cards"):
		return
	var pool_dict: Dictionary = ctrl._pools.get(pool_id, {}) if "_pools" in ctrl else {}
	var cards: Array = ctrl._build_cards(pool_dict, so as Dictionary)
	if cards.is_empty():
		return
	const ModalScene: PackedScene = preload("res://scenes/ui/skill_offer_modal.tscn")
	var modal: Node = ModalScene.instantiate()
	modal.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(modal)
	if modal.has_method("open"):
		modal.open(cards, so as Dictionary)
	if modal.has_signal("player_picked"):
		modal.player_picked.connect(_on_preview_modal_picked.bind(modal), CONNECT_ONE_SHOT)
	# Still emit the legacy preview-requested signal so the controller
	# could intercept (e.g. to log) — but no behaviour depends on it.
	skill_offer_preview_requested.emit(idx)


func _on_preview_modal_picked(_result: Dictionary, modal: Node) -> void:
	if modal != null and is_instance_valid(modal):
		modal.queue_free()


# ── Refresh from level → UI ────────────────────────────────────────────────

func _refresh_skill_offer_section() -> void:
	if _so_enable_cb == null or _level == null:
		return
	_so_refreshing = true
	var idx: int = _level.get_active_wave_index()
	var so: Variant = null
	if idx >= 0 and idx < _level.waves.size():
		so = _level.waves[idx].get("skill_offer", null)
	var enabled: bool = so != null and so is Dictionary
	_so_enable_cb.set_pressed_no_signal(enabled)
	_set_section_body_visible(enabled)
	if enabled:
		var d: Dictionary = so
		# Pool dropdown — find item with metadata matching saved pool id.
		var saved_pool: StringName = StringName(str(d.get("pool", "")))
		_select_pool_in_dropdown(saved_pool)
		_so_count_sb.set_value_no_signal(int(d.get("count", SLOT_PICK_DEFAULT_COUNT)))
		_so_allow_upgrade_cb.set_pressed_no_signal(bool(d.get("allow_upgrade", true)))
		_so_allow_replace_cb.set_pressed_no_signal(bool(d.get("allow_replace", true)))
		_so_allow_skip_cb.set_pressed_no_signal(bool(d.get("allow_skip", false)))
		_so_exclude_owned_cb.set_pressed_no_signal(bool(d.get("exclude_owned", false)))
	_so_refreshing = false


func _select_pool_in_dropdown(pool_id: StringName) -> void:
	if _so_pool_dd == null:
		return
	for i in _so_pool_dd.item_count:
		var meta: Variant = _so_pool_dd.get_item_metadata(i)
		if StringName(str(meta)) == pool_id:
			_so_pool_dd.select(i)
			return
	# Not found — fall back to first item (or none).
	if _so_pool_dd.item_count > 0:
		_so_pool_dd.select(0)


## Bind a level to the contained timeline + refresh button enablement.
## Called by editor on every dirty event (cheap — timeline rebuilds child
## controls in O(num_waves), deferred internally).
func bind_level(level: LevelData) -> void:
	_level = level
	if _timeline != null:
		_timeline.bind_level(level)
	_refresh_header()
	_refresh_skill_offer_section()


## Set which wave is highlighted as "active" in the timeline. Called when
## the editor controller's _active_wave_index changes (anchor click or
## programmatic switch).
func set_active_wave(idx: int) -> void:
	if _timeline != null:
		_timeline.set_edit_active_wave(idx)
	_refresh_header()
	_refresh_skill_offer_section()


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
		_status_label.text = Localization.tf("ui_wave_panel_status", [active + 1, total, tag], "Wave %d of %d%s")

	# Copy from prev — disabled on wave 0 (nothing to copy from).
	if _copy_btn != null:
		_copy_btn.disabled = (active <= 0)

	# Special — text reflects current state.
	if _special_btn != null:
		_special_btn.text = Localization.t("ui_wave_panel_special_on", "★ Special (on)") if is_special else Localization.t("ui_wave_panel_make_special", "Make Special")

	# Delete — disabled on wave 0 (Wave 0 must always exist; player spawner
	# lives there). Single-wave levels also can't delete (would leave none).
	if _delete_btn != null:
		_delete_btn.disabled = (active <= 0 or total <= 1)
