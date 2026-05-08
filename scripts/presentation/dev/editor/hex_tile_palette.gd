class_name HexTilePalette
extends VBoxContainer

## Tile picker grid for the editor's `hexes` layer. Iterates
## hex_terrain.tres atlas sources, renders one Button per (source_id,
## atlas_coord), plus an Erase button at the end. Single ButtonGroup
## across all buttons gives radio-mode out of the box — no manual
## set_pressed_no_signal cycles like in the legacy floor_palette_panel.
##
## Emits `selection_changed(value: Variant)`:
##   - Tile picked:  Dictionary {"source_id": int, "atlas_coord": Vector2i}
##   - Erase picked: StringName &"erase"
##
## Owned by LayersPanel; lives in its body. In 060 will be the content
## of the `hexes` tab on a TabbedBasePanel — no internal changes needed.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")

const TILESET_PATH := "res://scenes/arena/tilesets/hex_terrain.tres"
const ICON_SIZE := Vector2(48, 48)

signal selection_changed(value: Variant)

var _button_group: ButtonGroup
var _grid: HFlowContainer


func _ready() -> void:
	_button_group = ButtonGroup.new()
	_grid = HFlowContainer.new()
	_grid.name = "TileGrid"
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	add_child(_grid)
	_build_buttons()


func _build_buttons() -> void:
	var tileset: TileSet = load(TILESET_PATH) as TileSet
	if tileset == null:
		push_warning("[HexTilePalette] cannot load %s" % TILESET_PATH)
		return
	for source_idx in tileset.get_source_count():
		var source_id := tileset.get_source_id(source_idx)
		var src: TileSetAtlasSource = tileset.get_source(source_id) as TileSetAtlasSource
		if src == null:
			continue
		for tile_idx in src.get_tiles_count():
			var atlas_coord := src.get_tile_id(tile_idx)
			_grid.add_child(_make_tile_button(src, source_id, atlas_coord))
	_grid.add_child(_make_erase_button())


func _make_tile_button(atlas: TileSetAtlasSource, source_id: int,
		atlas_coord: Vector2i) -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_group = _button_group
	btn.custom_minimum_size = ICON_SIZE
	btn.text = ""

	# Icon: cropped texture from the atlas — same region the
	# TileMapLayer renders. Pattern from floor_palette_panel.gd:148-158.
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

	# Tooltip: tile_kind from custom data if present (helps when
	# multiple atlases have visually similar tiles).
	var td: TileData = atlas.get_tile_data(atlas_coord, 0)
	if td != null:
		var tk: Variant = td.get_custom_data("tile_kind")
		if tk != null and String(tk) != "":
			btn.tooltip_text = String(tk)

	UiTheme.apply_button_styling(btn)
	btn.set_meta("source_id", source_id)
	btn.set_meta("atlas_coord", atlas_coord)
	btn.pressed.connect(_on_tile_pressed.bind(source_id, atlas_coord))
	return btn


func _make_erase_button() -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_group = _button_group
	btn.custom_minimum_size = ICON_SIZE
	btn.text = Localization.t("ui_floor_palette_erase", "Erase")
	UiTheme.apply_button_styling(btn)
	btn.pressed.connect(_on_erase_pressed)
	return btn


func _on_tile_pressed(source_id: int, atlas_coord: Vector2i) -> void:
	selection_changed.emit({"source_id": source_id, "atlas_coord": atlas_coord})


func _on_erase_pressed() -> void:
	selection_changed.emit(&"erase")
