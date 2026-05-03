extends Node
## IntroDirector — autoload (045-intro-cutscene).
##
## Storyboard (per Andrey's spec):
##
##   1. Player clicks "Start Run" -> main menu disappears.
##   2. Office cutscene plays: cutscene_2 (zoomed monitor) -> camera pulls
##      back -> cutscene_1 (full office layout).
##   3. Cutscene dismisses with a zoom-into-monitor effect — the picture
##      flies into the screen, revealing the live hex room behind.
##   4. Player sprite is HIDDEN, chair is on the tile (visually: heroine
##      sitting, since the chair sprite shows the seated figure).
##   5. Dialogue plays.
##   6. Chair is removed from the tile, player sprite becomes visible —
##      visually the heroine "stands up" out of the chair.
##   7. Brief beat -> emit level_completed -> standard transition shader
##      -> story_map_01.
##
## All awaits timeout-bounded so a broken contract can't softlock.
##
## Owner: Andrey / 045-intro-cutscene.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const PLAYER_ID: StringName = &"player"
const INTRO_DIALOGUE_ID: StringName = &"intro_office_monologue"
const CHAIR_OBJECT_ID: StringName = &"object_on_chair"
const CHAIR_COORD: Vector2i = Vector2i(3, 2)  # matches data/maps/office_intro.json

# Dismiss: simple fade-out from cutscene_1 into the live office.
# No zoom shenanigans — keeps it clean and predictable per Andrey's
# storyboard simplification ("все эти зумы и движения мимо").
const DISMISS_DURATION: float = 1.0

# Beats give the player a moment to read each phase.
const POST_REVEAL_BEAT: float = 0.4
const POST_STAND_BEAT: float = 0.6

# Timeouts: every await is bounded.
const CUTSCENE_TIMEOUT_SEC: float = 8.0    # cutscene-art ~3.5s + slack
const DISMISS_TIMEOUT_SEC: float = 2.5     # > DISMISS_DURATION (1.0s) + slack
const DIALOGUE_TIMEOUT_SEC: float = 60.0   # waits for player input
const SIGNAL_POLL_HZ: float = 60.0         # process_frame is fine for our durations

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
	# Deferred so CampaignController._on_scene_ready (sync) finishes emitting
	# campaign_cutscene_requested first, and CutscenePlayer's overlay reaches
	# the tree before we await its finish-signal.
	_run_sequence.call_deferred()


func _run_sequence() -> void:
	_running = true
	GameLogger.info("IntroDirector", "[1/7] sequence start (level=%d cutscene=%s)" % [
		ActiveGame.current_index, String(ActiveGame.current_cutscene_id())
	])

	# Hide the player sprite immediately — the chair sprite shows the seated
	# heroine, and we don't want two heroines stacked on the same hex.
	# Chair is non-blocking (object_on_chair.json: blocks_movement=false) so
	# the player actually spawns at (3, 2), the chair tile.
	_set_player_visible(false)

	# ── 1. Wait for cutscene art to finish ──────────────────────────────────
	if ActiveGame.current_cutscene_id() != &"":
		var ok: bool = await _await_signal_with_timeout(CutscenePlayer, &"cutscene_finished", CUTSCENE_TIMEOUT_SEC)
		if ok:
			GameLogger.info("IntroDirector", "[2/7] cutscene_finished received")
		else:
			GameLogger.warn("IntroDirector", "[2/7] cutscene_finished TIMEOUT (%.1fs) — proceeding" % CUTSCENE_TIMEOUT_SEC)
	else:
		GameLogger.info("IntroDirector", "[2/7] no cutscene_id — skipping wait")

	# ── 2. Dismiss with a clean fade — reveals the live office ──────────────
	if CutscenePlayer.is_playing():
		GameLogger.info("IntroDirector", "[3/7] dismiss(%.1fs fade) — fade into live office" % DISMISS_DURATION)
		CutscenePlayer.dismiss(DISMISS_DURATION)
		var dismissed: bool = await _await_signal_with_timeout(CutscenePlayer, &"cutscene_dismissed", DISMISS_TIMEOUT_SEC)
		if dismissed:
			GameLogger.info("IntroDirector", "[3/7] dismissed — live office visible")
		else:
			GameLogger.warn("IntroDirector", "[3/7] cutscene_dismissed TIMEOUT")
	else:
		GameLogger.info("IntroDirector", "[3/7] CutscenePlayer not playing — skipping dismiss")

	# ── 3. Beat: let the player register the office ─────────────────────────
	await get_tree().create_timer(POST_REVEAL_BEAT).timeout
	GameLogger.info("IntroDirector", "[4/7] post-reveal beat done")

	# ── 4. Dialogue (chair still on tile, player still hidden) ──────────────
	if not DialogueManager.play(INTRO_DIALOGUE_ID):
		GameLogger.warn("IntroDirector", "[4/7] DialogueManager.play('%s') failed — skipping" % INTRO_DIALOGUE_ID)
	else:
		var got: bool = await _await_signal_with_timeout(EventBus, &"dialogue_finished", DIALOGUE_TIMEOUT_SEC)
		if got:
			GameLogger.info("IntroDirector", "[4/7] dialogue_finished received")
		else:
			GameLogger.warn("IntroDirector", "[4/7] dialogue_finished TIMEOUT (%.1fs)" % DIALOGUE_TIMEOUT_SEC)

	# ── 5. Chair vanishes, player becomes visible ───────────────────────────
	GameLogger.info("IntroDirector", "[5/7] chair -> empty, player -> visible (heroine 'stands up')")
	_remove_chair()
	_set_player_visible(true)

	await get_tree().create_timer(POST_STAND_BEAT).timeout

	# ── 6. Hand off to CampaignController via standard level_completed flow ─
	GameLogger.info("IntroDirector", "[6/7] emit level_completed(0) -> standard transition")
	EventBus.level_completed.emit(0)
	_running = false
	GameLogger.info("IntroDirector", "[7/7] sequence complete")


