# 060 — Level Editor: Layers + Palettes + Delete Legacy

**Спек:** доращивание thin slice'а из 059 до полного редактора — три слоя (`hexes` / `spawners` / `objects`) с палитрами и per-layer paint/erase, миграция `LayersPanel` на `TabbedBasePanel`, keyboard shortcuts (Q/W/E/Tab/1-9), Shift+RMB cascade, delete-flash, HELP modal, autosave, hex_grid.tscn fix, и **полное удаление** старого `MapEditorController` + всех его панелей и сцены. Все cross-refs (main_menu, game_editor, pause_menu, godmode_input) переключаются на `level_editor.tscn`.

**Обсуждали:** Андрей (идея, scope, отвечал на 13 Q-060-* в Clarify), brain (декомпозиция, выявление импликаций удаления legacy, проработка Q-060-1..13).

## 1. Что строим (one-paragraph summary)

Расширяем `LayersModel` до трёх слоёв с per-layer selection schemas (хексы / спаунеры / объекты), мигрируем `LayersPanel` с плоского `BasePanel` на `TabbedBasePanel` с тремя табами, добавляем `SpawnerPalette` и `ObjectPalette` (новые `VBoxContainer`'ы по паттерну `HexTilePalette`), расширяем `InputDispatcher` per-layer dispatch'ем + keyboard handling (Q/W/E/Tab forward only, 1-9 quick-select, Shift+RMB cascade), выносим save/load/autosave/grid-sync из `EditorController` в отдельный `editor_io.gd` чтобы остаться в hard cap 300 строк, добавляем `delete_flash` (короткий красный pulse на гексе при erase), переписываем `hotkey_overlay` под новые шорткаты как `editor_help_modal`, патчим `PanelTabBar` сигналом `active_tab_changed(tab_id)` (одна правка ui-panels framework), вычищаем все cross-refs на `map_editor.tscn` в пользу `level_editor.tscn`, исправляем `hex_grid.tscn` binding format (F-059-IMPL-4) и убираем workaround в `EditorController._ready`, и удаляем старый редактор атомарно: `map_editor.tscn`, `map_editor_controller.gd` (1551 строк), `floor_palette_panel.gd`, `object_palette_panel.gd`, `tool_panel.gd`, `paint_preview.gd`, `wave_panel.gd`, `wave_diff_overlay.gd`, `dialogue_trigger_panel.gd`, `hotkey_overlay.gd`, `delete_highlight.gd`, `level_history.gd` — суммарно ~3700 строк legacy. После 060 единственный путь редактирования карт — новый level editor.

## 2. Проблема

После 059 в репо живут два редактора в параллель. Это создаёт несколько проблем:

- **Cognitive load.** Контентщики видят две кнопки в main menu, не знают какая работает. F-059-1 явно говорит «не использовать новый для реальной работы» — то есть юзеры заперты в legacy с известной кучей багов и архитектурным джем-долгом (1551 строка в одном контроллере, mode enum, размазанный _placing_* state).
- **3700 строк legacy** висят в репо как dead-but-active code. Любая правка cross-cutting инфраструктуры (BasePanel, LevelData, EventBus) требует тестирования на обоих редакторах. PR-чекинг распухает.
- **Cross-refs.** `game_editor_controller.gd`, `pause_menu.gd`, `godmode_input.gd` ходят на `map_editor.tscn`. Пока не починим — Game Editor → Map Editor → Playtest → Back to Editor цикл проходит через старый редактор, минуя новый.
- **Никто не работает с картами в этом окне.** Никита и Стасян переключены на другие задачи (диалоги/баланс), Андрей не блокирует себя на wave editing. Это **окно, когда удалить старый редактор безопасно** — никаких прерванных Никитиных черновиков, никаких многоволновых правок в полёте.

059 был thin slice — фундамент. 060 — момент когда фундамент берёт нагрузку всего редактора, и legacy уезжает.

## 3. Цель

### A. Layer model + palettes

- **AC1.** `LayersModel` поддерживает три слоя: `LAYER_HEXES`, `LAYER_SPAWNERS`, `LAYER_OBJECTS`. `active_layer` переключается через API, восстанавливая previous selection слоя из `_selections`.
- **AC2.** `LayersPanel` extends `TabbedBasePanel`. В `_ready` после `super._ready()` добавляется три таба через `add_tab()`: `&"hexes"` (HexTilePalette), `&"spawners"` (SpawnerPalette), `&"objects"` (ObjectPalette). `HexTilePalette` переезжает в первый таб без правок класса.
- **AC3.** `PanelTabBar` (ui-panels framework) эмитит `active_tab_changed(tab_id: StringName)` при пользовательском клике на таб. `TabbedBasePanel` re-emit'ит как одноимённый сигнал. `LayersPanel` подписывается и дёргает `LayersModel.active_layer = tab_id` + сигналит контроллер для refresh overlays.
- **AC4.** `SpawnerPalette extends VBoxContainer` итерирует `data/enemies/*.json` через `EnemyRegistry` (или прямой scan, см. plan) + добавляет hardcoded Player entry. Кнопки в одной `ButtonGroup`, иконка из `data/enemies/<id>.json` portrait. Эмитит `selection_changed(value: Variant)` где value = `{"kind": StringName, "ref": StringName}` (player → `kind=&"player", ref=&""`; enemy → `kind=&"enemy", ref=enemy_id`).
- **AC5.** `ObjectPalette extends VBoxContainer` итерирует `TileObjectRegistry.new()` (читает `data/tile_objects/*.json`). Кнопки в `ButtonGroup`, иконка из `TileObject.icon` или `sprite`. Эмитит `selection_changed(value: Variant)` где value = `{"object_id": StringName}`. Без табов Obstacles/Interactive (упрощение от старой ObjectPalettePanel — design.md §4 «без разделения»).
- **AC6.** Каждая палитра имеет свой `ButtonGroup`. Выбор спаунера НЕ деактивирует выбор тайла в hexes-таб'е — selection per-layer независим. Smoke-тест: hexes → tile A → W (spawners) → spawner X → Q (hexes) → tile A всё ещё подсвечен. (Q-060-3.)

### B. Per-layer mouse dispatch

- **AC7.** LMB на гексе с active=`hexes` ведёт себя как в 059: рисует tile если selection != erase, иначе erase. (Регресс 059'ного поведения недопустим.)
- **AC8.** LMB на гексе с active=`spawners` ставит спаунер на coord. Player spawner uniqueness: если ставится `kind=&"player"` — старый player spawner удаляется (на любом coord). Enemy spawner — duplicate-allowed (можно поставить два slime'а на разные клетки). Если на coord уже есть spawner текущего типа — replace (тот же coord = новые kind/ref).
- **AC9.** LMB на гексе с active=`objects` ставит объект. На coord может быть только один объект; если уже есть — replace. (Spawners и objects на одном coord — допустимо, design.md §4 «объекты в воздухе допустимы».)
- **AC10.** RMB на гексе с active=`hexes` стирает тайл (поведение 059). RMB с active=`spawners` удаляет spawner на coord (если есть). RMB с active=`objects` удаляет объект на coord (если есть). Drag-RMB продолжает per-layer erase. На coord без relevant entity — silent no-op (без toast).
- **AC11.** Shift+RMB на гексе — cascade: одной операцией удаляет всё на coord (tile + objects + spawners) **независимо от active layer**. Не требует подтверждения, выполняется immediately. Без undo (Q-060-6 принят пользователем).

### C. Keyboard shortcuts

- **AC12.** `Q` → active=`hexes`, `W` → active=`spawners`, `E` → active=`objects` (прямой выбор). Tab strip визуально отражает переключение, активная палитра показывается. **Не работают** если фокус на `LineEdit`/`TextEdit`/`SpinBox` (стандартный focus traversal — handle через `_unhandled_input`, focused control съест event первым).
- **AC13.** `Tab` циклически переключает слой forward (hexes → spawners → objects → hexes). Reverse (Shift+Tab) **не реализуется** — Q-060-5 явно «только в одну сторону». Не работает если фокус в текстовом поле (см. AC12).
- **AC14.** `1`-`9` выбирают N-ый button палитры активного слоя (1-indexed). Кнопки 10+ недоступны через цифры. На первых 9 кнопках активной палитры рисуется подпись цифры в углу (`Label` overlay через `add_child`, mouse_filter=IGNORE). Палитры неактивных слоёв скрыты (TabbedBasePanel) — их подписи цифр не видны.
- **AC15.** `Esc` сбрасывает текущий drag (`_drag_state = NONE`) — поведение 059. Не закрывает редактор.
- **AC16.** `?` или `F1` открывает HELP modal со списком всех шорткатов (см. AC23).

### D. Visual feedback

- **AC17.** `delete_flash`: при каждом успешном erase (LMB+erase, RMB, cascade) на удалённой клетке проигрывается короткий красный pulse ~150ms. Реализуется как `Node2D` overlay child of HexGrid с `_draw()` методом, fade-out через `Tween` в `modulate.a`. Один Node на flash, освобождается через `queue_free()` по завершении tween. Для cascade — один flash на coord (не три отдельных за tile/objects/spawners).
- **AC18.** Hover highlight (`hover_highlight.gd`, был добавлен в 059 через F-059-IMPL-2) продолжает работать без изменений — показывает hex под курсором.
- **AC19.** Нет persistent delete-overlay (старый `delete_highlight.gd` был такой). Flash достаточен как feedback на действие.

### E. Autosave + restore

- **AC20.** При каждом мутирующем действии (paint/erase/cascade) запускается debounce-таймер 1.5s. По истечении — `editor_io.gd` пишет `_level` в `res://data/maps/__autosave__.json`. Debounce сбрасывается на каждом новом действии.
- **AC21.** В `EditorController._ready` (через `editor_io.check_autosave()`) — если `__autosave__.json` существует и младше 24h: открывается `ConfirmModal` «Restore unsaved work from N minutes ago?». Yes → загрузить файл, имя установить в `_level.name` (с пометкой что это restore — конкретика в plan). No → удалить файл. Старше 24h — silent delete + start fresh.
- **AC22.** Файл общий со старым (Q-060-9) — `__autosave__.json`. Раз старого редактора больше нет — конфликта нет.

### F. HELP modal

- **AC23.** Новый класс `EditorHelpModal extends BasePanel` (или наследник `BasePanel`-a с modal-flag — точное решение в plan). Показывает таблицу шорткатов: Q/W/E/Tab/1-9/RMB/Shift+RMB/Esc/F1/Ctrl+S/Ctrl+L. Hard-coded локализованный список — никакого dynamic discovery (overengineering для 060).
- **AC24.** Открывается по `?` или `F1`. Закрывается тем же ключом или Esc. Pause-game-while-open не нужен (редактор не в pause-state).

### G. Удаление legacy + cross-refs

- **AC25.** Удалены файлы (атомарно в одном PR, один коммит на git rm для трассируемости):
  - `scenes/dev/map_editor.tscn`
  - `scripts/presentation/dev/map_editor_controller.gd`
  - `scripts/presentation/dev/floor_palette_panel.gd`
  - `scripts/presentation/dev/object_palette_panel.gd`
  - `scripts/presentation/dev/tool_panel.gd`
  - `scripts/presentation/dev/paint_preview.gd`
  - `scripts/presentation/dev/wave_panel.gd`
  - `scripts/presentation/dev/wave_diff_overlay.gd`
  - `scripts/presentation/dev/dialogue_trigger_panel.gd`
  - `scripts/presentation/dev/hotkey_overlay.gd`
  - `scripts/presentation/dev/delete_highlight.gd`
  - `scripts/presentation/dev/level_history.gd`
- **AC26.** **НЕ удаляются** (используются новым редактором):
  - `scripts/presentation/dev/objects_overlay.gd` — рендер объектов на сетке, переподключается к новому EditorController.
  - `scripts/presentation/dev/spawners_overlay.gd` — рендер спаунеров.
  - `scripts/presentation/dev/hover_highlight.gd` — hover indicator (с 059).
  - `scripts/presentation/dev/level_meta_panel.gd` — общий, остаётся как был.
  - Все *_smoke_controller.gd — отдельные смоук-сцены, не трогаем.
- **AC27.** Cross-refs обновлены:
  - `scripts/presentation/main_menu.gd`: убрана кнопка `MapEditorButton` + handler `_on_map_editor`. Кнопка `LevelEditorNewButton` переименована в `LevelEditorButton`, текст «Level Editor» (без «(new)»). Соответствующий loc-key обновлён.
  - `scenes/main_menu.tscn`: удалён node `MapEditorButton`, переименован `LevelEditorNewButton` → `LevelEditorButton`, обновлены текст и unique_id если нужно.
  - `scripts/presentation/dev/game_editor_controller.gd`: `change_scene_to_file("res://scenes/dev/map_editor.tscn")` → `level_editor.tscn`.
  - `scripts/presentation/pause_menu.gd`: то же самое в `_on_back_to_editor`.
  - `scripts/presentation/godmode/godmode_input.gd`: то же самое в back-to-editor branch.
  - Любые orphan loc-keys из удалённых файлов (`ui_map_editor_*`, `ui_object_palette_*`, `ui_floor_palette_*` — тех что не реюзаются) — почищены из `data/localization/{en,ru}.json`.

### H. Game Editor → Level Editor handoff

- **AC28.** Когда `game_editor_controller.gd` вызывает `ActiveLevel.queue(map_path)` + `ActiveGame.queue_for_editor(save_path)` + `change_scene_to_file(level_editor.tscn)` — новый редактор в `_ready` дёргает `ActiveLevel.has_queued()` → `ActiveLevel.consume()` → `editor_io.load_from(path)`. Вход с конкретной картой работает.
- **AC29.** Кнопка Exit в `LevelMetaPanel` редиректит обратно в Game Editor если `ActiveGame.has_queued_for_editor()`, иначе main menu. Логика 1:1 с `_on_exit_requested` старого MapEditorController:1091-1107.

### I. Playtest + back-to-editor цикл

- **AC30.** Кнопка Playtest в `LevelMetaPanel` пишет `_level` в `__playtest__.json`, вызывает `ActiveLevel.mark_playtest(__playtest__.json)` + `ActiveLevel.queue(__playtest__.json)`, переходит на `godmode.tscn`. Логика 1:1 с `_on_playtest_requested` старого:1076-1088. **Toast «coming in 060»** из 059 (`_on_playtest_disabled`) удаляется, заменяется на функциональный handler.
- **AC31.** В godmode при ESC → Pause → Back to Editor → возвращает на `level_editor.tscn`, который при `_ready` подгружает `ActiveLevel.get_playtest_origin()` через `consume()`. Пользователь видит ту же карту что и до Playtest (с теми же изменениями — `__playtest__.json` уже содержит последнее состояние).

### J. F-059-IMPL-4 cleanup

- **AC32.** `scenes/arena/hex_grid.tscn` пересохранён в формат, который Godot 4 корректно резолвит для типизированных `@export TileMapLayer` полей. Workaround в `EditorController._ready` (`_grid.tile_map_layer = _grid.get_node_or_null("Terrain") as TileMapLayer` и аналогичный для `vfx_overlay`) удалён. Сцена `level_editor.tscn` грузится без error логов про «tile_map_layer is null». Старая сцена `godmode.tscn` тоже не регрессирует.

### K. Hard caps + structure

- **AC33.** `editor_controller.gd` ≤ **300 строк** (наследуется от 059 hard cap). Если превышает — finding и пересмотр extraction strategy.
- **AC34.** `editor_io.gd` ≤ **200 строк** (новый soft cap). Содержит save/load/autosave/grid-sync.
- **AC35.** `input_dispatcher.gd` ≤ **220 строк** (новый soft cap, поднят с 059'ных 150 потому что добавляется keyboard + per-layer dispatch + cascade).
- **AC36.** `layers_model.gd` ≤ **120 строк** (поднят с 059'ных 100).

### L. Multi-wave maps

- **AC37.** Если загруженная карта имеет `_level.waves.size() > 1` — toast при load «Multi-wave map (N waves) loaded. Editing affects wave 0 only — full wave editor coming in 061.» (severity warn, duration 4s). Save folds wave 0 обратно в `waves[0]`, остальные waves сохраняются roundtrip. Это **не** read-only mode (Q-060-11 склонился к (b) через ответ Андрея «Никита не работает с картами»).

## 4. Не-цели

Жёстко вне scope этого спека:

- **Wave UI / settings panel.** Это Spec 061. Активная wave в редакторе 060 — всегда `waves[0]`, переключение волн отсутствует.
- **dialogue_triggers panel.** Удаляется в 060, заново в 061 (с cleanup OQ-2). Между мерджами 060 и 061 редактирования диалог-триггеров через UI нет.
- **LevelData schema bump.** Остаётся на v2. v3 — Spec 061 (wave + spawner extensions per design.md §7).
- **Validation pipeline.** Spec 062. В 060 save проходит без проверок (как в 059).
- **Wave timeline UI.** Spec 063.
- **Undo/redo.** `level_history.gd` удаляется. Cascade без подтверждения и без recovery — Q-060-6 явно принят.
- **Eyedropper (Alt+click).** Не в скоупе, как и в 059.
- **Brush size > 1.** Кисть всегда 1 гекс.
- **Multi-select / box-select.** Design.md §11.
- **Drag-and-drop переупорядочивание палитр.** Кнопки в той же последовательности как итерация source.
- **Music editor.** Design.md §11.
- **Layout presets / persistence пользовательских раскладок.** Уже есть базовый persistence от BasePanel (058), не расширяем.
- **Tab tear-off в `LayersPanel`.** Технически возможен (058 фича), но скоуп 060 не включает explicit testing tear-off для редактора. Если случайно работает — bonus, не AC.
- **`tab_changed` UX-полировка** (анимация переключения, transition effects).
- **Hover preview объектов** (показывать silhouette объекта под курсором перед placement). Возможный future-полишинг — не сейчас.
- **Per-layer settings** (например, layer opacity, layer lock). YAGNI до запроса.

## 5. Структура изменений

### 5.1. Новые файлы

- `scripts/presentation/dev/editor/editor_io.gd` — extract save/load/autosave/grid-sync из EditorController. `class_name EditorIO extends RefCounted`. Конструктор `_init(controller, grid, level_provider)`. Методы:
  - `save(level: LevelData) -> bool`
  - `load_from(path: String) -> LevelData` (returns null on failure, controller обрабатывает toast)
  - `enqueue_autosave()` — debounce 1.5s, пишет в `__autosave__.json`
  - `check_autosave_on_ready() -> bool` — return true если был prompt'нут restore
  - `refresh_grid_from_level(level)` — sync TileMapLayer + overlays
  - `clear_autosave()` — на success-save
  - ≤ 200 строк (AC34).
- `scripts/presentation/dev/editor/spawner_palette.gd` — `class_name SpawnerPalette extends VBoxContainer`. Паттерн HexTilePalette: HFlowContainer с buttons, ButtonGroup для radio-mode, `selection_changed(value: Dictionary)`. Источник — `data/enemies/*.json` + Player entry.
- `scripts/presentation/dev/editor/object_palette.gd` — `class_name ObjectPalette extends VBoxContainer`. Аналог SpawnerPalette. Источник — `TileObjectRegistry.new()`. Без табов Obstacles/Interactive (упрощение).
- `scripts/presentation/dev/editor/delete_flash.gd` — `class_name DeleteFlash extends Node2D`. `_draw()` рисует красный hex polygon через `HexGeometry.flat_top_polygon()`. Tween в `modulate.a` 1→0 за 150ms, на finish — `queue_free()`. Один статический метод `DeleteFlash.spawn_at(parent: Node, coord: Vector2i, hex_grid: HexGrid)` для удобства вызова.
- `scripts/presentation/dev/editor/editor_help_modal.gd` — `class_name EditorHelpModal extends BasePanel` (или CenteredBasePanel — выбор в plan). Hard-coded таблица шорткатов с loc-keys. Открывается через `show()` / `hide()`.
- `scenes/dev/editor/spawner_palette.tscn` — wrapper для SpawnerPalette если нужен (palette может быть pure-script Control без .tscn — решается в plan).
- `scenes/dev/editor/object_palette.tscn` — аналогично.
- `scenes/dev/editor/editor_help_modal.tscn` — composition вокруг base_panel.tscn с прикреплённым editor_help_modal.gd.

### 5.2. Изменённые файлы

- `scripts/presentation/dev/editor/layers_model.gd` — расширение:
  - `const LAYER_SPAWNERS := &"spawners"`, `const LAYER_OBJECTS := &"objects"`.
  - Initial defaults в `_selections` для всех трёх слоёв.
  - Метод `cycle_active_layer_forward()` для Tab handler.
  - Метод-helpers `is_active_hex_selection_dict() -> bool` и т.п. для упрощения dispatch.
  - ≤ 120 строк (AC36).
- `scripts/presentation/dev/editor/input_dispatcher.gd` — расширение:
  - Per-layer dispatch в `_act_at`: `match _layers.active_layer:` → hexes (как 059) / spawners (paint_spawner / erase_spawner) / objects.
  - Keyboard handling в `handle()`: KEY_Q/W/E/TAB → `_layers.set_active(...)` + signal; KEY_1..9 → `_quick_select(n)`; KEY_F1/QUESTION → emit help_requested; KEY_SHIFT+RMB → cascade.
  - Focus check: `if _is_text_focus_active(): return false` для keyboard events. Проверяет `get_viewport().gui_get_focus_owner()` is `LineEdit`/`TextEdit`/`SpinBox`.
  - Cascade: `_controller.cascade_at(coord)` — отдельный метод, removes tile + all objects on coord + all spawners on coord. Один `delete_flash` на coord.
  - ≤ 220 строк (AC35).
- `scripts/presentation/dev/editor/layers_panel.gd` — миграция `extends BasePanel` → `extends TabbedBasePanel`:
  - В `_ready` после `super._ready()`: `add_tab(HexTilePalette.new(), &"hexes", &"ui_layers_panel_tab_hexes", "Hexes")` + аналог для spawners/objects.
  - Re-emit `selection_changed` сигналов всех трёх палитр в один: `layer_selection_changed(layer_id: StringName, value: Variant)`.
  - Подписка на `_tab_bar.active_tab_changed` (AC3) → re-emit как `active_tab_changed(tab_id)`.
- `scripts/presentation/dev/editor/editor_controller.gd` — расширение под три слоя:
  - Resolve overlays (`_objects_overlay`, `_spawners_overlay`) из новой scene structure.
  - Public API: `paint_floor` (есть) + `erase_floor` (есть) + `paint_object(coord, object_id)` + `erase_object(coord)` + `paint_spawner(coord, kind, ref)` + `erase_spawner(coord)` + `cascade_at(coord)` + `set_active_layer(layer_id)`.
  - Slot handlers расширены: `_on_layer_selection_changed(layer_id, value)`, `_on_active_tab_changed(tab_id)`, `_on_help_requested`.
  - Save/load/autosave вызовы делегируются в `_io: EditorIO`.
  - `_refresh_grid_from_level` уезжает в io.
  - Mutation methods для floor/object/spawner — каждый ~10-15 строк, обновляют `_level.<field>` и dispatch'ат в overlay.
  - Helper для Game Editor handoff в `_ready`: `if ActiveLevel.has_queued(): _io.load_from(ActiveLevel.consume())`.
  - ≤ 300 строк (AC33).
- `scripts/presentation/ui_panels/internal/panel_tab_bar.gd` — добавить:
  - `signal active_tab_changed(tab_id: StringName)` — эмитить в `_set_active(tab_id)` после изменения `_active_tab_id`. **Только** на пользовательский click (не на programmatic restore из persistence).
- `scripts/presentation/ui_panels/tabbed_base_panel.gd` — re-emit:
  - `signal active_tab_changed(tab_id: StringName)`.
  - В `_setup_tab_bar` после `_tab_bar.setup(self)`: `_tab_bar.active_tab_changed.connect(func(id): active_tab_changed.emit(id))`.
- `scenes/arena/hex_grid.tscn` — фикс F-059-IMPL-4:
  - Точная форма правки определяется при имплементации — варианты:
    - (a) Удалить строки 8-9 (`tile_map_layer = NodePath(...)` и `vfx_overlay = ...`), сделать поля `@onready var tile_map_layer = $Terrain` в `hex_grid.gd`.
    - (b) Пересохранить через Godot UI (приоритет).
    - (c) Ручной патч .tscn в правильный формат для типизированного export.
  - Какой бы fix ни был — workaround в EditorController._ready удаляется одной правкой.
- `scenes/dev/level_editor.tscn` — обновить:
  - Добавить `ObjectsOverlay` и `SpawnersOverlay` как children HexGrid (по образцу map_editor.tscn).
  - LayersPanel теперь TabbedBasePanel — может потребовать пересохранения если ext_resource format отличается.
  - Optional: HelpModal как child HUD (modal layer выше остальных).
  - Без HoverHighlight workaround (он остаётся как Node2D-child HexGrid с 059).
- `scenes/dev/editor/layers_panel.tscn` — пересохранение под TabbedBasePanel script-override (если в .tscn реализуется через children-as-tabs — может вообще не понадобиться, т.к. add_tab из кода).
- `scripts/presentation/main_menu.gd` — удаление map_editor handler + переименование level_editor_new → level_editor.
- `scenes/main_menu.tscn` — удаление кнопки + переименование.
- `scripts/presentation/dev/game_editor_controller.gd` — change_scene путь.
- `scripts/presentation/pause_menu.gd` — `_on_back_to_editor` путь.
- `scripts/presentation/godmode/godmode_input.gd` — back-to-editor путь.
- `data/localization/en.json` + `ru.json` — новые ключи (Q/W/E label'ы для табов, help modal текст, multi-wave warning toast); удаление osiротевших ключей (`ui_map_editor_*` etc.).

### 5.3. Удалённые файлы

См. AC25 — 12 файлов, ~3700 строк.

### 5.4. Selection schema (per-layer)

```
LAYER_HEXES selections:
  Dictionary {"source_id": int, "atlas_coord": Vector2i}  # tile picked
  StringName &"erase"                                      # erase mode
  null                                                     # not selected (initial)

LAYER_SPAWNERS selections:
  Dictionary {"kind": StringName, "ref": StringName}
    kind ∈ {&"player", &"enemy"}
    For player: ref = &""
    For enemy:  ref = enemy_id (e.g. &"slime", &"stapler")
  null                                                     # not selected (initial)

LAYER_OBJECTS selections:
  Dictionary {"object_id": StringName}
  null                                                     # not selected (initial)
```

LayersModel.is_erase() остаётся прежним (только для hexes).
Новый helper LayersModel.has_selection() возвращает true если active layer's selection != null.

### 5.5. Public API editor_controller.gd (под InputDispatcher + panels)

```gdscript
# Layer 1: floor (carry-over from 059)
func paint_floor(coord: Vector2i, source_id: int, atlas_coord: Vector2i) -> void
func erase_floor(coord: Vector2i) -> void

# Layer 2: spawners (new in 060)
func paint_spawner(coord: Vector2i, kind: StringName, ref: StringName) -> void
func erase_spawner(coord: Vector2i) -> void

# Layer 3: objects (new in 060)
func paint_object(coord: Vector2i, object_id: StringName) -> void
func erase_object(coord: Vector2i) -> void

# Cross-layer
func cascade_at(coord: Vector2i) -> void  # erases floor + all objects + all spawners on coord
func set_active_layer(layer_id: StringName) -> void  # called by Q/W/E and tab clicks

# Internal (не вызывается снаружи controller-a)
func _on_io_loaded(level: LevelData) -> void
func _on_layer_selection_changed(layer_id: StringName, value: Variant) -> void
```

Никаких других public методов наружу не торчит.

## 6. Acceptance criteria

См. §3 (AC1-AC37, инлайн с целями для удобства ревью). Smoke прогон описан в `tasks.md`. Все AC проверяются как часть финального smoke перед PR.

## 7. Findings (для других)

- **F-060-1 (для Никиты, Стасяна):** новый Level Editor — единственный путь редактирования карт после merge 060. Старого Map Editor больше нет. Wave editing появится в 061; до тех пор активная wave всегда 0. Многоволновые карты (Никитины концовочные) показывают только wave 0 + warning toast (AC37); их можно сохранять, остальные волны проходят roundtrip.
- **F-060-2 (для Алексея):** dialogue_trigger panel удалён в 060. Возвращается в 061 с cleanup OQ-2 (резолв `id` vs `dialogue_id`). До 061 редактирование триггеров возможно только напрямую в JSON `data/maps/*.json` поле `dialogue_triggers`. Logика runtime DialogueManager не затрагивается.
- **F-060-3 (для Андрея):** удалено ~3700 строк legacy одним атомарным PR. Если в будущем понадобится feature из удалённого (level_history undo, paint_preview, hotkey_overlay) — git log + git show <commit>:scripts/.../<file>.gd для подсмотра реализации. Не пытаться восстановить из памяти.
- **F-060-4 (для всех):** Cascade удаление (Shift+RMB) — destructive без recovery. Юзер должен быть осторожен. Документировано в HELP modal, иконка/цвет шортката отличается от обычного RMB.
- **F-060-5 (для будущего):** undo/redo откладывается. Если потребуется в 064+ — `level_history.gd` (111 строк) был стабильным джем-кодом, можно восстановить из `4f172ca:scripts/presentation/dev/level_history.gd` (= staging tip на момент написания спека) как стартовая точка. Подключение к новому InputDispatcher требует обёртывания каждой mutation (paint/erase/cascade) в transaction.
- **F-060-6 (для будущего):** TabbedBasePanel.active_tab_changed теперь эмитится framework'ом. Любой будущий consumer (in-game UI миграция, новые редакторы) может подписаться. Используется в LayersPanel впервые в 060.
- **F-060-7 (потенциальный):** EditorIO держит state debounce-таймера. При hot-reload F5 (если когда-нибудь подключим) таймер сбросится, accumulated changes могут потеряться. Не блокер сейчас (F5 не у редактора).
- **F-060-8 (для Стасяна):** SCHEMA_VERSION остаётся 2. Bump до 3 — Spec 061.
- **F-060-9 (manual smoke checklist для PR review):**
  1. Открыть main menu → видна одна кнопка «Level Editor», кнопки «Map Editor» нет.
  2. Кликнуть «Level Editor» → новая сцена, без error логов про tile_map_layer.
  3. Q → hexes таб активен → выбрать tile → LMB рисует.
  4. W → spawners таб → выбрать Player → LMB на гексе ставит player. Поставить второй player в другом месте → первый исчез (uniqueness).
  5. E → objects таб → выбрать tree → LMB ставит объект.
  6. Tab Tab Tab → циклически вернулся к hexes.
  7. Кликнуть на name input в LevelMetaPanel, нажать Q — фокус остался в input, ничего не переключилось.
  8. RMB на гексе с тайлом + spawner + object → удаляет только entity active слоя. Shift+RMB → удаляет всё, один flash.
  9. 1-9 → выбирают первые 9 кнопок активной палитры.
  10. F1 → help modal. Esc → закрыт.
  11. Ctrl+S через name + buttons → save в `data/maps/<name>.json`. Закрыть → открыть → проверить что autosave promp'нул бы (вручную: создать дубликат __autosave__ перед reopen).
  12. Из game editor открыть карту → редактировать → exit → возврат в game editor. Из game editor → playtest → ESC → back to editor → возврат.
  13. Загрузить многоволновую карту (если есть в data/maps) → видна warning toast, save сохраняет все волны.

## 8. Resolved decisions (Q-060-*)

Из Clarify-сессии с Андреем:

- **Q-060-1 → (a) extract editor_io.gd.** EditorController остаётся в hard cap 300 строк. Save/load/autosave/grid-sync — отдельный модуль, естественная зона ответственности (растёт в 062 от validation hooks). Альтернатива (c) поднять cap до 450 — отвергнута: 300 был осознанным решением 059, рано отказываться.
- **Q-060-2 → (a) signal в PanelTabBar + re-emit в TabbedBasePanel.** Generic правка ui-panels framework. Малое API expansion, оправдано первой реальной потребностью. Альтернатива (b) polling — отвергнута как cargo-cult.
- **Q-060-3 → проверяем smoke'ом.** Per-palette ButtonGroup сохраняет pressed-state при `visible=false` (TabbedBasePanel hide неактивных). Не нужно дополнительной restore-логики. AC6 формализует smoke-проверку.
- **Q-060-4 → (a) первые 9 buttons палитры.** Подпись цифры в углу первых 9 кнопок активной палитры, скрытые палитры не показывают (потому что сами скрыты). >9 недоступны через цифры — не блокер для 060.
- **Q-060-5 → forward-only Tab.** Q/W/E прямые. Tab → следующий слой. Shift+Tab не реализуется. Skip if focus в text — стандартная focus traversal через `_unhandled_input`.
- **Q-060-6 → cascade без undo, без подтверждения.** Андрей: «весь редактор пойдёт в продакшн целиком, можно без undo». Cascade — Shift+RMB, immediate. Один flash на coord. Документируется в HELP modal.
- **Q-060-7 → delete_flash = маленький visual эффект на удалении.** Не persistent overlay. Реализация как Node2D + Tween fade-out 150ms.
- **Q-060-8 → удаляем старый редактор полностью в 060.** Атомарно, один PR. Cross-refs пересмотрены.
- **Q-060-9 → общий autosave (`__autosave__.json`).** Раз старого больше нет — конфликта нет.
- **Q-060-10 → fix hex_grid.tscn в рамках 060.** Workaround удаляется. Точный fix-метод — при имплементации (см. §5.2).
- **Q-060-11 → (b) нормальное редактирование + warning toast (AC37).** Никита и Стасян не работают с картами в этом окне. Read-only mode не нужен.
- **Q-060-12 → принимаем как inconvenience.** Между 060 и 061 нет UI для dialogue triggers. Юзеры не блокированы.
- **Q-060-13 → (I) удаление в 060, parallel life заканчивается.** Никита не работает с картами в этом окне — окно безопасное для атомарного удаления.

## 9. Out of scope

- **Любая правка `LevelData` schema** — Spec 061 (v3 bump).
- **Validation pipeline** — Spec 062.
- **Wave UI** (timeline, settings, transitions) — Specs 061/063.
- **Music editor** — design.md §11, отдельная фича.
- **In-game UI migration на ui-panels** — design.md §11 OQ-6, отдельное решение.
- **Layout presets** — design.md §11.
- **Tab tear-off testing на LayersPanel** — генеральная фича из 058, не требует валидации в 060.
- **HoverHighlight расширения** (например, показывать silhouette object'а под курсором перед placement) — после 060, не сейчас.
- **HUD-полировка** (анимации табов, transition effects, smooth panel scrolling) — сейчас mvp.
- **Восстановление удалённых features** (level_history, paint_preview, etc.) — каждое требует отдельного спека если возникнет потребность.
- **Тесты GUT** — Editor — UI, manual smoke (по docs/testing.md если бы он был; следуем паттерну 059 — отсутствие GUT тестов).

## 10. Dependency / sequencing

- **Зависит от Spec 058** (TabbedBasePanel) — мерджнут в стейдж до 060.
- **Зависит от Spec 059** (architecture from scratch) — мерджнут в стейдж до 060.
- **Не зависит** от других in-progress спеков.
- **Разблокирует Spec 061** (wave data + settings panel). 061 расширяет LevelData schema и подключает wave UI к LayersPanel или отдельной панели.
- **Внутри 060 — последовательность реализации** в `tasks.md`. Большие группы:
  1. Framework patch (PanelTabBar signal + TabbedBasePanel re-emit) — изолированная правка, мерджится первой в порядке T-задач.
  2. EditorIO extract — рефакторинг 059 без functional changes.
  3. LayersModel/LayersPanel migration — структурный пересмотр.
  4. Палитры (SpawnerPalette, ObjectPalette).
  5. InputDispatcher расширение (per-layer + keyboard + cascade).
  6. EditorController public API + overlay wiring.
  7. Visual effects (delete_flash, help modal).
  8. Game Editor / Playtest / pause-menu cycle integration.
  9. hex_grid.tscn fix.
  10. Удаление legacy + cross-refs (последним — финальный «выключение»).
  11. Loc-keys cleanup.
  12. Smoke prelude.

- **Между 060 и 061 — review pause** per `docs/workflow.md` (если когда-нибудь появится — сейчас следуем паттерну 059). Spec 061 не стартует автоматически после merge 060; решает Андрей.

- **Параллельной жизни больше нет.** После merge 060 в staging — единственный путь редактирования карт. Если на 060 имплементации что-то пошло не так — fixup commits в той же ветке до merge, не через возврат к старому редактору.
