extends CanvasLayer
## PauseMenu — central modal opened by ESC (godmode_controller priority chain)
## or by pressing the pause button on TopHudBar (EventBus.pause_toggled).
##
## Pauses the world via setup_modal_pause helper. Buttons:
##   Resume      — close menu, unpause
##   Restart Run — confirm → emit run_started_requested (host destroys current
##                 run, starts new one)
##   Settings    — open SettingsPanel (T043). Settings is its own modal but
##                 stacks under pause — closes back to pause menu.
##   Main Menu   — confirm → emit main_menu_entered (host changes scene)
##   Quit        — confirm → quit application

const UiHelpers = preload("res://scripts/presentation/ui_signal_helpers.gd")
const MODAL_ID: StringName = &"pause_menu"

@onready var _panel: PanelContainer = $Center/Panel
@onready var _title: Label = $Center/Panel/VBox/Title
@onready var _resume_btn: Button = $Center/Panel/VBox/ResumeButton
@onready var _restart_btn: Button = $Center/Panel/VBox/RestartButton
@onready var _settings_btn: Button = $Center/Panel/VBox/SettingsButton
@onready var _menu_btn: Button = $Center/Panel/VBox/MainMenuButton
@onready var _quit_btn: Button = $Center/Panel/VBox/QuitButton
@onready var _confirm: Node = $ConfirmModal


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	_resume_btn.pressed.connect(close)
	_restart_btn.pressed.connect(_on_restart)
	_settings_btn.pressed.connect(_on_settings)
	_menu_btn.pressed.connect(_on_main_menu)
	_quit_btn.pressed.connect(_on_quit)
	# Pause-toggled hook: TopHudBar's pause button emits this. Open from any
	# scene that has PauseMenu mounted.
	if EventBus.has_signal("pause_toggled"):
		EventBus.pause_toggled.connect(_on_pause_toggled)


func _apply_theme() -> void:
	if _panel:
		_panel.add_theme_stylebox_override("panel", UiTheme.make_modal_stylebox())
	UiTheme.apply_label_kind(_title, "display")
	for btn in [_resume_btn, _restart_btn, _settings_btn, _menu_btn, _quit_btn]:
		UiTheme.apply_button_styling(btn)


func open() -> void:
	if visible:
		return
	visible = true
	UiHelpers.emit_modal_opened(MODAL_ID, true)
	_resume_btn.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	UiHelpers.emit_modal_closed(MODAL_ID, true)


func _on_pause_toggled(paused: bool) -> void:
	# Open on true, close on false. The TopHudBar's button only ever passes true,
	# so this is forward-compat for explicit unpause callers.
	if paused:
		open()
	else:
		close()


func _on_restart() -> void:
	if _confirm == null or not _confirm.has_method("ask"):
		return
	var ok: bool = await _confirm.ask("Restart run?", "Current progress will be lost.",
			"Restart", "Cancel", true)
	if ok:
		close()
		EventBus.run_started_requested.emit()


func _on_settings() -> void:
	# Settings panel is mounted at scene root (typically alongside pause menu).
	# Best-effort lookup via parent.
	var settings: Node = get_parent().get_node_or_null("SettingsPanel")
	if settings != null and settings.has_method("open"):
		settings.open()
	else:
		EventBus.ui_toast_requested.emit("Settings unavailable", 2.0, &"warn")


func _on_main_menu() -> void:
	if _confirm == null or not _confirm.has_method("ask"):
		return
	var ok: bool = await _confirm.ask("Return to main menu?", "Current run will end.",
			"Main Menu", "Cancel", true)
	if ok:
		close()
		EventBus.main_menu_entered.emit()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_quit() -> void:
	if _confirm == null or not _confirm.has_method("ask"):
		return
	var ok: bool = await _confirm.ask("Quit game?", "Unsaved progress will be lost.",
			"Quit", "Cancel", true)
	if ok:
		get_tree().quit()
