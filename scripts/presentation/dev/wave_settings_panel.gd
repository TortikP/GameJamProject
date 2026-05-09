class_name WaveSettingsPanel
extends BasePanel

## WaveSettingsPanel — Spec 061. Right-side panel in the level editor.
## Owns wave navigation (ItemList + add/copy/delete) and per-wave/level
## fields that aren't layer-painted (is_special, advance_mode, spawner
## metadata, skill_offer config, dialogue triggers, music_config).
##
## ## Sections (top → bottom in body)
##
##   1. Wave switcher — ItemList + [+ Wave] [Copy from prev] [Delete].
##   2. Level — name (read-only mirror), level-scoped dialogue triggers (CRUD).
##   3. Wave — is_special, turns_to_next, respawn_player, advance_mode,
##      music_config (raw JSON).
##   4. Spawners — list of active wave's spawners + edit form (kind read-only,
##      ref/timer/amount/delay editable). amount/delay tagged (schema-only).
##   5. Skill offer — ported from deleted scripts/presentation/dev/wave_panel.gd.
##   6. Dialogue triggers (wave-scoped) — read-only mirror of level-section
##      triggers filtered by conditions.wave_index == active_wave.
##
## ## Wiring
##
## Signals are flat: each user action emits one signal, EditorController
## receives it and mutates _level. Refresh is pull-based: editor calls
## bind_level() / set_active_wave() to repaint UI from canonical state.
##
## ## Refresh guard
##
## All signal emits are gated on `_refreshing == false`. _refreshing is set
## while controls are programmatically populated in _refresh_*; otherwise
## set_value_no_signal would deal with this, but a generic guard avoids the
## per-control verbosity.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")
const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

## Curated event vocabulary for dialogue triggers. Mirrors old
## dialogue_trigger_panel.gd CURATED_EVENTS — kept verbatim per Spec 061
## §3.D (no expansion in this spec).
const CURATED_EVENTS: Array[String] = [
	"level_started",
	"wave_about_to_start",
	"wave_started",
	"wave_cleared",
	"world_turn_ended",
	"skill_offer_about_to_open",
	"skill_offer_closed",
	"level_completed",
]

const SLOT_PICK_MIN: int = 1
const SLOT_PICK_MAX: int = 5
const SLOT_PICK_DEFAULT_COUNT: int = 3

# ── Signals (flat — see header) ─────────────────────────────────────────────

# Wave navigation
signal wave_switch_requested(idx: int)
signal wave_add_requested(after_idx: int)
signal wave_copy_requested(after_idx: int)
signal wave_delete_requested(idx: int)

# Wave field updates (generic setter — controller validates)
signal wave_field_changed(idx: int, field: String, value: Variant)

# Spawner field updates
signal spawner_field_changed(coord: Vector2i, fields: Dictionary)

# Dialogue triggers CRUD
signal trigger_created(trigger_dict: Dictionary)
signal trigger_updated(old_id: StringName, trigger_dict: Dictionary)
signal trigger_deleted(trigger_id: StringName)

# Skill offer (relay of old wave_panel signals)
signal skill_offer_changed(idx: int, offer: Variant)
signal skill_offer_preview_requested(idx: int)


# ── State ───────────────────────────────────────────────────────────────────

var _level: LevelData = null
var _active_wave: int = 0

# Spawner currently selected in the spawner section. -1 = none. Stored as
# the index into _level.waves[active].spawners (which mutates whenever the
# active wave changes — selection clears on wave switch).
var _selected_spawner_idx: int = -1

# Dialogue trigger CRUD state (level-scoped section).
var _selected_trigger_idx: int = -1
var _editing_trigger: bool = false
var _editing_trigger_new: bool = false

# Refresh guard — programmatic UI population suppresses change emits.
var _refreshing: bool = false

# Skill offer refresh guard — narrower, mirrors old wave_panel pattern.
var _so_refreshing: bool = false


# ── UI references ───────────────────────────────────────────────────────────

# Switcher
var _switcher_list: ItemList
var _switcher_add_btn: Button
var _switcher_copy_btn: Button
var _switcher_delete_btn: Button

# Level section
var _level_name_label: Label
var _level_triggers_count: Label
var _level_triggers_list: ItemList
var _trigger_btn_edit: Button
var _trigger_btn_dupe: Button
var _trigger_btn_delete: Button
var _trigger_form_box: VBoxContainer
var _trigger_form_id: LineEdit
var _trigger_form_event_option: OptionButton
var _trigger_form_event_custom: LineEdit
var _trigger_form_dialogue_filter: LineEdit
var _trigger_form_dialogue_option: OptionButton
var _trigger_form_playmode_request: CheckBox
var _trigger_form_playmode_play: CheckBox
var _trigger_form_conditions: VBoxContainer
var _trigger_form_error: Label
var _trigger_cond_widgets: Dictionary = {}  # key → {check: CheckBox, editor: Control}

# Wave section
var _wave_is_special_edit: LineEdit
var _wave_ttn_spin: SpinBox
var _wave_respawn_cb: CheckBox
var _wave_respawn_row: HBoxContainer  # hidden on wave 0
var _wave_advance_mode_dd: OptionButton
var _wave_music_config_edit: LineEdit  # raw JSON (one-line)

# Spawner section
var _spawner_list: ItemList
var _spawner_form_box: VBoxContainer
var _spawner_form_kind_label: Label
var _spawner_form_ref_dd: OptionButton
var _spawner_form_timer_spin: SpinBox
var _spawner_form_amount_spin: SpinBox
var _spawner_form_amount_tag: Label
var _spawner_form_delay_spin: SpinBox
var _spawner_form_delay_tag: Label

# Skill offer section (ported)
var _so_section_box: VBoxContainer
var _so_enable_cb: CheckBox
var _so_pool_dd: OptionButton
var _so_count_sb: SpinBox
var _so_allow_upgrade_cb: CheckBox
var _so_allow_replace_cb: CheckBox
var _so_allow_skip_cb: CheckBox
var _so_exclude_owned_cb: CheckBox
var _so_preview_btn: Button

# Wave-section trigger mirror
var _wave_triggers_list: ItemList


# ── Lifecycle ───────────────────────────────────────────────────────────────

func _ready() -> void:
	# In Godot 4, parent _ready() is NOT auto-called when subclass overrides.
	# super._ready() invokes BasePanel: resolve nodes, apply theme, install
	# drag/resize/collapse/lock/persistence handlers. Then build our body.
	super._ready()
	_build_body()


# ── Public API ──────────────────────────────────────────────────────────────

## Bind a LevelData. Called by EditorController on level load and after every
## CRUD operation so the panel reflects canonical state.
func bind_level(level: LevelData) -> void:
	_level = level
	_active_wave = level.get_active_wave_index() if level != null else 0
	_selected_spawner_idx = -1
	_selected_trigger_idx = -1
	_close_trigger_form()
	_refresh_all()


