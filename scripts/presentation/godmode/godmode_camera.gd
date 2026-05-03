extends Camera2D
## GodmodeCamera — Camera2D with mouse-wheel zoom and MMB pan.
##
## All tunables in config/game_speed.cfg [godmode]:
##   zoom_step          — zoom increment per wheel tick
##   zoom_min / zoom_max — clamp range
##   zoom_lerp_duration — Tween duration (seconds)
##
## Zoom-to-cursor invariant: the world point under the mouse remains under the
## mouse after zoom. Formula assumes anchor_mode = ANCHOR_MODE_DRAG_CENTER (default)
## and no camera rotation.
##
## Pan: hold MMB and drag. Speed compensated for zoom level.
##
## 043-camera-follow: mode-by-presence — when `_follow_target` is a valid
## Node2D, camera enters follow-mode: snaps to target every frame, MMB-pan
## is disabled, zoom-to-cursor degrades to plain scale (since `_process`
## would overwrite any cursor-anchored shift). When `_follow_target` is null
## or freed, camera reverts to free-mode (current editor behaviour).
## map_editor never calls set_follow_target — stays in free-mode by default.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

## 045-intro-cutscene: pan is gameplay-disabled by default. Map editor sets
## this to true in its scene to keep navigation. Battle/runtime scenes leave
## it false — pan during combat caused stale-cursor / off-screen click bugs
## (see HANDOFF §22).
##
## 051b: in godmode we DO want pan back, with a different model — pan is
## allowed even while following a target, but it temporarily detaches the
## follow-snap. Detach persists until `recenter_on_target()` is called
## (manually via `C` or automatically at level-end / corpse absorption).
## So allow_pan stays the gate ("scene opts in"), and the per-frame snap
## learned a second condition: "and not detached".
@export var allow_pan: bool = false

var _zoom_target: Vector2 = Vector2.ONE
var _zoom_tween: Tween

var _panning: bool = false
var _pan_last: Vector2 = Vector2.ZERO

# 015 / F-013: explicit injection from godmode_controller after Player spawn.
# Falls back to find_child("Player", ...) if no controller is present (e.g.
# camera scene loaded standalone for debugging).
var _follow_target: Node2D = null

# 051b: follow-detach latch. While true, _process skips the per-frame snap
# so the camera stays where the player panned it. Set on first MMB-drag,
# cleared by recenter_on_target() (manual `C` or scripted hook like absorb
# start / level transition).
var _follow_detached: bool = false

# 048-corpse-absorption — multi-layer additive shake. Each call to shake()
# pushes a layer; _process sums offsets and removes expired layers. Channel
# is `offset` (Camera2D's secondary), which is independent from `position`
# used by follow-mode — they don't fight.
var _shake_layers: Array[Dictionary] = []
var _shake_clock: float = 0.0


func _ready() -> void:
	_zoom_target = zoom
	_center_on_target.call_deferred()
	# 048: tag for CorpseManager (and future systems) to find via group lookup.
	add_to_group(&"main_camera")
	# 051b: hook absorb-start → recenter so the end-of-level VFX always plays
	# with the player anchored, no matter where the user panned. Ignored on
	# scenes without an active game (smoke / editor playtest).
	EventBus.corpses_absorbing_started.connect(_on_corpses_absorbing_started)


# 043-camera-follow: follow-mode is implicit — true iff target is set & alive.
# 051b: detach latch suspends the snap without losing the target reference.
func _is_following() -> bool:
	return _follow_target != null and is_instance_valid(_follow_target) and not _follow_detached


# 043-camera-follow: snap to target every frame in follow-mode.
# position_smoothing on the Camera2D node interpolates the rendered anchor.
# 048: also drives shake-offset accumulation (independent of position).
func _process(delta: float) -> void:
	if _is_following():
		global_position = _follow_target.global_position
	_apply_shake(delta)


# 051b: external recenter — clears the pan-detach latch and snaps back
# onto the followed target. Called by `C` keypress (player intent) and by
# the corpse-absorbing-started signal (scripted level transition).
func recenter_on_target() -> void:
	_follow_detached = false
	_panning = false
	_center_on_target()


func _on_corpses_absorbing_started(_count: int, _total_sec: float) -> void:
	# Active-game gate: only auto-recenter during a real campaign run, not
	# during the godmode F1 sandbox where the user may want to keep their
	# panned view across smoke tests.
	if not (ActiveGame and ActiveGame.has_active_game()):
		return
	recenter_on_target()


# 048: queue an additive shake layer. Multiple concurrent calls stack.
# amp_px ≤ 0 or duration ≤ 0 → no-op (silent — caller may pass tunables).
func shake(amp_px: float, freq: float, duration_sec: float) -> void:
	if amp_px <= 0.0 or duration_sec <= 0.0:
		return
	_shake_layers.append({
		"amp": amp_px,
		"freq": freq,
		"t_started": _shake_clock,
		"duration": duration_sec,
		"phase_seed": randf() * TAU,
	})


