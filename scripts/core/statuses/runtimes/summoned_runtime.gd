class_name SummonedRuntime
extends StatusRuntime
## summoned(d) — entity lifetime tracker. Decrement по 1 за turn (через
## стандартный Actor.tick_statuses); при duration<=0 → on_remove убивает.
## d=-1 → infinite (Actor.tick_statuses пропускает декремент при duration<0).
##
## NB: только для actor'ов. Tile-object'ы используют side-table в
## TileObjectResolver._summon_timers — у них нет статусной системы.
## См. specs/041-effect-create-entity/.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")


## Stash original duration in snapshot_value — useful for inspectors / future UI.
## Not used in lifetime logic (which reads instance.duration directly).
static func compute_snapshot(args: Array[int], _skill_level: int) -> int:
	if args.size() == 0:
		return 0
	return args[0]


## Called when status is removed. If duration <= 0, this is a natural expire →
## destroy actor via kill_with_reason (bypasses take_damage pipeline → ignores
## shielded absorption / future damage_reduction tiers; summon timer must NOT
## be cancellable by piling defensive buffs on the entity). If duration > 0,
## status was removed externally (e.g. dispel, not implemented in 041) →
## don't kill, just log.
static func on_remove(actor: Actor, instance: StatusInstance) -> void:
	if not actor.is_alive():
		return  # already dead by combat; status removed via dead-cleanup, no-op
	if instance.duration > 0:
		GameLogger.info("SummonedRuntime", "%s summoned removed early (duration=%d) — not killing" % [actor.actor_id, instance.duration])
		return
	GameLogger.info("SummonedRuntime", "%s summoned expired — destroying" % actor.actor_id)
	actor.kill_with_reason("summon expired")
