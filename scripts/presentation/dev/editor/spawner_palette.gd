class_name SpawnerPalette
extends VBoxContainer

## Spawner picker for the editor's `spawners` layer. Lists Player +
## one Button per file in data/enemies/*.json. Single ButtonGroup gives
## radio-mode. Owned by LayersPanel; lives as the content of the
## `spawners` tab on TabbedBasePanel.
##
## Emits `selection_changed(value: Dictionary)`:
##   - Player picked:  {"kind": &"player", "ref": &""}
##   - Enemy picked:   {"kind": &"enemy",  "ref": <enemy_id>}
##
## Stub in Φ-3 — empty body so layers_panel can `add_tab(SpawnerPalette.new())`.
## Real implementation lands in Φ-4 (T-060-22).

signal selection_changed(value: Dictionary)


func _ready() -> void:
	pass


## 1-9 quick-select hook called from EditorController via the active
## palette. No-op in stub; real impl in Φ-4.
func quick_select(_n: int) -> void:
	pass
