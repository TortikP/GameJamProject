extends Node

## CampaignController — autoload that orchestrates the inter-level flow when
## an ActiveGame is loaded. Without an active game, every signal it listens
## to is short-circuited and standard godmode behaviour is unchanged.
##
## Flow on level victory (mid-game):
##   1. EventBus.level_completed received.
##   2. Emit upgrade_choice_requested(score, on_done). Wait for callback or
##      [meta]/upgrade_choice_timeout_sec — whichever first.
##   3. Spawn level_transition.tscn into the current scene as overlay.
##      play_out() (shake + distort + fade-to-black), await its done signal.
##   4. ActiveGame.advance() (queues next map into ActiveLevel).
##   5. change_scene_to_file(godmode.tscn). Set _pending_fade_in flag.
##   6. New scene's _ready emits scene_ready. We see the flag, spawn another
##      transition overlay, and run play_in().
##
## Flow on last level victory:
##   Same up to step 3, then change_scene_to_file(campaign_end.tscn) and
##   emit campaign_finished. No fade-in there (campaign_end has its own
##   presentation).
##
## Flow on intro level start:
##   On scene_ready of a level whose ActiveGame.current_level() carries
##   is_intro=true and/or cutscene_id != &"", emit campaign_cutscene_requested.
##   Wait for callback or timeout. (No actual cutscene player exists in 035 —
##   stub timeout makes this a no-op until a future spec wires up a listener.)

const TRANSITION_SCENE: PackedScene = preload("res://scenes/meta/level_transition.tscn")
const GODMODE_SCENE: String = "res://scenes/dev/godmode.tscn"
const CAMPAIGN_END_SCENE: String = "res://scenes/meta/campaign_end.tscn"
const CAMPAIGN_DEFEAT_SCENE: String = "res://scenes/meta/campaign_defeat.tscn"
const TUTORIAL_GAME_PATH: String = "res://data/games/tutorial.game.json"
const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const PlayerSkillAdapterScript = preload("res://scripts/runtime/player_skill_adapter.gd")

const STARTER_SKILLS: Array[StringName] = [
	&"default_melee",
	&"default_ranged",
	&"default_heal",
]

# Set right before change_scene_to_file → consumed by next scene_ready.
var _pending_fade_in: bool = false
# Per-callback latch to make sure CampaignController only acts once even if a
# listener calls on_done after the timeout already fired. Reset on each request.
var _callback_fired: bool = false
# Cumulative score across all levels of the current campaign. Resets when a
# new campaign starts (campaign_level_started with index=0). Read by
# campaign_end.gd at scene load. Necessary because RunScore.reset() fires on
# every run_started (i.e. every level start), so per-level scores would be
# lost otherwise.
var last_campaign_total: int = 0
var last_defeat_final_boss: bool = false
var last_defeat_map_index: int = -1
var last_defeat_wave_index: int = -1
var _running_total: int = 0
var _current_wave_index: int = -1
var _current_level_wave_count: int = 0
var _defeat_in_progress: bool = false
var _campaign_skill_loadout: Array = []
var _pending_hub_entry_context: StringName = &""


func _ready() -> void:
	EventBus.level_completed.connect(_on_level_completed)
	EventBus.scene_ready.connect(_on_scene_ready)
	EventBus.main_menu_entered.connect(_on_main_menu_entered)
	EventBus.campaign_level_started.connect(_on_campaign_level_started)
	EventBus.level_loaded.connect(_on_level_loaded)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.actor_died.connect(_on_actor_died)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.player_turn_ended.connect(_on_turn_boundary)
	EventBus.world_turn_ended.connect(_on_turn_boundary)
	EventBus.skill_offer_closed.connect(_on_skill_offer_closed)