func _apply_shake(delta: float) -> void:
	_shake_clock += delta
	if _shake_layers.is_empty():
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	var sum := Vector2.ZERO
	var i: int = _shake_layers.size() - 1
	while i >= 0:
		var L: Dictionary = _shake_layers[i]
		var t_local: float = _shake_clock - float(L["t_started"])
		if t_local >= float(L["duration"]):
			_shake_layers.remove_at(i)
		else:
			var atten: float = 1.0 - (t_local / float(L["duration"]))
			var phase: float = float(L["phase_seed"]) + t_local * float(L["freq"]) * TAU
			sum += Vector2(sin(phase) * 0.7, cos(phase * 1.31)) * float(L["amp"]) * atten
		i -= 1
	offset = sum


## Called by godmode_controller after Player is placed. Decouples this camera
## from a fragile cross-tree node-name lookup.
func set_follow_target(target: Node2D) -> void:
	_follow_target = target
	if is_inside_tree():
		_center_on_target()


func _center_on_target() -> void:
	var target: Node2D = _follow_target
	if target == null:
		# Standalone-scene fallback. Kept so camera scene works without controller.
		target = get_tree().root.find_child("Player", true, false) as Node2D
	if target != null:
		global_position = target.global_position
		# 045: position_smoothing_enabled=true (set in godmode.tscn) makes
		# global_position assignment lerp from the previous value — which is
		# (0,0) on a fresh scene load. That causes a visible camera-drift
		# from the top-left corner toward the player at the start of every
		# level. reset_smoothing() snaps the smoothed transform to the
		# current position so the next frame renders on the player exactly.
		reset_smoothing()


func _unhandled_input(event: InputEvent) -> void:
	# 045-intro-cutscene: full input lockout on intro levels (HUD hidden,
	# scripted sequence drives the camera via _follow_target).
	if ActiveGame.has_active_game() and ActiveGame.current_is_intro():
		return

	# 051b: `C` — recenter on follow target. Cheap "I lost my player" escape
	# hatch after panning; matches conventional RTS / MOBA control.
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_C and not (ke.ctrl_pressed or ke.alt_pressed or ke.meta_pressed):
			if allow_pan and _follow_target != null:
				recenter_on_target()
				get_viewport().set_input_as_handled()
				return

	# --- MMB pan ---
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			# 051b: pan now works WITH a follow target — first MMB-drag
			# detaches the follow latch, _process stops snapping, the
			# user owns the camera until they hit `C` or the level ends.
			# allow_pan is still the scene-level gate (godmode / map editor
			# opt in; intro / cutscene scenes don't).
			if not allow_pan:
				return
			_panning = mb.pressed
			_pan_last = mb.position
			if _panning:
				_follow_detached = true
				get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and _panning:
		var mm := event as InputEventMouseMotion
		# relative is in screen pixels; divide by zoom to get world-space delta
		position -= mm.relative / zoom.x
		get_viewport().set_input_as_handled()
		return

	# --- Wheel zoom ---
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	var step: float = GameSpeed.get_value("godmode", "zoom_step", 0.1)
	var zoom_min: float = GameSpeed.get_value("godmode", "zoom_min", 0.5)
	var zoom_max: float = GameSpeed.get_value("godmode", "zoom_max", 3.0)
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_apply_zoom(_zoom_target.x + step, mb.position, zoom_min, zoom_max)
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_apply_zoom(_zoom_target.x - step, mb.position, zoom_min, zoom_max)
		get_viewport().set_input_as_handled()


func _apply_zoom(new_z: float, mouse_screen: Vector2, zmin: float, zmax: float) -> void:
	new_z = clampf(new_z, zmin, zmax)
	if is_equal_approx(new_z, _zoom_target.x):
		return

	# World position under cursor before zoom change.
	var mouse_world_before: Vector2 = get_global_mouse_position()

	_zoom_target = Vector2(new_z, new_z)

	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()

	var dur: float = GameSpeed.get_value("godmode", "zoom_lerp_duration", 0.12)
	_zoom_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_property(self, "zoom", _zoom_target, dur)

	# Zoom-to-cursor: shift camera so that mouse_world_before stays under cursor.
	# 043-camera-follow: skip the position-shift parallel tween while following —
	# `_process` would overwrite it on the next frame. In follow-mode zoom is
	# pure scale, anchored on the followed target.
	if not _is_following():
		var vp_center: Vector2 = get_viewport_rect().size * 0.5
		var mouse_world_after: Vector2 = global_position + (mouse_screen - vp_center) / new_z
		var delta: Vector2 = mouse_world_before - mouse_world_after
		_zoom_tween.parallel().tween_property(self, "position", position + delta, dur)
