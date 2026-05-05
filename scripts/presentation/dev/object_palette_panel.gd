extends PanelContainer
## ObjectPalettePanel — TabBar (Spawners / Obstacles / Interactive) + filter
## row + clickable button list. Filters apply to Obstacles + Interactive only;
## hidden on the Spawners tab.
##
## Categorization (deterministic from TileObject fields, no new schema):
##   breakable=true OR behavior_effect_id != "" → Interactive
##   else                                       → Obstacle
##
## Spawner list comes from data/enemies/*.json + a hardcoded Player entry.
##
## Signals (consumed by MapEditorController):
##   object_picked(object_id: StringName)
##   spawner_picked(kind: StringName, ref: StringName)

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")
const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const DraggablePanel = preload("res://scripts/presentation/dev/draggable_panel.gd")

const ENEMIES_DIR: String = "res://data/enemies/"

const TAB_SPAWNERS: int = 0
const TAB_OBSTACLES: int = 1
const TAB_INTERACTIVE: int = 2

signal object_picked(object_id: StringName)
signal spawner_picked(kind: StringName, ref: StringName)

var _controller: Node = null
var _registry: TileObjectRegistry

var _tab_bar: TabBar
var _filter_row: HBoxContainer
var _filter_large: CheckBox
var _filter_small: CheckBox
var _filter_elev: CheckBox
var _filter_has_effect: CheckBox
var _content: VBoxContainer

var _current_tab: int = TAB_SPAWNERS


func _ready() -> void:
	_apply_theme()
	EventBus.ui_theme_reloaded.connect(_apply_theme)
	_build_ui()
	_rebuild_for_tab(_current_tab)


func setup(controller: Node, registry: TileObjectRegistry) -> void:
	_controller = controller
	_registry = registry
	if is_inside_tree():
		_rebuild_for_tab(_current_tab)


func _apply_theme() -> void:
	add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var header := Label.new()
	header.text = Localization.t("ui_object_palette_title", "Objects")
	UiTheme.apply_label_kind(header, "header")
	vbox.add_child(header)
	_install_drag(header)

	_tab_bar = TabBar.new()
	_tab_bar.clip_tabs = false  # show all 3 tabs always; no scroll arrows
	_tab_bar.add_tab(Localization.t("ui_object_palette_tab_spawners", "Spawners"))
	_tab_bar.add_tab(Localization.t("ui_object_palette_tab_obstacles", "Obstacles"))
	_tab_bar.add_tab(Localization.t("ui_object_palette_tab_interactive", "Interactive"))
	_tab_bar.tab_changed.connect(_on_tab_changed)
	vbox.add_child(_tab_bar)

	# Filter row (visibility toggled per tab)
	_filter_row = HBoxContainer.new()
	_filter_row.add_theme_constant_override("separation", 4)
	_filter_large = _make_filter(Localization.t("ui_object_palette_filter_large", "Large"), true)
	_filter_small = _make_filter(Localization.t("ui_object_palette_filter_small", "Small"), true)
	_filter_elev = _make_filter(Localization.t("ui_object_palette_filter_elev", "Elev"), true)
	_filter_has_effect = _make_filter(Localization.t("ui_object_palette_filter_effect", "Effect"), false)
	_filter_row.add_child(_filter_large)
	_filter_row.add_child(_filter_small)
	_filter_row.add_child(_filter_elev)
	_filter_row.add_child(_filter_has_effect)
	vbox.add_child(_filter_row)

	# Content
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 4)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(_content)
	vbox.add_child(scroll)

	# VBox itself should fill the panel so the scroll has room to expand.
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _make_filter(label: String, default_on: bool) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = label
	cb.button_pressed = default_on
	cb.toggled.connect(_on_filter_toggled)
	return cb


func _on_tab_changed(idx: int) -> void:
	_current_tab = idx
	_filter_row.visible = (idx != TAB_SPAWNERS)
	_rebuild_for_tab(idx)


