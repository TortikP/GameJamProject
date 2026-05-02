extends Node
## AiDriver — runs the per-world-turn enemy turn (Phase 1 RESOLVE, Phase 2 PLAN).
##
## Subscribes to EventBus.world_turn_ended via setup chain. Owns _world_processing
## flag (queryable via is_world_processing for input gates).
##
## Two-stage per enemy on world_turn_ended:
##   1. RESOLVE last turn's attack intent (if any). If player still on the
##      intent hex, attack lands; else attack misses (wasted turn). Clear
##      telegraph visual either way.
##   2. PLAN this turn:
##      a. If adjacent to player → don't move (preserve attacking position).
##      b. Else → step one hex toward player.
##   3. SET intent for next turn: if adjacent (now or after the step) AND
##      has attack_ability, intent = player's current coord. Show telegraph.
##
## Sequential per enemy. _world_processing locks player input during the loop.


const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

var _ctrl: Node = null
var _world_processing: bool = false  # true while AI takes its turn — locks player input


func _ready() -> void:
	_ctrl = get_parent()


func is_world_processing() -> bool:
	return _world_processing


func world_ctx() -> Dictionary:
	return {
		"registry": _ctrl.registry,
		"grid": _ctrl.grid,
		"all_actors": _ctrl.registry.all(),
		"turn": TurnManager.current(),
	}


## Re-plan ALL live enemies and refresh the telegraph layer. Used by
## ManekinSpawner.spawn() so a freshly-added dummy's intent is visible
## immediately, without the player having to end their turn first.
func replan_all_and_refresh() -> void:
	var registry: ActorRegistry = _ctrl.registry
	var enemies: Array = []
	for actor in registry.all():
		if actor is Actor and (actor as Actor).team == &"enemy":
			enemies.append(actor)
	var ctx: Dictionary = world_ctx()
	for actor in enemies:
		if actor is Actor and (actor as Actor).is_alive():
			EnemyAIPlanner.plan(actor as Actor, ctx)
	_ctrl.telegraphs.refresh()


func _on_world_turn_ended(_turn: int) -> void:
	if _world_processing:
		return
	var player: Actor = _ctrl.player
	if player == null or not player.is_alive():
		return
	_world_processing = true
	# 027 / AC-CT1: tick statuses for ALL actors before AI runs. DoT damage
	# may kill some — they're skipped naturally in subsequent loops.
	_tick_all_statuses()
	# 031: tick skill cooldowns for ALL actors. Must run before the stun-skip
	# branch below, otherwise a stunned actor's cooldowns freeze for the
	# stun's duration. See specs/031-skill-system-fixes.
	_tick_all_skills()
	# 027 / AC-X5: if player is stunned (newly applied or carried over),
	# show the icon for stun_skip_delay seconds, then auto-advance their turn.
	# Recursion is fine — next world_turn_ended will tick again, and either
	# decrement to expire or skip again.
	if player.is_alive() and player.is_stunned():
		await get_tree().create_timer(GameSpeed.get_value("arena", "stun_skip_delay", 0.4)).timeout
		_world_processing = false
		TurnManager.advance()
		return
	await _run_enemy_turn()
	_world_processing = false
	_ctrl.refresh_overlay()


# 027: status tick for all live actors. ctx mirrors what AI gets — runtimes
# (feared/enraged source-validity, and any future ctx-dependent runtime) read
# `registry` / `grid` / `all_actors` from it.
func _tick_all_statuses() -> void:
	var registry: ActorRegistry = _ctrl.registry
	if registry == null:
		return
	var ctx: Dictionary = world_ctx()
	for actor_v in registry.all():
		if not (actor_v is Actor):
			continue
		var actor: Actor = actor_v
		if actor.is_alive():
			actor.tick_statuses_with_ctx(ctx)


# 031: skill-cooldown tick for all live actors. Mirrors _tick_all_statuses.
# No ctx — Actor.tick_skills only needs the decrement amount. Dead actors
# skipped (their skills can't fire anyway; consistent with status helper).
func _tick_all_skills() -> void:
	var registry: ActorRegistry = _ctrl.registry
	if registry == null:
		return
	for actor_v in registry.all():
		if not (actor_v is Actor):
			continue
		var actor: Actor = actor_v
		if actor.is_alive():
			actor.tick_skills(1)


