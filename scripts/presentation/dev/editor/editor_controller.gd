extends Node2D

## Level Editor Controller — orchestrates the editor's MVC.
## Model: LevelData + LayersModel. View: LayersPanel + LevelMetaPanel +
## ToastLayer + HexGrid + Objects/SpawnersOverlay + help/confirm modals.
## Input: InputDispatcher.
##
## Hard cap: 300 lines (AC33). Data-mutation primitives are extracted
## to LevelMutations to fit cap; see plan §Φ-6 R1.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_EDITOR_SCENE := "res://scenes/dev/game_editor.tscn"
const GODMODE_SCENE := "res://scenes/dev/godmode.tscn"

@export var hex_grid_path: NodePath
@export var layers_panel_path: NodePath
@export var level_meta_panel_path: NodePath
@export var toast_layer_path: NodePath
@export var objects_overlay_path: NodePath
@export var spawners_overlay_path: NodePath
@export var help_modal_path: NodePath
@export var confirm_modal_path: NodePath

var _grid: HexGrid
var _layers_panel: LayersPanel
var _meta_panel: Node              # extends BasePanel (level_meta_panel.gd)
var _toast_layer: Node             # toast_layer.tscn root
var _objects_overlay: Node         # weak typing — overlay scripts not class_named
var _spawners_overlay: Node
var _help_modal: Node
var _confirm_modal: Node

var _level: LevelData
var _layers: LayersModel
var _dispatcher: InputDispatcher
var _io: EditorIO


func _ready() -> void:
	_resolve_nodes()
	if _grid != null:
		_grid.initialize()
	_level = LevelData.new()
	_layers = LayersModel.new()
	_layers.set_selection(LayersModel.LAYER_HEXES, _default_hex_selection())
	_dispatcher = InputDispatcher.new(self, _grid, _layers)
	_io = EditorIO.new()
	add_child(_io)
	_io.setup(_grid, _objects_overlay, _spawners_overlay)
	_wire_panels()
	_level = await EditorStartup.run(_io, _level, _meta_panel, _confirm_modal, get_tree())


func _unhandled_input(event: InputEvent) -> void:
	if _dispatcher == null:
		return
	if _dispatcher.handle(event):
		get_viewport().set_input_as_handled()


# Public API for InputDispatcher

func paint_floor(coord: Vector2i, source_id: int, atlas_coord: Vector2i) -> void:
	if _grid == null or _grid.tile_map_layer == null:
		return
	_grid.tile_map_layer.set_cell(coord, source_id, atlas_coord)
	LevelMutations.set_or_update_floor_cell(_level.floor_cells, coord, source_id, atlas_coord)
	_io.enqueue_autosave(_level)


func erase_floor(coord: Vector2i) -> bool:
	if _grid == null or _grid.tile_map_layer == null:
		return false
	if _grid.tile_map_layer.get_cell_source_id(coord) < 0:
		return false  # Empty hex — guard prevents stray flash.
	_grid.tile_map_layer.set_cell(coord, -1)
	LevelMutations.remove_at_coord(_level.floor_cells, coord)
	_io.enqueue_autosave(_level)
	return true


func paint_spawner(coord: Vector2i, kind: StringName, ref: StringName) -> void:
	# Player uniqueness: drop ALL existing players regardless of coord;
	# enemies replace any existing spawner at the same coord.
	if kind == &"player":
		for i in range(_level.spawners.size() - 1, -1, -1):
			if _level.spawners[i]["kind"] == &"player":
				_level.spawners.remove_at(i)
	else:
		LevelMutations.remove_at_coord(_level.spawners, coord)
	_level.spawners.append({
		"coord": coord, "kind": kind, "ref": ref,
		"timer": LevelData.DEFAULT_SPAWNER_TIMER,
	})
	LevelMutations.refresh_overlay(_spawners_overlay, _level.spawners)
	_io.enqueue_autosave(_level)


func erase_spawner(coord: Vector2i) -> bool:
	var changed := LevelMutations.remove_at_coord(_level.spawners, coord)
	if changed:
		LevelMutations.refresh_overlay(_spawners_overlay, _level.spawners)
		_io.enqueue_autosave(_level)
	return changed


func paint_object(coord: Vector2i, object_id: StringName) -> void:
	LevelMutations.remove_at_coord(_level.objects, coord)
	_level.objects.append({"coord": coord, "object_id": object_id})
	LevelMutations.refresh_overlay(_objects_overlay, _level.objects)
	_io.enqueue_autosave(_level)


func erase_object(coord: Vector2i) -> bool:
	var changed := LevelMutations.remove_at_coord(_level.objects, coord)
	if changed:
		LevelMutations.refresh_overlay(_objects_overlay, _level.objects)
		_io.enqueue_autosave(_level)
	return changed


## Cross-layer wipe — Q-060-6: no undo, no confirmation.
func cascade_at(coord: Vector2i) -> bool:
	var floor_changed := erase_floor(coord)
	var obj_changed := LevelMutations.remove_at_coord(_level.objects, coord)
	var sp_changed := LevelMutations.remove_at_coord(_level.spawners, coord)
	if obj_changed:
		LevelMutations.refresh_overlay(_objects_overlay, _level.objects)
	if sp_changed:
		LevelMutations.refresh_overlay(_spawners_overlay, _level.spawners)
	if floor_changed or obj_changed or sp_changed:
		_io.enqueue_autosave(_level)
		return true
	return false


