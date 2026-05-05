extends RefCounted
## SkillFormatter — pure-static helpers for rendering Skill / Ability data
## as text. Single source of truth so PSP, inspector tooltip, modifier-pick
## screen all show the same string for the same skill.
##
## Used via explicit preload (no class_name, no autoload):
##   const SkillFormatter = preload("res://scripts/presentation/skill_formatter.gd")
##   var human := SkillFormatter.format_skill_human(skill)
##
## Modifier-aware: applies ParameterModifier list to a duplicated Effect/Area
## before formatting — same path Ability.cast() uses, so the text reflects
## final (post-modifier) numbers, not base. (Mirrors AC-M5 formula.)
##
## 049: prefer `format_skill_human` (uses Localization.t(skill.tooltip)) over
## the legacy structural `format_skill`. Legacy retained for dev/debug callers.


## 049 / AC-1: human-readable skill description sourced from
## Localization.t(skill.tooltip). When the tooltip key is missing or empty
## (Localization.t returns the key itself = sentinel for missing) we surface
## a visible placeholder so designers immediately spot un-authored skills,
## rather than hiding behind structural debug text. Cooldown indicator is
## appended verbatim from format_skill semantics.
##
## NOTE: this is the source of truth for PSP SpellDesc, HexTooltip rows,
## EnemyDetailsPanel ability hover. format_skill below is now
## debug/dev-mode-only and must not be wired into player-visible UI.
const _DESC_PLACEHOLDER := "[ДОБАВИТЬ]"

static func format_skill_human(skill) -> String:
	if skill == null:
		return ""
	var key: String = String(skill.tooltip)
	var body: String = ""
	if key != "":
		# Localization.t returns `fallback` when the key didn't translate
		# (i.e. translated == key_or_source). We pass the placeholder as
		# fallback so missing/unauthored keys are visible to designers.
		body = Localization.t(key, _DESC_PLACEHOLDER)
	else:
		body = _DESC_PLACEHOLDER
	var has_inline_cooldown: bool = body.find("$cooldown$") >= 0 or body.find("$cd$") >= 0
	body = _interpolate_skill_vars(body, skill)
	# Append CD indicator (matches format_skill).
	if skill.cooldown > 0 and not has_inline_cooldown:
		var cd_remaining: int = int(skill.get("_cd_remaining"))
		if cd_remaining > 0:
			body += " " + Localization.tf("ui_skill_cooldown_remaining",
					[cd_remaining, skill.cooldown], "(CD %d/%d)")
		else:
			body += " " + Localization.tf("ui_skill_cooldown",
					[skill.cooldown], "(CD %d)")
	return body


static func format_skill_desc(skill) -> String:
	if skill == null:
		return ""
	var key: String = String(skill.desc)
	if key == "":
		return ""
	var body: String = Localization.t(key, key)
	return _interpolate_skill_vars(body, skill)


## Replaces designer-authored tokens like `$damage$`, `$range$`, `$cooldown$`
## with numbers read from this exact Skill resource. Tokens are intentionally
## generic: the caller supplies the Skill, and this formatter derives the right
## parameters from its target/area/effects instead of requiring per-skill keys.
static func _interpolate_skill_vars(text: String, skill) -> String:
	if text == "" or (text.find("$") < 0 and text.find("{") < 0) or skill == null:
		return text
	var values: Dictionary = _skill_var_values(skill)
	var out: String = _interpolate_plural_forms(text, values)
	var pos: int = 0
	while true:
		var open: int = out.find("$", pos)
		if open < 0:
			break
		var close: int = out.find("$", open + 1)
		if close < 0:
			break
		var name: String = out.substr(open + 1, close - open - 1).strip_edges()
		if name == "":
			pos = close + 1
			continue
		var key: StringName = StringName(name)
		if not values.has(key):
			pos = close + 1
			continue
		var replacement: String = _format_var_value(values[key])
		out = out.substr(0, open) + replacement + out.substr(close + 1)
		pos = open + replacement.length()
	return out


