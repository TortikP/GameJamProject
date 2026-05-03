class_name Skill
extends Resource
## Skill — ordered composition of 1..N Abilities with a shared cooldown.
##
## cast() executes abilities in array order. Each ability resolves its own targets
## at execution time (not at skill-start) — enabling multi-ability combos like vampirism.
##
## tick_cooldown(n) is called once per round by
## godmode_controller._tick_all_skills (driven from _on_world_turn_ended)
## for every live Actor. See spec 031-skill-cooldown-fix.
##
## 031 phase 4 — first-tick absorption: world_turn_ended fires in the
## same TurnManager.advance() that caps off the cast turn, so the very
## next tick after cast() lands inside the *cast turn itself* and would
## erase one round of cooldown. _skip_next_tick=true on cast absorbs
## exactly that tick, so cooldown=N means N rounds of being unavailable
## (the design intent in JSON), not N-1.
##
## 021 additions (021-skill-system-v2):
##  - name / tooltip / desc — localization keys (raw strings; resolution out of scope).
##  - behaviour_tags — renamed from `tags`. AI strategy uses these to pick a skill.
##  - mood — narrative archetype tags. No consumer yet; reserved for character system.
##  - level — power axis. Propagated into Ability.cast and predicted_damage_to.
##    Components (target/area/effect) self-react via apply_level(level) on a duplicate
##    before resolve/apply — base resource stays untouched.
##
## 026 additions (026-skill-system-v3):
##  - icon — StringName id for future IconDB. Stored, not dispatched.
##  - cast(caster, ctxs: Array[Dictionary]) — per-ability ctx. ctxs.size() must
##    equal abilities.size(); abilities[i] gets ctxs[i]. Caller (godmode_controller
##    for player, _resolve_cast_intent for AI) is responsible for collecting
##    targets per ability before calling cast.
##
## 047 additions (047-skill-fx-system):
##  - cast(caster, ctxs, fx: Object = null) — coroutine. When fx != null,
##    awaits FxDirector.play_cast / play_collisions per ability between the
##    pure resolve phase and the side-effecting apply phase. fx is duck-typed
##    Object so this file has no presentation import. Callers MUST `await`
##    skill.cast(...) — without await the bool return value is not realised.
##  - Per-ability skip on empty plan: if Ability.resolve returns {} (e.g.
##    target died from previous ability in same skill), THAT ability is
##    skipped and the loop continues. Cooldown is still applied as long as
##    AT LEAST ONE ability resolved (any_resolved).

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@export var id: StringName = &""
@export var name: String = ""
@export var tooltip: String = ""
@export var desc: String = ""
@export var icon: StringName = &""                   # 026: future IconDB lookup
@export var cooldown: int = 0
@export var behaviour_tags: Array[StringName] = []   # was: tags (renamed in 021)
@export var mood: Array[StringName] = []
@export var level: int = 0
@export var abilities: Array[Ability] = []

var _cd_remaining: int = 0
# 031 phase 4 — true between cast() and the very next tick_cooldown call,
# which fires inside the same world_turn_ended as the cast itself. Set on
# cast (cooldown>0), cleared by the absorbing tick.
var _skip_next_tick: bool = false


func is_ready() -> bool:
	return _cd_remaining <= 0


## Pre-check for UI slot greying. Castable iff (a) skill is off cooldown
## and (b) the first ability accepts the current ctx. Without the
## is_ready guard, slot bar wouldn't grey out on cooldown (and the
## set_castable early-return short-circuits cd label refreshes — see
## spec 031 phase 3). Spec 031 phase 3.
func can_apply(caster: Actor, ctx: Dictionary) -> bool:
	if abilities.is_empty():
		return false
	if not is_ready():
		return false
	return (abilities[0] as Ability).can_apply(caster, ctx)


## Damage preview for hover UI. Sums predicted_damage_to across all abilities,
## passing this skill's level so previewed numbers match what the cast will deal.
func predicted_damage_to(caster: Actor, target: Actor, ctx: Dictionary) -> int:
	var total: int = 0
	for ab in abilities:
		total += (ab as Ability).predicted_damage_to(caster, target, ctx, level)
	return total


## Returns all contained ability IDs. Used by MoveRangeOverlay for attack-range painting.
func get_ability_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for ab in abilities:
		ids.append((ab as Ability).id)
	return ids


