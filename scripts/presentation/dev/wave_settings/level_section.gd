class_name WaveSettingsLevelSection
extends VBoxContainer

## Level-scope tab of WaveSettingsPanel. Two things:
##   1. Read-only echo of the level name (from LevelMetaPanel).
##   2. Full CRUD UI for level-scoped dialogue triggers — list, add, edit,
##      duplicate, delete, with an inline form for the selected trigger.
##
## Triggers are level-scoped (not wave-scoped) on purpose: one trigger may
## fire on any wave (filtered via conditions.wave_index). The wave switcher
## above doesn't affect this tab's content.
##
## Signals trigger_created / trigger_updated / trigger_deleted bubble to
## the host panel, which forwards them to EditorController.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")

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

signal trigger_created(trigger_dict: Dictionary)
signal trigger_updated(old_id: StringName, trigger_dict: Dictionary)
signal trigger_deleted(trigger_id: StringName)

var _level: LevelData = null
var _selected_idx: int = -1
var _editing_new: bool = false

# Header.
var _name_label: Label
var _triggers_count_label: Label

# List + CRUD buttons.
var _list: ItemList
var _btn_edit: Button
var _btn_dupe: Button
var _btn_delete: Button

# Form.
var _form_box: VBoxContainer
var _form_error: Label
var _form_id: LineEdit
var _form_event_option: OptionButton
var _form_event_custom: LineEdit
var _form_dialogue_filter: LineEdit
var _form_dialogue_option: OptionButton
var _form_playmode_request: CheckBox
var _form_playmode_play: CheckBox
var _form_conditions: VBoxContainer
var _cond_widgets: Dictionary = {}  # key → {check, editor, type}


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_build()


func bind_level(level: LevelData) -> void:
	_level = level
	_selected_idx = -1
	_close_form()
	_refresh()


func set_active_wave(_idx: int) -> void:
	# Triggers are level-scoped — wave changes don't affect this tab.
	pass


## External call from host to focus a specific trigger by id (e.g. when the
## wave-mirror list selects one). Re-selects in list and opens the edit
## form. No-op if not found.
func select_trigger(tid: StringName) -> void:
	if _level == null:
		return
	for i in _level.dialogue_triggers.size():
		if StringName(str(_level.dialogue_triggers[i].get("id", ""))) == tid:
			_selected_idx = i
			if _list != null:
				_list.select(i)
			_editing_new = false
			_open_form(_level.dialogue_triggers[i])
			_update_button_states()
			return


# ── Build ───────────────────────────────────────────────────────────────────

func _build() -> void:
	# Name (read-only mirror).
	var name_row := HBoxContainer.new()
	add_child(name_row)
	var name_lbl := _make_label("ui_wavesettings_level_name", "name:")
	name_lbl.custom_minimum_size = Vector2(80, 0)
	name_row.add_child(name_lbl)
	_name_label = Label.new()
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_label)

	# Trigger count + list.
	var count_row := HBoxContainer.new()
	add_child(count_row)
	var count_lbl := _make_label("ui_wavesettings_dialogue_triggers_header", "Triggers")
	count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_row.add_child(count_lbl)
	_triggers_count_label = Label.new()
	UiTheme.apply_label_kind(_triggers_count_label, "dim")
	count_row.add_child(_triggers_count_label)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 110)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_list_selected)
	add_child(_list)

	# CRUD buttons.
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	add_child(btn_row)
	var btn_add := _make_btn(Localization.t("ui_trigger_btn_add", "+ Add"), _on_add)
	btn_row.add_child(btn_add)
	_btn_edit = _make_btn(Localization.t("ui_trigger_btn_edit", "Edit"), _on_edit)
	btn_row.add_child(_btn_edit)
	_btn_dupe = _make_btn(Localization.t("ui_trigger_btn_dupe", "Dupe"), _on_dupe)
	btn_row.add_child(_btn_dupe)
	_btn_delete = _make_btn(Localization.t("ui_trigger_btn_delete", "Delete"), _on_delete)
	btn_row.add_child(_btn_delete)

	# Edit form (hidden by default).
	_form_box = VBoxContainer.new()
	_form_box.visible = false
	add_child(_form_box)
	_build_form(_form_box)

	_form_error = Label.new()
	UiTheme.apply_label_kind(_form_error, "error")
	_form_error.autowrap_mode = TextServer.AUTOWRAP_WORD
	_form_error.visible = false
	add_child(_form_error)

	_update_button_states()


