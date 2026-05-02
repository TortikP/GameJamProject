extends Node
## TelegraphRenderer — builds and tears down per-enemy cast telegraph hexes
## (primary damage tile + secondary AoE shape outlines) and movement intent
## arrows. Aggregates by coord across all live enemies' intents.

var _ctrl: Node = null


func _ready() -> void:
	_ctrl = get_parent()
