extends PanelContainer
## ActorInspector — right-side info panel showing the selected Actor's stats
## and abilities. In dev_mode (Godmode), stats are editable SpinBoxes; in
## production scenes (dev_mode=false), they're read-only Labels created at
## runtime as siblings — same scene, two modes, no .tscn duplication.
##
## bind(actor)   — attach to a new actor (rebinds signals)
## unbind()      — detach, hides panel
## get_bound()   — returns current bound Actor (null if none)
##
## Team badge: small ColorRect prepended to the id row, colored by team.
## Palette: UiTheme.* throughout. Subscribes to ui_theme_reloaded.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const UiHelpers = preload("res://scripts/presentation/ui_signal_helpers.gd")

signal speed_changed(actor: Actor)   # emitted when inspector changes actor.speed

## Editable SpinBoxes when true; read-only Labels when false.
## Production arena scenes set dev_mode=false; Godmode scene leaves it true.
@export var dev_mode: bool = true

var _actor: Actor = null

# UI nodes — resolved in _ready, all must exist in actor_inspector.tscn
@onready var _label_id: Label        = $VBox/ActorSection/LabelId
@onready var _label_team: Label      = $VBox/ActorSection/LabelTeam
@onready var _spin_curr_hp: SpinBox  = $VBox/ActorSection/RowMaxHp/SpinCurrHp
@onready var _spin_max_hp: SpinBox   = $VBox/ActorSection/RowMaxHp/SpinMaxHp
@onready var _spin_damage: SpinBox   = $VBox/ActorSection/RowDamage/SpinDamage
@onready var _spin_speed: SpinBox    = $VBox/ActorSection/RowSpeed/SpinSpeed
@onready var _abilities_row: HBoxContainer = $VBox/ActorSection/AbilitiesRow
@onready var _actor_section: Control = $VBox/ActorSection
@onready var _hex_section: Control   = $VBox/HexSection
@onready var _label_hex_coord: Label = $VBox/HexSection/LabelHexCoord
@onready var _label_hex_kind: Label  = $VBox/HexSection/LabelHexKind
@onready var _label_hex_effect: Label = $VBox/HexSection/LabelHexEffect

# Team badge — small colored rect prepended to the actor section header.
var _team_badge: ColorRect

# Read-only Labels created at runtime when dev_mode=false. Mirror the SpinBox
# values; SpinBoxes themselves are hidden in that mode.
var _label_curr_hp_proxy: Label
var _label_max_hp_proxy: Label
var _label_damage_proxy: Label
var _label_speed_proxy: Label


func _ready() -> void:
	hide()
	add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	_setup_spinbox_ranges()
	_apply_label_palette()
	_create_team_badge()
	if not dev_mode:
		_create_readonly_proxies()
	# Both sections start hidden; shown by bind_* calls
	if _actor_section:
		_actor_section.hide()
	if _hex_section:
		_hex_section.hide()
	EventBus.ui_theme_reloaded.connect(_on_theme_reloaded)


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
		for spin in [_spin_max_hp, _spin_damage, _spin_speed, _spin_curr_hp]:
			if spin != null:
				spin.get_line_edit().release_focus()
		# Do NOT call accept_event — let the key fall through to _unhandled_input


func _setup_spinbox_ranges() -> void:
	_spin_curr_hp.min_value = 1;   _spin_curr_hp.max_value = 200; _spin_curr_hp.step = 1
	_spin_max_hp.min_value  = 1;   _spin_max_hp.max_value  = 200; _spin_max_hp.step  = 1
	_spin_damage.min_value  = 0;   _spin_damage.max_value  = 50;  _spin_damage.step  = 1
	_spin_speed.min_value   = 0;   _spin_speed.max_value   = 6;   _spin_speed.step   = 1
	_spin_curr_hp.rounded = true
	_spin_max_hp.rounded  = true
	_spin_damage.rounded  = true
	_spin_speed.rounded   = true
	_restrict_to_int(_spin_curr_hp)
	_restrict_to_int(_spin_max_hp)
	_restrict_to_int(_spin_damage)
	_restrict_to_int(_spin_speed)


## Apply UiTheme font size + color to all labels in the inspector.
## Overrides the .tscn-set theme overrides (which were set with literal Color()).
func _apply_label_palette() -> void:
	UiTheme.apply_label_kind(_label_id, "header")
	UiTheme.apply_label_kind(_label_team, "small")
	UiTheme.apply_label_kind(_label_hex_coord, "small")
	UiTheme.apply_label_kind(_label_hex_kind, "body")
	# Hex effect label keeps semantic color (debuff orange) — set explicitly.
	_label_hex_effect.add_theme_font_size_override("font_size", UiTheme.FS_SMALL)
	_label_hex_effect.add_theme_color_override("font_color", UiTheme.SEM_DEBUFF)
	# Section labels (LabelMaxHp, LabelDamage, LabelSpeed, LabelAbilities, HintLabel)
	# get repainted via _refresh_section_labels — they're tscn-built, fetch by path.
	_refresh_section_labels()


