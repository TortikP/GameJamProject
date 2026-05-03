extends Node
## CutscenePlayer — autoload (045-intro-cutscene).
##
## Listens for `EventBus.campaign_cutscene_requested(cutscene_id, on_done)`,
## opens a fullscreen overlay (CanvasLayer 30) and runs a multi-frame slideshow
## with scale + cross-fade between frames.
##
## Two-phase design: animation finishes -> emit `cutscene_finished` and fire
## `on_done` immediately so CampaignController's 4-sec timeout doesn't snip
## the flow. The overlay STAYS up holding the last frame until `dismiss()`
## is explicitly called by IntroDirector (after dialogue completes). This
## hides the live hex level (which is a stub) for the entire intro.
##
## NB: we do NOT pause the tree. DialogueManager/DialoguePanel default to
## process_mode=INHERIT and would stall during pause, leaving the player
## unable to advance dialogue lines. Instead, `is_intro` early-returns in
## godmode_input/camera block all gameplay input, and the overlay's
## mouse_filter=STOP root absorbs stray clicks.
##
## JSON schema (`data/cutscenes/<id>.json`):
##   {
##     "id": "<id>",
##     "frames": [
##       {
##         "image":            "res://...",
##         "scale_from":       float,    # default 1.0
##         "scale_to":         float,    # default 1.0
##         "duration":         float,    # default 1.0 — animation time
##         "fade_in_sec":      float,    # default 0.0
##         "cross_fade_to_next_sec": float,  # default 0.0
##         "pivot":            [x, y],   # default [0.5, 0.5] — relative to image
##         "fade_out_sec":     float     # default 0.0 — only on last frame if no hold
##       }, ...
##     ]
##   }
##
## Skip via Space/Enter/Mouse — interrupts the frame loop, jumps to held last
## frame. Skipping doesn't call dismiss() — IntroDirector still controls when
## the overlay actually tears down.
##
## Owner: Andrey / 045-intro-cutscene.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const CUTSCENES_DIR: String = "res://data/cutscenes/"
const OVERLAY_SCENE: String = "res://scenes/meta/cutscene_player.tscn"

signal cutscene_finished(cutscene_id: StringName)   # frames done; overlay still up
signal cutscene_dismissed(cutscene_id: StringName)  # overlay torn down

var _active: bool = false
var _frames_done: bool = false
var _skip_requested: bool = false
var _current_id: StringName = &""
var _overlay: CanvasLayer = null
var _last_frame_rect: TextureRect = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.campaign_cutscene_requested.connect(_on_cutscene_requested)
	GameLogger.info("CutscenePlayer", "ready")


func is_playing() -> bool:
	return _active


# ── Entry ─────────────────────────────────────────────────────────────────────

func _on_cutscene_requested(cutscene_id: StringName, on_done: Callable) -> void:
	GameLogger.info("CutscenePlayer", "cutscene_requested '%s'" % cutscene_id)
	if _active:
		GameLogger.warn("CutscenePlayer", "already playing — ignoring '%s'" % cutscene_id)
		on_done.call()
		cutscene_finished.emit(cutscene_id)
		cutscene_dismissed.emit(cutscene_id)
		return

	var data: Dictionary = _load_cutscene(cutscene_id)
	var frames: Array = (data.get("frames", []) as Array) if not data.is_empty() else []
	if frames.is_empty():
		GameLogger.warn("CutscenePlayer", "no frames for '%s' — firing on_done + deferred signals" % cutscene_id)
		on_done.call()
		# Defer signal emission to the next frame so IntroDirector's
		# call_deferred(_run_sequence) connects to cutscene_finished BEFORE
		# we emit it. Without defer, the signals fire during the same sync
		# call chain as scene_ready -> CampaignController -> CutscenePlayer,
		# which is BEFORE IntroDirector._on_scene_ready runs.
		call_deferred("_emit_finish_signals_deferred", cutscene_id)
		return

	_active = true
	_frames_done = false
	_current_id = cutscene_id
	_skip_requested = false
	GameLogger.info("CutscenePlayer", "playing '%s' — %d frames" % [cutscene_id, frames.size()])

	# NOTE: we used to set get_tree().paused = true here. Removed — DialogueManager
	# and its panel default to PROCESS_MODE_INHERIT, so they'd stall during pause
	# and the player couldn't advance dialogue lines on top of the held overlay.
	# is_intro locks (godmode_input/camera early-returns) already prevent all
	# gameplay input. WaveController has 0 enemies on intro level — nothing to
	# tick. Overlay is_input mouse_filter=STOP catches stray clicks.

	# Spawn overlay parented to current_scene so a quit-to-menu mid-cutscene
	# frees it cleanly. CanvasLayer renders globally regardless of parent.
	var packed := load(OVERLAY_SCENE) as PackedScene
	if packed == null:
		GameLogger.error("CutscenePlayer", "failed to load overlay scene: %s" % OVERLAY_SCENE)
		_active = false
		on_done.call()
		call_deferred("_emit_finish_signals_deferred", cutscene_id)
		return
	_overlay = packed.instantiate() as CanvasLayer
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(_overlay)
	GameLogger.info("CutscenePlayer", "overlay spawned in %s" % host.name)

	await _play_frames(frames)
	_frames_done = true

	# Phase 1 complete: notify listeners so they can play dialogue / next steps.
	# Overlay stays up holding the last frame; dismiss() ends it.
	GameLogger.info("CutscenePlayer", "frames done '%s' — overlay held, awaiting dismiss()" % cutscene_id)
	on_done.call()
	cutscene_finished.emit(cutscene_id)


