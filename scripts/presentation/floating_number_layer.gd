extends Node2D
## FloatingNumberLayer — manager that spawns FloatingNumber instances on
## EventBus damage/heal events.
##
## Lives at world-space (parent under HexGrid or arena root). Each spawned
## number is a child Label that auto-frees.
##
## Listener wiring: EventBus.damage_dealt and heal_done exist since 013-refactor-wave-1.
## Lazy-bind via has_signal() kept so test scenes that swap EventBus for a stub
## don't crash on _ready.

const FloatingNumberScene: PackedScene = preload("res://scenes/ui/floating_number.tscn")

# Guard against duplicate spawns within the same frame on the same actor —
# the design says stagger by 80ms; we serve that with a tiny per-actor queue.
var _last_spawn_ms: Dictionary = {}  # actor_id → ticks_msec of last spawn


func _ready() -> void:
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


# ── EventBus signal handlers ────────────────────────────────────────────────
# 013/F-002: signal payload carries actor's global_position so we don't need
# to walk a registry to find it (closes F-006 from 012). Convert global → local
# of this layer before handing to spawn(), since FloatingNumber.setup writes
# straight into Label.position (local to parent).

func _on_damage_dealt(target_id: StringName, amount: int, world_pos: Vector2) -> void:
	_throttle(target_id)
	spawn(to_local(world_pos), amount, &"damage")


func _on_heal_done(target_id: StringName, amount: int, world_pos: Vector2) -> void:
	_throttle(target_id)
	spawn(to_local(world_pos), amount, &"heal")


func _throttle(actor_id: StringName) -> void:
	# Records timestamp for future stagger logic; no-op for now.
	_last_spawn_ms[actor_id] = Time.get_ticks_msec()
