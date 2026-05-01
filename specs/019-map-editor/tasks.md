# 019-map-editor — tasks

**Spec:** [`spec.md`](./spec.md) — **Plan:** [`plan.md`](./plan.md)

> Implement-режим: один таск за раз, отметить `[x]` когда работает (или `[~]` если частично — с пометкой что не доделано). Не ломиться через всё одним рывком — после каждого `[~]`/блокера остановиться, синхронизироваться.

## Phase 0 — Data layer (~2-3 ч)

- [ ] **T001** [P1] `scripts/core/maps/level_data.gd` — `class_name LevelData`, поля + `validate()` + `to_dict()` / `from_dict()` (см. plan.md API)
- [ ] **T002** [P1] `scripts/core/maps/level_serializer.gd` — `static save() / load()`, JSON через `JSON.stringify(d, "\t")`, FileAccess errors → GameLogger.error (depends T001)
- [ ] **T003** [P1] `scripts/infrastructure/active_level.gd` — autoload, queued_path slot, queue/consume/has_queued/clear
- [ ] **T004** [P1] `project.godot` — register `ActiveLevel` autoload (depends T003)
- [ ] **T005** [P1] `scripts/core/maps/level_loader.gd` — `static apply_to(grid, registry, level)`. Floor paint → grid.initialize() (caller does it) → set_tile_object loop → spawn player + enemies (depends T001, hex_grid setter T006)
- [ ] **T006** [P1] `scripts/core/arena/hex_grid.gd` — `set_tile_object(coord, object_id)` setter + rebuild_pathfinder. Plus optional `apply_level_data` thin wrapper (depends 002 hex_grid existing)
- [ ] **T007** [P2] `data/maps/_schema.md` — schema doc для Стасяна, 1:1 c LevelData

## Phase 1 — Editor scene scaffolding (~2 ч)

- [ ] **T008** [P1] `scenes/dev/map_editor.tscn` — root Node2D + Camera2D + HexGrid инстанс + HUD CanvasLayer заглушки (no UI yet) (depends 002)
- [ ] **T009** [P1] `scripts/presentation/dev/map_editor_controller.gd` — _ready: resolve nodes, initial 5×5 grass paint, no input yet (depends T008)
- [ ] **T010** [P1] `scripts/presentation/dev/objects_overlay.gd` — Node2D, метод `set_object(coord, object_id)` спавнит/заменяет Sprite2D ребёнка с texture из `TileObject.sprite_path` (depends T009)
- [ ] **T011** [P1] `scripts/presentation/dev/spawners_overlay.gd` — то же для спавнеров (player Unicode-глиф, enemy с тинтом по hash) (depends T010)
- [ ] **T012** [P1] `scripts/presentation/dev/hover_highlight.gd` — рисует контур текущего гекса под курсором (depends T009)
- [ ] **T013** [P1] `scripts/presentation/dev/delete_highlight.gd` — рисует красный заполненный полигон отмеченного гекса (depends T009)

## Phase 2 — Input + state machine (~3 ч)

- [ ] **T014** [P1] State machine enum + переменные в map_editor_controller.gd (см. plan.md) (depends T009)
- [ ] **T015** [P1] LMB place handler — таблица из plan.md. Floor / Object / Spawner placement пути (depends T014)
- [ ] **T016** [P1] RMB pending-delete + повторное удаление + переключение на новый гекс. LMB сбрасывает pending (depends T014)
- [ ] **T017** [P1] Collision popup — простой ConfirmModal с одной кнопкой OK при попытке поставить на занятый тайл (depends 009 ConfirmModal)
- [ ] **T018** [P1] Player spawner singleton — при placement, если уже стоит, удалить старый (с 200ms fade-out опционально) (depends T015)
- [ ] **T019** [P3] Drag-and-drop существующих объектов — IDLE LMB-press → grab → ghost preview → release. **STRETCH, не делать в первом проходе** (depends T015)

## Phase 3 — Palette UI (~3-4 ч)

- [ ] **T020** [P1] `floor_palette_panel.gd` + scene — TileSet dropdown, кнопки тайлов из выбранного TileSet (рендерим превьюшки из атласа), Erase кнопка (depends T009)
- [ ] **T021** [P1] `object_palette_panel.gd` — TabBar (Spawners / Obstacles / Interactive), filter row (3 type checkboxes + Has-effect), категоризация из plan.md (depends 018 TileObjectRegistry)
- [ ] **T022** [P1] Spawners tab content — `_build_spawner_list()` из `data/enemies/*.json` + player (depends T021)
- [ ] **T023** [P1] Obstacles + Interactive tab content — `TileObjectRegistry.all()` через категоризатор + filter (depends T021)
- [ ] **T024** [P1] Wire palette selections → controller mode (PLACING_FLOOR / PLACING_OBJECT / PLACING_SPAWNER / ERASING_FLOOR) (depends T015, T020, T021)

## Phase 4 — Meta panel + Save/Load (~2 ч)

