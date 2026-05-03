extends PanelContainer
## PlayerStatusPanel — bottom-left HUD panel showing player Actor's name, HP
## bar (text form), and active status icons.
##
## Binds to a player Actor via bind_player(actor). Listens to actor.damaged
## directly (and statuses_changed once 007 lands). On each event, refreshes
## the name+HP labels and the embedded StatusIconStrip.

const SkillFormatter = preload("res://scripts/presentation/skill_formatter.gd")

@onready var _name_label: Label = $VBox/NameLabel
@onready var _hp_label: Label   = $VBox/HpRow/HpLabel
@onready var _hp_value: Label   = $VBox/HpRow/HpValue
@onready var _strip: HBoxContainer = $VBox/StatusIconStrip
@onready var _spell_section: VBoxContainer = $VBox/SpellSection
@onready var _spell_header: Label = $VBox/SpellSection/SpellHeader
@onready var _spell_name: Label = $VBox/SpellSection/SpellName
@onready var _spell_desc: Label = $VBox/SpellSection/SpellDesc

var _actor: Actor = null

# 049 / AC-8: hover beats active. Slot bar emits slot_hovered/_unhovered;
# controller pipes into set_hover_spell. set_active_spell is unchanged callsite-
# wise (slot_activated). Both targets feed _refresh_spell_section so toggling
# either updates the visible text.
var _active_skill = null
var _hover_skill = null


func _ready() -> void:
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	# Spell section starts collapsed — no slot active means nothing to show.
	_spell_section.visible = false


func _apply_theme() -> void:
	add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	UiTheme.apply_label_kind(_name_label, "header")
	UiTheme.apply_label_kind(_hp_label, "small")
	UiTheme.apply_label_kind(_hp_value, "num_large")
	UiTheme.apply_label_kind(_spell_header, "small")
	UiTheme.apply_label_kind(_spell_name, "header")
	UiTheme.apply_label_kind(_spell_desc, "small")


## Bind to player actor. Auto-listens to damaged and statuses_changed
## (latter is a placeholder; emit is post-007 work).
##
## Safe to call before our own _ready: if @onready vars aren't resolved yet,
## defers the bind until the `ready` signal fires. Godmode_controller binds
## us from its _ready, which runs before HUD subtree's _ready (Godot calls
## _ready bottom-up per scene-tree order; sibling subtrees follow source order).
func bind_player(actor: Actor) -> void:
	if not is_node_ready():
		# CONNECT_ONE_SHOT so re-binding before _ready doesn't pile listeners.
		ready.connect(bind_player.bind(actor), CONNECT_ONE_SHOT)
		return
	if _actor == actor:
		return
	if _actor != null:
		_disconnect()
	_actor = actor
	if actor == null:
		hide()
		return
	_actor.damaged.connect(_on_damaged)
	# statuses_changed will be added on Actor in the status-system feature.
	# Until then, callers can push via push_statuses() below.
	_refresh_all()
	show()


func _disconnect() -> void:
	if not is_instance_valid(_actor):
		_actor = null
		return
	if _actor.damaged.is_connected(_on_damaged):
		_actor.damaged.disconnect(_on_damaged)


## Until status system lands, allow caller to push test data.
func push_statuses(entries: Array) -> void:
	if _strip and _strip.has_method("set_statuses"):
		_strip.set_statuses(entries)


## Show description of currently selected skill. Pass null to clear (e.g.,
## on slot deselect). Same defensive guard as bind_player — caller may
## invoke from another node's _ready before our @onready resolves.
##
## Accepts Skill objects (post-007); legacy Ability objects also work
## because format helper duck-types `.id` and either `.abilities[]` (Skill)
## or falls back to per-ability formatting.
func set_active_spell(skill_or_ability) -> void:
	if not is_node_ready():
		ready.connect(set_active_spell.bind(skill_or_ability), CONNECT_ONE_SHOT)
		return
	_active_skill = skill_or_ability
	_refresh_spell_section()


## 049 / AC-8: per-slot hover description. Hovered skill takes priority over
## active selection — moving the cursor across slots previews each spell
## without committing. Pass null on mouse_exited to fall back to active.
func set_hover_spell(skill) -> void:
	if not is_node_ready():
		ready.connect(set_hover_spell.bind(skill), CONNECT_ONE_SHOT)
		return
	_hover_skill = skill
	_refresh_spell_section()


## 049: shared rebuild path for active + hover. Hover beats active; both
## null hides the section.
func _refresh_spell_section() -> void:
	var s = _hover_skill if _hover_skill != null else _active_skill
	if s == null:
		_spell_section.visible = false
		return
	# Header — localised name + CD when active. Same compact "name (CD x/y)"
	# convention format_skill uses on its first line, kept inline because
	# format_skill_human bakes CD into the body string and the header label
	# wants name-only.
	var display_name: String = Localization.t(String(s.name), String(s.id))
	if "cooldown" in s and s.cooldown > 0:
		var cd_remaining: int = int(s.get("_cd_remaining"))
		if cd_remaining > 0:
			display_name += "  (CD %d/%d)" % [cd_remaining, s.cooldown]
		else:
			display_name += "  (CD %d)" % s.cooldown
	_spell_name.text = display_name
	# Body — human-readable per AC-1. format_skill_human collapses to the
	# Localization.t(skill.tooltip) string (or [ДОБАВИТЬ] placeholder when
	# the key is missing) so designers see un-authored skills immediately.
	# Bare-Ability legacy callers (no .abilities[]) still fall through to
	# the structural format_ability path so they don't 500.
	var has_abilities: bool = "abilities" in s
	if has_abilities:
		_spell_desc.text = SkillFormatter.format_skill_human(s)
	else:
		_spell_desc.text = "\n".join(SkillFormatter.format_ability(s))
	_spell_section.visible = true


func _refresh_all() -> void:
	if _actor == null:
		return
	_name_label.text = String(_actor.actor_id)
	_hp_value.text = "%d/%d" % [_actor.hp, _actor.max_hp]
	# Color HP value by threshold (mirrors HealthBar logic).
	var ratio: float = float(_actor.hp) / max(1.0, float(_actor.max_hp))
	_hp_value.add_theme_color_override("font_color", UiTheme.hp_color_for(ratio))


func _on_damaged(_id: StringName, _amount: int, _hp_left: int) -> void:
	_refresh_all()
