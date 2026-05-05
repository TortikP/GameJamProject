extends PanelContainer
## DialogueTriggerPanel -- editor sidebar for 039-dialogue-triggers.
##
## CRUD for LevelData.dialogue_triggers[]. Emits signals consumed by
## map_editor_controller which owns _level and _mark_dirty().
##
## Layout (built in _ready from code, no separate .tscn children besides
## the root PanelContainer):
##   VBox
##     Header: Label "Dialogue triggers" + count + collapse button
##     ItemList (trigger list)
##     ButtonRow: Add . Edit . Duplicate . Delete
##     EditForm (collapsible VBox) -- Add/Edit only
##       IdRow, EventRow, DialogueRow, PlayModeRow, ConditionsSection
##       FormButtons: Save . Cancel
##
## Owner: Andrey / 039-dialogue-triggers.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")
const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const DraggablePanelScript = preload("res://scripts/presentation/dev/draggable_panel.gd")

## Emitted after CRUD -- controller updates _level.dialogue_triggers + _mark_dirty.
signal trigger_created(trigger_dict: Dictionary)
signal trigger_updated(old_id: StringName, trigger_dict: Dictionary)
signal trigger_deleted(trigger_id: StringName)
## Emitted when user clicks a row -- controller calls select_trigger from timeline.
signal trigger_selected(trigger_id: StringName)

## Curated event vocabulary shown in the dropdown.
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

var _level: LevelData = null
var _selected_idx: int = -1   # index in _level.dialogue_triggers[]
var _editing: bool = false    # true = form is open (add or edit)
var _editing_new: bool = false
var _collapsed: bool = false

# UI references (built in _ready).
var _count_label: Label
var _collapse_btn: Button
var _title_label: Label   # drag handle
var _btn_row: Control     # Add/Edit/Dupe/Delete row
var _list: ItemList
var _btn_edit: Button
var _btn_dupe: Button
var _btn_delete: Button
var _form_container: Control
var _form_id: LineEdit
var _form_event_option: OptionButton
var _form_event_custom: LineEdit
var _form_dialogue_filter: LineEdit
var _form_dialogue_option: OptionButton
var _form_playmode_request: CheckBox
var _form_playmode_play: CheckBox
var _form_conditions: VBoxContainer
# Condition widgets (checkbox + value editor pairs)
var _cond_widgets: Dictionary = {}  # key -> {check: CheckBox, editor: Control}
var _form_error_label: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	_build_ui()
	_refresh_list()
	_update_button_states()
	# Make the panel draggable via its title label as handle.
	var dragger := DraggablePanelScript.new()
	add_child(dragger)
	if _title_label != null:
		dragger.setup(self, _title_label)


## Bind a LevelData. Called on level load + any CRUD from controller side.
func bind_level(level: LevelData) -> void:
	_level = level
	_selected_idx = -1
	_close_form()
	_refresh_list()
	_update_button_states()


## Select a trigger row by id (called from controller on timeline marker click).
func select_trigger(id: StringName) -> void:
	if _level == null:
		return
	for i in _level.dialogue_triggers.size():
		if StringName(str(_level.dialogue_triggers[i].get("id", ""))) == id:
			_selected_idx = i
			_list.select(i)
			_update_button_states()
			return


