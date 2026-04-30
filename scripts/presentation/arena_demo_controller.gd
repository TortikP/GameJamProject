extends Node

## Demo controller for hex_grid_demo.tscn.
## Init order (критично):
##   1. resolve nodes
##   2. _paint_demo_grid()  ← set_cell ДО того, как HexGrid их читает
##   3. grid.initialize()   ← читает клетки, строит pathfinder
##   4. _place_player()

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const PLAYER_ID: StringName = &"player"

@export var grid: HexGrid
@export var actor_node: Node2D

# ── Визуал ────────────────────────────────────────────────────────────────────
# Flat-top hex, outer radius r=32, tile_size=(64,56).
# Inner radius = r*√3/2 ≈ 27.7  ← граница до которой fill не может доходить
# чтобы не перекрывать соседей и оставить видимую обводку.
#
# bg_r  = 33.0  → чуть больше 32, перекрывает все зазоры от float-погрешности
# fill_r = 26.0  → < 27.7, fill не пересекается с соседями → тёмное кольцо = обводка
# Обводка всегда видна между любыми двумя тайлами, шовов нет.

const BG_R     := 33.0                        # bg-полигон, устраняет зазоры
const FILL_R   := 26.0                        # fill-полигон, меньше inner radius
const BG_COLOR_HEX := Color(0.05, 0.05, 0.07) # цвет обводки / фона сетки

# Цвета тайлов: 0=grass 1=wall 2=swamp 3=acid 4=fountain
const TILE_COLORS: Array[Color] = [
	Color(0.15, 0.80, 0.15),   # grass    — насыщенный зелёный
	Color(0.10, 0.10, 0.10),   # wall     — почти чёрный
	Color(0.45, 0.10, 0.55),   # swamp    — фиолетовый
	Color(0.92, 1.00, 0.00),   # acid     — ярко-жёлтый
	Color(0.05, 0.50, 1.00),   # fountain — ярко-синий
]

