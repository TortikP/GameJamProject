# 019-map-editor — spec

**Owner:** Andrey (UX / dev-tooling, integration). Живёт в `scripts/presentation/dev/` и `scripts/core/maps/`.
**Coordination:**
- **Egor** — `HexGrid` дополняется методом `apply_level_data(level)` и сеттером `set_tile_object(coord, object_id)` (additive, без переименований). PR review нужен.
- **Sergey** — `TileObject` schema **не трогаем**. Редактор — read-only consumer `TileObjectRegistry`. 018 не меняется.
- **Stasyan** — после мержа делает карты мышью, JSON падает в `data/maps/`, схема в `data/maps/_schema.md`.
- **Alexey** — runtime-loader уровня (`LevelLoader`) живёт в Andrey-владении. Когда появится 005-roguelike-loop, тот же loader подключится туда. Сейчас playtest = текущая боевая сцена (godmode-движок) с подгруженной картой.

**Status:** Draft. Жду явного go от Andrey'а; имплементацию запускаю отдельной командой на ветке `andrey/019-map-editor-impl`.

## Цель

Сейчас уровни «рисуются» процедурно в `_paint_grid()` контроллеров. Чтобы добавить новую расстановку — править GDScript. Это блокирует Стасяна (не код) и тормозит итерации Андрея/Никиты по UX-сетапам сцен.

После 019:
- Любой член команды собирает карту мышью в редакторе и сохраняет JSON в `data/maps/`.
- Карта несёт всё нужное для запуска боя: пол, статика 018, спавнеры (игрока + врагов), имя.
- Кнопка **Playtest** в редакторе → сразу в боевую сцену с этой картой.
- Кнопка **Load Custom Level** в главном меню → выбор JSON → бой на этой карте.
- Боевой контроллер в `_ready()` смотрит `ActiveLevel.queued_path`. Выставлен → грузит через `LevelLoader`. Не выставлен → работает как сейчас (процедурный paint). Существующие `Start Run` / `Godmode (dev)` не ломаются.

«Godmode» в репе — историческое имя сцены текущего движка боя; в этой спеке слово «movement engine» / «боевая сцена» означает её же. 019 не разделяет редактор и игру — редактор пишет данные, движок их читает.

## Что вводится

### Сущность LevelData (новая, pure-data)

Контейнер уровня. Сериализуется в JSON, грузится `LevelSerializer`'ом.

| Поле | Тип | Описание |
|---|---|---|
| `name` | `String` | Человекочитаемое имя. Файл сохраняется как `<sanitized_name>.json`. |
| `version` | `int` | Schema version. v1 = `1`. |
| `tileset_path` | `String` | `res://...` к `.tres` тайлсета пола. Default `res://scenes/dev/godmode_terrain.tres`. |
| `floor` | `Array[Dictionary]` | `[{coord: Vector2i, source_id: int, atlas_coord: Vector2i}]` — каждый покрашенный гекс. |
| `objects` | `Array[Dictionary]` | `[{coord: Vector2i, object_id: StringName}]` — статика 018. |
| `spawners` | `Array[Dictionary]` | `[{coord: Vector2i, kind: StringName, ref: StringName}]`. `kind ∈ {&"player", &"enemy"}`. Для `&"enemy"` `ref` = enemy_id (`manekin`). Для `&"player"` `ref` = `&""`. |

Жёсткие инварианты `LevelData.validate()`:
- ровно 1 спавнер `kind=&"player"`. 0 или >1 → save с warn-toast'ом *и* отказом записи; load — отказ + toast.
- `coord` каждого `objects` / `spawners` ∈ `floor.map(it.coord)`. Иначе drop entry с warn (graceful — не валится весь уровень).
- 1 объект на тайл, 1 спавнер на тайл, объект+спавнер на одном тайле — запрещено (валидация editor-side при placement, см. AC-E5).

### Сцена редактора `scenes/dev/map_editor.tscn`

