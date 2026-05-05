extends PanelContainer
## game_editor_level_row — one row in the Game Editor's level list.
## Hosts the controls for a single level entry: index label, map dropdown,
## display name, cutscene id, is_intro toggle, and reorder/remove buttons.
##
## Holds no canonical state. It edits the parent controller's GameData.levels
## entry directly via the `entry` Dictionary reference, then emits `changed`
## so the controller can persist (autosave + dirty flag).

signal removed
signal moved_up
signal moved_down
signal changed
signal intro_toggled(value: bool)
signal edit_requested

@onready var _index_label: Label = $HBox/IndexLabel
@onready var _map_option: OptionButton = $HBox/MapOption
@onready var _name_input: LineEdit = $HBox/NameInput
@onready var _cutscene_input: LineEdit = $HBox/CutsceneInput
@onready var _intro_check: CheckBox = $HBox/IntroCheck
@onready var _edit_btn: Button = $HBox/EditButton
@onready var _up_btn: Button = $HBox/UpButton
@onready var _down_btn: Button = $HBox/DownButton
@onready var _remove_btn: Button = $HBox/RemoveButton

# Reference to the parent controller's levels[i] dict. Mutated in place.
var entry: Dictionary = {}
# Cached list of available .json paths for the OptionButton.
var _map_paths: Array[String] = []


func _ready() -> void:
	UiTheme.apply_button_styling(_edit_btn)
	UiTheme.apply_button_styling(_up_btn)
	UiTheme.apply_button_styling(_down_btn)
	UiTheme.apply_button_styling(_remove_btn)

	_map_option.item_selected.connect(_on_map_selected)
	_name_input.text_changed.connect(_on_name_changed)
	_cutscene_input.text_changed.connect(_on_cutscene_changed)
	_intro_check.toggled.connect(_on_intro_toggled)
	_edit_btn.pressed.connect(func(): edit_requested.emit())
	_up_btn.pressed.connect(func(): moved_up.emit())
	_down_btn.pressed.connect(func(): moved_down.emit())
	_remove_btn.pressed.connect(func(): removed.emit())


## Called by parent controller. Populates the OptionButton with available
## map files and binds this row to a specific levels[i] dict.
func bind(map_paths: Array[String], level_entry: Dictionary, index: int) -> void:
	_map_paths = map_paths
	entry = level_entry
	_index_label.text = "%d." % (index + 1)

	_map_option.clear()
	# Always include a placeholder entry first so empty map_path renders.
	_map_option.add_item(Localization.t("ui_game_editor_select_map", "(select map...)"), -1)
	var current_path: String = String(entry.get("map_path", ""))
	var matched: int = -1
	for i: int in range(_map_paths.size()):
		var p: String = _map_paths[i]
		_map_option.add_item(p.get_file(), i)
		if p == current_path:
			matched = i
	if matched >= 0:
		# OptionButton selects by index in its own list, not by id.
		_map_option.select(matched + 1)
	else:
		_map_option.select(0)
		if current_path != "":
			# Map file referenced doesn't exist locally any more — show a
			# warning entry at the end so the user can see what's missing.
			_map_option.add_item(Localization.tf("ui_game_editor_missing_map", [current_path.get_file()], "(missing: %s)"), -2)
			_map_option.select(_map_option.item_count - 1)
			_map_option.set_item_disabled(_map_option.item_count - 1, true)

	_name_input.text = String(entry.get("display_name", ""))
	_cutscene_input.text = String(entry.get("cutscene_id", ""))
	# Bypass the toggled signal during programmatic init so we don't fan out
	# spurious intro_toggled events.
	_intro_check.set_pressed_no_signal(bool(entry.get("is_intro", false)))


# Called by parent when this row's index changes (e.g. after reorder/remove).
func update_index(new_index: int) -> void:
	_index_label.text = "%d." % (new_index + 1)


# ── Signal handlers ─────────────────────────────────────────────────────────

func _on_map_selected(_idx: int) -> void:
	var id: int = _map_option.get_selected_id()
	if id == -1:
		entry["map_path"] = ""
	elif id == -2:
		# Selecting the disabled "missing" entry shouldn't be possible; ignore.
		pass
	else:
		entry["map_path"] = _map_paths[id]
	changed.emit()


func _on_name_changed(new_text: String) -> void:
	entry["display_name"] = new_text
	changed.emit()


func _on_cutscene_changed(new_text: String) -> void:
	entry["cutscene_id"] = new_text
	changed.emit()


func _on_intro_toggled(pressed: bool) -> void:
	entry["is_intro"] = pressed
	intro_toggled.emit(pressed)
	# changed.emit() is fired by the controller after it dedups other rows,
	# not from here, so we don't double-trigger autosave.