# -- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	UiTheme.apply_label_kind(title, "header")
	title.text = Localization.t("ui_dialogue_trigger_title", "Dialogue Triggers")
	header.add_child(title)
	_title_label = title
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_count_label = Label.new()
	UiTheme.apply_label_kind(_count_label, "dim")
	header.add_child(_count_label)
	_collapse_btn = Button.new()
	UiTheme.apply_button_styling(_collapse_btn)
	_collapse_btn.text = "v"
	_collapse_btn.flat = true
	_collapse_btn.pressed.connect(_on_collapse_toggled)
	header.add_child(_collapse_btn)

	# List
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(200, 80)
	_list.item_selected.connect(_on_list_item_selected)
	vbox.add_child(_list)

	# Button row
	var btn_row := HBoxContainer.new()
	_btn_row = btn_row
	vbox.add_child(btn_row)
	var btn_add := Button.new()
	UiTheme.apply_button_styling(btn_add)
	btn_add.text = Localization.t("ui_dialogue_trigger_add", "+ Add")
	btn_add.pressed.connect(_on_add_pressed)
	btn_row.add_child(btn_add)
	_btn_edit = Button.new()
	UiTheme.apply_button_styling(_btn_edit)
	_btn_edit.text = Localization.t("ui_common_edit", "Edit")
	_btn_edit.pressed.connect(_on_edit_pressed)
	btn_row.add_child(_btn_edit)
	_btn_dupe = Button.new()
	UiTheme.apply_button_styling(_btn_dupe)
	_btn_dupe.text = Localization.t("ui_common_duplicate_short", "Dupe")
	_btn_dupe.pressed.connect(_on_duplicate_pressed)
	btn_row.add_child(_btn_dupe)
	_btn_delete = Button.new()
	UiTheme.apply_button_styling(_btn_delete)
	_btn_delete.text = Localization.t("ui_common_delete", "Delete")
	_btn_delete.pressed.connect(_on_delete_pressed)
	btn_row.add_child(_btn_delete)

	# Edit form (hidden by default)
	_form_container = VBoxContainer.new()
	_form_container.visible = false
	vbox.add_child(_form_container)
	_build_form(_form_container)

	# Error label
	_form_error_label = Label.new()
	UiTheme.apply_label_kind(_form_error_label, "error")
	_form_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_form_error_label.visible = false
	vbox.add_child(_form_error_label)


func _build_form(parent: Control) -> void:
	var sb := VBoxContainer.new()
	parent.add_child(sb)

	# id row
	var id_row := HBoxContainer.new()
	sb.add_child(id_row)
	var id_lbl := Label.new(); id_lbl.text = Localization.t("ui_dialogue_trigger_id", "id:"); UiTheme.apply_label_kind(id_lbl, "dim")
	id_row.add_child(id_lbl)
	_form_id = LineEdit.new()
	_form_id.placeholder_text = "unique_id"
	_form_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_row.add_child(_form_id)

	# event row
	var ev_row := HBoxContainer.new()
	sb.add_child(ev_row)
	var ev_lbl := Label.new(); ev_lbl.text = Localization.t("ui_dialogue_trigger_event", "event:"); UiTheme.apply_label_kind(ev_lbl, "dim")
	ev_row.add_child(ev_lbl)
	_form_event_option = OptionButton.new()
	_form_event_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for e in CURATED_EVENTS:
		_form_event_option.add_item(e)
	_form_event_option.add_item(Localization.t("ui_common_custom", "Custom..."))
	_form_event_option.item_selected.connect(_on_event_option_selected)
	ev_row.add_child(_form_event_option)
	_form_event_custom = LineEdit.new()
	_form_event_custom.placeholder_text = "custom_signal_name"
	_form_event_custom.visible = false
	_form_event_custom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ev_row.add_child(_form_event_custom)

	# dialogue_id row
	var dlg_row := HBoxContainer.new()
	sb.add_child(dlg_row)
	var dlg_lbl := Label.new(); dlg_lbl.text = Localization.t("ui_dialogue_trigger_dialogue", "dialogue:"); UiTheme.apply_label_kind(dlg_lbl, "dim")
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

	# play_mode row
	var pm_row := HBoxContainer.new()
	sb.add_child(pm_row)
	var pm_lbl := Label.new(); pm_lbl.text = Localization.t("ui_dialogue_trigger_mode", "mode:"); UiTheme.apply_label_kind(pm_lbl, "dim")
	pm_row.add_child(pm_lbl)
	_form_playmode_request = CheckBox.new()
	_form_playmode_request.text = Localization.t("ui_dialogue_trigger_mode_request", "request")
	_form_playmode_request.button_group = ButtonGroup.new()
	_form_playmode_request.set_pressed_no_signal(true)
	pm_row.add_child(_form_playmode_request)
	_form_playmode_play = CheckBox.new()
	_form_playmode_play.text = Localization.t("ui_dialogue_trigger_mode_play", "play")
	_form_playmode_play.button_group = _form_playmode_request.button_group
	pm_row.add_child(_form_playmode_play)

	# Conditions section
	var cond_lbl := Label.new(); cond_lbl.text = Localization.t("ui_dialogue_trigger_conditions", "Conditions (opt):"); UiTheme.apply_label_kind(cond_lbl, "dim")
	sb.add_child(cond_lbl)
	_form_conditions = VBoxContainer.new()
	sb.add_child(_form_conditions)
	_build_condition_widgets()

	# Form buttons
	var form_btns := HBoxContainer.new()
	sb.add_child(form_btns)
	var save_btn := Button.new(); UiTheme.apply_button_styling(save_btn); save_btn.text = Localization.t("ui_common_save", "Save")
	save_btn.pressed.connect(_on_form_save)
	form_btns.add_child(save_btn)
	var cancel_btn := Button.new(); UiTheme.apply_button_styling(cancel_btn); cancel_btn.text = Localization.t("ui_common_cancel", "Cancel")
	cancel_btn.pressed.connect(_on_form_cancel)
	form_btns.add_child(cancel_btn)


