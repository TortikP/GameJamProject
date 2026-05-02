class_name Ability
extends Resource
## Ability — single cast unit. target × area × effect[] × modifier[].
##
## Lifecycle (021-skill-system-v2 §"Lifecycle: Ability.cast"):
##   1. target_dup = target.duplicate(); target_dup.apply_level(level)
##      primary = target_dup.resolve(caster, ctx)
##   2. area_dup = area.duplicate(); area_dup.apply_level(level)
##      _apply_param_modifiers(area_dup, modifiers)
##      victims = area_dup.resolve(caster, primary, ctx)
##   3. for victim in victims:
##        for base_eff in effects:
##          eff_dup = base_eff.duplicate()
##          eff_dup.apply_level(level)
##          _apply_param_modifiers(eff_dup, modifiers)
##          if requires_alive_target and victim is dead: continue
##          eff_dup.apply(caster, victim, ctx)
##   4. EventBus.ability_cast.emit(...)
##
## Order matters: apply_level (base progression) FIRST, then param-modifiers
## (granular crafted affixes) ON TOP. Level is a property of the parent Skill.
##
## Modifier formula (007 AC-M5): final = (base + Σ adds) × Π muls
## Applied per-param, commutative, int → floor, float → as-is.
##
## 026 additions (026-skill-system-v3):
##  - sound (021) renamed → sound_start (cast-start cue).
##  - sound_end — new (cast-resolution cue).
##  - collision_effect — new (VFX id at impact, distinct from `animation`
##    which is the caster's pose/gesture).
## All four presentation IDs (sound_start / sound_end / collision_effect /
## animation) are stored as StringName, default &"". Dispatch (AudioDB / VFXDB)
## lives in future features — 026 only fixes the data shape.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@export var id: StringName = &""
@export var sound_start:      StringName = &""    # 026 — was `sound` in 021
@export var sound_end:        StringName = &""    # 026 — new
@export var collision_effect: StringName = &""    # 026 — new (VFX at impact)
@export var animation:        StringName = &""    # caster pose/gesture (021)
@export var target: AbilityTarget
@export var area: AbilityArea
@export var effects: Array[AbilityEffect] = []
@export var modifiers: Array[ParameterModifier] = []

# 015 / F-014: populated by cast() before EventBus.ability_cast emit so
# Skill.cast can aggregate per-ability target_ids into its own skill_cast
# emit. Overwritten on every cast() call — read immediately after cast()
# returns true; do not cache. Sharing an Ability resource across simultaneous
# casts is unsafe (turn manager is sequential, so this is fine in practice).
var last_target_ids: Array = []


## Cheap pre-check for UI (grey-out un-castable slots). Doesn't run area/effects.
func can_apply(caster: Actor, ctx: Dictionary) -> bool:
	if target == null or area == null or effects.is_empty():
		return false
	return target.can_apply(caster, ctx)


## Damage preview for hover UI. Sums all DamageEffect.damage values + caster bonus,
## after applying skill-level scaling AND add/mul modifiers (in that order).
## Returns 0 for non-damage-only abilities.
## KEEP IN SYNC with DamageEffect.apply + the cast lifecycle order.
func predicted_damage_to(caster: Actor, _target: Actor, _ctx: Dictionary, level: int = 0) -> int:
	var total: int = 0
	# 027: damage_amplifier sums strong/weak status modifiers (signed).
	var bonus: int = 0
	if caster != null:
		bonus = caster.damage_bonus + caster.damage_amplifier()
	for base_eff in effects:
		if not base_eff is DamageEffect:
			continue
		var eff_dup: AbilityEffect = base_eff.duplicate()
		eff_dup.apply_level(level)
		_apply_param_modifiers(eff_dup, modifiers)
		total += maxi(0, (eff_dup as DamageEffect).damage + bonus)
	return total


