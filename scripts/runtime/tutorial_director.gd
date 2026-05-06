extends CanvasLayer
## TutorialDirector -- friendly, state-based guidance for the tutorial mission.

const TutorialHexHighlight = preload("res://scripts/presentation/tutorial_hex_highlight.gd")

const MELEE_RANGE := 1
const RANGED_RANGE := 2
const UNSEEN_TIP_BONUS := 60
const SIDE_PANEL_RIGHT := -16.0
const SIDE_PANEL_WIDTH := 280.0
const SIDE_PANEL_LEFT := SIDE_PANEL_RIGHT - SIDE_PANEL_WIDTH
const HINT_PANEL_TOP := 190.0
const HINT_MARGIN_EXPANDED := 12
const HINT_MARGIN_COLLAPSED := 4
const CHECKLIST_ITEMS := [
	{"id": &"movement", "key": "ui_tutorial_checklist_movement"},
	{"id": &"melee", "key": "ui_tutorial_checklist_melee"},
	{"id": &"ranged", "key": "ui_tutorial_checklist_ranged"},
	{"id": &"self_effect", "key": "ui_tutorial_checklist_self_effect"},
	{"id": &"left_threat", "key": "ui_tutorial_checklist_left_threat"},
	{"id": &"kill", "key": "ui_tutorial_checklist_kill"},
	{"id": &"skill", "key": "ui_tutorial_checklist_active_skill"},
	{"id": &"passive_skill", "key": "ui_tutorial_checklist_passive_skill"},
]

const WAVE_SPAWN_HINTS := [
	Vector2i(4, 1),
	Vector2i(2, 1),
	Vector2i(3, 2),
	Vector2i(4, 0),
]

var _ctrl: Node = null
var _highlight: Node = null
var _panel: PanelContainer = null
var _hint_margin: MarginContainer = null
var _title: Label = null
var _body: Label = null
var _footer: Label = null
var _collapse_button: Button = null
var _hint_content_box: VBoxContainer = null
var _checklist_panel: PanelContainer = null
var _checklist_labels: Dictionary = {}
var _checklist_done: Dictionary = {}
var _slot_markers: Array[Panel] = []
var _slot_indices: Array[int] = []
var _current_wave: int = -1
var _current_tip: StringName = &""
var _seen_tips: Dictionary = {}
var _player_was_threatened: bool = false
var _hint_collapsed: bool = false
var _in_skill_offer: bool = false
var _level_done: bool = false
var _reevaluate_in: float = 0.0


func setup(ctrl: Node, _level: LevelData) -> void:
	_ctrl = ctrl
	layer = 85
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_build_checklist()
	_build_world_highlight()
	_connect_events()
	_evaluate_guidance.call_deferred()


