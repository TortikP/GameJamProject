# 059 — Tasks

Спек: [`spec.md`](./spec.md). Plan: [`plan.md`](./plan.md).

## Code (Claude в impl-команде)

### Pre-check

- [ ] **T000.** Подтвердить состояние перед началом. Все условия должны выполниться:
  - `git log --oneline -1 staging` показывает merge коммит спека 058 (TabbedBasePanel).
  - `find scripts/presentation/dev/editor -type d 2>/dev/null` пусто (subfolder не создан).
  - `find scripts/presentation/dev -name "editor_controller.gd" -o -name "layers_model.gd" -o -name "input_dispatcher.gd" -o -name "hex_tile_palette.gd"` пусто.
  - `find scenes/dev -name "level_editor*"` пусто.
  - `find scenes/dev/editor -type d 2>/dev/null` пусто.
  - `wc -l scripts/presentation/dev/level_meta_panel.gd` — файл существует, ~155 строк (используем как есть).
  - `cat scenes/arena/tilesets/hex_terrain.tres | head -5` — tileset существует.
  - `grep -c "MapEditorButton" scenes/main_menu.tscn` — 1 (есть Map Editor кнопка, рядом с которой добавим Level Editor).

### Module 1: LayersModel

- [ ] **T001.** Создать `scripts/presentation/dev/editor/layers_model.gd`. См. [plan.md §Step 1](./plan.md):
  - [ ] Создать subfolder `scripts/presentation/dev/editor/`.
  - [ ] `class_name LayersModel`, `extends RefCounted`.
  - [ ] Const `LAYER_HEXES := &"hexes"`.
  - [ ] Поля: `active_layer: StringName = LAYER_HEXES`, `_selections: Dictionary = {}`.
  - [ ] Методы: `get_active_selection() -> Variant`, `set_selection(layer, value) -> void`, `is_erase() -> bool`.
  - [ ] Docstring в начале файла объясняет selection types (Dictionary для tile / StringName &"erase" / null).
  - [ ] Проверка: `wc -l scripts/presentation/dev/editor/layers_model.gd` — целевой 30-60 строк.

### Module 2: HexTilePalette

- [ ] **T002.** Создать `scripts/presentation/dev/editor/hex_tile_palette.gd`. См. [plan.md §Step 2](./plan.md):
  - [ ] `class_name HexTilePalette`, `extends VBoxContainer`.
  - [ ] Const `TILESET_PATH := "res://scenes/arena/tilesets/hex_terrain.tres"`, `ICON_SIZE := Vector2(48, 48)`.
  - [ ] Signal `selection_changed(value: Variant)`.
  - [ ] Поля: `_button_group: ButtonGroup`, `_grid: HFlowContainer`.
  - [ ] `_ready` создаёт ButtonGroup, HFlowContainer, добавляет в self, вызывает `_build_buttons`.
  - [ ] `_build_buttons` итерирует sources в tileset (паттерн из `floor_palette_panel.gd:123-138`), создаёт кнопку на каждый (source_id, atlas_coord), плюс Erase кнопку в конце.
  - [ ] `_make_tile_button` — паттерн из `floor_palette_panel.gd:141-172` (toggle_mode=true, button_group=_button_group, AtlasTexture icon, custom_minimum_size, theme styling). На pressed → `selection_changed.emit({"source_id": source_id, "atlas_coord": atlas_coord})`.
  - [ ] `_make_erase_button` — Button с text=`Localization.t("ui_floor_palette_erase", "Erase")` (переиспользуем существующий ключ из старой палитры). toggle_mode=true, button_group=_button_group. На pressed → `selection_changed.emit(&"erase")`.
  - [ ] **Важно:** в отличие от `floor_palette_panel`, у нас один ButtonGroup на всё (включая Erase) — radio-mode из коробки. Никаких `set_pressed_no_signal` циклов.
  - [ ] Проверка: `wc -l scripts/presentation/dev/editor/hex_tile_palette.gd` — целевой 80-130 строк. `grep -c "set_pressed_no_signal" scripts/presentation/dev/editor/hex_tile_palette.gd` = 0 (не должно быть, ButtonGroup делает работу).

### Module 3: LayersPanel + scene

