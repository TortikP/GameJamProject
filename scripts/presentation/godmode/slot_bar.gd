class_name SlotBar
extends HBoxContainer
## SlotBar — 4 ability slots bound to Q W E R (and aliased to 1 2 3 4 by controller).
##
## UI-only. Doesn't cast itself — controller listens to slot_activated and decides.
## Active slot is highlighted; activation also re-emits the signal so input from
## either keys or mouse-clicks-on-slot can drive casting.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const SLOT_LABELS := ["Q", "W", "E", "R"]
const SLOT_COUNT := 4

signal slot_activated(index: int)

var _slots: Array = []  # holds Ability or null per slot. Plain Array — Godot 4
                        # typed-array check is strict and rejects values that
                        # arrive via Variant boundary (e.g. duck-typed calls)
                        # even when runtime type matches.
var _buttons: Array[Button] = []
var _active: int = 0


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(72, 72)
		btn.text = SLOT_LABELS[i] + "\n—"
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_button_pressed.bind(i))
		add_child(btn)
		_buttons.append(btn)
	_refresh_active_visual()


func set_slot(index: int, ability: Ability) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	_slots[index] = ability
	var label_id := "—" if ability == null else String(ability.id)
	_buttons[index].text = "%s\n%s" % [SLOT_LABELS[index], label_id]


func get_slot(index: int) -> Ability:
	if index < 0 or index >= SLOT_COUNT:
		return null
	return _slots[index]


func get_active() -> int:
	return _active


func set_active(index: int) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	_active = index
	_refresh_active_visual()


## Activate a slot AND emit the signal so controller casts.
func activate(index: int) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	set_active(index)
	slot_activated.emit(index)


func _on_button_pressed(index: int) -> void:
	activate(index)


func _refresh_active_visual() -> void:
	for i in SLOT_COUNT:
		var btn := _buttons[i]
		if i == _active:
			btn.modulate = Color(1.2, 1.2, 0.6)
		else:
			btn.modulate = Color(1, 1, 1)
