class_name HexTile

## Data holder for a single hex cell. Populated from TileData custom layers at _ready().
## Never mutated at runtime — treat as read-only after HexGrid._build_tile_map() fills it.

var coord: Vector2i
var walkable: bool
var move_cost: int          # 1 = normal, 2+ = difficult
var tile_kind: StringName   # "grass", "wall", "swamp", "acid", "fountain", ...
var static_effect_id: StringName  # "" = none, "damage_zone", "heal_fountain", ...


func _init(
		p_coord: Vector2i,
		p_walkable: bool,
		p_move_cost: int,
		p_tile_kind: StringName,
		p_effect_id: StringName
) -> void:
	coord = p_coord
	walkable = p_walkable
	move_cost = p_move_cost
	tile_kind = p_tile_kind
	static_effect_id = p_effect_id