## Switch which wave's data the panel displays. Called by EditorController
## when active wave changes (anchor click or programmatic).
func set_active_wave(idx: int) -> void:
	_active_wave = idx
	_selected_spawner_idx = -1
	_refresh_active_wave_fields()
	_refresh_spawner_list()
	_refresh_skill_offer_section()
	_refresh_wave_triggers_mirror()
	_refresh_switcher_list()  # selection highlight changes


## Select a trigger row in the level-scoped list and open its edit form.
## Called by EditorController on wave-mirror click (Φ-8) and external
## select-by-id (e.g. timeline marker click).
func select_trigger(id: StringName) -> void:
	if _level == null:
		return
	for i in _level.dialogue_triggers.size():
		if StringName(str(_level.dialogue_triggers[i].get("id", ""))) == id:
			_selected_trigger_idx = i
			if _level_triggers_list != null:
				_level_triggers_list.select(i)
			_update_trigger_button_states()
			_open_trigger_form(_level.dialogue_triggers[i])
			return


# ── Build ───────────────────────────────────────────────────────────────────

func _build_body() -> void:
	var body := get_body_container()
	if body == null:
		push_error("[WaveSettingsPanel] body container not available")
		return
	# A scroll wrapper so the panel can still be small without clipping the
	# six sections. Inner VBox grows naturally.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "ContentVBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	_build_wave_switcher(vbox)
	_make_section_header(vbox, "ui_wavesettings_level_header", "Level")
	_build_level_section(vbox)
	_make_section_header(vbox, "ui_wavesettings_wave_header", "Wave")
	_build_wave_section(vbox)
	_make_section_header(vbox, "ui_wavesettings_spawners_header", "Spawners")
	_build_spawner_section(vbox)
	_make_section_header(vbox, "ui_wavesettings_skill_offer_header", "Skill Offer")
	_build_skill_offer_section(vbox)
	_make_section_header(vbox, "ui_wavesettings_wave_triggers_header", "Dialogue Triggers (this wave)")
	_build_wave_triggers_mirror(vbox)


# ─── Switcher ───────────────────────────────────────────────────────────────

func _build_wave_switcher(parent: Control) -> void:
	var wrap := VBoxContainer.new()
	parent.add_child(wrap)

	_switcher_list = ItemList.new()
	_switcher_list.custom_minimum_size = Vector2(280, 110)
	_switcher_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_switcher_list.item_selected.connect(_on_switcher_item_selected)
	wrap.add_child(_switcher_list)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	wrap.add_child(btn_row)

	_switcher_add_btn = _make_btn(
		Localization.t("ui_wavesettings_switcher_add", "+ Wave"),
		_on_switcher_add_pressed)
	btn_row.add_child(_switcher_add_btn)
	_switcher_copy_btn = _make_btn(
		Localization.t("ui_wavesettings_switcher_copy", "Copy from prev"),
		_on_switcher_copy_pressed)
	btn_row.add_child(_switcher_copy_btn)
	_switcher_delete_btn = _make_btn(
		Localization.t("ui_wavesettings_switcher_delete", "Delete"),
		_on_switcher_delete_pressed)
	btn_row.add_child(_switcher_delete_btn)


# ─── Level section (CRUD for level-scoped dialogue triggers) ────────────────

func _build_level_section(parent: Control) -> void:
	# Name mirror — read-only echo of LevelMetaPanel.
	var name_row := HBoxContainer.new()
	parent.add_child(name_row)
	var name_lbl := _make_label("ui_wavesettings_level_name", "name:", "dim")
	name_lbl.custom_minimum_size = Vector2(80, 0)
	name_row.add_child(name_lbl)
	_level_name_label = Label.new()
	_level_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_level_name_label)

	# Trigger count + list.
	var count_row := HBoxContainer.new()
	parent.add_child(count_row)
	var count_lbl := _make_label("ui_wavesettings_dialogue_triggers_header", "Triggers", "dim")
	count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_row.add_child(count_lbl)
	_level_triggers_count = Label.new()
	UiTheme.apply_label_kind(_level_triggers_count, "dim")
	count_row.add_child(_level_triggers_count)

	_level_triggers_list = ItemList.new()
	_level_triggers_list.custom_minimum_size = Vector2(260, 110)
	_level_triggers_list.item_selected.connect(_on_trigger_list_selected)
	parent.add_child(_level_triggers_list)

	# CRUD buttons.
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	parent.add_child(btn_row)
	var btn_add := _make_btn(Localization.t("ui_trigger_btn_add", "+ Add"), _on_trigger_add)
	btn_row.add_child(btn_add)
	_trigger_btn_edit = _make_btn(Localization.t("ui_trigger_btn_edit", "Edit"), _on_trigger_edit)
	btn_row.add_child(_trigger_btn_edit)
	_trigger_btn_dupe = _make_btn(Localization.t("ui_trigger_btn_dupe", "Dupe"), _on_trigger_duplicate)
	btn_row.add_child(_trigger_btn_dupe)
	_trigger_btn_delete = _make_btn(Localization.t("ui_trigger_btn_delete", "Delete"), _on_trigger_delete)
	btn_row.add_child(_trigger_btn_delete)

	# Edit form (hidden by default).
	_trigger_form_box = VBoxContainer.new()
	_trigger_form_box.visible = false
	parent.add_child(_trigger_form_box)
	_build_trigger_form(_trigger_form_box)

	_trigger_form_error = Label.new()
	UiTheme.apply_label_kind(_trigger_form_error, "error")
	_trigger_form_error.autowrap_mode = TextServer.AUTOWRAP_WORD
	_trigger_form_error.visible = false
	parent.add_child(_trigger_form_error)