# Atlas column: 0=grass, 1=wall, 2=swamp, 3=acid, 4=fountain
const _GRID_MAP := [
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

const KEY_TO_NEIGHBOR: Dictionary = {
	"hex_move_top":          TileSet.CELL_NEIGHBOR_TOP_SIDE,
	"hex_move_top_left":     TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE,
	"hex_move_top_right":    TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,
	"hex_move_bottom":       TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
	"hex_move_bottom_left":  TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,
	"hex_move_bottom_right": TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
}

var _visual_layer: Node2D


func _ready() -> void:
	# ── 1. Резолв нод ─────────────────────────────────────────────────────────
	if grid == null:
		grid = get_node_or_null("../HexGrid") as HexGrid
	if grid == null:
		GameLogger.error("Demo", "HexGrid not found")
		return

	if grid.tile_map_layer == null:
		grid.tile_map_layer = grid.get_node_or_null("Terrain") as TileMapLayer
	if grid.vfx_overlay == null:
		grid.vfx_overlay = grid.get_node_or_null("VFXOverlay") as TileMapLayer
	if grid.tile_map_layer == null:
		GameLogger.error("Demo", "Terrain TileMapLayer not found")
		return

	if actor_node == null:
		actor_node = get_node_or_null("../HexGrid/Actors/PlayerActor") as Node2D
	if actor_node == null:
		actor_node = _create_placeholder_actor()

	# ── 2. Покраска клеток → Polygon2D гексы ─────────────────────────────────
	_paint_demo_grid()

	# ── 3. Инициализация HexGrid ──────────────────────────────────────────────
	grid.actor_step_started.connect(_on_step_started)
	grid.actor_step_finished.connect(_on_step_finished)
	EventBus.tile_effect_triggered.connect(_on_tile_effect_triggered)
	grid.initialize()

	# ── 4. Актор ──────────────────────────────────────────────────────────────
	_place_player()


# ── Визуальный слой ──────────────────────────────────────────────────────────

func _paint_demo_grid() -> void:
	grid.tile_map_layer.visible = false

	_visual_layer = Node2D.new()
	_visual_layer.name = "VisualHexLayer"
	grid.add_child(_visual_layer)

	var bg_pts  := _flat_hex_pts(BG_R)
	var fill_pts := _flat_hex_pts(FILL_R)

	# Два прохода: сначала все bg, потом все fill.
	# bg (z=0) — тёмный, перекрывает зазоры между тайлами.
	# fill (z=1) — поверх всех bg; fill_r < inner_radius → не перекрывает соседей.
	# Видимое тёмное кольцо = обводка.
	var bg_layer  := Node2D.new()
	var fill_layer := Node2D.new()
	bg_layer.z_index   = 0
	fill_layer.z_index = 1
	_visual_layer.add_child(bg_layer)
	_visual_layer.add_child(fill_layer)

	for row in _GRID_MAP.size():
		for col in _GRID_MAP[row].size():
			var coord := Vector2i(col, row)
			var tile_idx: int = _GRID_MAP[row][col]
			grid.tile_map_layer.set_cell(coord, 0, Vector2i(tile_idx, 0))

			var center: Vector2 = grid.tile_map_layer.map_to_local(coord)

			var bg := Polygon2D.new()
			bg.polygon  = bg_pts
			bg.color    = BG_COLOR_HEX
			bg.position = center
			bg_layer.add_child(bg)

			var fill := Polygon2D.new()
			fill.polygon  = fill_pts
			fill.color    = TILE_COLORS[tile_idx]
			fill.position = center
			fill_layer.add_child(fill)


func _flat_hex_pts(r: float) -> PackedVector2Array:
	# Flat-top: вершина 0 справа (0°), остальные через 60°
	var pts: PackedVector2Array = []
	for i in 6:
		var a := deg_to_rad(60.0 * i)
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	return pts


# ── Актор ─────────────────────────────────────────────────────────────────────

func _create_placeholder_actor() -> Node2D:
	var actors_node := grid.get_node_or_null("Actors") as Node2D
	if actors_node == null:
		actors_node = grid

	var poly := Polygon2D.new()
	poly.name = "PlayerActor"
	# Маленький белый гекс с ярко-голубой обводкой
	poly.polygon = _flat_hex_pts(16.0)
	poly.color = Color(1.0, 1.0, 1.0, 0.95)
	poly.z_index = 5

	# Обводка — чуть большой голубой гекс позади
	var outline := Polygon2D.new()
	outline.polygon = _flat_hex_pts(20.0)
	outline.color = Color(0.05, 0.80, 1.00)
	outline.z_index = 4
	outline.position = Vector2.ZERO
	actors_node.add_child(outline)
	actors_node.add_child(poly)

	# Сохраняем outline чтобы двигать вместе с актором
	poly.set_meta("outline", outline)
	GameLogger.info("Demo", "Placeholder actor created (white hex + cyan outline)")
	return poly


func _place_player() -> void:
	var start := Vector2i(4, 4)
	for candidate: Vector2i in [Vector2i(4, 4), Vector2i(0, 0)]:
		if grid.is_walkable(candidate):
			start = candidate
			break
	if not grid.is_walkable(start):
		for coord: Vector2i in grid._tiles:
			if grid.is_walkable(coord):
				start = coord
				break
	grid.place_actor(PLAYER_ID, start)
	_snap_actor_to_coord(start)
	GameLogger.info("Demo", "Player at %s. Click=move, QWEADS=6dirs." % str(start))


func _unhandled_input(event: InputEvent) -> void:
	for action: String in KEY_TO_NEIGHBOR:
		if event.is_action_pressed(action):
			grid.step_actor(PLAYER_ID, KEY_TO_NEIGHBOR[action])
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var coord := grid.coord_under_mouse()
			if coord != Vector2i(-1, -1):
				grid.move_actor(PLAYER_ID, coord)
			get_viewport().set_input_as_handled()


func _on_step_started(actor_id: StringName, _from: Vector2i, to: Vector2i) -> void:
	if actor_id != PLAYER_ID or actor_node == null:
		return
	var target_pos: Vector2 = grid.tile_map_layer.map_to_local(to)
	var cost: int = grid.get_move_cost(to)
	var duration: float = GameSpeed.get_value("arena", "step_duration", 0.18) * cost
	var tw := create_tween()
	tw.tween_property(actor_node, "position", target_pos, duration)
	# двигаем outline вместе
	if actor_node.has_meta("outline"):
		var outline := actor_node.get_meta("outline") as Node2D
		create_tween().tween_property(outline, "position", target_pos, duration)


func _on_step_finished(actor_id: StringName, coord: Vector2i) -> void:
	if actor_id == PLAYER_ID:
		GameLogger.info("Demo", "at %s  kind=%s  effect=%s" % [
			str(coord), grid.get_tile_kind(coord), grid.get_effect_id(coord)
		])


func _on_tile_effect_triggered(actor_id: StringName, coord: Vector2i, effect_id: StringName) -> void:
	GameLogger.info("HexGrid", "effect: %s @ %s for %s" % [effect_id, str(coord), actor_id])


func _snap_actor_to_coord(coord: Vector2i) -> void:
	if grid.tile_map_layer == null:
		return
	var pos: Vector2 = grid.tile_map_layer.map_to_local(coord)
	if actor_node != null:
		actor_node.position = pos
	if actor_node != null and actor_node.has_meta("outline"):
		(actor_node.get_meta("outline") as Node2D).position = pos