## Q/W/E/Tab UI sync. set_active_tab does NOT emit (TabbedBasePanel
## policy: signal is for user click only, no feedback loop).
func notify_active_layer_changed(layer_id: StringName) -> void:
	if _layers_panel != null:
		_layers_panel.set_active_tab(layer_id)


func quick_select_in_active_palette(n: int) -> void:
	if _layers_panel == null:
		return
	var palette := _layers_panel.get_palette_for_layer(_layers.active_layer)
	if palette != null and palette.has_method("quick_select"):
		palette.quick_select(n)


func show_help() -> void:
	if _help_modal != null:
		_help_modal.visible = true


func is_text_focused() -> bool:
	var owner_ctl: Control = get_viewport().gui_get_focus_owner()
	if owner_ctl == null:
		return false
	return owner_ctl is LineEdit or owner_ctl is TextEdit or owner_ctl is SpinBox


# Wiring

func _resolve_nodes() -> void:
	_grid = get_node_or_null(hex_grid_path) as HexGrid
	_layers_panel = get_node_or_null(layers_panel_path) as LayersPanel
	_meta_panel = get_node_or_null(level_meta_panel_path)
	_toast_layer = get_node_or_null(toast_layer_path)
	_objects_overlay = get_node_or_null(objects_overlay_path)
	_spawners_overlay = get_node_or_null(spawners_overlay_path)
	_help_modal = get_node_or_null(help_modal_path)
	_confirm_modal = get_node_or_null(confirm_modal_path)
	for pair in [["hex_grid_path", _grid], ["layers_panel_path", _layers_panel],
			["level_meta_panel_path", _meta_panel]]:
		if pair[1] == null:
			GameLogger.error("EditorController", str(pair[0]) + " did not resolve")


func _wire_panels() -> void:
	if _layers_panel != null:
		_layers_panel.layer_selection_changed.connect(_on_layer_selection_changed)
		_layers_panel.active_tab_changed.connect(_on_active_tab_changed)
	if _meta_panel == null:
		return
	var meta_signals: Array = [
		[&"save_requested", _on_save], [&"load_requested", _on_load],
		[&"exit_requested", _on_exit], [&"playtest_requested", _on_playtest],
		[&"name_changed", _on_name_changed],
	]
	for entry in meta_signals:
		if _meta_panel.has_signal(entry[0]):
			_meta_panel.connect(entry[0], entry[1])
	if _meta_panel.has_method("setup"):
		_meta_panel.setup(self)
	if _meta_panel.has_method("set_level_name"):
		_meta_panel.set_level_name(_level.name)


# Slot handlers

func _on_layer_selection_changed(layer_id: StringName, value: Variant) -> void:
	_layers.set_selection(layer_id, value)
	# Clicking any palette button also makes that layer active. Avoids
	# the "I clicked tree in detached objects panel but I'm still on
	# hexes layer so paint goes to hexes" trap. set_active_tab no-ops
	# when target is detached (panel_tab_bar guard) so this is safe
	# regardless of detach state.
	if _layers.active_layer != layer_id:
		_layers.active_layer = layer_id
		notify_active_layer_changed(layer_id)


func _on_active_tab_changed(tab_id: StringName) -> void:
	_layers.active_layer = tab_id


func _on_save() -> void:
	if _io.save(_level):
		_toast("Saved: " + EditorIO.MAPS_DIR + _level.name + ".json", &"success")
	else:
		_toast("Save FAILED — see Output", &"error")


func _on_load(path: String) -> void:
	var loaded := _io.load_from(path)
	if loaded == null:
		_toast("Load FAILED — see Output", &"error")
		return
	_level = loaded
	if _meta_panel != null and _meta_panel.has_method("set_level_name"):
		_meta_panel.set_level_name(_level.name)
	_io.refresh_grid_from_level(_level)
	_toast("Loaded: " + path, &"success")


func _on_playtest() -> void:
	if not _io.write_playtest_snapshot(_level):
		_toast(Localization.t("ui_level_editor_playtest_write_failed",
			"Failed to write playtest"), &"error")
		return
	ActiveLevel.mark_playtest(EditorIO.PLAYTEST_PATH)
	ActiveLevel.queue(EditorIO.PLAYTEST_PATH)
	get_tree().change_scene_to_file(GODMODE_SCENE)


# 035 v1.1 — return to Game Editor if we came from there.
func _on_exit() -> void:
	if ActiveGame.has_queued_for_editor():
		get_tree().change_scene_to_file(GAME_EDITOR_SCENE)
		return
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_name_changed(new_name: String) -> void:
	_level.name = new_name


# Internal helpers

func _default_hex_selection() -> Dictionary:
	return {"source_id": 0, "atlas_coord": Vector2i.ZERO}


func _toast(text: String, level: StringName = &"info") -> void:
	if EventBus != null:
		EventBus.ui_toast_requested.emit(text, 0.0, level)
	else:
		GameLogger.info("EditorController", text)