## Repaints labels that live inside .tscn rows (LabelMaxHp, LabelDamage, etc.)
## without us holding @onready refs to each.
func _refresh_section_labels() -> void:
	var sub_paths := [
		"VBox/ActorSection/RowMaxHp/LabelMaxHp",
		"VBox/ActorSection/RowDamage/LabelDamage",
		"VBox/ActorSection/RowSpeed/LabelSpeed",
		"VBox/ActorSection/LabelAbilities",
		"VBox/ActorSection/HintLabel",
	]
	for p in sub_paths:
		var n := get_node_or_null(p)
		if n is Label:
			# Section labels are "small" kind (TEXT_DIM, FS_SMALL) — except
			# row labels which are slightly bigger. For jam: all "small" is
			# acceptable, distinguishable enough.
			UiTheme.apply_label_kind(n, "small")


func _create_team_badge() -> void:
	# Small colored square prepended to the LabelId row.
	# We can't easily restructure the .tscn from code without breaking @onready
	# refs, so we add the badge as a sibling label-prefix: a HBox wrapper around
	# (badge, label_id). For jam: simplest path is a ColorRect added to
	# ActorSection above LabelId.
	_team_badge = ColorRect.new()
	_team_badge.custom_minimum_size = Vector2(UiTheme.SP_3, UiTheme.SP_3)
	_team_badge.color = UiTheme.TEAM_NEUTRAL
	_team_badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# Insert as the very first child of ActorSection (above LabelId).
	_actor_section.add_child(_team_badge)
	_actor_section.move_child(_team_badge, 0)


## Create read-only Label proxies and hide the SpinBoxes when dev_mode=false.
## Each proxy is added as a sibling of its SpinBox in the same row.
func _create_readonly_proxies() -> void:
	_label_curr_hp_proxy = _make_readonly_proxy("0")
	_label_max_hp_proxy  = _make_readonly_proxy("0")
	_label_damage_proxy  = _make_readonly_proxy("0")
	_label_speed_proxy   = _make_readonly_proxy("0")
	_spin_curr_hp.get_parent().add_child(_label_curr_hp_proxy)
	_spin_max_hp.get_parent().add_child(_label_max_hp_proxy)
	_spin_damage.get_parent().add_child(_label_damage_proxy)
	_spin_speed.get_parent().add_child(_label_speed_proxy)
	_spin_curr_hp.hide()
	_spin_max_hp.hide()
	_spin_damage.hide()
	_spin_speed.hide()


func _make_readonly_proxy(initial_text: String) -> Label:
	var lbl := Label.new()
	lbl.text = initial_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.apply_label_kind(lbl, "body")
	return lbl


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
	_team_badge.color = UiTheme.team_color(actor.team)
	_spin_curr_hp.set_value_no_signal(actor.hp)
	_spin_curr_hp.max_value = actor.max_hp
	_spin_max_hp.set_value_no_signal(actor.max_hp)
	_spin_damage.set_value_no_signal(actor.damage_bonus)
	_spin_speed.set_value_no_signal(actor.speed)

	actor.damaged.connect(_on_actor_damaged)
	actor.died.connect(_on_actor_died, CONNECT_ONE_SHOT)
	if dev_mode:
		_spin_curr_hp.value_changed.connect(_on_curr_hp_changed)
		_spin_max_hp.value_changed.connect(_on_max_hp_changed)
		_spin_damage.value_changed.connect(_on_damage_changed)
		_spin_speed.value_changed.connect(_on_speed_changed)

	_refresh_hp_label()
	_refresh_proxies()
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
	if dev_mode:
		if _spin_curr_hp.value_changed.is_connected(_on_curr_hp_changed):
			_spin_curr_hp.value_changed.disconnect(_on_curr_hp_changed)
		if _spin_max_hp.value_changed.is_connected(_on_max_hp_changed):
			_spin_max_hp.value_changed.disconnect(_on_max_hp_changed)
		if _spin_damage.value_changed.is_connected(_on_damage_changed):
			_spin_damage.value_changed.disconnect(_on_damage_changed)
		if _spin_speed.value_changed.is_connected(_on_speed_changed):
			_spin_speed.value_changed.disconnect(_on_speed_changed)


func _refresh_hp_label() -> void:
	if _actor == null:
		return
	_spin_curr_hp.max_value = _actor.max_hp
	_spin_curr_hp.set_value_no_signal(_actor.hp)
	_refresh_proxies()


func _refresh_proxies() -> void:
	if dev_mode or _actor == null:
		return
	if _label_curr_hp_proxy: _label_curr_hp_proxy.text = "%d" % _actor.hp
	if _label_max_hp_proxy:  _label_max_hp_proxy.text  = "%d" % _actor.max_hp
	if _label_damage_proxy:  _label_damage_proxy.text  = "%d" % _actor.damage_bonus
	if _label_speed_proxy:   _label_speed_proxy.text   = "%d" % _actor.speed


func _on_theme_reloaded() -> void:
	add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	_apply_label_palette()
	if _actor != null:
		_team_badge.color = UiTheme.team_color(_actor.team)


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
		UiTheme.apply_label_kind(none_lbl, "small")
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
	UiTheme.apply_button_styling(btn)
	return btn


func _build_tooltip(ability_id: StringName) -> String:
	# Try to get the ability from AbilityDatabase for richer info.
	# Phase 4 (T060) replaces this with a SkillTooltip Control rendering
	# modifier-aware breakdowns. For Phase 1 we keep the primitive text tooltip.
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

func _on_curr_hp_changed(value: float) -> void:
	if _actor == null:
		return
	_actor.hp = clampi(int(value), 1, _actor.max_hp)
	_actor.damaged.emit(_actor.actor_id, 0, _actor.hp)


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