## Returns true if at least one victim was processed.
## False means "no valid targets" — callers should NOT advance the turn.
##
## `level` is the Skill.level passed in by Skill.cast. 0 = identity (no scaling).
func cast(caster: Actor, ctx: Dictionary, level: int = 0) -> bool:
	if target == null or area == null or effects.is_empty():
		GameLogger.error("Ability", "%s: target / area / effects misconfigured" % id)
		return false

	# Duplicate target so apply_level mutates a copy, not the shared resource.
	var target_dup: AbilityTarget = target.duplicate()
	target_dup.apply_level(level)

	var primary: Variant = target_dup.resolve(caster, ctx)
	if primary == null:
		GameLogger.info("Ability", "%s: no primary target" % id)
		return false

	# Duplicate area, scale by level, then layer modifiers.
	var eff_area: AbilityArea = area.duplicate()
	eff_area.apply_level(level)
	_apply_param_modifiers(eff_area, modifiers)

	# 041: CreateEffect operates per-hex (via ctx["target_coord"]) and doesn't
	# need a victim. Detect upfront so empty-area on a hex-targeted ability
	# (e.g. summon onto an empty hex) doesn't bail at the victims.is_empty()
	# guard, and so multi-hex zones (zone_circle radius>1) spawn one entity
	# per affected hex instead of N copies at the primary coord.
	var has_create: bool = false
	for e in effects:
		if e is CreateEffect:
			has_create = true
			break

	var victims: Array = eff_area.resolve(caster, primary, ctx)
	if victims.is_empty() and not has_create:
		GameLogger.info("Ability", "%s: no victims in area" % id)
		return false

	# Caster is excluded from zone AoE only when (a) the ability is self-targeted
	# (primary == caster, i.e. SelfTarget) AND (b) the area is a real zone that
	# can contain others (not SelfArea). SelfArea returns exactly [caster] —
	# stripping the caster there would empty the victim list and break self-
	# heals / self-buffs (spec 031 phase 6). Non-self targets (actor, hex) can catch
	# the caster in their zone — intentional friendly-fire design space.
	var exclude_caster: bool = (
		primary is Actor
		and (primary as Actor) == caster
		and not (eff_area is SelfArea)
	)
	if exclude_caster:
		var filtered: Array = []
		for v in victims:
			if v != caster:
				filtered.append(v)
		victims = filtered
	if victims.is_empty() and not has_create:
		GameLogger.info("Ability", "%s: no victims after caster exclusion" % id)
		return false

	var target_ids: Array = []

	# 041: CreateEffect hex-pass. Independent of victim iteration — drives
	# spawn coord from area.get_affected_hexes() so an empty hex still fires
	# and a multi-hex zone produces one entity per hex.
	if has_create:
		var grid: HexGrid = ctx.get("grid")
		var caster_coord: Vector2i = Vector2i(-1, -1)
		if grid != null and caster != null:
			caster_coord = grid.get_coord(caster.actor_id)
		var hexes: Array[Vector2i] = eff_area.get_affected_hexes(caster_coord, primary, grid)
		for hex_coord in hexes:
			var per_hex_ctx: Dictionary = ctx.duplicate()
			per_hex_ctx["target_coord"] = hex_coord
			for base_eff in effects:
				if not base_eff is CreateEffect:
					continue
				var eff_dup_c: AbilityEffect = base_eff.duplicate()
				eff_dup_c.apply_level(level)
				_apply_param_modifiers(eff_dup_c, modifiers)
				eff_dup_c.apply(caster, null, per_hex_ctx)

	for victim in victims:
		for base_eff in effects:
			if base_eff is CreateEffect:
				continue   # 041: handled by hex-pass above
			var eff_dup: AbilityEffect = base_eff.duplicate()
			eff_dup.apply_level(level)              # 021: level FIRST
			_apply_param_modifiers(eff_dup, modifiers)  # then modifiers ON TOP
			if eff_dup.requires_alive_target and _is_dead(victim):
				continue
			eff_dup.apply(caster, victim, ctx)
		if victim is Actor:
			target_ids.append((victim as Actor).actor_id)

	last_target_ids = target_ids
	EventBus.ability_cast.emit(caster.actor_id, id, target_ids)
	return true


# ── Internals ────────────────────────────────────────────────────────────────

## Mutates obj's numeric properties in-place per modifier list.
## Formula per param p: final = (base + Σ adds_p) × Π muls_p
## int → floor, float → as-is.
func _apply_param_modifiers(obj: Object, mods: Array[ParameterModifier]) -> void:
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


func _is_dead(victim: Variant) -> bool:
	if victim is Actor:
		return not (victim as Actor).is_alive()
	return false
