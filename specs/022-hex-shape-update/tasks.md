# 022-hex-shape-update — tasks

- [ ] T001 — Создать `scripts/infrastructure/hex_geometry.gd` с `flat_top_polygon(tile_size: Vector2) -> PackedVector2Array`. Без `class_name`, без autoload (паттерн GameLogger).
- [ ] T002 — `scripts/presentation/hex_cursor.gd`: убрать `HEX_RADIUS`, читать tile_size из `grid.tile_map_layer.tile_set.tile_size`, переписать `_draw()` (включая INSPECT corner-brackets, если они тоже от радиуса считаются).
- [ ] T003 — `scripts/presentation/dev/hover_highlight.gd`: убрать `HEX_RADIUS`, заменить цикл `cos/sin` на `HexGeometry.flat_top_polygon(...)`. Проверить, что `_draw` вызывается через `queue_redraw` (если нет — добавить в `_process` после смены координат).
- [ ] T004 — `scripts/presentation/dev/delete_highlight.gd`: то же.
- [ ] T005 — `scripts/presentation/godmode/move_range_overlay.gd`: убрать `RADIUS`, использовать `_grid.tile_map_layer.tile_set.tile_size`. Полигоны создаются через `Polygon2D.new()` + `pgon.polygon = pts` — pts строим хелпером.
- [ ] T006 — `scripts/presentation/cast_range_overlay.gd`: то же.
- [ ] T007 — `scripts/presentation/telegraph_hex.gd`: убрать `RADIUS`, добавить `_get_tile_size()` через `get_parent() as HexGrid` с fallback Vector2(120, 104) + `GameLogger.warn("TelegraphHex", "no parent HexGrid, using fallback tile_size")`. Заменить `-RADIUS - 6.0` в позиции лейбла damage на `-tile_size.y * 0.5 - 6.0`.
- [ ] T008 — `grep -rn "RADIUS" scripts/presentation/` → должен вернуть только то, что не относится к гекс-радиусу (UiTheme константы, PADDING_*, и т.п.). Подтвердить AC-1.
- [ ] T009 — Smoke-test (вручную, в Godot): открыть `scenes/dev/godmode.tscn`, поводить мышью, селектнуть актёра, посмотреть move-range, нажать Q-W-E-R, посмотреть cast-range, дождаться телеграфа от врага. Никаких визуальных глюков.
- [ ] T010 — Smoke-test (вручную): открыть `scenes/arena/hex_grid_demo.tscn`, мышь над клеткой → курсор в клетке (не в 2 раза больше). До правки был баг: курсор был 60-радиуса при тайле 64×56 (≈ 2× больше). Сейчас должен сидеть впритык к границам.
- [ ] T011 — Smoke-test (вручную): открыть `scenes/dev/map_editor.tscn`, нажать каждую кнопку палитры (Godmode Terrain / Hex Terrain), убедиться что hover/delete-highlight перерисовывается под новый размер. Если не перерисовывается — добавить `queue_redraw()` после смены тайлсета в map_editor_controller (это уже в скоупе 020, но если упёрлись — фиксим здесь же).
- [ ] T012 — Doc: добавить строку в `CLAUDE.md` секцию «Architecture» (после правила 5 про UiTheme): «6. Hex polygon geometry — через `HexGeometry.flat_top_polygon(layer.tile_set.tile_size)`. Не хардкодим радиус: tile_size — единственный источник правды».
- [ ] T013 — Commit + push, забрать PR-URL из stderr `git push`, отдать Andrey.

## Dependencies

- T001 → T002..T007 (хелпер первый).
- T008 после T002..T007.
- T009..T011 после T008.
- T012 — независимо, можно в любой момент.
- T013 — последний.

## Notes

- Никаких правок `core/` — там ничего и не было хардкода, всё через `tile_map_layer.map_to_local()`.
- Никаких правок `data/` — это код-only фича.
- Никаких правок `.tres` — `tile_size` остаётся какой был, фиксим только что код этому tile_size доверяет.
- Если по ходу find выскочит ещё файл с радиусом гекса — добавить таску, не отдельную спеку.
