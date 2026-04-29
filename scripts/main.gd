extends Node
## Main entry point. Emits run_started so we can verify autoloads + EventBus
## are wired up. Will be replaced by a real main menu after bootstrap.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

func _ready() -> void:
	GameLogger.info("Main", "boot complete; emitting run_started")
	EventBus.run_started.emit()


func _on_run_started() -> void:
	GameLogger.info("Main", "run_started signalled — EventBus is alive")