Дерево:
```
MapEditor (Node2D)
├── EditorCamera (Camera2D — pan/zoom как godmode_camera)
├── HexGrid (instance scenes/arena/hex_grid.tscn)
│   ├── FloorLayer (TileMapLayer, единственный реальный tile_map для пола)
│   ├── ObjectsOverlay (Node2D, spawn'ит Sprite2D-per-object из TileObject.sprite_path)
│   ├── SpawnersOverlay (Node2D, Sprite2D-per-spawner; player = постоянная иконка, enemy = тинт по enemy_id)
│   ├── HoverHighlight (Node2D, рисует контур текущего гекса)
│   └── DeleteHighlight (Node2D, красная заливка отмеченного к удалению гекса)
├── EditorController (Node, скрипт map_editor_controller.gd)
└── HUD (CanvasLayer)
    ├── ObjectPalettePanel (правая панель)
    ├── FloorPalettePanel (левая нижняя)
    ├── LevelMetaPanel (правый верх — Name input, Save, Load, Playtest, Exit)
    ├── ToastLayer (instance scenes/ui/toast_layer.tscn)
    └── ConfirmModal (instance scenes/ui/confirm_modal.tscn)
```

Замечание про «два TileLayer»: пол — реальный `TileMapLayer`. Объекты — `Node2D` с Sprite2D-детьми. Это сознательное отклонение от буквальной формулировки задачи: 018 хранит `object_id` в custom data layer тайла-пола, отдельного TileSet'а под все объекты-спрайты в репе нет (потребовало бы атласа от Кати + переписывания 018). Семантически слой ровно тот же — данные снаружи (в `LevelData.objects`), визуализация поверх пола, не смешивается с тайлсетом.

### Палитры

**FloorPalettePanel (нижняя):**
- Дропдаун выбора TileSet: `godmode_terrain.tres` / `hex_terrain.tres` (значение пишется в `LevelData.tileset_path`).
- Кнопки тайлов из выбранного TileSet (одна кнопка на каждую `(source_id, atlas_coord)` пару, лейбл — `tile_kind` из custom data, иконка — превью из атласа).
- Кнопка **Erase** — отдельный mode, LMB снимает тайл.

**ObjectPalettePanel (правая):**
- Вкладки (TabBar): **Spawners**, **Obstacles**, **Interactive**.
- Filter row (горизонталь, persistent across tabs):
  - 3 чекбокса type: `Large` / `Small` / `Elevation` (default: все вкл). Применяются только к Obstacles/Interactive — на Spawners-табе скрыты.
  - 1 чекбокс `Has effect` (показывает только объекты с `behavior_effect_id != ""`). Применяется только к Obstacles/Interactive.
- Контент вкладок:
  - **Spawners:** 1 кнопка `Player Spawn` (статичная иконка) + 1 кнопка на каждый `data/enemies/*.json`.
  - **Obstacles:** объекты из `TileObjectRegistry`, у которых `breakable=false` AND `behavior_effect_id == &""`. Это «чистая статика»: `mountain`, `boulder`, `wooden_table` (не breakable... — стоп, `wooden_table` breakable. см. ниже).
  - **Interactive:** объекты, у которых `breakable=true` OR `behavior_effect_id != &""`. Это `lava_pool`, `heal_fountain`, `wooden_barrel`, `wooden_table`.
  - Категоризация — детерминированная функция от полей `TileObject`. Без новых полей. Формула в `plan.md`.

«Локация» в исходной формулировке = карта/уровень (синоним). Связи объект↔локация в 019 нет — все объекты доступны на любой карте.

### Input (state machine)

States:
- **IDLE** — ничего не выбрано в палитрах. LMB на гексе с объектом → drag-mode (P2). LMB на пустом — no-op.
- **PLACING_FLOOR** — выбран тайл пола. LMB на гексе → set_cell. Hover показывает превью. RMB → cancel selection в палитре, переход в IDLE.
- **ERASING_FLOOR** — выбран Erase в FloorPalette. LMB → erase_cell + удалить любой объект/спавнер на нём.
- **PLACING_OBJECT** — выбран объект из ObjectPalette. LMB на пустом гексе пола → place. LMB на гексе с объектом или спавнером → popup «Невозможно: тайл занят». LMB вне покрашенного пола → toast «Сначала пол».
- **PLACING_SPAWNER** — выбран спавнер. Та же логика placement. Player-спавнер: если уже стоит где-то и игрок ставит ещё — старый удаляется (single-instance constraint).
- **PENDING_DELETE** — RMB по гексу. Гекс подкрашен красным. Следующий RMB по тому же гексу → удалить (объект → объект; спавнер → спавнер; иначе → пол + всё что на нём). RMB по другому гексу — переключить highlight на новый. LMB где угодно → снять highlight (и при этом выполнить нормальное LMB-действие согласно текущему placement-моду).

