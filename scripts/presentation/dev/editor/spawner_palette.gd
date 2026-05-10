class_name SpawnerPalette
extends VBoxContainer

## Spawner picker for the editor's `spawners` layer. Lists Player +
## one Button per file in data/enemies/*.json. Single ButtonGroup gives
## radio-mode. Owned by LayersPanel; lives as the content of the
## `spawners` tab on TabbedBasePanel.
##
## Emits `selection_changed(value: Dictionary)`:
##   - Player picked:  {"kind": &"player", "ref": &"", "timer": <spin>}
##   - Enemy picked:   {"kind": &"enemy",  "ref": <enemy_id>, "timer": <spin>}
##   - Erase:          &"erase" (sentinel, no timer)
##
## `timer` is the per-session "spawn-after-N-turns" value applied to every
## newly-placed spawner. Per-spawner editing was removed in F-061-IMPL-6
## (post-spawners-tab teardown). Existing spawners on loaded maps keep
## their original timer untouched.
##
## ## Icons (AC4)
##
## Each enemy button shows its sprite from `data/enemies/<id>.json:sprite`
## (relative path normalized to res:// by PaletteHelpers.load_texture).
## Player has no sprite asset — uses a "★" glyph fallback to match the
## SpawnersOverlay visual idiom. Enemies whose sprite path is missing
## degrade to a single-letter monogram.

const ENEMIES_DIR := "res://data/enemies/"

const TIMER_MIN: int = 0
const TIMER_MAX: int = 99
const TIMER_DEFAULT: int = 1

signal selection_changed(value: Dictionary)

var _button_group: ButtonGroup
var _grid: HFlowContainer
var _timer_spin: SpinBox
var _quick_select_buttons: Array[Button] = []


func _ready() -> void:
	_button_group = ButtonGroup.new()
	# Timer row (above grid). Single SpinBox controls the `timer` field
	# applied to all newly placed spawners — F-061-IMPL-6.
	var timer_row := HBoxContainer.new()
	timer_row.add_theme_constant_override("separation", 6)
	add_child(timer_row)
	var timer_lbl := Label.new()
	timer_lbl.text = Localization.t("ui_spawner_palette_timer", "Spawn timer:")
	timer_lbl.tooltip_text = Localization.t("ui_spawner_palette_timer_hint",
		"Turns until spawner triggers. 0 = immediate. Applied to newly-placed spawners.")
	timer_row.add_child(timer_lbl)
	_timer_spin = SpinBox.new()
	_timer_spin.min_value = TIMER_MIN
	_timer_spin.max_value = TIMER_MAX
	_timer_spin.step = 1
	_timer_spin.value = TIMER_DEFAULT
	timer_row.add_child(_timer_spin)
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
	var player_btn := PaletteHelpers.make_icon_button(_button_group,
		Localization.t("ui_spawner_palette_player", "Player"),
		null, "★")
	player_btn.set_meta("kind", &"player")
	player_btn.set_meta("ref", &"")
	player_btn.pressed.connect(_on_pressed.bind(&"player", &""))
	_grid.add_child(player_btn)
	_quick_select_buttons.append(player_btn)
	# Enemies from data/enemies/*.json — sorted for stable 1-9 mapping
	# across runs (DirAccess iteration order is filesystem-dependent).
	var entries := _list_enemy_entries()
	for entry in entries:
		var tex: Texture2D = PaletteHelpers.load_texture(String(entry["sprite_path"]))
		var btn := PaletteHelpers.make_icon_button(_button_group,
			String(entry["label"]), tex,
			String(entry["id"]).substr(0, 1).to_upper())
		btn.set_meta("kind", &"enemy")
		btn.set_meta("ref", entry["id"])
		btn.pressed.connect(_on_pressed.bind(&"enemy", entry["id"]))
		_grid.add_child(btn)
		_quick_select_buttons.append(btn)
	# Erase entry — always last, AC14 quick-select stops at this slot
	# only when there are <9 entries before it (which there are: Player
	# + up to 12 enemies). Emits &"erase" sentinel so dispatcher's
	# is_erase() check works the same as on the hexes layer.
	var erase_btn := PaletteHelpers.make_erase_button(_button_group)
	erase_btn.pressed.connect(_on_erase_pressed)
	_grid.add_child(erase_btn)
	_quick_select_buttons.append(erase_btn)


func _on_erase_pressed() -> void:
	selection_changed.emit(&"erase")


func _list_enemy_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var dir := DirAccess.open(ENEMIES_DIR)
	if dir == null:
		return entries
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var enemy_id := StringName(fname.get_basename())
			# Read sprite path from each JSON; same pattern Localization
			# uses for asset-side keys. Cheaper than instantiating a full
			# enemy registry just for icons.
			var sprite_path := _read_sprite_field(ENEMIES_DIR + fname)
			entries.append({
				"id": enemy_id,
				"label": Localization.t("%s_name" % String(enemy_id),
					String(enemy_id).capitalize()),
				"sprite_path": sprite_path,
			})
		fname = dir.get_next()
	dir.list_dir_end()
	entries.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	return entries


static func _read_sprite_field(json_path: String) -> String:
	var raw := FileAccess.get_file_as_string(json_path)
	if raw == "":
		return ""
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return ""
	return str((parsed as Dictionary).get("sprite", ""))


func _on_pressed(kind: StringName, ref: StringName) -> void:
	var t: int = TIMER_DEFAULT
	if _timer_spin != null:
		t = int(_timer_spin.value)
	selection_changed.emit({"kind": kind, "ref": ref, "timer": t})


## Programmatic activation by KEY_1..9 in InputDispatcher. Buttons in a
## ButtonGroup with toggle_mode don't emit `pressed` when their
## button_pressed property is set programmatically — emit explicitly.
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
	var d: Dictionary = value
	var target_kind := StringName(String(d.get("kind", "")))
	var target_ref := StringName(String(d.get("ref", "")))
	for btn in _quick_select_buttons:
		if btn == null or not btn.has_meta("kind"):
			continue
		if StringName(btn.get_meta("kind")) == target_kind \
				and StringName(btn.get_meta("ref")) == target_ref:
			btn.button_pressed = true
			return true
	return false
