class_name WeakRuntime
extends StatusRuntime
## weak(d, n_debuff, lvl_bonus) — уменьшает весь outgoing урон actor'а
## на snapshot_value (через отрицательный damage_amplifier).
## Если strong и weak активны одновременно, их суммирует Actor.damage_amplifier.
## DamageEffect клампит итоговый урон через maxi(0, ...) — weak не уведёт в минус.
## 027.fix-2: новый статус.


static func compute_snapshot(args: Array[int], skill_level: int) -> int:
	# args = [duration, n_debuff, lvl_bonus]
	if args.size() < 3:
		return 0
	return args[1] + skill_level * args[2]


static func damage_amplifier(instance: StatusInstance) -> int:
	# Negative — sums algebraically with strong.
	return -maxi(0, instance.snapshot_value)
