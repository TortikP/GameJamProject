extends Node2D

## Level Editor Controller (059) — orchestrates the new editor's MVC.
##
##   Model:    LevelData (in-memory state) + LayersModel (UI selection).
##   View:     LayersPanel + LevelMetaPanel + ToastLayer (HUD); HexGrid
##             (TileMapLayer for floor visualization).
##   Input:    InputDispatcher (centralized event pipeline).
##
## ## _ready sequencing (R1)
##
## Hard contract — order matters:
##   1. _resolve_nodes        — get_node for every export path.
##   2. _grid.initialize()    — HexGrid is built explicitly after resolve.
##   3. data + LayersModel    — LevelData with default name/wave; LayersModel
##                              with default hex selection.
##   4. InputDispatcher       — needs grid + layers ready.
##   5. _wire_panels          — connects signals; panels exist after step 1.
##   6. _refresh_grid_from_level — sync TileMapLayer with empty floor_cells.
##
## Reordering breaks subtle invariants (panels firing signals at uninitialized
## controller, dispatcher receiving events before wire, etc.). Don't.
##
## ## Public API (called only by InputDispatcher)
##
##   paint_floor(coord, source_id, atlas_coord)
##   erase_floor(coord)
##
## Anyone else needing to mutate floor goes through these too.
##
## ## Hard cap: 300 lines (AC13)
##
## If approaching cap, surface as finding and extract a helper (likely
## candidate: pull save/load + _refresh_grid_from_level into editor_io.gd).

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const MAPS_DIR := "res://data/maps/"

@export var hex_grid_path: NodePath
@export var layers_panel_path: NodePath
@export var level_meta_panel_path: NodePath
@export var toast_layer_path: NodePath

var _grid: HexGrid
var _layers_panel: LayersPanel
var _meta_panel: Node            # extends BasePanel (level_meta_panel.gd)
var _toast_layer: Node           # toast_layer.tscn root

var _level: LevelData
var _layers: LayersModel
var _dispatcher: InputDispatcher


func _ready() -> void:
	_resolve_nodes()
	if _grid != null:
		_grid.initialize()
	_level = LevelData.new()
	_layers = LayersModel.new()
	_layers.set_selection(LayersModel.LAYER_HEXES, _default_hex_selection())
	_dispatcher = InputDispatcher.new(self, _grid, _layers)
	_wire_panels()
	_refresh_grid_from_level()


func _unhandled_input(event: InputEvent) -> void:
	if _dispatcher == null:
		return
	if _dispatcher.handle(event):
		get_viewport().set_input_as_handled()


# ── Public API for InputDispatcher ────────────────────────────────

func paint_floor(coord: Vector2i, source_id: int, atlas_coord: Vector2i) -> void:
	if _grid == null or _grid.tile_map_layer == null:
		return
	_grid.tile_map_layer.set_cell(coord, source_id, atlas_coord)
	_set_or_update_floor_cell(coord, source_id, atlas_coord)


func erase_floor(coord: Vector2i) -> void:
	if _grid == null or _grid.tile_map_layer == null:
		return
	_grid.tile_map_layer.set_cell(coord, -1)
	_remove_floor_cell(coord)


# ── Wiring ────────────────────────────────────────────────────────

func _resolve_nodes() -> void:
	_grid = get_node_or_null(hex_grid_path) as HexGrid
	_layers_panel = get_node_or_null(layers_panel_path) as LayersPanel
	_meta_panel = get_node_or_null(level_meta_panel_path)
	_toast_layer = get_node_or_null(toast_layer_path)

	if _grid == null:
		GameLogger.error("EditorController", "hex_grid_path did not resolve")
	if _layers_panel == null:
		GameLogger.error("EditorController", "layers_panel_path did not resolve")
	if _meta_panel == null:
		GameLogger.error("EditorController", "level_meta_panel_path did not resolve")


