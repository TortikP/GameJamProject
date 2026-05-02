# 023-editor-ux-polish — plan

> «Как» к `spec.md`. File paths, signal API, нюансы реализации. Поделено по тем же P1/P2/P3.

## Уже сделано в ветке

- `scripts/presentation/dev/draggable_panel.gd` — Node-mixin, цепляется к `PanelContainer`, header-Label = drag handle, на старте drag отвязывает от якорей.
- `scenes/dev/map_editor.tscn` — `ObjectPalettePanel.offset_top` 80→160 (фикс перекрытия с Level панелью).
- 3 палитры подключают `_install_drag(header)` в `_build_ui()`.

## P1

### Drag-paint LMB

**Файл:** `scripts/presentation/dev/map_editor_controller.gd`.

`_unhandled_input` сейчас обрабатывает только `pressed`-события. Добавляется:

- `var _lmb_held: bool = false`
- `var _last_paint_coord: Vector2i = Vector2i(-1, -1)` — анти-ребаунс, чтобы один и тот же гекс не обрабатывался дважды подряд при микродвижении мыши.
- На `InputEventMouseButton` LMB pressed → `_lmb_held = true`, `_paint_at(coord)` (выделить тело старого `_handle_lmb` в чистую функцию `_paint_at`).
- На LMB released → `_lmb_held = false`, `_last_paint_coord = Vector2i(-1, -1)`, **закрыть undo-транзакцию** (см. ниже).
- На `InputEventMouseMotion` если `_lmb_held` и режим один из `PLACING_FLOOR / ERASING_FLOOR / PLACING_OBJECT / PLACING_SPAWNER` (кроме `kind == &"player"`, см. ниже) → `coord := grid.coord_under_mouse()`. Если `coord != _last_paint_coord` → `_paint_at(coord)`, обновить `_last_paint_coord`.

**Player spawner**: сингл-шот, не drag. В motion-ветке проверяем `_placing_spawner_kind == &"player"` → return.

**Erase**: `Mode.ERASING_FLOOR` ведёт себя одинаково с placing, drag тоже работает.

### Silent reject занятого тайла

**Файл:** `map_editor_controller.gd`.

- `_show_occupied_modal()` — удалить.
- В `_place_object` и `_place_spawner` где сейчас `_show_occupied_modal()` → `return` без побочных эффектов. Опциональный однократный toast `«Занято»` 0.8s `&"info"` с debounce: `var _occupied_toast_until: float = 0.0`; toast показывается только если `Time.get_ticks_msec() / 1000.0 > _occupied_toast_until`, после показа `_occupied_toast_until = now + 0.8`.

### Undo/Redo

**Новый файл:** `scripts/presentation/dev/level_history.gd` — RefCounted.

```gdscript
class_name LevelHistory extends RefCounted

const MAX_DEPTH: int = 50

var _undo: Array = []   # of LevelData snapshots (PackedByteArray от bytes_to_var)
var _redo: Array = []
var _txn_open: bool = false
var _txn_baseline = null   # snapshot, взятый при begin_txn

func begin_transaction(level: LevelData) -> void
func end_transaction(level: LevelData) -> void   # пушит baseline в _undo если изменилось
func push(level: LevelData) -> void              # для одиночных мутаций
func can_undo() -> bool
func can_redo() -> bool
func undo(current: LevelData) -> LevelData       # возвращает прошлый snapshot, текущий → в _redo
func redo(current: LevelData) -> LevelData
```

Snapshot — `var_to_bytes(level.to_dict())` (LevelData уже сериализуется в Dict для save). На undo — `LevelData.from_dict(bytes_to_var(snapshot))`. Это даёт глубокую копию без ручного клонирования каждого Dict-а.

**Подключение в `map_editor_controller.gd`:**

- `var _history: LevelHistory = LevelHistory.new()`.
- В `_handle_lmb` LMB-pressed (начало drag) → `_history.begin_transaction(_level)`.
- В LMB released → `_history.end_transaction(_level)`.
- Одиночные мутации не через drag (RMB delete, replace_all, load) → `_history.push(_level)` **до** мутации.
- На `Ctrl+Z` → если `_history.can_undo()`: `_level = _history.undo(_level)`, перерисовать (см. «Полная перерисовка»).
- На `Ctrl+Y` или `Ctrl+Shift+Z` → симметрично.

**Полная перерисовка после undo/redo:**
- `grid.tile_map_layer.clear()` → пройти по `_level.floor_cells` → `set_cell`.
- `_objects_overlay.clear_all()` → пройти по `_level.objects` → `set_object`.
- `_spawners_overlay` — аналогично.
- `_mark_dirty()`.

