extends Node
## Main entry point. Emits run_started so we can verify autoloads + EventBus
## are wired up. Will be replaced by a real main menu after bootstrap.

func _ready() -> void:
	Logger.info("Main", "boot complete; emitting run_started")
	EventBus.run_started.emit()


func _on_run_started() -> void:
	Logger.info("Main", "run_started signalled — EventBus is alive")
