class_name ShieldedRuntime
extends StatusRuntime
## shielded(d, n_block, lvl_bonus) — поглощает фиксированное кол-во
## входящего урона. Не consume'ится от каждого удара, decrement'ится
## только от tick'а duration. snapshot_value = n_block + level * lvl_bonus.
## 027: spec §"Контракт статусов" / AC-RT-shielded.


static func compute_snapshot(args: Array[int], skill_level: int) -> int:
	# args = [duration, n_block, lvl_bonus]
	if args.size() < 3:
		return 0
	return args[1] + skill_level * args[2]


static func damage_reduction(instance: StatusInstance) -> int:
	return maxi(0, instance.snapshot_value)
