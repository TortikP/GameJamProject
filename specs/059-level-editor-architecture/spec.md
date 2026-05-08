# 059 — Level Editor: Architecture from Scratch (thin slice)

**Спек:** заложить новый Level Editor на чистом фундаменте — three-layer архитектура (presentation → editor-state → core), новый `EditorController` на ≤300 строк, без mode-enum'а — диспатч через `(active_layer, layer_selections)`. Тонкий вертикальный срез: палитра hexes → клик → тайл лежит в `LevelData` → save/load работают. **Никаких** объектов, спаунеров, волн, валидаций, undo, hover-overlay, eyedropper'а, 1-9 quick-select, Q/W/E смены слоёв. Старый `MapEditorController` параллельно живёт, удаляется в Spec 060.

**Обсуждали:** Андрей (идея, scope, hard cap по строкам), brain (декомпозиция на 4 модуля + thin-slice фокус).

## 1. Что строим (one-paragraph summary)

Новая сцена `scenes/dev/level_editor.tscn`, новый `editor_controller.gd` с тремя композиционными модулями (`LayersModel`, `InputDispatcher`, новый `LayersPanel` на `TabbedBasePanel` с одним табом «Hexes»), переиспользование существующего `level_meta_panel.gd` (на `BasePanel` после 057) для кнопок Save/Load/Exit. Новая кнопка «Level Editor (new)» в главном меню без feature-флагов. Жёсткий thin slice — только hex-painting через LMB/RMB drag/single-click, save/load через `LevelSerializer`. Архитектура заложена так, чтобы Spec 060 добавил `spawners` и `objects` слои через **add_tab()** на ту же `LayersPanel` без рефакторинга.

## 2. Проблема

`MapEditorController` (1551 строка) — джем-фундамент с пятью `Mode` состояниями, семью `set_mode_*` методами, размазанным `_placing_*` state и неявной priority chain (`spawner > object > floor`) на ПКМ. Каждая будущая фича (новый тип content, валидации, undo per layer) требует ad-hoc патчей в монолит. Параллельные ветки (объекты/спаунеры/палитры) переплетены так, что добавить, например, Erase как палитра-item невозможно без рефакторинга всех колл-сайтов `_clear_pending_delete()`.

Spec 055 пробовал инкрементную миграцию — провалилось по smoke. Решение из design.md §1: **полный re-do на новой ветке кода** с параллельной жизнью старого. Этот спек — фундамент: архитектура + минимально достаточный срез чтобы доказать, что фундамент выдерживает рисование тайлов.

## 3. Цель

- **AC1.** Новая сцена `scenes/dev/level_editor.tscn` открывается из main menu по кнопке «Level Editor (new)», рендерится без parser/runtime errors.
- **AC2.** В HUD виден `LayersPanel` (на `TabbedBasePanel`) с одним табом «Hexes». В body таба — палитра тайлов с `Erase`-item в конце.
- **AC3.** Click по tile-кнопке палитры → выбор тайла (radio-group, single-active, визуальный highlight на активной кнопке).
- **AC4.** LMB-click на гексе с выбранным non-erase tile → тайл рисуется на сетке. LMB на уже залитом гексе → перерисовывается на новый.
- **AC5.** RMB-click на гексе с тайлом → тайл стирается. RMB на пустом гексе → silent no-op (без toast).
- **AC6.** LMB-drag → paint по гексам под курсором, anti-dup на одной координате (не считается как новый paint, если курсор не покинул и вернулся на тот же coord без перехода через другой).
- **AC7.** RMB-drag → erase по гексам под курсором, anti-dup аналогично.
- **AC8.** Selection = `Erase` + LMB → стирает (поведение совпадает с RMB). Drag поддерживается.
- **AC9.** `LevelMetaPanel.save_requested` → запись `data/maps/<level_name>.json` через `LevelSerializer.save`. Файл на диске содержит `floor_cells` со списком текущих тайлов.
- **AC10.** `LevelMetaPanel.load_requested(path)` → загружает файл через `LevelSerializer.load_from`, сетка обновляется, тайлы видны.
- **AC11.** `LevelMetaPanel.exit_requested` → возвращает в main menu, состояние редактора чисто (`ActiveLevel.clear()`).
- **AC12.** Старый `scenes/dev/map_editor.tscn` продолжает открываться по кнопке «Map Editor» и работать как до 059 — никаких регрессий.
- **AC13.** `editor_controller.gd` ≤ **300 строк** (hard cap, Q-059-5). Если перевалит за 350 на имплементации — finding и сигнал на отдельный модуль.
- **AC14.** Структурные ограничения soft caps (Q-059-5): `input_dispatcher.gd` ~150, `layers_model.gd` ~100. Не блокеры, но если за 200/150 — finding.