static func _interpolate_plural_forms(text: String, values: Dictionary) -> String:
	if text.find("{") < 0 or text.find(";") < 0:
		return text
	var out: String = text
	var pos: int = 0
	while true:
		var open: int = out.find("{", pos)
		if open < 0:
			break
		var close: int = out.find("}", open + 1)
		if close < 0:
			break
		var body: String = out.substr(open + 1, close - open - 1)
		var parts := body.split(";", true)
		if parts.size() < 4:
			pos = close + 1
			continue
		var count_value: Variant = _plural_count_value(String(parts[0]).strip_edges(), values)
		if count_value == null:
			pos = close + 1
			continue
		var forms: Array[String] = [
			String(parts[1]).strip_edges(),
			String(parts[2]).strip_edges(),
			String(parts[3]).strip_edges(),
		]
		var replacement: String = "%s %s" % [_format_var_value(count_value), forms[_plural_form_index(int(count_value))]]
		out = out.substr(0, open) + replacement + out.substr(close + 1)
		pos = open + replacement.length()
	return out


static func _plural_count_value(source: String, values: Dictionary) -> Variant:
	if source.begins_with("$") and source.ends_with("$") and source.length() >= 3:
		var name := source.substr(1, source.length() - 2).strip_edges()
		var key := StringName(name)
		if not values.has(key):
			return null
		var value: Variant = values[key]
		if typeof(value) == TYPE_INT:
			return int(value)
		if typeof(value) == TYPE_FLOAT:
			return int(round(float(value)))
		return null
	if source.is_valid_int():
		return int(source)
	if source.is_valid_float():
		return int(round(source.to_float()))
	return null


static func _plural_form_index(count: int) -> int:
	return Localization.plural_form_index(count)


static func _skill_var_values(skill) -> Dictionary:
	var values: Dictionary = {}
	_set_var(values, &"cooldown", skill.cooldown)
	_set_var(values, &"cd", skill.cooldown)
	_set_var(values, &"level", skill.level)

	var totals: Dictionary = {
		&"damage": 0,
		&"heal": 0,
	}
	for ab in skill.abilities:
		if ab == null:
			continue
		_collect_target_vars(values, ab.target, int(skill.level))
		_collect_area_vars(values, ab.area, int(skill.level))
		for base_eff in ab.effects:
			var eff: AbilityEffect = base_eff.duplicate()
			_apply_modifiers(eff, ab.modifiers)
			eff.apply_level(int(skill.level))
			_collect_effect_vars(values, totals, eff, int(skill.level))

	for key in totals.keys():
		if int(totals[key]) > 0:
			_set_var(values, key, totals[key])
	return values


static func _collect_target_vars(values: Dictionary, target: AbilityTarget, level: int) -> void:
	if target == null:
		return
	var dup: AbilityTarget = target.duplicate()
	dup.apply_level(level)
	_set_number_property(values, &"range", dup, &"range", false)
	_set_number_property(values, &"target_range", dup, &"range", false)


static func _collect_area_vars(values: Dictionary, area: AbilityArea, level: int) -> void:
	if area == null:
		return
	var dup: AbilityArea = area.duplicate()
	dup.apply_level(level)
	_set_number_property(values, &"radius", dup, &"radius", false)
	_set_number_property(values, &"area_radius", dup, &"radius", false)
	_set_number_property(values, &"inner_radius", dup, &"inner_radius", false)
	_set_number_property(values, &"length", dup, &"length", false)
	_set_number_property(values, &"width", dup, &"width", false)
	_set_number_property(values, &"angle", dup, &"angle", false)
	_set_number_property(values, &"max_chain_length", dup, &"max_chain_length", false)
	_set_number_property(values, &"chain_targets", dup, &"max_chain_length", false)


static func _collect_effect_vars(values: Dictionary, totals: Dictionary,
		eff: AbilityEffect, level: int) -> void:
	if eff == null:
		return
	if eff is DamageEffect:
		var damage: int = (eff as DamageEffect).damage
		totals[&"damage"] = int(totals[&"damage"]) + damage
		_set_var(values, &"damage", damage, false)
		return
	if eff is HealEffect:
		var heal: int = (eff as HealEffect).heal
		totals[&"heal"] = int(totals[&"heal"]) + heal
		_set_var(values, &"heal", heal, false)
		return
	if eff is MoveEffect:
		_set_var(values, &"move_distance", (eff as MoveEffect).move_distance, false)
		return
	if eff is CreateEffect:
		var ce: CreateEffect = eff as CreateEffect
		_set_var(values, &"duration", ce.duration, false)
		_set_var(values, &"summon_duration", ce.duration, false)
		_set_var(values, &"entity_id", String(ce.entity_id), false)
		return
	if eff is StatusEffect:
		_collect_status_vars(values, eff as StatusEffect, level)


