# 002-hex-grid — tasks

`[P]` — можно делать параллельно с другим тасоком той же фазы. `(depends T0XX)` — нужен предыдущий.

## Фаза 1 — инфраструктурные правки (additive, не breaking)

- [ ] T001 [P1] Добавить секцию `[arena]` в `config/game_speed.cfg`:
  ```
  [arena]
  step_duration=0.18
  path_step_pause=0.05
  hover_highlight_fade=0.1
  ```
- [ ] T002 [P1] [P] Добавить 3 сигнала в `scripts/infrastructure/event_bus.gd`:
  ```gdscript
  # Arena
  signal actor_moved(actor_id: StringName, from: Vector2i, to: Vector2i)
  signal tile_entered(actor_id: StringName, coord: Vector2i)
  signal tile_effect_triggered(actor_id: StringName, coord: Vector2i, effect_id: StringName)
  ```
- [ ] T003 [P1] [P] Добавить 6 InputAction в `project.godot` (через редактор Godot, Project Settings → Input Map):
  `hex_move_top` (W), `hex_move_top_left` (Q), `hex_move_top_right` (E),
  `hex_move_bottom` (S), `hex_move_bottom_left` (A), `hex_move_bottom_right` (D).

## Фаза 2 — TileSet и тестовые ассеты

- [ ] T004 [P1] Создать `scenes/arena/tilesets/hex_terrain.tres`: TileSet с `tile_shape = TILE_SHAPE_HEXAGON`, `tile_offset_axis = TILE_OFFSET_AXIS_VERTICAL` (flat-top). Размер тайла 64×64. (depends T003)
- [ ] T005 [P1] В TileSet добавить custom data layers: `walkable: bool`, `move_cost: int`, `tile_kind: StringName`, `effect_id: StringName`. (depends T004)
- [ ] T006 [P1] Заполнить TileSet 5 placeholder-тайлами (плоские цвета на джем-старте, Катя заменит): `grass` (walkable=true, cost=1), `wall` (walkable=false), `swamp` (walkable=true, cost=2), `acid` (walkable=true, cost=1, effect_id=`damage_zone`), `fountain` (walkable=true, cost=1, effect_id=`heal_fountain`). (depends T005)

## Фаза 3 — Core scripts

- [ ] T007 [P1] [P] `scripts/core/arena/hex_tile.gd` — `class_name HexTile`. Простой data holder: `coord: Vector2i`, `walkable: bool`, `move_cost: int`, `tile_kind: StringName`, `static_effect_id: StringName`.
- [ ] T008 [P1] [P] `scripts/core/arena/tile_effect_registry.gd` — `class_name TileEffectRegistry`. `load_from_dir("res://data/tile_effects/") -> void`, `get(id: StringName) -> Dictionary`. (см. plan §2)
- [ ] T009 [P1] `scripts/core/arena/hex_pathfinder.gd` — `class_name HexPathfinder`. Метод `build(grid: HexGrid) -> void` (поднимает AStar2D), `find_path(from, to) -> Array[Vector2i]`, `update_walkability(coord, walkable: bool)`. (depends T007)
- [ ] T010 [P1] `scripts/core/arena/hex_grid.gd` — `class_name HexGrid extends Node2D`. Полное API из plan §«API контракт». (depends T007, T008, T009)
  - `_ready()`: пробежка `tile_map_layer.get_used_cells()`, заполнение `_tiles`, инициализация `HexPathfinder`, эмит `grid_built`.
  - `place_actor / clear_actor / move_actor / step_actor / get_coord / get_actor_at`.
  - `is_walkable / get_move_cost / get_tile_kind / get_effect_id`.
  - `coord_under_mouse / find_path / size`.
  - `add_overlay_effect / remove_overlay_effect`.
  - `move_actor` использует HexPathfinder, шагает с `await GameSpeed.wait("arena", "step_duration")` * move_cost между шагами; на каждый шаг — emit `actor_step_started` (signal), `actor_step_finished`, `EventBus.actor_moved`, `EventBus.tile_entered`, проверка эффекта → `EventBus.tile_effect_triggered`.

## Фаза 4 — Сцены

- [ ] T011 [P1] `scenes/arena/hex_grid.tscn` — корень `HexGrid` (Node2D со скриптом hex_grid.gd), детьми: TileMapLayer (terrain, ссылка на hex_terrain.tres), TileMapLayer (vfx_overlay), Node2D (`actors` контейнер). (depends T010, T006)
- [ ] T012 [P1] `scripts/presentation/hex_cursor.gd` — Sprite2D-overlay следит за `coord_under_mouse()`, тянет `position = grid.tile_map_layer.map_to_local(coord)`. Прячется при `(-1,-1)`.
- [ ] T013 [P1] `scenes/arena/hex_grid_demo.tscn` — инстансит hex_grid.tscn, рисует 10×10 различными тайлами (1 swamp-кластер, 2 wall-стенки, 1 acid pool, 1 fountain), добавляет тестового актёра (цветной круг ColorRect или Sprite2D), скрипт-контроллер `arena_demo_controller.gd` (`scripts/presentation/`) с input handling (clicks → move_actor; QWE/ASD → step_actor) + слушатель `EventBus.tile_effect_triggered` который пишет в Logger. (depends T011, T012)

## Фаза 5 — Контент эффектов

- [ ] T014 [P1] [P] `data/tile_effects/damage_zone.json`:
  ```json
  {"id":"damage_zone","kind":"damage","amount":5,"applies_to":["player","enemy"]}
  ```
- [ ] T015 [P1] [P] `data/tile_effects/heal_fountain.json`:
  ```json
  {"id":"heal_fountain","kind":"heal","amount":3,"applies_to":["player"]}
  ```

## Фаза 6 — Smoke test и polish

- [ ] T016 [P1] Acceptance run: запустить hex_grid_demo.tscn, пройти все 7 пунктов из spec.md §«Acceptance verification».
- [ ] T017 [P2] [P] Подсветка пути preview перед кликом (наводка → A* строит путь → тонкие точки на пути). Можно опустить если время поджимает.
- [ ] T018 [P2] [P] Difficult-terrain визуальный фидбек: лёгкий ripple/задержка на входе. Можно через `tile_kind`-based SFX.
- [ ] T019 [P3] Camera2D pan на drag правой кнопкой (HANDOFF §9 упоминает; для 10×10 не критично, скорее под будущие большие арены).
- [ ] T020 [P3] Минимальный unit-тест pathfinder через GUT (если время будет — на джеме обычно нет).

## Фаза 7 — PR

- [ ] T021 [P1] Коммит, push в `egor/hex-grid`, открыть PR в `staging`.
- [ ] T022 [P1] Ревью человеком (Андрей или Сергей/Алексей по доступности), merge в staging.

## Известные пробелы / осознанно вне фичи

- [ ] T023 [P3] Реальный арт от Кати в TileSet — придёт отдельным PR в её обмене.
- [ ] T024 [P3] Поддержка > 1 актёра на гексе (нужно для каких-то эффектов?) — пока нет, можно добавить на фазе 5 джема если нужно.
- [ ] T025 [P3] Pointy-top вариант TileSet как альтернативная конфигурация — переключается одной правкой `tile_offset_axis` + ремап InputAction.
