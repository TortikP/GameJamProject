extends Node
## IntroDirector — autoload (045-intro-cutscene).
##
## Activates ONLY on campaign levels marked `is_intro=true`. Orchestrates the
## full intro sequence:
##
##   1. Wait for CutscenePlayer to play its frames (cutscene_finished fires;
##      overlay holds the last frame).
##   2. CutscenePlayer.dismiss(zoom_to=4.0, pivot=monitor) — last frame scales
##      up centered on the monitor while fading out. Visual: "exit through
##      the screen" — the office is revealed behind the dissolving image.
##   3. Brief beat so the player registers the live office room (chair, desk,
##      cooler, the heroine standing where the cutscene art said she was).
##   4. Play `intro_office_monologue` (3 lines, heroine speaker).
##   5. Scripted south-step (1 hex). Camera follows via 043-camera-follow.
##   6. Emit `level_completed(0)` — CampaignController's standard transition
##      shader fires; advance() loads the next campaign level (story_map_01).
##
## All awaits timeout-bounded so a broken contract can't softlock the campaign.
## Verbose GameLogger.info on every phase boundary so smoke-test console
## diagnoses failures.
##
## NOT generic: dialogue id, step direction, monitor pivot are hardcoded.
##
## Owner: Andrey / 045-intro-cutscene.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const PLAYER_ID: StringName = &"player"
const INTRO_DIALOGUE_ID: StringName = &"intro_office_monologue"

# "Exit through monitor": scale up the held cutscene_1 image with anchor at
# the monitor's location in the 500x500 art. Tuned visually.
const MONITOR_ZOOM: float = 4.5
const MONITOR_PIVOT: Vector2 = Vector2(0.5, 0.22)
const DISMISS_DURATION: float = 0.9

# Beats give the player a moment to read the scene before the next step.
const POST_REVEAL_BEAT: float = 0.35
const POST_STEP_BEAT: float = 0.45

# Timeouts: every await is bounded so a broken contract can't softlock.
const CUTSCENE_TIMEOUT_SEC: float = 8.0    # cutscene-art ~3s + slack
const DISMISS_TIMEOUT_SEC: float = 2.5     # > DISMISS_DURATION + slack
const DIALOGUE_TIMEOUT_SEC: float = 60.0   # waits for player input
const MOVE_TIMEOUT_SEC: float = 2.0        # step_duration ~0.18s + slack

var _running: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.scene_ready.connect(_on_scene_ready)
	GameLogger.info("IntroDirector", "ready")


func _on_scene_ready(scene_kind: StringName) -> void:
	if scene_kind != &"godmode":
		return
	if not ActiveGame.has_active_game():
		GameLogger.info("IntroDirector", "scene_ready: no active game — skip")
		return
	if not ActiveGame.current_is_intro():
		GameLogger.info("IntroDirector", "scene_ready: current level is_intro=false — skip")
		return
	if _running:
		GameLogger.warn("IntroDirector", "scene_ready while already running — skip")
		return
	GameLogger.info("IntroDirector", "scene_ready: is_intro level — deferring _run_sequence")
	# Deferred so CampaignController._on_scene_ready (sync, before us in
	# scene_ready listener order) finishes emitting campaign_cutscene_requested
	# and CutscenePlayer's overlay reaches the tree first.
	_run_sequence.call_deferred()


