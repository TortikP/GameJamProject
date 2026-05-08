class_name LayersPanel
extends BasePanel

## Layers panel for the level editor. Currently a flat BasePanel with a
## single HexTilePalette in body.
##
## In Spec 060 this migrates to TabbedBasePanel — `extends BasePanel`
## becomes `extends TabbedBasePanel`, and `_ready` swaps
## `body.add_child(palette)` for `add_tab(palette, &"hexes", ...)` plus
## `add_tab(SpawnerPalette.new(), &"spawners", ...)` and similar for
## objects. HexTilePalette stays unchanged — it's just a Control,
## already decoupled from any panel chrome (Q-059-6 flip rationale).
##
## Re-emits HexTilePalette.selection_changed as
## `hex_palette_selection_changed`. The transparent re-emit keeps
## EditorController unaware of HexTilePalette as a class — the
## controller depends only on LayersPanel's signal contract.

signal hex_palette_selection_changed(value: Variant)

var _palette: HexTilePalette


func _ready() -> void:
	# CRITICAL: super._ready() FIRST. BasePanel resolves nodes,
	# normalizes anchors, applies theme, and sets up handlers in
	# this order. Body operations are only valid after.
	# (CLAUDE.md trap row — same gotcha hit in spec 057.)
	super._ready()
	_palette = HexTilePalette.new()
	_palette.name = "HexTilePalette"
	_palette.selection_changed.connect(_on_palette_changed)
	get_body_container().add_child(_palette)


func _on_palette_changed(value: Variant) -> void:
	hex_palette_selection_changed.emit(value)
