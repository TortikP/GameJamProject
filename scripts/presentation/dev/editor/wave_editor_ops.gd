class_name WaveEditorOps
extends RefCounted

## Wave-data mutation primitives. Extracted from EditorController (Spec 061
## Φ-9) to keep the controller under its 350-line hard cap (AC33). Stateless
## — every method takes the LevelData + side-effect refs as arguments.
##
## Side-effects: autosave (via EditorIO), spawner overlay refresh (via
## LevelMutations.refresh_overlay), and toast (via emitting EventBus.
## ui_toast_requested directly — no controller indirection needed).
##
## Validation is best-effort. LevelData.validate() runs the full pass at
## save time. These methods enforce only the invariants needed to keep the
## in-memory data well-formed (e.g. contiguous wave indices, last wave's
## turns_to_next == 0).

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")


# ── Wave navigation ─────────────────────────────────────────────────────────

static func add_wave(level: LevelData, after_idx: int, io: EditorIO) -> int:
	if level == null:
		return -1
	# Fold pending grid edits from root scratchpad into waves[active] so we
	# read the *current* state of the previous wave, not a stale snapshot.
	# set_active_wave_index(same_idx) early-returns without folding — call
	# the explicit sync helper instead.
	level.sync_root_to_active_wave()
	var new_idx: int = clampi(after_idx + 1, 0, level.waves.size())
	var new_wave: Dictionary
	# Default behaviour: inherit floor + objects from the previous wave so
	# designers can build a level that transforms gradually wave-to-wave.
	# Spawners are NOT copied — duplicating the player/enemies is almost
	# never wanted. Wave-level metadata (is_special, advance_mode,
	# music_config) is reset to defaults so a boss wave doesn't silently
	# propagate. copy_wave_from_prev (separate button) keeps metadata.
	if after_idx >= 0 and after_idx < level.waves.size():
		new_wave = level.make_wave_copy_no_spawners(after_idx, new_idx)
		new_wave["is_special"] = LevelData.DEFAULT_IS_SPECIAL
		new_wave["advance_mode"] = LevelData.DEFAULT_ADVANCE_MODE
		new_wave["music_config"] = {}
	else:
		new_wave = LevelData._make_empty_wave(new_idx)
	level.waves.insert(new_idx, new_wave)
	_reindex_waves(level)
	io.enqueue_autosave(level)
	return new_idx


static func copy_wave_from_prev(level: LevelData, after_idx: int, io: EditorIO) -> int:
	if level == null or after_idx <= 0 or after_idx >= level.waves.size():
		return -1
	# See add_wave: explicit fold instead of set_active_wave_index(same).
	level.sync_root_to_active_wave()
	var new_idx: int = after_idx + 1
	var copy: Dictionary = level.make_wave_copy_no_spawners(after_idx, new_idx)
	level.waves.insert(new_idx, copy)
	_reindex_waves(level)
	io.enqueue_autosave(level)
	return new_idx


static func delete_wave(level: LevelData, idx: int, io: EditorIO) -> int:
	if level == null or level.waves.size() <= 1:
		return -1
	if idx < 0 or idx >= level.waves.size():
		return -1
	level.waves.remove_at(idx)
	_reindex_waves(level)
	# Final-wave invariant: turns_to_next == 0.
	if not level.waves.is_empty():
		level.waves[level.waves.size() - 1]["turns_to_next"] = 0
	io.enqueue_autosave(level)
	return clampi(idx, 0, level.waves.size() - 1)


static func _reindex_waves(level: LevelData) -> void:
	for i in level.waves.size():
		level.waves[i]["index"] = i


# ── Wave / spawner field setters ────────────────────────────────────────────

## Returns true if the field was applied. Returns false when the field name
## is unknown OR validation rejected the value (the controller decides what
## to do with the rejection — typically toast).
static func update_wave_field(level: LevelData, idx: int, field: String,
		value: Variant, io: EditorIO) -> bool:
	if level == null or idx < 0 or idx >= level.waves.size():
		return false
	var w: Dictionary = level.waves[idx]
	match field:
		"is_special":
			w["is_special"] = String(value)
		"turns_to_next":
			w["turns_to_next"] = int(value)
		"advance_mode":
			var s: String = String(value)
			if not (s in LevelData.VALID_ADVANCE_MODES):
				return false  # caller toasts
			w["advance_mode"] = s
		"music_config":
			if not (value is Dictionary):
				return false
			w["music_config"] = value
		_:
			GameLogger.warn("WaveEditorOps", "update_wave_field: unknown field '%s'" % field)
			return false
	level.waves[idx] = w
	io.enqueue_autosave(level)
	return true


