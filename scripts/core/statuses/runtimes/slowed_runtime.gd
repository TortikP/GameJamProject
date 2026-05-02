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
##
## 034: on_apply сетит rt_flag=_FLIP_HOLD на свежем инстансе. Это нужно
## потому что 034 добавляет replan-on-status-added — без on_apply tweak'а
## replan видит rt_flag=0 (free), планирует ход, и следующий RESOLVE
## двигает actor'а на ходу применения slowed. С rt_flag=1 на apply
## replan видит hold → ничего не планирует → первый ход slowed = no move.
## Первый tick тоггливает rt_flag→0 (free), Phase 2 планирует ход,
## следующий tick тоггливает rt_flag→1, Phase 1 RESOLVE его выполняет.
## Итого slowed(d=4) → 2 движения за 4 тика, ход применения hold'ится.
## Это закрывает 027 §"Open after playtest" #7 (slowed AI 1-tick lag).
##
## 027: spec §"Контракт статусов" / AC-RT-slowed.

const _FLIP_HOLD: int = 1


# 034: prime rt_flag=_FLIP_HOLD on a fresh instance so the post-add_status
# replan (godmode_controller._on_actor_status_added) sees override_movement
# returning hold and plans no move on the apply turn. First tick toggles
# rt_flag→0 (free), so Phase 2 plans normally, and the alternation continues.
static func on_apply(_actor: Actor, instance: StatusInstance) -> void:
	if instance == null:
		return
	instance.rt_flag = _FLIP_HOLD


static func modify_speed(current: int, _instance: StatusInstance) -> int:
	# Floor division. Player с speed=4 → 2; speed=1 → 0; speed=0 → 0.
	return current / 2


static func on_turn_start(_actor: Actor, instance: StatusInstance, _ctx: Dictionary) -> void:
	# Toggle: 1 ⇄ 0. on_apply primes rt_flag=1 (held), so the first tick after
	# apply lowers it to 0 (free → Phase 2 plans). The next tick raises it
	# back to 1 (held → Phase 2 holds), Phase 1 then resolves the previous
	# turn's move plan. Net: enemy moves every other tick, starting on W2.
	instance.rt_flag = _FLIP_HOLD - instance.rt_flag


static func override_movement(_actor: Actor, instance: StatusInstance, _ctx: Dictionary) -> Vector2i:
	if instance.rt_flag == _FLIP_HOLD:
		return Vector2i(-2, -2)
	return Vector2i(-1, -1)
