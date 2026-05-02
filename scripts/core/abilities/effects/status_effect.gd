class_name StatusEffect
extends AbilityEffect
## Applies a registered status to an Actor. Effect-instance carries the
## already-parsed status_id and args; AbilityDatabase parses the JSON
## inline encoding `"id(d, a1, a2, ...)"` and fills these fields.
##
## At apply-time this builds a StatusInstance, computes its snapshot_value
## via the runtime's compute_snapshot(args, level), and hands it to
## actor.add_status (which fires runtime.on_apply for behavior swaps).
##
## 026: previously stored `status: StringName` and inherited `duration` from
## AbilityEffect base.
## 027: `args: Array[int]` carries duration + per-status numeric params;
## base.duration is gone.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const _StatusInstance = preload("res://scripts/core/statuses/status_instance.gd")

@export var status_id: StringName = &""
@export var args: Array[int] = []

# Snapshotted at apply_level — the Skill.cast pipeline calls duplicate(),
# then apply_level(level), then apply(...). We squirrel level away here so
# compute_snapshot has it at apply-time.
var _level: int = 0


## 021: scaling hook. We don't scale duration (it's args[0], designer-set).
## The numeric scaling for poisoned/burning/shielded happens inside
## the runtime's compute_snapshot, not here — but we need the level value
## available there, so cache it.
func apply_level(level: int) -> void:
	_level = level


func apply(caster: Actor, target: Variant, _ctx: Dictionary) -> void:
	var actor := target as Actor
	if actor == null:
		return
	if status_id == &"":
		GameLogger.warn("StatusEffect", "status_id is empty — skipping")
		return
	if args.is_empty():
		GameLogger.warn("StatusEffect", "args empty for status '%s' — skipping" % status_id)
		return
	if args[0] <= 0:
		GameLogger.info("StatusEffect", "duration <= 0 for '%s' — skipping" % status_id)
		return
	var rt: GDScript = StatusRegistry.runtime_for(status_id)
	if rt == null:
		GameLogger.warn("StatusEffect", "no runtime for '%s' — skipping" % status_id)
		return
	var inst: StatusInstance = _StatusInstance.new()
	inst.status_id = status_id
	inst.duration = args[0]
	inst.args = args.duplicate()
	inst.source_id = caster.actor_id if caster != null else &""
	inst.snapshot_value = rt.compute_snapshot(args, _level)
	actor.add_status(inst)
