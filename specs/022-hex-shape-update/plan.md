# 022-hex-shape-update — plan

## Контракт хелпера

Новый файл: `scripts/infrastructure/hex_geometry.gd`. Без `class_name` и без autoload — паттерн `GameLogger` (см. CLAUDE.md, traps table: `class_name HexGeometry` теоретически безопасно, но пресет «utility = preload» — наш стандарт, не нарушаем).

```gdscript
# scripts/infrastructure/hex_geometry.gd
extends Object

## Flat-top hexagon inscribed in the bounding box (tile_size).
## Vertices в порядке против часовой (Godot Y-down): (R, 0), (R/2, H/2),
## (-R/2, H/2), (-R, 0), (-R/2, -H/2), (R/2, -H/2).
##
## Use:
##   const HexGeometry = preload("res://scripts/infrastructure/hex_geometry.gd")
##   var pts := HexGeometry.flat_top_polygon(layer.tile_set.tile_size)
##
## Если нужно для overlay'а без прямого доступа к TileMapLayer — родитель
## обычно HexGrid, читай `get_parent().tile_map_layer.tile_set.tile_size`.
static func flat_top_polygon(tile_size: Vector2) -> PackedVector2Array:
    var hw: float = tile_size.x * 0.5
    var hh: float = tile_size.y * 0.5
    var pts := PackedVector2Array()
    pts.append(Vector2( hw,    0.0))
    pts.append(Vector2( hw*0.5, hh))
    pts.append(Vector2(-hw*0.5, hh))
    pts.append(Vector2(-hw,    0.0))
    pts.append(Vector2(-hw*0.5,-hh))
    pts.append(Vector2( hw*0.5,-hh))
    return pts
```

Почему вершины именно так: для flat-top гекса, вписанного в bbox `(W, H)`, две вершины лежат на `(±W/2, 0)`, остальные четыре — на `(±W/4, ±H/2)`. Это не правильный шестиугольник в общем случае (правильный = `H = W·√3/2 ≈ 0.866·W`), и нам это **нужно**: атлас Кати «приплюснутый», `H/W < 0.866`.

Проверка: для godmode 128×112 → `H/W = 0.875` (почти правильный, чуть растянут по Y). Для нового атласа Кати, скажем 128×80 → `H/W = 0.625`, заметно flatter — но формула одна.

Старый код `Vector2(cos(a)*R, sin(a)*R)` — это правильный шестиугольник с `H = W·√3/2`. У нашего хелпера для **квадратного** bbox получится не правильный шестиугольник, а растянутый. Если кому-то понадобится правильный гекс по circumradius — добавит вторую функцию. Сейчас не нужно.

## Источник tile_size в каждом overlay

| Overlay | Текущий доступ к Grid | Источник tile_size при draw |
|---|---|---|
| `hex_cursor.gd` | `@export var grid: HexGrid` | `grid.tile_map_layer.tile_set.tile_size` |
| `hover_highlight.gd` | `@export var grid: HexGrid` | то же |
| `delete_highlight.gd` | `@export var grid: HexGrid` | то же |
| `move_range_overlay.gd` | `setup(grid)` сохраняет в `_grid` | `_grid.tile_map_layer.tile_set.tile_size` |
| `cast_range_overlay.gd` | `setup(grid)` → `_grid` | то же |
| `telegraph_hex.gd` | **нет ссылки.** Создаётся в `godmode_controller._update_telegraphs()`, добавляется как child в `grid` | использовать `get_parent()` cast в `HexGrid` (родитель — сам HexGrid в текущей разводке). На случай null — fallback на `Vector2(120, 104)` + лог через GameLogger.warn |

Альтернативы для telegraph_hex рассмотрены и отброшены:
- Передавать tile_size через сеттер из контроллера — лишняя сцепленность, +1 место правки при каждом spawn.
- Сделать `@export var grid` — телеграф создаётся через `Script.new()`, экспорты надо назначать вручную, +строка кода в каждом spawn.
- `get_parent()` — текущий контракт уже это гарантирует (`grid.add_child(hex)` в godmode_controller:910). Если контракт сломают в будущем — fallback + warn ловит.

## Order of operations при `tile_size` change в runtime

Godmode swap:
1. `godmode_controller._ready()` ставит `grid.tile_map_layer.tile_set = GODMODE_TERRAIN`.
2. Оверлеи добавляются как дети HexGrid после этого.
3. Их первый `_draw()` уже видит правильный tile_set.

Map editor swap (если в будущем будет менять тайлсет на лету): после смены `tile_set` контроллер должен пройтись по детям HexGrid и вызвать `queue_redraw()` на тех, что наследуют Node2D и реализуют `_draw()`. **В рамках этой спеки не делаем** — ни одно текущее место не свопает tile_set после init. Если 020-map-editor добавит — это его задача, отметить в его spec.

## Файлы / порядок правок

1. Создать `scripts/infrastructure/hex_geometry.gd`.
2. `scripts/presentation/hex_cursor.gd` — убрать `HEX_RADIUS`, использовать helper. Внимание: cursor имеет 4 режима (IDLE / VALID / INVALID / INSPECT), INSPECT рисует corner-brackets — там тоже `HEX_RADIUS` фигурирует или нет? Проверить.
3. `scripts/presentation/dev/hover_highlight.gd` — то же.
4. `scripts/presentation/dev/delete_highlight.gd` — то же.
5. `scripts/presentation/godmode/move_range_overlay.gd` — то же. Проверить, что `setup(grid)` точно вызывается до первого `_draw()` (он вызывается из godmode_controller на init).
6. `scripts/presentation/cast_range_overlay.gd` — то же.
7. `scripts/presentation/telegraph_hex.gd` — добавить `_get_tile_size() -> Vector2` через `get_parent()`. Учесть: метка damage позиционируется как `Vector2(-size.x*0.5, -RADIUS - 6.0)` — заменить `RADIUS` на `tile_size.y * 0.5`.
8. CLAUDE.md — добавить строку в Architecture rules: «Hex polygon geometry — `HexGeometry.flat_top_polygon(layer.tile_set.tile_size)`. Не хардкодим радиус».

## Risks / unknowns

- **Низкий**: `get_parent() as HexGrid` в telegraph_hex может вернуть null, если кто-то изменит spawn-сайт. Fallback + warn покрывает.
- **Низкий**: после правки оверлеи в `hex_grid_demo.tscn` (арена 64×56) внезапно станут вдвое меньше — это правильно (исправление существующего бага), но визуально удивит. Smoke-test: проверить, что ничего не выглядит сломанно.
- **Близко к нулю**: TileSet может быть null в момент _draw() (race на init). Все callsite-ы и так проверяют `tile_map_layer != null`, добавим парный `tile_set != null`.

## Links

- Godot 4.6 [`TileSet.tile_size`](https://docs.godotengine.org/en/4.6/classes/class_tileset.html#class-tileset-property-tile-size)
- Godot 4.6 [`TileMapLayer.tile_set`](https://docs.godotengine.org/en/4.6/classes/class_tilemaplayer.html#class-tilemaplayer-property-tile-set)
- Red Blob — [Hex Geometry](https://www.redblobgames.com/grids/hexagons/#basics) (только секция «Size and Spacing»)
- HANDOFF.md §9 «HexGrid» — сам модуль не трогаем, только overlay'и поверх него.
- CLAUDE.md «Known Godot 4.6 traps» — `class_name` collision rule (почему utility-helper без class_name).
