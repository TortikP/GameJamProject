extends Node
## EventBus — global signal hub.
##
## All cross-module communication goes through these signals. Modules don't reference
## each other directly. Add new signals here when needed; renaming or removing an
## existing signal requires PR with `breaking:` prefix and approval from listeners' owners.
##
## Naming convention: snake_case, past tense (battle_started, wave_spawned).

# Signals here are intentionally public API: emitted/connected from other scripts,
# never from EventBus itself. Suppress GDScript's "declared but never used in this
# class" warning for the whole file — it's noise.
@warning_ignore_start("unused_signal")

# Battle
signal battle_started(arena_id: StringName)
signal battle_ended(victory: bool)
signal turn_started(actor_id: StringName)
signal spell_cast(actor_id: StringName, spell_id: StringName, targets: Array)

# Progression
signal wave_spawned(wave_index: int)
signal portal_opened
signal upgrade_offered(options: Array)
signal upgrade_chosen(modifier_id: StringName)

# Run cycle
signal run_started
signal run_ended(reason: String)
signal rewind_started
signal rewind_finished

# Dialogue
signal dialogue_started(dialogue_id: StringName)
signal dialogue_finished(dialogue_id: StringName)

# Arena
signal actor_moved(actor_id: StringName, from: Vector2i, to: Vector2i)
signal tile_entered(actor_id: StringName, coord: Vector2i)
signal tile_effect_triggered(actor_id: StringName, coord: Vector2i, effect_id: StringName)

# Tile Objects (018-tile-objects)
# Decoupling layer: hex_grid / pathfinder / future runtime resolver emit these,
# presentation + modifier engine listen. 018 declares the contract; the runtime
# resolver (019-tile-object-resolver) drives applies_on_*, aura ticks, linger.
signal tile_object_damaged(coord: Vector2i, hp_remaining: int)
signal tile_object_destroyed(coord: Vector2i, object_id: StringName)
signal tile_object_effect_triggered(coord: Vector2i, target_actor_id: StringName, effect_id: StringName)
signal tile_object_actor_exited(coord: Vector2i, actor_id: StringName, object_id: StringName)

# Turn loop
signal player_turn_ended(turn: int)
signal world_turn_ended(turn: int)

# Combat (composed-ability era; spell_cast above is legacy)
signal ability_cast(caster_id: StringName, ability_id: StringName, target_ids: Array)
signal skill_cast(caster_id: StringName, skill_id: StringName, target_ids: Array)  # 007
signal actor_died(id: StringName)

# Combat feedback (013-refactor-wave-1, F-002/F-003)
# Emitted by Actor.take_damage / Actor.heal. Listeners: floating_number_layer
# (spawns world-space numbers) and combat_log (ring buffer). amount is always
# positive — heal uses heal_done, damage uses damage_dealt. world_pos is the
# actor's global_position at emit time so listeners don't need a registry walk.
signal damage_dealt(target_id: StringName, amount: int, world_pos: Vector2)
signal heal_done(target_id: StringName, amount: int, world_pos: Vector2)

# UI infrastructure (009-ui-kit)
signal ui_theme_reloaded
signal ui_toast_requested(text: String, duration_sec: float, level: StringName)  # level ∈ info/success/warn/error
signal ui_modal_opened(id: StringName)
signal ui_modal_closed(id: StringName)

# Game flow (used by main menu, run summary, pause)
signal main_menu_entered
signal run_started_requested
signal run_summary_shown(summary: Dictionary)
signal pause_toggled(paused: bool)
