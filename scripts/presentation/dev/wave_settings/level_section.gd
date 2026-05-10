class_name WaveSettingsLevelSection
extends VBoxContainer

## Level-scope tab of WaveSettingsPanel. Two things:
##   1. Read-only echo of the level name (from LevelMetaPanel).
##   2. Read-only preview of dialogue triggers — list + detail of selection.
##
## CRUD was removed in F-061-IMPL-7 — Никита authors triggers in tables
## (his preferred workflow) and the editor only needs to show what's
## already attached. To add/edit a trigger, hand-edit the map JSON or use
## an external authoring tool. No signals leave this section.
##
## Triggers are level-scoped (one trigger may fire on any wave, filtered
## via conditions.wave_index). The wave switcher above doesn't filter
## the list — designers see the full set; the wave-scoped ones display
## their `wave_index` inline as a hint.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")

var _level: LevelData = null

var _name_value: Label
var _count_label: Label
var _list: ItemList
var _detail_id: Label
var _detail_event: Label
var _detail_dialogue: Label
var _detail_playmode: Label
var _detail_conditions: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_build()


func bind_level(level: LevelData) -> void:
	_level = level
	_refresh()


# Wave switcher doesn't filter the list — but the API is preserved so
# the host panel can call it without a special-case.
func set_active_wave(_idx: int) -> void:
	pass


# Public: select a trigger by id (e.g. when wave_timeline marker is clicked).
# Read-only — just highlights the row and populates the detail.
func select_trigger(tid: StringName) -> void:
	if _level == null or _list == null:
		return
	for i in _level.dialogue_triggers.size():
		if StringName(str(_level.dialogue_triggers[i].get("id", ""))) == tid:
			_list.select(i)
			_on_list_item_selected(i)
			return


# ── Build ───────────────────────────────────────────────────────────────────

func _build() -> void:
	# Row 1: level name (read-only echo).
	var name_row := HBoxContainer.new()
	add_child(name_row)
	var name_lbl := _make_label("ui_wavesettings_level_name", "name:")
	name_lbl.custom_minimum_size = Vector2(120, 0)
	name_row.add_child(name_lbl)
	_name_value = Label.new()
	_name_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.apply_label_kind(_name_value, "default")
	name_row.add_child(_name_value)

	# Row 2: triggers header with count.
	var hdr_row := HBoxContainer.new()
	add_child(hdr_row)
	var hdr_lbl := _make_label("ui_wavesettings_dialogue_triggers_header", "Triggers")
	hdr_row.add_child(hdr_lbl)
	_count_label = Label.new()
	UiTheme.apply_label_kind(_count_label, "dim")
	hdr_row.add_child(_count_label)

	# List of triggers (read-only).
	_list = ItemList.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 120)
	_list.item_selected.connect(_on_list_item_selected)
	add_child(_list)

	# Detail block (read-only labels for selected trigger fields).
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 2)
	add_child(detail_box)
	_detail_id = _make_detail_label(detail_box)
	_detail_event = _make_detail_label(detail_box)
	_detail_dialogue = _make_detail_label(detail_box)
	_detail_playmode = _make_detail_label(detail_box)
	_detail_conditions = _make_detail_label(detail_box)


# ── Refresh ─────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if _level == null:
		return
	if _name_value != null:
		_name_value.text = _level.name
	if _list != null:
		_list.clear()
		for t in _level.dialogue_triggers:
			_list.add_item(_summarize_trigger(t))
	if _count_label != null:
		_count_label.text = "(%d)" % _level.dialogue_triggers.size()
	_clear_detail()


func _summarize_trigger(t: Dictionary) -> String:
	# One-line summary for ItemList row. Format:
	#   "id  ·  event  →  dialogue_id  [wave N]"
	# wave_index suffix only when condition narrows it.
	var id_s: String = String(t.get("id", "?"))
	var event_s: String = String(t.get("event", "?"))
	var dlg_s: String = String(t.get("dialogue_id", "?"))
	var conds: Dictionary = t.get("conditions", {})
	var wave_hint: String = ""
	if conds.has("wave_index"):
		wave_hint = "  [wave %s]" % str(conds["wave_index"])
	return "%s  ·  %s  →  %s%s" % [id_s, event_s, dlg_s, wave_hint]


func _on_list_item_selected(idx: int) -> void:
	if _level == null or idx < 0 or idx >= _level.dialogue_triggers.size():
		_clear_detail()
		return
	var t: Dictionary = _level.dialogue_triggers[idx]
	_detail_id.text = "id: %s" % str(t.get("id", ""))
	_detail_event.text = "event: %s" % str(t.get("event", ""))
	_detail_dialogue.text = "dialogue_id: %s" % str(t.get("dialogue_id", ""))
	_detail_playmode.text = "play_mode: %s" % str(t.get("play_mode", ""))
	var conds: Dictionary = t.get("conditions", {})
	if conds.is_empty():
		_detail_conditions.text = "conditions: —"
	else:
		_detail_conditions.text = "conditions: %s" % JSON.stringify(conds)


func _clear_detail() -> void:
	for lbl in [_detail_id, _detail_event, _detail_dialogue, _detail_playmode, _detail_conditions]:
		if lbl != null:
			lbl.text = ""


# ── Helpers ─────────────────────────────────────────────────────────────────

func _make_label(loc_key: String, fallback: String) -> Label:
	var lbl := Label.new()
	lbl.text = Localization.t(loc_key, fallback)
	UiTheme.apply_label_kind(lbl, "dim")
	return lbl


func _make_detail_label(parent: Node) -> Label:
	var lbl := Label.new()
	lbl.text = ""
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.apply_label_kind(lbl, "default")
	parent.add_child(lbl)
	return lbl
