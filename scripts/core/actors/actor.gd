class_name Actor
extends Node2D
## Actor — minimal HP-bearing entity. Player and dummies share this contract.
##
## Responsibilities:
##   - Own hp / max_hp.
##   - Expose take_damage(amount) and emit `damaged` / `died` signals.
##   - Emit EventBus.actor_died on death (one-shot, idempotent).
##   - 027: own active StatusInstance dict + dispatch tick to runtimes.
##
## NON-responsibilities:
##   - Movement (HexGrid handles position by id).
##   - AI (separate component, not on this PR).
##   - Visuals (subclass adds Polygon2D / Sprite2D as child).

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

signal damaged(id: StringName, amount: int, hp_left: int)
signal died(id: StringName)
# 027: emitted whenever _statuses changes — UI subscribes to rebuild pill strip.
signal statuses_changed(actor_id: StringName)
signal passives_changed(actor_id: StringName)

@export var actor_id: StringName = &""
@export var max_hp: int = 100
@export var team: StringName = &"neutral"   # &"player" / &"enemy" / &"neutral"
@export var behavior_id: StringName = &""   # 008: id in BehaviorDatabase. &"" → fallback default_melee.
@export var speed: int = 1                  # hex steps per turn (0 = immobile)
@export var damage_bonus: int = 0           # flat bonus added to any DamageEffect cast by this actor

## 037: status ids this actor refuses to receive. Checked in add_status — listed
## ids never apply (no on_apply, no statuses_changed, no EventBus emit). Symmetric:
## player sets [&"stunned"] in player.tscn; enemies can opt out of feared/enraged/etc
## via their own scene or (future) JSON data. Empty by default.
@export var status_immunities: Array[StringName] = []

var hp: int = 0
var _dead: bool = false
var _ability_ids: Array[StringName] = []
var _skills: Array = []   # Array[Skill] — plain Array to avoid typed-array Variant edge cases (CLAUDE.md trap)
var _passive_skills: Array = []
# 008: AI-planned (or player-issued) cast for the next resolve tick. null = no cast this turn.
# Type intentionally untyped (Variant) — CastIntent class is loaded lazily; keeping this as a
# concrete type would force every Actor consumer to preload it. Read via `actor.cast_intent`.
var cast_intent: Resource = null
var move_intent_coord: Vector2i = Vector2i(-1, -1)   # 008: planned move target. (-1,-1) = no move.

# 027: status state. Dictionary not Array[StatusInstance] — CLAUDE trap #6
# (Array[Resource] capricious with subclasses through Variant boundary).
var _statuses: Dictionary = {}   # StringName status_id -> StatusInstance

# 027: behavior-override slot for feared/enraged. Mutually exclusive — only one
# of feared/enraged active at a time on an Actor (AC-RA3). _BEHAVIOR_OVERRIDE_IDS
# enumerates which status_ids participate in this slot.
var _original_behavior_id: StringName = &""
var _behavior_override_id: StringName = &""
const _BEHAVIOR_OVERRIDE_IDS: Array[StringName] = [&"feared", &"enraged"]


## Returns ability ids available to this actor (set externally by controller or subclass).
func get_abilities() -> Array[StringName]:
	return _ability_ids


## Called by controller/subclass to declare which abilities this actor has.
func set_abilities(ids: Array[StringName]) -> void:
	_ability_ids = ids


## Returns Skill objects on this actor. Controllers call tick_skills() each turn.
func get_skills() -> Array:
	return _skills


func set_skills(skills: Array) -> void:
	_skills = skills


func get_passive_skills() -> Array:
	return _passive_skills


func set_passive_skills(skills: Array) -> void:
	_passive_skills = skills
	passives_changed.emit(actor_id)


func get_loot_skills() -> Array:
	var out: Array = []
	for skill in _skills:
		if skill != null and not out.has(skill):
			out.append(skill)
	for skill in _passive_skills:
		if skill != null and not out.has(skill):
			out.append(skill)
	return out


