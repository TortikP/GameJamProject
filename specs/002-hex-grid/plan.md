# 002-hex-grid — plan

Решения по 4 вопросам Егора с альтернативами и обоснованием. Дальше — API, файлы, точки интеграции.

Базовая инфра: HANDOFF §6 (autoloads), §9 (стартовая заготовка HexGrid). Этот plan расширяет §9.

Документация Godot 4.6 (читать по мере нужды):
- [TileMapLayer](https://docs.godotengine.org/en/4.6/classes/class_tilemaplayer.html) — `local_to_map`, `map_to_local`, `get_neighbor_cell`, `get_cell_tile_data`.
- [TileSet](https://docs.godotengine.org/en/4.6/classes/class_tileset.html) — `tile_shape = TILE_SHAPE_HEXAGON`, `tile_offset_axis`, `tile_layout`, custom data layers.
- [TileData](https://docs.godotengine.org/en/4.6/classes/class_tiledata.html) — `get_custom_data(layer_name)`.
- [AStar2D](https://docs.godotengine.org/en/4.6/classes/class_astar2d.html) — `add_point`, `connect_points`, `get_id_path`, `set_point_weight_scale`.
- [Red Blob Hexagons](https://www.redblobgames.com/grids/hexagons/) — общая теория, особенно секции про offset/cube coordinates и направления.

---

## §1. Слои тайлов: один TileMapLayer + custom data + runtime mirror

### Решение

**Один TileMapLayer для местности**, в TileSet — custom data layers:
- `walkable: bool`
- `move_cost: int` (1 = норма, 2+ = difficult, при `walkable=false` игнорируется)
- `tile_kind: StringName` (`grass`, `wall`, `swamp`, `lava`, `ice`, ...) — для будущей логики и SFX
- `effect_id: StringName` (пусто для нейтральных, `damage_zone` / `heal_fountain` / ... — static-эффекты)

При `_ready()` HexGrid единократно пробегает все cells через `get_used_cells()` и строит `_tiles: Dictionary[Vector2i, HexTile]` — рантайм-зеркало для `O(1)` query. TileMapLayer трогаем только если меняется визуал.

Параллельно — **второй TileMapLayer для VFX-оверлея** (анимации эффектов, подсветка, маршрут): чисто визуальный, логика его не читает.

### Альтернативы и почему отброшены

| Вариант | Плюсы | Минусы | Вердикт |
|---|---|---|---|
| **N TileMapLayer per kind** (passable/blocked/difficult — 3 слоя) | Хорошо красить в редакторе одним кликом «выбрать слой» | `is_walkable(coord)` = опросить N слоёв; смешанные случаи (difficult + effect) требуют > 1 слоя; рантайм-overlay из эффектов всё равно нужен | Нет |
| **Полный класс `Tile` без TileMapLayer** | Гибкость, можно процедурно генерировать | Теряем редакторное painting от Кати; надо самим рисовать сетку через Sprite2D + ручной hit-test | Нет, Катя красит в редакторе |
| **TileMapLayer + TileData custom data** (выбран) | Painting в редакторе; query через `get_cell_tile_data().get_custom_data(...)`; runtime mirror = `O(1)` | Custom data layers надо настроить руками в TileSet один раз | **Да** |

### Dynamic effects (acid pool после взрыва врага)

Не пишем в TileMapLayer (это карта дизайнера, не рантайм-состояние). Отдельный `_overlay_effects: Dictionary[Vector2i, EffectInstance]` в HexGrid. На вход актёра проверяем: сначала overlay, потом static `effect_id` из TileData. VFX-слой опционально показывает оверлей-эффекты.

---

## §2. Тайл-эффекты: data-driven JSON, HexGrid только эмитит

### Поток

1. Актёр входит на тайл → `move_actor(id, to)` атомарно: меняет `_actor_positions`, эмитит `actor_moved`, эмитит `tile_entered`, ищет static `effect_id` или overlay → если есть, эмитит `tile_effect_triggered(id, coord, effect_id)`.
2. Логика урона/хила/статуса живёт **снаружи** (PlayerController, EnemyController, StatusSystem). HexGrid не знает про HP — он знает про `effect_id` как строку.
3. Кто и сколько лечится/получает урона — определяет JSON-файл эффекта + слушатель.

### `data/tile_effects/*.json` (формат)

```json
{
  "id": "damage_zone",
  "kind": "damage",
  "amount": 5,
  "applies_to": ["player", "enemy"],
  "vfx": "res://assets/vfx/acid_splash.tscn",
  "sfx": "res://assets/audio/sfx/acid.ogg"
}
```

Под джем нужно 2-3 примера (`damage_zone`, `heal_fountain`). Стасян потом досыпет контент.

### Ответственности

- **HexGrid** — знает `effect_id` на координате, эмитит сигнал.
- **TileEffectRegistry** (новый, `scripts/core/arena/tile_effect_registry.gd`) — грузит JSON в `Dictionary[StringName, Dictionary]`, отдаёт по `id`.
- **Кто-то снаружи** (стартово — `arena_demo_controller.gd`, потом — реальный battle controller) — слушает `tile_effect_triggered`, тянет данные из реестра, применяет.

Регистрация TileEffectRegistry — обычный `class_name`, не autoload. На джеме экземпляр живёт на сцене HexGrid или подгружается напрямую.

---

## §3. Отслеживание позиций акторов

### State

```gdscript
var _actor_positions: Dictionary[StringName, Vector2i] = {}   # id -> coord
var _occupants: Dictionary[Vector2i, StringName] = {}          # coord -> id
```

Двусторонний словарь — `O(1)` в обе стороны. Инвариант: `_actor_positions[id] == coord` ⇔ `_occupants[coord] == id`. Если ломается — `Logger.error`.

### API (HexGrid)

```gdscript
func place_actor(id: StringName, coord: Vector2i) -> bool       # false если занято/невалидно
func clear_actor(id: StringName) -> void
func move_actor(id: StringName, to: Vector2i) -> void           # async, async path traversal
func step_actor(id: StringName, neighbor: TileSet.CellNeighbor) -> bool   # одиночный шаг для клавиатуры
func get_coord(id: StringName) -> Vector2i                      # Vector2i(-1,-1) если не размещён
func get_actor_at(coord: Vector2i) -> StringName                # &"" если пусто
```

Правило: **только grid меняет позиции**. Никто не пишет напрямую в Sprite2D.position актёра — позиция актёра = `map_to_local(coord)`, всё движение оркестрирует grid.

`actor_id` — `StringName` (`&"player"`, `&"enemy_3"`). Уникальный в пределах сцены. Без нэймспейсов в этом джеме.

---

## §4. Pathfinding и input

### Pathfinding (`scripts/core/arena/hex_pathfinder.gd`)

`AStar2D` с инициализацией от HexGrid:
1. `add_point(idx, Vector3(coord.x, coord.y, 0))` для каждого walkable coord. `idx` = плоский индекс `coord.y * width + coord.x` (sentinel function).
2. Для каждого walkable coord — `connect_points` с walkable-соседями через `TileMapLayer.get_neighbor_cell(coord, neighbor)`.
3. `set_point_weight_scale(idx, move_cost)` — difficult terrain получает вес 2+.
4. На спавн/удаление dynamic blocker (например, в overlay) — `set_point_disabled` или `disconnect_points`.

`find_path(from, to) -> Array[Vector2i]`. Возвращает пустой массив, если недостижимо.

Не используем `AStarGrid2D` — он строго прямоугольный, для гекса не подходит.

### Mouse

- В `_unhandled_input` ловим `InputEventMouseMotion` → `coord_under_mouse()` через `tile_map_layer.local_to_map(tile_map_layer.to_local(event.position))`. Подсветка — VFX-слой.
- `InputEventMouseButton.pressed && button_index == LEFT` → `_on_click(coord)` → `find_path` → `move_actor(actor, target)` который сам анимирует traversal.

### Keyboard: 6 направлений на 6 клавишах (flat-top hex, QWE/ASD)

**Решение: flat-top hex + Q/W/E/A/S/D как 6-key layout.**

```
   W           ↑ TOP (CELL_NEIGHBOR_TOP_SIDE)
 Q   E         ↖ TOP_LEFT_SIDE   ↗ TOP_RIGHT_SIDE
   ◯
 A   D         ↙ BOTTOM_LEFT     ↘ BOTTOM_RIGHT
   S           ↓ BOTTOM
```

Q/W/E/A/S/D физически складываются в гексаграмму на клавиатуре — 1-к-1 соответствие визуальным соседям на экране. Mapping в `project.godot` как `InputAction`:

```
hex_move_top_left, hex_move_top, hex_move_top_right,
hex_move_bottom_left, hex_move_bottom, hex_move_bottom_right
```

Внутри `_unhandled_input`:
```gdscript
if Input.is_action_just_pressed("hex_move_top"):
    step_actor(player_id, TileSet.CELL_NEIGHBOR_TOP_SIDE)
# ... ×6
```

Сосед получаем через `TileMapLayer.get_neighbor_cell(coord, TileSet.CellNeighbor)` — Godot сам разруливает offset/parity, мы не пишем direction-таблицу руками.

### Альтернативы для 4→6 проблемы

| Вариант | Плюсы | Минусы | Вердикт |
|---|---|---|---|
| **WASD-only**, ↑/↓/←/→ → ближайший hex-сосед (евристика по углу или parity) | Использует знакомые клавиши, не учить | Потеря 2 направлений или непредсказуемое поведение в blocked-ситуациях; чувствуется поломанным | Нет |
| **WASD + Q/E** — только 2 диагонали | На 1 клавишу меньше | Асимметрично визуально, путает | Нет |
| **Numpad 7/9/4/6/1/3** | Идеально совпадает с pointy-top | Без numpad — никак (ноуты) | Нет |
| **WASD + tap-tap** (W,A = top-left) | Только 4 клавиши | Лаг, фрустрация | Нет |
| **Hex-aware WASD: A/D в ряду, W/S диагональ + контекст по кнопке Shift** | Менее экзотично | 6-я клавиша всё равно нужна; модификаторы ломают muscle memory | Нет |
| **6-key Q/W/E/A/S/D**, flat-top (выбран) | Визуально-моторное соответствие; одна клавиша = один шаг; стандарт у roguelike-сообщества | Чуть-чуть учить (2 минуты) | **Да** |

### Pointy-top как fallback

Если по плейтесту flat-top плохо ложится визуально (часто хуже на 16:9 экране без масштаба) — TileSet перенастраивается на pointy-top, mapping становится:
```
Q W            ↖ TOP_LEFT   ↗ TOP_RIGHT
A   D          ← LEFT       → RIGHT
Z X            ↙ BOTTOM_LEFT ↘ BOTTOM_RIGHT
```
Меняются только `InputAction` definitions и одна строчка в TileSet. Стартуем с flat-top.

### Animation pacing

`step_actor` и `move_actor` тween-ят `actor.position` от `map_to_local(from)` к `map_to_local(to)` за `GameSpeed.get_value("arena", "step_duration", 0.18)`. На path traversal — последовательный await каждого шага через `GameSpeed.wait("arena", "step_duration")`. Difficult terrain → `step_duration * move_cost`.

Анимируем через `create_tween().tween_property(...)` — встроено, без addon'ов.

---

## API контракт (фиксируем для остальных модулей)

### `class_name HexGrid extends Node2D`

Публично:
```gdscript
signal grid_built                                                # после _ready
signal actor_step_started(actor_id: StringName, from: Vector2i, to: Vector2i)
signal actor_step_finished(actor_id: StringName, coord: Vector2i)

func place_actor(id: StringName, coord: Vector2i) -> bool
func clear_actor(id: StringName) -> void
func move_actor(id: StringName, to: Vector2i) -> void            # async, использует pathfinder
func step_actor(id: StringName, neighbor: int) -> bool           # int = TileSet.CellNeighbor
func get_coord(id: StringName) -> Vector2i
func get_actor_at(coord: Vector2i) -> StringName

func is_walkable(coord: Vector2i) -> bool
func get_move_cost(coord: Vector2i) -> int
func get_tile_kind(coord: Vector2i) -> StringName
func get_effect_id(coord: Vector2i) -> StringName

func coord_under_mouse() -> Vector2i                             # (-1,-1) если вне
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]
func size() -> Vector2i                                          # (width, height)

func add_overlay_effect(coord: Vector2i, effect_id: StringName) -> void
func remove_overlay_effect(coord: Vector2i) -> void
```

### EventBus (additive)

Добавить в `scripts/infrastructure/event_bus.gd`:
```gdscript
# Arena
signal actor_moved(actor_id: StringName, from: Vector2i, to: Vector2i)
signal tile_entered(actor_id: StringName, coord: Vector2i)
signal tile_effect_triggered(actor_id: StringName, coord: Vector2i, effect_id: StringName)
```
Не breaking — только добавление. Подписчики появятся в 004/005.

### GameSpeed (additive)

Добавить секцию в `config/game_speed.cfg`:
```
[arena]
step_duration=0.18
path_step_pause=0.05
hover_highlight_fade=0.1
```

---

## Файловая структура

```
scripts/core/arena/
├── hex_grid.gd                  # class_name HexGrid
├── hex_tile.gd                  # class_name HexTile (data holder)
├── hex_pathfinder.gd            # class_name HexPathfinder (wraps AStar2D)
└── tile_effect_registry.gd      # class_name TileEffectRegistry (loads JSON)

scenes/arena/
├── hex_grid.tscn                # переиспользуемая сцена с TileMapLayer + HexGrid script
├── hex_grid_demo.tscn           # demo с актёром, тестовыми тайлами и input
└── tilesets/
    └── hex_terrain.tres         # TileSet с 5+ тайлами и custom data layers

data/tile_effects/
├── damage_zone.json
└── heal_fountain.json

scripts/presentation/
└── hex_cursor.gd                # подсветка под курсором, путь preview (опционально)
```

---

## Точки интеграции

- **Battle controller** (фича 005-roguelike-loop) — слушает `tile_effect_triggered` для применения урона/хила.
- **Spell engine** (фича 004) — спрашивает `is_walkable`, `find_path`, `get_actor_at` для targeting.
- **Enemy AI** (часть фичи 005, owner Egor) — использует `find_path`, `step_actor`.
- **Audio** — слушает `actor_step_started` для footstep SFX (по `tile_kind`).

---

## Риски

- **Hex offset coord parity** легко ошибиться вручную → используем `TileMapLayer.get_neighbor_cell` всегда, не пишем offset-таблицу.
- **AStar2D rebuild на каждое изменение проходимости** дорого на 10×10 — но 100 точек, не проблема. Для 30×30 — пересмотрим.
- **Перекрытие static и overlay-эффекта** — приоритет overlay > static, документируем явно.
- **Анимация шага vs логика хода** — пока ход ≠ wait’а анимации (мир тикает только когда игрок шагает, см. концепт §«Боёвка»). Это решит battle controller, не grid. Grid просто эмитит сигналы и ждёт следующего вызова.
