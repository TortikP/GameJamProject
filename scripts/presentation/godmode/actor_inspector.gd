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
@onready var _label_id: Label        = $VBox/LabelId
@onready var _label_team: Label      = $VBox/LabelTeam
@onready var _label_hp: Label        = $VBox/LabelHp
@onready var _spin_max_hp: SpinBox   = $VBox/RowMaxHp/SpinMaxHp
@onready var _spin_damage: SpinBox   = $VBox/RowDamage/SpinDamage
@onready var _spin_speed: SpinBox    = $VBox/RowSpeed/SpinSpeed
@onready var _abilities_row: HBoxContainer = $VBox/AbilitiesRow


func _ready() -> void:
	hide()
	_setup_spinbox_ranges()


func _setup_spinbox_ranges() -> void:
	_spin_max_hp.min_value  = 1;   _spin_max_hp.max_value  = 200; _spin_max_hp.step  = 1
	_spin_damage.min_value  = 0;   _spin_damage.max_value  = 50;  _spin_damage.step  = 1
	_spin_speed.min_value   = 0;   _spin_speed.max_value   = 6;   _spin_speed.step   = 1
	_spin_max_hp.rounded  = true
	_spin_damage.rounded  = true
	_spin_speed.rounded   = true


func get_bound() -> Actor:
	return _actor


func bind(actor: Actor) -> void:
	if _actor != null:
		_disconnect_actor()
	_actor = actor
	if actor == null:
		hide()
		return

	# Populate static fields
	_label_id.text   = String(actor.actor_id)
	_label_team.text = String(actor.team)

	# SpinBox values — use set_value_no_signal to avoid triggering value_changed
	_spin_max_hp.set_value_no_signal(actor.max_hp)
	_spin_damage.set_value_no_signal(actor.damage_bonus)
	_spin_speed.set_value_no_signal(actor.speed)

	# Connect signals
	actor.damaged.connect(_on_actor_damaged)
	actor.died.connect(_on_actor_died, CONNECT_ONE_SHOT)
	_spin_max_hp.value_changed.connect(_on_max_hp_changed)
	_spin_damage.value_changed.connect(_on_damage_changed)
	_spin_speed.value_changed.connect(_on_speed_changed)

	_refresh_hp_label()
	_rebuild_abilities()
	show()


func unbind() -> void:
	if _actor != null:
		_disconnect_actor()
	_actor = null
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
	_label_hp.text = "HP: %d / %d" % [_actor.hp, _actor.max_hp]


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
	# Controller listens to EventBus.actor_died and calls _deselect_to_player.
	# We just hide here to avoid showing stale data if controller is slow.
	hide()