- [ ] **T025** [P1] `level_meta_panel.gd` + scene — name input + 4 кнопки (Save / Load / Playtest / Exit) — стилизация через UiTheme (depends T009)
- [ ] **T026** [P1] Save flow — sanitize + validate + ConfirmModal на overwrite + LevelSerializer.save + toast (depends T002, T025)
- [ ] **T027** [P1] Load flow (editor) — dirty check + confirm-save + FileDialog + LevelSerializer.load + apply to editor (depends T002, T025)
- [ ] **T028** [P1] Playtest flow — validate + write `__playtest__.json` + ActiveLevel.queue + change_scene godmode (depends T026, T003)
- [ ] **T029** [P1] Add `__playtest__.json` to `.gitignore` (depends T028)

## Phase 5 — Game-side integration (~1-2 ч)

- [ ] **T030** [P1] `godmode_controller.gd` — patch `_ready()`: ActiveLevel.has_queued() → load path; иначе оригинальный paint+place (см. plan.md). Тщательно протестировать что non-queued path 1:1 как до патча (depends T005, T003)
- [ ] **T031** [P1] `main_menu.gd` + `main_menu.tscn` — добавить `MapEditorButton` (text `"Map Editor [Ctrl+E]"`) и `LoadCustomLevelButton` + handlers (depends T028)
- [ ] **T032** [P1] `project.godot` — input action `dev_open_editor` (Ctrl+E) (depends T031)
- [ ] **T033** [P1] Hotkey listener в `main_menu.gd`, `map_editor_controller.gd`, `godmode_controller.gd`. В редакторе — no-op (уже здесь). В остальных — change_scene → map_editor (depends T032)
- [ ] **T034** [P2] `config/game_speed.cfg` — секция `[editor]` с `spawner_swap=0.2`, `place_feedback=0.05`, `hover_pulse=0.6`. Использовать в overlay'ях через `GameSpeed.get_value("editor", key)` (если ключ отсутствует — graceful default)

## Phase 6 — Sample + smoke (~1 ч)

- [ ] **T035** [P1] `data/maps/sample.json` — рукотворная карта 8×6 с player + 2 manekin + lava_pool + wooden_barrel (см. plan.md)
- [ ] **T036** [P1] Smoke (manual): главное меню → Load Custom Level → sample.json → бой стартует на этой карте, player и манекены в правильных позициях, lava_pool блокирует движение по своему хексу
- [ ] **T037** [P1] Smoke (manual): Ctrl+E из главного меню → редактор → нарисовать пол → положить player + manekin + объект → Save "smoke_test" → файл в `data/maps/smoke_test.json` валидный JSON
- [ ] **T038** [P1] Smoke (manual): редактор → Playtest на свежей карте без сохранения → бой стартует (через `__playtest__.json`)
- [ ] **T039** [P1] Smoke (manual): редактор → попытка Save без player-спавнера → toast warn, файл не пишется
- [ ] **T040** [P1] Smoke (manual): редактор → положить объект → попытка положить второй на тот же хекс → ConfirmModal «Тайл занят»
- [ ] **T041** [P1] Smoke (manual): редактор → RMB по объекту (красный) → второй RMB → объект исчез
- [ ] **T042** [P1] Smoke (manual): редактор → RMB → LMB по другому хексу с тайлом-в-палитре → highlight снят, тайл положен
- [ ] **T043** [P2] Update HANDOFF.md §18 — упомянуть 019 в работе / смержено

## Phase 7 — Стасян onboarding (~30 мин, не блокер)

- [ ] **T044** [P2] После мержа: пинг Стасяну в Discord, ссылка на `data/maps/_schema.md`, краткая записка как открыть редактор (Ctrl+E или Map Editor button), и «делай карты, я буду их PR-нуть».

## Зависимости — критический путь

```
T001 → T002 → T026, T027, T028
T003 → T004, T028, T030
T006 → T005 → T030, T028
T009 → T010, T011, T014, T020, T021, T025
T021 → T024
T015 + T024 → T028
T030 + T031 → T036, T038
```

Параллелизация:
- Один человек может вести phase 0+1 (data + scaffolding), второй параллельно phase 3 (UI палитра), пересечение в phase 4 на wiring.
- Альтернатива: одиночная работа Андреем в порядке T001 → ... → T043 — реалистичный объём 12-16 ч чистого времени.

## Где остановиться если время кончается

Минимально работающий редактор (cut order):
1. Сначала отрезать **T019** (drag-existing) — чисто quality-of-life.
2. Затем **T013 → T012** — overlays приятные но не критичные (LMB всё равно работает без визуала pending-delete? нет, T013 нужен для UX RMB. Не резать).
3. **T034** — game_speed для editor — не блокер, hardcode 0.2 fallback в коде.
4. **T020 (Erase кнопка)** в floor palette — без неё работает, но удалять пол через RMB-двойной можно.

Минимальная демоверсия:
- T001-T011 (data + scaffolding + overlays)
- T014-T018 (input + collision)
- T020-T024 (palettes minimum)
- T025-T028 (save + load + playtest)
- T030-T033 (game integration + main menu)
- T035-T038 (sample + 3 smokes)

= 22 P1-таска, ~10-12 ч одного человека.