func _process(delta: float) -> void:
	_refresh_slot_markers()
	_reevaluate_in -= delta
	if _reevaluate_in <= 0.0:
		_reevaluate_in = 0.15
		_evaluate_guidance()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(SIDE_PANEL_WIDTH, 0)
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = SIDE_PANEL_LEFT
	_panel.offset_right = SIDE_PANEL_RIGHT
	_panel.offset_top = HINT_PANEL_TOP
	_panel.offset_bottom = 0
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)

	_hint_margin = MarginContainer.new()
	_hint_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_child(_hint_margin)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", UiTheme.SP_2)
	_hint_margin.add_child(box)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", UiTheme.SP_2)
	header.clip_contents = true
	box.add_child(header)

	_title = Label.new()
	_title.custom_minimum_size = Vector2(0, 0)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_title)

	_collapse_button = Button.new()
	_collapse_button.custom_minimum_size = Vector2(34, 28)
	_collapse_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_collapse_button.focus_mode = Control.FOCUS_NONE
	_collapse_button.pressed.connect(_toggle_hint_collapsed)
	header.add_child(_collapse_button)

	_hint_content_box = VBoxContainer.new()
	_hint_content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_content_box.add_theme_constant_override("separation", UiTheme.SP_2)
	box.add_child(_hint_content_box)

	_body = Label.new()
	_body.custom_minimum_size = Vector2(0, 0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_content_box.add_child(_body)

	_footer = Label.new()
	_footer.custom_minimum_size = Vector2(0, 0)
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_content_box.add_child(_footer)

	_apply_theme()
	_refresh_hint_collapse()
	EventBus.ui_theme_reloaded.connect(_apply_theme)


func _build_checklist() -> void:
	_checklist_panel = PanelContainer.new()
	_checklist_panel.custom_minimum_size = Vector2(SIDE_PANEL_WIDTH, 0)
	_checklist_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_checklist_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_checklist_panel.offset_left = SIDE_PANEL_LEFT
	_checklist_panel.offset_right = SIDE_PANEL_RIGHT
	_checklist_panel.offset_top = 16
	_checklist_panel.offset_bottom = 0
	_checklist_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_checklist_panel)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", UiTheme.SP_2)
	margin.add_theme_constant_override("margin_top", UiTheme.SP_2)
	margin.add_theme_constant_override("margin_right", UiTheme.SP_2)
	margin.add_theme_constant_override("margin_bottom", UiTheme.SP_2)
	_checklist_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = Localization.t("ui_tutorial_checklist_title", "Tutorial")
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.clip_text = true
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(heading)
	_checklist_labels[&"_heading"] = heading

	for item in CHECKLIST_ITEMS:
		var id: StringName = item.id
		var label := Label.new()
		label.text = ""
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(label)
		_checklist_labels[id] = label
		_checklist_done[id] = false

	_apply_theme()
	_refresh_checklist()


func _build_world_highlight() -> void:
	if _ctrl == null or _ctrl.grid == null:
		return
	_highlight = TutorialHexHighlight.new()
	_highlight.name = "TutorialHexHighlight"
	_highlight.z_index = 12
	_ctrl.grid.add_child(_highlight)
	_highlight.setup(_ctrl.grid)


func _connect_events() -> void:
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.actor_moved.connect(_on_actor_changed)
	EventBus.actor_spawned.connect(_on_actor_spawned)
	EventBus.skill_cast.connect(_on_skill_cast)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.heal_done.connect(_on_heal_done)
	EventBus.actor_died_snapshot.connect(_on_actor_died_snapshot)
	EventBus.actor_died.connect(_on_actor_died)
	EventBus.player_turn_ended.connect(_on_turn_changed)
	EventBus.world_turn_ended.connect(_on_turn_changed)
	EventBus.skill_offer_about_to_open.connect(_on_skill_offer_about_to_open)
	EventBus.skill_offer_closed.connect(_on_skill_offer_closed)
	EventBus.level_completed.connect(_on_level_completed)


func _apply_theme() -> void:
	if _panel != null:
		_panel.add_theme_stylebox_override("panel", UiTheme.make_modal_stylebox())
	if _title != null:
		UiTheme.apply_label_kind(_title, "body")
	if _body != null:
		UiTheme.apply_label_kind(_body, "body")
	if _footer != null:
		UiTheme.apply_label_kind(_footer, "small")
		_footer.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	if _collapse_button != null:
		UiTheme.apply_button_styling(_collapse_button)
		_refresh_hint_collapse()
	for marker in _slot_markers:
		_apply_marker_theme(marker)
	if _checklist_panel != null:
		_checklist_panel.add_theme_stylebox_override("panel", UiTheme.make_modal_stylebox())
	var heading := _checklist_labels.get(&"_heading", null) as Label
	if heading != null:
		UiTheme.apply_label_kind(heading, "small")
		heading.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	for item in CHECKLIST_ITEMS:
		var label := _checklist_labels.get(item.id, null) as Label
		if label != null:
			UiTheme.apply_label_kind(label, "small")
	_refresh_checklist()


func _refresh_checklist() -> void:
	if _checklist_labels.is_empty():
		return
	var heading := _checklist_labels.get(&"_heading", null) as Label
	if heading != null:
		heading.text = Localization.t("ui_tutorial_checklist_title", "Tutorial")
	for item in CHECKLIST_ITEMS:
		var id: StringName = item.id
		var label := _checklist_labels.get(id, null) as Label
		if label == null:
			continue
		var done := bool(_checklist_done.get(id, false))
		var prefix := "[x] " if done else "[ ] "
		label.text = prefix + Localization.t(item.key, String(item.key))
		label.add_theme_color_override("font_color", UiTheme.TEXT_DIM if done else UiTheme.TEXT)


