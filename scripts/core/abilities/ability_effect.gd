class_name AbilityEffect
extends Resource
## AbilityEffect — abstract base. "What does the spell do to one target?"
##
## Subclasses override apply(). Called once per resolved victim.
## target is Variant (Actor | Vector2i | Object) — subclasses cast and validate.
## Clean no-op if the cast fails.
##
## 007: added duration, requires_alive_target; target → Variant.
## 021: added apply_level virtual.
## 021 (post-merge): removed `id` and `type` fields — `kind` from JSON was the
## sole discriminator (resolved at parse-time via AbilityDatabase).
## 026: `kind` itself is removed from the JSON schema. The effect class is
## now inferred from key-presence in the effect dict (e.g. `damage` →
## DamageEffect). Multiple keys → fan-out into N typed instances in
## EFFECT_KEY_ORDER (damage → heal → status → move → create).
## 027: `duration` is removed from the base. Status-effect duration is
## encoded inline in the JSON status string (`"id(d, ...)"`); other effect
## kinds (damage/heal/move/create) were never DoT/HoT in practice — the
## TODO scaffolds in subclasses are dropped.

@export var requires_alive_target: bool = true


func apply(_caster: Actor, _target: Variant, _ctx: Dictionary) -> void:
	push_warning("AbilityEffect.apply() not overridden on %s" % get_script().resource_path)


## 021: skill-level scaling hook. Default no-op; subclasses with `damage`,
## `heal`, or scaling parameters override per spec §"Уровень навыка".
## Called on a duplicate before apply(), so the base resource stays untouched.
## level=0 is the safe identity (overrides should early-out).
func apply_level(_level: int) -> void:
	pass
