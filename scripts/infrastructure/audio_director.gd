extends Node
## AudioDirector — centralized audio layer management.
##
## Stub for the bootstrap. Will manage:
## - SFX → AI voice → human voice escalation tied to progression.
## - Music layers (interactive composition).
## - Dialogue audio_layer routing (sfx | ai_voice | human).
##
## Owner: Andrey. Filled out as audio direction matures during the jam.

const Logger = preload("res://scripts/infrastructure/logger.gd")

func _ready() -> void:
	Logger.info("AudioDirector", "ready (stub)")


# Placeholder — filled in once we have actual audio assets and policy.
func play_dialogue_audio(dialogue_id: StringName, layer: String) -> void:
	Logger.debug("AudioDirector", "play_dialogue_audio(%s, %s) — stub, no-op" % [dialogue_id, layer])
