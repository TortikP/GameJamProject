extends PanelContainer
## FloorPalettePanel — pick a floor tile to paint. Dropdown switches between
## available TileSets (godmode_terrain / hex_terrain); each TileSet's tiles
## render as a button grid. Erase mode is a separate button.
##
## Right-click on any tile button opens a "Replace all" popup, listing every
## OTHER tile_kind currently in the level — picking one swaps every painted
## cell of that kind to the right-clicked tile.
##
## Signals (consumed by MapEditorController):
##   tile_picked(source_id: int, atlas: Vector2i)
##   erase_picked()
##   tileset_changed(path: String)
##   replace_all_requested(from_source: int, from_atlas: Vector2i,
##                         to_source: int, to_atlas: Vector2i)

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")
const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const DraggablePanel = preload("res://scripts/presentation/dev/draggable_panel.gd")

const TILESETS: Array[Dictionary] = [
	{"label": "Placeholder (6 tiles)", "path": "res://scenes/dev/placeholder_terrain.tres"},
	{"label": "Godmode Terrain",       "path": "res://scenes/dev/godmode_terrain.tres"},
	{"label": "Hex Terrain",           "path": "res://scenes/arena/tilesets/hex_terrain.tres"},
]

const ICON_SIZE: Vector2 = Vector2(48, 48)
const REPLACE_MENU_ID: StringName = &"floor_replace_menu"

signal tile_picked(source_id: int, atlas: Vector2i)
signal erase_picked()
signal tileset_changed(path: String)
signal replace_all_requested(from_source: int, from_atlas: Vector2i,
		to_source: int, to_atlas: Vector2i)

var _controller: Node = null
var _tileset_dropdown: OptionButton
var _tile_grid: HFlowContainer
var _erase_btn: Button
var _current_tileset: TileSet
var _current_path: String = ""


func _ready() -> void:
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	_build_ui()
	# Default selection: tileset[0]
	_current_path = TILESETS[0].path
	_current_tileset = load(_current_path) as TileSet
	_rebuild_tile_buttons()


func setup(controller: Node) -> void:
	_controller = controller


func _apply_theme() -> void:
	add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var header := Label.new()
	header.text = "Floor"
	UiTheme.apply_label_kind(header, "header")
	vbox.add_child(header)
	_install_drag(header)

	# Tileset dropdown
	_tileset_dropdown = OptionButton.new()
	for i in TILESETS.size():
		_tileset_dropdown.add_item(TILESETS[i].label, i)
	_tileset_dropdown.item_selected.connect(_on_tileset_selected)
	UiTheme.apply_button_styling(_tileset_dropdown)
	vbox.add_child(_tileset_dropdown)

	# Erase button
	_erase_btn = Button.new()
	_erase_btn.text = "Erase"
	_erase_btn.toggle_mode = true
	_erase_btn.pressed.connect(_on_erase_pressed)
	UiTheme.apply_button_styling(_erase_btn)
	vbox.add_child(_erase_btn)

	# Tile button grid (HFlowContainer wraps automatically)
	_tile_grid = HFlowContainer.new()
	_tile_grid.add_theme_constant_override("h_separation", 4)
	_tile_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(_tile_grid)


func _on_tileset_selected(idx: int) -> void:
	if idx < 0 or idx >= TILESETS.size():
		return
	_current_path = TILESETS[idx].path
	_current_tileset = load(_current_path) as TileSet
	_rebuild_tile_buttons()
	tileset_changed.emit(_current_path)


func _on_erase_pressed() -> void:
	# Untoggle other tile buttons (visual feedback only)
	for child in _tile_grid.get_children():
		if child is Button:
			(child as Button).button_pressed = false
	erase_picked.emit()


func _rebuild_tile_buttons() -> void:
	for child in _tile_grid.get_children():
		child.queue_free()
	if _current_tileset == null:
		return
	# Iterate over every source / atlas pair the TileSet defines.
	for source_idx in _current_tileset.get_source_count():
		var source_id: int = _current_tileset.get_source_id(source_idx)
		var src: TileSetSource = _current_tileset.get_source(source_id)
		if not (src is TileSetAtlasSource):
			continue
		var atlas: TileSetAtlasSource = src as TileSetAtlasSource
		for tile_idx in atlas.get_tiles_count():
			var atlas_coord: Vector2i = atlas.get_tile_id(tile_idx)
			var btn := _make_tile_button(atlas, source_id, atlas_coord)
			_tile_grid.add_child(btn)


func _make_tile_button(atlas: TileSetAtlasSource, source_id: int,
		atlas_coord: Vector2i) -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.custom_minimum_size = ICON_SIZE
	btn.text = ""

	# Icon: cropped texture from the atlas — TileMapLayer uses the same region
	var tile_texture: Texture2D = atlas.texture
	if tile_texture != null:
		var region_size: Vector2i = atlas.texture_region_size
		var atlas_tex := AtlasTexture.new()
		atlas_tex.atlas = tile_texture
		atlas_tex.region = Rect2(
			Vector2(atlas_coord.x * region_size.x, atlas_coord.y * region_size.y),
			Vector2(region_size))
		btn.icon = atlas_tex
		btn.expand_icon = true

	# Tooltip: show tile_kind from custom data if present
	var td: TileData = atlas.get_tile_data(atlas_coord, 0)
	if td != null:
		var tk: Variant = td.get_custom_data("tile_kind")
		if tk != null and String(tk) != "":
			btn.tooltip_text = String(tk)

	UiTheme.apply_button_styling(btn)
	btn.set_meta("source_id", source_id)
	btn.set_meta("atlas_coord", atlas_coord)
	btn.pressed.connect(_on_tile_pressed.bind(source_id, atlas_coord, btn))
	btn.gui_input.connect(_on_tile_gui_input.bind(source_id, atlas_coord))
	return btn


