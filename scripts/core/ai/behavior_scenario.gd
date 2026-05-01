class_name BehaviorScenario
extends Resource
## BehaviorScenario — named AI behavior loaded from data/ai_behaviors/<id>.json.
## Referenced from data/enemies/<id>.json's behavior_id field.
## See spec/008 AC-S2.

@export var id: StringName = &""
## Ordered: planner evaluates top-to-bottom, fires the first rule whose condition
## passes AND has ≥ min_skill_count matching ready skills.
@export var rules: Array[TacticRule] = []
## Used when no rule fires. Returned step is fed to move_intent_coord.
@export var movement_policy: MovementPolicy
## Final fallback if no rule fires AND movement_policy returned (-1,-1) AND this
## skill is ready AND has a valid target. Backward-compat with current manekin.
@export var fallback_skill_id: StringName = &""