## 4. Не-цели

Жёстко вне scope:

- **Объекты, спаунеры, волны.** Q-059-3 — thin slice. Слой только `hexes`. `LayersModel.set_selection(spawners, ...)` не существует в этом спеке — добавляется в 060.
- **Q/W/E/Tab keyboard смена слоёв.** Слой один — переключать нечего. В 060 после добавления второго таба — добавятся клавиши.
- **1-9 quick-select.** Нет shortcut'ов выбора item'а из палитры. Только мышь.
- **Eyedropper** (alt-click для выбора тайла под курсором). Не в скоупе.
- **HoverHighlight, paint preview, delete highlight.** Никаких пред-визуализаций жеста. Просто paint/erase сразу.
- **Undo/redo (`LevelHistory`).** Не подключается. Действия необратимы кроме «закрыть без save».
- **Validation.** Нет `LevelValidator`, save идёт с любым контентом. Эта работа — 062.
- **Wave UI / WavePanel.** В этом thin slice level — single-wave (`waves[0]`), редактор активной волны не показывается. Сетка отображает `floor_cells` базовой волны.
- **dialogue_triggers panel.** Не подключается.
- **Playtest button.** В meta panel она есть (общая для обоих редакторов), но в новом контроллере подключена к toast «Playtest пока не в новом редакторе — спек 060+». Не падает, не спавнит сцену.
- **Tile object placement, spawner placement, brush size > 1.** Кисть всегда 1 гекс.
- **Migration старого `__autosave__.json` или интеграция с любыми autosave'ами старого редактора.** Новый editor имеет свой autosave (см. §5.2 для F-059-? или Q ниже — TBD).
- **Удаление старого `MapEditorController` и `floor_palette_panel`.** Это работа 060.
- **Tear-off для одного-таба `LayersPanel`.** Технически работает (фреймворк 058 поддерживает), но в 1-tab случае это не имеет UX смысла. Не блокируем — просто не часть AC. На smoke не проверяем.

## 5. Структура изменений

### 5.1. Новые файлы

- `scenes/dev/level_editor.tscn` — корневая сцена нового редактора. Структура зеркалит `map_editor.tscn` минимально: `LevelEditor` (Node2D + script) → `EditorCamera` (Camera2D) → `HexGrid` (instance) → `HUD` (CanvasLayer) → `LayersPanel` (instance + script) + `LevelMetaPanel` (instance существующего) + `ToastLayer` (instance). Никаких overlay'ев (HoverHighlight/DeleteHighlight/PaintPreview/etc) — они вне скоупа.
- `scripts/presentation/dev/editor/editor_controller.gd` — новый главный контроллер. ≤300 строк (AC13). Owns `LevelData`, `LayersModel`, `InputDispatcher`, проводки сигналов от panels.
- `scripts/presentation/dev/editor/layers_model.gd` — `class_name LayersModel extends RefCounted`. Pure state holder: `active_layer: StringName`, `_selections: Dictionary[StringName, Variant]`. Методы `get_active_selection()`, `set_selection(layer, value)`, `is_erase()`. ~80-100 строк.
- `scripts/presentation/dev/editor/input_dispatcher.gd` — `class_name InputDispatcher extends RefCounted`. Принимает `EditorController + HexGrid + LayersModel` в конструкторе. Метод `handle(event) -> bool` — централизованный input pipeline. Внутри `DragState { NONE, PAINTING, ERASING }`, anti-dup `_last_painted_coord`. ~120-150 строк.
- `scripts/presentation/dev/editor/layers_panel.gd` — `class_name LayersPanel extends TabbedBasePanel`. Owns `HexTilePalette` (внутренний Control) для `hexes` таба. В 060 расширяется через `add_tab()` для `spawners` / `objects`. ~80 строк.
- `scenes/dev/editor/layers_panel.tscn` — Control composition вокруг `tabbed_base_panel.tscn` с прикреплённым `layers_panel.gd` script-override (паттерн из 057, как dev-панели). Tabs создаются runtime в `_ready` через `add_tab()` (per F-058-IMPL-1 — .tscn-decl half hybrid API не верифицирован).
- `scripts/presentation/dev/editor/hex_tile_palette.gd` — `class_name HexTilePalette extends VBoxContainer` (или GridContainer — TBD при имплементации). Создаётся `LayersPanel` и помещается в body таба `hexes` через `add_tab()`. Итерирует sources в `hex_terrain.tres`, генерирует Button-grid с TextureRect, добавляет `Erase`-item в конце. ButtonGroup для radio-mode. Сигнал `selection_changed(value: Variant)` (`{"source_id": int, "atlas_coord": Vector2i}` или `&"erase"`). ~100-130 строк.