func _on_tile_pressed(source_id: int, atlas: Vector2i, btn: Button) -> void:
	# Untoggle erase + every other button (visual single-select)
	if _erase_btn != null:
		_erase_btn.button_pressed = false
	for child in _tile_grid.get_children():
		if child is Button and child != btn:
			(child as Button).button_pressed = false
	tile_picked.emit(source_id, atlas)


func _on_tile_gui_input(event: InputEvent, source_id: int, atlas: Vector2i) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_show_replace_menu(source_id, atlas)


# ── Replace-all flow ────────────────────────────────────────────────────────

func _show_replace_menu(target_source: int, target_atlas: Vector2i) -> void:
	if _controller == null or not _controller.has_method("get_level"):
		return
	var level: LevelData = _controller.get_level()
	# Collect distinct (source, atlas) pairs in the level, excluding target.
	var seen: Dictionary = {}  # "src:x,y" -> [src, atlas, label]
	for f in level.floor_cells:
		var key: String = "%d:%d,%d" % [f.source_id, f.atlas_coord.x, f.atlas_coord.y]
		if seen.has(key):
			continue
		if f.source_id == target_source and f.atlas_coord == target_atlas:
			continue
		var label: String = _label_for_atlas(f.source_id, f.atlas_coord)
		seen[key] = [f.source_id, f.atlas_coord, label]
	if seen.is_empty():
		EventBus.ui_toast_requested.emit("Нечего заменять — других типов нет", 1.5, &"info")
		return
	var menu := PopupMenu.new()
	add_child(menu)
	var entries: Array = seen.values()
	for i in entries.size():
		var entry: Array = entries[i]
		menu.add_item("Заменить все «%s» на этот" % entry[2], i)
	menu.id_pressed.connect(_on_replace_picked.bind(entries, target_source, target_atlas, menu))
	menu.popup_hide.connect(menu.queue_free)
	menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


func _on_replace_picked(item_id: int, entries: Array, to_source: int,
		to_atlas: Vector2i, menu: PopupMenu) -> void:
	if item_id < 0 or item_id >= entries.size():
		menu.queue_free()
		return
	var from_source: int = entries[item_id][0]
	var from_atlas: Vector2i = entries[item_id][1]
	var from_label: String = entries[item_id][2]
	var to_label: String = _label_for_atlas(to_source, to_atlas)
	menu.queue_free()
	# Confirm
	var confirm := _controller.get_node_or_null("HUD/ConfirmModal")
	if confirm != null and confirm.has_method("ask"):
		# Count target cells for confirm copy
		var count: int = 0
		var lvl: LevelData = _controller.get_level()
		for f in lvl.floor_cells:
			if f.source_id == from_source and f.atlas_coord == from_atlas:
				count += 1
		var ok: bool = await confirm.ask(
			"Заменить тайлы?",
			"Заменить %d тайлов «%s» на «%s»?" % [count, from_label, to_label],
			"Заменить", "Отмена", false)
		if not ok:
			return
	replace_all_requested.emit(from_source, from_atlas, to_source, to_atlas)


func _label_for_atlas(source_id: int, atlas: Vector2i) -> String:
	if _current_tileset == null:
		return "%d:%d,%d" % [source_id, atlas.x, atlas.y]
	var src: TileSetSource = _current_tileset.get_source(source_id)
	if src is TileSetAtlasSource:
		var atlas_src := src as TileSetAtlasSource
		var td: TileData = atlas_src.get_tile_data(atlas, 0)
		if td != null:
			var tk: Variant = td.get_custom_data("tile_kind")
			if tk != null and String(tk) != "":
				return String(tk)
	return "%d:%d,%d" % [source_id, atlas.x, atlas.y]


func _install_drag(handle: Control) -> void:
	var dragger := DraggablePanel.new()
	add_child(dragger)
	dragger.setup(self, handle)


# ── Public selection API (eyedropper / 1-9 quick select) ───────────────────

## Programmatically select the tile button matching (source_id, atlas).
## Toggles the button as if user clicked it — including emitting tile_picked
## so the controller switches mode. No-op if no button matches.
func select_tile(source_id: int, atlas: Vector2i) -> void:
	if _tile_grid == null:
		return
	for child in _tile_grid.get_children():
		if not (child is Button):
			continue
		var btn := child as Button
		if int(btn.get_meta("source_id", -1)) != source_id:
			continue
		if Vector2i(btn.get_meta("atlas_coord", Vector2i(-1, -1))) != atlas:
			continue
		# Found — simulate press.
		btn.button_pressed = true
		_on_tile_pressed(source_id, atlas, btn)
		return


## Quick palette select — pick the N-th tile button (0-indexed). Out of range
## → no-op. Erase button is NOT counted; only the actual tile grid.
func select_nth(idx: int) -> void:
	if _tile_grid == null or idx < 0:
		return
	var i: int = 0
	for child in _tile_grid.get_children():
		if not (child is Button):
			continue
		if i == idx:
			var btn := child as Button
			var src_id: int = int(btn.get_meta("source_id", -1))
			var atlas: Vector2i = Vector2i(btn.get_meta("atlas_coord", Vector2i(-1, -1)))
			if src_id < 0:
				return
			btn.button_pressed = true
			_on_tile_pressed(src_id, atlas, btn)
			return
		i += 1
