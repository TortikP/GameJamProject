extends CanvasLayer

## HubController is mounted only in campaign hub scenes. It gives the office
## computer an interaction hint and opens the dream-entry modal.

const GODMODE_SCENE: String = "res://scenes/dev/godmode.tscn"
const COMPUTER_OBJECT_ID: StringName = &"object_computer"
const PLAYER_ID: StringName = &"player"

var _ctrl: Node = null
var _grid: HexGrid = null
var _computer_coord: Vector2i = Vector2i(-1, -1)
var _hint_label: Label = null
var _modal_backdrop: ColorRect = null
var _modal_panel: PanelContainer = null


func setup(ctrl: Node, level: LevelData) -> void:
	_ctrl = ctrl
	_grid = ctrl.grid if ctrl != null else null
	_computer_coord = _find_computer_coord(level)
	if _computer_coord == Vector2i(-1, -1):
		return
	_build_hint()
	_build_modal()
	set_process(true)
	_play_entry_dialogue.call_deferred()


func try_interact_at(coord: Vector2i) -> bool:
	if not ActiveGame.is_in_hub():
		return false
	if coord != _computer_coord:
		return false
	_open_modal()
	return true


func _process(_delta: float) -> void:
	if _hint_label == null or _grid == null or _grid.tile_map_layer == null:
		return
	var world_pos: Vector2 = _grid.tile_map_layer.to_global(_grid.tile_map_layer.map_to_local(_computer_coord))
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * world_pos
	_hint_label.global_position = screen_pos + Vector2(-_hint_label.size.x * 0.5, -92.0)


func _find_computer_coord(level: LevelData) -> Vector2i:
	if level == null:
		return Vector2i(-1, -1)
	for entry in level.objects:
		if StringName(entry.get("object_id", &"")) == COMPUTER_OBJECT_ID:
			return entry.get("coord", Vector2i(-1, -1))
	return Vector2i(-1, -1)


func _build_hint() -> void:
	_hint_label = Label.new()
	_hint_label.text = Localization.t("ui_hub_computer_hint", "Move to the computer")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_constant_override("outline_size", 4)
	_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	UiTheme.apply_label_kind(_hint_label, "header")
	add_child(_hint_label)


func _build_modal() -> void:
	_modal_backdrop = ColorRect.new()
	_modal_backdrop.name = "HubComputerBackdrop"
	_modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_backdrop.color = Color(0, 0, 0, 0.55)
	_modal_backdrop.visible = false
	add_child(_modal_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_backdrop.add_child(center)

	_modal_panel = PanelContainer.new()
	_modal_panel.custom_minimum_size = Vector2(520, 0)
	_modal_panel.add_theme_stylebox_override("panel", UiTheme.make_modal_stylebox())
	center.add_child(_modal_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_modal_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = Localization.t("ui_hub_computer_title", "Office Computer")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.apply_label_kind(title, "header")
	vbox.add_child(title)

	var body := Label.new()
	body.text = Localization.t("ui_hub_computer_body", "The dream is ready. Dive in or stay in the office.")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTheme.apply_label_kind(body, "body")
	vbox.add_child(body)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	vbox.add_child(buttons)

	var dive_btn := Button.new()
	dive_btn.text = Localization.t("ui_hub_computer_dive_button", "Dive into Dream")
	UiTheme.apply_button_styling(dive_btn)
	dive_btn.pressed.connect(_on_dive_pressed)
	buttons.add_child(dive_btn)

	var back_btn := Button.new()
	back_btn.text = Localization.t("ui_hub_computer_back_button", "Return")
	UiTheme.apply_button_styling(back_btn)
	back_btn.pressed.connect(_close_modal)
	buttons.add_child(back_btn)


func _open_modal() -> void:
	if _modal_backdrop == null:
		return
	_modal_backdrop.visible = true
	EventBus.ui_modal_opened.emit(&"hub_computer")


func _close_modal() -> void:
	if _modal_backdrop == null:
		return
	_modal_backdrop.visible = false
	EventBus.ui_modal_closed.emit(&"hub_computer")


func _on_dive_pressed() -> void:
	_close_modal()
	EventBus.run_started_requested.emit()
	if not ActiveGame.start_campaign_attempt():
		EventBus.ui_toast_requested.emit(Localization.t("ui_hub_start_attempt_failed", "Failed to enter the dream"), 3.0, &"error")
		return
	get_tree().change_scene_to_file(GODMODE_SCENE)


func _play_entry_dialogue() -> void:
	var dialogue_id: StringName = CampaignController.consume_hub_entry_dialogue_id()
	if dialogue_id == &"":
		return
	GameSave.save_campaign_state("hub entry dialogue consumed")
	if DialogueDB.has_line(dialogue_id):
		DialogueManager.play(dialogue_id, true)
