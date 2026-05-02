# 023-editor-ux-polish — tasks

> Атомарные задачи, в порядке зависимостей. `[x]` — сделано, `[ ]` — открыто.
> P1 → P2. P3 не планируем заранее.

## Done (вне основного списка задач — immediate fix перед спекой)

- [x] **D-01.** `scripts/presentation/dev/draggable_panel.gd` — Node-mixin для drag-by-handle.
- [x] **D-02.** `level_meta_panel.gd / object_palette_panel.gd / floor_palette_panel.gd` — `_install_drag(header)` в `_build_ui()`.
- [x] **D-03.** `scenes/dev/map_editor.tscn` — `ObjectPalettePanel.offset_top` 80→160 (фикс перекрытия).

---

## P1

### Drag-paint LMB

- [x] **T-01.** Извлечь тело `_handle_lmb` в чистую `_paint_at(coord)`. `_handle_lmb` остаётся обёрткой (snapshot baseline → `_paint_at`).
  - File: `scripts/presentation/dev/map_editor_controller.gd`.
  - Pure refactor, без поведенческих изменений.

- [x] **T-02.** Добавить состояние `_lmb_held: bool`, `_last_paint_coord: Vector2i = Vector2i(-1, -1)`.
  - В `_unhandled_input` LMB pressed → `_lmb_held = true`. LMB released → `_lmb_held = false`, `_last_paint_coord = Vector2i(-1, -1)`.
  - Зависит от: T-01.

- [x] **T-03.** Drag-paint в `_unhandled_input`: на `InputEventMouseMotion` если `_lmb_held` и `_mode in {PLACING_FLOOR, ERASING_FLOOR, PLACING_OBJECT, PLACING_SPAWNER}` и не `(PLACING_SPAWNER & kind == &"player")` → если `coord != _last_paint_coord` вызвать `_paint_at(coord)`, обновить `_last_paint_coord`.
  - Зависит от: T-02.

### Silent reject

- [x] **T-04.** Удалить `_show_occupied_modal()` в `map_editor_controller.gd`. В двух местах (`_place_object`, `_place_spawner`) заменить вызов на `return`.
  - Опционально: однократный toast `«Занято»` 0.8s `&"info"` с debounce через `_occupied_toast_until: float`. Spec говорит «опционально» — делаем, отключаемо одной строкой.
  - File: `scripts/presentation/dev/map_editor_controller.gd`.

### Undo / Redo

- [x] **T-05.** Изучить `scripts/core/maps/level_data.gd` — найти точные имена `to_dict`/`from_dict` (или эквивалентов). Если есть только save-сериализация в JSON — использовать её через промежуточный Dict.
  - Подтверждено: `to_dict()` и `from_dict(d)` существуют, разведка для T-06.

- [x] **T-06.** Создать `scripts/presentation/dev/level_history.gd` — `RefCounted`. API: `begin_transaction`, `end_transaction`, `push`, `can_undo`, `can_redo`, `undo`, `redo`. `MAX_DEPTH = 50`. Snapshot через `var_to_bytes(level.to_dict())`.
  - Зависит от: T-05.

- [x] **T-07.** Подключить `LevelHistory` в `map_editor_controller.gd`: `var _history := LevelHistory.new()`. На LMB pressed → `_history.begin_transaction(_level)`. На LMB released → `_history.end_transaction(_level)`.
  - Зависит от: T-06, T-02.

- [x] **T-08.** Одиночные мутации (RMB delete, replace_all, load) → `_history.push(_level)` **до** мутации.
  - Зависит от: T-07.

- [x] **T-09.** Извлечь полную перерисовку уровня в `_redraw_level()` (clear tile_map_layer + objects_overlay + spawners_overlay → пройти по `_level` и расставить заново). Если `_apply_loaded_level` уже это делает — переименовать/переиспользовать.
  - Подтверждено: `_apply_level` уже делает полную перерисовку, переиспользуем напрямую в undo/redo.

