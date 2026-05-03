extends Node
## CutscenePlayer — autoload (045-intro-cutscene).
##
## Listens for `EventBus.campaign_cutscene_requested(cutscene_id, on_done)`,
## opens a fullscreen overlay (CanvasLayer 30) and runs a multi-frame slideshow
## with scale + cross-fade between frames, then calls `on_done` and emits
## `cutscene_finished(cutscene_id)`.
##
## Designed for the office_intro flow (see specs/045) but data-driven via
## `data/cutscenes/<id>.json`. JSON schema:
##   {
##     "id": "<id>",
##     "frames": [
##       {
##         "image":               "res://...",
##         "scale_from":          float,            # default 1.0
##         "scale_to":            float,            # default 1.0
##         "duration":            float,            # default 1.0 — animation time
##         "fade_in_sec":         float,            # default 0.0
##         "cross_fade_to_next_sec": float,         # default 0.0 — overlap with next frame
##         "fade_out_sec":        float             # default 0.0 — only on last frame
##       },
##       ...
##     ]
##   }
##
## Skip via Space / Enter / mouse click — interrupts running tweens, frees
## overlay, fires `on_done`. Once `on_done` has fired (timeout or normal),
## subsequent skip events are ignored.
##
## During play, `get_tree().paused = true`. Overlay nodes use
## `PROCESS_MODE_ALWAYS` so tweens continue.
##
## Owner: Andrey / 045-intro-cutscene.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const CUTSCENES_DIR: String = "res://data/cutscenes/"
const OVERLAY_SCENE: String = "res://scenes/meta/cutscene_player.tscn"

signal cutscene_finished(cutscene_id: StringName)

var _active: bool = false
var _skip_requested: bool = false
var _current_id: StringName = &""
var _overlay: CanvasLayer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.campaign_cutscene_requested.connect(_on_cutscene_requested)
	GameLogger.info("CutscenePlayer", "ready")


func is_playing() -> bool:
	return _active


# ── Entry ─────────────────────────────────────────────────────────────────────

func _on_cutscene_requested(cutscene_id: StringName, on_done: Callable) -> void:
	if _active:
		GameLogger.warn("CutscenePlayer", "already playing — ignoring request '%s'" % cutscene_id)
		# Still must fire callback so CampaignController doesn't hang.
		on_done.call()
		cutscene_finished.emit(cutscene_id)
		return

	var data: Dictionary = _load_cutscene(cutscene_id)
	if data.is_empty():
		# warn-once already logged in _load_cutscene
		on_done.call()
		cutscene_finished.emit(cutscene_id)
		return

	_active = true
	_current_id = cutscene_id
	_skip_requested = false
	GameLogger.info("CutscenePlayer", "play '%s' — %d frames" % [cutscene_id, (data.get("frames", []) as Array).size()])

	get_tree().paused = true

	_overlay = (load(OVERLAY_SCENE) as PackedScene).instantiate() as CanvasLayer
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	# Parent to current_scene (not root) so a scene-change during cutscene
	# (e.g. ESC -> Quit to menu) frees the overlay along with the level.
	# CanvasLayer renders globally regardless of its parent's transform, so
	# z-order (layer=30) is preserved.
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(_overlay)

	await _play_frames(data.get("frames", []) as Array)

	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	get_tree().paused = false
	_active = false

	on_done.call()
	cutscene_finished.emit(cutscene_id)
	GameLogger.info("CutscenePlayer", "done '%s'" % cutscene_id)
	_current_id = &""


# ── Animation ─────────────────────────────────────────────────────────────────

