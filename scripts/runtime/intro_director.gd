extends Node
## IntroDirector — autoload (045-intro-cutscene).
##
## Activates ONLY on campaign levels marked `is_intro=true` in the game.json.
## On scene_ready for godmode, runs the scripted intro flow:
##
##   1. Wait for CutscenePlayer to finish the overlay (or skip-fired).
##   2. Play the dialogue named `intro_office_monologue`.
##   3. Step the player one hex south (`TileSet.CELL_NEIGHBOR_BOTTOM_SIDE`).
##      Camera-follow (043) handles re-centering.
##   4. Emit `EventBus.level_completed(0)` to fire the standard transition
##      shader -> next campaign level.
##
## Awaits are timeout-bounded so a missing dialogue / unresponsive grid can't
## softlock the campaign. On timeout, the sequence proceeds to the next step
## with a warning.
##
## NOT generic: dialogue id and step direction are hardcoded for office_intro.
## Adding another intro level means copying this director or extending the
## campaign schema (per spec out-of-scope, jam policy).
##
## Owner: Andrey / 045-intro-cutscene.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const PLAYER_ID: StringName = &"player"
const INTRO_DIALOGUE_ID: StringName = &"intro_office_monologue"

# Timeouts: every await is bounded so a broken contract can't softlock.
const CUTSCENE_TIMEOUT_SEC: float = 6.0       # > cutscene_request_timeout (4.0) + animation slack
const DIALOGUE_TIMEOUT_SEC: float = 60.0      # generous — dialogue waits for player input
const MOVE_TIMEOUT_SEC: float = 2.0           # step_duration is ~0.3s typical
const POST_MOVE_BEAT_SEC: float = 0.4         # breathing room before transition

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
	# is in the tree before we await its finish-signal.
	_run_sequence.call_deferred()


func _run_sequence() -> void:
	_running = true
	GameLogger.info("IntroDirector", "intro sequence starting (level=%d)" % ActiveGame.current_index)

	# 1. Cutscene art (skip if no cutscene_id on this level)
	if ActiveGame.current_cutscene_id() != &"":
		var ok: bool = await _await_cutscene_finished()
		if not ok:
			GameLogger.warn("IntroDirector", "cutscene_finished timeout — proceeding anyway")

	# 2. Dialogue
	if not DialogueManager.play(INTRO_DIALOGUE_ID):
		GameLogger.warn("IntroDirector", "DialogueManager.play('%s') failed — skip dialogue" % INTRO_DIALOGUE_ID)
	else:
		var got: bool = await _await_signal_with_timeout(EventBus, &"dialogue_finished", DIALOGUE_TIMEOUT_SEC)
		if not got:
			GameLogger.warn("IntroDirector", "dialogue_finished timeout (%.1fs)" % DIALOGUE_TIMEOUT_SEC)

	# 3. Scripted south step
	var grid := _find_grid()
	if grid == null:
		GameLogger.warn("IntroDirector", "HexGrid not found — skip step, complete level")
	else:
		await _step_player_south(grid)

	# 4. Beat
	await get_tree().create_timer(POST_MOVE_BEAT_SEC).timeout

	# 5. Hand off to CampaignController via standard level_completed flow.
	GameLogger.info("IntroDirector", "intro sequence complete -> level_completed(0)")
	EventBus.level_completed.emit(0)
	_running = false


# ── Helpers ───────────────────────────────────────────────────────────────────

func _find_grid() -> HexGrid:
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.find_child("HexGrid", true, false) as HexGrid


func _step_player_south(grid: HexGrid) -> void:
	# step_actor is async (awaits step_duration internally) and emits
	# EventBus.actor_moved synchronously before the await. We fire-and-forget
	# the call and wait for the signal with a timeout; if step_actor returns
	# false (blocked / occupied), the signal never fires and we time out
	# gracefully.
	if not grid.has_method("step_actor"):
		GameLogger.warn("IntroDirector", "HexGrid lacks step_actor")
		return
	# Use a callable to avoid awaiting the (void-returning) step_actor itself.
	# step_actor returns bool, but as an async func GDScript still returns the
	# call object; we just call it and rely on the EventBus signal.
	var fired: bool = false
	var moved_cb := func(actor_id: StringName, _from: Vector2i, _to: Vector2i) -> void:
		if actor_id == PLAYER_ID:
			fired = true
	EventBus.actor_moved.connect(moved_cb)

	# Step using TileSet.CELL_NEIGHBOR_BOTTOM_SIDE (south for our flat-top
	# vertical-offset hex grid, see hex_terrain.tres).
	grid.step_actor(PLAYER_ID, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE)

	# Poll for signal or timeout.
	var elapsed: float = 0.0
	var step: float = 0.05
	while elapsed < MOVE_TIMEOUT_SEC and not fired:
		await get_tree().create_timer(step).timeout
		elapsed += step
	if EventBus.is_connected(&"actor_moved", moved_cb):
		EventBus.disconnect(&"actor_moved", moved_cb)
	if not fired:
		GameLogger.warn("IntroDirector", "actor_moved (player) timeout after %.1fs — south step blocked?" % MOVE_TIMEOUT_SEC)


func _await_cutscene_finished() -> bool:
	# CutscenePlayer.cutscene_finished is the signal emitted by the autoload
	# itself (not via EventBus). Returns false on timeout.
	return await _await_signal_with_timeout(CutscenePlayer, &"cutscene_finished", CUTSCENE_TIMEOUT_SEC)


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
