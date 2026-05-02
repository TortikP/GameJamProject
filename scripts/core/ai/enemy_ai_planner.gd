extends Node
## EnemyAIPlanner — picks an action for one enemy using its BehaviorScenario.
## Autoload, stateless (no per-call state retained).
## API: plan(actor, ctx) — writes actor.cast_intent and/or actor.move_intent_coord.
##
## Spec/008 AC-X1..X5, AC-GACT-1..3, Q-AI-3 (tiebreak), Q-AI-6 (no-anchor fallback).

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const DEFAULT_BEHAVIOR := &"default_melee"


## Plans an action for `actor` and writes intents on the actor itself.
## Caller (godmode_controller) reads cast_intent / move_intent_coord on next tick.
##
## ctx schema:
##   {
##     "registry": ActorRegistry,
##     "grid":     HexGrid,
##     "all_actors": Array,    # registry.all() snapshot
##     "turn":     int,        # current turn
##   }
func plan(actor: Actor, ctx: Dictionary) -> void:
	# Reset intents — every plan() starts fresh.
	actor.cast_intent = null
	actor.move_intent_coord = Vector2i(-1, -1)

	# AC-GACT-1: dead actors don't act.
	if not actor.is_alive():
		return

	# 027 / AC-RT-stunned: stunned actors skip planning entirely.
	if actor.is_stunned():
		return

	# 027 / AC-AI3: enrich ctx with behavior_target_id from active feared/enraged.
	# Mutual exclusivity (AC-RA3) means at most one is active. Enraged checked
	# first — but in practice add_status enforces only-one, so order is moot.
	# CTX is shared across iterations in godmode_controller's enemy loop; we
	# must clear stale state from the previous enemy before setting (or not).
	ctx.erase("behavior_target_id")
	var bid: StringName = &""
	var enr: StatusInstance = actor.get_status(&"enraged")
	if enr != null:
		bid = enr.source_id
	else:
		var fer: StatusInstance = actor.get_status(&"feared")
		if fer != null:
			bid = fer.source_id
	if bid != &"":
		ctx["behavior_target_id"] = bid

	# 027: status-driven movement override (slowed flip-flop / rooted hold).
	# Computed before scenario logic so we can suppress movement_policy.pick_step
	# if any active status returns the (-2,-2) hold sentinel. Cast-intent still
	# gets a chance — slowed/rooted don't block casting.
	var hold_movement: bool = false
	for inst_v in actor.get_statuses():
		var inst := inst_v as StatusInstance
		var rt: GDScript = StatusRegistry.runtime_for(inst.status_id)
		if rt == null:
			continue
		var ov: Vector2i = rt.override_movement(actor, inst, ctx)
		if ov == Vector2i(-2, -2):
			hold_movement = true
			break

	# Resolve scenario (with default fallback). 027: feared/enraged AI gets
	# its swapped behavior_id here, so the dedicated scenario is loaded.
	var scenario: BehaviorScenario = BehaviorDatabase.get_scenario(actor.behavior_id)
	if scenario == null:
		scenario = BehaviorDatabase.get_scenario(DEFAULT_BEHAVIOR)
	if scenario == null:
		# No fallback configured — log once, hold.
		GameLogger.warn("AI", "%s: no scenario for behavior_id=%s and no default_melee — hold" % [actor.actor_id, actor.behavior_id])
		return

	# AC-GACT-2: can't act if no skills AND policy is hold_position.
	var has_skills: bool = not actor.get_skills().is_empty()
	var policy_is_hold: bool = scenario.movement_policy is PolicyHoldPosition
	if not has_skills and policy_is_hold:
		return

	# AC-X3: try rules top-to-bottom.
	for rule in scenario.rules:
		if _try_rule(actor, rule, ctx):
			return  # cast_intent set, planning done

	# Fallback: movement. 027: suppress if any status held movement.
	if scenario.movement_policy != null and not hold_movement:
		actor.move_intent_coord = scenario.movement_policy.pick_step(actor, ctx)

	# Last-ditch: scenario.fallback_skill_id if defined and movement gave no anchor.
	if actor.move_intent_coord == Vector2i(-1, -1) and scenario.fallback_skill_id != &"":
		_try_fallback_skill(actor, scenario.fallback_skill_id, ctx)
		if actor.cast_intent != null:
			return

	# Q-AI-6: no rule fired, no anchor, no fallback → log and hold.
	if actor.move_intent_coord == Vector2i(-1, -1) and actor.cast_intent == null:
		GameLogger.info("AI", "%s: no action this turn (no anchor)" % actor.actor_id)


# ── Rule evaluation ──────────────────────────────────────────────────────────

