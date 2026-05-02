extends Node
## LevelDialogueDirector -- autoload (039-dialogue-triggers).
##
## Lifecycle:
##   level_loaded(level)   -> cache LevelData ref, build DialogueTrigger list.
##   battle_started(arena) -> disconnect any stale handlers, connect fresh ones
##                           per unique event in _triggers.
##   battle_ended(victory) -> disconnect all, clear state.
##   run_started           -> clear once-per-run fired set.
##
## On each matched EventBus signal, checks conditions (AND semantics), then
## calls DialogueManager.play(id) or DialogueManager.request(event, ctx).
## Chained play-mode triggers on the same event fire sequentially via
## await dialogue_finished.
##
## Owner: Andrey / 039-dialogue-triggers.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

## Cached level from the most-recent level_loaded signal.
var _level: LevelData = null

## Parsed triggers for the active level. Array of DialogueTrigger.
var _triggers: Array = []

## Active EventBus connections for the current battle.
## Each entry: {event: String, callable: Callable}
var _connected_signals: Array = []

## Once-tracking sets (trigger_id -> true).
var _fired_per_run: Dictionary = {}
var _fired_per_session: Dictionary = {}

## Pending sequential play-mode queue (StringName dialogue_ids).
var _pending_plays: Array = []
var _is_chaining: bool = false

## Warn-once guard: signal name -> true.
var _warned_missing_signal: Dictionary = {}

## Warn-once guard: MoodTracker absence.
var _warned_no_mood: bool = false


func _ready() -> void:
	EventBus.run_started.connect(_on_run_started)
	EventBus.level_loaded.connect(_on_level_loaded)
	EventBus.battle_started.connect(_on_battle_started)
	EventBus.battle_ended.connect(_on_battle_ended)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)


func _on_run_started() -> void:
	_fired_per_run.clear()


func _on_level_loaded(level: LevelData) -> void:
	_level = level
	_triggers = _build_triggers(level.dialogue_triggers)
	GameLogger.info("LevelDialogueDirector",
		"level_loaded: %d triggers registered for '%s'" % [_triggers.size(), level.name])


func _on_battle_started(arena_id: StringName) -> void:
	# Re-entry guard: disconnect previous battle's handlers first.
	_disconnect_all()
	if _level == null:
		GameLogger.warn("LevelDialogueDirector", "battle_started but no level loaded -- no triggers will fire")
		return
	_connect_for_events()
	# Special case: level_started triggers must fire NOW because their
	# underlying signal (battle_started) already fired -- we're inside it.
	# Connecting to it again would wait for the NEXT battle.
	_on_event_fired(&"level_started", [arena_id, null, null])


func _on_battle_ended(_victory: bool) -> void:
	_disconnect_all()
	_is_chaining = false
	_pending_plays.clear()


func _build_triggers(raw: Array) -> Array:
	var out: Array = []
	for d in raw:
		if not (d is Dictionary):
			continue
		var t: DialogueTrigger = DialogueTrigger.from_dict(d)
		var errs: Array[String] = t.validate()
		for e in errs:
			GameLogger.warn("LevelDialogueDirector", e)
		out.append(t)
	return out


func _connect_for_events() -> void:
	# Gather unique curated event names.
	var unique: Dictionary = {}
	for t in _triggers:
		var dt: DialogueTrigger = t as DialogueTrigger
		if dt != null:
			unique[String(dt.event)] = true

	for ev_curated in unique.keys():
		# level_started is fired directly in _on_battle_started (race-safe).
		# Connecting here would only catch the NEXT battle_started.
		if ev_curated == "level_started":
			continue
		# Translate curated UI name -> actual EventBus signal name.
		var ev_signal: String = _curated_to_signal(ev_curated)
		if not EventBus.has_signal(ev_signal):
			if not _warned_missing_signal.has(ev_signal):
				_warned_missing_signal[ev_signal] = true
				GameLogger.warn("LevelDialogueDirector",
					"EventBus has no signal '%s' (for event '%s') -- triggers using it are dead" % [ev_signal, ev_curated])
			continue
		# Handler fires with the curated name so _on_event_fired matches trigger.event.
		var cb: Callable = _make_handler(StringName(ev_curated))
		EventBus.connect(ev_signal, cb)
		_connected_signals.append({"event": ev_signal, "callable": cb})