func _run_sequence() -> void:
	_running = true
	GameLogger.info("IntroDirector", "[1/6] sequence start (level=%d cutscene=%s)" % [
		ActiveGame.current_index, String(ActiveGame.current_cutscene_id())
	])

	# ── 1. Cutscene art frames done (overlay holding last frame) ─────────────
	if ActiveGame.current_cutscene_id() != &"":
		var ok: bool = await _await_signal_with_timeout(CutscenePlayer, &"cutscene_finished", CUTSCENE_TIMEOUT_SEC)
		if ok:
			GameLogger.info("IntroDirector", "[2/6] cutscene_finished received")
		else:
			GameLogger.warn("IntroDirector", "[2/6] cutscene_finished TIMEOUT (%.1fs) — proceeding" % CUTSCENE_TIMEOUT_SEC)
	else:
		GameLogger.info("IntroDirector", "[2/6] no cutscene_id — skipping wait")

	# ── 2. Dismiss with zoom-into-monitor — reveals live office ─────────────
	if CutscenePlayer.is_playing():
		GameLogger.info("IntroDirector", "[3/6] dismiss(zoom_to=%.1f, pivot=%s) — exit through screen" % [MONITOR_ZOOM, str(MONITOR_PIVOT)])
		CutscenePlayer.dismiss(DISMISS_DURATION, MONITOR_ZOOM, MONITOR_PIVOT)
		var dismissed: bool = await _await_signal_with_timeout(CutscenePlayer, &"cutscene_dismissed", DISMISS_TIMEOUT_SEC)
		if dismissed:
			GameLogger.info("IntroDirector", "[3/6] dismissed")
		else:
			GameLogger.warn("IntroDirector", "[3/6] cutscene_dismissed TIMEOUT")
	else:
		GameLogger.info("IntroDirector", "[3/6] CutscenePlayer not playing — skipping dismiss")

	# ── 3. Beat: let the player see the office ──────────────────────────────
	await get_tree().create_timer(POST_REVEAL_BEAT).timeout
	GameLogger.info("IntroDirector", "[4/6] post-reveal beat done — playing dialogue")

	# ── 4. Dialogue ─────────────────────────────────────────────────────────
	if not DialogueManager.play(INTRO_DIALOGUE_ID):
		GameLogger.warn("IntroDirector", "[4/6] DialogueManager.play('%s') failed — skipping" % INTRO_DIALOGUE_ID)
	else:
		var got: bool = await _await_signal_with_timeout(EventBus, &"dialogue_finished", DIALOGUE_TIMEOUT_SEC)
		if got:
			GameLogger.info("IntroDirector", "[4/6] dialogue_finished received")
		else:
			GameLogger.warn("IntroDirector", "[4/6] dialogue_finished TIMEOUT (%.1fs)" % DIALOGUE_TIMEOUT_SEC)

	# ── 5. Visible south step ──────────────────────────────────────────────
	var grid := _find_grid()
	if grid == null:
		GameLogger.warn("IntroDirector", "[5/6] HexGrid not found — skipping step")
	else:
		await _step_player_south(grid)
		GameLogger.info("IntroDirector", "[5/6] step done")

	await get_tree().create_timer(POST_STEP_BEAT).timeout

	# ── 6. Hand off to CampaignController via standard level_completed flow ─
	GameLogger.info("IntroDirector", "[6/6] emit level_completed(0) -> standard transition")
	EventBus.level_completed.emit(0)
	_running = false


# ── Helpers ───────────────────────────────────────────────────────────────────

func _find_grid() -> HexGrid:
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.find_child("HexGrid", true, false) as HexGrid


func _step_player_south(grid: HexGrid) -> void:
	if not grid.has_method("step_actor"):
		GameLogger.warn("IntroDirector", "HexGrid lacks step_actor")
		return
	var fired: bool = false
	var moved_cb := func(actor_id: StringName, _from: Vector2i, _to: Vector2i) -> void:
		if actor_id == PLAYER_ID:
			fired = true
	EventBus.actor_moved.connect(moved_cb)

	# step_actor is async (awaits step_duration internally) but emits actor_moved
	# synchronously BEFORE the await. Calling without await: function runs sync
	# up to the first await, signal fires, we resume polling.
	@warning_ignore("return_value_discarded")
	grid.step_actor(PLAYER_ID, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE)

	var elapsed: float = 0.0
	var step: float = 0.05
	while elapsed < MOVE_TIMEOUT_SEC and not fired:
		await get_tree().create_timer(step).timeout
		elapsed += step
	if EventBus.is_connected(&"actor_moved", moved_cb):
		EventBus.disconnect(&"actor_moved", moved_cb)
	if not fired:
		GameLogger.warn("IntroDirector", "actor_moved (player) timeout — south step blocked?")


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