func _build_form(parent: Control) -> void:
	# id row.
	var id_row := HBoxContainer.new()
	parent.add_child(id_row)
	var id_lbl := _make_label("ui_trigger_id_help", "id:")
	id_lbl.custom_minimum_size = Vector2(70, 0)
	id_lbl.tooltip_text = Localization.t("ui_trigger_id_help_tooltip",
		"Unique trigger ID — used in logs and once-tracking. Not the dialogue.")
	id_row.add_child(id_lbl)
	_form_id = LineEdit.new()
	_form_id.placeholder_text = "unique_id"
	_form_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_row.add_child(_form_id)

	# event row — curated dropdown + custom override.
	var ev_row := HBoxContainer.new()
	parent.add_child(ev_row)
	var ev_lbl := _make_label("ui_dialogue_trigger_event", "event:")
	ev_lbl.custom_minimum_size = Vector2(70, 0)
	ev_row.add_child(ev_lbl)
	_form_event_option = OptionButton.new()
	_form_event_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for e in CURATED_EVENTS:
		_form_event_option.add_item(e)
	_form_event_option.add_item(Localization.t("ui_trigger_event_custom", "Custom..."))
	_form_event_option.item_selected.connect(_on_event_option_selected)
	ev_row.add_child(_form_event_option)
	_form_event_custom = LineEdit.new()
	_form_event_custom.placeholder_text = "custom_signal_name"
	_form_event_custom.visible = false
	_form_event_custom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ev_row.add_child(_form_event_custom)

	# dialogue_id row.
	var dlg_row := HBoxContainer.new()
	parent.add_child(dlg_row)
	var dlg_lbl := _make_label("ui_trigger_dialogue_help", "dialogue:")
	dlg_lbl.custom_minimum_size = Vector2(70, 0)
	dlg_lbl.tooltip_text = Localization.t("ui_trigger_dialogue_help_tooltip",
		"Dialogue ID — what plays when the trigger fires. Distinct from trigger id above.")
	dlg_row.add_child(dlg_lbl)
	_form_dialogue_filter = LineEdit.new()
	_form_dialogue_filter.placeholder_text = Localization.t("ui_common_filter_placeholder", "filter...")
	_form_dialogue_filter.custom_minimum_size = Vector2(60, 0)
	_form_dialogue_filter.text_changed.connect(_on_dialogue_filter_changed)
	dlg_row.add_child(_form_dialogue_filter)
	_form_dialogue_option = OptionButton.new()
	_form_dialogue_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dlg_row.add_child(_form_dialogue_option)
	_populate_dialogue_picker("")

	# play_mode row — request | play.
	var pm_row := HBoxContainer.new()
	parent.add_child(pm_row)
	var pm_lbl := _make_label("ui_dialogue_trigger_mode", "mode:")
	pm_lbl.custom_minimum_size = Vector2(70, 0)
	pm_row.add_child(pm_lbl)
	_form_playmode_request = CheckBox.new()
	_form_playmode_request.text = Localization.t("ui_trigger_play_mode_request", "request")
	_form_playmode_request.button_group = ButtonGroup.new()
	_form_playmode_request.set_pressed_no_signal(true)
	pm_row.add_child(_form_playmode_request)
	_form_playmode_play = CheckBox.new()
	_form_playmode_play.text = Localization.t("ui_trigger_play_mode_play", "play")
	_form_playmode_play.button_group = _form_playmode_request.button_group
	pm_row.add_child(_form_playmode_play)

	# Conditions section.
	var cond_lbl := _make_label("ui_dialogue_trigger_conditions", "Conditions (opt):")
	parent.add_child(cond_lbl)
	_form_conditions = VBoxContainer.new()
	parent.add_child(_form_conditions)
	_build_condition_widgets()

	# Form buttons.
	var form_btns := HBoxContainer.new()
	parent.add_child(form_btns)
	var save_btn := _make_btn(Localization.t("ui_trigger_btn_save", "Save"), _on_form_save)
	form_btns.add_child(save_btn)
	var cancel_btn := _make_btn(Localization.t("ui_trigger_btn_cancel", "Cancel"), _on_form_cancel)
	form_btns.add_child(cancel_btn)


