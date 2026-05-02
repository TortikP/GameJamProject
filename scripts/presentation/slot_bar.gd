class_name SlotBar
extends HBoxContainer
## SlotBar — 4 ability slots bound to Q W E R (and aliased to 1 2 3 4 by controller).
##
## UI-only. Doesn't cast itself — controller listens to slot_activated and decides.
## Active slot is highlighted; activation also re-emits the signal so input from
## either keys or mouse-clicks-on-slot can drive casting.
##
## States per slot:
##   empty                                      — dim, no hover
##   filled+disabled (out of range / no target) — dim grey, light hover
##   filled+castable                            — bright, hover slightly brighter
##   active                                     — focus tint + scale-pop
##
## Cooldown overlay (numeric Label centered when Skill.cooldown_remaining > 0)
## is Phase 4 (T062, blocked on 007).

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const SLOT_LABELS := ["Q", "W", "E", "R"]
const SLOT_COUNT := 4

signal slot_activated(index: int)
signal slot_right_clicked(index: int)  # for ability picker popup

## Slot map: int index → Ability instance (or absent if empty).
## Dictionary intentionally — Godot 4.6 array element type-check fires
## on Resource subclasses passed through Variant boundaries even on
## plain Array. Dictionary has no type-check for values. See CLAUDE.md.
var _slots: Dictionary = {}
var _castable: Dictionary = {}  # int → bool — set by controller each frame
var _hovered: Dictionary = {}   # int → bool — mouse over slot
var _buttons: Array[Button] = []
var _cd_labels: Array[Label] = []  # cooldown overlay, one per slot — empty text when ready
var _active: int = -1  # -1 = no spell selected


func _ready() -> void:
	add_theme_constant_override("separation", UiTheme.SP_2)
	for i in SLOT_COUNT:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(72, 72)
		btn.text = SLOT_LABELS[i] + "\n—"
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_button_pressed.bind(i))
		btn.mouse_entered.connect(_on_mouse_entered.bind(i))
		btn.mouse_exited.connect(_on_mouse_exited.bind(i))
		btn.gui_input.connect(_on_button_gui_input.bind(i))
		UiTheme.apply_button_styling(btn)
		add_child(btn)
		_buttons.append(btn)
		# T062 numeric cooldown overlay — Label centered on the button. Hidden
		# until skill.cd_remaining > 0. Mouse-pass-through so it doesn't eat
		# button clicks.
		var cd_lbl := Label.new()
		cd_lbl.text = ""
		cd_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiTheme.apply_label_kind(cd_lbl, "display")
		cd_lbl.add_theme_color_override("font_color", UiTheme.SEM_DEBUFF)
		btn.add_child(cd_lbl)
		_cd_labels.append(cd_lbl)
	EventBus.ui_theme_reloaded.connect(_on_theme_reloaded)
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
##
## Spec 031 phase 3: this also drives cooldown-label refreshes —
## _refresh_visual reads the slot's _cd_remaining each call. The earlier
## early-return on unchanged castability skipped those refreshes, leaving
## stale numbers on slots that stayed dim across multiple ticks. 4 slots
## × per-frame is negligible.
func set_castable(index: int, castable: bool) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	_castable[index] = castable
	_refresh_visual(index)


func get_active() -> int:
	return _active


## Set active slot directly. Pass -1 to deselect all.
func set_active(index: int) -> void:
	if index < -1 or index >= SLOT_COUNT:
		return
	_active = index
	_refresh_all()


## Activate a slot: if it's already active, deselect (-1). Emits slot_activated.
func activate(index: int) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return
	if _active == index:
		set_active(-1)
		slot_activated.emit(-1)
	else:
		set_active(index)
		slot_activated.emit(index)


func _on_button_pressed(index: int) -> void:
	activate(index)


func _on_mouse_entered(index: int) -> void:
	_hovered[index] = true
	_refresh_visual(index)


func _on_mouse_exited(index: int) -> void:
	_hovered[index] = false
	_refresh_visual(index)


func _on_button_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			slot_right_clicked.emit(index)
			get_viewport().set_input_as_handled()


func _on_theme_reloaded() -> void:
	# Rebuild styleboxes (StyleBoxFlat instances are not shared per CLAUDE.md;
	# re-apply via helper). Modulate / scale state preserved by _refresh_all.
	for btn in _buttons:
		UiTheme.apply_button_styling(btn)
	_refresh_all()


func _refresh_all() -> void:
	for i in SLOT_COUNT:
		_refresh_visual(i)


func _refresh_visual(index: int) -> void:
	if index >= _buttons.size():
		return
	var btn := _buttons[index]
	var slot = _slots.get(index, null)
	var has_ability: bool = slot != null
	var castable: bool = _castable.get(index, false)
	var hovered: bool = _hovered.get(index, false)
	# Cooldown label: show remaining turns when slot holds a Skill with active
	# cooldown. Skill check via duck-type — Skill has _cd_remaining; bare
	# Ability instances don't (legacy).
	if index < _cd_labels.size():
		var cd_lbl := _cd_labels[index]
		var cd_remaining: int = 0
		if has_ability and "cooldown" in slot:
			cd_remaining = int(slot.get("_cd_remaining"))
		if cd_remaining > 0:
			cd_lbl.text = str(cd_remaining)
			cd_lbl.visible = true
		else:
			cd_lbl.text = ""
			cd_lbl.visible = false
	# Modulate is layered on top of the stylebox — kept simple to avoid
	# stylebox recompilation per state change. Active state uses FOCUS tint.
	if not has_ability:
		# Empty slot — strong dim, ignore hover.
		btn.modulate = Color(UiTheme.TEXT_FAINT, 1.0)
		btn.scale = Vector2.ONE
	elif index == _active:
		# Active is always visually distinct, even when not castable.
		# Focus tint via UiTheme.FOCUS_ACTIVE_* (pre-baked from FOCUS — see ui_theme).
		btn.modulate = UiTheme.FOCUS_ACTIVE_CASTABLE if castable else UiTheme.FOCUS_ACTIVE_DISABLED
		btn.scale = Vector2(1.12, 1.12)
		btn.pivot_offset = btn.size * 0.5
	elif not castable:
		# Filled but disabled (out of range / cooldown / no target).
		# Light hover overlay still applies — affords discoverability.
		var base := Color(UiTheme.TEXT_DIM.r, UiTheme.TEXT_DIM.g, UiTheme.TEXT_DIM.b, 1.0)
		btn.modulate = base.lightened(0.10) if hovered else base
		btn.scale = Vector2.ONE
	else:
		# Castable — full bright; hover slightly more.
		btn.modulate = UiTheme.HOVER_BRIGHTEN if hovered else Color.WHITE
		btn.scale = Vector2.ONE
