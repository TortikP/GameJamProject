## WindowMode — F11 toggles between windowed (override size) and borderless fullscreen.
##
## Spec 054 (smoke revision): with viewport bumped to 1920×1080, launching at
## window size = viewport occupies the whole 1080p monitor and leaves no room
## for the Godot editor / console while testing. project.godot now overrides
## window size to 1600×900 (windowed-by-default for dev workflow). F11 jumps
## to native-resolution fullscreen for crisp pixel-perfect render and back.
##
## WINDOW_MODE_FULLSCREEN (borderless windowed fullscreen) is preferred over
## EXCLUSIVE_FULLSCREEN — alt-tab is instant, no display-mode switch.
extends Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # F11 must work while paused


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_fullscreen"):
		return
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	get_viewport().set_input_as_handled()
