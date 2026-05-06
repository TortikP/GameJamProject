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
func can_apply(caster: Actor, ctx: Dictionary, level: int = 0, passive_mods: Dictionary = {}) -> bool:
	if target == null or area == null or effects.is_empty():
		return false
	var target_dup: AbilityTarget = _effective_target(level, passive_mods)
	return target_dup != null and target_dup.can_apply(caster, ctx)


## Damage preview for hover UI. Sums all DamageEffect.damage values + caster bonus,
## after applying skill-level scaling AND add/mul modifiers (in that order).
## Returns 0 for non-damage-only abilities.
## KEEP IN SYNC with DamageEffect.apply + the cast lifecycle order.
func predicted_damage_to(caster: Actor, _target: Actor, _ctx: Dictionary, level: int = 0,
		passive_mods: Dictionary = {}) -> int:
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
		_apply_passive_modifiers(eff_dup, passive_mods)
		total += maxi(0, (eff_dup as DamageEffect).damage + bonus)
	return total


## Returns true if at least one victim was processed.
## False means "no valid targets" — callers should NOT advance the turn.
##
## `level` is the Skill.level passed in by Skill.cast. 0 = identity (no scaling).
##
## 047-skill-fx-system: cast is now a thin back-compat wrapper around the
## resolve / apply_resolved split. Call resolve() to get a plan, then
## apply_resolved(plan, ...) to actually mutate state. Skill.cast inserts an
## await on FxDirector between these two phases so visuals and sound land
## BEFORE damage/heal numbers fly. Callers that don't need FX can keep using
## cast() and stay synchronous — no behavioural change for them.
func cast(caster: Actor, ctx: Dictionary, level: int = 0) -> bool:
	var plan: Dictionary = resolve(caster, ctx, level)
	if plan.is_empty():
		return false
	return apply_resolved(plan, caster, ctx)


## 047: pure target/area resolution. NO side effects — no signals emitted, no
## effects applied, no actor mutations. Returns a plan dict consumed by
## apply_resolved, or {} on bail.
##
## Plan shape:
##   "primary":      Variant            — primary target as resolved
##   "victims":      Array              — victims after caster-exclusion
##   "has_create":   bool               — at least one CreateEffect in this ability
##   "create_hexes": Array[Vector2i]    — affected hexes for hex-pass (only if has_create)
##   "level":        int                — captured for apply_resolved consistency
func resolve(caster: Actor, ctx: Dictionary, level: int = 0, passive_mods: Dictionary = {}) -> Dictionary:
	if target == null or area == null or effects.is_empty():
		GameLogger.error("Ability", "%s: target / area / effects misconfigured" % id)
		return {}

	# Duplicate target so apply_level mutates a copy, not the shared resource.
	var target_dup: AbilityTarget = _effective_target(level, passive_mods)
	if target_dup == null:
		return {}

	var primary: Variant = target_dup.resolve(caster, ctx)
	if primary == null:
		GameLogger.info("Ability", "%s: no primary target" % id)
		return {}

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

	# 046: only ActorTarget / ObjectTarget semantically require a victim.
	# SelfTarget describes "centered on me", HexTarget describes "centered
	# on this tile", DirectionTarget describes a vector — for all three,
	# an empty area is a valid cast (cooldown ticks, audio fires, no per-
	# victim effects run). Without this gate, target=self + zone_circle
	# bailed whenever no other actors stood in the radius (the
	# exclude_caster strip below leaves victims=[]); target=hex + zone on
	# an empty hex bailed at the pre-exclusion guard.
	var target_requires_victims: bool = (target is ActorTarget) or (target is ObjectTarget)

	var victims: Array = eff_area.resolve(caster, primary, ctx)
	if victims.is_empty() and not has_create and target_requires_victims:
		GameLogger.info("Ability", "%s: no victims in area" % id)
		return {}

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
	if victims.is_empty() and not has_create and target_requires_victims:
		GameLogger.info("Ability", "%s: no victims after caster exclusion" % id)
		return {}

	var create_hexes: Array[Vector2i] = []
	if has_create:
		var grid: HexGrid = ctx.get("grid")
		var caster_coord: Vector2i = Vector2i(-1, -1)
		if grid != null and caster != null:
			caster_coord = grid.get_coord(caster.actor_id)
		create_hexes = eff_area.get_affected_hexes(caster_coord, primary, grid)

	return {
		"primary":      primary,
		"victims":      victims,
		"has_create":   has_create,
		"create_hexes": create_hexes,
		"level":        level,
		"passive_mods": passive_mods,
	}