func _build_trigger_form(parent: Control) -> void:
	# id row — with help hint per AC15 (id vs dialogue_id distinction).
	var id_row := HBoxContainer.new()
	parent.add_child(id_row)
	var id_lbl := _make_label("ui_trigger_id_help", "id:", "dim")
	id_lbl.custom_minimum_size = Vector2(70, 0)
	id_lbl.tooltip_text = Localization.t("ui_trigger_id_help_tooltip",
		"Unique trigger ID — used in logs and once-tracking. Not the dialogue.")
	id_row.add_child(id_lbl)
	_trigger_form_id = LineEdit.new()
	_trigger_form_id.placeholder_text = "unique_id"
	_trigger_form_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_row.add_child(_trigger_form_id)

	# event row — curated dropdown + custom override.
	var ev_row := HBoxContainer.new()
	parent.add_child(ev_row)
	var ev_lbl := _make_label("ui_dialogue_trigger_event", "event:", "dim")
	ev_lbl.custom_minimum_size = Vector2(70, 0)
	ev_row.add_child(ev_lbl)
	_trigger_form_event_option = OptionButton.new()
	_trigger_form_event_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for e in CURATED_EVENTS:
		_trigger_form_event_option.add_item(e)
	_trigger_form_event_option.add_item(Localization.t("ui_trigger_event_custom", "Custom..."))
	_trigger_form_event_option.item_selected.connect(_on_trigger_event_option_selected)
	ev_row.add_child(_trigger_form_event_option)
	_trigger_form_event_custom = LineEdit.new()
	_trigger_form_event_custom.placeholder_text = "custom_signal_name"
	_trigger_form_event_custom.visible = false
	_trigger_form_event_custom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ev_row.add_child(_trigger_form_event_custom)

	# dialogue_id row — filterable picker. Help hint distinguishes from id.
	var dlg_row := HBoxContainer.new()
	parent.add_child(dlg_row)
	var dlg_lbl := _make_label("ui_trigger_dialogue_help", "dialogue:", "dim")
	dlg_lbl.custom_minimum_size = Vector2(70, 0)
	dlg_lbl.tooltip_text = Localization.t("ui_trigger_dialogue_help_tooltip",
		"Dialogue ID — what plays when the trigger fires. Distinct from trigger id above.")
	dlg_row.add_child(dlg_lbl)
	_trigger_form_dialogue_filter = LineEdit.new()
	_trigger_form_dialogue_filter.placeholder_text = Localization.t("ui_common_filter_placeholder", "filter...")
	_trigger_form_dialogue_filter.custom_minimum_size = Vector2(60, 0)
	_trigger_form_dialogue_filter.text_changed.connect(_on_trigger_dialogue_filter_changed)
	dlg_row.add_child(_trigger_form_dialogue_filter)
	_trigger_form_dialogue_option = OptionButton.new()
	_trigger_form_dialogue_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dlg_row.add_child(_trigger_form_dialogue_option)
	_populate_dialogue_picker("")

	# play_mode row — request | play.
	var pm_row := HBoxContainer.new()
	parent.add_child(pm_row)
	var pm_lbl := _make_label("ui_dialogue_trigger_mode", "mode:", "dim")
	pm_lbl.custom_minimum_size = Vector2(70, 0)
	pm_row.add_child(pm_lbl)
	_trigger_form_playmode_request = CheckBox.new()
	_trigger_form_playmode_request.text = Localization.t("ui_trigger_play_mode_request", "request")
	_trigger_form_playmode_request.button_group = ButtonGroup.new()
	_trigger_form_playmode_request.set_pressed_no_signal(true)
	pm_row.add_child(_trigger_form_playmode_request)
	_trigger_form_playmode_play = CheckBox.new()
	_trigger_form_playmode_play.text = Localization.t("ui_trigger_play_mode_play", "play")
	_trigger_form_playmode_play.button_group = _trigger_form_playmode_request.button_group
	pm_row.add_child(_trigger_form_playmode_play)

	# Conditions section.
	var cond_lbl := _make_label("ui_dialogue_trigger_conditions", "Conditions (opt):", "dim")
	parent.add_child(cond_lbl)
	_trigger_form_conditions = VBoxContainer.new()
	parent.add_child(_trigger_form_conditions)
	_build_trigger_condition_widgets()

	# Form buttons.
	var form_btns := HBoxContainer.new()
	parent.add_child(form_btns)
	var save_btn := _make_btn(Localization.t("ui_trigger_btn_save", "Save"), _on_trigger_form_save)
	form_btns.add_child(save_btn)
	var cancel_btn := _make_btn(Localization.t("ui_trigger_btn_cancel", "Cancel"), _on_trigger_form_cancel)
	form_btns.add_child(cancel_btn)


func _build_trigger_condition_widgets() -> void:
	var specs: Array[Dictionary] = [
		{"key": "wave_index",         "label_key": "ui_trigger_condition_wave_index",         "fallback": "wave_index (int)",     "type": "int"},
		{"key": "absolute_turn",      "label_key": "ui_trigger_condition_absolute_turn",      "fallback": "absolute_turn (int)",  "type": "int"},
		{"key": "cleared_in_turns_lt","label_key": "ui_trigger_condition_cleared_in_turns_lt","fallback": "cleared_in_turns_lt",  "type": "int"},
		{"key": "chance",             "label_key": "ui_trigger_condition_chance",             "fallback": "chance 0..1",          "type": "float"},
		{"key": "mood",               "label_key": "ui_trigger_condition_mood",               "fallback": "mood (string)",        "type": "string"},
		{"key": "once_per_run",       "label_key": "ui_trigger_condition_once_per_run",       "fallback": "once_per_run",         "type": "bool"},
	]
	for spec in specs:
		var row := HBoxContainer.new()
		_trigger_form_conditions.add_child(row)
		var chk := CheckBox.new()
		chk.text = Localization.t(String(spec["label_key"]), String(spec["fallback"]))
		# Local capture: bind key into a typed Callable so changes flip the
		# editor visibility for that specific row.
		var key_capture: String = String(spec["key"])
		chk.toggled.connect(func(on: bool) -> void: _on_trigger_condition_toggled(key_capture, on))
		row.add_child(chk)
		var ed: Control
		if spec["type"] == "bool":
			ed = CheckBox.new()
			(ed as CheckBox).text = ""
		else:
			ed = LineEdit.new()
			(ed as LineEdit).placeholder_text = String(spec["key"])
			(ed as LineEdit).custom_minimum_size = Vector2(60, 0)
		ed.visible = false
		row.add_child(ed)
		_trigger_cond_widgets[key_capture] = {"check": chk, "editor": ed, "type": spec["type"]}


func _populate_dialogue_picker(filter: String) -> void:
	if _trigger_form_dialogue_option == null:
		return
	_trigger_form_dialogue_option.clear()
	var ids: Array = []
	var db: Node = get_node_or_null("/root/DialogueDB")
	if db != null and db.has_method("get_all_ids"):
		ids = db.get_all_ids()
	var lf: String = filter.strip_edges().to_lower()
	for id_str in ids:
		var s: String = str(id_str)
		if lf == "" or lf in s.to_lower():
			_trigger_form_dialogue_option.add_item(s)


# ─── Wave section ───────────────────────────────────────────────────────────

