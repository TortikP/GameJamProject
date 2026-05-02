extends Control
## campaign_end — minimal "you win" screen shown at the end of a successful
## campaign run. Spec 035-game-editor §6.
##
## Reads RunScore.total at _ready (CampaignController emitted campaign_finished
## just before change_scene, so the value is still up-to-date).
## Single button: Main Menu — emits main_menu_entered + change_scene.

@onready var _title: Label = $VBox/Title
@onready var _score_label: Label = $VBox/Score
@onready var _menu_btn: Button = $VBox/MenuButton


func _ready() -> void:
	UiTheme.apply_label_kind(_title, "display")
	UiTheme.apply_label_kind(_score_label, "header")
	UiTheme.apply_button_styling(_menu_btn)
	# 035 — read cumulative campaign total from CampaignController, not from
	# RunScore.total. RunScore resets at the start of every level (run_started
	# signal in godmode_setup) so by the time this scene loads, RunScore.total
	# reflects only the LAST level. CampaignController accumulates across all
	# levels in a campaign and parks the final value in last_campaign_total
	# right before change_scene_to_file(this scene).
	_score_label.text = "Total score: %d" % CampaignController.last_campaign_total
	_menu_btn.pressed.connect(_on_main_menu)
	_menu_btn.grab_focus()
	# 035 — emit scene_ready so any future fade-in / cutscene listener can
	# react. CampaignController itself only reacts to scene_kind == &"godmode".
	EventBus.scene_ready.emit(&"campaign_end")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_ESCAPE or k == KEY_ENTER or k == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_on_main_menu()


func _on_main_menu() -> void:
	EventBus.main_menu_entered.emit()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
