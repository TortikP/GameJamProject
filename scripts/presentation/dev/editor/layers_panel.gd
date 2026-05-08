class_name LayersPanel
extends TabbedBasePanel

## Layers panel for the level editor. TabbedBasePanel with three tabs
## — Hexes / Spawners / Objects — added programmatically in _ready.
## HexTilePalette is unchanged from 059; SpawnerPalette and ObjectPalette
## are new in 060 (Φ-4).
##
## ## Signals
##
##   layer_selection_changed(layer_id: StringName, value: Variant)
##     Emitted whenever ANY palette's selection_changed fires; the
##     handler binds layer_id at connect time so EditorController gets
##     a single fan-in slot.
##
##   active_tab_changed(tab_id: StringName) — INHERITED from TabbedBasePanel.
##     Fires only on user click of a tab button (see TabbedBasePanel
##     comment for full policy). Programmatic switches via Q/W/E
##     keyboard shortcuts go through set_active_tab() which does NOT emit.
##
## ## Quick-select dispatch
##
## EditorController calls get_palette_for_layer(_layers.active_layer)
## then palette.quick_select(n) for KEY_1..9. Each palette stores its
## own button list in declaration order.

signal layer_selection_changed(layer_id: StringName, value: Variant)

var _hex_palette: HexTilePalette
var _spawner_palette: SpawnerPalette
var _object_palette: ObjectPalette


func _ready() -> void:
	# CRITICAL: super._ready() FIRST. TabbedBasePanel.super._ready() runs
	# BasePanel resolution + _setup_tab_bar (creates _tab_bar). Body
	# operations + add_tab are only valid after.
	# (CLAUDE.md trap row — same gotcha hit in spec 057.)
	super._ready()
	_hex_palette = HexTilePalette.new()
	_spawner_palette = SpawnerPalette.new()
	_object_palette = ObjectPalette.new()
	# Bind layer_id at connect time so the slot signature stays
	# (value: Variant) and the controller-facing signal becomes a
	# clean (layer_id, value) two-arg form. Callable.bind appends
	# bound args AFTER the signal args, so the slot receives
	# (value, layer_id) — matches _on_palette_selection signature.
	_hex_palette.selection_changed.connect(
		_on_palette_selection.bind(LayersModel.LAYER_HEXES))
	_spawner_palette.selection_changed.connect(
		_on_palette_selection.bind(LayersModel.LAYER_SPAWNERS))
	_object_palette.selection_changed.connect(
		_on_palette_selection.bind(LayersModel.LAYER_OBJECTS))
	add_tab(_hex_palette, LayersModel.LAYER_HEXES,
		&"ui_layers_panel_tab_hexes", "Hexes")
	add_tab(_spawner_palette, LayersModel.LAYER_SPAWNERS,
		&"ui_layers_panel_tab_spawners", "Spawners")
	add_tab(_object_palette, LayersModel.LAYER_OBJECTS,
		&"ui_layers_panel_tab_objects", "Objects")


func _on_palette_selection(value: Variant, layer_id: StringName) -> void:
	layer_selection_changed.emit(layer_id, value)


## Returns the palette Control for a given layer id, or null if unknown.
## Used by EditorController.quick_select_in_active_palette to dispatch
## KEY_1..9 to the active layer's palette.
func get_palette_for_layer(layer_id: StringName) -> Node:
	match layer_id:
		LayersModel.LAYER_HEXES:
			return _hex_palette
		LayersModel.LAYER_SPAWNERS:
			return _spawner_palette
		LayersModel.LAYER_OBJECTS:
			return _object_palette
	return null
