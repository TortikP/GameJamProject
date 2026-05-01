extends PanelContainer
## ActorInspector — right-side info panel showing the selected Actor's stats
## and abilities. Stats are editable (SpinBox) for sandbox tuning.
## Abilities are shown as labelled pips with tooltips.
##
## bind(actor)   — attach to a new actor (rebinds signals)
## unbind()      — detach, hides panel
## get_bound()   — returns current bound Actor (null if none)

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

signal speed_changed(actor: Actor)   # emitted when inspector changes actor.speed

var _actor: Actor = null

# UI nodes — resolved in _ready, all must exist in actor_inspector.tscn
@onready var _label_id: Label        = $VBox/ActorSection/LabelId
@onready var _label_team: Label      = $VBox/ActorSection/LabelTeam
@onready var _label_curr_hp: Label   = $VBox/ActorSection/RowMaxHp/LabelCurrHp
@onready var _spin_max_hp: SpinBox   = $VBox/ActorSection/RowMaxHp/SpinMaxHp
@onready var _spin_damage: SpinBox   = $VBox/ActorSection/RowDamage/SpinDamage
@onready var _spin_speed: SpinBox    = $VBox/ActorSection/RowSpeed/SpinSpeed
@onready var _abilities_row: HBoxContainer = $VBox/ActorSection/AbilitiesRow
@onready var _actor_section: Control = $VBox/ActorSection
@onready var _hex_section: Control   = $VBox/HexSection
@onready var _label_hex_coord: Label = $VBox/HexSection/LabelHexCoord
@onready var _label_hex_kind: Label  = $VBox/HexSection/LabelHexKind
@onready var _label_hex_effect: Label = $VBox/HexSection/LabelHexEffect


func _ready() -> void:
	hide()
	_setup_spinbox_ranges()
	# Both sections start hidden; shown by bind_* calls
	if _actor_section:
		_actor_section.hide()
	if _hex_section:
		_hex_section.hide()


## Pass game-action keys through to the controller by releasing SpinBox focus.
## Without this, a focused SpinBox LineEdit swallows QWER/Space/F-keys before
## _unhandled_input in GodmodeController ever sees them.
const _GAME_KEYS: Array = [
	KEY_Q, KEY_W, KEY_E, KEY_R,
	KEY_1, KEY_2, KEY_3, KEY_4,
	KEY_SPACE, KEY_ESCAPE,
	KEY_F1, KEY_F2, KEY_F5,
]
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	if (event as InputEventKey).keycode in _GAME_KEYS:
		for spin in [_spin_max_hp, _spin_damage, _spin_speed]:
			if spin != null:
				spin.get_line_edit().release_focus()
		# Do NOT call accept_event — let the key fall through to _unhandled_input


func _setup_spinbox_ranges() -> void:
	_spin_max_hp.min_value  = 1;   _spin_max_hp.max_value  = 200; _spin_max_hp.step  = 1
	_spin_damage.min_value  = 0;   _spin_damage.max_value  = 50;  _spin_damage.step  = 1
	_spin_speed.min_value   = 0;   _spin_speed.max_value   = 6;   _spin_speed.step   = 1
	_spin_max_hp.rounded  = true
	_spin_damage.rounded  = true
	_spin_speed.rounded   = true
	_restrict_to_int(_spin_max_hp)
	_restrict_to_int(_spin_damage)
	_restrict_to_int(_spin_speed)


## Prevent non-numeric input in a SpinBox's internal LineEdit.
func _restrict_to_int(spin: SpinBox) -> void:
	var le := spin.get_line_edit()
	le.text_changed.connect(func(new_text: String) -> void:
		var filtered := ""
		for c in new_text:
			if c >= "0" and c <= "9":
				filtered += c
		if filtered != new_text:
			var col := le.caret_column
			le.text = filtered
			le.caret_column = mini(col, filtered.length())
	)


func get_bound() -> Actor:
	return _actor


func bind(actor: Actor) -> void:
	if _actor != null:
		_disconnect_actor()
	_actor = actor
	if actor == null:
		if _actor_section:
			_actor_section.hide()
		_check_visibility()
		return

	_label_id.text   = String(actor.actor_id)
	_label_team.text = String(actor.team)
	_spin_max_hp.set_value_no_signal(actor.max_hp)
	_spin_damage.set_value_no_signal(actor.damage_bonus)
	_spin_speed.set_value_no_signal(actor.speed)

	actor.damaged.connect(_on_actor_damaged)
	actor.died.connect(_on_actor_died, CONNECT_ONE_SHOT)
	_spin_max_hp.value_changed.connect(_on_max_hp_changed)
	_spin_damage.value_changed.connect(_on_damage_changed)
	_spin_speed.value_changed.connect(_on_speed_changed)

	_refresh_hp_label()
	_rebuild_abilities()
	if _actor_section:
		_actor_section.show()
	_check_visibility()


