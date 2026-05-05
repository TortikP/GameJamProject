extends Node
## AudioDirector — centralized audio layer management.
##
## 047-skill-fx-system: added play_sfx(id, world_pos) — generic SFX dispatch
## under res://assets/audio/sfx/<id>. Used by UI / breaking_object / etc.
##
## 051-ability-sfx-resolver: added play_ability_sfx(ability_id, phase, pos).
## Initial impl scanned res://assets/audio/sfx/abilitys/<ability_id>/ via
## DirAccess at _ready. JSON `sound_start` / `sound_end` fields stay as
## on/off gates; their value is ignored.
##
## 053-pck-audio-portrait-fix: DirAccess.list_dir on res:// in exported
## .pck builds doesn't enumerate imported audio files (they live as
## hashed .sample under .godot/imported/ rather than as their original
## .wav names in the source dir). Switched to lazy convention probing
## via ResourceLoader.exists — works identically in editor and pck.
## Cache is populated on first play_ability_sfx call per ability_id.
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
# 053: probe canonical name + numbered variants <id>_sound_start[N].<ext>
# from N=0 (no suffix) up to N=ABILITY_SFX_VARIATIONS_MAX-1. 4 covers the
# current max (default_melee_damage has _sound_start + _sound_start1) with
# headroom; cost is 12 ResourceLoader.exists calls per ability on first cast.
const ABILITY_SFX_VARIATIONS_MAX := 4

# StringName ability_id -> { &"start": Array[String], &"end": Array[String] }.
# 053: lazy — populated on first play_ability_sfx for that ability_id.
# Absent key = not yet probed; explicit empty arrays = probed and silent.
var _ability_sfx_cache: Dictionary = {}


func _ready() -> void:
	GameLogger.info("AudioDirector", "ready (ability sfx: lazy probe, max %d variations)" % ABILITY_SFX_VARIATIONS_MAX)


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


## 051: ability-scoped dispatch. Resolves a sound by probing the per-ability
## folder for canonical filenames `<ability_id>_sound_start[N].<ext>` and
## `<ability_id>_sound_end[N].<ext>` (N=0..ABILITY_SFX_VARIATIONS_MAX-1).
## Picks a random match each call (so default_melee_damage's _sound_start /
## _sound_start1 act as variations). Empty ability_id or empty bucket → no-op
## (silent — probing has no false-positive risk that warrants log noise).
##
## 053: lazy probing replaces 051's DirAccess scan, which didn't enumerate
## imported audio in exported .pck builds.
func play_ability_sfx(ability_id: StringName, phase: StringName, world_pos: Variant = null) -> void:
	if ability_id == &"":
		return
	if not _ability_sfx_cache.has(ability_id):
		_ability_sfx_cache[ability_id] = _probe_ability_folder(ability_id)
	var bucket: Dictionary = _ability_sfx_cache[ability_id]
	var paths: Array = bucket.get(phase, [])
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


## 053: probe-on-demand replacement for 051's DirAccess scan. Convention-
## based: <id>_sound_start[N].<ext> / <id>_sound_end[N].<ext> in folder
## <ABILITIES_SFX_DIR><id>/. ResourceLoader.exists handles both editor
## (raw filesystem) and exported .pck (remap table) uniformly.
func _probe_ability_folder(ability_id: StringName) -> Dictionary:
	var folder: String = ABILITIES_SFX_DIR + String(ability_id) + "/"
	var starts: Array[String] = []
	var ends: Array[String] = []
	for ext in ABILITY_SFX_AUDIO_EXTS:
		for i in ABILITY_SFX_VARIATIONS_MAX:
			var suffix: String = "" if i == 0 else str(i)
			var ps: String = "%s%s_sound_start%s.%s" % [folder, String(ability_id), suffix, ext]
			if ResourceLoader.exists(ps):
				starts.append(ps)
			var pe: String = "%s%s_sound_end%s.%s" % [folder, String(ability_id), suffix, ext]
			if ResourceLoader.exists(pe):
				ends.append(pe)
	return { &"start": starts, &"end": ends }


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
