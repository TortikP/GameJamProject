# 002-hex-grid — tasks

`[P]` — можно делать параллельно с другим тасоком той же фазы. `(depends T0XX)` — нужен предыдущий.

## Фаза 1 — инфраструктурные правки (additive, не breaking)

- [x] T001 [P1] Добавить секцию `[arena]` в `config/game_speed.cfg`
- [x] T002 [P1] [P] Добавить 3 сигнала в `scripts/infrastructure/event_bus.gd`
- [x] T003 [P1] [P] 6 InputAction в `project.godot`: hex_move_top(W), hex_move_top_left(Q),
  hex_move_top_right(E), hex_move_bottom(S), hex_move_bottom_left(A), hex_move_bottom_right(D).

## Фаза 2 — TileSet и тестовые ассеты

- [x] T004 [P1] TileSet TILE_SHAPE_HEXAGON, flat-top — программно в `HexPlaceholderBuilder`
  (нет текстурного атласа без Кати; рантайм-сборка удобнее для демо).
  `.tres` создаётся в редакторе после получения ассетов, HexGrid прочитает его корректно.
- [x] T005 [P1] Custom data layers (walkable, move_cost, tile_kind, effect_id) — в HexPlaceholderBuilder._build_tileset().
- [x] T006 [P1] 5 placeholder-тайлов (grass/wall/swamp/acid/fountain) — TILE_DEFS + GRID_MAP (10×10 layout).

## Фаза 3 — Core scripts

- [x] T007 [P1] [P] `scripts/core/arena/hex_tile.gd` — class_name HexTile
- [x] T008 [P1] [P] `scripts/core/arena/tile_effect_registry.gd` — class_name TileEffectRegistry
- [x] T009 [P1] `scripts/core/arena/hex_pathfinder.gd` — class_name HexPathfinder (wraps AStar2D)
- [x] T010 [P1] `scripts/core/arena/hex_grid.gd` — class_name HexGrid extends Node2D, полное API.
  NOTE: initialize() вместо _ready() — контроллер вызывает явно после подготовки TileSet.

## Фаза 4 — Сцены

- [x] T011 [P1] `scenes/arena/hex_grid.tscn` — HexGrid + Terrain (TileMapLayer) + VFXOverlay + Actors
- [x] T012 [P1] `scripts/presentation/hex_cursor.gd` — Polygon2D, следит за coord_under_mouse()
- [x] T013 [P1] `scenes/arena/hex_grid_demo.tscn` + `scripts/presentation/arena_demo_controller.gd`

## Фаза 5 — Контент эффектов

- [x] T014 [P1] [P] `data/tile_effects/damage_zone.json`
- [x] T015 [P1] [P] `data/tile_effects/heal_fountain.json`

## Фаза 6 — Smoke test и polish

- [ ] T016 [P1] **REQUIRES GODOT EDITOR** — Acceptance run, 7 пунктов из spec.md.
  Ожидаемые правки при первом запуске:
  1. Exported NodePath vars — проверить в Inspector, переназначить если не резолвятся.
  2. Если flat-top даёт pointy-top визуально — поменять TILE_OFFSET_AXIS_VERTICAL на
     TILE_OFFSET_AXIS_HORIZONTAL в HexPlaceholderBuilder._build_tileset().
  3. HexCursor радиус — подогнать под реальный размер тайлов.
- [ ] T017 [P2] [P] Path preview подсветка перед кликом (skip если поджимает)
- [ ] T018 [P2] [P] Difficult-terrain визуальный фидбек
- [ ] T019 [P3] Camera2D pan на drag правой кнопкой
- [ ] T020 [P3] GUT unit-тест pathfinder

## Фаза 7 — PR

- [ ] T021 [P1] push egor/hex-grid → открыть PR в staging
- [ ] T022 [P1] Ревью человеком → merge в staging

## Известные пробелы / осознанно вне фичи

- [ ] T023 [P3] Реальный арт Кати в TileSet — отдельный PR
- [ ] T024 [P3] >1 актёра на гексе
- [ ] T025 [P3] Pointy-top fallback

## Architecture notes

- HexPathfinder предполагает grid-координаты от (0,0). Для offset-гридов — пересмотреть.
- get_neighbor_cell(coord, TileSet.CellNeighbor) — Godot разруливает hex parity сам.
- overlay-эффект приоритетнее static tile effect_id (задокументировано в get_effect_id).
