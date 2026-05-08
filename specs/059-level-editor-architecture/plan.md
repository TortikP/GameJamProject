# 059 — Plan: Level Editor architecture from scratch

Спек: [`spec.md`](./spec.md). Резолвлены T-059-1..5 + Q-059-6..9 (Q-059-6 после flip — плоский BasePanel).

## Что дальше (TL;DR)

Восемь имплементационных шагов + smoke по AC1-AC14. Размер: spec-M (1.5–2 дня).

1. **`LayersModel`** (~80 строк) — RefCounted state holder. Без deps.
2. **`HexTilePalette`** (~120 строк) — Control с button-grid + Erase. Без deps на наш новый код.
3. **`LayersPanel`** (~50 строк) + `layers_panel.tscn` (~7 строк) — обёртка вокруг `base_panel.tscn` со script-override, в `_ready` создаёт HexTilePalette в body.
4. **`InputDispatcher`** (~140 строк) — RefCounted с DragState. DI через конструктор: получает controller, grid, layers_model.
5. **`EditorController`** (~280 строк, должен быть ≤300) — главный контроллер сцены. Owns всех остальных, wires panels.
6. **`level_editor.tscn`** — корневая сцена. Зеркалит минимум `map_editor.tscn`, без overlays.
7. **Main menu wiring** — кнопка `LevelEditorNewButton`, обработчик `_on_level_editor_new`.
8. **Loc keys + _sources** — 2 новых ключа (en/ru/_sources).

Smoke (AC1-AC14) — ручной прогон в Godot. Никаких новых зависимостей в проекте — используем существующие `LevelData`, `LevelSerializer`, `HexGrid`, `level_meta_panel.gd`, `base_panel.tscn`, `hex_terrain.tres`, `toast_layer.tscn`, `Localization`, `UiTheme`.

Главные риски — sequencing внутри `EditorController._ready` (R1), ConfigFile-collision панелей со старого редактора через persistence_scope_override (R2). Подробно в §Risks.

## Архитектурное обоснование

### Почему три модуля, а не один большой контроллер (per Q-059-5)

Старый `MapEditorController` — 1551 строка, монолит с 5 mode'ами и 7 set_mode-методами. Любая новая фича патчит файл в нескольких местах. 059 заходит с другой стороны: **разделить ответственности**.

- **`LayersModel`** — pure state. Что выбрано в активном слое. Не знает про grid, panels, input. Тестируется отдельно (юнит-тестами в потенциальном GUT, без зависимостей).
- **`InputDispatcher`** — pure pipeline. Принимает `InputEvent`, возвращает «что делать». Не знает про UI panels, не сохраняет state кроме DragState и `_last_painted_coord`. В 060 расширяется обработкой Q/W/E переключения слоёв и шорткатов palette select — без правок controller'а.
- **`EditorController`** — orchestration. Owns модели и dispatcher, wires сигналы panels'ов, делает paint/erase в HexGrid через `tile_map_layer.set_cell()`. Тонкая прослойка ≤300 строк.

Граница между ними формальная: dispatcher вызывает controller через **узкое API** (`paint_floor` / `erase_floor`). Никаких обратных вызовов dispatcher → panel или panel → dispatcher. Wiring живёт в одном месте — `EditorController._wire_panels()`.

### Почему subfolder `scripts/presentation/dev/editor/`

В старом коде `scripts/presentation/dev/` — плоский каталог: `map_editor_controller.gd`, `floor_palette_panel.gd`, `object_palette_panel.gd`, `tool_panel.gd`, ещё ~10 файлов. После добавления наших ~6 новых файлов туда же — 16+ файлов в одном каталоге, среди них половина — старая половина — новая. Subfolder `editor/` — простая визуальная сепарация: «всё что в `editor/` относится к новому редактору».

