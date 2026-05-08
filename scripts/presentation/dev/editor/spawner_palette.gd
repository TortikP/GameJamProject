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
## ## Source of truth
##
## Filename scan of data/enemies/*.json (no central registry exists for
## enemies in spec 060). Each enemy_id = filename stem. Buttons are
## text-only — icons would require loading sprite_path from each json,
## skipped as an optimisation in 060 (spec §4 / plan §Φ-4 "Иконки").

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")
const ENEMIES_DIR := "res://data/enemies/"

signal selection_changed(value: Dictionary)

var _button_group: ButtonGroup
var _grid: HFlowContainer
var _quick_select_buttons: Array[Button] = []


func _ready() -> void:
	_button_group = ButtonGroup.new()
	_grid = HFlowContainer.new()
	_grid.name = "SpawnerGrid"
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	add_child(_grid)
	_build_buttons()
	PaletteHelpers.decorate_quick_select_badges(_quick_select_buttons)


func _build_buttons() -> void:
	# Player always first — uniqueness is enforced controller-side
	# (paint_spawner removes any existing player spawner before append).
	_add_button(
		Localization.t("ui_spawner_palette_player", "Player"),
		&"player", &"")
	# Enemies from data/enemies/*.json — sorted for stable 1-9 mapping
	# across runs (DirAccess iteration order is filesystem-dependent).
	var enemy_ids := _list_enemy_ids()
	enemy_ids.sort()
	for enemy_id in enemy_ids:
		var label := Localization.t(
			"%s_name" % String(enemy_id),
			String(enemy_id).capitalize())
		_add_button(label, &"enemy", enemy_id)


func _list_enemy_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	var dir := DirAccess.open(ENEMIES_DIR)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			ids.append(StringName(fname.get_basename()))
		fname = dir.get_next()
	dir.list_dir_end()
	return ids


func _add_button(label: String, kind: StringName, ref: StringName) -> void:
	var btn := Button.new()
	btn.text = label
	btn.toggle_mode = true
	btn.button_group = _button_group
	UiTheme.apply_button_styling(btn)
	btn.pressed.connect(_on_pressed.bind(kind, ref))
	_grid.add_child(btn)
	_quick_select_buttons.append(btn)


func _on_pressed(kind: StringName, ref: StringName) -> void:
	selection_changed.emit({"kind": kind, "ref": ref})


## Programmatic activation by KEY_1..9 in InputDispatcher. Buttons in a
## ButtonGroup with toggle_mode don't emit `pressed` when their
## button_pressed property is set programmatically — emit explicitly so
## the controller's selection updates (Godot quirk noted in plan §Φ-4.a).
func quick_select(n: int) -> void:
	if n < 1 or n > _quick_select_buttons.size():
		return
	var btn := _quick_select_buttons[n - 1]
	btn.button_pressed = true
	btn.pressed.emit()