**Drag-and-drop существующих объектов (P2, опциональный):**
- LMB-press в IDLE на гексе с объектом → grab.
- Mouse-move с зажатым LMB → ghost preview под курсором.
- LMB-release на пустом гексе пола → переместить.
- LMB-release на занятом → popup-отказ.

### Save / Load / Playtest

- **Save:** `LevelMetaPanel.SaveButton` → `LevelData.validate()` → если ошибка → toast warn, не пишем. Иначе `LevelSerializer.save(level, "res://data/maps/<sanitized_name>.json")`. Sanitize: lowercase, `[a-z0-9_-]`, остальные → `_`. Если файл существует — `ConfirmModal.ask("Перезаписать?", danger=true)`.
- **Load (в редакторе):** `LevelMetaPanel.LoadButton` → если в редакторе есть несохранённые изменения (флаг dirty) → `ConfirmModal.ask("Сохранить текущую карту?", confirm="Сохранить", cancel="Не сохранять")`. После — file picker (`FileDialog` с фильтром `*.json` в `res://data/maps/`). Выбор → `LevelSerializer.load(path)` → `MapEditorController.apply(level)`.
- **Load (в главном меню):** `MainMenu.LoadCustomLevelButton` → file picker → `ActiveLevel.queue(path)` → `change_scene_to_file(godmode.tscn)`. Боевой контроллер в `_ready()` подхватывает.
- **Playtest:** `LevelMetaPanel.PlaytestButton` → если карта не валидна (нет player spawner) → toast error, exit. Иначе → write to temp `res://data/maps/__playtest__.json` → `ActiveLevel.queue("res://data/maps/__playtest__.json")` → `change_scene_to_file("res://scenes/dev/godmode.tscn")`. **Не** заставляем сохранять реальный файл — Playtest всегда работает на временном слоте.

«Замещение уровня по умолчанию»: godmode-контроллер в `_ready()` чек'ает `ActiveLevel.has_queued()`. Если да — пропускает `_paint_grid()` + `_place_player()`, вызывает `LevelLoader.apply_to(grid, registry, level)`. Если нет — старый procedural-путь нетронут.

### Hotkey + точки входа

- Новая input action `dev_open_editor` = **Ctrl+E** (любой контекст: главное меню, бой, godmode). `_unhandled_input` → `change_scene_to_file("res://scenes/dev/map_editor.tscn")`.
- В главном меню новые кнопки:
  - **Map Editor [Ctrl+E]** — лейбл с хоткеем (текстом, не отдельным виджетом — как в keybind_overlay-стиле).
  - **Load Custom Level** — file picker → ActiveLevel.queue → change_scene godmode.

Хоткей слушает глобальный `ProjectSettings.input_map`. Чтобы он не срабатывал во время диалогов / модалок — слушатель сидит в editor scene, в главном меню, и в godmode. В каждом — `_unhandled_input` (модалки сами `set_input_as_handled`).

### Новый autoload `ActiveLevel`

```gdscript
# scripts/infrastructure/active_level.gd
extends Node
var queued_path: String = ""
func queue(path: String) -> void: queued_path = path
func consume() -> String:
    var p := queued_path; queued_path = ""; return p
func has_queued() -> bool: return queued_path != ""
```

Зарегистрировать в `[autoload]` в `project.godot`. Не event-bus подписан, чисто синхронный slot.

## Acceptance criteria

