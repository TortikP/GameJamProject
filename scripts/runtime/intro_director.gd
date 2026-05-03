extends Node
## IntroDirector — autoload (045-intro-cutscene).
##
## Storyboard (final, per Andrey 2026-05-03):
##
##   1. Player clicks "Start Run" -> godmode loads office_intro level.
##   2. Player sprite is HIDDEN, the chair sprite (which depicts the seated
##      heroine) shows on the chair tile. HUD is hidden via godmode_setup.
##   3. Dialogue plays.
##   4. Chair is removed from the tile, player sprite becomes visible —
##      visually the heroine "stands up" out of the chair.
##   5. Brief beat -> emit level_completed -> standard transition shader
##      -> story_map_01.
##
## NO cutscene art overlay anymore. Andrey 2026-05-03: «обе сцены с
## cutscene_1 и cutscene_2 выкидывай, они просто не работают, сразу
## дропаемся на левел с офисом».
##
## All awaits timeout-bounded so a broken contract can't softlock.
##
## Owner: Andrey / 045-intro-cutscene.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const PLAYER_ID: StringName = &"player"
const INTRO_DIALOGUE_ID: StringName = &"intro_office_monologue"
const CHAIR_OBJECT_ID: StringName = &"object_on_chair"
const CHAIR_COORD: Vector2i = Vector2i(3, 2)  # matches data/maps/office_intro.json

# Beats give the player a moment to read each phase.
const PRE_DIALOGUE_BEAT: float = 0.6        # let the office settle before talking
const POST_STAND_BEAT: float = 0.6          # tiny pause before transition

# Timeouts: every await is bounded.
const DIALOGUE_TIMEOUT_SEC: float = 60.0    # waits for player input

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
	# Deferred so the host scene's _ready() finishes (it emitted scene_ready
	# from its last line) before we mutate the tree.
	_run_sequence.call_deferred()


func _run_sequence() -> void:
	_running = true
	GameLogger.info("IntroDirector", "[1/5] sequence start (level=%d)" % ActiveGame.current_index)

	# Hide the player sprite immediately. The chair sprite depicts the
	# seated heroine, and the chair is non-blocking so player actually
	# spawned at (3, 2) on the chair tile. We don't want two overlapping
	# heroines.
	_set_player_visible(false)
	GameLogger.info("IntroDirector", "[1/5] player hidden, chair shows seated heroine")

	# ── 1. Beat to let the office register ──────────────────────────────────
	await get_tree().create_timer(PRE_DIALOGUE_BEAT).timeout
	GameLogger.info("IntroDirector", "[2/5] pre-dialogue beat done")

	# ── 2. Dialogue ─────────────────────────────────────────────────────────
	if not DialogueManager.play(INTRO_DIALOGUE_ID):
		GameLogger.warn("IntroDirector", "[2/5] DialogueManager.play('%s') failed — skipping" % INTRO_DIALOGUE_ID)
	else:
		var got: bool = await _await_signal_with_timeout(EventBus, &"dialogue_finished", DIALOGUE_TIMEOUT_SEC)
		if got:
			GameLogger.info("IntroDirector", "[3/5] dialogue_finished received")
		else:
			GameLogger.warn("IntroDirector", "[3/5] dialogue_finished TIMEOUT (%.1fs)" % DIALOGUE_TIMEOUT_SEC)

	# ── 3. Chair vanishes, player becomes visible ───────────────────────────
	GameLogger.info("IntroDirector", "[4/5] chair -> empty, player -> visible (heroine 'stands up')")
	_remove_chair()
	_set_player_visible(true)

	await get_tree().create_timer(POST_STAND_BEAT).timeout

	# ── 4. Hand off to CampaignController via standard level_completed flow ─
	GameLogger.info("IntroDirector", "[5/5] emit level_completed(0) -> standard transition")
	EventBus.level_completed.emit(0)
	_running = false


# ── Helpers ───────────────────────────────────────────────────────────────────

func _find_grid() -> HexGrid:
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	return root.find_child("HexGrid", true, false) as HexGrid


func _set_player_visible(v: bool) -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		return
	var player_node: Node = root.find_child("Player", true, false)
	if player_node == null:
		GameLogger.warn("IntroDirector", "_set_player_visible: Player node not found")
		return
	(player_node as CanvasItem).visible = v
	GameLogger.info("IntroDirector", "player visible -> %s" % str(v))


func _remove_chair() -> void:
	var grid := _find_grid()
	if grid == null:
		GameLogger.warn("IntroDirector", "_remove_chair: grid not found")
		return
	# Clear data side
	grid.set_tile_object_id(CHAIR_COORD, &"")
	# Clear visual side
	var root: Node = get_tree().current_scene
	if root == null:
		return
	var overlay: Node = root.find_child("ObjectsOverlay", true, false)
	if overlay != null and overlay.has_method("set_object"):
		overlay.set_object(CHAIR_COORD, &"")
		GameLogger.info("IntroDirector", "chair removed from %s (data + overlay)" % str(CHAIR_COORD))
	else:
		GameLogger.warn("IntroDirector", "ObjectsOverlay missing or no set_object — chair sprite may linger")
	# Emit canonical destroyed event for any other listeners.
	EventBus.tile_object_destroyed.emit(CHAIR_COORD, CHAIR_OBJECT_ID)


# Race the target signal against a timeout timer. The first to fire wins.
# Implemented via two parallel coroutines that flip a shared dict — avoids
# Godot 4 lambda-arity-mismatch issues with `connect(... CONNECT_ONE_SHOT)`.
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
