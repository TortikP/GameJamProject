extends Node
## AudioDirector — centralized audio layer management.
##
## Stub for the bootstrap. Will manage:
## - SFX-bubbling for dialogues (Animal Crossing-style mumble).
## - Music layers (interactive composition).
## - Dialogue audio_layer routing (sfx default; tag-based).
##
## Owner: Andrey. Filled out as audio direction matures during the jam.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

func _ready() -> void:
	GameLogger.info("AudioDirector", "ready (stub)")


# Placeholder — filled in once we have actual audio assets and policy.
func play_dialogue_audio(dialogue_id: StringName, layer: String) -> void:
	GameLogger.debug("AudioDirector", "play_dialogue_audio(%s, %s) — stub, no-op" % [dialogue_id, layer])