func _on_main_menu_entered() -> void:
	# Returning to main menu cancels any pending transition state — otherwise
	# a back-to-menu mid-flow would trigger fade-in next time godmode loads.
	_pending_fade_in = false
	_callback_fired = true  # latch any in-flight upgrade/cutscene awaits
	_defeat_in_progress = false
	_campaign_skill_loadout.clear()
	_pending_hub_entry_context = &""


func _on_campaign_level_started(index: int, _map_path: String) -> void:
	# Fresh campaign → reset cumulative score. ActiveGame.load_game always
	# emits with index=0 first; subsequent levels of the same campaign
	# emit with index>0 (no reset).
	if index < 0:
		_defeat_in_progress = false
		if _campaign_skill_loadout.is_empty():
			_seed_campaign_skill_loadout()
	elif index == 0 and not ActiveGame.is_starting_attempt_from_hub():
		_running_total = 0
		last_campaign_total = 0
		last_defeat_final_boss = false
		last_defeat_map_index = -1
		last_defeat_wave_index = -1
		_defeat_in_progress = false
		_pending_hub_entry_context = &""
		_seed_campaign_skill_loadout()
	_current_wave_index = -1
	_current_level_wave_count = 0
	GameSave.save_campaign_state("campaign level started")


func _on_level_loaded(level: LevelData) -> void:
	_current_level_wave_count = level.waves.size() if level != null else 0
	_current_wave_index = -1


func _on_wave_started(index: int, _is_special: bool) -> void:
	_current_wave_index = index


func _on_skill_offer_closed(_wave_index: int, _picked_skill_id: StringName, _mode: StringName) -> void:
	if not ActiveGame.has_active_game() or _defeat_in_progress:
		return
	capture_current_skill_loadout()


func apply_campaign_skill_loadout() -> void:
	if not ActiveGame.has_active_game():
		return
	if _campaign_skill_loadout.is_empty():
		_seed_campaign_skill_loadout()
	PlayerSkillAdapterScript.apply_slots_snapshot(_campaign_skill_loadout)


func get_campaign_skill_loadout() -> Array:
	return _campaign_skill_loadout.duplicate(true)


func restore_campaign_skill_loadout(snapshot: Variant) -> void:
	_campaign_skill_loadout.clear()
	if snapshot is Array:
		for entry in snapshot:
			if entry is Dictionary:
				_campaign_skill_loadout.append(entry.duplicate(true))
	if _campaign_skill_loadout.is_empty():
		_seed_campaign_skill_loadout()


func prepare_hub_entry(context: StringName) -> void:
	_pending_hub_entry_context = context


func pending_hub_entry_context() -> StringName:
	return _pending_hub_entry_context


func restore_hub_entry_context(context: Variant) -> void:
	_pending_hub_entry_context = StringName(str(context))


func consume_hub_entry_dialogue_id() -> StringName:
	var context: StringName = _pending_hub_entry_context
	_pending_hub_entry_context = &""
	match context:
		&"new_game":
			return &"hub_entry_new_game"
		&"after_death":
			return &"hub_entry_after_death"
		&"after_final_boss":
			return &"hub_entry_after_final_boss"
		_:
			return &""


func capture_current_skill_loadout() -> void:
	if not ActiveGame.has_active_game():
		return
	var snapshot: Array = PlayerSkillAdapterScript.slots_snapshot()
	if snapshot.is_empty():
		return
	_campaign_skill_loadout = snapshot.duplicate(true)
	GameLogger.info("CampaignController", "captured campaign skill loadout (%d slots)" % _campaign_skill_loadout.size())
	GameSave.save_campaign_state("skill loadout captured")


func _seed_campaign_skill_loadout() -> void:
	_campaign_skill_loadout.clear()
	for i in STARTER_SKILLS.size():
		_campaign_skill_loadout.append({
			"kind": PlayerSkillAdapterScript.SLOT_KIND_ACTIVE,
			"slot": i,
			"id": STARTER_SKILLS[i],
			"level": 0,
		})


# ── level_completed flow ────────────────────────────────────────────────────