## 034: lookup an actor's per-instance Skill by id. AI cast resolution
## (and player cast paths) must read cooldown state from the *actor's*
## skill copy, not from the SkillDatabase shared instance — see spec 034.
## Returns null if the actor doesn't own a skill with this id.
func get_skill_by_id(skill_id: StringName) -> Skill:
	for s in _skills:
		if (s as Skill).id == skill_id:
			return s
	return null


## Reduce cooldown on all skills by 1. Call from controller on each turn advance.
func tick_skills(by: int = 1) -> void:
	for s in _skills:
		s.tick_cooldown(by)


func passive_move_speed_bonus() -> int:
	return _passive_int_sum(&"move_speed")


func passive_damage_bonus() -> int:
	return _passive_int_sum(&"damage_bonus")


func passive_damage_reduction() -> int:
	return _passive_int_sum(&"damage_reduction")


func passive_range_bonus() -> int:
	return _passive_int_sum(&"range_bonus")


func passive_cooldown_reduction() -> int:
	return _passive_int_sum(&"cooldown_reduction")


func passive_status_duration_bonus() -> int:
	return _passive_int_sum(&"status_duration_bonus")


func passive_offer_bonus() -> int:
	return _passive_int_sum(&"offer_count_bonus")


func passive_ranged_push_distance() -> int:
	return _passive_int_sum(&"ranged_push")


func _passive_int_sum(kind: StringName) -> int:
	var sum: int = 0
	for skill_v in _passive_skills:
		var skill: Skill = skill_v as Skill
		if skill == null:
			continue
		for eff in skill.passive_effects:
			if StringName(str(eff.get("kind", ""))) == kind:
				sum += int(eff.get("amount", 0))
	return sum


func _ready() -> void:
	hp = max_hp
	if actor_id == &"":
		GameLogger.warn("Actor", "spawned with empty actor_id — abilities can't target it")
	# 027: optional over-actor StatusIconStrip child. Bind if present; not all
	# scenes (tests, sandbox dummies) need one. Child's own _ready ran first
	# per Godot scene-tree order, so bind_actor is safe to call here.
	if has_node("StatusIconStrip"):
		var strip: Node = get_node("StatusIconStrip")
		if strip.has_method("bind_actor"):
			strip.bind_actor(self)
	else:
		GameLogger.info("Actor", "%s: no StatusIconStrip child (statuses won't render over actor)" % actor_id)


# ── Damage / heal ───────────────────────────────────────────────────────────

func take_damage(amount: int) -> void:
	if _dead or amount <= 0:
		return
	# 027: shielded (and any future damage_reduction status) absorbs first.
	var reduced: int = maxi(0, amount - damage_reduction())
	hp = max(0, hp - reduced)
	# `damaged` (HP-state) only fires when HP actually changed — semantic for
	# HealthBar redraw. damage_dealt (UI feedback channel) fires unconditionally
	# so a fully-absorbed hit shows a "0" floating number instead of looking
	# like the cast missed. (027 fix per spec §"Open after playtest" #6.)
	if reduced > 0:
		damaged.emit(actor_id, reduced, hp)
	EventBus.damage_dealt.emit(actor_id, reduced, global_position)
	if reduced != amount:
		GameLogger.info("Actor", "%s -%d hp (%d/%d) [absorbed %d]" % [actor_id, reduced, hp, max_hp, amount - reduced])
	else:
		GameLogger.info("Actor", "%s -%d hp (%d/%d)" % [actor_id, reduced, hp, max_hp])
	if hp == 0:
		_dead = true
		_emit_death_events()


## Restore a fixed amount of HP. Clamps to max_hp. No-op on dead actors.
func heal(amount: int) -> void:
	if _dead or amount <= 0:
		return
	var old_hp: int = hp
	hp = mini(max_hp, hp + amount)
	var healed: int = hp - old_hp
	if healed <= 0:
		return
	# Reuse damaged signal with negative amount as "healed" convention.
	# hp_left is the new hp. Listeners use amount <= 0 to detect heals.
	damaged.emit(actor_id, -healed, hp)
	# 013/F-002: dedicated UI-event channel — positive amount, separate signal.
	# Listeners that only want heals don't need to filter the legacy `damaged`.
	EventBus.heal_done.emit(actor_id, healed, global_position)
	GameLogger.info("Actor", "%s +%d hp (%d/%d)" % [actor_id, healed, hp, max_hp])


