extends Node
## AudioDirector — centralized audio layer management.
##
## 047-skill-fx-system: added play_sfx(id, world_pos) — generic SFX dispatch
## under res://assets/audio/sfx/<id>. Used by UI / breaking_object / etc.
##
## 051-ability-sfx-resolver: added play_ability_sfx(ability_id, phase, pos).
## Scans res://assets/audio/sfx/abilitys/<ability_id>/ at _ready, picks files
## whose basename matches `sound_start` or `sound_end` (regex), and on each
## call returns a random pick from the matching bucket. JSON `sound_start` /
## `sound_end` fields stay as on/off gates; their value is now ignored.
##
## Stub for the bootstrap. Will manage:
## - SFX-bubbling for dialogues (Animal Crossing-style mumble).
## - Music layers (interactive composition).
## - Dialogue audio_layer routing (sfx default; tag-based).
##
## Owner: Andrey. Filled out as audio direction matures during the jam.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const SFX_BASE_PATH := "res://assets/audio/sfx/"
const VOICE_BASE_PATH := "res://assets/audio/voice/"
const ABILITIES_SFX_DIR := "res://assets/audio/sfx/abilitys/"
const ABILITY_SFX_AUDIO_EXTS: PackedStringArray = ["wav", "ogg", "mp3"]

# StringName ability_id -> { &"start": Array[String], &"end": Array[String] }.
# Built once at _ready by walking ABILITIES_SFX_DIR. Empty bucket key omitted.
var _ability_sfx_cache: Dictionary = {}
var _ability_sfx_re_start: RegEx
var _ability_sfx_re_end: RegEx


func _ready() -> void:
	_ability_sfx_re_start = RegEx.new()
	_ability_sfx_re_start.compile("sound_start")
	_ability_sfx_re_end = RegEx.new()
	_ability_sfx_re_end.compile("sound_end")
	_build_ability_sfx_cache()
	GameLogger.info("AudioDirector", "ready (ability sfx folders: %d)" % _ability_sfx_cache.size())


func play_dialogue_audio(dialogue_id: StringName, layer: String, audio_clip: String = "") -> void:
	if audio_clip.strip_edges() == "":
		GameLogger.debug("AudioDirector", "play_dialogue_audio(%s, %s) — no clip" % [dialogue_id, layer])
		return
	var path: String = _resolve_dialogue_audio_path(audio_clip)
	if path == "":
		GameLogger.warn("AudioDirector", "play_dialogue_audio: missing '%s' for '%s'" % [audio_clip, dialogue_id])
		return
	_play_path(path, null, _resolve_bus(layer))


## 047: generic SFX dispatch. id is a relative path under SFX_BASE_PATH.
## world_pos == null → non-positional via AudioStreamPlayer.
## world_pos != null → positional via AudioStreamPlayer2D at that point.
## Empty id is a valid no-op (caller doesn't need to gate). Missing file
## logs a warn and returns.
func play_sfx(id: StringName, world_pos: Variant = null) -> void:
	if id == &"":
		return
	_play_path(SFX_BASE_PATH + str(id), world_pos, _resolve_bus("sfx"))


## 051: ability-scoped dispatch. Resolves a sound by scanning the per-ability
## folder for files whose basename matches `sound_start` / `sound_end`.
## Picks a random match each call (so default_melee_damage's _sound_start /
## _sound_start1 act as variations). Empty ability_id or missing folder /
## empty bucket → no-op (warn for missing folder, silent for empty bucket
## since end-only or start-only abilities are legal).
func play_ability_sfx(ability_id: StringName, phase: StringName, world_pos: Variant = null) -> void:
	if ability_id == &"":
		return
	var bucket: Variant = _ability_sfx_cache.get(ability_id, null)
	if bucket == null:
		GameLogger.warn("AudioDirector", "play_ability_sfx: no folder for '%s'" % ability_id)
		return
	var paths: Array = (bucket as Dictionary).get(phase, [])
	if paths.is_empty():
		return
	var path: String = paths[randi() % paths.size()]
	_play_path(path, world_pos, _resolve_bus("sfx"))


func _resolve_dialogue_audio_path(audio_clip: String) -> String:
	var clip := audio_clip.strip_edges()
	if clip == "":
		return ""
	if clip.begins_with("res://"):
		return clip if ResourceLoader.exists(clip) else ""
	var path := VOICE_BASE_PATH + clip
	return path if ResourceLoader.exists(path) else ""


func _resolve_bus(layer: String) -> StringName:
	var requested := layer.strip_edges()
	var bus_name := requested
	match requested.to_lower():
		"sfx":
			bus_name = "SFX"
		"music":
			bus_name = "Music"
		"voice":
			bus_name = "Voice"
		"dialogue":
			bus_name = "Dialogue"
		_:
			pass
	if bus_name != "" and AudioServer.get_bus_index(bus_name) >= 0:
		return StringName(bus_name)
	return &"Master"


## Walks ABILITIES_SFX_DIR once and populates _ability_sfx_cache.
func _build_ability_sfx_cache() -> void:
	var dir: DirAccess = DirAccess.open(ABILITIES_SFX_DIR)
	if dir == null:
		GameLogger.warn("AudioDirector", "ability sfx dir missing: %s" % ABILITIES_SFX_DIR)
		return
	dir.list_dir_begin()
	var sub: String = dir.get_next()
	while sub != "":
		if dir.current_is_dir() and not sub.begins_with("."):
			_scan_ability_folder(sub)
		sub = dir.get_next()
	dir.list_dir_end()


func _scan_ability_folder(folder_name: String) -> void:
	var folder_path: String = ABILITIES_SFX_DIR + folder_name
	var sub: DirAccess = DirAccess.open(folder_path)
	if sub == null:
		return
	var starts: Array[String] = []
	var ends: Array[String] = []
	sub.list_dir_begin()
	var fname: String = sub.get_next()
	while fname != "":
		if not sub.current_is_dir() and not fname.begins_with("."):
			var ext: String = fname.get_extension().to_lower()
			if ABILITY_SFX_AUDIO_EXTS.has(ext):
				var stem: String = fname.get_basename()
				var full_path: String = folder_path + "/" + fname
				# end check first — if a filename contains both tokens, end
				# wins (more specific lifecycle stage).
				if _ability_sfx_re_end.search(stem) != null:
					ends.append(full_path)
				elif _ability_sfx_re_start.search(stem) != null:
					starts.append(full_path)
		fname = sub.get_next()
	sub.list_dir_end()
	if starts.is_empty() and ends.is_empty():
		return
	_ability_sfx_cache[StringName(folder_name)] = {
		&"start": starts,
		&"end": ends,
	}


## Spawns a temporary AudioStreamPlayer (or 2D) under the current scene root
## that frees itself on `finished`. No pool — concurrent SFX during a single
## cast are few; pool can be added later if needed.
func _play_path(path: String, world_pos: Variant, bus: StringName = &"Master") -> void:
	if not ResourceLoader.exists(path):
		GameLogger.warn("AudioDirector", "_play_path: missing '%s'" % path)
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		GameLogger.warn("AudioDirector", "_play_path: '%s' is not AudioStream" % path)
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = self
	if world_pos != null and world_pos is Vector2:
		var p2d: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		p2d.stream = stream
		p2d.position = world_pos
		p2d.bus = bus
		scene_root.add_child(p2d)
		p2d.finished.connect(p2d.queue_free)
		p2d.play()
	else:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.stream = stream
		p.bus = bus
		scene_root.add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