func _play_frames(frames: Array) -> void:
	if frames.is_empty():
		return
	var root: Control = _overlay.get_node("Root") as Control
	var f1: TextureRect = root.get_node("Frame1") as TextureRect
	var f2: TextureRect = root.get_node("Frame2") as TextureRect
	# Pivot at center of each TextureRect for scale-from-center.
	# anchors_preset=15 fills parent → size set after first layout pass.
	await get_tree().process_frame
	f1.pivot_offset = f1.size * 0.5
	f2.pivot_offset = f2.size * 0.5

	# Two-buffer ping-pong: even frames go to f1, odd to f2.
	# Cross-fade overlaps current frame's tail with next frame's head.
	var slots: Array = [f1, f2]

	for i in range(frames.size()):
		if _skip_requested:
			return
		var frame: Dictionary = frames[i] as Dictionary
		var current: TextureRect = slots[i % 2]
		var next: TextureRect = slots[(i + 1) % 2]

		_set_frame_image(current, String(frame.get("image", "")))

		var scale_from: float = float(frame.get("scale_from", 1.0))
		var scale_to: float = float(frame.get("scale_to", 1.0))
		var duration: float = max(0.05, float(frame.get("duration", 1.0)))
		var fade_in: float = max(0.0, float(frame.get("fade_in_sec", 0.0)))
		var cross_to_next: float = max(0.0, float(frame.get("cross_fade_to_next_sec", 0.0)))
		var fade_out: float = max(0.0, float(frame.get("fade_out_sec", 0.0)))

		current.scale = Vector2(scale_from, scale_from)

		# Fade in (or instant pop if fade_in == 0).
		var tw_in := create_tween()
		tw_in.tween_property(current, "modulate:a", 1.0, fade_in if fade_in > 0.0 else 0.001)
		# Scale animation runs across full duration.
		var tw_scale := create_tween()
		tw_scale.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw_scale.tween_property(current, "scale", Vector2(scale_to, scale_to), duration)

		# Schedule cross-fade out for this frame, timed so it OVERLAPS with the next
		# frame's fade-in. cross_to_next is applied if there's a next frame, else
		# fade_out kicks in (handled below).
		var has_next: bool = i + 1 < frames.size()
		if has_next and cross_to_next > 0.0:
			# Wait until duration - cross_to_next, then start fading current out
			# and the next frame in. Both happen in parallel.
			var hold: float = max(0.0, duration - cross_to_next)
			var ok: bool = await _await_or_skip(hold)
			if not ok: return
			# Prepare next frame
			var next_frame: Dictionary = frames[i + 1] as Dictionary
			_set_frame_image(next, String(next_frame.get("image", "")))
			var next_scale_from: float = float(next_frame.get("scale_from", 1.0))
			next.scale = Vector2(next_scale_from, next_scale_from)
			next.modulate.a = 0.0
			var tw_cross_out := create_tween()
			tw_cross_out.tween_property(current, "modulate:a", 0.0, cross_to_next)
			var tw_cross_in := create_tween()
			tw_cross_in.tween_property(next, "modulate:a", 1.0, cross_to_next)
			ok = await _await_or_skip(cross_to_next)
			if not ok: return
		else:
			# Final frame (or no cross-fade): play full duration, then fade out if requested.
			var ok: bool = await _await_or_skip(duration)
			if not ok: return
			if fade_out > 0.0:
				var tw_out := create_tween()
				tw_out.tween_property(current, "modulate:a", 0.0, fade_out)
				ok = await _await_or_skip(fade_out)
				if not ok: return


# Returns false if skip was requested during the wait. Tweens continue independently
# until overlay is freed; that's fine because the overlay teardown happens in caller.
func _await_or_skip(seconds: float) -> bool:
	if seconds <= 0.0:
		return not _skip_requested
	var elapsed: float = 0.0
	var step: float = 0.016
	while elapsed < seconds:
		if _skip_requested:
			return false
		await get_tree().create_timer(step, true, false, true).timeout  # ignore_time_scale ok; process_in_physics false
		elapsed += step
	return not _skip_requested


func _set_frame_image(rect: TextureRect, path: String) -> void:
	if path == "":
		rect.texture = null
		return
	var tex := load(path) as Texture2D
	if tex == null:
		GameLogger.warn("CutscenePlayer", "missing texture: %s" % path)
		rect.texture = null
		return
	rect.texture = tex


# ── Skip input ────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
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
		GameLogger.warn("CutscenePlayer", "cutscene file empty/unreadable: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		GameLogger.warn("CutscenePlayer", "cutscene root not Dictionary: %s" % path)
		return {}
	return parsed as Dictionary