### 5.2. Минимальные правки в существующих файлах

- `scenes/main_menu.tscn` — добавляется кнопка `LevelEditorNewButton` рядом с существующей `MapEditorButton`.
- `scripts/presentation/main_menu.gd` — `@onready var _level_editor_btn`, подписка `pressed.connect(_on_level_editor_new)`, метод `_on_level_editor_new()` → `change_scene_to_file("res://scenes/dev/level_editor.tscn")`. Добавляется в массив focus-handling кнопок (line ~112).
- `data/localization/en.json` + `ru.json` + `_sources.json` — новые ключи `ui_main_menu_level_editor_new_button_text` (en: «Level Editor (new)», ru: «Редактор уровней (новый)») и `ui_level_editor_playtest_disabled_toast` (en: «Playtest not yet wired in new editor — coming in spec 060», ru: «Playtest пока не подключён в новом редакторе — будет в спеке 060»).

### 5.3. Sequencing внутри `EditorController._ready()`

Жёсткий порядок (важен для отсутствия null-references):

1. `_resolve_nodes()` — экспортированные NodePath → конкретные ссылки.
2. `_level = LevelData.new()` — пустой level в памяти.
3. `_layers = LayersModel.new()` — defaults: `active_layer = &"hexes"`, selection = first tile в hex_terrain.tres source 0 atlas (0,0).
4. `_dispatcher = InputDispatcher.new(self, grid, _layers)` — wire зависимостей.
5. `_wire_panels()` — connect signals: `_layers_panel.hex_palette_selection_changed → _on_palette_selection_changed`, `_meta_panel.save_requested → _on_save_requested`, `_meta_panel.load_requested → _on_load_requested`, `_meta_panel.exit_requested → _on_exit_requested`, `_meta_panel.playtest_requested → _on_playtest_disabled_toast`, `_meta_panel.name_changed → _on_name_changed`.
6. `_refresh_grid_from_level()` — синхронизация `HexGrid.tile_map_layer` с `_level.floor_cells` (на пустом уровне — no-op).

Именно в этом порядке: `_layers` нужен `InputDispatcher`-у, `_dispatcher` нужен в `_input(event)`, `_wire_panels` зависит от `_layers` для default selection.

### 5.4. LayersPanel как `TabbedBasePanel` с одним табом

Архитектурное решение **Q-059-6 → TabbedBasePanel с 1 табом «Hexes»**. Альтернатива (BasePanel + ручной контент в body) была отвергнута: цена переезда на TabbedBasePanel в 060 — переписывание `LayersPanel`. Сейчас закладываем правильный фундамент.

Tear-off в 1-tab случае: технически работает (можно потащить таб «Hexes» вниз, появится detached panel; tab-bar главной покажет placeholder; reattach восстанавливает). UX в 1-tab — странно, но не сломано. На smoke 059 не проверяем — вне AC. В 060 при добавлении 2 ещё табов tear-off становится осмысленным.

Tabs создаются **runtime** в `LayersPanel._ready()` через `add_tab()` (F-058-IMPL-1: .tscn-declarative half hybrid API не верифицирован, runtime — единственный точно-работающий путь).

```gdscript
# layers_panel.gd
func _ready() -> void:
    super._ready()  # TabbedBasePanel._ready → super._ready (BasePanel) + _setup_tab_bar
    _add_hexes_tab()

func _add_hexes_tab() -> void:
    var palette := HexTilePalette.new()
    palette.selection_changed.connect(_on_hex_palette_selection_changed)
    add_tab(palette, &"hexes", &"", "Hexes")
```

### 5.5. InputDispatcher pipeline

Per design.md §5, упрощённый под thin slice:

```gdscript
# input_dispatcher.gd (skeleton)
enum DragState { NONE, PAINTING, ERASING }

var _drag_state: DragState = DragState.NONE
var _last_painted_coord: Vector2i = Vector2i(-99999, -99999)

func handle(event: InputEvent) -> bool:
    if event is InputEventMouseButton:
        return _handle_mouse_button(event)
    if event is InputEventMouseMotion and _drag_state != DragState.NONE:
        return _handle_mouse_drag(event)
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        _drag_state = DragState.NONE
        return true
    return false
```