func _on_level_completed(total_score: int) -> void:
	if _defeat_in_progress:
		return
	# 035 — Diagnostic. If this fires but transition doesn't follow, the next
	# log line tells us whether it's a campaign-aware test or a single-map
	# playtest (Map Editor Playtest, Load Custom Level).
	GameLogger.info("CampaignController", "level_completed received: total_score=%d, has_active_game=%s" % [
		total_score, str(ActiveGame.has_active_game())
	])
	if not ActiveGame.has_active_game():
		# No campaign in progress — this is a Map Editor single-map playtest
		# or a Load Custom Level run. The score sits, the player can Esc to
		# main menu manually. No-op for CampaignController.
		GameLogger.info("CampaignController", "no active game → skipping transition (use Game Editor → Playtest or Load Game for campaign mode)")
		return
	# Accumulate before any awaits — total_score arg is RunScore.total at the
	# moment WaveController declared the level done, which is the canonical
	# per-level value (stub upgrade bonuses applied AFTER this don't count
	# towards campaign cumulative — they're per-level visual only).
	_running_total += total_score
	GameLogger.info("CampaignController", "campaign level_completed: level_score=%d, campaign_total=%d, level %d/%d" % [
		total_score, _running_total, ActiveGame.current_index, ActiveGame.total_levels() - 1
	])
	_run_post_level_flow(total_score)


func _run_post_level_flow(total_score: int) -> void:
	await _await_dialogue_idle()
	capture_current_skill_loadout()
	# 045-intro-cutscene: skip upgrade screen for intro levels. The intro is
	# narrative-only — there's nothing to upgrade after the player gets up
	# from the chair. ActiveGame.current_is_intro() still reflects the
	# JUST-completed level here (advance() runs after this flow's transition).
	var skip_upgrade: bool = ActiveGame.current_is_intro() or ActiveGame.game_path() == TUTORIAL_GAME_PATH
	if skip_upgrade:
		GameLogger.info("CampaignController", "post-level flow: skipping upgrade screen + continue-input")
	else:
		# 1. Upgrade screen (or stub).
		GameLogger.info("CampaignController", "post-level flow: awaiting upgrade")
		await _await_upgrade(total_score)
		await _await_continue_input()
		GameLogger.info("CampaignController", "upgrade done — playing transition out")

	# 2. Transition out — but only if we're still in a scene that has a tree
	#    (the upgrade screen could in principle have changed scenes; we don't,
	#    but be defensive).
	if not is_inside_tree():
		GameLogger.warn("CampaignController", "not in tree after upgrade — aborting flow")
		return
	await _play_transition_out()
	GameLogger.info("CampaignController", "transition out done — branching")

	# 3. Branch on last level vs next.
	if ActiveGame.is_last_level():
		last_campaign_total = _running_total
		GameLogger.info("CampaignController", "last level → campaign_finished(score=%d) → campaign_end" % last_campaign_total)
		EventBus.campaign_finished.emit(last_campaign_total)
		if ActiveGame.uses_hub():
			prepare_hub_entry(&"after_final_boss")
			if ActiveGame.return_to_hub():
				_pending_fade_in = true
				get_tree().change_scene_to_file(GODMODE_SCENE)
			else:
				ActiveGame.clear()
				get_tree().change_scene_to_file(CAMPAIGN_END_SCENE)
		else:
			ActiveGame.clear()
			get_tree().change_scene_to_file(CAMPAIGN_END_SCENE)
	else:
		ActiveGame.advance()
		_pending_fade_in = true
		GameLogger.info("CampaignController", "advanced to level %d (%s) → reload godmode" % [
			ActiveGame.current_index, ActiveGame.current_map_path()
		])
		get_tree().change_scene_to_file(GODMODE_SCENE)


func _on_actor_died(actor_id: StringName) -> void:
	if actor_id != &"player":
		return
	_begin_defeat_flow()


