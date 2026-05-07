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

@onready var _title: Label = $Title
@onready var _back_button: Button = $BackButton


func _ready() -> void:
	# T805: explicit Localization.t with fallbacks. The .tscn keeps the
	# Russian fallback strings so editor preview stays readable even
	# if Localization autoload hasn't run yet.
	if _title != null:
		_title.text = Localization.t("ui_catalog_title", "Каталог Интерфейсов")
	if _back_button != null:
		_back_button.text = Localization.t("ui_catalog_back", "← В меню")

	var panels: int = get_tree().get_nodes_in_group(&"ui_panel").size()
	print("[ui_catalog] loaded with %d panels in group" % panels)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
