extends Control
## campaign_defeat - final stop after a failed campaign run.
##
## Defeat dialogue is played by CampaignController before this scene loads.
## From here the player deliberately returns to the main menu.

@onready var _title: Label = $VBox/Title
@onready var _body: Label = $VBox/Body
@onready var _menu_btn: Button = $VBox/MenuButton


func _ready() -> void:
	UiTheme.apply_label_kind(_title, "display")
	UiTheme.apply_label_kind(_body, "header")
	UiTheme.apply_button_styling(_menu_btn)
	_title.text = Localization.t("ui_campaign_defeat_title", "Defeat")
	if CampaignController.last_defeat_final_boss:
		_body.text = Localization.t("ui_campaign_defeat_final_boss_body", "The final battle is lost.")
	else:
		_body.text = Localization.t("ui_campaign_defeat_body", "The campaign ends here.")
	_menu_btn.text = Localization.t("ui_campaign_defeat_menu_button", "Main Menu")
	_menu_btn.pressed.connect(_on_main_menu)
	_menu_btn.grab_focus()
	EventBus.scene_ready.emit(&"campaign_defeat")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_ESCAPE or k == KEY_ENTER or k == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_on_main_menu()


func _on_main_menu() -> void:
	EventBus.main_menu_entered.emit()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