func _build_wave_section(parent: Control) -> void:
	# is_special — free-form string per design D5. Hint placeholder shown.
	var spec_row := HBoxContainer.new()
	parent.add_child(spec_row)
	var spec_lbl := _make_label("ui_wavesettings_is_special", "is_special:", "dim")
	spec_lbl.custom_minimum_size = Vector2(120, 0)
	spec_lbl.tooltip_text = Localization.t("ui_wavesettings_is_special_hint",
		"Free-form string. Convention: \"normal\" | \"boss\" | \"miniboss_*\".")
	spec_row.add_child(spec_lbl)
	_wave_is_special_edit = LineEdit.new()
	_wave_is_special_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_is_special_edit.placeholder_text = "normal | boss | miniboss_*"
	_wave_is_special_edit.text_submitted.connect(_on_wave_is_special_submitted)
	_wave_is_special_edit.focus_exited.connect(_on_wave_is_special_focus_exited)
	spec_row.add_child(_wave_is_special_edit)

	# turns_to_next.
	var ttn_row := HBoxContainer.new()
	parent.add_child(ttn_row)
	var ttn_lbl := _make_label("ui_wavesettings_ttn", "turns_to_next:", "dim")
	ttn_lbl.custom_minimum_size = Vector2(120, 0)
	ttn_row.add_child(ttn_lbl)
	_wave_ttn_spin = SpinBox.new()
	_wave_ttn_spin.min_value = 0
	_wave_ttn_spin.max_value = 999
	_wave_ttn_spin.step = 1
	_wave_ttn_spin.value_changed.connect(_on_wave_ttn_changed)
	ttn_row.add_child(_wave_ttn_spin)

	# respawn_player — hidden on wave 0 (implicit true there).
	_wave_respawn_row = HBoxContainer.new()
	parent.add_child(_wave_respawn_row)
	var rp_lbl := _make_label("ui_wavesettings_respawn_player", "respawn_player:", "dim")
	rp_lbl.custom_minimum_size = Vector2(120, 0)
	_wave_respawn_row.add_child(rp_lbl)
	_wave_respawn_cb = CheckBox.new()
	_wave_respawn_cb.toggled.connect(_on_wave_respawn_toggled)
	_wave_respawn_row.add_child(_wave_respawn_cb)

	# advance_mode.
	var am_row := HBoxContainer.new()
	parent.add_child(am_row)
	var am_lbl := _make_label("ui_wavesettings_advance_mode", "advance_mode:", "dim")
	am_lbl.custom_minimum_size = Vector2(120, 0)
	am_row.add_child(am_lbl)
	_wave_advance_mode_dd = OptionButton.new()
	_wave_advance_mode_dd.add_item(Localization.t("ui_wavesettings_advance_timer", "timer"), 0)
	_wave_advance_mode_dd.set_item_metadata(0, "timer")
	_wave_advance_mode_dd.add_item(Localization.t("ui_wavesettings_advance_clear", "clear"), 1)
	_wave_advance_mode_dd.set_item_metadata(1, "clear")
	_wave_advance_mode_dd.add_item(Localization.t("ui_wavesettings_advance_timer_and_clear", "timer + clear"), 2)
	_wave_advance_mode_dd.set_item_metadata(2, "timer_and_clear")
	_wave_advance_mode_dd.item_selected.connect(_on_wave_advance_mode_selected)
	am_row.add_child(_wave_advance_mode_dd)

	# music_config — raw JSON (advanced). Empty = fallback to level music_config.
	var mc_row := HBoxContainer.new()
	parent.add_child(mc_row)
	var mc_lbl := _make_label("ui_wavesettings_music_config", "music_config:", "dim")
	mc_lbl.custom_minimum_size = Vector2(120, 0)
	mc_lbl.tooltip_text = Localization.t("ui_wavesettings_music_config_hint",
		"Raw JSON object overriding level music_config for this wave. Empty = fallback.")
	mc_row.add_child(mc_lbl)
	_wave_music_config_edit = LineEdit.new()
	_wave_music_config_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wave_music_config_edit.placeholder_text = "{}"
	_wave_music_config_edit.text_submitted.connect(_on_wave_music_config_submitted)
	_wave_music_config_edit.focus_exited.connect(_on_wave_music_config_focus_exited)
	mc_row.add_child(_wave_music_config_edit)


# ─── Spawner section ────────────────────────────────────────────────────────

func _build_spawner_section(parent: Control) -> void:
	_spawner_list = ItemList.new()
	_spawner_list.custom_minimum_size = Vector2(280, 90)
	_spawner_list.item_selected.connect(_on_spawner_selected)
	parent.add_child(_spawner_list)

	_spawner_form_box = VBoxContainer.new()
	_spawner_form_box.visible = false
	parent.add_child(_spawner_form_box)

	# kind (read-only Label) — kind change goes through delete + paint per AC12.
	var kind_row := HBoxContainer.new()
	_spawner_form_box.add_child(kind_row)
	var kind_lbl := _make_label("ui_spawner_form_kind", "kind:", "dim")
	kind_lbl.custom_minimum_size = Vector2(80, 0)
	kind_row.add_child(kind_lbl)
	_spawner_form_kind_label = Label.new()
	kind_row.add_child(_spawner_form_kind_label)

	# ref dropdown.
	var ref_row := HBoxContainer.new()
	_spawner_form_box.add_child(ref_row)
	var ref_lbl := _make_label("ui_spawner_form_ref", "ref:", "dim")
	ref_lbl.custom_minimum_size = Vector2(80, 0)
	ref_row.add_child(ref_lbl)
	_spawner_form_ref_dd = OptionButton.new()
	_spawner_form_ref_dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spawner_form_ref_dd.item_selected.connect(_on_spawner_ref_selected)
	ref_row.add_child(_spawner_form_ref_dd)
	_populate_spawner_ref_dropdown()

	# timer.
	var t_row := HBoxContainer.new()
	_spawner_form_box.add_child(t_row)
	var t_lbl := _make_label("ui_spawner_form_timer", "timer:", "dim")
	t_lbl.custom_minimum_size = Vector2(80, 0)
	t_row.add_child(t_lbl)
	_spawner_form_timer_spin = SpinBox.new()
	_spawner_form_timer_spin.min_value = 1
	_spawner_form_timer_spin.max_value = 999
	_spawner_form_timer_spin.step = 1
	_spawner_form_timer_spin.value_changed.connect(_on_spawner_timer_changed)
	t_row.add_child(_spawner_form_timer_spin)

	# amount + schema-only tag.
	var a_row := HBoxContainer.new()
	_spawner_form_box.add_child(a_row)
	var a_lbl := _make_label("ui_spawner_form_amount", "amount:", "dim")
	a_lbl.custom_minimum_size = Vector2(80, 0)
	a_row.add_child(a_lbl)
	_spawner_form_amount_spin = SpinBox.new()
	_spawner_form_amount_spin.min_value = 1
	_spawner_form_amount_spin.max_value = 99
	_spawner_form_amount_spin.step = 1
	_spawner_form_amount_spin.value_changed.connect(_on_spawner_amount_changed)
	a_row.add_child(_spawner_form_amount_spin)
	_spawner_form_amount_tag = Label.new()
	_spawner_form_amount_tag.text = Localization.t(
		"ui_spawner_form_amount_schema_only", "(schema-only)")
	UiTheme.apply_label_kind(_spawner_form_amount_tag, "dim")
	_spawner_form_amount_tag.visible = false
	a_row.add_child(_spawner_form_amount_tag)

	# delay + schema-only tag.
	var d_row := HBoxContainer.new()
	_spawner_form_box.add_child(d_row)
	var d_lbl := _make_label("ui_spawner_form_delay", "delay:", "dim")
	d_lbl.custom_minimum_size = Vector2(80, 0)
	d_row.add_child(d_lbl)
	_spawner_form_delay_spin = SpinBox.new()
	_spawner_form_delay_spin.min_value = 1
	_spawner_form_delay_spin.max_value = 99
	_spawner_form_delay_spin.step = 1
	_spawner_form_delay_spin.value_changed.connect(_on_spawner_delay_changed)
	d_row.add_child(_spawner_form_delay_spin)
	_spawner_form_delay_tag = Label.new()
	_spawner_form_delay_tag.text = Localization.t(
		"ui_spawner_form_amount_schema_only", "(schema-only)")
	UiTheme.apply_label_kind(_spawner_form_delay_tag, "dim")
	_spawner_form_delay_tag.visible = false
	d_row.add_child(_spawner_form_delay_tag)


