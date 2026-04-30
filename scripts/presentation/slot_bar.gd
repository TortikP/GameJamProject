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

## Slot map: int index → Ability instance (or absent if empty).
## Dictionary intentionally — Godot 4.6 array element type-check fires
## on Resource subclasses passed through Variant boundaries even on
## plain Array. Dictionary has no type-check for values. See CLAUDE.md.
var _slots: Dictionary = {}
var _castable: Dictionary = {}  # int → bool — set by controller each frame
var _buttons: Array[Button] = []
var _active: int = 0


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	for i in SLOT_COUNT:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(72, 72)
		btn.text = SLOT_LABELS[i] + "\n—"
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_button_pressed.bind(i))
		add_child(btn)
		_buttons.append(btn)
	_refresh_all()


func set_slot(index: int, ability) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	_slots[index] = ability
	var label_id := "—" if ability == null else String(ability.id)
	_buttons[index].text = "%s\n%s" % [SLOT_LABELS[index], label_id]
	_refresh_visual(index)


func get_slot(index: int):
	if index < 0 or index >= SLOT_COUNT:
		return null
	return _slots.get(index, null)


## Called by controller per-frame for each slot. true → bright, false → dim.
func set_castable(index: int, castable: bool) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	if _castable.get(index, false) == castable:
		return  # no-op skip to avoid redundant modulate writes
	_castable[index] = castable
	_refresh_visual(index)


func get_active() -> int:
	return _active


func set_active(index: int) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	_active = index
	_refresh_all()


## Activate a slot AND emit the signal so controller casts.
func activate(index: int) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	set_active(index)
	slot_activated.emit(index)


func _on_button_pressed(index: int) -> void:
	activate(index)


func _refresh_all() -> void:
	for i in SLOT_COUNT:
		_refresh_visual(i)


func _refresh_visual(index: int) -> void:
	if index >= _buttons.size():
		return
	var btn := _buttons[index]
	var has_ability: bool = _slots.get(index, null) != null
	var castable: bool = _castable.get(index, false)
	if not has_ability:
		btn.modulate = Color(0.4, 0.4, 0.4)
		btn.scale = Vector2.ONE
	elif index == _active:
		# Active is always visually distinct, even when not castable.
		# Saturated yellow + slight upscale separates it from siblings.
		btn.modulate = Color(1.5, 1.5, 0.25) if castable else Color(1.1, 1.1, 0.5)
		btn.scale = Vector2(1.12, 1.12)
		btn.pivot_offset = btn.size * 0.5
	elif not castable:
		btn.modulate = Color(0.55, 0.55, 0.55)
		btn.scale = Vector2.ONE
	else:
		btn.modulate = Color(1, 1, 1)
		btn.scale = Vector2.ONE
