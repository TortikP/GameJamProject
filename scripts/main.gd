extends Node
## Main entry point.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@onready var _debug_layer : CanvasLayer = $DebugLayer
@onready var _debug_btn   : Button      = $UI/DebugBtn

func _ready() -> void:
	GameLogger.info("Main", "boot complete; emitting run_started")
	EventBus.run_started.emit()

	# TODO: remove in feature 005-roguelike-loop
	($UI/TestDialogueBtn as Button).pressed.connect(_on_test_dialogue_pressed)
	_debug_btn.pressed.connect(_on_debug_btn_pressed)


func _on_run_started() -> void:
	GameLogger.info("Main", "run_started signalled — EventBus is alive")


# TODO: remove in feature 005-roguelike-loop
func _on_test_dialogue_pressed() -> void:
	DialogueManager.request(&"respawn", {"run_count": 1})


func _on_debug_btn_pressed() -> void:
	_debug_layer.visible = not _debug_layer.visible


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		_debug_layer.visible = not _debug_layer.visible
		get_viewport().set_input_as_handled()