func _populate_spawner_ref_dropdown() -> void:
	# Mirror SpawnerPalette enemy list — read EnemyDB if present, else
	# leave empty (controller validates ref string anyway).
	if _spawner_form_ref_dd == null:
		return
	_spawner_form_ref_dd.clear()
	# Try EnemyDB autoload first; fall back to a small static list.
	var db: Node = get_node_or_null("/root/EnemyDB")
	if db != null and db.has_method("get_all_ids"):
		var ids: Array = db.get_all_ids()
		for i in ids.size():
			var id: StringName = StringName(str(ids[i]))
			_spawner_form_ref_dd.add_item(String(id), i)
			_spawner_form_ref_dd.set_item_metadata(i, id)
	else:
		# Defensive empty dropdown — controller can still update via direct
		# field setter if designer types ref elsewhere. Logged via warn-once.
		GameLogger.warn_once("wave_settings_panel.no_enemy_db",
			"WaveSettingsPanel: EnemyDB autoload not found — ref dropdown empty")


# ─── Skill offer section (port from old wave_panel.gd) ──────────────────────

func _build_skill_offer_section(parent: Control) -> void:
	_so_section_box = VBoxContainer.new()
	_so_section_box.add_theme_constant_override("separation", 4)
	parent.add_child(_so_section_box)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 4)
	_so_section_box.add_child(header_row)

	_so_enable_cb = CheckBox.new()
	_so_enable_cb.text = Localization.t("ui_wave_panel_skill_offer", "Skill offer after this wave")
	_so_enable_cb.toggled.connect(_on_so_enable_toggled)
	header_row.add_child(_so_enable_cb)

	_so_preview_btn = _make_btn(
		Localization.t("ui_wave_panel_skill_offer_preview", "Preview"),
		_on_so_preview_pressed)
	header_row.add_child(_so_preview_btn)

	# Body.
	var body := VBoxContainer.new()
	_so_section_box.add_child(body)

	var pool_row := HBoxContainer.new()
	body.add_child(pool_row)
	var pool_lbl := _make_label("ui_wave_panel_skill_offer.pool", "Pool", "dim")
	pool_lbl.custom_minimum_size = Vector2(80, 0)
	pool_row.add_child(pool_lbl)
	_so_pool_dd = OptionButton.new()
	_so_pool_dd.custom_minimum_size = Vector2(160, 0)
	_so_pool_dd.item_selected.connect(_on_so_field_changed_int)
	pool_row.add_child(_so_pool_dd)

	var count_row := HBoxContainer.new()
	body.add_child(count_row)
	var count_lbl := _make_label("ui_wave_panel_skill_offer.count", "Count", "dim")
	count_lbl.custom_minimum_size = Vector2(80, 0)
	count_row.add_child(count_lbl)
	_so_count_sb = SpinBox.new()
	_so_count_sb.min_value = SLOT_PICK_MIN
	_so_count_sb.max_value = SLOT_PICK_MAX
	_so_count_sb.step = 1
	_so_count_sb.value = SLOT_PICK_DEFAULT_COUNT
	_so_count_sb.value_changed.connect(_on_so_field_changed_float)
	count_row.add_child(_so_count_sb)

	_so_allow_upgrade_cb = _so_make_toggle(body, "ui_wave_panel_skill_offer.allow_upgrade", "Allow upgrade")
	_so_allow_replace_cb = _so_make_toggle(body, "ui_wave_panel_skill_offer.allow_replace", "Allow replace")
	_so_allow_skip_cb    = _so_make_toggle(body, "ui_wave_panel_skill_offer.allow_skip", "Allow skip")
	_so_exclude_owned_cb = _so_make_toggle(body, "ui_wave_panel_skill_offer.exclude_owned", "Exclude owned")

	_populate_so_pool_dropdown()
	_set_so_body_visible(false)


func _so_make_toggle(parent: Node, key: String, fallback: String) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = Localization.t(key, fallback)
	cb.toggled.connect(_on_so_field_changed_bool)
	parent.add_child(cb)
	return cb


func _populate_so_pool_dropdown() -> void:
	if _so_pool_dd == null:
		return
	_so_pool_dd.clear()
	var ctrl: Node = get_node_or_null("/root/SkillOfferController")
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


func _set_so_body_visible(visible_body: bool) -> void:
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


# ─── Wave-section dialogue triggers mirror ──────────────────────────────────

func _build_wave_triggers_mirror(parent: Control) -> void:
	_wave_triggers_list = ItemList.new()
	_wave_triggers_list.custom_minimum_size = Vector2(280, 70)
	_wave_triggers_list.item_selected.connect(_on_wave_trigger_mirror_selected)
	parent.add_child(_wave_triggers_list)
	var hint_lbl := Label.new()
	hint_lbl.text = Localization.t(
		"ui_wavesettings_wave_triggers_hint",
		"Read-only mirror — edit in the Level section above.")
	UiTheme.apply_label_kind(hint_lbl, "dim")
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(hint_lbl)


# ── Refresh ─────────────────────────────────────────────────────────────────

func _refresh_all() -> void:
	if _level == null:
		return
	_refreshing = true
	_refresh_switcher_list()
	_refresh_level_section()
	_refresh_active_wave_fields()
	_refresh_spawner_list()
	_refresh_skill_offer_section()
	_refresh_wave_triggers_mirror()
	_refresh_trigger_list()
	_update_trigger_button_states()
	_refreshing = false


func _refresh_switcher_list() -> void:
	if _switcher_list == null or _level == null:
		return
	_refreshing = true
	_switcher_list.clear()
	for i in _level.waves.size():
		var w: Dictionary = _level.waves[i]
		var spec_str: String = String(w.get("is_special", "normal"))
		var spec_seg: String = "" if spec_str == "normal" else (" · " + spec_str)
		var ttn: int = int(w.get("turns_to_next", 0))
		var line: String = "Wave %d%s · ttn=%d" % [i, spec_seg, ttn]
		_switcher_list.add_item(line)
	if _active_wave >= 0 and _active_wave < _switcher_list.item_count:
		_switcher_list.select(_active_wave)
	# Update button enablement.
	if _switcher_copy_btn != null:
		_switcher_copy_btn.disabled = (_active_wave <= 0)
	if _switcher_delete_btn != null:
		_switcher_delete_btn.disabled = (_level.waves.size() <= 1)
	_refreshing = false


func _refresh_level_section() -> void:
	if _level == null:
		return
	if _level_name_label != null:
		_level_name_label.text = _level.name
	_refresh_trigger_list()