- [ ] **T003.** Создать `scripts/presentation/dev/editor/layers_panel.gd` + `scenes/dev/editor/layers_panel.tscn`. См. [plan.md §Step 3](./plan.md):
  - [ ] **`.gd`:**
    - [ ] `class_name LayersPanel`, `extends BasePanel`.
    - [ ] Signal `hex_palette_selection_changed(value: Variant)`.
    - [ ] Поле `_palette: HexTilePalette`.
    - [ ] `_ready`: **сначала `super._ready()`** (CLAUDE.md trap row), затем создать HexTilePalette, connect её signal к `_on_palette_changed`, добавить в `get_body_container()`.
    - [ ] `_on_palette_changed(value)` — re-emit как `hex_palette_selection_changed.emit(value)`. (Прозрачный re-emit; controller не должен лезть во внутренности panel'а.)
    - [ ] Docstring объясняет миграцию на TabbedBasePanel в 060.
    - [ ] Проверка: `wc -l scripts/presentation/dev/editor/layers_panel.gd` — целевой 30-50 строк. `grep "super._ready" scripts/presentation/dev/editor/layers_panel.gd` находит вызов.
  - [ ] **`.tscn`** (создать subfolder `scenes/dev/editor/` если нет):
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
  - [ ] Проверка: `cat scenes/dev/editor/layers_panel.tscn | grep -c "^\[node"` = 1.

### Module 4: InputDispatcher

- [ ] **T004.** Создать `scripts/presentation/dev/editor/input_dispatcher.gd`. См. [plan.md §Step 4](./plan.md):
  - [ ] `class_name InputDispatcher`, `extends RefCounted`.
  - [ ] Const `NO_COORD := Vector2i(-99999, -99999)`.
  - [ ] Enum `DragState { NONE, PAINTING, ERASING }`.
  - [ ] Поля: `_controller` (untyped — circular class_name avoidance), `_grid: HexGrid`, `_layers: LayersModel`, `_drag_state: int = DragState.NONE`, `_last_painted_coord: Vector2i = NO_COORD`.
  - [ ] `_init(controller, grid, layers)` — DI через конструктор.
  - [ ] `handle(event: InputEvent) -> bool` — главный entry-point. Возвращает true если event consumed:
    - InputEventMouseButton → `_handle_mouse_button(event)`.
    - InputEventMouseMotion + drag_state != NONE → `_handle_mouse_drag(event)`.
    - InputEventKey + ESC → reset drag state, return true.
    - Else return false.
  - [ ] `_handle_mouse_button(mb)`:
    - LMB pressed → drag_state=PAINTING, _act_at(coord_under_mouse, false), return true.
    - LMB released → drag_state=NONE, _last_painted_coord=NO_COORD, return true.
    - RMB pressed → drag_state=ERASING, _act_at(coord_under_mouse, true), return true.
    - RMB released → drag_state=NONE, _last_painted_coord=NO_COORD, return true.
    - Other → return false.
  - [ ] `_handle_mouse_drag(mm)`:
    - coord = _grid.coord_under_mouse().
    - if coord == _last_painted_coord → return false.
    - _act_at(coord, _drag_state == DragState.ERASING).
    - return true.
  - [ ] `_act_at(coord, erase)`:
    - if `erase or _layers.is_erase()` → `_controller.erase_floor(coord)`.
    - else → проверить что selection это Dictionary, разобрать source_id+atlas, `_controller.paint_floor(coord, source_id, atlas)`.
    - В обоих случаях `_last_painted_coord = coord` в конце.
  - [ ] Проверка: `wc -l scripts/presentation/dev/editor/input_dispatcher.gd` — целевой 100-150 строк. AC14 soft cap = 150.

### Module 5: EditorController

- [ ] **T005.** Создать `scripts/presentation/dev/editor/editor_controller.gd`. См. [plan.md §Step 5](./plan.md):
  - [ ] `extends Node2D` (без class_name — controller не нужен другим как класс).
  - [ ] Const `MAPS_DIR := "res://data/maps/"`.
  - [ ] Const `GameLogger = preload("res://scripts/infrastructure/game_logger.gd")`.
  - [ ] Exports: `hex_grid_path`, `layers_panel_path`, `level_meta_panel_path`, `toast_layer_path` — все NodePath.
  - [ ] Поля: `_grid: HexGrid`, `_layers_panel: LayersPanel`, `_meta_panel: Node`, `_toast_layer: Node`, `_level: LevelData`, `_layers: LayersModel`, `_dispatcher: InputDispatcher`.
  - [ ] `_ready` в **строгом порядке** (R1 mitigation):
    1. `_resolve_nodes()` — get_node для каждого пути, типизация.
    2. `_level = LevelData.new()`.
    3. `_layers = LayersModel.new()` + `_layers.set_selection(LayersModel.LAYER_HEXES, _default_hex_selection())`.
    4. `_dispatcher = InputDispatcher.new(self, _grid, _layers)`.
    5. `_wire_panels()`.
    6. `_refresh_grid_from_level()`.
  - [ ] `_unhandled_input(event)` → `if _dispatcher.handle(event): get_viewport().set_input_as_handled()`.
  - [ ] Public API (вызывается ТОЛЬКО из InputDispatcher):
    - [ ] `paint_floor(coord, source_id, atlas_coord)`: `_grid.tile_map_layer.set_cell(coord, source_id, atlas_coord)` + `_set_or_update_floor_cell(coord, source_id, atlas_coord)`.
    - [ ] `erase_floor(coord)`: `_grid.tile_map_layer.set_cell(coord, -1)` + `_remove_floor_cell(coord)`.
  - [ ] `_default_hex_selection() -> Dictionary` — `{"source_id": 0, "atlas_coord": Vector2i.ZERO}` (первый тайл source 0 в hex_terrain.tres = grass).
  - [ ] `_wire_panels()`:
    - [ ] `_layers_panel.hex_palette_selection_changed.connect(_on_palette_selection)`.
    - [ ] `_meta_panel.save_requested.connect(_on_save)`.
    - [ ] `_meta_panel.load_requested.connect(_on_load)`.
    - [ ] `_meta_panel.exit_requested.connect(_on_exit)`.
    - [ ] `_meta_panel.playtest_requested.connect(_on_playtest_disabled)`.
    - [ ] `_meta_panel.name_changed.connect(_on_name_changed)`.
    - [ ] `if _meta_panel.has_method("setup"): _meta_panel.setup(self)`.
  - [ ] Slot методы:
    - [ ] `_on_palette_selection(value)` → `_layers.set_selection(LayersModel.LAYER_HEXES, value)`.
    - [ ] `_on_save()` → `LevelSerializer.save(_level, MAPS_DIR + _level.name + ".json")` + toast по результату.
    - [ ] `_on_load(path)` → `LevelSerializer.load_from(path)` → `_level = loaded` + `_meta_panel.set_level_name(_level.name)` + `_refresh_grid_from_level()` + toast.
    - [ ] `_on_exit()` → `change_scene_to_file("res://scenes/main_menu.tscn")`.
    - [ ] `_on_playtest_disabled()` → toast с loc-ключом `ui_level_editor_playtest_disabled_toast`.
    - [ ] `_on_name_changed(new_name)` → `_level.name = new_name`.
  - [ ] Internal helpers:
    - [ ] `_refresh_grid_from_level()`: `_grid.tile_map_layer.clear()` + цикл по `_level.floor_cells` с `set_cell`.
    - [ ] `_set_or_update_floor_cell(coord, source_id, atlas_coord)`: ищет в _level.floor_cells по coord, если нашёл — update, иначе append. Формат — `{"coord": Vector2i, "source_id": int, "atlas_coord": Vector2i}` (per LevelData line 49).
    - [ ] `_remove_floor_cell(coord)`: ищет по coord, remove_at если нашёл.
    - [ ] `_toast(text)`: `if _toast_layer != null and _toast_layer.has_method("show_toast"): _toast_layer.show_toast(text)` else `GameLogger.info("EditorController", text)`.
  - [ ] **AC13 hard cap проверка**: `wc -l scripts/presentation/dev/editor/editor_controller.gd` — должно быть ≤300. Если 280+ — surface как warning. Если >300 — STOP, finding в `findings.md`, extract `_on_save/_on_load/_refresh_grid_from_level` в `editor_io.gd` helper и продолжить.

### Module 6: Scene level_editor.tscn

- [ ] **T006.** Создать `scenes/dev/level_editor.tscn`. См. [plan.md §Step 6](./plan.md):
  - [ ] Структура (минимально, БЕЗ overlays):
    - LevelEditor (Node2D, script=editor_controller.gd) — exports на 4 NodePath'а.
    - BackgroundLayer (CanvasLayer) → Background (ColorRect, dark color, full rect).
    - EditorCamera (Camera2D, script=godmode_camera.gd — переиспользуем существующий).
    - HexGrid (instance hex_grid.tscn).
    - HUD (CanvasLayer):
      - LayersPanel (instance scenes/dev/editor/layers_panel.tscn). Anchors_preset=0, offset=(16, 60, 280, 320).
      - LevelMetaPanel (instance base_panel.tscn + script=level_meta_panel.gd). Anchors_preset=1 (top-right), панель в правом верхнем углу. **`persistence_scope_override = &"level_editor"`** (R2 mitigation).
      - ToastLayer (instance scenes/ui/toast_layer.tscn).
  - [ ] **Не добавлять**: ObjectsOverlay, SpawnersOverlay, WaveDiffOverlay, HoverHighlight, DeleteHighlight, PaintPreview, ConfirmModal, HotkeyOverlay, WaveTimeline, WavePanel, ObjectPalettePanel, FloorPalettePanel, ToolPanel, DialogueTriggerPanel — ничего из этого нет в скоупе 059.
  - [ ] LevelMetaPanel экспорты:
    - [ ] `panel_id = &"level_meta"`.
    - [ ] `panel_title_key = &"ui_level_meta_panel_title"`.
    - [ ] `panel_title_fallback = "Level Meta"`.
    - [ ] `min_panel_size = Vector2(280, 180)`.
    - [ ] `persistence_scope_override = &"level_editor"` — критично для R2.
  - [ ] Проверка: `cat scenes/dev/level_editor.tscn | grep -c "^\[node"` ≤ 8 (LevelEditor + BackgroundLayer + Background + EditorCamera + HexGrid + HUD + LayersPanel + LevelMetaPanel + ToastLayer = 9 максимум).
  - [ ] Открыть в Godot — нет parser errors.

### Module 7: Main menu wiring

- [ ] **T007.** Подключить кнопку «Level Editor (new)» в main menu. См. [plan.md §Step 7](./plan.md):
  - [ ] **`scenes/main_menu.tscn`** — добавить `LevelEditorNewButton` ПОСЛЕ `MapEditorButton` (строка 64), ДО `GameEditorButton` (строка 68):
    ```
    [node name="LevelEditorNewButton" type="Button" parent="VBox" unique_id=<новый>]
    layout_mode = 2
    text = "ui_main_menu_level_editor_new_button_text"
    ```
  - [ ] **`scripts/presentation/main_menu.gd`**:
    - [ ] `@onready var _level_editor_new_btn: Button = $VBox/LevelEditorNewButton` (рядом с line 46).
    - [ ] В `_ready()` около line 79 (где `_map_editor_btn.pressed.connect(_on_map_editor)`): добавить `_level_editor_new_btn.pressed.connect(_on_level_editor_new)`.
    - [ ] Новый метод рядом с `_on_map_editor` (line 224):
      ```gdscript
      func _on_level_editor_new() -> void:
          get_tree().change_scene_to_file("res://scenes/dev/level_editor.tscn")
      ```
    - [ ] **Surface**: проверить line ~112-141 main_menu.gd на наличие массива focus-handling кнопок. Если есть — добавить `_level_editor_new_btn` туда же. Если нет — пропускаем.
  - [ ] Проверка: открыть main_menu.tscn в Godot — кнопка появляется в VBox, текст рендерится через loc-ключ.

### Module 8: Localization

- [ ] **T008.** Добавить 4 loc-ключа. См. [plan.md §Step 8](./plan.md):
  - [ ] **Сначала проверить переиспользуется ли `ui_level_meta_panel_title`**: `grep "ui_level_meta_panel_title" data/localization/en.json scenes/dev/map_editor.tscn`. Если ключ уже есть — НЕ дублируем, используем как есть в level_editor.tscn. Если нет — добавляем.
  - [ ] Добавить недостающие ключи в **алфавитной** позиции в `data/localization/en.json` и `data/localization/ru.json`:
    - `ui_layers_panel_title` — en: `"Layers"`, ru: `"Слои"`.
    - `ui_level_editor_playtest_disabled_toast` — en: `"Playtest not yet wired in new editor — coming in spec 060"`, ru: `"Playtest пока не подключён в новом редакторе — будет в спеке 060"`.
    - `ui_level_meta_panel_title` (если его ещё нет) — en: `"Level Meta"`, ru: `"Свойства уровня"`.
    - `ui_main_menu_level_editor_new_button_text` — en: `"Level Editor (new)"`, ru: `"Редактор уровней (новый)"`.
  - [ ] Соответствующие записи в `data/localization/_sources.json` для каждого нового ключа: source = соответствующий .gd/.tscn файл, note = «added in spec 059».
  - [ ] Валидация: `python3 -c "import json; [json.load(open(f)) for f in ['data/localization/en.json', 'data/localization/ru.json', 'data/localization/_sources.json']]"` без ошибок.
  - [ ] Проверка: `grep -c "ui_level_editor_playtest_disabled_toast" data/localization/en.json data/localization/ru.json` = 1 в каждом.

### Smoke (manual в Godot)

- [ ] **T009.** Smoke: открытие сцены + UI базис (AC1, AC2, AC12).
  - [ ] **AC1.** Main menu → клик «Level Editor (new)» → сцена открывается без parser/runtime errors. Output чистый или с safe info-warning'ами.
  - [ ] **AC2.** В HUD виден LayersPanel слева сверху. В body — палитра тайлов (sources/atlases из hex_terrain.tres) + Erase кнопка в конце. LevelMetaPanel в правом верхнем с полем Name + 4 кнопки. ToastLayer есть (невидим пока тостов нет).
  - [ ] **AC12.** Назад в main menu (Exit или ESC если работает) → клик «Map Editor» → старый редактор открывается, panel'и в их позициях, drag/save/load/etc работает как до 059.

- [ ] **T010.** Smoke: paint/erase базис (AC3, AC4, AC5, AC8).
  - [ ] **AC3.** Click по tile-кнопке палитры → кнопка визуально активна (radio highlight). Click по другой → переключился. Click по Erase → активен Erase, тайлы deactive.
  - [ ] **AC4.** Выбрать первый тайл (grass). LMB-click на пустом гексе → тайл нарисовался. LMB на нём же → ничего не меняется (или перерисовывается тем же — оба ОК для thin slice). Выбрать другой тайл, LMB на залитом гексе → тайл сменился.
  - [ ] **AC5.** RMB-click на залитом гексе → тайл стёрся. RMB на пустом → ничего не происходит, нет toast.
  - [ ] **AC8.** Выбрать Erase. LMB-click на залитом гексе → тайл стёрся (Erase + LMB = erase). LMB-drag по тайлам → стираются один за другим.

- [ ] **T011.** Smoke: drag (AC6, AC7).
  - [ ] **AC6.** Выбрать тайл. LMB-down + drag по 5+ соседним гексам → каждый закрашивается. Удерживая LMB, вернуться курсором на уже закрашенный гекс → нет повторного triggering (anti-dup). Двинуть курсор на следующий → закрашивается.
  - [ ] **AC7.** RMB-down + drag по 5+ закрашенным гексам → стираются один за другим. Anti-dup аналогично.

- [ ] **T012.** Smoke: save / load / exit (AC9, AC10, AC11).
  - [ ] **AC9.** Закрасить пару гексов разными тайлами. В LevelMetaPanel поменять Name на `smoke_059`. Save → toast «Saved: …». Проверить `cat data/maps/smoke_059.json` — содержит `floor_cells` со списком наших тайлов (формат `{"coord": [x, y], "source_id": ..., "atlas_coord": [a, b]}`).
  - [ ] **AC10.** Стереть всё (или выйти и заново открыть редактор). Load (через FileDialog в LevelMetaPanel) → выбрать `smoke_059.json` → тайлы появляются на сетке в тех же позициях. Name в panel'е обновляется на `smoke_059`.
  - [ ] **AC11.** Exit → main menu открывается. Нет orphan'ов в memory (visual: панели из level_editor не висят на main menu).

- [ ] **T012a.** Smoke: persistence isolation (R2 проверка).
  - [ ] Открыть Level Editor → подвинуть LevelMetaPanel в новое место → Exit.
  - [ ] Открыть Map Editor → его LevelMetaPanel должен остаться на СВОЁМ привычном месте (не в позиции новой).
  - [ ] `cat user://layouts.cfg` (Linux: `~/.local/share/godot/app_userdata/<project>/layouts.cfg`) → должны быть ДВЕ секции: `[<level_editor>::level_meta]` (через persistence_scope_override) и `[<map_editor>::level_meta]`. Не пересекаются.
  - [ ] Если позиции пересеклись — R2 материализовался, finding в findings.md, проверить что `persistence_scope_override = &"level_editor"` действительно прописан в level_editor.tscn.

- [ ] **T013.** Smoke: structural caps (AC13, AC14).
  - [ ] **AC13.** `wc -l scripts/presentation/dev/editor/editor_controller.gd` ≤ 300.
  - [ ] **AC14a.** `wc -l scripts/presentation/dev/editor/input_dispatcher.gd` ≤ 200 (soft cap 150, finding если 150-200, fail если >200).
  - [ ] **AC14b.** `wc -l scripts/presentation/dev/editor/layers_model.gd` ≤ 150 (soft cap 100, finding если 100-150).

### Cleanup verification

- [ ] **T014.** Dead code grep + sanity:
  - [ ] `grep -rnE "MapEditorController|map_editor_controller" scripts/presentation/dev/editor/` пусто (новые файлы не должны ссылаться на старый controller).
  - [ ] `grep -rn "extends Node2D" scripts/presentation/dev/editor/` — только `editor_controller.gd` (1 hit).
  - [ ] `grep -rnE "TabbedBasePanel|tabbed_base_panel" scripts/presentation/dev/editor/ scenes/dev/editor/` пусто (per Q-059-6 flip — миграция в 060).
  - [ ] `grep -nE "preload.*editor_controller" scripts/presentation/dev/editor/input_dispatcher.gd scripts/presentation/dev/editor/layers_model.gd scripts/presentation/dev/editor/layers_panel.gd` пусто (`InputDispatcher._controller` untyped — circular avoidance).
  - [ ] Если что-то нашлось — finding.

### Findings

- [ ] **T015.** Если по ходу T001-T014 всплыли неожиданности (R1-R6 материализовались, EditorController не помещается, anti-dup семантика не та, paint работает за пределами сетки) — `specs/059-level-editor-architecture/findings.md` создаётся, в нём фиксируются проблемы с конкретикой и работающим work-around'ом. Если ничего не всплыло — finding файл не создаётся.

### Push + PR

- [ ] **T016.** Push ветки + PR. После всех T001-T015 done и smoke зелёный:
  - [ ] `git push -u origin andrey/059-level-editor-architecture` (ветка уже существует на origin, push отправит новые коммиты).
  - [ ] PR-creation URL: `https://github.com/TortikP/GameJamProject/compare/staging...andrey/059-level-editor-architecture?expand=1`.
  - [ ] PR title: `059 — Level Editor architecture from scratch (thin slice)`.
  - [ ] PR body: чек-лист AC1-AC14 с подтверждениями + ссылки на spec/plan/tasks + список новых файлов (~7 шт.: layers_model.gd, hex_tile_palette.gd, layers_panel.gd, layers_panel.tscn, input_dispatcher.gd, editor_controller.gd, level_editor.tscn) + список расширенных (3 шт.: main_menu.gd, main_menu.tscn, en/ru/_sources.json) + явное упоминание что миграция LayersPanel на TabbedBasePanel — работа 060.

## Open questions during impl

Если возникают новые вопросы по ходу T001-T014 — фиксируются как Q-059-N+ в `spec.md` §Resolved decisions с пометкой `OPEN`, спек паузится до резолва Андреем. Текущие закрытые Q-059-1..9 не пересматриваются без явного повода.

Особое внимание Q-059-6/7/8/9 — резолвлены мозгом. Андрей может пересмотреть на ревью PR (до старта T-задач или после smoke). Если иначе — план перерабатывается до T001.