static func _collect_status_vars(values: Dictionary, eff: StatusEffect, level: int) -> void:
	if eff.status_id == &"":
		return
	var status_prefix: String = String(eff.status_id)
	var args: Array[int] = eff.args
	if not args.is_empty():
		_set_var(values, &"duration", args[0], false)
		_set_var(values, &"status_duration", args[0], false)
		_set_var(values, StringName("%s_duration" % status_prefix), args[0], false)

	var meta: Dictionary = StatusRegistry.meta_for(eff.status_id)
	var names: Array = meta.get("param_names", [])
	for i in mini(args.size(), names.size()):
		var param: String = String(names[i])
		if param == "":
			continue
		var value: int = args[i]
		if i == 1:
			var rt: GDScript = StatusRegistry.runtime_for(eff.status_id)
			if rt != null:
				value = rt.compute_snapshot(args, level)
		_set_var(values, StringName(param), value, false)
		_set_var(values, StringName("status_%s" % param), value, false)
		_set_var(values, StringName("%s_%s" % [status_prefix, param]), value, false)
		if i == 1:
			_set_var(values, &"status_value", value, false)
			_set_var(values, StringName("%s_value" % status_prefix), value, false)
			if not values.has(&"damage") and (param == "damage" or param == "damage_pct"):
				_set_var(values, &"damage", value, false)


static func _set_number_property(values: Dictionary, key: StringName,
		obj: Object, property: StringName, overwrite: bool = true) -> void:
	if obj == null or not _has_property(obj, property):
		return
	var value: Variant = obj.get(property)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return
	_set_var(values, key, value, overwrite)


static func _set_var(values: Dictionary, key: StringName, value: Variant,
		overwrite: bool = true) -> void:
	if key == &"":
		return
	if values.has(key) and not overwrite:
		return
	values[key] = value


static func _has_property(obj: Object, property: StringName) -> bool:
	for p in obj.get_property_list():
		if StringName(str(p.get("name", ""))) == property:
			return true
	return false