func unbind() -> void:
	if _actor != null:
		_disconnect_actor()
	_actor = null
	if _actor_section:
		_actor_section.hide()
	_check_visibility()


## Show hex info layer. tile_kind and effect_id come from HexGrid.
func bind_hex(coord: Vector2i, tile_kind: StringName, effect_id: StringName) -> void:
	if _hex_section == null:
		return
	_label_hex_coord.text = "(%d, %d)" % [coord.x, coord.y]
	_label_hex_kind.text  = String(tile_kind) if tile_kind != &"" else "—"
	if effect_id != &"":
		_label_hex_effect.text = String(effect_id)
		_label_hex_effect.show()
	else:
		_label_hex_effect.hide()
	_hex_section.show()
	_check_visibility()


func unbind_hex() -> void:
	if _hex_section:
		_hex_section.hide()
	_check_visibility()


## Show panel if at least one section is visible, hide otherwise.
func _check_visibility() -> void:
	var actor_vis: bool = _actor_section != null and _actor_section.visible
	var hex_vis:   bool = _hex_section   != null and _hex_section.visible
	if actor_vis or hex_vis:
		show()
	else:
		hide()


func _disconnect_actor() -> void:
	if not is_instance_valid(_actor):
		_actor = null
		return
	if _actor.damaged.is_connected(_on_actor_damaged):
		_actor.damaged.disconnect(_on_actor_damaged)
	# died was CONNECT_ONE_SHOT — auto-disconnects after fire, no manual needed
	if _spin_max_hp.value_changed.is_connected(_on_max_hp_changed):
		_spin_max_hp.value_changed.disconnect(_on_max_hp_changed)
	if _spin_damage.value_changed.is_connected(_on_damage_changed):
		_spin_damage.value_changed.disconnect(_on_damage_changed)
	if _spin_speed.value_changed.is_connected(_on_speed_changed):
		_spin_speed.value_changed.disconnect(_on_speed_changed)


func _refresh_hp_label() -> void:
	if _actor == null:
		return
	_label_curr_hp.text = "%d /" % _actor.hp


## Rebuild the abilities row from actor.get_abilities().
func _rebuild_abilities() -> void:
	# Clear previous pips
	for child in _abilities_row.get_children():
		child.queue_free()
	if _actor == null:
		return
	var ids: Array[StringName] = _actor.get_abilities()
	if ids.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "—"
		none_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_abilities_row.add_child(none_lbl)
		return
	for id in ids:
		var pip := _make_ability_pip(id)
		_abilities_row.add_child(pip)


func _make_ability_pip(ability_id: StringName) -> Button:
	var btn := Button.new()
	btn.text = String(ability_id).substr(0, 1).to_upper()
	btn.disabled = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(28, 28)
	btn.tooltip_text = _build_tooltip(ability_id)
	return btn


func _build_tooltip(ability_id: StringName) -> String:
	# Try to get the ability from AbilityDatabase for richer info
	var ability: Ability = AbilityDatabase.get_ability(ability_id)
	if ability == null:
		return String(ability_id)
	var lines: Array[String] = []
	lines.append(String(ability_id))
	if ability.effect != null:
		if ability.effect is DamageEffect:
			lines.append("Damage: %d" % (ability.effect as DamageEffect).amount)
		else:
			lines.append("Effect: %s" % ability.effect.get_class())
	if ability.target != null:
		lines.append("Target: %s" % ability.target.get_class())
	return "\n".join(lines)


# ── SpinBox handlers ──────────────────────────────────────────────────────────

func _on_max_hp_changed(value: float) -> void:
	if _actor == null:
		return
	_actor.max_hp = int(value)
	_actor.hp     = mini(_actor.hp, _actor.max_hp)
	# Emit damaged (amount=0) so HealthBar on the actor sprite redraws immediately.
	_actor.damaged.emit(_actor.actor_id, 0, _actor.hp)
	_refresh_hp_label()


func _on_damage_changed(value: float) -> void:
	if _actor == null:
		return
	_actor.damage_bonus = int(value)


func _on_speed_changed(value: float) -> void:
	if _actor == null:
		return
	_actor.speed = int(value)
	speed_changed.emit(_actor)


# ── Actor signal handlers ─────────────────────────────────────────────────────

func _on_actor_damaged(_id: StringName, _amount: int, _hp_left: int) -> void:
	_refresh_hp_label()


func _on_actor_died(_id: StringName) -> void:
	if _actor_section:
		_actor_section.hide()
	_check_visibility()
