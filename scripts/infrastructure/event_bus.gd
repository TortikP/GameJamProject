extends Node
## EventBus — global signal hub.
##
## All cross-module communication goes through these signals. Modules don't reference
## each other directly. Add new signals here when needed; renaming or removing an
## existing signal requires PR with `breaking:` prefix and approval from listeners' owners.
##
## Naming convention: snake_case, past tense (battle_started, wave_spawned).

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