Уже есть `_apply_loaded_level` (для Load) — подходящий хелпер, переиспользуем (если нет — извлечь рефакторингом).

### Ctrl+S save

`_unhandled_input` ловит `InputEventKey` с `keycode == KEY_S and ctrl_pressed and pressed`. Дёргает `_on_save_requested()` (тот же путь, что кнопка Save). `accept_event()`.

### Dirty-asterisk

**Файл:** `scripts/presentation/dev/level_meta_panel.gd` + `map_editor_controller.gd`.

- В `LevelMetaPanel`: новый метод `set_dirty(dirty: bool)`. Хранит `_base_name` (то, что юзер ввёл) и `_dirty`. В `_name_edit.text` показывает `"* " + _base_name` если dirty, иначе `_base_name`. На `text_changed` обновляет `_base_name` (срез `* `, если есть).
- В контроллере: после `_mark_dirty()` → `_meta_panel.set_dirty(true)`. После успешного Save → `_meta_panel.set_dirty(false)`.

## P2

### Eyedropper (Alt+ЛКМ)

**Файлы:** `map_editor_controller.gd`, обе палитры (`floor_palette_panel.gd`, `object_palette_panel.gd`).

- В `_unhandled_input` LMB pressed: если `mb.alt_pressed` → ветка eyedropper, не paint.
- Контроллер вызывает `_eyedropper(coord)`:
  - Сначала проверяем object/spawner в этой клетке (приоритет, т.к. они «сверху» пола).
  - Spawner → `_object_palette.select_spawner(kind, ref)` (новый публичный метод: переключает Tab на Spawners + находит и тогглит соответствующую кнопку, эмитит `spawner_picked`).
  - Object → `_object_palette.select_object(object_id)` — switch tab на Obstacles или Interactive в зависимости от `_registry.get_object(object_id).breakable or behavior_effect_id != ""`.
  - Иначе пол → `_floor_palette.select_tile(source_id, atlas)` — найти кнопку с такими координатами и pressed-toggle.
- Палитры получают новые методы `select_*(...)`. Внутри: untoggle other + toggle target + emit соответствующий сигнал → controller выставит mode.

### Quick palette select (1-9)

**Файл:** `map_editor_controller.gd`.

`_unhandled_input` ловит `KEY_1..KEY_9` (без Ctrl/Alt). Контроллер знает, какая палитра активна по `_mode`:
- `PLACING_FLOOR / ERASING_FLOOR / IDLE` → передать на `_floor_palette.select_nth(N-1)`.
- `PLACING_OBJECT / PLACING_SPAWNER` → на `_object_palette.select_nth(N-1)` (внутри текущего таба).

Если кнопок меньше N — игнор. Палитры реализуют `select_nth(idx: int)` поверх существующих списков.

### Hotkey overlay (H)

**Новый файл:** `scenes/dev/hotkey_overlay.tscn` + `scripts/presentation/dev/hotkey_overlay.gd`.

- `Control` с полупрозрачным фоном (UiTheme bg 0.7 alpha), центрированный VBox с `Label`-ами — две колонки (key | description).
- Контент захардкоден в скрипте (это шпаргалка, не настраиваемая):
  ```
  LMB           — paint / place
  LMB drag      — paint / place serial
  RMB / RMB     — delete (2-click confirm)
  Alt+LMB       — eyedropper
  Ctrl+Z / Y    — undo / redo
  Ctrl+S        — save
  1-9           — quick palette select
  WASD / arrows — pan
  Mouse wheel   — zoom
  H             — toggle this overlay
  ```
- В `map_editor.tscn` инстанцируется в `HUD/HotkeyOverlay`, `visible = false` по дефолту. `mouse_filter = MOUSE_FILTER_IGNORE` чтобы не съедал клики.
- Контроллер ловит `KEY_H` без модификаторов → `_hotkey_overlay.visible = !_hotkey_overlay.visible`.

### Тематический фон панелей

**Файл:** `scripts/presentation/ui_theme.gd` → `make_panel_stylebox`.

Минимальные правки (заметные, не радикальные):
- Тонкий border (1-2px) с акцентным цветом (`COL_ACCENT` если есть, иначе ввести).
- `corner_radius` чуть больше (если уже не 4-6).
- Лёгкая внутренняя тень (`shadow_size = 4, shadow_offset = (0, 2), shadow_color = bg.darkened(0.3)`).

Все три палитры подхватят автоматом через `EventBus.ui_theme_reloaded` (уже подписаны).

### Силуэты объектов

**Файл:** `scripts/presentation/dev/objects_overlay.gd`.