func _build_condition_widgets() -> void:
	var specs: Array[Dictionary] = [
		{"key": "wave_index",         "label_key": "ui_dialogue_trigger_cond_wave_index", "fallback": "wave_index (int)",       "type": "int"},
		{"key": "absolute_turn",      "label_key": "ui_dialogue_trigger_cond_absolute_turn", "fallback": "absolute_turn (int)",    "type": "int"},
		{"key": "cleared_in_turns_lt","label_key": "ui_dialogue_trigger_cond_cleared_turns", "fallback": "cleared_in_turns_lt (int)", "type": "int"},
		{"key": "chance",             "label_key": "ui_dialogue_trigger_cond_chance", "fallback": "chance 0-1 (float)",     "type": "float"},
		{"key": "once_per_run",       "label_key": "ui_dialogue_trigger_cond_once_run", "fallback": "once_per_run",           "type": "bool"},
		{"key": "once_per_session",   "label_key": "ui_dialogue_trigger_cond_once_session", "fallback": "once_per_session",       "type": "bool"},
	]
	for spec in specs:
		var row := HBoxContainer.new()
		_form_conditions.add_child(row)
		var chk := CheckBox.new(); chk.text = Localization.t(String(spec["label_key"]), String(spec["fallback"]))
		chk.toggled.connect(func(on: bool) -> void: _on_condition_toggled(spec["key"], on))
		row.add_child(chk)
		var ed: Control
		if spec["type"] == "bool":
			ed = CheckBox.new()
			(ed as CheckBox).text = ""
		else:
			ed = LineEdit.new()
			(ed as LineEdit).placeholder_text = spec["key"]
			(ed as LineEdit).custom_minimum_size = Vector2(50, 0)
		ed.visible = false
		row.add_child(ed)
		_cond_widgets[spec["key"]] = {"check": chk, "editor": ed}


# -- Helpers -----------------------------------------------------------------

func _populate_dialogue_picker(filter: String) -> void:
	_form_dialogue_option.clear()
	var ids: Array = []
	if Engine.has_singleton("DialogueDB") or get_node_or_null("/root/DialogueDB") != null:
		var db: Node = get_node_or_null("/root/DialogueDB")
		if db != null and db.has_method("get_all_ids"):
			ids = db.get_all_ids()
	if ids.is_empty():
		_form_dialogue_option.add_item(Localization.t("ui_dialogue_trigger_no_dialogues", "(no dialogues loaded)"))
		return
	var lf: String = filter.to_lower()
	for id_str in ids:
		var s: String = str(id_str)
		if lf == "" or lf in s.to_lower():
			_form_dialogue_option.add_item(s)


func _refresh_list() -> void:
	_list.clear()
	if _level == null:
		_count_label.text = Localization.t("ui_dialogue_trigger_count_zero", "0 triggers")
		return
	var triggers: Array = _level.dialogue_triggers
	_count_label.text = Localization.tf("ui_dialogue_trigger_count", [triggers.size()], "%d triggers")
	for d in triggers:
		var tid: String = str(d.get("id", "?"))
		var ev: String = str(d.get("event", "?"))
		var did: String = str(d.get("dialogue_id", "?"))
		_list.add_item("%s . %s . %s" % [tid, ev, did])


