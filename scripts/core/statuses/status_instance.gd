class_name StatusInstance
extends Resource
## StatusInstance — one active status on an Actor. Pure data; behaviour lives
## in StatusRuntime subclasses dispatched via StatusRegistry.
##
## 027: spec/027-status-effects/spec.md §"StatusInstance".

@export var status_id: StringName = &""
## Decrements by 1 each tick (start of world turn). <=0 → expire.
@export var duration: int = 0
## Raw args from JSON `"id(d, a1, a2, ...)"`. args[0] == initial duration.
## Kept around so re-apply / inspectors can show original parameters.
@export var args: Array[int] = []
## Caster.actor_id at apply-time. Used by feared/enraged for source-tracking
## and fear/rage source-validity checks. &"" if status was applied without a
## caster (e.g. dev tooling).
@export var source_id: StringName = &""
## Pre-computed scaling result. Filled by StatusRuntime.compute_snapshot at
## apply-time so runtime ticks don't redo arithmetic and don't depend on
## caster's level after the fact.
@export var snapshot_value: int = 0
## Stateful per-instance flag, free-form for runtimes (e.g. slowed flip-flop).
## Initialised 0; mutate via runtime.on_turn_start.
@export var rt_flag: int = 0