# Public: tear down overlay with optional zoom-into-pivot effect.
# duration: total time for fade + scale in parallel.
# zoom_to: target scale on the held last frame. 1.0 = no zoom, just fade.
#   Use >1 for "exit through screen" feel (camera flies into pivot).
# zoom_pivot: relative point on the image (0..1) that becomes the scale anchor.
#   For the office cutscene, [0.5, 0.22] hits the monitor.
func dismiss(duration: float = 0.4, zoom_to: float = 1.0, zoom_pivot: Vector2 = Vector2(0.5, 0.5)) -> void:
	if not _active:
		GameLogger.info("CutscenePlayer", "dismiss called but not active — no-op")
		return
	GameLogger.info("CutscenePlayer", "dismiss '%s' (dur=%.2f zoom=%.2f pivot=%s)" % [_current_id, duration, zoom_to, str(zoom_pivot)])
	if is_instance_valid(_overlay) and duration > 0.0:
		var root: Control = _overlay.get_node_or_null("Root") as Control
		# Scale tween on last frame — "fly into" effect when zoom_to > 1.
		if _last_frame_rect != null and is_instance_valid(_last_frame_rect) and not is_equal_approx(zoom_to, 1.0):
			var rect_size: Vector2 = _last_frame_rect.size
			_last_frame_rect.pivot_offset = Vector2(rect_size.x * zoom_pivot.x, rect_size.y * zoom_pivot.y)
			var current_scale: float = _last_frame_rect.scale.x
			var tw_scale := create_tween()
			tw_scale.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tw_scale.tween_property(_last_frame_rect, "scale", Vector2(zoom_to, zoom_to), duration)
			GameLogger.info("CutscenePlayer", "dismiss scale tween: %.2f -> %.2f" % [current_scale, zoom_to])
		# Fade root alpha to 0 in parallel.
		if root != null:
			var tw_fade := create_tween()
			tw_fade.tween_property(root, "modulate:a", 0.0, duration)
			await tw_fade.finished
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_last_frame_rect = null
	var id: StringName = _current_id
	_active = false
	_frames_done = false
	_current_id = &""
	cutscene_dismissed.emit(id)
	GameLogger.info("CutscenePlayer", "dismissed '%s'" % id)


# Used by deferred-emit path when there are no frames or load failed.
# Ensures cutscene_finished / cutscene_dismissed fire on a later frame so
# any deferred listeners (IntroDirector._run_sequence) have a chance to
# connect first.
func _emit_finish_signals_deferred(cutscene_id: StringName) -> void:
	cutscene_finished.emit(cutscene_id)
	cutscene_dismissed.emit(cutscene_id)


# ── Animation ─────────────────────────────────────────────────────────────────

