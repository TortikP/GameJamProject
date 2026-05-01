extends RefCounted
## UiSignalHelpers — small static helpers for cross-cutting UI plumbing.
##
## Used via explicit preload (no class_name, no autoload — pattern from GameLogger):
##
##   const UiHelpers = preload("res://scripts/presentation/ui_signal_helpers.gd")
##   UiHelpers.attach_focus_release(my_spinbox, ["cast_slot_0", "wait_turn"])
##
## Why static and not autoload: these are pure helpers, no state. Autoload bloat is
## a real concern for jam projects — every new autoload adds startup cost and
## another global to think about. Static preload pattern from CLAUDE.md is the
## established convention.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")


## Releases focus from a LineEdit/SpinBox when one of the listed game-key actions
## is pressed. Prevents the focus-stealing trap (handoff §7) where typing
## a value into a SpinBox swallows Q/W/E/R/SPACE because the engine routes them
## as text input.
##
## Usage:
##   UiHelpers.attach_focus_release(hp_spinbox, ["cast_slot_0", "cast_slot_1",
##       "cast_slot_2", "cast_slot_3", "wait_turn"])
##
## The action names are the same strings used by InputMap (see project.godot
## [input] section). If an action doesn't exist it's silently ignored — we don't
## want jam helpers to throw on missing input bindings.
static func attach_focus_release(node: Control, game_actions: Array) -> void:
	if node == null:
		GameLogger.warn("UiHelpers", "attach_focus_release: node is null")
		return
	# Connect to gui_input — fires on focused-control events. We can't override
	# _input on the host script from a helper, so we listen via signal.
	if not node.gui_input.is_connected(_on_gui_input_release_focus):
		node.gui_input.connect(_on_gui_input_release_focus.bind(node, game_actions))


static func _on_gui_input_release_focus(event: InputEvent, node: Control, game_actions: Array) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	for action_name in game_actions:
		if InputMap.has_action(action_name) and event.is_action_pressed(action_name):
			node.release_focus()
			return


## Sets up a CanvasLayer to behave as a pause-triggering modal:
## - PROCESS_MODE_ALWAYS so it keeps responding when the world is paused
## - emits EventBus.ui_modal_opened/closed with the given id
## - flips get_tree().paused on visibility
##
## Modal scripts call this in _ready() then just toggle .visible to open/close.
##
##   func _ready():
##       UiHelpers.setup_modal_pause(self, &"pause_menu")
##
## Multiple modals can stack — last close also unsets pause via _open_modals tracking
## that lives on EventBus listeners (each modal manages its own state, the global
## "is anything open" check is done by counting on the listening side).
static func setup_modal_pause(canvas_layer: CanvasLayer, modal_id: StringName) -> void:
	if canvas_layer == null:
		GameLogger.warn("UiHelpers", "setup_modal_pause: canvas_layer is null")
		return
	canvas_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	# Hook visibility_changed — this fires when .visible flips on the layer.
	# Note: CanvasLayer doesn't have visibility_changed natively; route through
	# its first child Control if present, or expect the modal script to call
	# emit_modal_opened/closed manually. Default approach: helper provides the
	# emit functions, modals call them on open/close.


## Helper for modals to call on open. Emits signal + sets pause.
## Pair with emit_modal_closed.
##
## Nested modal pause via depth counter: the first opener sets pause=true,
## subsequent opens just increment. The last close (counter back to 0) flips
## pause=false. This avoids the bug where an inner ConfirmModal's close would
## unpause the world while the outer PauseMenu is still meant to be paused.
static var _modal_depth: int = 0


static func emit_modal_opened(modal_id: StringName, pause_world: bool = true) -> void:
	EventBus.ui_modal_opened.emit(modal_id)
	if not pause_world:
		return
	_modal_depth += 1
	if _modal_depth == 1:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.paused = true


## Helper for modals to call on close. Emits signal + clears pause IF this was
## the last open modal (depth → 0).
static func emit_modal_closed(modal_id: StringName, unpause_world: bool = true) -> void:
	EventBus.ui_modal_closed.emit(modal_id)
	if not unpause_world:
		return
	_modal_depth = maxi(0, _modal_depth - 1)
	if _modal_depth == 0:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.paused = false