## Update spawner fields by coord on the currently-active wave. Caller is
## responsible for refreshing the spawners overlay; we only mutate the
## LevelData side here. Active wave is sourced from level.get_active_wave_index.
static func update_spawner(level: LevelData, coord: Vector2i,
		fields: Dictionary, io: EditorIO) -> bool:
	if level == null:
		return false
	var idx: int = level.get_active_wave_index()
	if idx < 0 or idx >= level.waves.size():
		return false
	var spawners: Array = level.waves[idx].get("spawners", [])
	var hit: bool = false
	for i in spawners.size():
		var s: Dictionary = spawners[i]
		if s.get("coord", Vector2i(-1, -1)) != coord:
			continue
		for k in fields:
			match k:
				"ref":
					s["ref"] = StringName(str(fields[k]))
				"timer":
					s["timer"] = max(1, int(fields[k]))
				_:
					GameLogger.warn("WaveEditorOps",
						"update_spawner: unknown field '%s'" % k)
		spawners[i] = s
		hit = true
		break
	if not hit:
		return false
	level.waves[idx]["spawners"] = spawners
	# Active-wave: keep root spawners array in sync so overlays/runtime
	# refresh paths see the same shape.
	level.spawners = spawners.duplicate(true)
	io.enqueue_autosave(level)
	return true


# ── Dialogue triggers CRUD ──────────────────────────────────────────────────

## Returns "" on success, an error message string otherwise (caller toasts).
static func add_dialogue_trigger(level: LevelData, t: Dictionary,
		io: EditorIO) -> String:
	if level == null:
		return "no level"
	var tid: String = str(t.get("id", ""))
	if tid == "":
		return "trigger id must not be empty"
	for existing in level.dialogue_triggers:
		if str(existing.get("id", "")) == tid:
			return "trigger id '%s' already exists" % tid
	level.dialogue_triggers.append(t.duplicate(true))
	io.enqueue_autosave(level)
	return ""


static func update_dialogue_trigger(level: LevelData, old_id: StringName,
		t: Dictionary, io: EditorIO) -> String:
	if level == null:
		return "no level"
	var new_id: String = str(t.get("id", ""))
	if new_id == "":
		return "trigger id must not be empty"
	for existing in level.dialogue_triggers:
		if str(existing.get("id", "")) == new_id and StringName(new_id) != old_id:
			return "trigger id '%s' already exists" % new_id
	for i in level.dialogue_triggers.size():
		if StringName(str(level.dialogue_triggers[i].get("id", ""))) == old_id:
			level.dialogue_triggers[i] = t.duplicate(true)
			io.enqueue_autosave(level)
			return ""
	return "trigger id '%s' not found" % old_id


## Returns true if the entry existed and was removed.
static func delete_dialogue_trigger(level: LevelData, id: StringName,
		io: EditorIO) -> bool:
	if level == null:
		return false
	for i in level.dialogue_triggers.size():
		if StringName(str(level.dialogue_triggers[i].get("id", ""))) == id:
			level.dialogue_triggers.remove_at(i)
			io.enqueue_autosave(level)
			return true
	return false


# ── Skill offer ─────────────────────────────────────────────────────────────

## offer == null clears the wave's skill_offer entry; Dictionary replaces it.
## Other types are ignored.
static func update_skill_offer(level: LevelData, idx: int, offer: Variant,
		io: EditorIO) -> void:
	if level == null or idx < 0 or idx >= level.waves.size():
		return
	if offer == null:
		level.waves[idx].erase("skill_offer")
	elif offer is Dictionary:
		level.waves[idx]["skill_offer"] = (offer as Dictionary).duplicate(true)
	io.enqueue_autosave(level)
