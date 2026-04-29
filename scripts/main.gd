extends Node
## Main entry point.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const PREVIEW_SCENE = "res://scenes/dev/dialogue_preview.tscn"

@onready var _debug_layer : CanvasLayer = $DebugLayer

var _preview: Node = null


func _ready() -> void:
	GameLogger.info("Main", "boot complete; emitting run_started")
	EventBus.run_started.emit()

	# TODO: remove in feature 005-roguelike-loop
	($UI/TestDialogueBtn as Button).pressed.connect(_on_test_dialogue_pressed)
	($UI/DebugBtn as Button).pressed.connect(_on_debug_btn_pressed)


func _on_run_started() -> void:
	GameLogger.info("Main", "run_started signalled — EventBus is alive")


func _on_test_dialogue_pressed() -> void:
	DialogueManager.request(&"respawn", {"run_count": 1})


func _on_debug_btn_pressed() -> void:
	_toggle_preview()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		_toggle_preview()
		get_viewport().set_input_as_handled()


func _toggle_preview() -> void:
	if _preview == null:
		_preview = load(PREVIEW_SCENE).instantiate()
		_debug_layer.add_child(_preview)
		_debug_layer.visible = true
	else:
		_debug_layer.visible = not _debug_layer.visible
