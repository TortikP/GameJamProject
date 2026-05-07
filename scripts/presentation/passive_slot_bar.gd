class_name PassiveSlotBar
extends HBoxContainer

const SLOT_LABELS := ["P1", "P2"]
const SLOT_COUNT := 2

signal passive_hovered(index: int)
signal passive_unhovered(index: int)

var _slots: Dictionary = {}
var _buttons: Array[Button] = []


func _ready() -> void:
	add_theme_constant_override("separation", UiTheme.SP_2)
	for i in SLOT_COUNT:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(64, 56)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_entered.connect(_on_mouse_entered.bind(i))
		btn.mouse_exited.connect(_on_mouse_exited.bind(i))
		UiTheme.apply_button_styling(btn)
		btn.add_theme_font_size_override("font_size", UiTheme.FS_SMALL)
		add_child(btn)
		_buttons.append(btn)
	EventBus.ui_theme_reloaded.connect(_on_theme_reloaded)
	_refresh_all()


func set_slot(index: int, skill) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	_slots[index] = skill
	_refresh_visual(index)


func get_slot(index: int):
	if index < 0 or index >= SLOT_COUNT:
		return null
	return _slots.get(index, null)


func _on_theme_reloaded() -> void:
	for btn in _buttons:
		UiTheme.apply_button_styling(btn)
	_refresh_all()


func _on_mouse_entered(index: int) -> void:
	passive_hovered.emit(index)


func _on_mouse_exited(index: int) -> void:
	passive_unhovered.emit(index)


func _refresh_all() -> void:
	for i in SLOT_COUNT:
		_refresh_visual(i)


func _refresh_visual(index: int) -> void:
	if index >= _buttons.size():
		return
	var btn: Button = _buttons[index]
	var skill = _slots.get(index, null)
	var label: String = SLOT_LABELS[index]
	if skill != null and "id" in skill:
		var name_key: String = String(skill.name) if "name" in skill else ""
		var display_name: String = Localization.t(name_key, str(skill.id)) if name_key != "" else str(skill.id)
		btn.text = "%s\n%s" % [label, display_name]
		btn.modulate = Color.WHITE
	else:
		btn.text = "%s\n-" % label
		btn.modulate = Color(UiTheme.TEXT_DIM.r, UiTheme.TEXT_DIM.g, UiTheme.TEXT_DIM.b, 1.0)
