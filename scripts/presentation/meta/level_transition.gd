extends CanvasLayer
## level_transition — metamorphosis overlay between levels (035-game-editor).
##
## Lifecycle:
##   - Spawned by CampaignController as a child of the current scene.
##   - play_out() runs phases A (wobble) → B (distort+fade) → C (hold black),
##     then frees self after change_scene_to_file resolves.
##   - play_in() runs phase D (fade-in from black) on a freshly-loaded scene
##     and frees self when done.
##
## All durations come from [meta] in game_speed.cfg and are F5-reloadable.
##
## The overlay is a fullscreen ColorRect with a ShaderMaterial driving 4
## uniforms (wobble / distort / chroma / fade). We tween those uniforms
## directly via Tween.tween_method.

const SHADER: Shader = preload("res://scripts/presentation/meta/level_transition.gdshader")

# Defaults if cfg missing.
const DEFAULT_SHAKE_SEC: float = 0.4
const DEFAULT_DISTORT_SEC: float = 0.6
const DEFAULT_HOLD_SEC: float = 0.15
const DEFAULT_FADE_IN_SEC: float = 0.6

@onready var _rect: ColorRect = $Rect
var _mat: ShaderMaterial


func _ready() -> void:
	# Always sit above gameplay UI. CanvasLayer.layer is set in the .tscn
	# (high value), this is just a sanity guard if the .tscn forgets.
	if layer < 100:
		layer = 100
	_mat = _rect.material as ShaderMaterial
	if _mat == null:
		# Defensive: build material at runtime if the .tscn shipped without one.
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_rect.material = _mat
	_set_uniforms(0.0, 0.0, 0.0, 0.0)


func _set_uniforms(wobble: float, distort: float, chroma: float, fade: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("wobble", wobble)
	_mat.set_shader_parameter("distort", distort)
	_mat.set_shader_parameter("chroma", chroma)
	_mat.set_shader_parameter("fade", fade)


func _set_wobble(v: float) -> void: _mat.set_shader_parameter("wobble", v)
func _set_distort(v: float) -> void: _mat.set_shader_parameter("distort", v)
func _set_chroma(v: float) -> void: _mat.set_shader_parameter("chroma", v)
func _set_fade(v: float) -> void: _mat.set_shader_parameter("fade", v)


# ── Public API ──────────────────────────────────────────────────────────────

## Plays the OUT half of the transition (shake → distort+fade → hold black).
## Awaitable. After this returns the screen is fully black; caller should
## change_scene_to_file immediately.
func play_out() -> void:
	var shake_sec: float = float(GameSpeed.get_value("meta", "transition_shake_sec", DEFAULT_SHAKE_SEC))
	var distort_sec: float = float(GameSpeed.get_value("meta", "transition_distort_sec", DEFAULT_DISTORT_SEC))
	var hold_sec: float = float(GameSpeed.get_value("meta", "transition_hold_sec", DEFAULT_HOLD_SEC))

	# Phase A — wobble ramps in fast and stays high.
	var t1: Tween = create_tween()
	t1.tween_method(_set_wobble, 0.0, 1.0, shake_sec * 0.35)
	t1.tween_method(_set_wobble, 1.0, 0.9, shake_sec * 0.65)
	# Distort + chroma start subtle during shake.
	var t1b: Tween = create_tween()
	t1b.parallel().tween_method(_set_distort, 0.0, 0.25, shake_sec)
	t1b.parallel().tween_method(_set_chroma, 0.0, 0.25, shake_sec)
	await t1.finished

	# Phase B — distort peaks, chroma peaks, fade-to-black.
	var t2: Tween = create_tween()
	t2.parallel().tween_method(_set_wobble, 0.9, 0.0, distort_sec)
	t2.parallel().tween_method(_set_distort, 0.25, 1.0, distort_sec * 0.7)
	t2.parallel().tween_method(_set_distort, 1.0, 0.6, distort_sec * 0.3).set_delay(distort_sec * 0.7)
	t2.parallel().tween_method(_set_chroma, 0.25, 1.0, distort_sec)
	t2.parallel().tween_method(_set_fade, 0.0, 1.0, distort_sec)
	await t2.finished

	# Phase C — hold black (a beat of nothing-ness).
	_set_uniforms(0.0, 0.0, 0.0, 1.0)
	await get_tree().create_timer(hold_sec).timeout

	# Don't free here — the upcoming change_scene_to_file will free the
	# parent scene which owns us.


## Plays the IN half (fade-in from black). Use on the freshly-loaded scene.
## Frees self when the fade completes.
func play_in() -> void:
	var fade_in_sec: float = float(GameSpeed.get_value("meta", "transition_fade_in_sec", DEFAULT_FADE_IN_SEC))
	# Start fully black with mild residual distort for "settling-in" feel.
	_set_uniforms(0.0, 0.15, 0.15, 1.0)
	var t: Tween = create_tween()
	t.parallel().tween_method(_set_fade, 1.0, 0.0, fade_in_sec)
	t.parallel().tween_method(_set_distort, 0.15, 0.0, fade_in_sec * 0.8)
	t.parallel().tween_method(_set_chroma, 0.15, 0.0, fade_in_sec * 0.8)
	await t.finished
	queue_free()
