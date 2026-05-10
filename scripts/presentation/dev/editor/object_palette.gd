class_name ObjectPalette
extends VBoxContainer

## Object picker for the editor's `objects` layer. Lists one Button per
## entry in TileObjectRegistry (data/tile_objects/*.json). No
## obstacles/interactive sub-tabs — design.md §4 simplification from
## the legacy ObjectPalettePanel.
##
## Emits `selection_changed(value: Dictionary)`:
##   - Object picked: {"object_id": <object_id>}
##
## ## Icons (AC5)
##
## Each button shows the object's sprite from
## `TileObject.sprite_path` (already a res:// path from the registry).
## Objects whose asset is missing degrade to a single-letter monogram —
## same fallback rule as SpawnerPalette and HexTilePalette.

const TILE_OBJECTS_DIR := "res://data/tile_objects/"

signal selection_changed(value: Dictionary)

var _button_group: ButtonGroup
var _grid: HFlowContainer
var _registry: TileObjectRegistry
var _quick_select_buttons: Array[Button] = []


func _ready() -> void:
	_registry = TileObjectRegistry.new()
	_registry.load_from_dir(TILE_OBJECTS_DIR)
	_button_group = ButtonGroup.new()
	_grid = HFlowContainer.new()
	_grid.name = "ObjectGrid"
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	add_child(_grid)
	_build_buttons()
	PaletteHelpers.decorate_quick_select_badges(_quick_select_buttons)


func _build_buttons() -> void:
	# Sort for stable 1-9 mapping across runs (registry order is dict
	# insertion order = DirAccess iteration order = filesystem-dependent).
	var ids := _registry.get_all_ids()
	ids.sort()
	for object_id in ids:
		var obj: TileObject = _registry.get_object(object_id)
		if obj == null or obj.id == &"":
			continue
		var label := Localization.t("%s_name" % String(object_id),
			String(object_id).capitalize())
		var tex: Texture2D = PaletteHelpers.load_texture(obj.sprite_path)
		var btn := PaletteHelpers.make_icon_button(_button_group, label, tex,
			String(object_id).substr(0, 1).to_upper())
		btn.set_meta("object_id", object_id)
		btn.pressed.connect(_on_pressed.bind(object_id))
		_grid.add_child(btn)
		_quick_select_buttons.append(btn)
	# Erase entry — always last; same icon + sentinel as the other two
	# palettes. Dispatcher's is_erase() detects this in _act_objects.
	var erase_btn := PaletteHelpers.make_erase_button(_button_group)
	erase_btn.pressed.connect(_on_erase_pressed)
	_grid.add_child(erase_btn)
	_quick_select_buttons.append(erase_btn)


func _on_pressed(object_id: StringName) -> void:
	selection_changed.emit({"object_id": object_id})


func _on_erase_pressed() -> void:
	selection_changed.emit(&"erase")


## Programmatic activation by KEY_1..9 — see SpawnerPalette.quick_select
## for the Godot toggle/ButtonGroup quirk that requires explicit emit.
func quick_select(n: int) -> void:
	if n < 1 or n > _quick_select_buttons.size():
		return
	var btn := _quick_select_buttons[n - 1]
	btn.button_pressed = true
	btn.pressed.emit()


## Restore stored selection without emitting. Returns true on match.
func select_value(value: Variant) -> bool:
	if typeof(value) == TYPE_STRING_NAME and StringName(value) == &"erase":
		for btn in _quick_select_buttons:
			if btn != null and btn.has_meta("is_erase"):
				btn.button_pressed = true
				return true
		return false
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var target := StringName(String((value as Dictionary).get("object_id", "")))
	for btn in _quick_select_buttons:
		if btn == null or not btn.has_meta("object_id"):
			continue
		if StringName(btn.get_meta("object_id")) == target:
			btn.button_pressed = true
			return true
	return false
