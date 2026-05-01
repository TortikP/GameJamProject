class_name TacticRule
extends Resource
## TacticRule — one row in a BehaviorScenario's rule list.
## See spec/008 AC-S3.

@export var condition: TacticCondition
@export var target_selector: TargetSelector
## Ordered: first tag has highest priority. Skill matches if it has at least one
## of these tags; ranking by index of best matching tag (lower = preferred).
@export var tag_priority: Array[StringName] = []
## Rule fires only if at least N matching ready skills exist (default 1).
@export var min_skill_count: int = 1