# ── Helpers ───────────────────────────────────────────────────────────────────

func _find_grid() -> HexGrid:
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.find_child("HexGrid", true, false) as HexGrid


func _set_player_visible(v: bool) -> void:
	var grid := _find_grid()
	if grid == null:
		GameLogger.warn("IntroDirector", "_set_player_visible: grid not found")
		return
	# ActorRegistry node is a sibling of HexGrid on the godmode scene; query
	# via the controller path. Simpler: look up Actor in tree by name.
	var root: Node = get_tree().current_scene
	if root == null:
		return
	var player_node: Node = root.find_child("Player", true, false)
	if player_node == null:
		# Player hasn't spawned yet (placeholder still), or fallback name.
		GameLogger.warn("IntroDirector", "_set_player_visible: Player node not found")
		return
	(player_node as CanvasItem).visible = v
	GameLogger.info("IntroDirector", "player visible -> %s" % str(v))


func _remove_chair() -> void:
	var grid := _find_grid()
	if grid == null:
		GameLogger.warn("IntroDirector", "_remove_chair: grid not found")
		return
	# Clear the data side
	grid.set_tile_object_id(CHAIR_COORD, &"")
	# Clear the visual side (ObjectsOverlay paints sprites from set_object calls)
	var root: Node = get_tree().current_scene
	if root == null:
		return
	var overlay: Node = root.find_child("ObjectsOverlay", true, false)
	if overlay != null and overlay.has_method("set_object"):
		overlay.set_object(CHAIR_COORD, &"")
		GameLogger.info("IntroDirector", "chair removed from %s (data + overlay)" % str(CHAIR_COORD))
	else:
		GameLogger.warn("IntroDirector", "ObjectsOverlay missing or no set_object — chair sprite may linger")
	# Emit the canonical destroyed event for any other listeners.
	EventBus.tile_object_destroyed.emit(CHAIR_COORD, CHAIR_OBJECT_ID)


# Race the target signal against a timeout timer. The first to fire wins.
# Implemented via two parallel coroutines that flip a shared dict — avoids
# Godot 4 lambda-arity-mismatch issues with `connect(... CONNECT_ONE_SHOT)`
# (lambdas with default-arg arities silently fail to fire on signals with
# fewer args).
func _await_signal_with_timeout(target: Object, signal_name: StringName, timeout: float) -> bool:
	var sig: Signal = Signal(target, signal_name)
	var timer := get_tree().create_timer(timeout)
	var state := {"signal_fired": false, "timeout_fired": false}
	_relay_signal(sig, state)
	_relay_timer(timer, state)
	while not state.signal_fired and not state.timeout_fired:
		await get_tree().process_frame
	return state.signal_fired


func _relay_signal(sig: Signal, state: Dictionary) -> void:
	await sig
	state.signal_fired = true


func _relay_timer(timer: SceneTreeTimer, state: Dictionary) -> void:
	await timer.timeout
	state.timeout_fired = true