static func _format_var_value(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		var f: float = float(value)
		if is_equal_approx(f, round(f)):
			return str(int(round(f)))
		return "%.2f" % f
	return str(value)


## 049 / AC-2: short consequence string for HexTooltip's 3rd column.
## Looks at the *first* ability's *first* meaningful effect — same heuristic
## the telegraph damage label uses (one number per skill, even if multi-effect).
## Modifier-naive on purpose: the tooltip is a quick affordance during cast
## planning; once the spell actually fires, floating numbers / hp bar deltas
## tell the precise post-modifier story. ≤30 chars target.
static func format_consequence(skill) -> String:
	if skill == null or skill.abilities.is_empty():
		return ""
	var ab = skill.abilities[0]
	if ab == null:
		return ""
	for eff in ab.effects:
		if eff is DamageEffect:
			return Localization.tf("ui_consequence_damage",
					[(eff as DamageEffect).damage], "-%d HP")
		if eff is HealEffect:
			return Localization.tf("ui_consequence_heal",
					[(eff as HealEffect).heal], "+%d HP")
		if eff is StatusEffect:
			var se: StatusEffect = eff
			if se.status_id == &"":
				continue
			var status_name: String = Localization.t(
					"status_%s_name" % String(se.status_id),
					String(se.status_id).capitalize())
			# args[0] = duration (per StatusEffect doc).
			var dur: int = se.args[0] if se.args.size() > 0 else 0
			if dur > 0:
				return Localization.tf("ui_consequence_status",
						[status_name, dur], "%s (%dt)")
			return status_name
		if eff is MoveEffect:
			var me: MoveEffect = eff
			return Localization.tf("ui_consequence_move",
					[String(me.move_type).capitalize(), me.move_distance],
					"%s %d")
		if eff is CreateEffect:
			return Localization.t("ui_consequence_summon", "Summon")
	return ""


## 049b / T035: semantic color for the consequence text — read at a glance.
## Mirrors the effect-priority order of format_consequence so the colour
## matches what the string actually says (no risk of "+15 HP" coming back
## red because the next effect is damage).
static func consequence_color(skill) -> Color:
	if skill == null or skill.abilities.is_empty():
		return UiTheme.TEXT
	var ab = skill.abilities[0]
	if ab == null:
		return UiTheme.TEXT
	for eff in ab.effects:
		if eff is DamageEffect:
			return UiTheme.SEM_DAMAGE
		if eff is HealEffect:
			return UiTheme.SEM_HEAL
		if eff is StatusEffect:
			return UiTheme.SEM_DEBUFF
		if eff is MoveEffect:
			return UiTheme.SEM_MOVE
		if eff is CreateEffect:
			return UiTheme.SEM_BUFF
	return UiTheme.TEXT


## Legacy structural format. Now debug/dev-only — public UI must use
## format_skill_human. Kept for ActorInspector-class debug surfaces and
## for unit-test parity until those callers are removed in their own PRs.
##
## Format a Skill into a multi-line plain-text block.
## Returns "" on null. First line is the skill id, then per-ability blocks.
static func format_skill(skill) -> String:
	if skill == null:
		return ""
	var lines: Array[String] = []
	# Header: name + cooldown if > 0
	var header: String = Localization.t(String(skill.name), String(skill.id))
	if skill.cooldown > 0:
		var cd_remaining: int = int(skill.get("_cd_remaining"))
		if cd_remaining > 0:
			header += " " + Localization.tf("ui_skill_cooldown_remaining", [cd_remaining, skill.cooldown], "(CD %d/%d)")
		else:
			header += " " + Localization.tf("ui_skill_cooldown", [skill.cooldown], "(CD %d)")
	lines.append(header)
	# One block per contained ability — most skills have just 1.
	for ab in skill.abilities:
		var ab_lines: Array[String] = format_ability(ab)
		for l in ab_lines:
			lines.append("  " + l)
	return "\n".join(lines)


## Format a single Ability — target / area / effects with modifier-applied numbers.
static func format_ability(ability) -> Array[String]:
	var lines: Array[String] = []
	if ability == null:
		return lines
	# Target type
	if ability.target != null:
		lines.append("Target: %s" % ability.target.get_class())
	# Area type
	if ability.area != null:
		lines.append("Area: %s" % ability.area.get_class())
	# Effects — duplicate + apply modifiers, then describe
	for base_eff in ability.effects:
		var eff_dup: AbilityEffect = base_eff.duplicate()
		_apply_modifiers(eff_dup, ability.modifiers)
		lines.append(_describe_effect(eff_dup, base_eff))
	return lines


## Returns just the headline string (single-line skill summary) — useful for
## slot-bar tooltips, status pills, etc.
static func format_skill_headline(skill) -> String:
	if skill == null:
		return ""
	var display_name := Localization.t(String(skill.name), String(skill.id))
	if skill.abilities.is_empty():
		return display_name
	# Sum predicted damage across abilities, if any
	var total_dmg: int = 0
	for ab in skill.abilities:
		for base_eff in ab.effects:
			if base_eff is DamageEffect:
				var eff_dup: AbilityEffect = base_eff.duplicate()
				_apply_modifiers(eff_dup, ab.modifiers)
				total_dmg += (eff_dup as DamageEffect).damage
	if total_dmg > 0:
		return Localization.tf("ui_skill_headline_damage", [display_name, total_dmg], "%s — %d dmg")
	return display_name


# ── Internals ────────────────────────────────────────────────────────────────

## Mirrors Ability._apply_param_modifiers but on a single object.
## Formula per param p: final = (base + Σ adds_p) × Π muls_p
static func _apply_modifiers(obj: Object, mods: Array) -> void:
	if obj == null or mods == null or mods.is_empty():
		return
	var params: Dictionary = {}
	for m in mods:
		if m.applies_to(obj):
			params[m.target_param] = true
	for param in params.keys():
		var base: Variant = obj.get(param)
		var add_sum: float = 0.0
		var mul_prod: float = 1.0
		for m in mods:
			if m.target_param != param:
				continue
			if m.op == &"add":
				add_sum += m.value
			elif m.op == &"mul":
				mul_prod *= m.value
		var final_val: float = (float(base) + add_sum) * mul_prod
		if typeof(base) == TYPE_INT:
			obj.set(param, int(floor(final_val)))
		else:
			obj.set(param, final_val)


## Render a single effect into a string. base_eff is the un-modified original
## (used to show base→final breakdown when they differ).
static func _describe_effect(eff_final: AbilityEffect, eff_base: AbilityEffect) -> String:
	if eff_final is DamageEffect:
		var f: int = (eff_final as DamageEffect).damage
		var b: int = (eff_base as DamageEffect).damage
		if f != b:
			return Localization.tf("ui_effect_damage_changed", [b, f], "Damage: %d → %d")
		return Localization.tf("ui_effect_damage", [f], "Damage: %d")
	# Generic fallback — class name is informative for unknown effect types.
	return Localization.tf("ui_effect_generic", [eff_final.get_class()], "Effect: %s")
