extends Node
## Main entry point.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const ARENA_DEMO := "res://scenes/arena/hex_grid_demo.tscn"
const GODMODE_SCENE := "res://scenes/dev/godmode.tscn"

const PREVIEW_SCENE = "res://scenes/dev/dialogue_preview.tscn"

@onready var _debug_layer : CanvasLayer = $DebugLayer

var _preview: Node = null


func _ready() -> void:
	GameLogger.info("Main", "boot complete; emitting run_started")
	EventBus.run_started.emit()
	
	($UI/TestDialogueBtn as Button).pressed.connect(_on_test_dialogue_pressed)
	($UI/DebugBtn as Button).pressed.connect(_on_debug_btn_pressed)

	# Временная кнопка запуска арены (удалить в feature 005)
	var arena_btn := Button.new()
	arena_btn.text = "▶  Arena Demo"
	arena_btn.anchors_preset = Control.PRESET_CENTER
	arena_btn.custom_minimum_size = Vector2(200, 48)
	arena_btn.pressed.connect(_on_arena_pressed)
	$UI.add_child(arena_btn)

	# Кнопка запуска Godmode (feature 004-godmode-base)
	var godmode_btn := Button.new()
	godmode_btn.text = "▶  Godmode (sandbox)"
	godmode_btn.anchors_preset = Control.PRESET_CENTER
	godmode_btn.custom_minimum_size = Vector2(220, 48)
	godmode_btn.position = Vector2(0, 60)
	godmode_btn.pressed.connect(_on_godmode_pressed)
	$UI.add_child(godmode_btn)


func _on_arena_pressed() -> void:
	get_tree().change_scene_to_file(ARENA_DEMO)


func _on_godmode_pressed() -> void:
	get_tree().change_scene_to_file(GODMODE_SCENE)


func _on_run_started() -> void:
	GameLogger.info("Main", "run_started signalled — EventBus is alive")


func _on_test_dialogue_pressed() -> void:
	DialogueManager.request(&"respawn", {"run_count": 1})
