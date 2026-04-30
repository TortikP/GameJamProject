class_name HexPlaceholderBuilder

## Builds a programmatic hex TileSet with 5 colored placeholder tiles and paints a 10x10 demo grid.
## Usage: call HexPlaceholderBuilder.setup(tile_map_layer) before grid.initialize().
## Katya's real TileSet replaces this via a .tres assigned in the editor.
##
## Tile legend (atlas column → tile_kind):
##   0  grass    (walkable=true,  cost=1,  effect="")
##   1  wall     (walkable=false, cost=1,  effect="")
##   2  swamp    (walkable=true,  cost=2,  effect="")
##   3  acid     (walkable=true,  cost=1,  effect="damage_zone")
##   4  fountain (walkable=true,  cost=1,  effect="heal_fountain")

const TILE_SIZE := Vector2i(64, 74)  # flat-top hex: 64 wide, 74 tall (≈ 64 * sqrt(3)/sqrt(3)*2)

# Tile definitions: [color, walkable, cost, kind, effect_id]
const TILE_DEFS := [
	[Color(0.3, 0.6, 0.2),  true,  1, "grass",    ""],
	[Color(0.25, 0.22, 0.2), false, 1, "wall",     ""],
	[Color(0.2, 0.4, 0.35), true,  2, "swamp",    ""],
	[Color(0.5, 0.8, 0.1),  true,  1, "acid",     "damage_zone"],
	[Color(0.1, 0.5, 0.9),  true,  1, "fountain", "heal_fountain"],
]

# 10x10 grid layout: 0=grass, 1=wall, 2=swamp, 3=acid, 4=fountain
const GRID_MAP := [
	[0,0,0,1,0,0,0,0,0,0],
	[0,2,0,1,0,0,3,0,0,0],
	[0,2,0,0,0,0,3,0,0,0],
	[0,2,0,0,0,0,0,0,4,0],
	[0,0,0,1,1,0,0,0,0,0],
	[0,0,0,0,0,0,0,2,0,0],
	[0,0,3,0,0,0,0,2,0,0],
	[0,0,0,0,1,0,0,0,0,0],
	[0,0,0,0,0,0,4,0,2,0],
	[0,0,0,0,0,0,0,0,0,0],
]


static func setup(tml: TileMapLayer) -> void:
	var ts := _build_tileset()
	tml.tile_set = ts
	_paint_grid(tml)


static func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	ts.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL  # flat-top
	ts.tile_size = TILE_SIZE

	# Custom data layers
	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(0, "walkable")
	ts.set_custom_data_layer_type(0, TYPE_BOOL)

	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(1, "move_cost")
	ts.set_custom_data_layer_type(1, TYPE_INT)

	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(2, "tile_kind")
	ts.set_custom_data_layer_type(2, TYPE_STRING_NAME)

	ts.add_custom_data_layer()
	ts.set_custom_data_layer_name(3, "effect_id")
	ts.set_custom_data_layer_type(3, TYPE_STRING_NAME)

	# Build atlas strip: 5 tiles × TILE_SIZE, one per column
	var img_width := TILE_SIZE.x * TILE_DEFS.size()
	var img := Image.create(img_width, TILE_SIZE.y, false, Image.FORMAT_RGBA8)

	for i in TILE_DEFS.size():
		var col: Color = TILE_DEFS[i][0]
		# Fill rectangle for this tile column
		for px in TILE_SIZE.x:
			for py in TILE_SIZE.y:
				img.set_pixel(i * TILE_SIZE.x + px, py, col)

	var texture := ImageTexture.create_from_image(img)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = TILE_SIZE

	for i in TILE_DEFS.size():
		var atlas_coord := Vector2i(i, 0)
		source.create_tile(atlas_coord)
		var td: TileData = source.get_tile_data(atlas_coord, 0)
		td.set_custom_data("walkable", TILE_DEFS[i][1])
		td.set_custom_data("move_cost", TILE_DEFS[i][2])
		td.set_custom_data("tile_kind", StringName(TILE_DEFS[i][3]))
		td.set_custom_data("effect_id", StringName(TILE_DEFS[i][4]))

	ts.add_source(source)  # source_id = 0
	return ts


static func _paint_grid(tml: TileMapLayer) -> void:
	for row in GRID_MAP.size():
		for col in GRID_MAP[row].size():
			var tile_idx: int = GRID_MAP[row][col]
			tml.set_cell(Vector2i(col, row), 0, Vector2i(tile_idx, 0))
