extends CanvasLayer
## CrtPostFx — fullscreen CRT post-process autoload.
##
## Single CanvasLayer (layer = 128) sitting above every game CanvasLayer with
## one fullscreen ColorRect that runs `crt.gdshader`. Toggle on/off with F6
## or via `CrtPostFx.enabled = ...` from anywhere.
##
## NO class_name — autoload singleton is accessed as `CrtPostFx` (project.godot).
## Adding `class_name` here would shadow the autoload name. Same pattern as
## EventBus, GameSpeed.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@onready var _screen: ColorRect = $Screen


func _ready() -> void:
	# Process input even when game is paused (pause menu still wants CRT toggle).
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameLogger.info("CrtPostFx", "ready (enabled=%s, layer=%d)" % [str(visible), layer])


func _unhandled_input(event: InputEvent) -> void:
	# Same pattern as game_speed.gd:48 — no echo, no held repeats.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		toggle()
		get_viewport().set_input_as_handled()


# --- Public API -------------------------------------------------------------

## Toggle CRT effect on/off. Bound to F6.
func toggle() -> void:
	enabled = not enabled


## CanvasLayer.visible drives whether the ColorRect renders at all.
## Setting `enabled = false` is zero-cost — the shader doesn't run.
var enabled: bool = true:
	set(value):
		enabled = value
		visible = value
		GameLogger.info("CrtPostFx", "toggled %s" % ("ON" if value else "OFF"))


## Adjust a single shader uniform at runtime.
##
## Use case: settings panel slider for "CRT intensity" calls
## `set_param(&"vignette_strength", 0.4)` etc.
##
## Silently ignores unknown uniforms (logged at WARN). Caller passes raw float;
## for vec3 uniforms use `set_param_vec3` instead.
func set_param(uniform_name: StringName, value: float) -> void:
	if _screen == null or _screen.material == null:
		return
	var mat: ShaderMaterial = _screen.material
	if mat.shader == null:
		return
	if not _shader_has_param(mat, uniform_name):
		GameLogger.warn("CrtPostFx", "unknown shader uniform: %s" % str(uniform_name))
		return
	mat.set_shader_parameter(uniform_name, value)


## Same as set_param but for vec3 uniforms (e.g. warm_tint).
func set_param_vec3(uniform_name: StringName, value: Vector3) -> void:
	if _screen == null or _screen.material == null:
		return
	var mat: ShaderMaterial = _screen.material
	if mat.shader == null:
		return
	mat.set_shader_parameter(uniform_name, value)


# --- Internal ---------------------------------------------------------------

func _shader_has_param(mat: ShaderMaterial, uniform_name: StringName) -> bool:
	# Walk the shader's uniform list. Slow but only called on miss path.
	var target := String(uniform_name)
	for u in mat.shader.get_shader_uniform_list():
		var name_v: Variant = u.get("name", "")
		if String(name_v) == target:
			return true
	return false
