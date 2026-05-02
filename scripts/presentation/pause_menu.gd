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
@onready var _back_to_editor_btn: Button = $Center/Panel/VBox/BackToEditorButton
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
	_back_to_editor_btn.pressed.connect(_on_back_to_editor)
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
	for btn in [_resume_btn, _back_to_editor_btn, _restart_btn, _settings_btn, _menu_btn, _quit_btn]:
		UiTheme.apply_button_styling(btn)


func open() -> void:
	if visible:
		return
	# Refresh "Back to Editor" visibility — only relevant when the current
	# run came from the map editor's Playtest button (020).
	if _back_to_editor_btn != null:
		_back_to_editor_btn.visible = ActiveLevel.can_return_to_editor()
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
	var ok: bool = await _confirm.ask(
			Localization.t("ui_pause_restart_title", "Restart run?"),
			Localization.t("ui_pause_restart_body", "Current progress will be lost."),
			Localization.t("ui_pause_restart_confirm", "Restart"),
			Localization.t("ui_common_cancel", "Cancel"), true)
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
		EventBus.ui_toast_requested.emit(Localization.t("ui_pause_settings_unavailable", "Settings unavailable"), 2.0, &"warn")


func _on_main_menu() -> void:
	if _confirm == null or not _confirm.has_method("ask"):
		return
	var ok: bool = await _confirm.ask(
			Localization.t("ui_pause_main_menu_title", "Return to main menu?"),
			Localization.t("ui_pause_main_menu_body", "Current run will end."),
			Localization.t("ui_pause_main_menu_confirm", "Main Menu"),
			Localization.t("ui_common_cancel", "Cancel"), true)
	if ok:
		# 020 — leaving for main menu invalidates the playtest-origin link;
		# clear it so a future Ctrl+E from a different battle doesn't try to
		# return us to a stale editor session.
		ActiveLevel.clear_playtest_origin()
		ActiveLevel.clear()
		close()
		EventBus.main_menu_entered.emit()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## 020 — Back-to-Editor: only visible when ActiveLevel.can_return_to_editor().
## Re-queues the playtest origin path so the editor reopens with the same
## map. We don't clear playtest_origin_path here in case the user wants to
## bounce back-and-forth (editor → playtest → editor → playtest).
func _on_back_to_editor() -> void:
	if not ActiveLevel.can_return_to_editor():
		return
	ActiveLevel.queue(ActiveLevel.get_playtest_origin())
	close()
	get_tree().change_scene_to_file("res://scenes/dev/map_editor.tscn")


func _on_quit() -> void:
	if _confirm == null or not _confirm.has_method("ask"):
		return
	var ok: bool = await _confirm.ask(
			Localization.t("ui_pause_quit_title", "Quit game?"),
			Localization.t("ui_pause_quit_body", "Unsaved progress will be lost."),
			Localization.t("ui_pause_quit_confirm", "Quit"),
			Localization.t("ui_common_cancel", "Cancel"), true)
	if ok:
		get_tree().quit()
