extends Node2D
## FloatingNumberLayer — manager that spawns FloatingNumber instances on
## EventBus damage/heal events.
##
## Lives at world-space (parent under HexGrid or arena root). Each spawned
## number is a child Label that auto-frees.
##
## Listener wiring: damage_dealt and heal_done signals are post-007. Until
## those exist, callers can spawn() directly. We connect lazily — only if
## the signal exists on EventBus at _ready time.

const FloatingNumberScene: PackedScene = preload("res://scenes/ui/floating_number.tscn")

# Guard against duplicate spawns within the same frame on the same actor —
# the design says stagger by 80ms; we serve that with a tiny per-actor queue.
var _last_spawn_ms: Dictionary = {}  # actor_id → ticks_msec of last spawn


func _ready() -> void:
	# Wire to forward-compat signals if EventBus has them.
	if EventBus.has_signal("damage_dealt"):
		EventBus.connect("damage_dealt", _on_damage_dealt)
	if EventBus.has_signal("heal_done"):
		EventBus.connect("heal_done", _on_heal_done)


## Public: spawn a single floating number at world_pos (in this layer's coord
## space). kind drives color + glyphs. Use this from controllers / tests.
func spawn(world_pos: Vector2, amount: int, kind: StringName) -> void:
	var n := FloatingNumberScene.instantiate() as Label
	add_child(n)
	if n.has_method("setup"):
		n.setup(world_pos, amount, kind)


# ── Forward-compat signal handlers ───────────────────────────────────────────
# These will be wired by 007/008 after EventBus gains the signals. For Phase 2
# they simply don't fire (signal absent).

func _on_damage_dealt(target_id: StringName, amount: int) -> void:
	var pos: Variant = _resolve_actor_pos(target_id)
	if pos == null:
		return
	_throttle(target_id)
	spawn(pos, amount, &"damage")


func _on_heal_done(target_id: StringName, amount: int) -> void:
	var pos: Variant = _resolve_actor_pos(target_id)
	if pos == null:
		return
	_throttle(target_id)
	spawn(pos, amount, &"heal")


func _throttle(actor_id: StringName) -> void:
	# Records timestamp for future stagger logic; no-op for now.
	_last_spawn_ms[actor_id] = Time.get_ticks_msec()


func _resolve_actor_pos(actor_id: StringName) -> Variant:
	# Walk parent chain looking for an ActorRegistry sibling. Best-effort —
	# returns null if registry isn't reachable. Real wiring happens in 007.
	var n := get_parent()
	while n != null:
		var reg := n.get_node_or_null("ActorRegistry")
		if reg != null and reg.has_method("by_id"):
			var actor: Node = reg.by_id(actor_id)
			if actor != null and actor is Node2D:
				return (actor as Node2D).position
			return null
		n = n.get_parent()
	return null
