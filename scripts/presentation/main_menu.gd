extends Control
## MainMenu — entry point for the game. Replaces scenes/main.tscn from
## 001-bootstrap as the project main_scene (see project.godot).
##
## Buttons:
##   Start Run    — emits EventBus.run_started_requested, then loads the
##                  arena/godmode scene. Until a run-loop scene exists, this
##                  loads scenes/dev/godmode.tscn (sandbox). When 010+ ships
##                  scenes/arena/run.tscn, swap target.
##   Continue     — loads the single continue slot if present
##   Godmode      — straight-to-sandbox button (dev convenience)
##   Settings     — opens embedded SettingsPanel
##   Credits      — toast for now (no credits scene yet)
##   Quit         — get_tree().quit()

const RUN_SCENE: String = "res://scenes/dev/godmode.tscn"
const STORY_CAMPAIGN_PATH: String = "res://data/games/story_campaign.game.json"
const TUTORIAL_GAME_PATH: String = "res://data/games/tutorial.game.json"

const RUN_CHOICES: Array[Dictionary] = [
	{
		"title_key": "ui_main_menu_run_mode_tutorial_title",
		"title_fallback": "Tutorial",
		"body_key": "ui_main_menu_run_mode_tutorial_body",
		"body_fallback": "Learn the basics in a short guided map.",
		"path": TUTORIAL_GAME_PATH,
		"hub": false,
		"error_key": "ui_main_menu_start_tutorial_failed",
	},
	{
		"title_key": "games_story_campaign_game_name",
		"title_fallback": "Story Campaign",
		"body_key": "ui_main_menu_run_mode_story_body",
		"body_fallback": "Start in the office hub, then dive into the dream.",
		"path": STORY_CAMPAIGN_PATH,
		"hub": true,
		"error_key": "ui_main_menu_start_campaign_failed",
	},
]

@onready var _title: Label = $VBox/Title
@onready var _subtitle: Label = $VBox/Subtitle
@onready var _start_btn: Button = $VBox/StartButton
@onready var _continue_btn: Button = $VBox/ContinueButton
@onready var _godmode_btn: Button = $VBox/GodmodeButton
@onready var _map_editor_btn: Button = $VBox/MapEditorButton
@onready var _game_editor_btn: Button = $VBox/GameEditorButton
@onready var _load_game_btn: Button = $VBox/LoadGameButton
@onready var _load_custom_btn: Button = $VBox/LoadCustomLevelButton
@onready var _settings_btn: Button = $VBox/SettingsButton
@onready var _credits_btn: Button = $VBox/CreditsButton
@onready var _ui_catalog_btn: Button = $VBox/UiCatalogButton
@onready var _quit_btn: Button = $VBox/QuitButton
@onready var _settings: Node = $SettingsPanel
@onready var _file_dialog: FileDialog = $LoadFileDialog
@onready var _game_file_dialog: FileDialog = $LoadGameFileDialog
@onready var _run_mode_dialog: CanvasLayer = $RunModeDialog
@onready var _run_mode_panel: PanelContainer = $RunModeDialog/Center/Panel
@onready var _run_mode_title: Label = $RunModeDialog/Center/Panel/Margin/VBox/Title
@onready var _run_mode_body: Label = $RunModeDialog/Center/Panel/Margin/VBox/Body
@onready var _run_mode_list: VBoxContainer = $RunModeDialog/Center/Panel/Margin/VBox/Scroll/CampaignList
@onready var _run_mode_cancel_btn: Button = $RunModeDialog/Center/Panel/Margin/VBox/CancelButton


func _ready() -> void:
	# 020 — Main menu is the "all state clean" reset point. Clear any stale
	# ActiveLevel slots from a previous run/playtest so Start Run / Godmode
	# can't accidentally pick up a queued level or stale playtest origin.
	# 035 — Same for ActiveGame so an aborted campaign doesn't bleed into
	# the next session.
	ActiveLevel.clear()
	ActiveLevel.clear_playtest_origin()
	ActiveGame.clear()
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	_start_btn.pressed.connect(_on_start)
	_continue_btn.pressed.connect(_on_continue)
	_godmode_btn.pressed.connect(_on_godmode)
	_map_editor_btn.pressed.connect(_on_map_editor)
	_game_editor_btn.pressed.connect(_on_game_editor)
	_load_game_btn.pressed.connect(_on_load_game)
	_load_custom_btn.pressed.connect(_on_load_custom)
	_settings_btn.pressed.connect(_on_settings)
	_credits_btn.pressed.connect(_on_credits)
	_ui_catalog_btn.pressed.connect(_on_ui_catalog)
	_quit_btn.pressed.connect(_on_quit)
	_run_mode_cancel_btn.pressed.connect(_close_run_mode_dialog)
	_file_dialog.file_selected.connect(_on_custom_level_selected)
	_game_file_dialog.file_selected.connect(_on_game_selected)
	_continue_btn.disabled = not GameSave.has_continue_save()
	_build_run_mode_list()
	EventBus.main_menu_entered.emit()
	_start_btn.grab_focus()