## Instant death with a logged reason (e.g. "crushed" by no-target push-out
## from 024-wave-editor). Idempotent on already-dead actors. Bypasses
## take_damage hooks (no damage_dealt emit, no per-amount HP step) — this is
## a discrete out-of-combat death event. Fires `died` and `EventBus.actor_died`
## exactly once.
func kill_with_reason(reason: String) -> void:
	if _dead:
		return
	hp = 0
	_dead = true
	GameLogger.info("Actor", "%s killed (%s)" % [actor_id, reason])
	# Reuse `damaged` so HealthBar repaints to 0. Amount = current full bar
	# (semantic "state changed, hp now 0") — listeners using amount<=0 for
	# heal won't misinterpret because hp_left is also 0.
	damaged.emit(actor_id, max_hp, hp)
	_emit_death_events()


func is_alive() -> bool:
	return not _dead


func _emit_death_events() -> void:
	EventBus.actor_died_snapshot.emit(actor_id, team, _death_skill_ids())
	died.emit(actor_id)
	EventBus.actor_died.emit(actor_id)


func _death_skill_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for skill_v in get_loot_skills():
		var skill: Skill = skill_v as Skill
		if skill == null or skill.id == &"":
			continue
		if ids.has(skill.id):
			continue
		ids.append(skill.id)
	return ids


## Restore HP to max and clear death state. Used by godmode reset (F2),
## debug/cheat tooling, fountain-tile heal effects, etc.
func heal_to_full() -> void:
	_dead = false
	hp = max_hp
	# Piggyback existing signal so HealthBar (and anything else listening)
	# repaints. Amount=0, hp_left=hp — semantic 'state changed, redraw'.
	damaged.emit(actor_id, 0, hp)
	GameLogger.info("Actor", "%s healed to full (%d/%d)" % [actor_id, hp, max_hp])


# ── 027: Statuses ───────────────────────────────────────────────────────────

## Apply a StatusInstance. Re-apply with the same status_id replaces the
## existing instance (AC-RA1). Mutual exclusivity: applying feared while
## enraged is active (or vice versa) silently removes the active one first
## (AC-RA3). Fires runtime.on_remove for the old instance and on_apply for
## the new one. Emits statuses_changed once.
func add_status(instance: StatusInstance) -> void:
	if instance == null or instance.status_id == &"":
		return
	# 037: immunity guard — refuse listed status_ids before any side effects.
	# Order matters: must run BEFORE the _BEHAVIOR_OVERRIDE_IDS removal block,
	# otherwise we'd evict an existing feared to make room for a stunned we
	# then refuse. info-level log: this is expected behavior, not an error.
	if instance.status_id in status_immunities:
		GameLogger.info("Actor", "%s immune to %s — refused" % [actor_id, instance.status_id])
		return
	# Mutual exclusivity for behavior-override statuses.
	if instance.status_id in _BEHAVIOR_OVERRIDE_IDS:
		for other_id in _BEHAVIOR_OVERRIDE_IDS:
			if other_id != instance.status_id and _statuses.has(other_id):
				remove_status(other_id)   # fires on_remove → restore behavior_id
	# Re-apply: fire on_remove for the existing instance before overwriting.
	if _statuses.has(instance.status_id):
		var old: StatusInstance = _statuses[instance.status_id]
		var old_rt: GDScript = StatusRegistry.runtime_for(old.status_id)
		if old_rt != null:
			old_rt.on_remove(self, old)
	_statuses[instance.status_id] = instance
	var rt: GDScript = StatusRegistry.runtime_for(instance.status_id)
	if rt != null:
		rt.on_apply(self, instance)
	statuses_changed.emit(actor_id)
	# 034: replan trigger. Listener (godmode_controller) recomputes the
	# enemy's intent under the new status (rooted/stunned/feared/enraged
	# change available actions; plan() handles them all). Fired after
	# on_apply + statuses_changed so listeners see fully-bound state.
	EventBus.actor_status_added.emit(actor_id, instance.status_id)