func cast(caster: Actor, ctxs: Array[Dictionary], fx: Object = null) -> bool:
	if not is_ready():
		GameLogger.info("Skill", "%s on cooldown (%d remaining)" % [id, _cd_remaining])
		return false

	# 026: ctxs is one Dictionary per ability — caller collects targets in phase 1.
	if ctxs.size() != abilities.size():
		GameLogger.error("Skill", "%s: ctxs.size()=%d != abilities.size()=%d" % [id, ctxs.size(), abilities.size()])
		return false

	var any_resolved: bool = false
	var all_target_ids: Array = []

	for i in abilities.size():
		var ab: Ability = abilities[i] as Ability
		# 047: split resolve / FX / apply per ability so visuals land BEFORE
		# damage. Empty plan → ability is pure no-op (e.g. target died after
		# the previous ability in this skill killed it). Skill continues to
		# the next ability instead of failing the whole cast.
		var plan: Dictionary = ab.resolve(caster, ctxs[i], level)
		if plan.is_empty():
			continue

		# 047: announce the cast BEFORE FX/apply. victim_ids extracted from
		# the plan's victims array — Actor instances filtered. UI listeners
		# (telegraph hide, preview clear, future cast-bar) hook here.
		var victim_ids: Array = []
		for v in plan.get("victims", []):
			if v is Actor:
				victim_ids.append((v as Actor).actor_id)
		EventBus.ability_cast_started.emit(caster.actor_id, ab.id, victim_ids)

		# 047: FX phase — sound_start + caster anim (parallel inside play_cast),
		# then collision shader on victims (or hex pulse on summon coords —
		# play_collisions dispatches by registry kind). fx is duck-typed Object
		# so core stays free of presentation imports — null-safe for non-FX
		# call sites (tests, headless, AI without a visible scene).
		if fx != null:
			await fx.play_cast(caster, ab)
			await fx.play_collisions(caster, ab, plan, ctxs[i])

		# 047: apply phase — effects run AFTER visuals. damage_dealt / heal_done
		# emit from inside DamageEffect.apply / HealEffect.apply, so floating
		# numbers spawn after the flash, which is the desired UX order.
		var resolved: bool = ab.apply_resolved(plan, caster, ctxs[i])

		# 047: sound_end at primary impact pos. Fire-and-forget — happens in
		# parallel with whatever comes next in this loop.
		if fx != null and resolved:
			fx.play_sound_end(_primary_world_pos(plan, caster), ab)

		if resolved:
			any_resolved = true
			# 015 / F-014: aggregate per-ability target_ids into skill-level emit.
			# Read last_target_ids immediately after apply_resolved — see Ability docstring.
			for tid in ab.last_target_ids:
				if not all_target_ids.has(tid):
					all_target_ids.append(tid)

	if any_resolved:
		_cd_remaining = cooldown
		# 031 phase 4: world_turn_ended fires later in the same advance() that
		# closes this turn → tick_cooldown lands inside the cast turn. Skip it
		# once so 'cooldown=N' means N rounds of skip, not N-1.
		if cooldown > 0:
			_skip_next_tick = true
		EventBus.skill_cast.emit(caster.actor_id, id, all_target_ids)
		GameLogger.info("Skill", "%s cast by %s → cd=%d" % [id, caster.actor_id, _cd_remaining])

	return any_resolved


## 047: best-effort world position for sound_end placement. First Actor victim
## wins; falls back to primary if it's an Actor; falls back to caster.
func _primary_world_pos(plan: Dictionary, caster: Actor) -> Vector2:
	for v in plan.get("victims", []):
		if v is Actor:
			return (v as Actor).global_position
	var primary: Variant = plan.get("primary")
	if primary is Actor:
		return (primary as Actor).global_position
	if caster != null:
		return caster.global_position
	return Vector2.ZERO


## Reduce remaining cooldown by `by` turns. Called from
## godmode_controller._tick_all_skills once per round per live actor.
func tick_cooldown(by: int = 1) -> void:
	# 031 phase 4: absorb the very first tick after a cast (see cast() above).
	if _skip_next_tick:
		_skip_next_tick = false
		return
	_cd_remaining = maxi(0, _cd_remaining - by)


## 034: returns a fresh copy with its own cooldown state — call this when
## an Actor takes ownership of a skill resource so cooldowns don't leak
## between owners (Skill is a Resource → SkillDatabase.get_skill returns
## a single shared instance). `abilities` array stays shared (Ability has
## no per-cast persistent state — last_target_ids is read immediately
## after cast(), no race in single-threaded execution).
func clone_for_owner() -> Skill:
	var copy: Skill = self.duplicate()   # shallow — abilities[] shared
	copy._cd_remaining = 0
	copy._skip_next_tick = false
	return copy
