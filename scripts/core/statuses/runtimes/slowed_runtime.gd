class_name SlowedRuntime
extends StatusRuntime
## slowed — скорость уменьшается на 50%, не скейлится от уровня.
##
## Player: effective_speed() возвращает floor(speed/2). Player'у с speed=4
## становится 2 — он сам выбирает дистанцию через MoveRangeOverlay.
##
## AI: текущий policy шагает 1 hex/turn независимо от actor.speed, поэтому
## floor(1/2)=0 = «не двигается совсем» = слишком жёстко. Вместо этого
## делаем флип-флоп: каждый второй tick AI пропускает move_intent (через
## sentinel (-2,-2) от override_movement). Cast-intent при этом не блокируется.
## 027: spec §"Контракт статусов" / AC-RT-slowed.

const _FLIP_HOLD: int = 1


static func modify_speed(current: int, _instance: StatusInstance) -> int:
	# Floor division. Player с speed=4 → 2; speed=1 → 0; speed=0 → 0.
	return current / 2


static func on_turn_start(_actor: Actor, instance: StatusInstance, _ctx: Dictionary) -> void:
	# Toggle: 0 → 1 → 0 → ... первый tick после apply поднимает в 1
	# (AI на этом ходу holds), второй опускает в 0 (AI двигается).
	instance.rt_flag = _FLIP_HOLD - instance.rt_flag


static func override_movement(_actor: Actor, instance: StatusInstance, _ctx: Dictionary) -> Vector2i:
	if instance.rt_flag == _FLIP_HOLD:
		return Vector2i(-2, -2)
	return Vector2i(-1, -1)
