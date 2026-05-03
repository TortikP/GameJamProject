extends Node
## AudioDirector — centralized audio layer management.
##
## 047-skill-fx-system: added play_sfx(id, world_pos) — generic SFX dispatch
## used by FxDirector for ability sound_start / sound_end. Convention path:
## res://assets/audio/sfx/<id>. Missing file → warn + return (no crash, since
## current data/skills/*.json reference yet-to-be-shipped .wav stubs).
##
## Stub for the bootstrap. Will manage:
## - SFX-bubbling for dialogues (Animal Crossing-style mumble).
## - Music layers (interactive composition).
## - Dialogue audio_layer routing (sfx default; tag-based).
##
## Owner: Andrey. Filled out as audio direction matures during the jam.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const SFX_BASE_PATH := "res://assets/audio/sfx/"

func _ready() -> void:
	GameLogger.info("AudioDirector", "ready (stub)")


# Placeholder — filled in once we have actual audio assets and policy.
func play_dialogue_audio(dialogue_id: StringName, layer: String) -> void:
	GameLogger.debug("AudioDirector", "play_dialogue_audio(%s, %s) — stub, no-op" % [dialogue_id, layer])


## 047: generic SFX dispatch. id is a relative path under SFX_BASE_PATH.
## world_pos == null → non-positional via AudioStreamPlayer.
## world_pos != null → positional via AudioStreamPlayer2D at that point.
## Empty id is a valid no-op (caller doesn't need to gate). Missing file
## logs a warn and returns — current skill JSONs reference unshipped stubs,
## crashing on every cast would be useless.
func play_sfx(id: StringName, world_pos: Variant = null) -> void:
	if id == &"":
		return
	var path: String = SFX_BASE_PATH + str(id)
	if not ResourceLoader.exists(path):
		GameLogger.warn("AudioDirector", "play_sfx: missing '%s'" % path)
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		GameLogger.warn("AudioDirector", "play_sfx: '%s' is not AudioStream" % path)
		return
	# Spawn a temporary player as a child of the current scene so it survives
	# the caller and frees itself on finished. No pool — we expect <=few
	# concurrent SFX during a single cast; a pool can be added later if needed.
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = self
	if world_pos != null and world_pos is Vector2:
		var p2d := AudioStreamPlayer2D.new()
		p2d.stream = stream
		p2d.position = world_pos
		p2d.bus = &"Master"
		scene_root.add_child(p2d)
		p2d.finished.connect(p2d.queue_free)
		p2d.play()
	else:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = &"Master"
		scene_root.add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
