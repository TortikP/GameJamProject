class_name RootedRuntime
extends StatusRuntime
## rooted — speed = 0. Перетирает любые модификации скорости (включая slowed).
## AI policy через override_movement видит sentinel и не двигается.
## Cast-intent не блокируется — рутнутый actor может бить с места.
## 027: spec §"Контракт статусов" / AC-RT-rooted.


static func modify_speed(_current: int, _instance: StatusInstance) -> int:
	return 0


static func override_movement(_actor: Actor, _instance: StatusInstance, _ctx: Dictionary) -> Vector2i:
	return Vector2i(-2, -2)
