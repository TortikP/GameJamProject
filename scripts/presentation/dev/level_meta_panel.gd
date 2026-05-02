extends PanelContainer
## LevelMetaPanel — top-right panel: level name input + 4 action buttons
## (Save / Load / Playtest / Exit).
##
## Load opens a Godot FileDialog rooted at res://data/maps/. The picked path
## comes back through the load_requested signal. Save / Playtest / Exit are
## just notify-the-controller signals — the controller handles validation,
## sanitization, autosave, scene-change.
##
## Signals (consumed by MapEditorController):
##   save_requested()
##   load_requested(path: String)
##   playtest_requested()
##   exit_requested()
##   name_changed(new_name: String)

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")
const DraggablePanel = preload("res://scripts/presentation/dev/draggable_panel.gd")

const MAPS_DIR: String = "res://data/maps/"

signal save_requested()
signal load_requested(path: String)
signal playtest_requested()
signal exit_requested()
signal name_changed(new_name: String)

var _controller: Node = null

var _name_edit: LineEdit
var _dirty_marker: Label
var _save_btn: Button
var _load_btn: Button
var _playtest_btn: Button
var _exit_btn: Button
var _file_dialog: FileDialog


func _ready() -> void:
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	_build_ui()


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


func _apply_theme() -> void:
	add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var header := Label.new()
	header.text = Localization.t("ui_level_meta_title", "Level")
	UiTheme.apply_label_kind(header, "header")
	vbox.add_child(header)
	_install_drag(header)

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
	_save_btn = _make_btn(Localization.t("ui_common_save", "Save"), _on_save)
	_load_btn = _make_btn(Localization.t("ui_common_load", "Load"), _on_load)
	_playtest_btn = _make_btn(Localization.t("ui_level_meta_playtest", "Playtest"), _on_playtest)
	_exit_btn = _make_btn(Localization.t("ui_common_exit", "Exit"), _on_exit)
	btn_row.add_child(_save_btn)
	btn_row.add_child(_load_btn)
	btn_row.add_child(_playtest_btn)
	btn_row.add_child(_exit_btn)
	vbox.add_child(btn_row)

	# File dialog (hidden until used)
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


func _install_drag(handle: Control) -> void:
	var dragger := DraggablePanel.new()
	add_child(dragger)
	dragger.setup(self, handle)
