extends Control
## DialoguePreview — debug scene. Left: list. Right: chain info. Bottom: play.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@onready var _search     : LineEdit      = $VBox/TopBar/SearchBar
@onready var _tag_filter : OptionButton  = $VBox/TopBar/TagFilter
@onready var _list       : ItemList      = $VBox/Main/List
@onready var _info       : RichTextLabel = $VBox/Main/Right/Info
@onready var _play_btn   : Button        = $VBox/Main/Right/Buttons/PlayBtn
@onready var _request_btn: Button        = $VBox/Main/Right/Buttons/RequestBtn
@onready var _tag_lbl    : Label         = $VBox/Main/Right/Buttons/TagLabel
@onready var _close_btn  : Button        = $VBox/TopBar/CloseBtn

var _all_ids: Array = []
var _selected_id: StringName = &""


func _ready() -> void:
	for id in DialogueDB.get_all_ids():
		_all_ids.append(id)
	_all_ids.sort()

	_build_tag_filter()
	_refresh_list()

	_search.text_changed.connect(_on_search_changed)
	_tag_filter.item_selected.connect(_on_tag_changed)
	_list.item_selected.connect(_on_item_selected)
	_play_btn.pressed.connect(_on_play)
	_request_btn.pressed.connect(_on_request)
	_close_btn.pressed.connect(func(): get_parent().visible = false)
	_play_btn.disabled = true
	_request_btn.disabled = true


func _build_tag_filter() -> void:
	var tags: Dictionary = {}
	for id in _all_ids:
		var line = DialogueDB.get_line(id)
		if line == null:
			continue
		for t in line.tags:
			tags[str(t)] = true
	_tag_filter.add_item("(все теги)", 0)
	var sorted_tags := tags.keys()
	sorted_tags.sort()
	for t in sorted_tags:
		_tag_filter.add_item(t)


func _on_search_changed(_text: String) -> void:
	_refresh_list()


func _on_tag_changed(_idx: int) -> void:
	_refresh_list()


func _refresh_list() -> void:
	var filter: String = _search.text.strip_edges().to_lower()
	var tag_idx: int = _tag_filter.selected
	var tag_selected: String = "" if tag_idx == 0 else _tag_filter.get_item_text(tag_idx)

	_list.clear()
	for id in _all_ids:
		var sid := str(id)
		if filter != "" and not sid.to_lower().contains(filter):
			continue
		if tag_selected != "":
			var line = DialogueDB.get_line(id)
			if line == null:
				continue
			var has_tag := false
			for t in line.tags:
				if str(t) == tag_selected:
					has_tag = true
					break
			if not has_tag:
				continue
		_list.add_item(sid)

	_play_btn.disabled = true
	_request_btn.disabled = true
	_info.text = ""
	_tag_lbl.text = ""
	_selected_id = &""


func _on_item_selected(index: int) -> void:
	_selected_id = StringName(_list.get_item_text(index))
	var line = DialogueDB.get_line(_selected_id)
	if line == null:
		_info.text = "[color=#ff4444]not found[/color]"
		return

	_play_btn.disabled = false

	var b := ""
	b += "[b]" + str(line.id) + "[/b]   speaker: " + str(line.speaker) + "\n"
	b += "priority: " + str(line.priority) + "   "
	if line.once_per_session:
		b += "[color=#ffcc00]once_per_session[/color]   "
	if line.once_per_run:
		b += "[color=#ffcc00]once_per_run[/color]   "
	b += "\n"

	if line.tags.size() > 0:
		var tag_strs: Array = []
		for t in line.tags:
			tag_strs.append(str(t))
		b += "[color=#88ffcc]tags:[/color] " + ", ".join(PackedStringArray(tag_strs)) + "\n"
		_request_btn.disabled = false
		_tag_lbl.text = "-> request(" + str(line.tags[0]) + ")"
	else:
		_request_btn.disabled = true
		_tag_lbl.text = ""

	var cond: Dictionary = line.conditions
	if cond.get("min_run", 0) != 0 or cond.get("max_run", 999) != 999:
		b += "[color=#888888]conditions: run " + str(cond.get("min_run", 0)) + "-" + str(cond.get("max_run", 999)) + "[/color]\n"

	b += "\n[color=#cccccc]" + line.text + "[/color]\n"
	b += "\n[color=#888888]-- chain --[/color]\n"
	b += _build_chain(line.id, {}, 0)

	_info.bbcode_enabled = true
	_info.text = b


func _build_chain(id: StringName, visited: Dictionary, depth: int) -> String:
	if depth > 10:
		return "  ...\n"
	var indent := "  ".repeat(depth)
	if visited.has(id):
		return indent + "[color=#ff4444](cycle: " + str(id) + ")[/color]\n"

	var line = DialogueDB.get_line(id)
	if line == null:
		return indent + "[color=#ff4444](missing: " + str(id) + ")[/color]\n"

	var vis2 := visited.duplicate()
	vis2[id] = true

	var short_text: String = line.text.left(50) + ("..." if line.text.length() > 50 else "")
	var out := indent + "[color=#88ffcc]" + str(id) + "[/color] (" + str(line.speaker) + ") " + short_text + "\n"

	if line.choices.size() > 0:
		for ch in line.choices:
			var lbl: String = ch.get("label", "?")
			var nxt: StringName = ch.get("next", &"")
			if nxt == &"":
				out += indent + "  [color=#ffcc00]> " + lbl + "[/color] -> (end)\n"
			else:
				out += indent + "  [color=#ffcc00]> " + lbl + "[/color] ->\n"
				out += _build_chain(nxt, vis2, depth + 2)
	elif line.next != &"":
		out += _build_chain(line.next, vis2, depth + 1)
	else:
		out += indent + "  (end)\n"

	return out


func _on_play() -> void:
	if _selected_id == &"":
		return
	DialogueManager.play(_selected_id, true)


func _on_request() -> void:
	if _selected_id == &"":
		return
	var line = DialogueDB.get_line(_selected_id)
	if line == null or line.tags.is_empty():
		return
	DialogueManager.request(line.tags[0], {}, true)