func _play_frames(frames: Array) -> void:
	var root: Control = _overlay.get_node("Root") as Control
	var f1: TextureRect = root.get_node("Frame1") as TextureRect
	var f2: TextureRect = root.get_node("Frame2") as TextureRect
	# Wait one frame so anchors apply and size is non-zero before computing pivot.
	await get_tree().process_frame
	f1.pivot_offset = f1.size * 0.5
	f2.pivot_offset = f2.size * 0.5

	var slots: Array = [f1, f2]

	for i in range(frames.size()):
		if _skip_requested:
			# Make last frame visible, hold; skip the rest
			_set_frame_image(slots[i % 2], String((frames[i] as Dictionary).get("image", "")))
			slots[i % 2].modulate.a = 1.0
			slots[i % 2].scale = Vector2.ONE
			_last_frame_rect = slots[i % 2]
			return
		var frame: Dictionary = frames[i] as Dictionary
		var current: TextureRect = slots[i % 2]
		var nxt: TextureRect = slots[(i + 1) % 2]

		_set_frame_image(current, String(frame.get("image", "")))
		_apply_pivot(current, frame)

		var scale_from: float = float(frame.get("scale_from", 1.0))
		var scale_to: float = float(frame.get("scale_to", 1.0))
		var duration: float = max(0.05, float(frame.get("duration", 1.0)))
		var fade_in: float = max(0.0, float(frame.get("fade_in_sec", 0.0)))
		var cross_to_next: float = max(0.0, float(frame.get("cross_fade_to_next_sec", 0.0)))

		current.scale = Vector2(scale_from, scale_from)
		current.modulate.a = 0.0 if fade_in > 0.0 else 1.0

		if fade_in > 0.0:
			var tw_in := create_tween()
			tw_in.tween_property(current, "modulate:a", 1.0, fade_in)

		var tw_scale := create_tween()
		tw_scale.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw_scale.tween_property(current, "scale", Vector2(scale_to, scale_to), duration)

		var has_next: bool = i + 1 < frames.size()
		if has_next and cross_to_next > 0.0:
			var hold: float = max(0.0, duration - cross_to_next)
			var ok: bool = await _await_or_skip(hold)
			if not ok:
				_last_frame_rect = current
				return
			var next_frame: Dictionary = frames[i + 1] as Dictionary
			_set_frame_image(nxt, String(next_frame.get("image", "")))
			_apply_pivot(nxt, next_frame)
			var next_scale_from: float = float(next_frame.get("scale_from", 1.0))
			nxt.scale = Vector2(next_scale_from, next_scale_from)
			nxt.modulate.a = 0.0
			var tw_cross_out := create_tween()
			tw_cross_out.tween_property(current, "modulate:a", 0.0, cross_to_next)
			var tw_cross_in := create_tween()
			tw_cross_in.tween_property(nxt, "modulate:a", 1.0, cross_to_next)
			ok = await _await_or_skip(cross_to_next)
			if not ok:
				_last_frame_rect = nxt
				return
		else:
			# Final frame — play full duration, leave visible (overlay stays for dialog).
			var ok: bool = await _await_or_skip(duration)
			_last_frame_rect = current
			if not ok:
				return


func _apply_pivot(rect: TextureRect, frame: Dictionary) -> void:
	var pivot_arr: Array = frame.get("pivot", [0.5, 0.5]) as Array
	var px: float = float(pivot_arr[0]) if pivot_arr.size() > 0 else 0.5
	var py: float = float(pivot_arr[1]) if pivot_arr.size() > 1 else 0.5
	rect.pivot_offset = Vector2(rect.size.x * px, rect.size.y * py)


func _await_or_skip(seconds: float) -> bool:
	if seconds <= 0.0:
		return not _skip_requested
	var elapsed: float = 0.0
	var step: float = 0.033  # ~30Hz polling, enough for skip responsiveness
	while elapsed < seconds:
		if _skip_requested:
			return false
		await get_tree().create_timer(step, true, false, true).timeout
		elapsed += step
	return not _skip_requested


func _set_frame_image(rect: TextureRect, path: String) -> void:
	if path == "":
		rect.texture = null
		return
	var tex := load(path) as Texture2D
	if tex == null:
		GameLogger.warn("CutscenePlayer", "load() returned null for: %s (.import not generated yet?)" % path)
		rect.texture = null
		return
	rect.texture = tex
	GameLogger.info("CutscenePlayer", "frame texture loaded: %s" % path)


# ── Skip input ────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _active or _frames_done:
		return
	var consume: bool = false
	if event is InputEventKey and (event as InputEventKey).pressed:
		var k := (event as InputEventKey).keycode
		if k == KEY_SPACE or k == KEY_ENTER or k == KEY_KP_ENTER:
			consume = true
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		consume = true
	if consume:
		_skip_requested = true
		get_viewport().set_input_as_handled()


# ── JSON loading ──────────────────────────────────────────────────────────────

func _load_cutscene(id: StringName) -> Dictionary:
	var path: String = CUTSCENES_DIR + String(id) + ".json"
	if not FileAccess.file_exists(path):
		GameLogger.warn("CutscenePlayer", "cutscene file not found: %s" % path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		GameLogger.warn("CutscenePlayer", "cutscene file empty: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		GameLogger.warn("CutscenePlayer", "cutscene root not Dictionary: %s" % path)
		return {}
	GameLogger.info("CutscenePlayer", "loaded cutscene '%s' from %s" % [id, path])
	return parsed as Dictionary
