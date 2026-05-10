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
		&"ui_layers_panel_tab_hexes", "Hexes (Q)")
	add_tab(_spawner_palette, LayersModel.LAYER_SPAWNERS,
		&"ui_layers_panel_tab_spawners", "Spawners (W)")
	add_tab(_object_palette, LayersModel.LAYER_OBJECTS,
		&"ui_layers_panel_tab_objects", "Objects (E)")


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


## Light-green tint applied to whichever panel header currently hosts
## the active layer's tab content. Active = green, inactive = default.
const ACTIVE_LAYER_TINT := Color(0.55, 0.95, 0.55, 1.0)
const _NO_TINT := Color(0, 0, 0, 0)


## Tint the panel header that hosts active_layer's content with a
## light-green accent; clear any tint on the other panel(s). Called by
## EditorController on every active_layer change. The decision is
## based on whether active_layer's tab is currently attached here vs.
## torn off — get_active_tab_id() returns the LOGICAL active id (which
## is updated even when the target tab is detached, per the
## panel_tab_bar set_active no-op-on-detach guard), so it can't be
## used as a "what's actually visible in this panel" check.
func update_layer_highlight(active_layer: StringName) -> void:
	# Main panel: tint only if active layer's tab is attached here.
	var attached: bool = is_tab_attached(active_layer)
	set_header_accent(ACTIVE_LAYER_TINT if attached else _NO_TINT)
	# Floating panels (one per detached tab) — tint matching one.
	for fp in get_floating_panels():
		if fp == null or not is_instance_valid(fp):
			continue
		var fp_tab_id: StringName = StringName(
			fp.get_meta(PanelTabBar.META_ORIGIN_TAB_ID, &""))
		var matches: bool = (fp_tab_id == active_layer)
		fp.set_header_accent(ACTIVE_LAYER_TINT if matches else _NO_TINT)
