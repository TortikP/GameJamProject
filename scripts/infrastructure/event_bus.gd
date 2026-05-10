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

# 061: emitted when WaveController toggles its advance gate. True = next
# advance is blocked pending kill-of-last-enemy (advance_mode "clear" while
# enemies live, or "timer_and_clear" after ttn expired). False = advance
# is no longer blocked (next wave applied or mode allows timer advance).
# HUDs subscribe to surface a "(waiting for clear)" cue per Pillar 1.
signal wave_advance_blocked(blocked: bool)
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
# 047-skill-fx-system: emitted from Skill.cast immediately AFTER Ability.resolve
# returned a non-empty plan and BEFORE the FX phase (caster anim + sound_start,
# then collision flashes). Order vs ability_cast: started fires first, ability_cast
# fires after apply_resolved completes (so after damage_dealt/heal_done, after
# floating numbers spawn). Listeners that want to gate UI on "ability about to
# resolve" subscribe here; listeners that want "ability finished" use ability_cast.
signal ability_cast_started(caster_id: StringName, ability_id: StringName, victim_ids: Array)
signal skill_cast(caster_id: StringName, skill_id: StringName, target_ids: Array)  # 007
# Emitted by Actor immediately before actor_died, while the dying node still
# owns its team/skills. Consumers that need death loot snapshots should use
# this instead of racing cleanup listeners on actor_died.
signal actor_died_snapshot(id: StringName, team: StringName, skill_ids: Array)
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
# HUD HELP button (top-right) → HelpDropdown listens & toggles. Sibling
# of the centered KeybindOverlay (`?` keybind), shares the same binds()
# data; this one drops down under the HELP button so clicks elsewhere
# stay unblocked.
signal help_dropdown_toggle_requested

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
signal campaign_defeated(map_index: int, wave_index: int, is_final_boss_wave: bool)

# 048-corpse-absorption — corpse lifecycle (presentation-only entities,
# spawned by CorpseManager autoload on EventBus.actor_died, NOT in ActorRegistry).
# actor_corpse_spawned: emitted right after Corpse node mounted under grid/Corpses
# and play_death() kicked off. coord = hex coord at time of death (Vector2i.MAX
# if unknown — spawner outside grid context). corpse_node = the Corpse Node2D
# itself (presentation listeners can hook absorbed_arrived directly if needed).
# corpses_absorbing_started: emitted at the start of CorpseManager.play_absorption_ritual.
# count = current corpse count at start (0 allowed — heroine FX still play, D-4).
# total_sec = fixed total ritual duration (audio sync — same value for any count).
# corpses_absorbed: emitted after total_sec elapsed. WaveController awaits this
# before skill_offer / level_completed on the final wave.
signal actor_corpse_spawned(coord: Vector2i, corpse_node: Node)
signal corpses_absorbing_started(count: int, total_sec: float)
signal corpses_absorbed