# Returns true and writes actor.cast_intent if the rule fires successfully.
func _try_rule(actor: Actor, rule: TacticRule, ctx: Dictionary) -> bool:
	if rule == null or rule.condition == null or rule.target_selector == null:
		return false
	if not rule.condition.evaluate(actor, ctx):
		return false

	# Filter actor's skills by tag intersection with rule.tag_priority.
	# Sort by best matching tag's index in tag_priority (lower = better).
	# Tiebreak (Q-AI-3): original order in actor.get_skills().
	var skills: Array = actor.get_skills()
	var matched: Array = []   # Array of {skill, best_tag_idx, original_idx}
	for i in range(skills.size()):
		var s: Skill = skills[i]
		if s == null or s.behaviour_tags.is_empty():
			continue
		var best_idx: int = -1
		for tag in s.behaviour_tags:
			var tag_idx: int = rule.tag_priority.find(tag)
			if tag_idx >= 0 and (best_idx == -1 or tag_idx < best_idx):
				best_idx = tag_idx
		if best_idx >= 0:
			matched.append({"skill": s, "tag_idx": best_idx, "orig_idx": i})

	if matched.is_empty():
		return false

	# Sort: best_idx asc, then orig_idx asc (tiebreak).
	var sorter := func(a: Dictionary, b: Dictionary) -> bool:
		if a.tag_idx != b.tag_idx:
			return a.tag_idx < b.tag_idx
		return a.orig_idx < b.orig_idx
	matched.sort_custom(sorter)

	# Filter: ready + has valid target + target in range.
	var candidates: Array = _build_target_candidates(actor, rule.target_selector, ctx)
	# 015 / F-015: single duplicate of ctx, mutated in-place per candidate.
	# Keeping it inside the loop allocated a new Dict per matched skill — wasted
	# work in the AI hot path. sel_ctx is local, drops out of scope after loop.
	var sel_ctx: Dictionary = ctx.duplicate()
	var selectable: Array = []   # Array of {skill, target}
	for entry in matched:
		var s: Skill = entry.skill
		if not s.is_ready():
			continue
		# For densest_enemy_hex, the selector needs the candidate skill to compute area shape.
		sel_ctx["candidate_skill"] = s
		var target: Variant = rule.target_selector.resolve(actor, candidates, sel_ctx)
		if target == null:
			continue
		if not _target_in_skill_range(actor, s, target, ctx):
			continue
		selectable.append({"skill": s, "target": target})

	if selectable.size() < rule.min_skill_count:
		return false

	# Pick first → build cast_intent.
	var pick: Dictionary = selectable[0]
	var intent: CastIntent = CastIntent.new()
	intent.skill_id = (pick.skill as Skill).id
	if pick.target is Actor:
		intent.target_id = (pick.target as Actor).actor_id
		var grid: HexGrid = ctx.get("grid")
		if grid != null:
			intent.target_coord = grid.get_coord(intent.target_id)
	elif pick.target is Vector2i:
		intent.target_coord = pick.target
	actor.cast_intent = intent
	return true


# Build candidate list for a selector: enemies / allies / self depending on type.
func _build_target_candidates(actor: Actor, selector: TargetSelector, ctx: Dictionary) -> Array:
	var actors: Array = ctx.get("all_actors", [])
	if selector is SelectorSelf:
		return [actor]
	# 027 / AC-AI4: SelectorSpecificActor reads behavior_target_id, ignores
	# team filter. Singleton list (or empty if source is gone).
	if selector is SelectorSpecificActor:
		var bid: StringName = ctx.get("behavior_target_id", &"")
		if bid == &"":
			return []
		var registry: ActorRegistry = ctx.get("registry") as ActorRegistry
		if registry == null:
			return []
		var src: Actor = registry.get_actor(bid)
		if src == null or not src.is_alive():
			return []
		return [src]
	var want_allies: bool = selector is SelectorLowestHpAlly or selector is SelectorHighestHpAlly  # 030 AC-PL1
	var result: Array = []
	for other_v in actors:
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if not other.is_alive():
			continue
		if other == actor:
			continue
		var same_team: bool = other.team == actor.team
		if want_allies and not same_team:
			continue
		if not want_allies and same_team:
			continue
		result.append(other)
	return result


# Check if target is within max range of skill's first ability.
# target may be Actor, Vector2i, or null.
func _target_in_skill_range(actor: Actor, skill: Skill, target: Variant, ctx: Dictionary) -> bool:
	if target == null:
		return false
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return true   # can't verify, assume yes
	if skill.abilities.is_empty():
		return false
	var ab: Ability = skill.abilities[0]
	if ab == null or ab.target == null:
		return false
	# SelfTarget: always in range.
	if ab.target is SelfTarget:
		return true
	# Range query — works for ActorTarget and HexTarget.
	var max_range: int = -1
	if "range" in ab.target:
		max_range = int(ab.target.range)
	if max_range < 0:
		return true
	var caster_coord: Vector2i = grid.get_coord(actor.actor_id)
	var target_coord: Vector2i
	if target is Actor:
		target_coord = grid.get_coord((target as Actor).actor_id)
	elif target is Vector2i:
		target_coord = target
	else:
		return false
	var d: int = grid.hex_distance(caster_coord, target_coord)
	return d >= 0 and d <= max_range


# ── Fallback skill (backward-compat path for current manekin) ────────────────

func _try_fallback_skill(actor: Actor, skill_id: StringName, ctx: Dictionary) -> void:
	# 034: per-actor skill lookup so cooldown state is read from this
	# actor's own copy, not the DB-shared resource. Symmetric with the
	# main planner path (line 148: iterates actor's _skills directly).
	var skill: Skill = actor.get_skill_by_id(skill_id)
	if skill == null or not skill.is_ready():
		return
	# Fallback only triggers if there's an enemy in skill range — match current
	# manekin behavior (attacks only adjacent player). Use nearest_enemy selector ad-hoc.
	var sel := SelectorNearestEnemy.new()
	var candidates: Array = _build_target_candidates(actor, sel, ctx)
	var target: Variant = sel.resolve(actor, candidates, ctx)
	if not _target_in_skill_range(actor, skill, target, ctx):
		return
	var intent: CastIntent = CastIntent.new()
	intent.skill_id = skill_id
	if target is Actor:
		intent.target_id = (target as Actor).actor_id
		var grid: HexGrid = ctx.get("grid")
		if grid != null:
			intent.target_coord = grid.get_coord(intent.target_id)
	actor.cast_intent = intent
