class_name StrongRuntime
extends StatusRuntime
## strong(d, n_buff, lvl_bonus) — увеличивает весь outgoing урон actor'а
## на snapshot_value. Снапшот = n_buff + level * lvl_bonus.
## Применяется к КАСТЕРУ (т.е. кто наносит урон), не к target'у.
## Симметричный с shielded по форме (snapshot + flat modifier), но
## модифицирует урон с противоположной стороны boundary'а.
## 027.fix-2: новый статус.


static func compute_snapshot(args: Array[int], skill_level: int) -> int:
	# args = [duration, n_buff, lvl_bonus]
	if args.size() < 3:
		return 0
	return args[1] + skill_level * args[2]


static func damage_amplifier(instance: StatusInstance) -> int:
	return maxi(0, instance.snapshot_value)
