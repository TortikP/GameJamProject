extends Control
## DialoguePreview — debug scene for testing dialogue lines.
## Run standalone from scenes/dev/dialogue_preview.tscn.
## Does NOT depend on arena/battle systems.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@onready var _search : LineEdit  = $VBoxContainer/SearchBar
@onready var _list   : ItemList  = $VBoxContainer/SplitContainer/ItemList
@onready var _play   : Button    = $VBoxContainer/SplitContainer/RightPanel/PlayButton
@onready var _info   : Label     = $VBoxContainer/SplitContainer/RightPanel/InfoLabel

var _all_ids: Array[StringName] = []


func _ready() -> void:
	_all_ids = []
	for id in DialogueDB._lines.keys():
		_all_ids.append(id)
	_all_ids.sort_custom(func(a, b): return str(a) < str(b))
	_refresh_list("")

	_search.text_changed.connect(_on_search_changed)
	_list.item_selected.connect(_on_item_selected)
	_play.pressed.connect(_on_play_pressed)
	_play.disabled = true


func _refresh_list(filter: String) -> void:
	_list.clear()
	for id in _all_ids:
		if filter == "" or str(id).contains(filter):
			_list.add_item(str(id))


func _on_search_changed(text: String) -> void:
	_refresh_list(text)
	_play.disabled = true
	_info.text = ""


func _on_item_selected(index: int) -> void:
	var id := StringName(_list.get_item_text(index))
	var line = DialogueDB.get_line(id)
	if line == null:
		_info.text = "?"
		return
	_info.text = "speaker: %s  |  priority: %d  |  tags: %s" % [
		line.speaker, line.priority, str(line.tags)
	]
	_play.disabled = false


func _on_play_pressed() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return
	var id := StringName(_list.get_item_text(sel[0]))
	# force=true so preview works even if something is playing
	DialogueManager.play(id, true)
