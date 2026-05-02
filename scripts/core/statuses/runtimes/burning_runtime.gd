class_name BurningRuntime
extends StatusRuntime
## burning(d, dmg, lvl_bonus) — фиксированный урон в начале хода жертвы,
## скейлится от Skill.level кастера на момент применения.
## 027: spec §"Контракт статусов" / AC-RT-burning.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")


static func compute_snapshot(args: Array[int], skill_level: int) -> int:
	# args = [duration, dmg, lvl_bonus]
	if args.size() < 3:
		return 0
	return args[1] + skill_level * args[2]


static func on_turn_start(actor: Actor, instance: StatusInstance, _ctx: Dictionary) -> void:
	if not actor.is_alive():
		return
	if instance.snapshot_value <= 0:
		return
	GameLogger.info("BurningRuntime", "%s -%d (burn)" % [actor.actor_id, instance.snapshot_value])
	actor.take_damage(instance.snapshot_value)