func _wire_panels() -> void:
	if _layers_panel != null:
		_layers_panel.hex_palette_selection_changed.connect(_on_palette_selection)
	if _meta_panel != null:
		if _meta_panel.has_signal("save_requested"):
			_meta_panel.save_requested.connect(_on_save)
		if _meta_panel.has_signal("load_requested"):
			_meta_panel.load_requested.connect(_on_load)
		if _meta_panel.has_signal("exit_requested"):
			_meta_panel.exit_requested.connect(_on_exit)
		if _meta_panel.has_signal("playtest_requested"):
			_meta_panel.playtest_requested.connect(_on_playtest_disabled)
		if _meta_panel.has_signal("name_changed"):
			_meta_panel.name_changed.connect(_on_name_changed)
		if _meta_panel.has_method("setup"):
			_meta_panel.setup(self)
		# Reflect initial level name in the panel.
		if _meta_panel.has_method("set_level_name"):
			_meta_panel.set_level_name(_level.name)


# ── Slot handlers ─────────────────────────────────────────────────

func _on_palette_selection(value: Variant) -> void:
	_layers.set_selection(LayersModel.LAYER_HEXES, value)


func _on_save() -> void:
	var path := MAPS_DIR + _level.name + ".json"
	if LevelSerializer.save(_level, path):
		_toast("Saved: " + path)
	else:
		_toast("Save FAILED — see Output")


func _on_load(path: String) -> void:
	var loaded := LevelSerializer.load_from(path)
	if loaded == null:
		_toast("Load FAILED — see Output")
		return
	_level = loaded
	if _meta_panel != null and _meta_panel.has_method("set_level_name"):
		_meta_panel.set_level_name(_level.name)
	_refresh_grid_from_level()
	_toast("Loaded: " + path)


func _on_exit() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_playtest_disabled() -> void:
	_toast(Localization.t("ui_level_editor_playtest_disabled_toast",
		"Playtest not yet wired in new editor — coming in spec 060"))


func _on_name_changed(new_name: String) -> void:
	_level.name = new_name


# ── Internal helpers ──────────────────────────────────────────────

func _default_hex_selection() -> Dictionary:
	# First atlas tile of source 0 in hex_terrain.tres = grass (Katya's
	# default tile, post-032 tileset consolidation).
	return {"source_id": 0, "atlas_coord": Vector2i.ZERO}


## Sync TileMapLayer with _level.floor_cells. Clears existing cells first
## (for the Load case where the previous in-memory level might have had
## different cells).
func _refresh_grid_from_level() -> void:
	if _grid == null or _grid.tile_map_layer == null:
		return
	_grid.tile_map_layer.clear()
	for cell in _level.floor_cells:
		var coord: Vector2i = cell["coord"]
		var source_id: int = int(cell["source_id"])
		var atlas: Vector2i = cell["atlas_coord"]
		_grid.tile_map_layer.set_cell(coord, source_id, atlas)


## Update an existing floor_cells entry by coord, or append if missing.
## Schema per LevelData line 49:
##   {"coord": Vector2i, "source_id": int, "atlas_coord": Vector2i}
func _set_or_update_floor_cell(coord: Vector2i, source_id: int,
		atlas_coord: Vector2i) -> void:
	for cell in _level.floor_cells:
		var cell_coord: Vector2i = cell["coord"]
		if cell_coord == coord:
			cell["source_id"] = source_id
			cell["atlas_coord"] = atlas_coord
			return
	_level.floor_cells.append({
		"coord": coord,
		"source_id": source_id,
		"atlas_coord": atlas_coord,
	})


func _remove_floor_cell(coord: Vector2i) -> void:
	for i in range(_level.floor_cells.size() - 1, -1, -1):
		var cell_coord: Vector2i = _level.floor_cells[i]["coord"]
		if cell_coord == coord:
			_level.floor_cells.remove_at(i)
			return


func _toast(text: String) -> void:
	if _toast_layer != null and _toast_layer.has_method("show_toast"):
		_toast_layer.show_toast(text)
	else:
		GameLogger.info("EditorController", text)