func _on_damage_dealt(target_id: StringName, _amount: int, _world_pos: Vector2) -> void:
	if target_id != &"player":
		return
	call_deferred("_check_player_defeat")


func _on_turn_boundary(_turn: int) -> void:
	call_deferred("_check_player_defeat")


func _check_player_defeat() -> void:
	if not ActiveGame.has_active_game() or _defeat_in_progress:
		return
	var player := _find_player_actor(get_tree().current_scene)
	if player == null:
		return
	if player.hp <= 0:
		if player.is_alive():
			player.kill_with_reason("campaign player hp reached zero")
		_begin_defeat_flow()
	elif not player.is_alive():
		_begin_defeat_flow()


func _begin_defeat_flow() -> void:
	if not ActiveGame.has_active_game() or _defeat_in_progress:
		return
	_defeat_in_progress = true
	var is_final_boss_wave: bool = (
		ActiveGame.is_last_level()
		and _current_level_wave_count > 0
		and _current_wave_index == _current_level_wave_count - 1
	)
	last_defeat_final_boss = is_final_boss_wave
	last_defeat_map_index = ActiveGame.current_index
	last_defeat_wave_index = _current_wave_index
	GameLogger.info("CampaignController", "campaign defeated: map=%d wave=%d final_boss=%s" % [
		ActiveGame.current_index, _current_wave_index, str(is_final_boss_wave)
	])
	EventBus.campaign_defeated.emit(ActiveGame.current_index, _current_wave_index, is_final_boss_wave)
	EventBus.battle_ended.emit(false)
	capture_current_skill_loadout()
	call_deferred("_run_defeat_flow", is_final_boss_wave)


func _run_defeat_flow(is_final_boss_wave: bool) -> void:
	var dialogue_id: StringName = &"ending_bad_final_version" if is_final_boss_wave else &"story_defeat_normal"
	if DialogueDB.has_line(dialogue_id):
		var started := DialogueManager.play(dialogue_id, true)
		if started:
			await _await_dialogue_finished(dialogue_id)
	DialogueManager.clear_queue()
	await get_tree().process_frame
	_pending_fade_in = false
	get_tree().paused = false
	if ActiveGame.uses_hub():
		GameLogger.info("CampaignController", "defeat dialogue done -> hub")
		prepare_hub_entry(&"after_death")
		if ActiveGame.return_to_hub():
			_pending_fade_in = true
			var hub_err := get_tree().change_scene_to_file(GODMODE_SCENE)
			if hub_err != OK:
				GameLogger.error("CampaignController", "failed to change to hub: %s" % str(hub_err))
			return
	ActiveGame.clear()
	ActiveLevel.clear()
	GameLogger.info("CampaignController", "defeat dialogue done -> campaign_defeat")
	var err := get_tree().change_scene_to_file(CAMPAIGN_DEFEAT_SCENE)
	if err != OK:
		GameLogger.error("CampaignController", "failed to change to campaign_defeat: %s" % str(err))


func _find_player_actor(root: Node) -> Actor:
	if root == null:
		return null
	if root is Actor:
		var actor := root as Actor
		if actor.actor_id == &"player":
			return actor
	for child in root.get_children():
		var found := _find_player_actor(child)
		if found != null:
			return found
	return null


# ── scene_ready flow ────────────────────────────────────────────────────────

func _on_scene_ready(scene_kind: StringName) -> void:
	# We only care about godmode scenes (level scenes). Future kinds ignored.
	if scene_kind != &"godmode":
		return

	# Pending fade-in from a just-finished transition_out → spawn overlay
	# in fade-in mode. This runs even without an active game (e.g. first
	# load via Load Game lands here too).
	if _pending_fade_in:
		_pending_fade_in = false
		_play_transition_in()

	# Intro-cutscene hook for active-game first-level.
	if ActiveGame.has_active_game():
		var cutscene_id: StringName = ActiveGame.current_cutscene_id()
		var is_intro: bool = ActiveGame.current_is_intro()
		if cutscene_id != &"" or is_intro:
			# Only emit if there's actually something to show (id non-empty).
			# is_intro alone without a cutscene id → no-op (future hook).
			if cutscene_id != &"":
				_emit_cutscene_request(cutscene_id)