После 060 (удаление `MapEditorController` + старых palette'ов) остаётся ~5 файлов в плоском `dev/` и наш `editor/` — будет лишняя иерархия. Тогда либо переезжаем `editor/*` на верхний уровень, либо оставляем (organizational benefit). Решаем после 060 (F-059-3).

### Почему RefCounted, а не Node для `LayersModel` / `InputDispatcher`

Они не имеют lifecycle потребностей: ни `_ready`, ни `_input` (dispatcher получает event'ы через явный `controller._input(event) → dispatcher.handle(event)`), ни сигналов наружу. RefCounted дешевле — не нужен add_child, не висит в scene tree, автоматически освобождается через ref-count при queue_free контроллера.

`HexTilePalette` и `LayersPanel` — Node-производные (Control / BasePanel), потому что им нужно жить в scene tree (рендериться, получать input).

### Почему Erase = просто кнопка в палитре, а не отдельная toggle

Старый `FloorPalettePanel` имел отдельный `_erase_btn` сверху + tile grid внизу. Мутил цикличную логику с `set_pressed_no_signal` для синхронизации между ними. У нас — один ButtonGroup на все Buttons (тайлы + Erase), radio-mode из коробки. Подписан один сигнал `selection_changed(value)` где value = либо `Dictionary{source_id, atlas_coord}`, либо `&"erase"`. EditorController / InputDispatcher оперируют `selection`-абстракцией без if-else на «erase mode vs paint mode».

Это **архитектурно** подкрепляет thin slice: «слой `hexes` имеет selection, selection бывает `tile` или `erase`». В 060 для `spawners`/`objects` — та же модель, и Erase у каждого таба своё.

### Почему playtest-toast вместо disabled-кнопки (Q-059-7)

`level_meta_panel.gd` — общий на оба редактора. Делать `_playtest_btn.disabled = true` conditional («если controller не умеет playtest») потребовало бы:
- либо добавить публичный setter (`set_playtest_enabled(bool)`) — лишний API surface на panel,
- либо сделать controller знать про panel'ы и вызывать setter — обратное direction зависимости.

Toast — нулевая правка panel'а. Controller подписан на signal, на сигнал отвечает toast'ом. Всё.

### Почему anti-dup через `_last_painted_coord`, а не Set всех координат drag'а (Q-059-9)

Семантика thin slice: «не повторять paint на той же координате если курсор не покинул её». Мышь над coord A → paint A. Двигается над coord A → ничего. Ушла на B → paint B. Вернулась на A → paint A (потому что переход через B). Это **последняя painted coord**, не история.

Для `_last_painted_coord` достаточно одного Vector2i. Set всех был бы overkill (для thin slice) и менял бы семантику: «не повторять paint на любой координате drag'а». На smoke семантика «последняя» интуитивнее: пользователь хочет «закрасить как кисточкой», то есть рисовать когда курсор движется. Set всех — это «pixel-perfect одноразовый paint каждой координаты», что бывает нужно для медленной кисти, но overkill для нашего случая.

Если в smoke (T009-T012) всплывёт жалоба на повторное рисование при дёрганиях курсора — finding, переключаемся на Set.

## Имплементация по шагам

### Step 1 — `LayersModel` (T001)

`scripts/presentation/dev/editor/layers_model.gd`:

```gdscript
class_name LayersModel
extends RefCounted

## Pure state holder for the level editor: which layer is active and what
## item is selected within each layer. No node ops, no signals.
##
## Selection types:
##   - Hex tile:  Dictionary {"source_id": int, "atlas_coord": Vector2i}
##   - Erase:     StringName &"erase"
##   - Empty:     null

const LAYER_HEXES := &"hexes"

var active_layer: StringName = LAYER_HEXES

# Per-layer selection. Keys are layer ids, values are layer-specific.
var _selections: Dictionary = {}


func get_active_selection() -> Variant:
	return _selections.get(active_layer, null)


func set_selection(layer: StringName, value: Variant) -> void:
	_selections[layer] = value


func is_erase() -> bool:
	var sel := get_active_selection()
	return typeof(sel) == TYPE_STRING_NAME and StringName(sel) == &"erase"
```

Размер ~30-50 строк. AC14 soft cap = 100 — с большим запасом.

### Step 2 — `HexTilePalette` (T002)

`scripts/presentation/dev/editor/hex_tile_palette.gd`:

```gdscript
class_name HexTilePalette
extends VBoxContainer  # или GridContainer / HFlowContainer — TBD

## Tile picker grid for the editor's `hexes` layer. Iterates the configured
## TileSet's atlas sources, renders one Button per (source, atlas_coord),
## plus an Erase button at the end. Single ButtonGroup → radio-mode.
##
## Emits selection_changed(value: Variant) where value is either:
##   - Dictionary {"source_id": int, "atlas_coord": Vector2i}
##   - StringName &"erase"

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")
const TILESET_PATH := "res://scenes/arena/tilesets/hex_terrain.tres"
const ICON_SIZE := Vector2(48, 48)

signal selection_changed(value: Variant)

var _button_group: ButtonGroup
var _grid: HFlowContainer  # внутренний контейнер для button'ов


func _ready() -> void:
	_button_group = ButtonGroup.new()
	_grid = HFlowContainer.new()
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	add_child(_grid)
	_build_buttons()


func _build_buttons() -> void:
	var tileset := load(TILESET_PATH) as TileSet
	if tileset == null:
		push_warning("[HexTilePalette] cannot load %s" % TILESET_PATH)
		return
	for source_idx in tileset.get_source_count():
		var source_id := tileset.get_source_id(source_idx)
		var src := tileset.get_source(source_id) as TileSetAtlasSource
		if src == null:
			continue
		for tile_idx in src.get_tiles_count():
			var atlas_coord := src.get_tile_id(tile_idx)
			_grid.add_child(_make_tile_button(src, source_id, atlas_coord))
	_grid.add_child(_make_erase_button())


func _make_tile_button(atlas: TileSetAtlasSource, source_id: int, atlas_coord: Vector2i) -> Button:
	# AtlasTexture-based icon. Pattern from floor_palette_panel.gd:141.
	# selection_changed.emit({"source_id": source_id, "atlas_coord": atlas_coord})
	# on `pressed` signal.
	...

func _make_erase_button() -> Button:
	# Localized text "Erase". On `pressed` → selection_changed.emit(&"erase").
	...
```

Конкретики Button-creation — паттерн из `floor_palette_panel.gd:141-172` (AtlasTexture, theme styling, set_meta для отладки). У нас проще: один ButtonGroup, без replace-all.

Размер: ~80-120 строк (плюс minus в зависимости от объёма комментариев). Soft cap не задан — палитра не критичный модуль.

### Step 3 — `LayersPanel` + `.tscn` (T003)

`scripts/presentation/dev/editor/layers_panel.gd`:

```gdscript
class_name LayersPanel
extends BasePanel

## Layers panel for the level editor. Currently flat-BasePanel with a single
## HexTilePalette in body. Will migrate to TabbedBasePanel in 060 when
## spawners/objects layers are added — palette stays unchanged, just wraps
## in add_tab().
##
## Re-emits HexTilePalette.selection_changed as hex_palette_selection_changed
## for the controller, so the controller doesn't reach into internals.

signal hex_palette_selection_changed(value: Variant)

var _palette: HexTilePalette


func _ready() -> void:
	super._ready()
	_palette = HexTilePalette.new()
	_palette.selection_changed.connect(_on_palette_changed)
	get_body_container().add_child(_palette)


func _on_palette_changed(value: Variant) -> void:
	hex_palette_selection_changed.emit(value)
```

`scenes/dev/editor/layers_panel.tscn` — минимальная композиция, как 5 dev-panels в map_editor.tscn после спека 057:

```
[gd_scene format=3 load_steps=3]

[ext_resource type="PackedScene" uid="uid://52k1drd6uyfx" path="res://scenes/ui/panels/base_panel.tscn" id="1_bp"]
[ext_resource type="Script" path="res://scripts/presentation/dev/editor/layers_panel.gd" id="2_lp"]

[node name="LayersPanel" instance=ExtResource("1_bp")]
script = ExtResource("2_lp")
panel_id = &"layers_panel"
panel_title_key = &"ui_layers_panel_title"
panel_title_fallback = "Layers"
min_panel_size = Vector2(220, 240)
```

Loc-ключ `ui_layers_panel_title` — добавим в шаге 8.

Соблюдаем CLAUDE.md trap row: `super._ready()` ПЕРВЫМ.

### Step 4 — `InputDispatcher` (T004)

`scripts/presentation/dev/editor/input_dispatcher.gd`:

```gdscript
class_name InputDispatcher
extends RefCounted

## Centralized input pipeline for the level editor. Receives InputEvents
## from EditorController._unhandled_input, decides if the event triggers
## a paint/erase action, and forwards via the narrow controller API
## (paint_floor / erase_floor).
##
## Drag state is internal: LMB-drag = continuous paint, RMB-drag =
## continuous erase. Anti-dup via _last_painted_coord prevents repeat
## work when the cursor is held over a single hex.

const NO_COORD := Vector2i(-99999, -99999)

enum DragState { NONE, PAINTING, ERASING }

var _controller  # EditorController, untyped to avoid circular class_name
var _grid: HexGrid
var _layers: LayersModel

var _drag_state: int = DragState.NONE
var _last_painted_coord: Vector2i = NO_COORD


func _init(controller, grid: HexGrid, layers: LayersModel) -> void:
	_controller = controller
	_grid = grid
	_layers = layers


func handle(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return _handle_mouse_button(event)
	if event is InputEventMouseMotion and _drag_state != DragState.NONE:
		return _handle_mouse_drag(event)
	if event is InputEventKey and event.pressed:
		var ke := event as InputEventKey
		if ke.keycode == KEY_ESCAPE:
			_drag_state = DragState.NONE
			_last_painted_coord = NO_COORD
			return true
	return false


func _handle_mouse_button(event: InputEventMouseButton) -> bool:
	# LMB / RMB press → start paint or erase, perform action on first coord.
	# LMB / RMB release → reset drag state + last coord.
	# ...
	return false


func _handle_mouse_drag(event: InputEventMouseMotion) -> bool:
	# Resolve coord_under_mouse, check anti-dup, dispatch paint or erase.
	# ...
	return false


func _act_at(coord: Vector2i, erase: bool) -> void:
	# Selection = &"erase" + LMB → erase path. Otherwise paint with selection.
	if erase or _layers.is_erase():
		_controller.erase_floor(coord)
	else:
		var sel := _layers.get_active_selection()
		if typeof(sel) != TYPE_DICTIONARY:
			return
		var d := sel as Dictionary
		_controller.paint_floor(coord, int(d["source_id"]), d["atlas_coord"] as Vector2i)
	_last_painted_coord = coord
```

`_handle_mouse_button` псевдокод:

```
mb := event as InputEventMouseButton
coord := _grid.coord_under_mouse()
if mb.button_index == MOUSE_BUTTON_LEFT:
    if mb.pressed:
        _drag_state = DragState.PAINTING
        _act_at(coord, false)
    else:
        _drag_state = DragState.NONE
        _last_painted_coord = NO_COORD
    return true
elif mb.button_index == MOUSE_BUTTON_RIGHT:
    if mb.pressed:
        _drag_state = DragState.ERASING
        _act_at(coord, true)
    else:
        _drag_state = DragState.NONE
        _last_painted_coord = NO_COORD
    return true
return false
```

`_handle_mouse_drag` псевдокод:

```
coord := _grid.coord_under_mouse()
if coord == _last_painted_coord:
    return false
_act_at(coord, _drag_state == DragState.ERASING)
return true
```

Размер: ~120-140 строк. AC14 soft cap = 150.

**Subtle point:** `coord_under_mouse()` может вернуть невалидный coord (например, координаты вне hex-сетки). Стоит проверять валидность через `_grid.is_walkable(coord)` или просто полагаться на `tile_map_layer.set_cell(coord, ...)` который тихо принимает любые координаты — для thin slice достаточно. Surface как finding если smoke выявит paint за пределами сетки.

### Step 5 — `EditorController` (T005)

`scripts/presentation/dev/editor/editor_controller.gd`. Структура (≤300 строк, AC13):

```gdscript
extends Node2D

## Level Editor Controller (059) — orchestrates the new editor's MVC:
##   Model:    LevelData (in-memory state) + LayersModel (UI selection state)
##   View:     LayersPanel + LevelMetaPanel (panels), HexGrid (tile map)
##   Input:    InputDispatcher (centralized event pipeline)
##
## Public-ish surface (called by InputDispatcher only):
##   paint_floor(coord, source_id, atlas_coord)
##   erase_floor(coord)
##
## Hard cap: 300 lines. If approaching cap, surface as finding and split off
## (likely candidate: extract LevelIO save/load wiring into a helper).

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const MAPS_DIR := "res://data/maps/"

@export var hex_grid_path: NodePath
@export var layers_panel_path: NodePath
@export var level_meta_panel_path: NodePath
@export var toast_layer_path: NodePath

var _grid: HexGrid
var _layers_panel: LayersPanel
var _meta_panel: Node  # level_meta_panel.gd extends BasePanel
var _toast_layer: Node

var _level: LevelData
var _layers: LayersModel
var _dispatcher: InputDispatcher


func _ready() -> void:
	_resolve_nodes()
	_level = LevelData.new()
	_layers = LayersModel.new()
	_layers.set_selection(LayersModel.LAYER_HEXES, _default_hex_selection())
	_dispatcher = InputDispatcher.new(self, _grid, _layers)
	_wire_panels()
	_refresh_grid_from_level()


func _unhandled_input(event: InputEvent) -> void:
	if _dispatcher.handle(event):
		get_viewport().set_input_as_handled()


# ── Public API for InputDispatcher ────────────────────────────────

func paint_floor(coord: Vector2i, source_id: int, atlas_coord: Vector2i) -> void:
	_grid.tile_map_layer.set_cell(coord, source_id, atlas_coord)
	_set_or_update_floor_cell(coord, source_id, atlas_coord)


func erase_floor(coord: Vector2i) -> void:
	_grid.tile_map_layer.set_cell(coord, -1)
	_remove_floor_cell(coord)


# ── Wiring + helpers ──────────────────────────────────────────────

func _resolve_nodes() -> void:
	_grid = get_node(hex_grid_path) as HexGrid
	_layers_panel = get_node(layers_panel_path) as LayersPanel
	_meta_panel = get_node(level_meta_panel_path)
	_toast_layer = get_node_or_null(toast_layer_path)


func _default_hex_selection() -> Dictionary:
	# First atlas tile of source 0 in hex_terrain.tres = grass (Katya's tile).
	return {"source_id": 0, "atlas_coord": Vector2i.ZERO}


func _wire_panels() -> void:
	_layers_panel.hex_palette_selection_changed.connect(_on_palette_selection)
	_meta_panel.save_requested.connect(_on_save)
	_meta_panel.load_requested.connect(_on_load)
	_meta_panel.exit_requested.connect(_on_exit)
	_meta_panel.playtest_requested.connect(_on_playtest_disabled)
	_meta_panel.name_changed.connect(_on_name_changed)
	if _meta_panel.has_method("setup"):
		_meta_panel.setup(self)


func _on_palette_selection(value: Variant) -> void:
	_layers.set_selection(LayersModel.LAYER_HEXES, value)


func _on_save() -> void:
	var path := MAPS_DIR + _level.name + ".json"
	if LevelSerializer.save(_level, path):
		_toast("Saved: %s" % path)
	else:
		_toast("Save FAILED — see Output")


func _on_load(path: String) -> void:
	var loaded := LevelSerializer.load_from(path)
	if loaded == null:
		_toast("Load FAILED — see Output")
		return
	_level = loaded
	if _meta_panel.has_method("set_level_name"):
		_meta_panel.set_level_name(_level.name)
	_refresh_grid_from_level()
	_toast("Loaded: %s" % path)


func _on_exit() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_playtest_disabled() -> void:
	_toast(Localization.t("ui_level_editor_playtest_disabled_toast",
		"Playtest not yet wired in new editor — coming in spec 060"))


func _on_name_changed(new_name: String) -> void:
	_level.name = new_name


func _refresh_grid_from_level() -> void:
	# Sync TileMapLayer with _level.floor_cells. On empty level → clear.
	_grid.tile_map_layer.clear()
	for cell in _level.floor_cells:
		var coord := cell["coord"] as Vector2i
		var source_id := int(cell["source_id"])
		var atlas := cell["atlas_coord"] as Vector2i
		_grid.tile_map_layer.set_cell(coord, source_id, atlas)


func _set_or_update_floor_cell(coord: Vector2i, source_id: int, atlas_coord: Vector2i) -> void:
	for cell in _level.floor_cells:
		if (cell["coord"] as Vector2i) == coord:
			cell["source_id"] = source_id
			cell["atlas_coord"] = atlas_coord
			return
	_level.floor_cells.append({"coord": coord, "source_id": source_id, "atlas_coord": atlas_coord})


func _remove_floor_cell(coord: Vector2i) -> void:
	for i in range(_level.floor_cells.size() - 1, -1, -1):
		if (_level.floor_cells[i]["coord"] as Vector2i) == coord:
			_level.floor_cells.remove_at(i)
			return


func _toast(text: String) -> void:
	if _toast_layer != null and _toast_layer.has_method("show_toast"):
		_toast_layer.show_toast(text)
	else:
		GameLogger.info("EditorController", text)
```

Размер ожидаемый: ~220-260 строк (с docstrings). Hard cap 300. Если на имплементации идём выше — finding + extract `_save/_load/_refresh_grid` в helper класс.

### Step 6 — `level_editor.tscn` (T006)

`scenes/dev/level_editor.tscn`. Минимально, без overlays:

```
[gd_scene load_steps=N format=3 uid="uid://level_editor_001"]

[ext_resource type="Script" path="res://scripts/presentation/dev/editor/editor_controller.gd" id="1_ec"]
[ext_resource type="PackedScene" path="res://scenes/arena/hex_grid.tscn" id="2_hex"]
[ext_resource type="Script" path="res://scripts/presentation/godmode/godmode_camera.gd" id="3_cam"]
[ext_resource type="PackedScene" path="res://scenes/ui/toast_layer.tscn" id="4_toast"]
[ext_resource type="PackedScene" path="res://scenes/dev/editor/layers_panel.tscn" id="5_lp"]
[ext_resource type="PackedScene" uid="uid://52k1drd6uyfx" path="res://scenes/ui/panels/base_panel.tscn" id="6_bp"]
[ext_resource type="Script" path="res://scripts/presentation/dev/level_meta_panel.gd" id="7_mp"]

[node name="LevelEditor" type="Node2D"]
script = ExtResource("1_ec")
hex_grid_path = NodePath("HexGrid")
layers_panel_path = NodePath("HUD/LayersPanel")
level_meta_panel_path = NodePath("HUD/LevelMetaPanel")
toast_layer_path = NodePath("HUD/ToastLayer")

[node name="BackgroundLayer" type="CanvasLayer" parent="."]
[node name="Background" type="ColorRect" parent="BackgroundLayer"]
# anchor_preset 15 (full rect) + dark color
color = Color(0.1, 0.1, 0.12, 1)

[node name="EditorCamera" type="Camera2D" parent="."]
script = ExtResource("3_cam")

[node name="HexGrid" parent="." instance=ExtResource("2_hex")]

[node name="HUD" type="CanvasLayer" parent="."]

[node name="LayersPanel" parent="HUD" instance=ExtResource("5_lp")]
anchors_preset = 0
offset_left = 16
offset_top = 60
offset_right = 280
offset_bottom = 320

[node name="LevelMetaPanel" parent="HUD" instance=ExtResource("6_bp")]
script = ExtResource("7_mp")
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -360
offset_top = 16
offset_right = -16
offset_bottom = 220
panel_id = &"level_meta"
panel_title_key = &"ui_level_meta_panel_title"
panel_title_fallback = "Level Meta"
min_panel_size = Vector2(280, 180)
persistence_scope_override = &"level_editor"

[node name="ToastLayer" parent="HUD" instance=ExtResource("4_toast")]
```

**Subtle: `persistence_scope_override = &"level_editor"`** на LevelMetaPanel. Старый `map_editor.tscn` имеет тот же `LevelMetaPanel` со своим persistence ключом. Без override оба редактора писали бы в одну ConfigFile-секцию (`<scene_path>::level_meta`), и при открытии одного ловили бы layout другого. Override на новый редактор — отдельный scope. См. R2.

### Step 7 — Main menu wiring (T007)

`scenes/main_menu.tscn` — добавить `LevelEditorNewButton` ПОСЛЕ `MapEditorButton`:

```
[node name="LevelEditorNewButton" type="Button" parent="VBox" unique_id=<новый>]
layout_mode = 2
text = "ui_main_menu_level_editor_new_button_text"
```

`scripts/presentation/main_menu.gd`:

```diff
+@onready var _level_editor_new_btn: Button = $VBox/LevelEditorNewButton
```

В функции `_ready()` (около line 79):

```diff
 _map_editor_btn.pressed.connect(_on_map_editor)
+_level_editor_new_btn.pressed.connect(_on_level_editor_new)
```

Новая функция (рядом с `_on_map_editor`):

```gdscript
func _on_level_editor_new() -> void:
	get_tree().change_scene_to_file("res://scenes/dev/level_editor.tscn")
```

Если в коде есть массив для focus-handling кнопок (line ~112-141 в текущем main_menu.gd) — добавить `_level_editor_new_btn` туда же. Surface при имплементации.

### Step 8 — Loc keys (T008)

3 новых ключа (alphabetic insertion как в спеке 058):

`data/localization/en.json`:
```
"ui_layers_panel_title":  "Layers",
"ui_level_editor_playtest_disabled_toast":  "Playtest not yet wired in new editor — coming in spec 060",
"ui_level_meta_panel_title":  "Level Meta",
"ui_main_menu_level_editor_new_button_text":  "Level Editor (new)",
```

`data/localization/ru.json`:
```
"ui_layers_panel_title":  "Слои",
"ui_level_editor_playtest_disabled_toast":  "Playtest пока не подключён в новом редакторе — будет в спеке 060",
"ui_level_meta_panel_title":  "Свойства уровня",
"ui_main_menu_level_editor_new_button_text":  "Редактор уровней (новый)",
```

`data/localization/_sources.json` — соответствующие записи source с указанием spec 059.

**4 ключа, не 2 как в §5.2 спека.** Спек упомянул только playtest и main-menu кнопку, но `level_meta_panel.tscn` (новый instance в level_editor.tscn) и `layers_panel.tscn` тоже требуют title-keys. Если уже использовались в старом редакторе — переиспользуем; иначе добавим. На имплементации проверим: `grep "ui_level_meta_panel_title" data/localization/`.

## Risks

- **R1 (sequencing внутри `EditorController._ready`).** Жёсткий порядок: resolve_nodes → init data/models → InputDispatcher → wire_panels → refresh_grid. Если перепутать — null-deref (panel слушает signal на ещё-не-создавнном controller'е, или dispatcher получает event'ы до wire_panels). Mitigation: явный § в spec.md (§5.3) + комментарий в `_ready` с порядком как контракт. Smoke (T009) ловит broken case на первом же открытии сцены.
- **R2 (ConfigFile persistence collision со старым редактором).** `LevelMetaPanel` instance в обоих редакторах с одинаковым `panel_id = &"level_meta"`. Без `persistence_scope_override` — общая секция в `layouts.cfg`. Открыли один → подвинули панель → открыли другой → панель уже подвинута. Mitigation: `persistence_scope_override = &"level_editor"` в level_editor.tscn. AC11 в смоук-листе явно проверяет старый редактор — там не должно быть регрессий по позициям панелей.
- **R3 (`coord_under_mouse()` за пределами сетки).** Может вернуть невалидный Vector2i (например, если курсор над HUD панелью). `tile_map_layer.set_cell(invalid_coord, ...)` тихо принимает — нарисует тайл вне видимой области. Не катастрофа, но неаккуратно. Mitigation: surface как finding если smoke выявит paint в странных местах. Опциональный фильтр через `_grid.is_walkable(coord)` или через `tile_map_layer.get_used_rect()` — только если smoke потребует.
- **R4 (paint events while cursor is over HUD).** Click по кнопке палитры или по level_meta_panel — должен НЕ триггерить paint на гексе под HUD'ом. Стандартный Godot путь: panel'и потребляют LMB через `mouse_filter = MOUSE_FILTER_STOP` (BasePanel должен это делать). Если события всё-таки доходят до `_unhandled_input` — finding. Контроль: `mouse_filter` BasePanel на STOP подтверждается тем что dialogue_trigger_panel etc. в map_editor.tscn не паинтит сквозь panel.
- **R5 (300-line cap на EditorController).** План оценивает ~220-260 строк с комментариями. Если на имплементации выходим за 280 — surface, начинаем урезать комментарии. Если выходим за 300 — finding + extract `_save/_load/_refresh_grid` в `LevelIO` класс (~40 строк отдельный файл). AC13 проверяет cap.
- **R6 (HexGrid.initialize не вызывается).** В `map_editor.tscn` controller вызывает `_grid.initialize()` после resolve. Мы тоже должны. Проверим что `grid_built` сигнал не нужен потребителям (не нужен — у нас нет actors, нет pathfinding). Скорее всего hex_grid.tscn сам init'ится через какой-то механизм; если нет — добавить вызов в `_ready` после resolve.

## Acceptance verification

После всех T001-T008 запустить smoke по AC1-AC14 из spec.md. Чек-лист — в `tasks.md` T009-T013. Если хоть один AC fail — блокер merge'а 059, finding в `findings.md` + правка.

После прохождения всех AC — push ветки + PR-creation URL Андрею.