Заменить ColorRect-плейсхолдер на кастомный `Node2D` с `_draw()`. Маппинг `object_id` → `shape_kind`:

| object_id | shape_kind | rationale |
|---|---|---|
| `mountain` | `triangle_filled` | пик |
| `boulder` | `circle_filled` | большой круг |
| `tree` (новый) | `triangle_filled_tall` | крона |
| `bush` (новый) | `triangle_filled_low` | низкая крона |
| `crystal` (новый) | `diamond_filled` | ромб |
| `wooden_table` | `rect_wide` | широкий низкий прямоугольник |
| `wooden_barrel` | `rect_tall` | высокий узкий |
| `heal_fountain` | `diamond_outline` | ромб контуром |
| `lava_pool` | `blob` (или `rect_rounded`) | большая лужа |

Цвет — берём по тегам (`tags` уже есть в `TileObject`):
- `wood`, `plant` → коричневый/зелёный
- `stone` → серый
- `metal` → серебристый
- `liquid` + `hazard` → красно-оранжевый
- `liquid` + не hazard → синий
- `furniture` → светло-коричневый
- fallback → текущий hash-цвет

Хелпер: `_silhouette_for(obj: TileObject) -> Dictionary { "shape": StringName, "color": Color }`. Все рисовалки — в `_draw()` нового вспомогательного `Node2D`-наследника `ObjectSilhouette` (отдельный мини-скрипт `scripts/presentation/dev/object_silhouette.gd`), один экземпляр на гекс, привязан к `set_object`.

### Новые объекты

**Файлы:** `data/tile_objects/tree.json`, `bush.json`, `crystal.json`. Без правок кода.

- `tree`: `level: -1` (LARGE), `breakable: true, hp: 3, armor_tags: [physical]`, `tags: ["wood", "plant", "flammable"]`, `on_destroy_effect_id: ""`. Sprite_path пустой → fallback на силуэт.
- `bush`: `level: 0` (SMALL walkable), `blocks_movement: false`, `behavior_effect_id: ""`, `tags: ["plant", "flammable"]`. Лёгкое cover.
- `crystal`: `level: -1` (LARGE), `breakable: true, hp: 4`, `behavior_effect_id: "heal_fountain", aura_radius: 1`, `tags: ["stone", "construct"]`.

(Финальный баланс — на Стасяне, это стартовая болванка для редактора.)

### Sample enemies

**Файлы:** `data/enemies/skeleton.json`, `slime.json`, `archer.json`. Структура — копия `manekin.json` с минимальными правками HP/skills (или пустыми, если schema допускает). Цель — проверить, что `_build_spawner_buttons` подхватывает новые файлы. Если schema требует ещё полей — копируем целиком, меняем `id`.

## P3 — пропускаем без планирования.

## Структура undo (детали)

`LevelData.to_dict()` и `LevelData.from_dict()` уже существуют для save/load. Snapshot:

```gdscript
func _snapshot(level: LevelData) -> PackedByteArray:
    return var_to_bytes(level.to_dict())

func _restore(snap: PackedByteArray) -> LevelData:
    var ld := LevelData.new()
    ld.from_dict(bytes_to_var(snap))
    return ld
```

Если эти методы называются иначе — посмотреть `scripts/core/maps/level_data.gd` и адаптировать (это уточняем в задаче T-04).

## EventBus (новых сигналов не нужно)

Все взаимодействия — через прямые ссылки `controller ↔ palette` (уже так) + локальные коллбеки. EventBus не расширяем.

## Файлы (итоговый список)

**Новые:**
- `scripts/presentation/dev/level_history.gd`
- `scripts/presentation/dev/object_silhouette.gd`
- `scripts/presentation/dev/hotkey_overlay.gd`
- `scenes/dev/hotkey_overlay.tscn`
- `data/tile_objects/tree.json`, `bush.json`, `crystal.json`
- `data/enemies/skeleton.json`, `slime.json`, `archer.json`

**Изменяемые:**
- `scripts/presentation/dev/map_editor_controller.gd` (drag-paint, undo, shortcuts, eyedropper)
- `scripts/presentation/dev/level_meta_panel.gd` (dirty asterisk)
- `scripts/presentation/dev/floor_palette_panel.gd` (`select_tile`, `select_nth`)
- `scripts/presentation/dev/object_palette_panel.gd` (`select_object`, `select_spawner`, `select_nth`)
- `scripts/presentation/dev/objects_overlay.gd` (силуэты вместо ColorRect)
- `scripts/presentation/ui_theme.gd` (`make_panel_stylebox` улучшение)
- `scenes/dev/map_editor.tscn` (`HotkeyOverlay` инстанс в HUD)
