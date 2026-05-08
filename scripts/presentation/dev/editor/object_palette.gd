class_name ObjectPalette
extends VBoxContainer

## Object picker for the editor's `objects` layer. Lists one Button per
## entry in TileObjectRegistry (data/tile_objects/*.json). No
## obstacles/interactive sub-tabs — design.md §4 simplification from
## the legacy ObjectPalettePanel.
##
## Emits `selection_changed(value: Dictionary)`:
##   - Object picked: {"object_id": <object_id>}

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")
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
		var label := Localization.t(
			"%s_name" % String(object_id),
			String(object_id).capitalize())
		_add_button(label, object_id)


func _add_button(label: String, object_id: StringName) -> void:
	var btn := Button.new()
	btn.text = label
	btn.toggle_mode = true
	btn.button_group = _button_group
	UiTheme.apply_button_styling(btn)
	btn.pressed.connect(_on_pressed.bind(object_id))
	_grid.add_child(btn)
	_quick_select_buttons.append(btn)


func _on_pressed(object_id: StringName) -> void:
	selection_changed.emit({"object_id": object_id})


## Programmatic activation by KEY_1..9 — see SpawnerPalette.quick_select
## for the Godot toggle/ButtonGroup quirk that requires explicit emit.
func quick_select(n: int) -> void:
	if n < 1 or n > _quick_select_buttons.size():
		return
	var btn := _quick_select_buttons[n - 1]
	btn.button_pressed = true
	btn.pressed.emit()