func _complete_check(id: StringName) -> void:
	if not _checklist_done.has(id) or bool(_checklist_done[id]):
		return
	_checklist_done[id] = true
	_refresh_checklist()


func _complete_skill_role(skill_id: StringName) -> void:
	var skill: Skill = SkillDatabase.get_skill(skill_id)
	if skill == null:
		return
	if _skill_matches_role(skill, &"melee"):
		_complete_check(&"melee")
	if _skill_matches_role(skill, &"ranged"):
		_complete_check(&"ranged")
	if _skill_matches_role(skill, &"heal"):
		_complete_check(&"self_effect")


func _apply_marker_theme(marker: Panel) -> void:
	if marker == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(3)
	sb.border_color = UiTheme.FOCUS
	marker.add_theme_stylebox_override("panel", sb)


func _toggle_hint_collapsed() -> void:
	_hint_collapsed = not _hint_collapsed
	_refresh_hint_collapse()


func _refresh_hint_collapse() -> void:
	if _panel != null:
		_panel.custom_minimum_size = Vector2(SIDE_PANEL_WIDTH, 0)
		_panel.offset_left = SIDE_PANEL_LEFT
		_panel.offset_right = SIDE_PANEL_RIGHT
		_panel.offset_top = HINT_PANEL_TOP
		_panel.offset_bottom = 0
	if _hint_margin != null:
		var margin := HINT_MARGIN_COLLAPSED if _hint_collapsed else HINT_MARGIN_EXPANDED
		_hint_margin.add_theme_constant_override("margin_left", margin)
		_hint_margin.add_theme_constant_override("margin_top", margin)
		_hint_margin.add_theme_constant_override("margin_right", margin)
		_hint_margin.add_theme_constant_override("margin_bottom", margin)
	if _hint_content_box != null:
		_hint_content_box.visible = not _hint_collapsed
	if _collapse_button != null:
		_collapse_button.custom_minimum_size = Vector2(30, 22) if _hint_collapsed else Vector2(34, 28)
		_collapse_button.text = "+" if _hint_collapsed else "-"
		if _hint_collapsed:
			_collapse_button.tooltip_text = Localization.t("ui_tutorial_expand_hint", "Expand hint")
		else:
			_collapse_button.tooltip_text = Localization.t("ui_tutorial_collapse_hint", "Collapse hint")


func _evaluate_guidance() -> void:
	if _level_done or _in_skill_offer or _ctrl == null or _ctrl.grid == null:
		return
	var player: Actor = _ctrl.player as Actor
	if player == null or not player.is_alive():
		return

	var candidates: Array[Dictionary] = []
	if _current_wave >= 0 and not bool(_checklist_done.get(&"movement", false)):
		var move_target := _next_pending_spawn_coord()
		if move_target == Vector2i(-1, -1):
			move_target = _spawn_hint_for_wave()
		candidates.append(_candidate(
				&"move",
				"ui_tutorial_move_title",
				"ui_tutorial_move_body",
				220,
				_reachable_move_hexes_toward(player, move_target),
				[]))

	var threat := _incoming_threat(player)
	if not threat.is_empty():
		var threat_priority: int = 5
		var threat_is_new: bool = not _seen_tips.has(&"threat")
		var melee_on_cooldown := _all_slots_on_cooldown(_skill_slots_by_role(&"melee"))
		var lethal_threat := int(threat.get("damage", 0)) >= player.hp
		if threat_is_new:
			threat_priority = 130
		elif melee_on_cooldown or lethal_threat:
			threat_priority = 160
		candidates.append(_candidate(
				&"threat",
				"ui_tutorial_threat_title",
				"ui_tutorial_threat_body",
				threat_priority,
				threat.get("hexes", []),
				[]))

	if player.hp < player.max_hp:
		candidates.append(_candidate(
				&"heal",
				"ui_tutorial_heal_title",
				"ui_tutorial_heal_body",
				90,
				[_ctrl.grid.get_coord(player.actor_id)],
				_skill_slots_by_role(&"heal")))

	var enemy: Actor = _nearest_enemy()
	if enemy == null:
		_add_no_enemy_candidate(candidates, player)
	else:
		_add_enemy_distance_candidates(candidates, player, enemy)

	if candidates.is_empty():
		_hide_guidance()
		_ensure_empty_wave_can_finish()
		return

	var best := _pick_best_candidate(candidates)
	_show_candidate(best)


