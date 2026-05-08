class_name ObjectPalette
extends VBoxContainer

## Object picker for the editor's `objects` layer. Lists one Button per
## entry in TileObjectRegistry (data/tile_objects/*.json). No
## obstacles/interactive sub-tabs — design.md §4 simplification.
##
## Emits `selection_changed(value: Dictionary)`:
##   - Object picked: {"object_id": <object_id>}
##
## Stub in Φ-3 — empty body so layers_panel can `add_tab(ObjectPalette.new())`.
## Real implementation lands in Φ-4 (T-060-23).

signal selection_changed(value: Dictionary)


func _ready() -> void:
	pass


## 1-9 quick-select hook. No-op in stub; real impl in Φ-4.
func quick_select(_n: int) -> void:
	pass
