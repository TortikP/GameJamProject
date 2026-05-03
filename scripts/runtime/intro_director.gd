extends Node
## IntroDirector — autoload (045-intro-cutscene).
##
## Activates ONLY on campaign levels marked `is_intro=true` in the game.json.
## The intro level itself is a 1-hex stub — never visually seen by the player
## because CutscenePlayer's overlay covers it for the entire intro sequence.
##
## On scene_ready for godmode:
##   1. Wait for CutscenePlayer.cutscene_finished (frames done, overlay held).
##   2. Play the dialogue 'intro_office_monologue' on top of the held last frame.
##   3. Dismiss the overlay with a fade.
##   4. Emit `level_completed(0)` -> standard transition shader -> next level.
##
## Originally also performed an in-engine south-step. Removed: the office is
## fully cutscene art now, no visible hex room, no visible step. The 'step
## off the chair' beat is conveyed by the cutscene art frames.
##
## All awaits timeout-bounded so a broken contract can't softlock the campaign.
##
## NOT generic: dialogue id is hardcoded for office_intro. Adding another
## intro level means copy-pasting this director (per spec out-of-scope).
##
## Owner: Andrey / 045-intro-cutscene.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const INTRO_DIALOGUE_ID: StringName = &"intro_office_monologue"

# Timeouts: every await is bounded so a broken contract can't softlock.
const CUTSCENE_TIMEOUT_SEC: float = 8.0    # cutscene-art ~3s + slack
const DIALOGUE_TIMEOUT_SEC: float = 60.0   # dialogue waits for player input
const DISMISS_TIMEOUT_SEC: float = 2.0     # fade-out budget
const PRE_TRANSITION_BEAT: float = 0.2     # tiny breathing room

var _running: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.scene_ready.connect(_on_scene_ready)
	GameLogger.info("IntroDirector", "ready")


func _on_scene_ready(scene_kind: StringName) -> void:
	if scene_kind != &"godmode":
		return
	if not ActiveGame.has_active_game():
		return
	if not ActiveGame.current_is_intro():
		return
	if _running:
		GameLogger.warn("IntroDirector", "scene_ready while already running — ignored")
		return
	# Defer one frame so CampaignController._on_scene_ready (which fires the
	# cutscene_request) finishes its sync work, and CutscenePlayer's overlay
	# is added to the tree before we await its finish-signal.
	_run_sequence.call_deferred()


func _run_sequence() -> void:
	_running = true
	GameLogger.info("IntroDirector", "intro sequence starting (level=%d)" % ActiveGame.current_index)

	# 1. Cutscene art frames done (overlay still held over the screen).
	if ActiveGame.current_cutscene_id() != &"":
		var ok: bool = await _await_signal_with_timeout(CutscenePlayer, &"cutscene_finished", CUTSCENE_TIMEOUT_SEC)
		if not ok:
			GameLogger.warn("IntroDirector", "cutscene_finished timeout — proceeding anyway")
	else:
		GameLogger.info("IntroDirector", "no cutscene_id on level — skipping cutscene wait")

	# 2. Dialogue plays on top of the held cutscene frame.
	#    (Game is NOT paused — is_intro locks already block gameplay input.)
	if not DialogueManager.play(INTRO_DIALOGUE_ID):
		GameLogger.warn("IntroDirector", "DialogueManager.play('%s') failed — skipping dialogue" % INTRO_DIALOGUE_ID)
	else:
		var got: bool = await _await_signal_with_timeout(EventBus, &"dialogue_finished", DIALOGUE_TIMEOUT_SEC)
		if not got:
			GameLogger.warn("IntroDirector", "dialogue_finished timeout (%.1fs)" % DIALOGUE_TIMEOUT_SEC)

	# 3. Dismiss the overlay with a fade. Reveals the (empty) hex stub briefly
	#    before transition shader takes over.
	if CutscenePlayer.is_playing():
		CutscenePlayer.dismiss(0.4)
		var dismissed: bool = await _await_signal_with_timeout(CutscenePlayer, &"cutscene_dismissed", DISMISS_TIMEOUT_SEC)
		if not dismissed:
			GameLogger.warn("IntroDirector", "cutscene_dismissed timeout")

	# 4. Tiny beat, then standard level-transition flow takes over.
	await get_tree().create_timer(PRE_TRANSITION_BEAT).timeout
	GameLogger.info("IntroDirector", "intro sequence complete -> level_completed(0)")
	EventBus.level_completed.emit(0)
	_running = false


# ── Helpers ───────────────────────────────────────────────────────────────────

func _await_signal_with_timeout(target: Object, signal_name: StringName, timeout: float) -> bool:
	var fired: bool = false
	var on_fire := func(_a = null, _b = null, _c = null) -> void:
		fired = true
	target.connect(signal_name, on_fire, CONNECT_ONE_SHOT)
	var elapsed: float = 0.0
	var step: float = 0.05
	while elapsed < timeout and not fired:
		await get_tree().create_timer(step).timeout
		elapsed += step
	if target.is_connected(signal_name, on_fire):
		target.disconnect(signal_name, on_fire)
	return fired
