class_name FearedRuntime
extends StatusRuntime
## feared — на player'е no-op (вариант C из чата spec'а), на AI swap'ит
## behavior_id на &"feared" — отдельный сценарий с policy_kite_specific_actor.
## Source прокидывается AI-планировщику через ctx["behavior_target_id"].
## 027: spec §"Контракт статусов" / AC-RT-feared / AC-BO1..2.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const _BEHAVIOR_ID: StringName = &"feared"


static func on_apply(actor: Actor, _instance: StatusInstance) -> void:
	if actor == null or actor.team == &"player":
		return  # variant C: status хранится, runtime no-op на player'е
	if actor._behavior_override_id == &"":
		actor._original_behavior_id = actor.behavior_id
	actor._behavior_override_id = _BEHAVIOR_ID
	actor.behavior_id = _BEHAVIOR_ID
	GameLogger.info("FearedRuntime", "%s behavior_id swap → feared (was %s)" % [actor.actor_id, actor._original_behavior_id])


static func on_remove(actor: Actor, _instance: StatusInstance) -> void:
	if actor == null or actor.team == &"player":
		return
	# Если override уже занят другим (mutual-exclusivity branch в Actor.add_status
	# мог его перетереть на enraged) — не трогаем чужой restore.
	if actor._behavior_override_id != _BEHAVIOR_ID:
		return
	actor.behavior_id = actor._original_behavior_id
	actor._behavior_override_id = &""
	actor._original_behavior_id = &""
	GameLogger.info("FearedRuntime", "%s behavior_id restore → %s" % [actor.actor_id, actor.behavior_id])


## Source-validity check: если источник страха умер или удалён из registry —
## статус истекает в этот же tick (на следующем sweep'е on_remove restore'ит
## behavior_id).
static func on_turn_start(_actor: Actor, instance: StatusInstance, ctx: Dictionary) -> void:
	if instance.source_id == &"":
		return
	var registry: ActorRegistry = ctx.get("registry") as ActorRegistry
	if registry == null:
		return
	var src: Actor = registry.get_actor(instance.source_id)
	if src == null or not src.is_alive():
		instance.duration = 0