func _build_condition_widgets() -> void:
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
		_form_conditions.add_child(row)
		var chk := CheckBox.new()
		chk.text = Localization.t(String(spec["label_key"]), String(spec["fallback"]))
		var key_capture: String = String(spec["key"])
		chk.toggled.connect(func(on: bool) -> void: _on_condition_toggled(key_capture, on))
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
		_cond_widgets[key_capture] = {"check": chk, "editor": ed, "type": spec["type"]}


func _populate_dialogue_picker(filter: String) -> void:
	if _form_dialogue_option == null:
		return
	_form_dialogue_option.clear()
	var ids: Array = []
	var db: Node = get_node_or_null("/root/DialogueDB")
	if db != null and db.has_method("get_all_ids"):
		ids = db.get_all_ids()
	var lf: String = filter.strip_edges().to_lower()
	for id_str in ids:
		var s: String = str(id_str)
		if lf == "" or lf in s.to_lower():
			_form_dialogue_option.add_item(s)


# ── Refresh ─────────────────────────────────────────────────────────────────

func _refresh() -> void:
	_refresh_name()
	_refresh_list()
	_update_button_states()


func _refresh_name() -> void:
	if _name_label == null:
		return
	if _level == null:
		_name_label.text = ""
	else:
		_name_label.text = Localization.t(_level.name, _level.name)


func _refresh_list() -> void:
	if _list == null or _triggers_count_label == null:
		return
	_list.clear()
	if _level == null:
		_triggers_count_label.text = Localization.t("ui_dialogue_trigger_count_zero", "0 triggers")
		return
	var triggers: Array = _level.dialogue_triggers
	_triggers_count_label.text = Localization.tf("ui_dialogue_trigger_count",
		[triggers.size()], "%d triggers")
	for d in triggers:
		var tid: String = str(d.get("id", "?"))
		var ev: String = str(d.get("event", "?"))
		var did: String = str(d.get("dialogue_id", "?"))
		_list.add_item("%s · %s · %s" % [tid, ev, did])


func _update_button_states() -> void:
	var has_sel: bool = _selected_idx >= 0 and _level != null \
			and _selected_idx < _level.dialogue_triggers.size()
	if _btn_edit != null:
		_btn_edit.disabled = not has_sel
	if _btn_dupe != null:
		_btn_dupe.disabled = not has_sel
	if _btn_delete != null:
		_btn_delete.disabled = not has_sel


# ── Form open/close ─────────────────────────────────────────────────────────

func _open_form(data: Dictionary) -> void:
	if _form_box == null:
		return
	_form_box.visible = true
	if _form_error != null:
		_form_error.visible = false
	if _form_id != null:
		_form_id.text = str(data.get("id", ""))
	var ev: String = str(data.get("event", "level_started"))
	var ev_idx: int = CURATED_EVENTS.find(ev)
	if ev_idx >= 0:
		_form_event_option.select(ev_idx)
		_form_event_custom.visible = false
	else:
		_form_event_option.select(CURATED_EVENTS.size())
		_form_event_custom.visible = true
		_form_event_custom.text = ev
	var pm: String = str(data.get("play_mode", "request"))
	_form_playmode_request.set_pressed_no_signal(pm == "request")
	_form_playmode_play.set_pressed_no_signal(pm == "play")
	_populate_dialogue_picker("")
	_form_dialogue_filter.text = ""
	var did: String = str(data.get("dialogue_id", ""))
	for i in _form_dialogue_option.item_count:
		if _form_dialogue_option.get_item_text(i) == did:
			_form_dialogue_option.select(i)
			break
	# Conditions.
	var c: Dictionary = data.get("conditions", {})
	for key in _cond_widgets:
		var w: Dictionary = _cond_widgets[key]
		var has_cond: bool = c.has(key)
		(w.check as CheckBox).set_pressed_no_signal(has_cond)
		w.editor.visible = has_cond
		if has_cond:
			if w.editor is LineEdit:
				(w.editor as LineEdit).text = str(c[key])
			elif w.editor is CheckBox:
				(w.editor as CheckBox).set_pressed_no_signal(bool(c[key]))


func _close_form() -> void:
	_editing_new = false
	if _form_box != null:
		_form_box.visible = false
	if _form_error != null:
		_form_error.visible = false


