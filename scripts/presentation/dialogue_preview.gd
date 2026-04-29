extends Control
## DialoguePreview — enhanced debug scene.
## Left: filterable list. Right: full line info + chain map. Bottom: play controls.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@onready var _search     : LineEdit      = $VBox/TopBar/SearchBar
@onready var _tag_filter : OptionButton  = $VBox/TopBar/TagFilter
@onready var _list       : ItemList      = $VBox/Main/List
@onready var _info       : RichTextLabel = $VBox/Main/Right/Info
@onready var _play_btn   : Button        = $VBox/Main/Right/Buttons/PlayBtn
@onready var _request_btn: Button        = $VBox/Main/Right/Buttons/RequestBtn
@onready var _tag_lbl    : Label         = $VBox/Main/Right/Buttons/TagLabel

var _all_ids: Array[StringName] = []
var _selected_id: StringName = &""


func _ready() -> void:
	_all_ids = []
	for id in DialogueDB._lines.keys():
		_all_ids.append(id)
	_all_ids.sort_custom(func(a, b): return str(a) < str(b))

	_build_tag_filter()
	_refresh_list()

	_search.text_changed.connect(func(_t): _refresh_list())
	_tag_filter.item_selected.connect(func(_i): _refresh_list())
	_list.item_selected.connect(_on_item_selected)
	_play_btn.pressed.connect(_on_play)
	_request_btn.pressed.connect(_on_request)
	_play_btn.disabled = true
	_request_btn.disabled = true
	_tag_lbl.text = ""


func _build_tag_filter() -> void:
	var tags: Dictionary = {}
	for id in _all_ids:
		var line = DialogueDB.get_line(id)
		if line == null: continue
		for t in line.tags:
			tags[str(t)] = true
	_tag_filter.add_item("(все теги)", 0)
	var sorted_tags := tags.keys()
	sorted_tags.sort()
	for t in sorted_tags:
		_tag_filter.add_item(t)


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
			if line == null or tag_selected not in line.tags.map(func(t): return str(t)):
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
	_tag_lbl.text = ""

	# Build info panel
	var b := ""
	b += "[b]%s[/b]  [color=#888888]speaker:[/color] %s\n" % [line.id, line.speaker]
	b += "[color=#888888]priority:[/color] %d  " % line.priority
	if line.once_per_session:
		b += "[color=#ffcc00]once_per_session[/color]  "
	if line.once_per_run:
		b += "[color=#ffcc00]once_per_run[/color]  "
	b += "\n"

	if line.tags.size() > 0:
		var tag_strs := line.tags.map(func(t): return str(t))
		b += "[color=#88ffcc]tags:[/color] %s\n" % ", ".join(tag_strs)
		# Enable request if has tags
		_request_btn.disabled = false
		_tag_lbl.text = "→ request('%s')" % line.tags[0]

	var cond: Dictionary = line.conditions
	if cond.get("min_run", 0) != 0 or cond.get("max_run", 999) != 999:
		b += "[color=#888888]conditions:[/color] run %d–%d\n" % [cond.get("min_run",0), cond.get("max_run",999)]

	b += "\n[color=#cccccc]\"%s\"[/color]\n" % line.text

	# Chain map
	b += "\n[color=#888888]── chain ──[/color]\n"
	b += _build_chain(line.id, {}, 0)

	_info.bbcode_enabled = true
	_info.text = b


func _build_chain(id: StringName, visited: Dictionary, depth: int) -> String:
	if depth > 8:
		return "  …\n"
	var indent := "  ".repeat(depth)
	if visited.has(id):
		return "%s[color=#ff4444]↺ %s (cycle)[/color]\n" % [indent, id]

	var line = DialogueDB.get_line(id)
	if line == null:
		return "%s[color=#ff4444]✗ %s (missing)[/color]\n" % [indent, id]

	visited = visited.duplicate()
	visited[id] = true

	var out := ""
	var short_text := line.text.left(40) + ("…" if line.text.length() > 40 else "")
	out += "%s[color=#88ffcc]%s[/color] [color=#888888](%s)[/color] %s\n" % [
		indent, id, line.speaker, short_text
	]

	if line.choices.size() > 0:
		for ch in line.choices:
			var label: String = ch.get("label", "?")
			var next: StringName = ch.get("next", &"")
			if next == &"":
				out += "%s  [color=#ffcc00]▸ \"%s\"[/color] → [color=#888888](end)[/color]\n" % [indent, label]
			else:
				out += "%s  [color=#ffcc00]▸ \"%s\"[/color] →\n" % [indent, label]
				out += _build_chain(next, visited, depth + 2)
	elif line.next != &"":
		out += _build_chain(line.next, visited, depth + 1)
	else:
		out += "%s  [color=#888888](end)[/color]\n" % indent

	return out


func _on_play() -> void:
	if _selected_id == &"": return
	DialogueManager.play(_selected_id, true)


func _on_request() -> void:
	if _selected_id == &"": return
	var line = DialogueDB.get_line(_selected_id)
	if line == null or line.tags.is_empty(): return
	DialogueManager.request(line.tags[0], {}, true)
