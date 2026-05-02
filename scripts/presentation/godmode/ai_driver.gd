extends Node
## AiDriver — runs the per-world-turn enemy turn (Phase 1 RESOLVE, Phase 2 PLAN).
##
## Subscribes to EventBus.world_turn_ended via setup chain. Owns _world_processing
## flag (queryable via is_world_processing for input gates).

var _ctrl: Node = null


func _ready() -> void:
	_ctrl = get_parent()