func _candidate(id: StringName, title_key: String, body_key: String, priority: int, hexes: Array, slots: Array) -> Dictionary:
	var score := priority
	if not _seen_tips.has(id):
		score += UNSEEN_TIP_BONUS
	return {
		"id": id,
		"title_key": title_key,
		"body_key": body_key,
		"score": score,
		"hexes": hexes,
		"slots": slots,
	}


func _add_no_enemy_candidate(candidates: Array[Dictionary], player: Actor) -> void:
	if _has_pending_spawns():
		var target := _next_pending_spawn_coord()
		if target == Vector2i(-1, -1):
			target = _spawn_hint_for_wave()
		var player_coord: Vector2i = _ctrl.grid.get_coord(player.actor_id)
		var dist: int = _ctrl.grid.hex_distance(player_coord, target) if target != Vector2i(-1, -1) else -1
		if dist > RANGED_RANGE:
			candidates.append(_candidate(
					&"far_marker",
					"ui_tutorial_far_title",
					"ui_tutorial_far_body",
					60,
					_move_hexes_toward(target),
					_skill_slots_by_role(&"ranged")))
		else:
			candidates.append(_candidate(
					&"wait",
					"ui_tutorial_wait_title",
					"ui_tutorial_wait_body",
					40,
					[target] if target != Vector2i(-1, -1) else [],
					[]))
	else:
		candidates.append(_candidate(
				&"wave_clear",
				"ui_tutorial_wave_clear_title",
				"ui_tutorial_wave_clear_body",
				20,
				[],
				[]))
		_ensure_empty_wave_can_finish()


func _add_enemy_distance_candidates(candidates: Array[Dictionary], player: Actor, enemy: Actor) -> void:
	var player_coord: Vector2i = _ctrl.grid.get_coord(player.actor_id)
	var enemy_coord: Vector2i = _ctrl.grid.get_coord(enemy.actor_id)
	var distance: int = _ctrl.grid.hex_distance(player_coord, enemy_coord)
	if distance < 0:
		candidates.append(_candidate(
				&"far",
				"ui_tutorial_far_title",
				"ui_tutorial_far_body",
				60,
				_move_hexes_toward(enemy_coord),
				_skill_slots_by_role(&"ranged")))
	elif distance <= MELEE_RANGE:
		var melee_slots := _skill_slots_by_role(&"melee")
		if _all_slots_on_cooldown(melee_slots):
			candidates.append(_candidate(
					&"melee_cd",
					"ui_tutorial_cooldown_title",
					"ui_tutorial_melee_cooldown_body",
					80,
					_move_hexes_toward(enemy_coord),
					melee_slots))
		else:
			candidates.append(_candidate(
					&"melee",
					"ui_tutorial_melee_title",
					"ui_tutorial_melee_body",
					70,
					[enemy_coord],
					melee_slots))
	elif distance <= RANGED_RANGE:
		var ranged_slots := _skill_slots_by_role(&"ranged")
		if _all_slots_on_cooldown(ranged_slots):
			candidates.append(_candidate(
					&"ranged_cd",
					"ui_tutorial_cooldown_title",
					"ui_tutorial_ranged_cooldown_body",
					80,
					_move_hexes_toward(enemy_coord),
					ranged_slots))
		else:
			candidates.append(_candidate(
					&"ranged",
					"ui_tutorial_ranged_title",
					"ui_tutorial_ranged_body",
					70,
					[enemy_coord],
					ranged_slots))
	else:
		candidates.append(_candidate(
				&"far",
				"ui_tutorial_far_title",
				"ui_tutorial_far_body",
				60,
				_move_hexes_toward(enemy_coord),
				_skill_slots_by_role(&"ranged")))


