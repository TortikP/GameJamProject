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
	# Append CD indicator (matches format_skill).
	if skill.cooldown > 0:
		var cd_remaining: int = int(skill.get("_cd_remaining"))
		if cd_remaining > 0:
			body += " " + Localization.tf("ui_skill_cooldown_remaining",
					[cd_remaining, skill.cooldown], "(CD %d/%d)")
		else:
			body += " " + Localization.tf("ui_skill_cooldown",
					[skill.cooldown], "(CD %d)")
	return body


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
