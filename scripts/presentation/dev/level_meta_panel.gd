extends BasePanel
## LevelMetaPanel — top-right panel: level name input + 5 action buttons
## (New / Save / Load / Playtest / Exit).
##
## Load opens a Godot FileDialog rooted at res://data/maps/. The picked path
## comes back through the load_requested signal. New / Save / Playtest /
## Exit are just notify-the-controller signals — the controller handles
## confirm modal, validation, sanitization, autosave, scene-change.
##
## Spec 057: migrated from extends PanelContainer + DraggablePanel mixin to
## extends BasePanel. Body content lives in get_body_container(); header,
## drag, resize, collapse, lock, persistence are handled by BasePanel.
##
## Signals (consumed by MapEditorController):
##   save_requested()
##   load_requested(path: String)
##   playtest_requested()
##   exit_requested()
##   name_changed(new_name: String)

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")

const MAPS_DIR: String = "res://data/maps/"

signal save_requested()
signal load_requested(path: String)
signal playtest_requested()
signal exit_requested()
signal new_requested()
signal name_changed(new_name: String)

var _controller: Node = null

var _name_edit: LineEdit
var _dirty_marker: Label
var _new_btn: Button
var _save_btn: Button
var _load_btn: Button
var _playtest_btn: Button
var _exit_btn: Button
var _file_dialog: FileDialog


func _ready() -> void:
	# In Godot 4, parent _ready() is NOT auto-called when subclass overrides.
	# super._ready() invokes BasePanel: resolve nodes, apply theme, install
	# drag/resize/collapse/lock/persistence handlers. Then build our body.
	super._ready()
	_build_body()


func setup(controller: Node) -> void:
	_controller = controller


## Called by the controller after Load applied a level — reflects the loaded
## name in the input without firing name_changed back.
func set_level_name(new_name: String) -> void:
	if _name_edit != null:
		_name_edit.text = new_name


## Toggle the unsaved-changes asterisk next to the name field.
func set_dirty(dirty: bool) -> void:
	if _dirty_marker != null:
		_dirty_marker.visible = dirty


func _build_body() -> void:
	var body := get_body_container()
	if body == null:
		push_error("[LevelMetaPanel] body container not available")
		return
	var vbox := VBoxContainer.new()
	vbox.name = "ContentVBox"
	vbox.add_theme_constant_override("separation", 6)
	body.add_child(vbox)

	# Name input
	var name_row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = Localization.t("ui_level_meta_name_label", "Name:")
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.text = Localization.t("ui_level_meta_untitled", "Untitled")
	_name_edit.custom_minimum_size = Vector2(180, 0)
	_name_edit.text_changed.connect(_on_name_changed)
	name_row.add_child(_name_edit)
	# Dirty marker (T-12) — separate label so we don't mangle the LineEdit
	# text on every edit / undo / save event.
	_dirty_marker = Label.new()
	_dirty_marker.text = "*"
	_dirty_marker.visible = false
	UiTheme.apply_label_kind(_dirty_marker, "header")
	_dirty_marker.modulate = UiTheme.SEM_DEBUFF  # warm orange — "attention, unsaved"
	name_row.add_child(_dirty_marker)
	vbox.add_child(name_row)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	_new_btn = _make_btn(Localization.t("ui_level_meta_new", "New"), _on_new)
	_save_btn = _make_btn(Localization.t("ui_common_save", "Save"), _on_save)
	_load_btn = _make_btn(Localization.t("ui_common_load", "Load"), _on_load)
	_playtest_btn = _make_btn(Localization.t("ui_level_meta_playtest", "Playtest"), _on_playtest)
	_exit_btn = _make_btn(Localization.t("ui_common_exit", "Exit"), _on_exit)
	btn_row.add_child(_new_btn)
	btn_row.add_child(_save_btn)
	btn_row.add_child(_load_btn)
	btn_row.add_child(_playtest_btn)
	btn_row.add_child(_exit_btn)
	vbox.add_child(btn_row)

	# File dialog (hidden until used). Stays parented to self (the panel root)
	# rather than the body container — it's a popup, not part of the body
	# layout flow.
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.current_dir = MAPS_DIR
	_file_dialog.filters = PackedStringArray(["*.json ; Map JSON files"])
	_file_dialog.use_native_dialog = false
	_file_dialog.size = Vector2i(720, 480)
	_file_dialog.file_selected.connect(_on_file_picked)
	add_child(_file_dialog)


func _make_btn(text: String, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(on_pressed)
	UiTheme.apply_button_styling(btn)
	return btn


func _on_name_changed(new_name: String) -> void:
	name_changed.emit(new_name)


func _on_save() -> void:
	save_requested.emit()


func _on_new() -> void:
	new_requested.emit()


func _on_load() -> void:
	# Show file dialog rooted at maps dir. Selection routes through file_selected.
	_file_dialog.current_dir = MAPS_DIR
	_file_dialog.popup_centered()


func _on_file_picked(path: String) -> void:
	load_requested.emit(path)


func _on_playtest() -> void:
	playtest_requested.emit()


func _on_exit() -> void:
	exit_requested.emit()