func _update_button_states() -> void:
	var has_sel: bool = _selected_idx >= 0 and _level != null 			and _selected_idx < _level.dialogue_triggers.size()
	_btn_edit.disabled = not has_sel
	_btn_dupe.disabled = not has_sel
	_btn_delete.disabled = not has_sel


func _open_form(data: Dictionary) -> void:
	_editing = true
	_form_container.visible = true
	_form_error_label.visible = false
	# Populate from data.
	_form_id.text = str(data.get("id", ""))
	var ev: String = str(data.get("event", "level_started"))
	var ev_idx: int = CURATED_EVENTS.find(ev)
	if ev_idx >= 0:
		_form_event_option.select(ev_idx)
		_form_event_custom.visible = false
	else:
		_form_event_option.select(CURATED_EVENTS.size())  # "Custom..."
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
	# Conditions
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
	_editing = false
	_form_container.visible = false
	_form_error_label.visible = false


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
		if w.editor is LineEdit:
			var raw: String = (w.editor as LineEdit).text.strip_edges()
			if key == "chance":
				c[key] = float(raw) if raw != "" else 1.0
			else:
				c[key] = int(raw) if raw != "" else 0
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
		return Localization.t("ui_dialogue_trigger_error_id_empty", "id must not be empty")
	if _level != null:
		for i in _level.dialogue_triggers.size():
			if i == _selected_idx and not _editing_new:
				continue  # same entry, editing -- skip self
			if str(_level.dialogue_triggers[i].get("id", "")) == tid:
				return Localization.tf("ui_dialogue_trigger_error_id_exists", [tid], "id '%s' already exists")
	if str(d.get("event", "")) == "":
		return Localization.t("ui_dialogue_trigger_error_event_empty", "event must not be empty")
	return ""


# -- Signals -----------------------------------------------------------------

func _on_collapse_toggled() -> void:
	_collapsed = not _collapsed
	_list.visible = not _collapsed
	if _btn_row != null:
		_btn_row.visible = not _collapsed
	_form_container.visible = false  # always close form on collapse
	_form_error_label.visible = false
	_collapse_btn.text = "v" if not _collapsed else ">"


func _on_list_item_selected(idx: int) -> void:
	_selected_idx = idx
	_update_button_states()
	if _level != null and idx < _level.dialogue_triggers.size():
		var tid: StringName = StringName(str(_level.dialogue_triggers[idx].get("id", "")))
		trigger_selected.emit(tid)


func _on_add_pressed() -> void:
	_selected_idx = -1
	_editing_new = true
	_list.deselect_all()
	_update_button_states()
	_open_form({})


func _on_edit_pressed() -> void:
	if _selected_idx < 0 or _level == null:
		return
	if _selected_idx >= _level.dialogue_triggers.size():
		return
	_editing_new = false
	_open_form(_level.dialogue_triggers[_selected_idx])


func _on_duplicate_pressed() -> void:
	if _selected_idx < 0 or _level == null:
		return
	if _selected_idx >= _level.dialogue_triggers.size():
		return
	var src: Dictionary = _level.dialogue_triggers[_selected_idx].duplicate(true)
	src["id"] = str(src.get("id", "")) + "_copy"
	_editing_new = true
	_selected_idx = -1
	_open_form(src)


func _on_delete_pressed() -> void:
	if _selected_idx < 0 or _level == null:
		return
	if _selected_idx >= _level.dialogue_triggers.size():
		return
	var tid: StringName = StringName(str(_level.dialogue_triggers[_selected_idx].get("id", "")))
	# Simple confirm via toast -- ConfirmModal is on controller; use a direct delete here.
	trigger_deleted.emit(tid)
	_selected_idx = -1
	_close_form()
	_refresh_list()
	_update_button_states()


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
		_form_error_label.text = err
		_form_error_label.visible = true
		return
	_form_error_label.visible = false
	if _editing_new:
		trigger_created.emit(d)
	else:
		var old_id: StringName = &""
		if _selected_idx >= 0 and _level != null and _selected_idx < _level.dialogue_triggers.size():
			old_id = StringName(str(_level.dialogue_triggers[_selected_idx].get("id", "")))
		trigger_updated.emit(old_id, d)
	_close_form()
	_refresh_list()
	_update_button_states()


func _on_form_cancel() -> void:
	_close_form()