## Remove a status by id. No-op if not present. Fires on_remove. Emits
## statuses_changed when something was actually removed.
func remove_status(id: StringName) -> void:
	if not _statuses.has(id):
		return
	var inst: StatusInstance = _statuses[id]
	var rt: GDScript = StatusRegistry.runtime_for(id)
	if rt != null:
		rt.on_remove(self, inst)
	_statuses.erase(id)
	statuses_changed.emit(actor_id)


## Returns Array[StatusInstance] (untyped Array — Variant boundary).
func get_statuses() -> Array:
	return _statuses.values()


## Lookup by id; null if not active. Used by AI planner for source-tracking.
func get_status(id: StringName) -> StatusInstance:
	return _statuses.get(id, null) as StatusInstance


func has_status(id: StringName) -> bool:
	return _statuses.has(id)


func is_stunned() -> bool:
	return _statuses.has(&"stunned")


## Effective speed = base speed after running through every active runtime's
## modify_speed. Order: base → each runtime in dictionary insertion order.
## rooted clamps to 0 (rooted_runtime returns 0). slowed halves.
func effective_speed() -> int:
	var s: int = speed + passive_move_speed_bonus()
	for inst_v in _statuses.values():
		var inst := inst_v as StatusInstance
		var rt: GDScript = StatusRegistry.runtime_for(inst.status_id)
		if rt != null:
			s = rt.modify_speed(s, inst)
	return maxi(0, s)


## Sum of damage_reduction across active statuses. Currently only shielded
## contributes; multi-shield stack would sum here (out of scope).
func damage_reduction() -> int:
	var sum: int = passive_damage_reduction()
	for inst_v in _statuses.values():
		var inst := inst_v as StatusInstance
		var rt: GDScript = StatusRegistry.runtime_for(inst.status_id)
		if rt != null:
			sum += rt.damage_reduction(inst)
	return maxi(0, sum)


## Signed sum of damage_amplifier across active statuses. strong returns
## positive, weak returns negative — they coexist via algebraic sum.
## Used by DamageEffect / predicted_damage_to: outgoing damage += this value.
## Final damage is clamped to 0 minimum at apply-site.
func damage_amplifier() -> int:
	var sum: int = passive_damage_bonus()
	for inst_v in _statuses.values():
		var inst := inst_v as StatusInstance
		var rt: GDScript = StatusRegistry.runtime_for(inst.status_id)
		if rt != null:
			sum += rt.damage_amplifier(inst)
	return sum


func tick_passives_with_ctx(ctx: Dictionary) -> void:
	if _dead or _passive_skills.is_empty():
		return
	for skill_v in _passive_skills:
		var skill: Skill = skill_v as Skill
		if skill == null:
			continue
		for eff in skill.passive_effects:
			_apply_passive_turn_effect(skill, eff, ctx)


func _apply_passive_turn_effect(skill: Skill, eff: Dictionary, ctx: Dictionary) -> void:
	var kind: StringName = StringName(str(eff.get("kind", "")))
	match kind:
		&"regen":
			heal(int(eff.get("amount", 0)))
		&"damage_aura":
			_apply_passive_damage_aura(eff, ctx)
		&"status_aura":
			_apply_passive_status_aura(skill, eff, ctx)


func _apply_passive_damage_aura(eff: Dictionary, ctx: Dictionary) -> void:
	var amount: int = int(eff.get("amount", 0))
	if amount <= 0:
		return
	for actor in _actors_in_passive_radius(eff, ctx):
		(actor as Actor).take_damage(amount)


