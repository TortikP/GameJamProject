extends Label
## Top-of-HUD turn counter for godmode. Listens to EventBus.world_turn_ended.

func _ready() -> void:
	text = "Turn: %d" % TurnManager.current()
	EventBus.world_turn_ended.connect(_on_turn)


func _on_turn(turn: int) -> void:
	text = "Turn: %d" % turn