func _emit_cutscene_request(cutscene_id: StringName) -> void:
	_callback_fired = false
	var on_done := Callable(self, "_on_cutscene_done")
	EventBus.campaign_cutscene_requested.emit(cutscene_id, on_done)
	var timeout: float = float(GameSpeed.get_value("meta", "cutscene_request_timeout_sec", 0.5))
	await get_tree().create_timer(timeout).timeout
	if not _callback_fired:
		# No listener picked it up; proceed silently.
		_callback_fired = true


func _on_cutscene_done() -> void:
	if _callback_fired:
		return  # late callback after timeout — ignore
	_callback_fired = true


# ── Helpers ─────────────────────────────────────────────────────────────────

func _await_upgrade(total_score: int) -> void:
	_callback_fired = false
	var on_done := Callable(self, "_on_upgrade_done")
	EventBus.upgrade_choice_requested.emit(total_score, on_done)
	var timeout: float = float(GameSpeed.get_value("meta", "upgrade_choice_timeout_sec", 0.5))
	# Wait for the listener to call on_done OR for timeout.
	# We use a small polling timer because we don't have a custom signal here.
	var elapsed: float = 0.0
	var step: float = 0.05
	while not _callback_fired and elapsed < timeout:
		await get_tree().create_timer(step).timeout
		elapsed += step
	# If listener calls on_done late we'll see it on the next iteration of the
	# main flow; latch prevents double-handling.
	if not _callback_fired:
		_callback_fired = true
		# If a stub or real upgrade screen is going to take longer than the
		# timeout, it should set its own internal flag on its first frame and
		# the listener pattern ensures we're not stuck. The dummy stub uses
		# upgrade_screen_min_display (~2s) which is longer than timeout, but
		# its own await chain will have already fired on_done by the time we
		# get here in practice. We still poll to be safe.


func _on_upgrade_done() -> void:
	if _callback_fired:
		return
	_callback_fired = true


func _await_dialogue_idle() -> void:
	while DialogueManager.is_playing():
		await EventBus.dialogue_finished


func _await_dialogue_finished(dialogue_id: StringName) -> void:
	while true:
		var finished_id: StringName = await EventBus.dialogue_finished
		if finished_id == dialogue_id:
			return


func _await_continue_input() -> void:
	EventBus.ui_toast_requested.emit(Localization.t("ui_campaign_continue_hint", "Click to continue"), 1.5, &"info")
	await get_tree().create_timer(0.35).timeout
	while true:
		await get_tree().process_frame
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
				or Input.is_key_pressed(KEY_SPACE) \
				or Input.is_key_pressed(KEY_ENTER) \
				or Input.is_key_pressed(KEY_KP_ENTER):
			return


func _play_transition_out() -> void:
	var overlay := TRANSITION_SCENE.instantiate() as LevelTransition
	if overlay == null:
		GameLogger.error("CampaignController", "transition scene instantiate failed or wrong type")
		return
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		GameLogger.warn("CampaignController", "current_scene null — cannot mount transition")
		return
	current_scene.add_child(overlay)
	GameLogger.info("CampaignController", "transition overlay mounted; running play_out")
	await overlay.play_out()
	GameLogger.info("CampaignController", "play_out returned")
	# Overlay is owned by current_scene which is about to be freed by
	# change_scene_to_file — no manual queue_free needed.


func _play_transition_in() -> void:
	var overlay := TRANSITION_SCENE.instantiate() as LevelTransition
	if overlay == null:
		return
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return
	current_scene.call_deferred("add_child", overlay)
	# Fire-and-forget: scene is already up, fade-in just decorates it.
	overlay.call_deferred("play_in")