## Translate curated editor event names -> actual EventBus signal names.
## "level_started" is the user-facing alias for battle_started(arena_id).
## All other curated names already match their EventBus signal.
func _curated_to_signal(ev: String) -> String:
	match ev:
		"level_started": return "battle_started"
		_: return ev


func _make_handler(event_name: StringName) -> Callable:
	# Variadic lambda -- covers all signal arities up to 3 args.
	return func(a0 = null, a1 = null, a2 = null) -> void:
		_on_event_fired(event_name, [a0, a1, a2])


func _on_event_fired(event_name: StringName, args: Array) -> void:
	for t in _triggers:
		var dt: DialogueTrigger = t as DialogueTrigger
		if dt == null or dt.event != event_name:
			continue
		if _fired_per_run.has(dt.id):
			continue
		if _fired_per_session.has(dt.id):
			continue
		if not _conditions_pass(dt, event_name, args):
			continue
		_try_fire(dt)


func _conditions_pass(t: DialogueTrigger, event_name: StringName, args: Array) -> bool:
	var c: Dictionary = t.conditions

	# -- Event-arg-bound conditions ------------------------------------------
	if c.has("wave_index"):
		var want: int = int(c["wave_index"])
		var got: int = -1
		if event_name in [&"wave_started", &"wave_cleared", &"wave_about_to_start",
				&"skill_offer_about_to_open", &"skill_offer_closed"]:
			got = int(args[0]) if args[0] != null else -1
		if got != want:
			return false

	if c.has("absolute_turn"):
		if event_name != &"world_turn_ended":
			return false  # condition not applicable to this event
		var want_t: int = int(c["absolute_turn"])
		var got_t: int = int(args[0]) if args[0] != null else -1
		if got_t != want_t:
			return false

	if c.has("cleared_in_turns_lt"):
		if event_name != &"wave_cleared":
			return false
		var idx: int = int(args[0]) if args[0] != null else -1
		var unused: int = int(args[1]) if args[1] != null else 0
		if _level == null or idx < 0 or idx >= _level.waves.size():
			return false
		var ttn: int = int(_level.waves[idx].get("turns_to_next", 0))
		# "cleared faster than N turns" = unused >= ttn - N
		if unused < ttn - int(c["cleared_in_turns_lt"]):
			return false

	# -- Global state conditions ----------------------------------------------
	if c.has("mood_required"):
		var moods: Array = c["mood_required"]
		var mt: Node = _get_autoload("MoodTracker")
		if mt == null:
			if not _warned_no_mood:
				_warned_no_mood = true
				GameLogger.warn("LevelDialogueDirector",
					"MoodTracker absent -- mood_required condition ignored")
			# Condition skipped (degraded gracefully per AC-D23).
		else:
			var dominant: StringName = mt.get_dominant() if mt.has_method("get_dominant") else &""
			if dominant not in moods:
				return false

	if c.has("chance"):
		if randf() >= float(c["chance"]):
			return false

	return true


func _try_fire(t: DialogueTrigger) -> void:
	var ok: bool = false
	if t.play_mode == "play":
		if _is_chaining:
			_pending_plays.append(t.dialogue_id)
			ok = true
		else:
			ok = DialogueManager.play(t.dialogue_id)
			_is_chaining = ok
	else:  # "request"
		var resolved: StringName = DialogueManager.request(t.dialogue_id, _make_context())
		ok = (resolved != &"")

	if not ok:
		return

	var c: Dictionary = t.conditions
	if c.get("once_per_run", false):
		_fired_per_run[t.id] = true
	if c.get("once_per_session", false):
		_fired_per_session[t.id] = true


func _on_dialogue_finished(_id: StringName) -> void:
	if _pending_plays.is_empty():
		_is_chaining = false
		return
	var next_id: StringName = _pending_plays.pop_front()
	_is_chaining = DialogueManager.play(next_id)


func _make_context() -> Dictionary:
	return {"flags": [], "run_count": 0}


func _disconnect_all() -> void:
	for entry in _connected_signals:
		var cb: Callable = entry["callable"]
		var ev: String = entry["event"]
		if EventBus.is_connected(ev, cb):
			EventBus.disconnect(ev, cb)
	_connected_signals.clear()


func _get_autoload(name: String) -> Node:
	return get_node_or_null("/root/" + name)
