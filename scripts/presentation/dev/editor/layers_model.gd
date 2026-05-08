class_name LayersModel
extends RefCounted

## Pure state holder for the level editor: which layer is active and what
## item is selected within each layer. No node ops, no signals — value
## object owned by EditorController. RefCounted because it doesn't need
## to live in the scene tree (no _ready, no _process, no input).
##
## Selection schema (per layer):
##   - LAYER_HEXES:    Dictionary {"source_id": int, "atlas_coord": Vector2i}
##                     OR StringName &"erase"
##                     OR null  (initial — no palette pick yet)
##   - LAYER_SPAWNERS: Dictionary {"kind": StringName, "ref": StringName}
##                     kind ∈ {&"player", &"enemy"}; for player ref=&"".
##                     OR null  (initial)
##   - LAYER_OBJECTS:  Dictionary {"object_id": StringName}
##                     OR null  (initial)
##
## See spec.md §5.4 for the full schema.

const LAYER_HEXES := &"hexes"
const LAYER_SPAWNERS := &"spawners"
const LAYER_OBJECTS := &"objects"

## Canonical iteration order for Q/W/E quick-select and Tab cycling.
## Matches the order LayersPanel adds tabs in.
const LAYER_ORDER: Array[StringName] = [LAYER_HEXES, LAYER_SPAWNERS, LAYER_OBJECTS]

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
## Returns false for non-hexes layers (erase sentinel only exists in
## the hexes palette schema).
func is_erase() -> bool:
	var sel: Variant = get_active_selection()
	return typeof(sel) == TYPE_STRING_NAME and StringName(sel) == &"erase"


## True when active layer has any non-null selection. Used by Φ-5
## InputDispatcher to short-circuit paint when there's nothing to paint.
func has_selection() -> bool:
	return get_active_selection() != null


## Tab handler: advance active_layer to the next entry in LAYER_ORDER,
## wrapping at the end. Returns the new active_layer for caller chaining
## (e.g. controller emits a UI sync signal). Forward-only by design —
## see spec.md AC13 / Q-060-5 for the rationale (Shift+Tab not implemented).
func cycle_active_forward() -> StringName:
	var idx := LAYER_ORDER.find(active_layer)
	if idx < 0:
		active_layer = LAYER_HEXES
	else:
		active_layer = LAYER_ORDER[(idx + 1) % LAYER_ORDER.size()]
	return active_layer