func _pick_best_candidate(candidates: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = candidates[0]
	for candidate in candidates:
		if int(candidate.score) > int(best.score):
			best = candidate
	return best


func _show_candidate(candidate: Dictionary) -> void:
	var id: StringName = candidate.id
	if _title == null or _body == null or _footer == null:
		return
	if _current_tip != id:
		_title.text = Localization.t(candidate.title_key, candidate.title_key)
		_title.tooltip_text = _title.text
		_body.text = Localization.t(candidate.body_key, candidate.body_key)
		_footer.text = Localization.t("ui_tutorial_footer_default", "You can keep playing while this hint is visible.")
		_current_tip = id
		_seen_tips[id] = true
		_panel.show()
	_set_hexes(candidate.hexes)
	_set_slots(candidate.slots)


func _hide_guidance() -> void:
	_current_tip = &""
	_clear_hexes()
	_set_slots([])
	if _panel != null:
		_panel.hide()


func _set_hexes(hexes: Array) -> void:
	if _highlight != null and _highlight.has_method("set_hexes"):
		_highlight.set_hexes(hexes)


func _clear_hexes() -> void:
	if _highlight != null and _highlight.has_method("clear"):
		_highlight.clear()


func _set_slots(indices: Array) -> void:
	_slot_indices.clear()
	for idx_v in indices:
		var idx := int(idx_v)
		if idx >= 0 and not _slot_indices.has(idx):
			_slot_indices.append(idx)
	_refresh_slot_markers()


func _refresh_slot_markers() -> void:
	while _slot_markers.size() < _slot_indices.size():
		var marker := Panel.new()
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.visible = false
		add_child(marker)
		_slot_markers.append(marker)
		_apply_marker_theme(marker)
	for i in _slot_markers.size():
		var marker := _slot_markers[i]
		if i >= _slot_indices.size() or _ctrl == null or _ctrl.slot_bar == null:
			marker.hide()
			continue
		var button := _ctrl.slot_bar.get_child(_slot_indices[i]) as Control
		if button == null:
			marker.hide()
			continue
		var rect: Rect2 = button.get_global_rect()
		marker.global_position = rect.position - Vector2(5, 5)
		marker.size = rect.size + Vector2(10, 10)
		marker.show()


func _skill_slots_by_role(role: StringName) -> Array:
	var result: Array = []
	if _ctrl == null or _ctrl.slot_bar == null:
		return result
	for i in 4:
		var skill := _ctrl.slot_bar.get_slot(i) as Skill
		if skill == null:
			continue
		if _skill_matches_role(skill, role):
			result.append(i)
	return result


func _skill_matches_role(skill: Skill, role: StringName) -> bool:
	if skill == null:
		return false
	if role == &"heal":
		return skill.behaviour_tags.has(&"heal")
	if role == &"ranged" and skill.behaviour_tags.has(&"ranged"):
		return true
	if role == &"melee" and skill.behaviour_tags.has(&"melee"):
		return true
	var range := _skill_first_target_range(skill)
	if role == &"ranged":
		return range > MELEE_RANGE
	if role == &"melee":
		return range == MELEE_RANGE and skill.behaviour_tags.has(&"damage")
	return false


func _skill_first_target_range(skill: Skill) -> int:
	if skill == null or skill.abilities.is_empty():
		return -1
	var ability := skill.abilities[0] as Ability
	if ability == null or ability.target == null:
		return -1
	if "range" in ability.target:
		return int(ability.target.range)
	return -1


func _all_slots_on_cooldown(slots: Array) -> bool:
	if slots.is_empty() or _ctrl == null or _ctrl.slot_bar == null:
		return false
	for idx_v in slots:
		var skill := _ctrl.slot_bar.get_slot(int(idx_v)) as Skill
		if skill != null and skill.is_ready():
			return false
	return true


func _incoming_threat(player: Actor) -> Dictionary:
	if _ctrl == null or _ctrl.registry == null or _ctrl.grid == null:
		_player_was_threatened = false
		return {}
	var player_coord: Vector2i = _ctrl.grid.get_coord(player.actor_id)
	if player_coord == Vector2i(-1, -1):
		_player_was_threatened = false
		return {}
	var threatened: Dictionary = {}
	var threat_damage: int = 0
	for actor_v in _ctrl.registry.all():
		if not (actor_v is Actor):
			continue
		var enemy: Actor = actor_v
		if enemy == player or enemy.team != &"enemy" or not enemy.is_alive():
			continue
		var intent_v: Variant = enemy.cast_intent
		if intent_v == null:
			continue
		var ci := intent_v as CastIntent
		if ci == null or not ci.is_valid():
			continue
		var intent_hexes: Array = _threat_hexes_for_intent(enemy, ci, player_coord)
		for c in intent_hexes:
			threatened[c] = true
		if intent_hexes.has(player_coord):
			threat_damage += _predicted_intent_damage(enemy, ci, player)
	if not threatened.has(player_coord):
		if _player_was_threatened:
			_complete_check(&"left_threat")
		_player_was_threatened = false
		return {}
	_player_was_threatened = true
	var safe: Array = _safe_move_hexes(player, threatened)
	var hexes: Array = [player_coord]
	for c in safe:
		hexes.append(c)
	return {"hexes": hexes, "damage": threat_damage}


func _threat_hexes_for_intent(enemy: Actor, ci: CastIntent, player_coord_override: Vector2i = Vector2i(-1, -1)) -> Array:
	var result: Array = []
	var skill: Skill = SkillDatabase.get_skill(ci.skill_id)
	if skill == null:
		return result
	var caster_coord: Vector2i = _ctrl.grid.get_coord(enemy.actor_id)
	var coord: Vector2i = ci.target_coord
	if ci.target_id != &"":
		if ci.target_id == &"player" and player_coord_override != Vector2i(-1, -1):
			coord = player_coord_override
		else:
			var live: Vector2i = _ctrl.grid.get_coord(ci.target_id)
			if live != Vector2i(-1, -1):
				coord = live
	for ability_v in skill.abilities:
		var ability := ability_v as Ability
		if ability == null:
			continue
		var anchor := coord
		if ability.target != null:
			var range_hexes: Array[Vector2i] = ability.target.get_range_hexes(caster_coord, _ctrl.grid)
			if not range_hexes.has(coord):
				continue
			anchor = ability.target.preview_anchor_coord(caster_coord, coord)
		if ability.area != null:
			for c in ability.area.get_affected_hexes(caster_coord, anchor, _ctrl.grid):
				if not result.has(c):
					result.append(c)
		elif not result.has(anchor):
			result.append(anchor)
	return result


func _predicted_intent_damage(enemy: Actor, ci: CastIntent, player: Actor) -> int:
	var skill: Skill = SkillDatabase.get_skill(ci.skill_id)
	if skill == null:
		return 0
	return skill.predicted_damage_to(enemy, player, {})


func _safe_move_hexes(player: Actor, _threatened: Dictionary) -> Array:
	var result: Array = []
	var player_coord: Vector2i = _ctrl.grid.get_coord(player.actor_id)
	var occupied: Array = []
	for actor_v in _ctrl.registry.all():
		if actor_v is Actor:
			var actor: Actor = actor_v
			if actor.actor_id != player.actor_id and actor.is_alive():
				var coord: Vector2i = _ctrl.grid.get_coord(actor.actor_id)
				if coord != Vector2i(-1, -1):
					occupied.append(coord)
	var reachable: Array = _ctrl.grid.reachable_within(player_coord, player.effective_speed(), occupied)
	for coord_v in reachable:
		var coord: Vector2i = coord_v
		if not _would_player_be_hit_at(coord):
			result.append(coord)
			if result.size() >= 3:
				break
	return result


func _would_player_be_hit_at(coord: Vector2i) -> bool:
	if _ctrl == null or _ctrl.registry == null:
		return false
	for actor_v in _ctrl.registry.all():
		if not (actor_v is Actor):
			continue
		var enemy: Actor = actor_v
		if enemy.team != &"enemy" or not enemy.is_alive():
			continue
		var intent_v: Variant = enemy.cast_intent
		if intent_v == null:
			continue
		var ci := intent_v as CastIntent
		if ci == null or not ci.is_valid():
			continue
		if _threat_hexes_for_intent(enemy, ci, coord).has(coord):
			return true
	return false


func _nearest_enemy() -> Actor:
	if _ctrl == null or _ctrl.registry == null or _ctrl.grid == null:
		return null
	var player: Actor = _ctrl.player as Actor
	if player == null:
		return null
	var player_coord: Vector2i = _ctrl.grid.get_coord(player.actor_id)
	var best: Actor = null
	var best_distance := 0x7fffffff
	for actor_v in _ctrl.registry.all():
		if not (actor_v is Actor):
			continue
		var actor: Actor = actor_v
		if actor.team != &"enemy" or not actor.is_alive():
			continue
		var coord: Vector2i = _ctrl.grid.get_coord(actor.actor_id)
		var distance: int = _ctrl.grid.hex_distance(player_coord, coord)
		if distance >= 0 and distance < best_distance:
			best = actor
			best_distance = distance
	return best


func _move_hexes_toward(target: Vector2i) -> Array:
	var result: Array = [target]
	if _ctrl == null or _ctrl.grid == null or _ctrl.registry == null:
		return result
	var player: Actor = _ctrl.player as Actor
	if player == null:
		return result
	var player_coord: Vector2i = _ctrl.grid.get_coord(player.actor_id)
	if player_coord == Vector2i(-1, -1):
		return result
	var occupied: Array = []
	for actor_v in _ctrl.registry.all():
		if actor_v is Actor:
			var actor: Actor = actor_v
			if actor.actor_id != player.actor_id and actor.is_alive():
				var coord: Vector2i = _ctrl.grid.get_coord(actor.actor_id)
				if coord != Vector2i(-1, -1):
					occupied.append(coord)
	var reachable: Array = _ctrl.grid.reachable_within(player_coord, player.effective_speed(), occupied)
	var best: Array = []
	var best_distance := 0x7fffffff
	for coord_v in reachable:
		var coord: Vector2i = coord_v
		var d: int = _ctrl.grid.hex_distance(coord, target)
		if d < 0:
			continue
		if d < best_distance:
			best_distance = d
			best = [coord]
		elif d == best_distance and best.size() < 2:
			best.append(coord)
	for coord in best:
		if not result.has(coord):
			result.append(coord)
	return result


func _reachable_move_hexes_toward(player: Actor, target: Vector2i) -> Array:
	if player == null or _ctrl == null or _ctrl.grid == null or _ctrl.registry == null:
		return []
	var player_coord: Vector2i = _ctrl.grid.get_coord(player.actor_id)
	if player_coord == Vector2i(-1, -1):
		return []
	var occupied: Array = []
	for actor_v in _ctrl.registry.all():
		if actor_v is Actor:
			var actor: Actor = actor_v
			if actor.actor_id != player.actor_id and actor.is_alive():
				var coord: Vector2i = _ctrl.grid.get_coord(actor.actor_id)
				if coord != Vector2i(-1, -1):
					occupied.append(coord)
	var reachable: Array = _ctrl.grid.reachable_within(player_coord, player.effective_speed(), occupied)
	if reachable.is_empty():
		return []
	if target == Vector2i(-1, -1):
		return [reachable[0]]
	var best: Array = []
	var best_distance := 0x7fffffff
	for coord_v in reachable:
		var coord: Vector2i = coord_v
		if coord == player_coord:
			continue
		var d: int = _ctrl.grid.hex_distance(coord, target)
		if d < 0:
			continue
		if d < best_distance:
			best_distance = d
			best = [coord]
		elif d == best_distance and best.size() < 2:
			best.append(coord)
	if best.is_empty():
		for coord_v in reachable:
			var coord: Vector2i = coord_v
			if coord != player_coord:
				best.append(coord)
				break
	return best


func _has_pending_spawns() -> bool:
	var pending := _pending_spawners()
	return pending.size() > 0


func _next_pending_spawn_coord() -> Vector2i:
	var pending := _pending_spawners()
	if pending.is_empty():
		return Vector2i(-1, -1)
	var best_time := 0x7fffffff
	var best_coord := Vector2i(-1, -1)
	for entry_v in pending:
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v
		var timer := int(entry.get("timer", 1))
		if timer < best_time:
			best_time = timer
			best_coord = entry.get("coord", Vector2i(-1, -1))
	return best_coord


func _pending_spawners() -> Array:
	if _ctrl == null or _ctrl.wave_controller == null:
		return []
	var pending_v: Variant = _ctrl.wave_controller.get("_pending_spawners")
	if pending_v is Array:
		return pending_v
	return []


func _spawn_hint_for_wave() -> Vector2i:
	if _current_wave < 0 or _current_wave >= WAVE_SPAWN_HINTS.size():
		return Vector2i(-1, -1)
	return WAVE_SPAWN_HINTS[_current_wave]


func _ensure_empty_wave_can_finish() -> void:
	if _ctrl == null or _ctrl.wave_controller == null:
		return
	if _nearest_enemy() != null or _has_pending_spawns():
		return
	if _ctrl.wave_controller.has_method("_check_auto_clear"):
		_ctrl.wave_controller.call_deferred("_check_auto_clear")


func _on_wave_started(index: int, _is_special: bool) -> void:
	_current_wave = index
	_current_tip = &""
	_evaluate_guidance.call_deferred()


func _on_actor_changed(_actor_id: StringName, _from: Vector2i, _to: Vector2i) -> void:
	if _actor_id == &"player":
		_complete_check(&"movement")
	_evaluate_guidance.call_deferred()


func _on_actor_spawned(_actor_id: StringName) -> void:
	_evaluate_guidance.call_deferred()


func _on_skill_cast(caster_id: StringName, skill_id: StringName, target_ids: Array) -> void:
	if caster_id == &"player":
		_complete_skill_role(skill_id)
		if target_ids.has(&"player") or target_ids.has("player"):
			_complete_check(&"self_effect")
		_evaluate_guidance.call_deferred()


func _on_damage_dealt(_target_id: StringName, _amount: int, _world_pos: Vector2) -> void:
	_evaluate_guidance.call_deferred()


func _on_heal_done(target_id: StringName, _amount: int, _world_pos: Vector2) -> void:
	if target_id == &"player":
		_complete_check(&"self_effect")
	_evaluate_guidance.call_deferred()


func _on_actor_died_snapshot(_actor_id: StringName, team: StringName, _skill_ids: Array) -> void:
	if team == &"enemy":
		_complete_check(&"kill")


func _on_actor_died(_actor_id: StringName) -> void:
	_evaluate_guidance.call_deferred()


func _on_turn_changed(_turn: int) -> void:
	_evaluate_guidance.call_deferred()


func _on_skill_offer_about_to_open(_wave_index: int, _count: int, _pool_id: StringName) -> void:
	_in_skill_offer = true
	var candidate := _candidate(
			&"skill_offer",
			"ui_tutorial_skill_offer_title",
			"ui_tutorial_skill_offer_body",
			120,
			[],
			[])
	_show_candidate(candidate)


func _on_skill_offer_closed(_wave_index: int, _picked_skill_id: StringName, _mode: StringName) -> void:
	_in_skill_offer = false
	if _picked_skill_id != &"":
		var picked: Skill = SkillDatabase.get_skill(_picked_skill_id)
		if picked != null and picked.is_passive():
			_complete_check(&"passive_skill")
		else:
			_complete_check(&"skill")
	_evaluate_guidance.call_deferred()


func _on_level_completed(_total_score: int) -> void:
	_level_done = true
	var candidate := _candidate(
			&"done",
			"ui_tutorial_complete_title",
			"ui_tutorial_complete_body",
			200,
			[],
			[])
	_show_candidate(candidate)
	_footer.text = Localization.t("ui_tutorial_complete_footer", "Click or press Space on the next screen to continue.")
	_clear_hexes()
