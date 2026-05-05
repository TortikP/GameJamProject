class_name PoisonedRuntime
extends StatusRuntime
## poisoned(d, dmg_pct, lvl_bonus_pct) — в начале хода жертве наносится
## урон в процентах от max_hp; скейлится от Skill.level кастера на момент
## применения (snapshot).
##
## snapshot_value хранит итоговый процент. Раундинг — floor.
## 027: spec §"Контракт статусов" / AC-RT-poisoned.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")


static func compute_snapshot(args: Array[int], skill_level: int) -> int:
	# args = [duration, dmg_pct, lvl_bonus_pct]
	if args.size() < 3:
		return 0
	return args[1] + skill_level * args[2]


static func on_turn_start(actor: Actor, instance: StatusInstance, _ctx: Dictionary) -> void:
	if not actor.is_alive():
		return
	if actor.max_hp <= 0:
		return
	var dmg: int = int(floor(float(actor.max_hp) * float(instance.snapshot_value) / 100.0))
	if dmg <= 0:
		return
	GameLogger.info("PoisonedRuntime", "%s -%d (%d%% of %d)" % [actor.actor_id, dmg, instance.snapshot_value, actor.max_hp])
	actor.take_damage(dmg)
