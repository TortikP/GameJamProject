extends Node
## Main entry point. Emits run_started so we can verify autoloads + EventBus
## are wired up. Will be replaced by a real main menu after bootstrap.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const ARENA_DEMO := "res://scenes/arena/hex_grid_demo.tscn"

func _ready() -> void:
	GameLogger.info("Main", "boot complete; emitting run_started")
	EventBus.run_started.emit()

	var btn := $UI/TestDialogueBtn as Button
	if btn:
		btn.pressed.connect(_on_test_dialogue_pressed)

	# Временная кнопка запуска арены (удалить в feature 005)
	var arena_btn := Button.new()
	arena_btn.text = "▶  Arena Demo"
	arena_btn.anchors_preset = Control.PRESET_CENTER
	arena_btn.custom_minimum_size = Vector2(200, 48)
	arena_btn.pressed.connect(_on_arena_pressed)
	$UI.add_child(arena_btn)


func _on_arena_pressed() -> void:
	get_tree().change_scene_to_file(ARENA_DEMO)


func _on_run_started() -> void:
	GameLogger.info("Main", "run_started signalled — EventBus is alive")


# TODO: remove in feature 005-roguelike-loop
func _on_test_dialogue_pressed() -> void:
	DialogueManager.request(&"respawn", {"run_count": 1})

