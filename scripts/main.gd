extends Node
## Main entry point. Emits run_started so we can verify autoloads + EventBus
## are wired up. Will be replaced by a real main menu after bootstrap.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

func _ready() -> void:
	GameLogger.info("Main", "boot complete; emitting run_started")
	EventBus.run_started.emit()

	# TODO: remove in feature 005-roguelike-loop
	var btn := $UI/TestDialogueBtn as Button
	if btn:
		btn.pressed.connect(_on_test_dialogue_pressed)


func _on_run_started() -> void:
	GameLogger.info("Main", "run_started signalled — EventBus is alive")


# TODO: remove in feature 005-roguelike-loop
func _on_test_dialogue_pressed() -> void:
	DialogueManager.request(&"respawn", {"run_count": 1})