func _apply_theme() -> void:
	UiTheme.apply_label_kind(_title, "display")
	# Title-specific bump for menu pop: oversized + thick black outline.
	# 80 = FS_BODY × 5, multiple of 16 so Pixellari stays crisp.
	_title.add_theme_font_size_override("font_size", 80)
	_title.add_theme_constant_override("outline_size", 8)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	# Subtitle: small tagline under the title, with its own outline.
	# 32 = FS_DISPLAY (pixel-perfect for Pixellari, visibly subordinate to 80).
	UiTheme.apply_label_kind(_subtitle, "body")
	_subtitle.add_theme_font_size_override("font_size", 32)
	_subtitle.add_theme_constant_override("outline_size", 4)
	_subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	for btn in [_start_btn, _continue_btn, _godmode_btn, _map_editor_btn,
				_game_editor_btn, _load_game_btn,
				_load_custom_btn, _settings_btn, _credits_btn,
				_ui_catalog_btn, _quit_btn]:
		UiTheme.apply_button_styling(btn)
	if _run_mode_panel != null:
		_run_mode_panel.add_theme_stylebox_override("panel", UiTheme.make_modal_stylebox())
	UiTheme.apply_label_kind(_run_mode_title, "header")
	UiTheme.apply_label_kind(_run_mode_body, "body")
	for btn in [_run_mode_cancel_btn]:
		UiTheme.apply_button_styling(btn)
	if _run_mode_list != null:
		for child in _run_mode_list.get_children():
			for nested in child.get_children():
				if nested is Button:
					UiTheme.apply_button_styling(nested)
				elif nested is Label:
					UiTheme.apply_label_kind(nested, "body")


func _unhandled_input(event: InputEvent) -> void:
	if _run_mode_dialog.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_run_mode_dialog()
		return
	# 020 — Ctrl+E from main menu opens map editor. Handled here so the
	# user doesn't have to start a run first to discover the editor.
	if event.is_action_pressed("dev_open_editor"):
		get_viewport().set_input_as_handled()
		_on_map_editor()


func _on_start() -> void:
	_open_run_mode_dialog()


func _open_run_mode_dialog() -> void:
	_run_mode_dialog.visible = true
	var first_btn := _first_run_choice_button()
	if first_btn != null:
		first_btn.grab_focus()
	else:
		_run_mode_cancel_btn.grab_focus()


func _close_run_mode_dialog() -> void:
	_run_mode_dialog.visible = false
	_start_btn.grab_focus()


func _on_continue() -> void:
	if not GameSave.continue_from_save():
		EventBus.ui_toast_requested.emit(Localization.t("ui_main_menu_continue_failed", "Failed to continue (see log)"), 3.0, &"error")
		_continue_btn.disabled = true
		return
	EventBus.run_started_requested.emit()
	get_tree().change_scene_to_file(RUN_SCENE)


func _build_run_mode_list() -> void:
	for child in _run_mode_list.get_children():
		child.queue_free()
	for choice in RUN_CHOICES:
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 4)
		var btn := Button.new()
		btn.text = Localization.t(String(choice["title_key"]), String(choice["title_fallback"]))
		btn.custom_minimum_size = Vector2(0, 48)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		UiTheme.apply_button_styling(btn)
		btn.pressed.connect(_start_game.bind(
			String(choice["path"]),
			String(choice["error_key"]),
			bool(choice["hub"])
		))
		card.add_child(btn)
		var body := Label.new()
		body.text = Localization.t(String(choice["body_key"]), String(choice["body_fallback"]))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_constant_override("outline_size", 2)
		body.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		UiTheme.apply_label_kind(body, "body")
		card.add_child(body)
		_run_mode_list.add_child(card)


func _first_run_choice_button() -> Button:
	for card in _run_mode_list.get_children():
		for child in card.get_children():
			if child is Button:
				return child
	return null


func _start_game(game_path: String, error_key: String, start_in_hub: bool = false) -> void:
	_close_run_mode_dialog()
	EventBus.run_started_requested.emit()
	if start_in_hub:
		CampaignController.prepare_hub_entry(&"new_game")
	var loaded: bool = ActiveGame.load_game_to_hub(game_path) if start_in_hub else ActiveGame.load_game(game_path)
	if not loaded:
		if start_in_hub:
			CampaignController.prepare_hub_entry(&"")
		EventBus.ui_toast_requested.emit(Localization.t(error_key, "Failed to start game (see log)"), 3.0, &"error")
		return
	get_tree().change_scene_to_file(RUN_SCENE)


func _on_godmode() -> void:
	get_tree().change_scene_to_file("res://scenes/dev/godmode.tscn")


func _on_map_editor() -> void:
	get_tree().change_scene_to_file("res://scenes/dev/map_editor.tscn")


func _on_game_editor() -> void:
	get_tree().change_scene_to_file("res://scenes/dev/game_editor.tscn")


func _on_load_game() -> void:
	_game_file_dialog.current_dir = "res://data/games/"
	_game_file_dialog.popup_centered()


func _on_game_selected(path: String) -> void:
	# 035 — ActiveGame.load_game queues the first level into ActiveLevel
	# itself, so all we do here is change scene. CampaignController takes
	# over from scene_ready / level_completed onwards.
	if not ActiveGame.load_game(path):
		EventBus.ui_toast_requested.emit(Localization.t("ui_main_menu_load_game_failed", "Failed to load game (see log)"), 3.0, &"error")
		return
	get_tree().change_scene_to_file("res://scenes/dev/godmode.tscn")


func _on_load_custom() -> void:
	_file_dialog.current_dir = "res://data/maps/"
	_file_dialog.popup_centered()


func _on_custom_level_selected(path: String) -> void:
	ActiveLevel.queue(path)
	get_tree().change_scene_to_file("res://scenes/dev/godmode.tscn")


func _on_settings() -> void:
	if _settings != null and _settings.has_method("open"):
		_settings.open()


func _on_credits() -> void:
	EventBus.ui_toast_requested.emit(Localization.t("ui_main_menu_credits_later", "Credits scene coming later."), 2.0, &"info")


func _on_ui_catalog() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/panels/ui_catalog.tscn")


func _on_quit() -> void:
	get_tree().quit()