func _on_filter_toggled(_pressed: bool) -> void:
	if _current_tab != TAB_SPAWNERS:
		_rebuild_for_tab(_current_tab)


func _rebuild_for_tab(tab: int) -> void:
	if _content == null:
		return
	for child in _content.get_children():
		child.queue_free()
	match tab:
		TAB_SPAWNERS:
			_build_spawner_buttons()
		TAB_OBSTACLES:
			_build_object_buttons(false)
		TAB_INTERACTIVE:
			_build_object_buttons(true)


# ── Spawners tab ────────────────────────────────────────────────────────────

func _build_spawner_buttons() -> void:
	# Player first (always)
	_content.add_child(_make_spawner_button(Localization.t("ui_object_palette_player_spawn", "Player Spawn"), &"player", &""))
	# Enemies from data/enemies/*.json
	var dir := DirAccess.open(ENEMIES_DIR)
	if dir == null:
		GameLogger.warn("ObjectPalette", "Cannot read %s" % ENEMIES_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var enemy_id := fname.get_basename()
			var enemy_name := Localization.t("%s_name" % enemy_id, enemy_id.capitalize())
			var label := Localization.tf("ui_object_palette_spawn_enemy", [enemy_name], "Spawn: %s")
			_content.add_child(_make_spawner_button(label, &"enemy", StringName(enemy_id)))
		fname = dir.get_next()
	dir.list_dir_end()


func _make_spawner_button(label: String, kind: StringName, ref: StringName) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.toggle_mode = true
	UiTheme.apply_button_styling(btn)
	btn.set_meta("spawner_kind", String(kind))
	btn.set_meta("spawner_ref", String(ref))
	btn.pressed.connect(_on_spawner_pressed.bind(kind, ref, btn))
	return btn


func _on_spawner_pressed(kind: StringName, ref: StringName, btn: Button) -> void:
	_untoggle_others(btn)
	spawner_picked.emit(kind, ref)


# ── Object tabs (Obstacles / Interactive) ───────────────────────────────────

func _build_object_buttons(want_interactive: bool) -> void:
	if _registry == null:
		var lbl := Label.new()
		lbl.text = Localization.t("ui_object_palette_registry_missing", "(registry not loaded)")
		_content.add_child(lbl)
		return
	for obj_id in _registry.get_all_ids():
		var obj: TileObject = _registry.get_object(obj_id)
		if obj == null or obj.id == &"":
			continue
		var is_interactive: bool = obj.breakable or obj.behavior_effect_id != &""
		if is_interactive != want_interactive:
			continue
		if not _passes_filter(obj):
			continue
		_content.add_child(_make_object_button(obj))


func _passes_filter(obj: TileObject) -> bool:
	# Type checkboxes
	var type_match: bool = false
	if _filter_large.button_pressed and obj.level == TileObject.Level.LARGE:
		type_match = true
	if _filter_small.button_pressed and obj.level == TileObject.Level.SMALL:
		type_match = true
	if _filter_elev.button_pressed and obj.level == TileObject.Level.ELEVATION:
		type_match = true
	if not type_match:
		return false
	# Has-effect filter
	if _filter_has_effect.button_pressed and obj.behavior_effect_id == &"":
		return false
	return true


func _make_object_button(obj: TileObject) -> Button:
	var btn := Button.new()
	var tag: String = ""
	match obj.level:
		TileObject.Level.LARGE: tag = "L"
		TileObject.Level.SMALL: tag = "S"
		TileObject.Level.ELEVATION: tag = "E"
	btn.text = "[%s] %s" % [tag, Localization.t("tile_objects_%s_name" % String(obj.id), String(obj.id))]
	btn.toggle_mode = true
	# Tooltip — quick at-a-glance summary
	var lines: PackedStringArray = []
	lines.append("blocks_movement: %s" % obj.blocks_movement)
	lines.append("blocks_abilities: %s" % obj.blocks_abilities_through)
	if obj.breakable:
		lines.append("hp: %d" % obj.hp)
	if obj.behavior_effect_id != &"":
		lines.append("effect: %s" % obj.behavior_effect_id)
	if obj.aura_radius > 0:
		lines.append("aura radius: %d" % obj.aura_radius)
	btn.tooltip_text = "\n".join(lines)
	UiTheme.apply_button_styling(btn)
	btn.set_meta("object_id", String(obj.id))
	btn.pressed.connect(_on_object_pressed.bind(obj.id, btn))
	return btn


func _on_object_pressed(object_id: StringName, btn: Button) -> void:
	_untoggle_others(btn)
	object_picked.emit(object_id)


func _untoggle_others(self_btn: Button) -> void:
	# set_pressed_no_signal: don't re-fire 'pressed' on every other toggle —
	# Godot will otherwise cascade into unintended slot-handler calls.
	for child in _content.get_children():
		if child is Button and child != self_btn:
			(child as Button).set_pressed_no_signal(false)


func _install_drag(handle: Control) -> void:
	var dragger := DraggablePanel.new()
	add_child(dragger)
	dragger.setup(self, handle)


# ── Public selection API (eyedropper / 1-9 quick select) ───────────────────

## Programmatically select the spawner button matching (kind, ref). Switches
## tab to Spawners first. No-op if not found.
func select_spawner(kind: StringName, ref: StringName) -> void:
	_switch_tab(TAB_SPAWNERS)
	if _content == null:
		return
	for child in _content.get_children():
		if not (child is Button):
			continue
		var btn := child as Button
		if String(btn.get_meta("spawner_kind", "")) != String(kind):
			continue
		if String(btn.get_meta("spawner_ref", "")) != String(ref):
			continue
		btn.button_pressed = true
		_on_spawner_pressed(kind, ref, btn)
		return


## Programmatically select the object button matching object_id. Switches
## tab to Obstacles or Interactive based on the object's traits. No-op if
## the registry isn't loaded or the id isn't found.
func select_object(object_id: StringName) -> void:
	if _registry == null:
		return
	var obj: TileObject = _registry.get_object(object_id)
	if obj == null:
		return
	var is_interactive: bool = obj.breakable or obj.behavior_effect_id != &""
	var target_tab: int = TAB_INTERACTIVE if is_interactive else TAB_OBSTACLES
	_switch_tab(target_tab)
	if _content == null:
		return
	for child in _content.get_children():
		if not (child is Button):
			continue
		var btn := child as Button
		if String(btn.get_meta("object_id", "")) != String(object_id):
			continue
		btn.button_pressed = true
		_on_object_pressed(object_id, btn)
		return


## Quick palette select — pick the N-th button (0-indexed) within the
## currently-active tab. Out of range → no-op.
func select_nth(idx: int) -> void:
	if _content == null or idx < 0:
		return
	var i: int = 0
	for child in _content.get_children():
		if not (child is Button):
			continue
		if i == idx:
			var btn := child as Button
			# Dispatch by tab — meta keys differ.
			match _current_tab:
				TAB_SPAWNERS:
					var kind := StringName(String(btn.get_meta("spawner_kind", "")))
					var ref := StringName(String(btn.get_meta("spawner_ref", "")))
					btn.button_pressed = true
					_on_spawner_pressed(kind, ref, btn)
				_:
					var obj_id := StringName(String(btn.get_meta("object_id", "")))
					if String(obj_id) == "":
						return
					btn.button_pressed = true
					_on_object_pressed(obj_id, btn)
			return
		i += 1


## Internal — switch tab and rebuild content if needed. No event-loop wait.
func _switch_tab(tab: int) -> void:
	if _tab_bar == null or _current_tab == tab:
		# Same tab — content is already current, nothing to do.
		return
	_tab_bar.current_tab = tab  # fires tab_changed → _on_tab_changed → rebuild
