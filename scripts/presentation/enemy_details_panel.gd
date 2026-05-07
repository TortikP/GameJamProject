extends PanelContainer
## EnemyDetailsPanel — top-right hover-only panel showing the enemy under the
## cursor. Replaces the legacy ActorInspector (right-side full-height panel
## with editable SpinBoxes) with a compact horizontal corner widget.
##
## 049 / AC-4: hover-driven, never click-driven. HoverDispatcher pushes
## bind(actor) when the cursor enters an enemy's hex, unbind() when it
## leaves. No selection state, no Esc-clear, no SpinBoxes — just read.
##
## Layout (horizontal):
##   ┌──────────────────────────────────────────────────────────┐
##   │ [portrait]  bee_2 [team]    HP 12/20   [🐝 Sting (CD0)] │
##   │             [slow][poison]                              │
##   └──────────────────────────────────────────────────────────┘
##
## Subscribes to actor.damaged + actor.statuses_changed for live updates so
## a fresh hit on the hovered enemy shows up without per-frame rebuilds.

const SkillFormatter    = preload("res://scripts/presentation/skill_formatter.gd")
const SkillIconResolver = preload("res://scripts/presentation/skill_icon_resolver.gd")

@onready var _portrait_rect: TextureRect    = $HBox/Portrait
@onready var _name_label:    Label          = $HBox/Info/NameRow/NameLabel
@onready var _team_badge:    ColorRect      = $HBox/Info/NameRow/TeamBadge
@onready var _hp_label:      Label          = $HBox/Info/HpLabel
@onready var _status_strip:  HBoxContainer  = $HBox/Info/StatusStrip
@onready var _abilities_row: HBoxContainer  = $HBox/AbilitiesRow

var _actor: Actor = null


func _ready() -> void:
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	hide()


func _apply_theme() -> void:
	add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
	UiTheme.apply_label_kind(_name_label, "header")
	# 049b / T041: HP label bumped from "small" to "body" — was 14px next to a
	# 20px name + 16px ability row, lost the read order. Body keeps it under
	# the name visually but readable at default zoom.
	UiTheme.apply_label_kind(_hp_label, "body")


## Bind to the hovered enemy. Idempotent — re-binding the same actor is a
## no-op, re-binding a different actor disconnects the old signals first.
## Status strip is forwarded via its own bind_actor (signal-driven).
##
## Defensive: HoverDispatcher's per-frame loop can fire bind before our
## @onready vars resolve in some scene-tree timings. Same `is_node_ready`
## guard PSP uses.
func bind(actor: Actor) -> void:
	if not is_node_ready():
		ready.connect(bind.bind(actor), CONNECT_ONE_SHOT)
		return
	if _actor == actor:
		return
	if _actor != null:
		_disconnect_actor()
	_actor = actor
	if actor == null:
		hide()
		return
	# Connect HP + status update signals so the panel reflects live state
	# without per-frame polling.
	if not actor.damaged.is_connected(_on_actor_damaged):
		actor.damaged.connect(_on_actor_damaged)
	if actor.has_signal("statuses_changed") \
			and not actor.statuses_changed.is_connected(_on_actor_statuses_changed):
		actor.statuses_changed.connect(_on_actor_statuses_changed)
	# Reuse status_icon_strip's signal-driven binding so we get free updates
	# without re-implementing pill rebuild here.
	if _status_strip != null and _status_strip.has_method("bind_actor"):
		_status_strip.bind_actor(actor)
	_refresh_all()
	show()


## Detach. Leaves the panel hidden so HoverDispatcher's "no enemy under
## cursor" path falls through cleanly.
func unbind() -> void:
	if not is_node_ready():
		return
	if _actor != null:
		_disconnect_actor()
	_actor = null
	if _status_strip != null and _status_strip.has_method("unbind"):
		_status_strip.unbind()
	hide()


func _disconnect_actor() -> void:
	if not is_instance_valid(_actor):
		return
	if _actor.damaged.is_connected(_on_actor_damaged):
		_actor.damaged.disconnect(_on_actor_damaged)
	if _actor.has_signal("statuses_changed") \
			and _actor.statuses_changed.is_connected(_on_actor_statuses_changed):
		_actor.statuses_changed.disconnect(_on_actor_statuses_changed)