- [x] **T-10.** Шорткаты Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z в `_unhandled_input`. На undo: `_level = _history.undo(_level)` → `_redraw_level()` → `_mark_dirty()`. Симметрично для redo.
  - Зависит от: T-07, T-09.

### Ctrl+S

- [x] **T-11.** В `_unhandled_input` ловить `InputEventKey` с `keycode == KEY_S and ctrl_pressed and pressed`. Дёргать тот же `_on_save_requested()`, что и кнопка Save. `accept_event()`.
  - File: `map_editor_controller.gd`.

### Dirty asterisk

- [x] **T-12.** В `level_meta_panel.gd`: новый метод `set_dirty(dirty: bool)`. Хранит `_base_name: String`. Имя в LineEdit показывается как `("* " + _base_name) if dirty else _base_name`. На `text_changed` обновляет `_base_name` (с автоснятием `* ` префикса, если юзер не удалил его сам).
  - **Реализация отличается от плана**: вместо префикса в LineEdit добавлен отдельный `_dirty_marker` Label с `*` рядом с полем. Чище UX (нет конфликта с edit-handling), плюс визуальный warm-orange акцент через `SEM_DEBUFF`.

- [x] **T-13.** В контроллере: после `_mark_dirty()` → `_meta_panel.set_dirty(true)`. После успешного `_save_to_path` → `_meta_panel.set_dirty(false)`. После Load — тоже false.
  - Реализовано через `_set_clean()` helper-counterpart к `_mark_dirty()`. Все прямые `_dirty = true/false` присваивания заменены на эти два метода — meta panel всегда в синке.
  - Зависит от: T-12.

---

## P2

### Eyedropper

- [x] **T-14.** В `floor_palette_panel.gd`: публичный метод `select_tile(source_id: int, atlas: Vector2i)`. Находит кнопку с этими параметрами в `_tile_grid`, untoggle others, toggle self, emit `tile_picked`.
  - Tile-кнопки получили meta `source_id`/`atlas_coord` для лукапа.

- [x] **T-15.** В `object_palette_panel.gd`: методы `select_object(object_id: StringName)` и `select_spawner(kind: StringName, ref: StringName)`. `select_object` сначала переключает Tab (Obstacles или Interactive по `obj.breakable or behavior_effect_id != ""`), потом ищет кнопку. `select_spawner` переключает Tab на Spawners, ищет по `kind+ref`.

- [x] **T-16.** В `map_editor_controller.gd`: метод `_eyedropper(coord)`. Приоритет: spawner → object → floor. Дёргает соответствующий `select_*`.

- [x] **T-17.** В `_unhandled_input` LMB pressed: если `mb.alt_pressed` → `_eyedropper(coord)` вместо `_handle_lmb`. `accept_event()`.
  - Зависит от: T-14, T-15, T-16.

### Quick palette select 1-9

- [x] **T-18.** В `floor_palette_panel.gd` и `object_palette_panel.gd`: метод `select_nth(idx: int)`. В `floor` это N-я кнопка в `_tile_grid` (без Erase). В `object` это N-я кнопка в `_content` текущего таба. Out-of-bounds → no-op.

- [x] **T-19.** В `_unhandled_input`: `KEY_1..KEY_9` (без Ctrl/Alt) → роутинг по `_mode`. `PLACING_FLOOR/ERASING_FLOOR/IDLE` → `_floor_palette.select_nth`. `PLACING_OBJECT/PLACING_SPAWNER` → `_object_palette.select_nth`.
  - Зависит от: T-18.

### Hotkey overlay

- [x] **T-20.** Создать `scenes/dev/hotkey_overlay.tscn` — `Control` с полупрозрачным фоном (UiTheme), центрированный VBox с двумя колонками. Корень `mouse_filter = MOUSE_FILTER_IGNORE`.
  - **Скрипт строит UI программно** — отдельный `.tscn` не создавался, вместо этого `HotkeyOverlay` инстанс добавлен прямо в `scenes/dev/map_editor.tscn` как Control со скриптом.

