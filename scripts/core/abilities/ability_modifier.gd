class_name AbilityModifier
extends Resource
## AbilityModifier — abstract base. "How does the ability behave differently?"
##
## Three hook points, executed in array order (no priorities, no magic):
##   before_apply(caster, targets, ctx) — before any effect.apply runs
##   after_apply(caster, target, ctx)   — after each individual effect.apply
##   after_cast(caster, targets, ctx)   — after all targets resolved
##
## See THEME_PLAN.md §4 for the full cast() lifecycle.
## Subclasses override only the hooks they need; defaults are no-ops.


func before_apply(_caster: Actor, _targets: Array, _ctx: Dictionary) -> void:
	pass


func after_apply(_caster: Actor, _target: Actor, _ctx: Dictionary) -> void:
	pass


func after_cast(_caster: Actor, _targets: Array, _ctx: Dictionary) -> void:
	pass