func _refresh_active_wave_fields() -> void:
	if _level == null or _active_wave < 0 or _active_wave >= _level.waves.size():
		return
	_refreshing = true
	var w: Dictionary = _level.waves[_active_wave]
	if _wave_is_special_edit != null:
		_wave_is_special_edit.text = String(w.get("is_special", "normal"))
	if _wave_ttn_spin != null:
		_wave_ttn_spin.set_value_no_signal(int(w.get("turns_to_next", 0)))
	# respawn_player visibility — wave 0 implicit true, hide row.
	if _wave_respawn_row != null:
		_wave_respawn_row.visible = (_active_wave > 0)
	if _wave_respawn_cb != null:
		_wave_respawn_cb.set_pressed_no_signal(bool(w.get("respawn_player", false)))
	if _wave_advance_mode_dd != null:
		var am: String = String(w.get("advance_mode", "timer"))
		var found: int = -1
		for i in _wave_advance_mode_dd.item_count:
			if String(_wave_advance_mode_dd.get_item_metadata(i)) == am:
				found = i
				break
		if found >= 0:
			_wave_advance_mode_dd.select(found)
	if _wave_music_config_edit != null:
		var mc: Dictionary = w.get("music_config", {}) as Dictionary
		_wave_music_config_edit.text = "" if mc.is_empty() else JSON.stringify(mc)
	_refreshing = false


func _refresh_spawner_list() -> void:
	if _spawner_list == null or _level == null:
		return
	_refreshing = true
	_spawner_list.clear()
	if _active_wave < 0 or _active_wave >= _level.waves.size():
		_refreshing = false
		return
	var spawners: Array = _level.waves[_active_wave].get("spawners", [])
	for s in spawners:
		var coord: Vector2i = s.get("coord", Vector2i.ZERO)
		var line: String = "%s %s @ (%d,%d) · t=%d a=%d d=%d" % [
			str(s.get("kind", &"")),
			str(s.get("ref", &"")),
			coord.x, coord.y,
			int(s.get("timer", 1)),
			int(s.get("amount", 1)),
			int(s.get("delay", 1)),
		]
		_spawner_list.add_item(line)
	# Hide form when nothing selected.
	if _selected_spawner_idx < 0 or _selected_spawner_idx >= spawners.size():
		_spawner_form_box.visible = false
	else:
		_spawner_list.select(_selected_spawner_idx)
		_open_spawner_form(spawners[_selected_spawner_idx])
	_refreshing = false


func _refresh_skill_offer_section() -> void:
	if _so_enable_cb == null or _level == null:
		return
	_so_refreshing = true
	var idx: int = _active_wave
	var so: Variant = null
	if idx >= 0 and idx < _level.waves.size():
		so = _level.waves[idx].get("skill_offer", null)
	var enabled: bool = so != null and so is Dictionary
	_so_enable_cb.set_pressed_no_signal(enabled)
	_set_so_body_visible(enabled)
	if enabled:
		var d: Dictionary = so
		var saved_pool: StringName = StringName(str(d.get("pool", "")))
		_so_select_pool_in_dropdown(saved_pool)
		_so_count_sb.set_value_no_signal(int(d.get("count", SLOT_PICK_DEFAULT_COUNT)))
		_so_allow_upgrade_cb.set_pressed_no_signal(bool(d.get("allow_upgrade", true)))
		_so_allow_replace_cb.set_pressed_no_signal(bool(d.get("allow_replace", true)))
		_so_allow_skip_cb.set_pressed_no_signal(bool(d.get("allow_skip", false)))
		_so_exclude_owned_cb.set_pressed_no_signal(bool(d.get("exclude_owned", false)))
	_so_refreshing = false


func _so_select_pool_in_dropdown(pool_id: StringName) -> void:
	if _so_pool_dd == null:
		return
	for i in _so_pool_dd.item_count:
		var meta: Variant = _so_pool_dd.get_item_metadata(i)
		if StringName(str(meta)) == pool_id:
			_so_pool_dd.select(i)
			return
	if _so_pool_dd.item_count > 0:
		_so_pool_dd.select(0)


func _refresh_trigger_list() -> void:
	if _level_triggers_list == null or _level_triggers_count == null:
		return
	_level_triggers_list.clear()
	if _level == null:
		_level_triggers_count.text = Localization.t("ui_dialogue_trigger_count_zero", "0 triggers")
		return
	var triggers: Array = _level.dialogue_triggers
	_level_triggers_count.text = Localization.tf("ui_dialogue_trigger_count",
		[triggers.size()], "%d triggers")
	for d in triggers:
		var tid: String = str(d.get("id", "?"))
		var ev: String = str(d.get("event", "?"))
		var did: String = str(d.get("dialogue_id", "?"))
		_level_triggers_list.add_item("%s · %s · %s" % [tid, ev, did])


func _update_trigger_button_states() -> void:
	var has_sel: bool = _selected_trigger_idx >= 0 and _level != null \
			and _selected_trigger_idx < _level.dialogue_triggers.size()
	if _trigger_btn_edit != null:
		_trigger_btn_edit.disabled = not has_sel
	if _trigger_btn_dupe != null:
		_trigger_btn_dupe.disabled = not has_sel
	if _trigger_btn_delete != null:
		_trigger_btn_delete.disabled = not has_sel


func _refresh_wave_triggers_mirror() -> void:
	if _wave_triggers_list == null or _level == null:
		return
	_wave_triggers_list.clear()
	for d in _level.dialogue_triggers:
		var c: Variant = d.get("conditions", {})
		if not (c is Dictionary):
			continue
		var cd: Dictionary = c
		# Filter: include if conditions.wave_index matches active wave.
		# Also include level_completed-style triggers explicitly tied to the
		# final wave (per AC17 those live in level-section but appear in
		# wave-mirror when active wave is final).
		if cd.has("wave_index"):
			if int(cd["wave_index"]) == _active_wave:
				_add_wave_trigger_mirror_row(d)
		elif String(d.get("event", "")) == "level_completed":
			if _active_wave == _level.waves.size() - 1:
				_add_wave_trigger_mirror_row(d)


func _add_wave_trigger_mirror_row(d: Dictionary) -> void:
	var tid: String = str(d.get("id", "?"))
	var ev: String = str(d.get("event", "?"))
	_wave_triggers_list.add_item("%s · %s" % [tid, ev])


# ── Helpers ─────────────────────────────────────────────────────────────────

func _make_label(loc_key: String, fallback: String, kind: String = "") -> Label:
	var lbl := Label.new()
	lbl.text = Localization.t(loc_key, fallback)
	if kind != "":
		UiTheme.apply_label_kind(lbl, kind)
	return lbl


func _make_section_header(parent: Control, loc_key: String, fallback: String) -> void:
	var h := Label.new()
	h.text = Localization.t(loc_key, fallback)
	UiTheme.apply_label_kind(h, "header")
	parent.add_child(h)


