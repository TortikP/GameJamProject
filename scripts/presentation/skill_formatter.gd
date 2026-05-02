extends RefCounted
## SkillFormatter — pure-static helpers for rendering Skill / Ability data
## as text. Single source of truth so PSP, inspector tooltip, modifier-pick
## screen all show the same string for the same skill.
##
## Used via explicit preload (no class_name, no autoload):
##   const SkillFormatter = preload("res://scripts/presentation/skill_formatter.gd")
##   var lines := SkillFormatter.format_skill(skill)
##
## Modifier-aware: applies ParameterModifier list to a duplicated Effect/Area
## before formatting — same path Ability.cast() uses, so the text reflects
## final (post-modifier) numbers, not base. (Mirrors AC-M5 formula.)


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
			header += " " + Localization.tf("(CD %d/%d)", [cd_remaining, skill.cooldown], "(CD %d/%d)")
		else:
			header += " " + Localization.tf("(CD %d)", [skill.cooldown], "(CD %d)")
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
		return Localization.tf("%s — %d dmg", [display_name, total_dmg], "%s — %d dmg")
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
			return Localization.tf("Damage: %d → %d", [b, f], "Damage: %d → %d")
		return Localization.tf("Damage: %d", [f], "Damage: %d")
	# Generic fallback — class name is informative for unknown effect types.
	return Localization.tf("Effect: %s", [eff_final.get_class()], "Effect: %s")