`_handle_mouse_button`:
- LMB press на coord → `_drag_state = PAINTING`, paint(coord).
- LMB release → `_drag_state = NONE`, reset `_last_painted_coord`.
- RMB press → `_drag_state = ERASING`, erase(coord).
- RMB release → `_drag_state = NONE`, reset.

Anti-dup: при painting/erasing — если `coord == _last_painted_coord` → skip; иначе paint/erase + `_last_painted_coord = coord`.

Selection = `&"erase"` + LMB → ведёт себя как RMB (erase path). Реализовано как ветка в `_paint_floor`:
```gdscript
func _paint_floor(coord: Vector2i) -> void:
    var sel = _layers.get_active_selection()
    if typeof(sel) == TYPE_STRING_NAME and StringName(sel) == &"erase":
        _controller.erase_floor(coord)
        return
    var d := sel as Dictionary
    _controller.paint_floor(coord, d["source_id"], d["atlas_coord"])
```

### 5.6. EditorController public surface

Минимальное API, вызываемое из InputDispatcher:

```gdscript
# editor_controller.gd
func paint_floor(coord: Vector2i, source_id: int, atlas: Vector2i) -> void
func erase_floor(coord: Vector2i) -> void
```

Эти два метода + signal handlers для panels — единственная public-ish поверхность. Никаких других методов наружу не торчит.

## 6. Acceptance criteria

См. §3 (AC1-AC14, инлайн с целями для удобства ревью). Smoke прогон делается через `tasks.md` T-задачи. AC11 (no regressions in old map_editor) проверяется отдельным запуском старого редактора и базовым smoke (drag panel, paint floor, save/load).

## 7. Findings (для других)

- **F-059-1 (для Алексея, Сергея, Никиты, Стасяна):** до конца Spec 060 параллельно живут **два** редактора. Старый «Map Editor» — для авторских задач (объекты, спаунеры, волны, диалоги). Новый «Level Editor (new)» — пока **только** для тестирования архитектуры (рисование тайлов). Не использовать для реальной работы до Spec 060.
- **F-059-2 (для Никиты):** existing `data/maps/*.json` файлы открываются в новом редакторе через Load (через `LevelSerializer.load_from` — общий на оба редактора). Но новый редактор не показывает / не редактирует объекты, спаунеры, волны — они в `LevelData` сохраняются как есть, проходят сквозь save/load roundtrip без изменений. Это safe — никаких данных не теряется.
- **F-059-3 (для Андрея):** структура каталогов — новые модули в `scripts/presentation/dev/editor/` (subfolder), отделено от старых `scripts/presentation/dev/*.gd`. После Spec 060 (удаление `MapEditorController` + старых palette files) — рассмотреть переезд оставшегося dev-кода в `editor/` или возврат всего на верхний уровень. Не решаем сейчас.
- **F-059-4 (для Стасяна):** SCHEMA_VERSION остаётся 2. Новых полей не добавляется. Bump до 3 — работа Spec 061 (waves data расширение).
- **F-059-5 (для всех):** `LevelMetaPanel.playtest_requested` в новом редакторе подключена к toast'у «Playtest not yet wired in new editor — coming in spec 060». Кнопка на panel не disabled (это сложно — общий panel на оба редактора), но клик не падает.
- **F-059-6 (потенциальный для будущего):** `HexTilePalette` рендерится как простой grid с Button + TextureRect. Если в команде кто-то захочет real-time preview на наведение / drag-and-drop тайлов / подписи — это полировка после Spec 060.

## 8. Resolved decisions (T-059-* / Q-059-*)

Из чата с Андреем + резолв в spec'е:

