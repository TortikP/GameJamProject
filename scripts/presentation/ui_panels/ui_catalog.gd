## UI Catalog — placeholder catalog screen for ui-panels demo.
##
## Spec 055 Phase 1: minimal scene with one BasePanel heir (FullPanel).
## Phase 4 adds AlwaysCollapsedPanel, LockedByDefaultPanel, NoResizePanel.
## Phase 5 adds PinnedPanel.
## Phase 8 wires this to the main menu and applies Localization.
##
## Long-term (Spec 060): becomes a full UI Catalog with navigation,
## search, panel descriptions. The route in/out and the .tscn path
## stay stable — only the contents evolve.

extends Control


func _ready() -> void:
	var panels: int = get_tree().get_nodes_in_group(&"ui_panel").size()
	print("[ui_catalog] loaded with %d panels in group" % panels)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