## 047: applies a previously-resolved plan. Mutates state, emits
## EventBus.ability_cast at the end. Returns true if anything ran.
##
## Order matches pre-047 cast(): create-pass first (per-hex spawning),
## then per-victim effect loop. This is unchanged for back-compat — the
## only difference is that callers (Skill.cast) get to insert FX awaits
## BETWEEN resolve() and this call.
func apply_resolved(plan: Dictionary, caster: Actor, ctx: Dictionary) -> bool:
	if plan.is_empty():
		return false
	var victims: Array = plan.get("victims", [])
	var has_create: bool = plan.get("has_create", false)
	var create_hexes: Array = plan.get("create_hexes", [])
	var level: int = plan.get("level", 0)

	var target_ids: Array = []

	# 041: CreateEffect hex-pass. Independent of victim iteration — drives
	# spawn coord from area.get_affected_hexes() so an empty hex still fires
	# and a multi-hex zone produces one entity per hex.
	if has_create:
		for hex_coord in create_hexes:
			var per_hex_ctx: Dictionary = ctx.duplicate()
			per_hex_ctx["target_coord"] = hex_coord
			for base_eff in effects:
				if not base_eff is CreateEffect:
					continue
				var eff_dup_c: AbilityEffect = base_eff.duplicate()
				eff_dup_c.apply_level(level)
				_apply_param_modifiers(eff_dup_c, modifiers)
				_apply_passive_modifiers(eff_dup_c, plan.get("passive_mods", {}))
				eff_dup_c.apply(caster, null, per_hex_ctx)

	for victim in victims:
		# 052b: defensive — a previous effect in this loop may have killed
		# and queue_free'd the victim (e.g. an AoE that reflects through a
		# trigger). _is_dead does `victim is Actor` which throws on a freed
		# Object; check validity first.
		if not is_instance_valid(victim):
			continue
		for base_eff in effects:
			if base_eff is CreateEffect:
				continue   # 041: handled by hex-pass above
			var eff_dup: AbilityEffect = base_eff.duplicate()
			eff_dup.apply_level(level)              # 021: level FIRST
			_apply_param_modifiers(eff_dup, modifiers)  # then modifiers ON TOP
			_apply_passive_modifiers(eff_dup, plan.get("passive_mods", {}))
			if eff_dup.requires_alive_target and _is_dead(victim):
				continue
			eff_dup.apply(caster, victim, ctx)
		_apply_passive_ranged_push(caster, victim, ctx, plan.get("passive_mods", {}))
		if victim is Actor:
			target_ids.append((victim as Actor).actor_id)

	last_target_ids = target_ids
	EventBus.ability_cast.emit(caster.actor_id, id, target_ids)
	return true


# ── Internals ────────────────────────────────────────────────────────────────

func effective_range_hexes(caster: Actor, grid: HexGrid, level: int = 0,
		passive_mods: Dictionary = {}) -> Array[Vector2i]:
	if caster == null or grid == null:
		return []
	var caster_coord: Vector2i = grid.get_coord(caster.actor_id)
	if caster_coord == Vector2i(-1, -1):
		return []
	var target_dup: AbilityTarget = _effective_target(level, passive_mods)
	if target_dup == null:
		return []
	return target_dup.get_range_hexes(caster_coord, grid)


func _effective_target(level: int, passive_mods: Dictionary) -> AbilityTarget:
	if target == null:
		return null
	var target_dup: AbilityTarget = target.duplicate()
	target_dup.apply_level(level)
	_apply_passive_modifiers(target_dup, passive_mods)
	return target_dup


func _apply_passive_modifiers(obj: Object, passive_mods: Dictionary) -> void:
	if obj == null or passive_mods.is_empty():
		return
	var range_bonus: int = int(passive_mods.get("range_bonus", 0))
	if range_bonus != 0 and "range" in obj:
		var current_range: int = int(obj.get("range"))
		if current_range > 0:
			obj.set("range", current_range + range_bonus)
	var status_duration_bonus: int = int(passive_mods.get("status_duration_bonus", 0))
	if status_duration_bonus != 0 and obj is StatusEffect:
		var se: StatusEffect = obj as StatusEffect
		if not se.args.is_empty() and se.args[0] > 0:
			se.args = se.args.duplicate()
			se.args[0] += status_duration_bonus


func _apply_passive_ranged_push(caster: Actor, victim: Variant, ctx: Dictionary,
		passive_mods: Dictionary) -> void:
	var distance: int = int(passive_mods.get("ranged_push_distance", 0))
	if distance <= 0 or not _is_ranged_damage_ability():
		return
	var actor := victim as Actor
	if caster == null or actor == null or actor == caster or not actor.is_alive():
		return
	if caster.team != &"" and actor.team == caster.team:
		return
	var push := MoveEffect.new()
	push.move_type = &"push"
	push.move_distance = distance
	push.apply(caster, actor, ctx)


func _is_ranged_damage_ability() -> bool:
	var is_ranged: bool = false
	if target != null and "range" in target:
		is_ranged = int(target.get("range")) > 1
	if not is_ranged:
		return false
	for eff in effects:
		if eff is DamageEffect:
			return true
	return false


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
	# 052b: `victim is Actor` throws on a previously freed instance, so
	# treat freed objects as dead-equivalent (they can't take any more
	# effects, the caller will skip).
	if not is_instance_valid(victim):
		return true
	if victim is Actor:
		return not (victim as Actor).is_alive()
	return false