func _run_enemy_turn() -> void:
	var registry: ActorRegistry = _ctrl.registry
	var enemies: Array = []
	for actor in registry.all():
		if actor is Actor and (actor as Actor).team == &"enemy":
			enemies.append(actor)
	_ctrl.telegraphs.clear()

	# Phase 1: RESOLVE — execute everyone's planned move, then planned cast.
	# Movement first so casts happen from the post-move position.
	# 029 / B-001: defensive is_instance_valid — same reasoning as Phase 2,
	# an enemy can die from another enemy's cast (AoE friendly fire) earlier
	# in this loop's iteration.
	for actor in enemies:
		if not is_instance_valid(actor):
			continue
		if not (actor is Actor):
			continue
		var enemy: Actor = actor
		if not enemy.is_alive() or registry.get_actor(enemy.actor_id) == null:
			continue
		await _resolve_move_intent(enemy)
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		await _resolve_cast_intent(enemy)

	# Phase 2: PLAN — pick next move and next cast (writes cast_intent /
	# move_intent_coord on each enemy). Visuals rebuilt at the end of this loop.
	# 029 / B-001: with multi-step movement (req-5), an enemy can step through
	# a damage-zone tile in Phase 1 and die mid-resolve. Its node is queue_freed
	# but the local `enemies` array still holds the stale ref. `actor is Actor`
	# on a freed instance throws "Left operand of 'is' is a previously freed
	# instance". Filter via is_instance_valid BEFORE any other check.
	var ctx: Dictionary = world_ctx()
	for actor in enemies:
		if not is_instance_valid(actor):
			continue
		if not (actor is Actor):
			continue
		var enemy: Actor = actor
		if not enemy.is_alive() or registry.get_actor(enemy.actor_id) == null:
			continue
		EnemyAIPlanner.plan(enemy, ctx)

	_ctrl.telegraphs.refresh()


# ── Resolve helpers ──────────────────────────────────────────────────────────

func _resolve_move_intent(enemy: Actor) -> void:
	var grid: HexGrid = _ctrl.grid
	var registry: ActorRegistry = _ctrl.registry
	var intent: Vector2i = enemy.move_intent_coord
	enemy.move_intent_coord = Vector2i(-1, -1)
	if intent == Vector2i(-1, -1):
		return
	var enemy_coord: Vector2i = grid.get_coord(enemy.actor_id)
	if enemy_coord == intent:
		return  # already there (somehow)
	# Check destination is still walkable + unoccupied at execute-time
	# (another enemy may have ended up there during this Phase 1)
	if grid.get_actor_at(intent) != &"":
		GameLogger.info("AI", "%s: move blocked at %s" % [enemy.actor_id, intent])
		return
	# 029 / req-5: re-pathfind around the CURRENT actor positions and walk the
	# whole route (not just one step). Plan was made earlier this turn — other
	# enemies have shifted since, so we recompute. move_actor_along revalidates
	# each step's occupancy and breaks early on conflict.
	var blocked: Array = []
	for other_v in registry.all():
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if other == enemy or not other.is_alive():
			continue
		var c: Vector2i = grid.get_coord(other.actor_id)
		if c != Vector2i(-1, -1):
			blocked.append(c)
	var path: Array = grid.find_path_around(enemy_coord, intent, blocked)
	if path.size() < 2:
		return
	await grid.move_actor_along(enemy.actor_id, path)


## Resolves a previously-planned cast on `enemy`. Reads enemy.cast_intent (set
## by EnemyAIPlanner during Phase 2 of the previous turn). Generic over Skill —
## works for any target type / area / effect chain. AC-X5 re-validates target
## state at resolve time (target alive, in range, skill still ready).
func _resolve_cast_intent(enemy: Actor) -> void:
	var grid: HexGrid = _ctrl.grid
	var registry: ActorRegistry = _ctrl.registry
	var intent_v: Variant = enemy.cast_intent
	enemy.cast_intent = null
	if intent_v == null:
		return
	var intent: CastIntent = intent_v as CastIntent
	if intent == null or not intent.is_valid():
		return
	# 034: read the *enemy's* per-owner Skill copy, not the DB-shared one.
	# Otherwise cast() writes cooldown state onto the shared resource,
	# leaking cd between every actor that uses this skill_id.
	var skill: Skill = enemy.get_skill_by_id(intent.skill_id)
	if skill == null or not skill.is_ready():
		return

	# Re-validate target — entity may have died/moved between plan and resolve.
	var target_id: StringName = intent.target_id
	var target_coord: Vector2i = intent.target_coord
	if target_id != &"":
		var target_actor: Actor = registry.get_actor(target_id)
		if target_actor == null or not target_actor.is_alive():
			GameLogger.info("AI", "%s: cast cancelled (target gone)" % enemy.actor_id)
			return
		var live_coord: Vector2i = grid.get_coord(target_id)
		if live_coord == Vector2i(-1, -1):
			GameLogger.info("AI", "%s: cast cancelled (target off-grid)" % enemy.actor_id)
			return
		# Target moved? Old planned coord is stale — use current.
		target_coord = live_coord

	var ctx: Dictionary = {
		"registry": registry, "grid": grid,
		"target_id": target_id, "target_coord": target_coord,
	}
	# 026: AI broadcasts a single ctx to all abilities. Per-ability AI targeting
	# is out of scope — see specs/026-skill-system-v3/spec.md §"Out of scope".
	# can_apply re-validates range / castability at the moment of cast.
	var ctxs: Array[Dictionary] = []
	for _i in skill.abilities.size():
		ctxs.append(ctx)
	skill.cast(enemy, ctxs)
	await GameSpeed.wait("godmode", "ability_cast_delay")