- [x] **T-21.** `scripts/presentation/dev/hotkey_overlay.gd` — заполняет колонки из захардкоженного списка (см. plan.md). `_apply_theme()` подписан на `EventBus.ui_theme_reloaded`.

- [x] **T-22.** В `scenes/dev/map_editor.tscn`: добавить инстанс `HotkeyOverlay` в `HUD`, `visible = false`.

- [x] **T-23.** В контроллере: ссылка `_hotkey_overlay`. `_unhandled_input` ловит `KEY_H` без модификаторов → toggle visible.
  - Зависит от: T-20, T-21, T-22.

### Тематический фон панелей

- [x] **T-24.** `scripts/presentation/ui_theme.gd` → `make_panel_stylebox`: добавить тонкий border (1-2px) акцентным цветом, чуть увеличенный corner_radius, лёгкая внутренняя тень. Если `COL_ACCENT` нет — ввести его. Все панели подхватят через уже существующее `EventBus.ui_theme_reloaded`.
  - Левый border 2px (визуальная spine), corner_radius 4→6, drop-shadow (0,0,0,0.35) с offset (0,2). Без новых констант.

### Силуэты объектов

- [x] **T-25.** Создать `scripts/presentation/dev/object_silhouette.gd` — `Node2D` с `_draw()`. Поля: `shape: StringName`, `color: Color`, `radius: float = 24.0`. Поддерживает фигуры из таблицы plan.md.
  - 9 фигур: circle, diamond, diamond_outline, triangle_tall, triangle_low, triangle_peak, rect_wide, rect_tall, blob.

- [x] **T-26.** В `objects_overlay.gd` заменить ColorRect-плейсхолдер на инстанс `ObjectSilhouette`. Хелпер `_silhouette_for(obj: TileObject) -> Dictionary { "shape", "color" }` — маппинг id→shape и tags→color по таблице plan.md. Fallback на текущий hash-цвет, если тегов нет.
  - Зависит от: T-25.

### Контент

- [x] **T-27.** `data/tile_objects/tree.json` — LARGE, breakable hp 3, tags `["wood", "plant", "flammable"]`, sprite_path empty.

- [x] **T-28.** `data/tile_objects/bush.json` — SMALL walkable, blocks_movement false, tags `["plant", "flammable"]`.

- [x] **T-29.** `data/tile_objects/crystal.json` — LARGE, breakable hp 4, behavior_effect_id `"heal_fountain"`, aura_radius 1, tags `["stone", "construct"]`.

- [x] **T-30.** `data/enemies/skeleton.json` — копия структуры `manekin.json` с другим `id` и базовыми статами (HP побольше). Если schema требует skills — копируем skills манекена для теста.

- [x] **T-31.** `data/enemies/slime.json` — аналогично, низкое HP, медленный.

- [x] **T-32.** `data/enemies/archer.json` — аналогично, ranged-stub если schema это позволяет, иначе minimal copy.
  - Сейчас только `default_melee` behavior существует — archer тоже melee. Стасян/Алексей перенастроят, когда появится ranged behavior.

- [ ] **T-33.** Запустить редактор, убедиться что 3 новых объекта рендерятся силуэтами и 3 новых врага появились в палитре спаунеров. Acceptance #5, #6, #7, #8 (см. spec.md).
  - Зависит от: T-26, T-27..T-32.
  - **Не делалось из контейнера** — нужен Godot, проверка вручную перед PR.

---

## Sanity-чек перед PR

- [ ] **S-01.** Все P1 acceptance criteria (#1-#4) проходят руками.
- [ ] **S-02.** Все P2 acceptance criteria (#5-#8) проходят руками.
- [x] **S-03.** `git push` в `andrey/023-editor-ux-polish` (та же ветка, что immediate fix).
- [ ] **S-04.** PR в staging — Андрей жмёт «Create PR» по URL.
