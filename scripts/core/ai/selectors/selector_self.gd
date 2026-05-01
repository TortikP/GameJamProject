class_name SelectorSelf
extends TargetSelector
## AC-T4: pick actor itself. Used for self-targeted heal / buff.


func resolve(actor: Actor, _candidates: Array, _ctx: Dictionary) -> Variant:
	return actor
