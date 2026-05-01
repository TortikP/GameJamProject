extends Control
## MainMenu — entry point for the game. Replaces scenes/main.tscn from
## 001-bootstrap as the project main_scene (see project.godot).
##
## Buttons:
##   Start Run    — emits EventBus.run_started_requested, then loads the
##                  arena/godmode scene. Until a run-loop scene exists, this
##                  loads scenes/dev/godmode.tscn (sandbox). When 010+ ships
##                  scenes/arena/run.tscn, swap target.
##   Continue     — disabled (no save system in jam scope; AC-spec)
##   Godmode      — straight-to-sandbox button (dev convenience)
##   Settings     — opens embedded SettingsPanel
##   Credits      — toast for now (no credits scene yet)
##   Quit         — get_tree().quit()

const RUN_SCENE: String = "res://scenes/dev/godmode.tscn"

@onready var _title: Label = $VBox/Title
@onready var _subtitle: Label = $VBox/Subtitle
@onready var _start_btn: Button = $VBox/StartButton
@onready var _continue_btn: Button = $VBox/ContinueButton
@onready var _godmode_btn: Button = $VBox/GodmodeButton
@onready var _settings_btn: Button = $VBox/SettingsButton
@onready var _credits_btn: Button = $VBox/CreditsButton
@onready var _quit_btn: Button = $VBox/QuitButton
@onready var _settings: Node = $SettingsPanel


func _ready() -> void:
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	_start_btn.pressed.connect(_on_start)
	_godmode_btn.pressed.connect(_on_godmode)
	_settings_btn.pressed.connect(_on_settings)
	_credits_btn.pressed.connect(_on_credits)
	_quit_btn.pressed.connect(_on_quit)
	# Continue button stays disabled — no save system in jam scope.
	EventBus.main_menu_entered.emit()
	_start_btn.grab_focus()


func _apply_theme() -> void:
	UiTheme.apply_label_kind(_title, "display")
	UiTheme.apply_label_kind(_subtitle, "small")
	for btn in [_start_btn, _continue_btn, _godmode_btn, _settings_btn,
				_credits_btn, _quit_btn]:
		UiTheme.apply_button_styling(btn)


func _on_start() -> void:
	EventBus.run_started_requested.emit()
	get_tree().change_scene_to_file(RUN_SCENE)


func _on_godmode() -> void:
	get_tree().change_scene_to_file("res://scenes/dev/godmode.tscn")


func _on_settings() -> void:
	if _settings != null and _settings.has_method("open"):
		_settings.open()


func _on_credits() -> void:
	EventBus.ui_toast_requested.emit("Credits scene coming later.", 2.0, &"info")


func _on_quit() -> void:
	get_tree().quit()
