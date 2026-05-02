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

# Waves (024-wave-editor) — runtime wave lifecycle, separate from legacy
# `wave_spawned` (which still exists for the future roguelike loop's spawn
# announcements). 024's WaveController emits these.
signal wave_started(index: int, is_special: bool)
signal wave_cleared(index: int, unused_turns: int)
signal level_completed(total_score: int)
# 039: synthesized event — emitted by WaveController one frame before
# _apply_wave_snapshot on wave N>0. Allows triggers to react "before the
# new wave content is live". arg index = the incoming wave index.
signal wave_about_to_start(index: int)
# 039: emitted by godmode_setup after LevelData is fully applied (floor +
# objects + player spawned). Director caches the level ref here, then wires
# its event handlers when battle_started fires.
signal level_loaded(level: LevelData)
# 024: emitted when a deferred spawner-placeholder instantiates a real actor.
# Listeners (e.g. AI planner, HUD) can react to the new actor entering play.
signal actor_spawned(actor_id: StringName)

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
# 041-effect-create-entity: emitted by CreateEffect after summoning a tile
# object via grid.set_tile_object_id + resolver.add_summon_timer. Listeners
# (presentation: spawn FX / outline) can react. duration=-1 means infinite.
signal tile_object_summoned(coord: Vector2i, object_id: StringName, duration: int)

# Turn loop
signal player_turn_ended(turn: int)
signal world_turn_ended(turn: int)

# Combat (composed-ability era; spell_cast above is legacy)
signal ability_cast(caster_id: StringName, ability_id: StringName, target_ids: Array)
signal skill_cast(caster_id: StringName, skill_id: StringName, target_ids: Array)  # 007
signal actor_died(id: StringName)
# 034: emitted by Actor.add_status after on_apply + statuses_changed.
# godmode_controller listens to replan affected enemy + refresh telegraphs
# so a freshly-applied control status takes effect on the very next
# world_turn_ended (not the one after).
signal actor_status_added(actor_id: StringName, status_id: StringName)

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

# Game flow (used by main menu, pause)
signal main_menu_entered
signal run_started_requested
signal pause_toggled(paused: bool)

# 040-wave-skill-choice: between-wave skill pick modal lifecycle.
# Emitted by SkillOfferController autoload. wave_index = the wave that
# just cleared (offer happens AFTER it, BEFORE the next wave snapshot).
# mode ∈ {&"add", &"upgrade", &"replace", &"skipped"}; picked_skill_id is
# &"" on skipped. WaveController awaits skill_offer_closed in
# _check_auto_clear before _advance_wave when the cleared wave has a
# skill_offer.
signal skill_offer_about_to_open(wave_index: int, count: int, pool_id: StringName)
signal skill_offer_closed(wave_index: int, picked_skill_id: StringName, mode: StringName)

# 038: narrative mood tracker — emitted by MoodTracker on every recompute
# (driven from godmode_controller.sync_player_skills_from_slots after
# player.set_skills). Consumer: future DialogueManager line picker. Counts
# is a Dictionary[StringName, int] over MoodTracker.MOODS_SKILL; dominant
# is one of MOODS_SKILL ∪ {chimera}.
signal player_mood_changed(counts: Dictionary, dominant: StringName)

# Campaign / game flow (035-game-editor)
# scene_ready: emitted as the LAST line of a scene's _ready() after all its
# own initialisation. Read-only notification — listeners must not mutate world
# state, only react (e.g. CampaignController plays intro cutscene hook or
# fade-in transition).
signal scene_ready(scene_kind: StringName)
# upgrade_choice_requested: emitted by CampaignController when a level ends
# inside an active game. Listener owns the upgrade screen (real impl in a
# separate spec; 035 ships a dummy stub). Listener MUST eventually call
# on_done.call() — CampaignController times out after
# [meta]/upgrade_choice_timeout_sec and proceeds anyway.
signal upgrade_choice_requested(level_score: int, on_done: Callable)
# campaign_cutscene_requested: emitted by CampaignController on scene_ready
# of a level that has cutscene_id != &"" (or is_intro=true with non-empty id).
# Same callback contract as upgrade_choice_requested.
signal campaign_cutscene_requested(cutscene_id: StringName, on_done: Callable)
# campaign_level_started / campaign_finished: read-only notifications.
signal campaign_level_started(index: int, map_path: String)
signal campaign_finished(total_score: int)