- **AC-E1 (data class).** `LevelData` в `scripts/core/maps/level_data.gd` — pure data + `validate() -> Array[String]` (массив сообщений об ошибках, пустой = валидно). `LevelSerializer.save(level, path) -> bool` и `LevelSerializer.load(path) -> LevelData`. JSON через `JSON.stringify(d, "\t")` (читаемо для человека).
- **AC-E2 (apply path).** `LevelLoader.apply_to(grid: HexGrid, registry: ActorRegistry, level: LevelData)` красит `FloorLayer.set_cell` по `floor[]`, ставит объекты через новый `HexGrid.set_tile_object(coord, object_id)` (additive setter), спавнит player + врагов в позиции спавнеров. После apply — `grid.initialize()` уже вызван контроллером сцены, loader не зовёт его повторно.
- **AC-E3 (godmode integration).** В `godmode_controller._ready()` перед `_paint_grid` / `_place_player` — проверка `ActiveLevel.has_queued()`. Если да: `_paint_grid()` пропускается, `_place_player()` пропускается, вызывается `LevelLoader.apply_to(...)` после `grid.initialize()`. Existing path (нет queued) работает побайтово как раньше.
- **AC-E4 (editor scene).** `scenes/dev/map_editor.tscn` запускается через Ctrl+E из любой сцены или из главного меню. На пустой карте — поле имени, пустой пол (стартует с минимального 5x5 покрашенного quad'а грассы для удобства; пользователь может стирать/расширять).
- **AC-E5 (placement validation).** Попытка положить объект на тайл, где уже объект или спавнер — `ConfirmModal`-style popup «Тайл занят» с одной кнопкой OK (не danger, не интрузивный — модалка просто закрывается, ничего не меняется). Toast тут не подходит (надо чтобы пользователь подтвердил, что увидел).
- **AC-E6 (delete two-step).** RMB по гексу → `DeleteHighlight` рисует красный полигон. Повторный RMB по нему → удаление. RMB по другому → highlight перенаправляется. LMB → highlight снимается + LMB-действие выполняется (если есть placement-mode).
- **AC-E7 (palette tabs).** ObjectPalette имеет 3 вкладки: Spawners, Obstacles, Interactive. Категоризация — `breakable OR behavior_effect_id != &""` → Interactive, иначе → Obstacles. Spawners тачается отдельно (не из TileObjectRegistry, а из `data/enemies/*.json` + хардкод player).
- **AC-E8 (filters).** На вкладках Obstacles + Interactive активны 3 type-чекбокса (Large/Small/Elevation) и `Has effect`. На Spawners — фильтры скрыты. Дефолт: все типы вкл, `Has effect` выкл (показывает все).
- **AC-E9 (player spawner singleton).** Размещение player-спавнера, если уже стоит — старый удаляется (с visual ghost-fade на 200ms — `await GameSpeed.wait("editor", "spawner_swap")`, фолбэк 200ms если ключа в cfg нет). Save без player-спавнера — отказ + toast error «Поставь Player Spawn».
- **AC-E10 (save).** Save → `res://data/maps/<sanitized>.json`. Sanitize: имя → lower → replace `[^a-z0-9_-]` на `_` → trim leading `_` → если пусто, `untitled`. Файл существует — confirm-modal перезаписи. После save — `EventBus.ui_toast_requested.emit("Saved: %s" % filename, 2.0, &"success")`.
- **AC-E11 (load editor-side).** Editor Load → если dirty → confirm-save. После — FileDialog с фильтром `*.json` в `res://data/maps/`. Загрузка → editor сбрасывается в новое состояние, dirty = false.
- **AC-E12 (load main-menu).** В главном меню новая кнопка **Load Custom Level** → FileDialog → `ActiveLevel.queue(path)` → change_scene → godmode. **Map Editor [Ctrl+E]** новая кнопка → change_scene → map_editor.
- **AC-E13 (playtest).** Editor Playtest → validate → write to `__playtest__.json` (даже если основной файл не сохранён) → ActiveLevel.queue → change_scene godmode. Возврат из godmode (Esc → main menu или новый «Back to editor» в pause-меню — последнее в out_of_scope для v1) — не специфицировано в 019. Минимум: Esc → main menu работает, оттуда снова Ctrl+E.
- **AC-E14 (sample map).** `data/maps/sample.json` — pre-made тестовая карта 8×6, content-blueprint Стасяна: грасса пол, 1 player спавнер, 2 manekin спавнера, 2 объекта (lava_pool, wooden_barrel). Грузится из главного меню → бой запускается, player ставится в свою клетку, манекены — в свои.
- **AC-E15 (schema doc).** `data/maps/_schema.md` — формат JSON для Стасяна (если он захочет править руками; редактор — основной путь). Структура — 1:1 с `LevelData`.

## Open Questions — RESOLVED

- **OQ-1: Связь объекта с локацией / биомом.** Резолвед: связи **нет**, все объекты везде. Будущая система тегов (тема «Метаморфозы») — отдельной фичей.
- **OQ-2: Формат двух TileLayer.** Резолвед: пол = реальный `TileMapLayer`, объекты = `Node2D` overlay со Sprite2D-детьми. Выделенный TileSet под все объекты — out_of_scope (нет атласа от Кати, ломает 018).
- **OQ-3: Save target.** Резолвед: `res://data/maps/`. В экспортированном билде readonly — приемлемо, редактор это dev-tool.
- **OQ-4: Палитра пола.** Резолвед: оба тайлсета (`hex_terrain.tres` + `godmode_terrain.tres`) выбираемые из дропдауна.

## Out of scope

- **Системы тегов на объектах** (forest/church/dungeon — для подмены под тему). Future-work, отдельная спека.
- **Биомы** в любой форме. Не существуют сейчас, не вводим.
- **Per-tile metadata** кроме floor source/atlas (нет «эта клетка — алтарь», нет per-tile biome, нет per-tile elevation). Если понадобится — отдельной фичей расширения схемы.
- **Multi-tile объекты.** 1 тайл = 1 объект (наследие 018).
- **Procedural-генерация** карт. Только ручной редактор.
- **Undo/redo.** Случайно стёр пол — придётся перерисовать. Save-чаще, чтобы не больно.
- **Снепшоты-автосейв.** Только manual save.
- **Multiple-select / box-select.** Только single-tile операции.
- **Copy-paste области.** Аналогично.
- **«Назад в редактор» из playtest'а** (Esc-меню knows). Сейчас Esc → главное меню → снова Ctrl+E. Polish-фича.
- **Шаринг карт между пользователями через UI.** Файлы в `res://data/maps/` коммитятся git'ом, обмен — через PR.
- **Visual TileSet для объектов** (атлас всех объектов как тайлов). Требует ассет-производства от Кати.
- **Режим «play this level» из main menu без редактирования** — по сути уже есть через **Load Custom Level**, но без файлдиалога-листинга preset карт. Если надо будет — отдельная итерация UX.
- **Spawner extra fields** (level overrides — manekin с другим HP, разные skills). Сейчас спавнер = `enemy_id` + coord, всё. Per-spawner-overrides — отдельной фичей если понадобится.
- **Игровое использование тайлсета биомов / per-tile color tint в бою.** Чисто визуальное, отдельно.

## Зависимости

- **Upstream:** 002-hex-grid (HexGrid + TileMapLayer), 018-tile-objects (TileObject + Registry), 009-ui-kit (UiTheme, ConfirmModal, ToastLayer), godmode-сцена.
- **Downstream:** 005-roguelike-loop (когда появится — будет читать `LevelData` для wave-encounters), модификатор-движок (когда появится система тегов на объектах).
- **Coordination:** Egor (additive методы в HexGrid) — PR review обязателен. Sergey — read-only зависимость от 018, его approval не нужен но FYI ping. Стасян — после мержа делает карты + опционально правит JSON руками. Alexey — `LevelLoader` API будет переиспользован в roguelike-loop'е, FYI ping.

## История правок

- 2026-05-02 v1 — first draft. Pre-clarify: фильтр «по локации» = новое поле в TileObject, биомы как система. ✗
- 2026-05-02 v2 — clarify-round: «локация» = карта (синоним), связи объект↔локация нет, биомов нет. Спека упрощена. Текущая версия.