func _apply_passive_status_aura(skill: Skill, eff: Dictionary, ctx: Dictionary) -> void:
	var status_id: StringName = StringName(str(eff.get("status_id", "")))
	var duration: int = int(eff.get("duration", 0))
	if status_id == &"" or duration <= 0:
		return
	var rt: GDScript = StatusRegistry.runtime_for(status_id)
	if rt == null:
		return
	var raw_args: Variant = eff.get("args", [])
	var args: Array[int] = [duration]
	if raw_args is Array:
		for arg in raw_args:
			args.append(int(arg))
	if StatusRegistry.arity_of(status_id) != args.size():
		return
	for actor in _actors_in_passive_radius(eff, ctx):
		var inst: StatusInstance = StatusInstance.new()
		inst.status_id = status_id
		inst.duration = duration
		inst.args = args.duplicate()
		inst.source_id = actor_id
		inst.snapshot_value = rt.compute_snapshot(args, skill.level)
		(actor as Actor).add_status(inst)


func _actors_in_passive_radius(eff: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var radius: int = int(eff.get("radius", 1))
	var grid: HexGrid = ctx.get("grid")
	var registry: ActorRegistry = ctx.get("registry")
	if grid == null or registry == null:
		return out
	var center: Vector2i = grid.get_coord(actor_id)
	if center == Vector2i(-1, -1):
		return out
	var coords: Array[Vector2i] = [center]
	coords.append_array(grid.reachable_within(center, radius, []))
	var coord_set: Dictionary = {}
	for coord in coords:
		coord_set[coord] = true
	for actor_v in registry.all():
		if not (actor_v is Actor):
			continue
		var actor: Actor = actor_v
		if actor == self or not actor.is_alive():
			continue
		if actor.team == team:
			continue
		if coord_set.has(grid.get_coord(actor.actor_id)):
			out.append(actor)
	return out


## Tick all statuses one turn. Called by godmode_controller from
## _on_world_turn_ended at the start of the turn, before AI plans / player
## acts. ctx is built by the caller (registry/grid/all_actors/turn) — passed
## through to runtime.on_turn_start so DoT-style runtimes can do source
## lookups via ctx["registry"].
##
## Order per actor: insertion order of _statuses (deterministic).
## DoT can kill actor mid-loop → short-circuit. Expired statuses (duration <= 0
## after decrement) are removed via remove_status (full path, on_remove fires).
func tick_statuses_with_ctx(ctx: Dictionary) -> void:
	if _dead:
		return
	if _statuses.is_empty():
		return
	# Snapshot keys to allow safe expire-during-iter (statuses can remove
	# themselves or set duration=0 for next sweep).
	var ids: Array = _statuses.keys()
	var to_remove: Array[StringName] = []
	var any_decremented: bool = false
	for id_v in ids:
		if not _statuses.has(id_v):
			continue   # cascaded-removed (e.g. by mutual exclusivity earlier)
		var inst := _statuses[id_v] as StatusInstance
		var rt: GDScript = StatusRegistry.runtime_for(inst.status_id)
		if rt != null:
			rt.on_turn_start(self, inst, ctx)
		if _dead:
			return   # DoT killed us; remaining statuses won't tick this turn
		if inst.duration < 0:
			continue   # 041: infinite-duration sentinel — never decrement, never expire
		inst.duration -= 1
		any_decremented = true
		if inst.duration <= 0:
			to_remove.append(inst.status_id)
	for id in to_remove:
		remove_status(id)   # fires on_remove (e.g. behavior_id restore for feared/enraged)
	# 034: pure-decrement turns (no status expired) still need a UI rebuild —
	# StatusIconStrip listens to statuses_changed to refresh duration digits.
	# Without this emit, durations only redrew when something actually
	# expired, so players saw "3 → 1" with the "2" frame missing, and any
	# enemy carrying a single non-expiring status (e.g. slowed mid-flight)
	# kept its initial duration onscreen indefinitely. remove_status above
	# already emits per-removal — skip here to avoid double-emit on
	# expire-only turns.
	if any_decremented and to_remove.is_empty():
		statuses_changed.emit(actor_id)
