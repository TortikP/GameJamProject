extends Node
## DialogueManager — autoload. Queues and plays dialogue scenes.
## Registered after DialogueDB in project.godot.

const GameLogger   = preload("res://scripts/infrastructure/game_logger.gd")
const PANEL_SCENE  := "res://scenes/ui/dialogue_panel.tscn"
const CANVAS_LAYER := 20   # modal overlay above gameplay UI

var _queue:             Array      = []   # Array[StringName] — resolved ids
var _played_per_run:    Dictionary = {}   # StringName -> true
var _played_per_session: Dictionary = {}  # StringName -> true

var _scene_start_id: StringName = &""
var _scene_visited:  Dictionary = {}

var _panel: Node = null   # DialoguePanel instance, persistent


func _ready() -> void:
	# Fail fast if DialogueDB is missing — autoload order problem
	if not has_node("/root/DialogueDB"):
		GameLogger.error("DialogueManager", "DialogueDB autoload not found — check autoload order")
		return

	EventBus.run_started.connect(_on_run_started)
	GameLogger.info("DialogueManager", "ready")


# ── Public API ────────────────────────────────────────────────────────────────

func play(id: StringName, force: bool = false) -> bool:
	if not DialogueDB.has_line(id):
		GameLogger.warn("DialogueManager", "play('%s') — id not in DB" % id)
		return false

	if is_playing():
		if force:
			_queue.append(id)
			GameLogger.debug("DialogueManager", "enqueue '%s' (force)" % id)
			return true
		else:
			GameLogger.warn("DialogueManager", "play('%s') — already playing, drop (use force=true to enqueue)" % id)
			return false

	_begin_scene(id)
	return true


func request(event: StringName, context: Dictionary = {}, force: bool = false) -> StringName:
	if is_playing():
		if force:
			var line = DialogueDB.find_by_event(event, context, _make_played_dict())
			if line == null:
				GameLogger.warn("DialogueManager", "request('%s') — no matching line found" % event)
				return &""
			_queue.append(line.id)
			GameLogger.debug("DialogueManager", "enqueue '%s' for event '%s' (force)" % [line.id, event])
			return line.id
		else:
			GameLogger.warn("DialogueManager", "request('%s') — already playing, drop" % event)
			return &""

	var line = DialogueDB.find_by_event(event, context, _make_played_dict())
	if line == null:
		GameLogger.warn("DialogueManager", "request('%s') — no matching line found" % event)
		return &""

	_begin_scene(line.id)
	return line.id


func is_playing() -> bool:
	return _scene_start_id != &""


func clear_queue() -> void:
	_queue.clear()
	GameLogger.debug("DialogueManager", "queue cleared")


# ── Internal ──────────────────────────────────────────────────────────────────

func _make_played_dict() -> Dictionary:
	return {"run": _played_per_run, "session": _played_per_session}


func _on_run_started() -> void:
	# NOTE (TODO 005-roguelike-loop): currently run_started is emitted once at
	# boot in Main._ready(), so _played_per_run is cleared exactly once and
	# behaves identically to _played_per_session until the roguelike loop
	# starts re-emitting run_started on respawn / new run. Author of 005:
	# decide whether respawn = new run, and emit accordingly.
	_played_per_run.clear()
	GameLogger.debug("DialogueManager", "_played_per_run cleared on run_started")


func _get_panel() -> Node:
	if _panel == null:
		var canvas := CanvasLayer.new()
		canvas.layer = CANVAS_LAYER
		canvas.name = "DialogueLayer"
		get_tree().root.add_child(canvas)

		_panel = load(PANEL_SCENE).instantiate()
		canvas.add_child(_panel)
		_panel.hide()

	return _panel


func _begin_scene(id: StringName) -> void:
	_scene_start_id = id
	_scene_visited  = {}
	_run_scenes_async(id)


# Iterative scene runner — flattens the previous recursive _play_line_async.
# Drives the current scene until next_id is empty, then drains the queue
# without growing the await stack.
func _run_scenes_async(first_id: StringName) -> void:
	var current_scene: StringName = first_id
	while current_scene != &"":
		await _play_scene_lines(current_scene)

		EventBus.dialogue_finished.emit(_scene_start_id)
		GameLogger.info("DialogueManager", "finished %s" % _scene_start_id)
		if _panel != null:
			_panel.hide()

		_scene_start_id = &""
		_scene_visited  = {}

		if _queue.is_empty():
			current_scene = &""
		else:
			current_scene = _queue.pop_front()
			_scene_start_id = current_scene
			_scene_visited  = {}


# Walks one scene from start_id along next/choice links. Cycle-guarded.
# Played-flags are set AFTER each line completes, not before — so an
# interrupted / crashed line does not silently consume a once_per_* slot.
func _play_scene_lines(start_id: StringName) -> void:
	var current_id: StringName = start_id
	while current_id != &"":
		if _scene_visited.has(current_id):
			GameLogger.warn("DialogueManager", "cycle detected on '%s' in scene '%s' — ending scene" % [current_id, _scene_start_id])
			return

		var line = DialogueDB.get_line(current_id)
		if line == null:
			GameLogger.warn("DialogueManager", "missing line '%s' — ending scene" % current_id)
			return

		_scene_visited[current_id] = true

		# Audio + EventBus
		var speaker_data: Dictionary = DialogueDB.get_speaker(line.speaker)
		var resolved_layer: String = _resolve_layer(line, speaker_data)
		EventBus.dialogue_started.emit(current_id)
		AudioDirector.play_dialogue_audio(current_id, resolved_layer)
		GameLogger.info("DialogueManager", "play %s" % current_id)

		# Show panel and await user
		var panel = _get_panel()
		panel.show()
		panel.show_line(line, speaker_data)

		var next_id: StringName = &""
		if line.choices.size() > 0:
			var choice_idx: int = await panel.choice_picked
			var chosen = line.choices[choice_idx]
			next_id = chosen.get("next", &"")
		else:
			await panel.line_ended
			next_id = line.next

		# Mark played only now — the line was actually displayed end-to-end.
		if line.once_per_run:
			_played_per_run[current_id] = true
		if line.once_per_session:
			_played_per_session[current_id] = true

		current_id = next_id


func _resolve_layer(line: Object, speaker_data: Dictionary) -> String:
	if line.audio_layer != "":
		return line.audio_layer
	var default_layer = speaker_data.get("default_audio_layer", "")
	if default_layer != "":
		return default_layer
	return "sfx"
