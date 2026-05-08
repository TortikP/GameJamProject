class_name LayersModel
extends RefCounted

## Pure state holder for the level editor: which layer is active and what
## item is selected within each layer. No node ops, no signals — value
## object owned by EditorController. RefCounted because it doesn't need
## to live in the scene tree (no _ready, no _process, no input).
##
## Selection schema (per layer):
##   - Hex tile:  Dictionary {"source_id": int, "atlas_coord": Vector2i}
##   - Erase:     StringName &"erase"
##   - Empty:     null  (default — happens before user touches the palette)
##
## In Spec 060 this gains LAYER_SPAWNERS, LAYER_OBJECTS plus methods to
## switch active_layer when LayersPanel becomes a TabbedBasePanel.

const LAYER_HEXES := &"hexes"

var active_layer: StringName = LAYER_HEXES

# Per-layer selection. Keys are layer ids (StringName), values are
# layer-specific Variants. Untyped on purpose — see schema above.
var _selections: Dictionary = {}


## Returns the current selection of `active_layer`, or null if the user
## hasn't picked anything in that layer yet.
func get_active_selection() -> Variant:
	return _selections.get(active_layer, null)


## Sets the selection for a specific layer. Doesn't change active_layer.
func set_selection(layer: StringName, value: Variant) -> void:
	_selections[layer] = value


## True when active layer's selection is the erase sentinel.
## Convenience for InputDispatcher._act_at to decide paint vs erase.
func is_erase() -> bool:
	var sel := get_active_selection()
	return typeof(sel) == TYPE_STRING_NAME and StringName(sel) == &"erase"