- **Q-059-1 (резолвлено в чате до спека).** Полный re-do на новой ветке кода. Старый `MapEditorController` — параллельная жизнь до Spec 060.
- **Q-059-2 → A.** Новая сцена `scenes/dev/level_editor.tscn`. Старый `map_editor.tscn` живёт нетронутый. Удаление обоих (старого) — в Spec 060.
- **Q-059-3 → thin slice.** Только `hexes` слой, LMB-paint / RMB-erase / single+drag, save/load. **Без**: undo, HoverHighlight, paint preview, 1-9, eyedropper, Q/W/E/Tab, объектов, спаунеров, волн, валидаций. Это явный набор «нет» — фиксирован, не пересматривается без явного повода.
- **Q-059-4 → no debug flags.** Кнопки «Map Editor» и «Level Editor (new)» в main menu — **обе видны всегда**, без debug/feature флагов. Никита/Стасян могут переключаться в любой момент, F-059-1 предупреждает использовать новый только для тестов.
- **Q-059-5 → 300 строк hard cap на `editor_controller.gd`.** Soft caps: `input_dispatcher.gd` ~150, `layers_model.gd` ~100. AC13/AC14 это формализуют. Если на имплементации упирается в cap — finding + сигнал на доп модуль (например, выделение `LevelIO` для save/load).
- **Q-059-6 → TabbedBasePanel с 1 табом «Hexes» для LayersPanel.** Альтернатива (BasePanel в этом спеке + миграция в 060) отвергнута — переписывать LayersPanel дороже чем нести 1-tab «странность» (которая на UX незаметна, потому что 1-tab — это нормальный sub-case TabbedBasePanel). Резолвлено мозгом, может быть пересмотрено на ревью PR.
- **Q-059-7 → переиспользовать существующий `level_meta_panel.gd`.** Не создаём новую meta-panel. Существующая (после 057 на BasePanel) — общая для обоих редакторов. Новый контроллер подписывается на её сигналы (`save_requested`, `load_requested`, `exit_requested`, `playtest_requested`, `name_changed`). `playtest_requested` в новом — toast «coming in 060». Резолвлено мозгом.
- **Q-059-8 → HexTilePalette итерирует sources в hex_terrain.tres + Erase в конце.** При `_ready` HexTilePalette: `for src_id in tile_set.get_source_count()` → `var src := tile_set.get_source(src_id) as TileSetAtlasSource` → `for atlas_coord in src.get_tiles_count()`-iterate коллекцию. Кнопка с TextureRect (atlas region). В конце добавляется `Erase` Button с иконкой/текстом. Все Buttons в одной ButtonGroup. Конкретный layout (GridContainer 4-wide или VBox или HFlowContainer) — решается при имплементации. Резолвлено мозгом.
- **Q-059-9 → anti-dup через `_last_painted_coord` в InputDispatcher.** Простой и достаточный для thin slice. Сбрасывается на release. Альтернатива (Set<Vector2i> всех закрашенных в текущем drag'е) — overkill для thin slice; пересмотрим если на 060 anti-dup потребует более сложной семантики.

Открытые decisions, которые **не блокируют start спека** но должны разрешиться к 060:

- **Q-059-10 (на 060):** autosave для нового редактора. Сейчас в thin slice — нет. На 060 при добавлении объектов/спаунеров — нужен ли свой `__autosave__.json`, или общий со старым редактором (последний сохранивший побеждает)? Surface как finding на конец 059 / start 060.
- **Q-059-11 (на 060):** Q/W/E клавиши — нужны ли явный shortcut'ы или только клик по табу LayersPanel? Design.md §4 предлагает оба. На 060 при добавлении табов будут реализованы.

## 9. Out of scope

- Любые правки `LevelData` / `LevelSerializer` / `LevelLoader` / `HexGrid` — используем как есть.
- Любые правки `BasePanel` / `TabbedBasePanel` / `PanelTabBar` — фреймворк 058 как есть.
- Любые правки старых dev-файлов (`map_editor_controller.gd`, `floor_palette_panel.gd`, `object_palette_panel.gd`, `tool_panel.gd`, `dialogue_trigger_panel.gd`, `wave_panel.gd`, etc.) — параллельная жизнь, не трогаем. Исключение — `level_meta_panel.gd` если для подключения playtest-toast потребуется сделать его поведение conditional (TBD, finding если так).
- Удаление чего-либо. Все удаления — Spec 060.
- Любое содержимое второго / третьего таба `LayersPanel` (`spawners`, `objects`) — Spec 060.
- Полноценный smoke параллельной жизни старого редактора — простой запуск + ручной paint/save сэмплом достаточно.

## 10. Dependency / sequencing

- Зависит от **Spec 058** (TabbedBasePanel). Если 058 не merge'нут в staging до старта 059 — блокер. На момент написания спека: 058 в финальном смоук-стадии.
- **Не зависит** от других in-progress спек. Не блокируется ничем кроме 058.
- **Разблокирует Spec 060** (level-editor: layers + palettes + delete old MapEditorController).
- После merge 059 в staging — review pause перед стартом 060 per `docs/workflow.md`. Если на 059 имплементации обнаружились проблемы фундамента (например, EditorController не помещается в 300 строк, или TabbedBasePanel в 1-tab случае ломает UX) — это окно чтобы доработать 059 до старта 060.
- Параллельная жизнь старого `MapEditorController` обязательна до конца Spec 060 (design.md §8 — «Никита может продолжать авторство»).