# 049 / T013: portrait pipeline. Try `assets/portraits/<actor_id>.png` —
# Katya may drop matching files later, JSON-driven path comes from
# enemy_data if/when we wire it. Failure → hide TextureRect (the layout
# has a fallback width via custom_minimum_size on its parent).
func _refresh_portrait() -> void:
	if _portrait_rect == null or _actor == null:
		return
	var path: String = "res://assets/portraits/%s.png" % String(_actor.actor_id)
	if ResourceLoader.exists(path):
		var tex = load(path)
		if tex is Texture2D:
			_portrait_rect.texture = tex
			_portrait_rect.visible = true
			return
	_portrait_rect.texture = null
	_portrait_rect.visible = false


func _refresh_all() -> void:
	if _actor == null:
		return
	_name_label.text = Localization.t(String(_actor.actor_id), String(_actor.actor_id))
	_team_badge.color = UiTheme.team_color(_actor.team)
	_refresh_hp()
	_refresh_portrait()
	_rebuild_abilities()


func _refresh_hp() -> void:
	if _actor == null or _hp_label == null:
		return
	_hp_label.text = Localization.tf("ui_enemy_details_hp", [_actor.hp, _actor.max_hp], "HP %d/%d")
	# HP-color tier (mirrors HealthBar / PSP).
	var ratio: float = float(_actor.hp) / max(1.0, float(_actor.max_hp))
	_hp_label.add_theme_color_override("font_color", UiTheme.hp_color_for(ratio))


# 049 / T014: abilities row — one pip per skill in actor.get_skills().
# Pip layout: HBox(IconRect or Letter, NameLabel + CD). Disabled (no LMB
# action — this panel is read-only). Tooltip on the pip button shows the
# full human description via format_skill_human.
func _rebuild_abilities() -> void:
	if _abilities_row == null:
		return
	for child in _abilities_row.get_children():
		child.queue_free()
	if _actor == null:
		return
	var skills: Array = _actor.get_loot_skills()
	if skills.is_empty():
		var none := Label.new()
		none.text = "—"
		UiTheme.apply_label_kind(none, "small")
		_abilities_row.add_child(none)
		return
	for sk_v in skills:
		var sk := sk_v as Skill
		if sk == null:
			continue
		_abilities_row.add_child(_make_pip(sk))


func _make_pip(skill: Skill) -> HBoxContainer:
	var pip := HBoxContainer.new()
	# 049b / T041: more spacing between letter and name; pips sat too tight
	# at SP_1 (4px) and the skills bled into each other.
	pip.add_theme_constant_override("separation", UiTheme.SP_2)
	# Icon — texture or single-letter fallback (consistent with HexTooltip
	# and TelegraphHex; the same SkillIconResolver path everywhere).
	var tex: Texture2D = SkillIconResolver.resolve(skill)
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# 049b / T041: 20→24px to balance against the larger name label.
		rect.custom_minimum_size = Vector2(24, 24)
		pip.add_child(rect)
	else:
		var lbl := Label.new()
		var nm: String = Localization.t(String(skill.name), String(skill.id))
		lbl.text = nm.substr(0, 1).to_upper() if not nm.is_empty() else "?"
		UiTheme.apply_label_kind(lbl, "header")
		pip.add_child(lbl)
	# Name + CD — name only when CD == 0; "(CD N/M)" when ticking.
	var name_lbl := Label.new()
	# 049b / T041: pip name from "small" (14px, dim) to "body" (16px, TEXT)
	# — names like "Бросок мяча" and "Сосать лапу" need to be legible
	# enough to scan during a tactical decision. Was the smallest text on
	# the panel; now reads cleanly next to the header letter.
	UiTheme.apply_label_kind(name_lbl, "body")
	var name_str: String = Localization.t(String(skill.name), String(skill.id))
	if skill.cooldown > 0:
		var cd_remaining: int = int(skill.get("_cd_remaining"))
		if cd_remaining > 0:
			name_str += "  (CD %d/%d)" % [cd_remaining, skill.cooldown]
	name_lbl.text = name_str
	# Native Godot tooltip — read-only hover description; no LMB needed
	# because this panel is hover-only (per AC-3 — selection is gone).
	name_lbl.tooltip_text = SkillFormatter.format_skill_human(skill)
	pip.add_child(name_lbl)
	return pip


func _on_actor_damaged(_id: StringName, _amount: int, _hp_left: int) -> void:
	_refresh_hp()


func _on_actor_statuses_changed(_id: StringName) -> void:
	# StatusIconStrip subscribes itself; this hook is here in case future UI
	# wants to react beyond the strip (e.g. flash the panel on stun).
	pass