func _collect_form_data() -> Dictionary:
	var ev: String
	if _form_event_option.selected == CURATED_EVENTS.size():
		ev = _form_event_custom.text.strip_edges()
	else:
		ev = CURATED_EVENTS[_form_event_option.selected]
	var did: String = ""
	if _form_dialogue_option.item_count > 0 and _form_dialogue_option.selected >= 0:
		did = _form_dialogue_option.get_item_text(_form_dialogue_option.selected)
	var c: Dictionary = {}
	for key in _cond_widgets:
		var w: Dictionary = _cond_widgets[key]
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
	var pm: String = "play" if _form_playmode_play.button_pressed else "request"
	return {
		"id": _form_id.text.strip_edges(),
		"event": ev,
		"dialogue_id": did,
		"play_mode": pm,
		"conditions": c,
	}


func _validate_form(d: Dictionary) -> String:
	var tid: String = str(d.get("id", ""))
	if tid == "":
		return Localization.t("ui_trigger_validate_id_empty", "id must not be empty")
	if _level != null:
		for i in _level.dialogue_triggers.size():
			if i == _selected_idx and not _editing_new:
				continue  # editing self
			if str(_level.dialogue_triggers[i].get("id", "")) == tid:
				return Localization.tf("ui_trigger_validate_id_dup", [tid],
					"id '%s' already exists")
	if str(d.get("event", "")) == "":
		return Localization.t("ui_trigger_validate_event_empty",
			"event must not be empty")
	return ""


# ── Helpers ─────────────────────────────────────────────────────────────────

func _make_label(loc_key: String, fallback: String) -> Label:
	var lbl := Label.new()
	lbl.text = Localization.t(loc_key, fallback)
	UiTheme.apply_label_kind(lbl, "dim")
	return lbl


func _make_btn(text: String, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	UiTheme.apply_button_styling(btn)
	btn.pressed.connect(on_pressed)
	return btn


# ── Signal handlers ─────────────────────────────────────────────────────────

func _on_list_selected(idx: int) -> void:
	_selected_idx = idx
	_update_button_states()


func _on_add() -> void:
	_selected_idx = -1
	_editing_new = true
	if _list != null:
		_list.deselect_all()
	_update_button_states()
	_open_form({})


func _on_edit() -> void:
	if _selected_idx < 0 or _level == null:
		return
	if _selected_idx >= _level.dialogue_triggers.size():
		return
	_editing_new = false
	_open_form(_level.dialogue_triggers[_selected_idx])


func _on_dupe() -> void:
	if _selected_idx < 0 or _level == null:
		return
	if _selected_idx >= _level.dialogue_triggers.size():
		return
	var src: Dictionary = _level.dialogue_triggers[_selected_idx].duplicate(true)
	src["id"] = str(src.get("id", "")) + "_copy"
	_editing_new = true
	_selected_idx = -1
	_open_form(src)


func _on_delete() -> void:
	if _selected_idx < 0 or _level == null:
		return
	if _selected_idx >= _level.dialogue_triggers.size():
		return
	var tid: StringName = StringName(str(
		_level.dialogue_triggers[_selected_idx].get("id", "")))
	trigger_deleted.emit(tid)
	_selected_idx = -1
	_close_form()


func _on_event_option_selected(idx: int) -> void:
	_form_event_custom.visible = (idx == CURATED_EVENTS.size())


func _on_dialogue_filter_changed(txt: String) -> void:
	_populate_dialogue_picker(txt)


func _on_condition_toggled(key: String, on: bool) -> void:
	if _cond_widgets.has(key):
		_cond_widgets[key].editor.visible = on


func _on_form_save() -> void:
	var d: Dictionary = _collect_form_data()
	var err: String = _validate_form(d)
	if err != "":
		_form_error.text = err
		_form_error.visible = true
		return
	_form_error.visible = false
	if _editing_new:
		trigger_created.emit(d)
	else:
		var old_id: StringName = &""
		if _selected_idx >= 0 and _level != null \
				and _selected_idx < _level.dialogue_triggers.size():
			old_id = StringName(str(
				_level.dialogue_triggers[_selected_idx].get("id", "")))
		trigger_updated.emit(old_id, d)
	_close_form()


func _on_form_cancel() -> void:
	_close_form()