func _make_btn(text: String, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(on_pressed)
	UiTheme.apply_button_styling(btn)
	return btn


func _open_spawner_form(s: Dictionary) -> void:
	if _spawner_form_box == null:
		return
	_refreshing = true
	_spawner_form_box.visible = true
	if _spawner_form_kind_label != null:
		_spawner_form_kind_label.text = str(s.get("kind", &""))
	# ref — try to find in dropdown; if not, leave first.
	if _spawner_form_ref_dd != null:
		var saved_ref: StringName = StringName(str(s.get("ref", "")))
		var found: int = -1
		for i in _spawner_form_ref_dd.item_count:
			if StringName(str(_spawner_form_ref_dd.get_item_metadata(i))) == saved_ref:
				found = i
				break
		if found >= 0:
			_spawner_form_ref_dd.select(found)
	if _spawner_form_timer_spin != null:
		_spawner_form_timer_spin.set_value_no_signal(int(s.get("timer", 1)))
	if _spawner_form_amount_spin != null:
		var amt: int = int(s.get("amount", 1))
		_spawner_form_amount_spin.set_value_no_signal(amt)
		_spawner_form_amount_tag.visible = (amt > 1)
	if _spawner_form_delay_spin != null:
		var dly: int = int(s.get("delay", 1))
		_spawner_form_delay_spin.set_value_no_signal(dly)
		_spawner_form_delay_tag.visible = (dly > 1)
	_refreshing = false


func _selected_spawner_coord() -> Vector2i:
	if _level == null or _active_wave < 0 or _active_wave >= _level.waves.size():
		return Vector2i.ZERO
	var spawners: Array = _level.waves[_active_wave].get("spawners", [])
	if _selected_spawner_idx < 0 or _selected_spawner_idx >= spawners.size():
		return Vector2i.ZERO
	return spawners[_selected_spawner_idx].get("coord", Vector2i.ZERO)


# ── Switcher signals ────────────────────────────────────────────────────────

func _on_switcher_item_selected(idx: int) -> void:
	if _refreshing:
		return
	wave_switch_requested.emit(idx)


func _on_switcher_add_pressed() -> void:
	wave_add_requested.emit(_active_wave)


func _on_switcher_copy_pressed() -> void:
	if _active_wave <= 0:
		return
	wave_copy_requested.emit(_active_wave)


func _on_switcher_delete_pressed() -> void:
	if _level == null or _level.waves.size() <= 1:
		return
	wave_delete_requested.emit(_active_wave)


# ── Wave field signals ──────────────────────────────────────────────────────

func _emit_wave_field(field: String, value: Variant) -> void:
	if _refreshing:
		return
	wave_field_changed.emit(_active_wave, field, value)


func _on_wave_is_special_submitted(text: String) -> void:
	_emit_wave_field("is_special", text.strip_edges())


func _on_wave_is_special_focus_exited() -> void:
	_on_wave_is_special_submitted(_wave_is_special_edit.text)


func _on_wave_ttn_changed(v: float) -> void:
	_emit_wave_field("turns_to_next", int(v))


func _on_wave_respawn_toggled(pressed: bool) -> void:
	_emit_wave_field("respawn_player", pressed)


func _on_wave_advance_mode_selected(idx: int) -> void:
	var meta: Variant = _wave_advance_mode_dd.get_item_metadata(idx)
	_emit_wave_field("advance_mode", String(meta))


func _on_wave_music_config_submitted(text: String) -> void:
	var trimmed: String = text.strip_edges()
	if trimmed == "":
		_emit_wave_field("music_config", {})
		return
	var parsed: Variant = JSON.parse_string(trimmed)
	if not (parsed is Dictionary):
		# Reject silently — controller will toast on validation. Don't emit
		# malformed dicts up the chain.
		GameLogger.warn("WaveSettingsPanel",
			"music_config edit rejected — invalid JSON object: " + trimmed)
		return
	_emit_wave_field("music_config", parsed)


func _on_wave_music_config_focus_exited() -> void:
	_on_wave_music_config_submitted(_wave_music_config_edit.text)


# ── Spawner signals ─────────────────────────────────────────────────────────

func _on_spawner_selected(idx: int) -> void:
	_selected_spawner_idx = idx
	if _level == null or _active_wave < 0 or _active_wave >= _level.waves.size():
		return
	var spawners: Array = _level.waves[_active_wave].get("spawners", [])
	if idx < 0 or idx >= spawners.size():
		_spawner_form_box.visible = false
		return
	_open_spawner_form(spawners[idx])


func _emit_spawner_field(field: String, value: Variant) -> void:
	if _refreshing:
		return
	var coord: Vector2i = _selected_spawner_coord()
	if coord == Vector2i.ZERO and _selected_spawner_idx < 0:
		return  # nothing selected
	spawner_field_changed.emit(coord, {field: value})


func _on_spawner_ref_selected(idx: int) -> void:
	var meta: Variant = _spawner_form_ref_dd.get_item_metadata(idx)
	_emit_spawner_field("ref", StringName(str(meta)))


func _on_spawner_timer_changed(v: float) -> void:
	_emit_spawner_field("timer", int(v))


func _on_spawner_amount_changed(v: float) -> void:
	var amt: int = int(v)
	if _spawner_form_amount_tag != null:
		_spawner_form_amount_tag.visible = (amt > 1)
	_emit_spawner_field("amount", amt)


func _on_spawner_delay_changed(v: float) -> void:
	var dly: int = int(v)
	if _spawner_form_delay_tag != null:
		_spawner_form_delay_tag.visible = (dly > 1)
	_emit_spawner_field("delay", dly)


# ── Skill offer signals (ported) ────────────────────────────────────────────

func _so_current_offer_dict() -> Dictionary:
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


func _so_emit_changed_for_active() -> void:
	if _so_refreshing or _level == null:
		return
	if not _so_enable_cb.button_pressed:
		skill_offer_changed.emit(_active_wave, null)
	else:
		skill_offer_changed.emit(_active_wave, _so_current_offer_dict())


func _on_so_enable_toggled(pressed: bool) -> void:
	_set_so_body_visible(pressed)
	_so_emit_changed_for_active()


func _on_so_field_changed_bool(_v: bool) -> void:
	_so_emit_changed_for_active()


func _on_so_field_changed_float(_v: float) -> void:
	_so_emit_changed_for_active()


func _on_so_field_changed_int(_v: int) -> void:
	_so_emit_changed_for_active()


func _on_so_preview_pressed() -> void:
	skill_offer_preview_requested.emit(_active_wave)


# ── Trigger CRUD signals ────────────────────────────────────────────────────

func _on_trigger_list_selected(idx: int) -> void:
	_selected_trigger_idx = idx
	_update_trigger_button_states()


func _on_trigger_add() -> void:
	_selected_trigger_idx = -1
	_editing_trigger_new = true
	if _level_triggers_list != null:
		_level_triggers_list.deselect_all()
	_update_trigger_button_states()
	_open_trigger_form({})


func _on_trigger_edit() -> void:
	if _selected_trigger_idx < 0 or _level == null:
		return
	if _selected_trigger_idx >= _level.dialogue_triggers.size():
		return
	_editing_trigger_new = false
	_open_trigger_form(_level.dialogue_triggers[_selected_trigger_idx])


func _on_trigger_duplicate() -> void:
	if _selected_trigger_idx < 0 or _level == null:
		return
	if _selected_trigger_idx >= _level.dialogue_triggers.size():
		return
	var src: Dictionary = _level.dialogue_triggers[_selected_trigger_idx].duplicate(true)
	src["id"] = str(src.get("id", "")) + "_copy"
	_editing_trigger_new = true
	_selected_trigger_idx = -1
	_open_trigger_form(src)


func _on_trigger_delete() -> void:
	if _selected_trigger_idx < 0 or _level == null:
		return
	if _selected_trigger_idx >= _level.dialogue_triggers.size():
		return
	var tid: StringName = StringName(str(
		_level.dialogue_triggers[_selected_trigger_idx].get("id", "")))
	trigger_deleted.emit(tid)
	_selected_trigger_idx = -1
	_close_trigger_form()


func _on_trigger_event_option_selected(idx: int) -> void:
	# Last item is "Custom..." — show custom LineEdit when picked.
	_trigger_form_event_custom.visible = (idx == CURATED_EVENTS.size())


func _on_trigger_dialogue_filter_changed(txt: String) -> void:
	_populate_dialogue_picker(txt)


func _on_trigger_condition_toggled(key: String, on: bool) -> void:
	if _trigger_cond_widgets.has(key):
		_trigger_cond_widgets[key].editor.visible = on


func _on_trigger_form_save() -> void:
	var d: Dictionary = _collect_trigger_form_data()
	var err: String = _validate_trigger_form(d)
	if err != "":
		_trigger_form_error.text = err
		_trigger_form_error.visible = true
		return
	_trigger_form_error.visible = false
	if _editing_trigger_new:
		trigger_created.emit(d)
	else:
		var old_id: StringName = &""
		if _selected_trigger_idx >= 0 and _level != null \
				and _selected_trigger_idx < _level.dialogue_triggers.size():
			old_id = StringName(str(
				_level.dialogue_triggers[_selected_trigger_idx].get("id", "")))
		trigger_updated.emit(old_id, d)
	_close_trigger_form()


func _on_trigger_form_cancel() -> void:
	_close_trigger_form()


func _open_trigger_form(data: Dictionary) -> void:
	if _trigger_form_box == null:
		return
	_editing_trigger = true
	_trigger_form_box.visible = true
	if _trigger_form_error != null:
		_trigger_form_error.visible = false
	if _trigger_form_id != null:
		_trigger_form_id.text = str(data.get("id", ""))
	var ev: String = str(data.get("event", "level_started"))
	var ev_idx: int = CURATED_EVENTS.find(ev)
	if ev_idx >= 0:
		_trigger_form_event_option.select(ev_idx)
		_trigger_form_event_custom.visible = false
	else:
		_trigger_form_event_option.select(CURATED_EVENTS.size())
		_trigger_form_event_custom.visible = true
		_trigger_form_event_custom.text = ev
	var pm: String = str(data.get("play_mode", "request"))
	_trigger_form_playmode_request.set_pressed_no_signal(pm == "request")
	_trigger_form_playmode_play.set_pressed_no_signal(pm == "play")
	_populate_dialogue_picker("")
	_trigger_form_dialogue_filter.text = ""
	var did: String = str(data.get("dialogue_id", ""))
	for i in _trigger_form_dialogue_option.item_count:
		if _trigger_form_dialogue_option.get_item_text(i) == did:
			_trigger_form_dialogue_option.select(i)
			break
	# Conditions.
	var c: Dictionary = data.get("conditions", {})
	for key in _trigger_cond_widgets:
		var w: Dictionary = _trigger_cond_widgets[key]
		var has_cond: bool = c.has(key)
		(w.check as CheckBox).set_pressed_no_signal(has_cond)
		w.editor.visible = has_cond
		if has_cond:
			if w.editor is LineEdit:
				(w.editor as LineEdit).text = str(c[key])
			elif w.editor is CheckBox:
				(w.editor as CheckBox).set_pressed_no_signal(bool(c[key]))


func _close_trigger_form() -> void:
	_editing_trigger = false
	_editing_trigger_new = false
	if _trigger_form_box != null:
		_trigger_form_box.visible = false
	if _trigger_form_error != null:
		_trigger_form_error.visible = false


func _collect_trigger_form_data() -> Dictionary:
	var ev: String
	if _trigger_form_event_option.selected == CURATED_EVENTS.size():
		ev = _trigger_form_event_custom.text.strip_edges()
	else:
		ev = CURATED_EVENTS[_trigger_form_event_option.selected]
	var did: String = ""
	if _trigger_form_dialogue_option.item_count > 0 \
			and _trigger_form_dialogue_option.selected >= 0:
		did = _trigger_form_dialogue_option.get_item_text(
			_trigger_form_dialogue_option.selected)
	var c: Dictionary = {}
	for key in _trigger_cond_widgets:
		var w: Dictionary = _trigger_cond_widgets[key]
		if not (w.check as CheckBox).button_pressed:
			continue
		var t: String = String(w.get("type", "string"))
		if w.editor is LineEdit:
			var raw: String = (w.editor as LineEdit).text.strip_edges()
			match t:
				"int":
					c[key] = int(raw) if raw != "" else 0
				"float":
					c[key] = float(raw) if raw != "" else 1.0
				_:
					c[key] = raw
		elif w.editor is CheckBox:
			c[key] = (w.editor as CheckBox).button_pressed
	var pm: String = "play" if _trigger_form_playmode_play.button_pressed else "request"
	return {
		"id": _trigger_form_id.text.strip_edges(),
		"event": ev,
		"dialogue_id": did,
		"play_mode": pm,
		"conditions": c,
	}


func _validate_trigger_form(d: Dictionary) -> String:
	var tid: String = str(d.get("id", ""))
	if tid == "":
		return Localization.t("ui_trigger_validate_id_empty", "id must not be empty")
	if _level != null:
		for i in _level.dialogue_triggers.size():
			if i == _selected_trigger_idx and not _editing_trigger_new:
				continue  # editing self — skip
			if str(_level.dialogue_triggers[i].get("id", "")) == tid:
				return Localization.tf("ui_trigger_validate_id_dup", [tid],
					"id '%s' already exists")
	if str(d.get("event", "")) == "":
		return Localization.t("ui_trigger_validate_event_empty",
			"event must not be empty")
	return ""


# ── Wave-section trigger mirror signal ──────────────────────────────────────

func _on_wave_trigger_mirror_selected(_idx: int) -> void:
	# Translate mirror-row index back to level-section trigger id, then
	# re-select in level-section list and open form. Mirror is built by
	# filtering _level.dialogue_triggers — we can't trust _idx maps 1:1
	# to dialogue_triggers index, so resolve via the visible row text id.
	if _level == null or _wave_triggers_list == null:
		return
	var row_text: String = _wave_triggers_list.get_item_text(_idx)
	var dot_pos: int = row_text.find(" · ")
	var tid_str: String = row_text.substr(0, dot_pos) if dot_pos > 0 else row_text
	select_trigger(StringName(tid_str))
