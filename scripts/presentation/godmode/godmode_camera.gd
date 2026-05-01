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

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

var _zoom_target: Vector2 = Vector2.ONE
var _zoom_tween: Tween

var _panning: bool = false
var _pan_last: Vector2 = Vector2.ZERO


func _ready() -> void:
	_zoom_target = zoom
	_center_on_player.call_deferred()


func _center_on_player() -> void:
	var player := get_tree().root.find_child("Player", true, false) as Node2D
	if player != null:
		global_position = player.global_position


func _unhandled_input(event: InputEvent) -> void:
	# --- MMB pan ---
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			_pan_last = mb.position
			if _panning:
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
	var vp_center: Vector2 = get_viewport_rect().size * 0.5
	var mouse_world_after: Vector2 = global_position + (mouse_screen - vp_center) / new_z
	var delta: Vector2 = mouse_world_before - mouse_world_after
	_zoom_tween.parallel().tween_property(self, "position", position + delta, dur)
