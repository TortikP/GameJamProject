# 018-tile-objects — plan

**Spec:** [`spec.md`](./spec.md)

> Plan v2 — учитывает разрешение OQ-1=A (aura, configurable radius), OQ-2=C+linger (combined on_enter+turn_end DoT + actor-side linger status), OQ-3=A (one object per tile). Маркеры [DEPENDS-OQ] убраны.

## Файлы

| Путь | Что | Размер |
|---|---|---|
| `scripts/core/arena/tile_object.gd` | NEW pure data class | ~40 строк |
| `scripts/core/arena/tile_object_registry.gd` | NEW JSON loader (паттерн из `tile_effect_registry.gd`) | ~80 строк |
| `scripts/core/arena/hex_tile.gd` | +1 поле `object_id: StringName`, +1 параметр в `_init` | +3 |
| `scripts/core/arena/hex_grid.gd` | в `_build_tile_map` читать custom data layer "object_id" | +5 |
| `scripts/core/arena/hex_pathfinder.gd` | injected dep `TileObjectRegistry`, в проверке проходимости — query объект | +10 |
| `scripts/infrastructure/event_bus.gd` | +4 сигнала per AC-O7 | +6 |
| `data/tile_objects/_schema.md` | NEW schema doc для Стасяна | ~80 строк |
| `data/tile_objects/mountain.json` | NEW sample | ~10 |
| `data/tile_objects/lava_pool.json` | NEW sample | ~15 |
| `data/tile_objects/heal_fountain.json` | NEW sample (имя коллидит с tile_effects/heal_fountain.json — намеренно, разные регистры, разные namespace) | ~15 |
| `data/tile_objects/wooden_barrel.json` | NEW sample | ~18 |
| `data/tile_objects/wooden_table.json` | NEW sample | ~12 |
| `data/tile_objects/boulder.json` | NEW sample | ~12 |
| `scenes/dev/tile_objects_smoke.tscn` | NEW dev-scene для smoke per AC-O8 | scene file |

Итого: 8 кода / 7 контента / 1 dev-сцена. Чисто additive — переименований/удалений нет.

## TileObject API

```gdscript
class_name TileObject

## Pure data, заполняется один раз TileObjectRegistry'ем при load.
## Никаких сигналов внутри. Эмиттит EventBus сторонний код (resolver).

enum Level { LARGE = -1, SMALL = 0, ELEVATION = 1 }

# core
var id: StringName
var level: int
var blocks_movement: bool
var blocks_abilities_through: bool
var sprite_path: String

# destructible
var breakable: bool
var hp: int
var armor_tags: Array[StringName]

# behavior — независимые булевые флаги триггеров (см. spec OQ-2 resolution)
var behavior_effect_id: StringName
var applies_on_enter: bool
var applies_on_turn_end: bool
var aura_radius: int            # 0 = no aura, >=1 = active aura
var applies_on_attacked: bool

# linger (только SMALL walkable, &"" = выкл)
var linger_effect_id: StringName   # ссылка на tile_effect с duration > 0

# synergy
var tags: Array[StringName]

# on-destroy
var on_destroy_effect_id: StringName
var on_destroy_spawn_object_id: StringName

# audio/visual
var vfx_destroy: String
var sfx_destroy: String


func _init(p_data: Dictionary) -> void:
    # все поля распаковываются из dict с дефолтами.
    # registry уже валидирует level и forces blocks_movement/blocks_abilities_through
    # + force-zero запрещённых триггеров для уровня + force-empty linger для не-SMALL-walkable.
    ...
```

Без геттеров/сеттеров — read-only по convention. Consumers (pathfinder, resolver) читают напрямую.

## TileObjectRegistry API

Паттерн полностью копирует `scripts/core/arena/tile_effect_registry.gd`:

```gdscript
class_name TileObjectRegistry

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const _EMPTY := TileObject.new({})  # singleton "no object" — id=&"", level=0, all flags false

var _objects: Dictionary = {}   # StringName -> TileObject


func load_from_dir(dir_path: String) -> void:
    # ходим по dir, для каждого *.json — _load_file().
    # лог в конце: "Loaded N tile objects".


func _load_file(path: String) -> void:
    # parse JSON, validate, конструируем TileObject, кладём в _objects.


func _validate_and_normalize(data: Dictionary) -> Dictionary:
    # AC-O2 правила:
    # - id обязателен и строка → иначе skip + warn
    # - level ∈ {-1, 0, 1} → иначе skip + warn
    # - level == LARGE (-1)     → blocks_movement=true, blocks_abilities_through=true (force, warn если в JSON было иначе)
    # - level == ELEVATION (1)  → blocks_movement=true, blocks_abilities_through=true (force)
    # - level == ELEVATION (1)  → behavior_effect_id = "" + applies_*=false + aura_radius=0 (force, warn если что-то было)
    # - level == LARGE (-1)     → applies_on_enter=false, applies_on_turn_end=false (force, warn). aura_radius >=1 и applies_on_attacked допустимы.
    # - level == SMALL (0) и blocks_movement==true → как LARGE: applies_on_enter=false, applies_on_turn_end=false (force, warn).
    # - behavior_effect_id == "" но любой триггер включён → warn + force-zero все триггеры.
    # - linger_effect_id != "" но НЕ (level==SMALL и blocks_movement==false) → force-empty + warn.
    # - linger_effect_id != "" и referenced effect не найден в TileEffectRegistry → warn (не блокер,
    #   registry может загрузиться позже — в 018 проверяем только при idle-валидации если registry доступен).
    return data


func get_object(id: StringName) -> TileObject:
    return _objects.get(id, _EMPTY)


func has_object(id: StringName) -> bool:
    return _objects.has(id)
```

> Naming: `get`/`has` shadow `Object.get(property)` / `Object.has_method()` — same family of trap as `log()` in CLAUDE.md §Known traps. Using `get_object`/`has_object`, mirroring `get_effect`/`has_effect` in `TileEffectRegistry`.

Snippet парсинга `tags` копируется из 011-skill-tags (`SkillDatabase._build_skill`) — тот же graceful-degradation паттерн при кривом массиве.

## JSON schema (sample — `lava_pool.json`)

```json
{
  "id": "lava_pool",
  "level": 0,
  "blocks_movement": false,
  "sprite_path": "res://assets/sprites/tiles/lava_pool.png",

  "breakable": false,

  "behavior_effect_id": "damage_zone",
  "applies_on_enter": true,
  "applies_on_turn_end": true,
  "aura_radius": 0,
  "applies_on_attacked": false,

  "linger_effect_id": "burning",

  "tags": ["liquid", "hazard"],

  "on_destroy_effect_id": "",
  "on_destroy_spawn_object_id": "",

  "vfx_destroy": "",
  "sfx_destroy": ""
}
```

`heal_fountain.json` (LARGE, aura): `level: -1`, `applies_on_enter: false`, `applies_on_turn_end: false`, `aura_radius: 1`, `applies_on_attacked: false`, `linger_*` пустые. `blocks_movement` и `blocks_abilities_through` в JSON не пишем (всё равно перезатрётся registry-ем) — но в `_schema.md` укажем что для LARGE/ELEVATION эти поля **read-only-derived**.

`wooden_barrel.json` (SMALL non-walkable, breakable bomb): `applies_on_attacked: true` опционально (если хотим сразу `damage_zone` при попадании, ДО разрушения). На разрушение (hp=0) — `on_destroy_effect_id: "damage_zone"` оставляет огненную лужу.

## HexTile diff

```gdscript
# было
var coord: Vector2i
var walkable: bool
var move_cost: int
var tile_kind: StringName
var static_effect_id: StringName
```

Добавляется одно поле:
```gdscript
var object_id: StringName  # &"" если нет объекта
```

И параметр в `_init` — последним, default `&""` (backward-compat для существующих вызовов в `hex_grid.gd`):

```gdscript
func _init(
        p_coord: Vector2i,
        p_walkable: bool,
        p_move_cost: int,
        p_tile_kind: StringName,
        p_effect_id: StringName,
        p_object_id: StringName = &""
) -> void:
    ...
    object_id = p_object_id
```

`walkable` остаётся как есть — это derive-от-биома, не от объекта. Pathfinder сам комбинирует `tile.walkable AND not registry.get(tile.object_id).blocks_movement`.

## HexGrid diff

В `_build_tile_map` (точное место — после чтения `static_effect_id`): добавить чтение custom data layer `"object_id"` (если такого слоя в TileMap нет — TileSet.add_custom_data_layer руками; задача в tasks). Если значение пусто/null → `&""`.

```gdscript
var obj_id_raw: Variant = tile_data.get_custom_data("object_id")
var obj_id: StringName = StringName(obj_id_raw) if obj_id_raw != null else &""
```

Передаётся в HexTile._init последним аргументом.

## HexPathfinder diff

После T001 — фактическая структура: `HexPathfinder.build(tiles, w, h)` итерирует `_tiles` и `add_point` только если `tile.walkable`. `set_point_walkable(coord, bool)` уже есть.

Минимальный путь — вынести логику комбинации в HexGrid (он владеет registry) перед `_build_pathfinder`: пройтись по `_tiles`, если `obj.blocks_movement` → выставить `tile.walkable = false`-эффективно через альтернативный подход. Но `tile.walkable` — read-only-после-инициализации (см. `hex_tile.gd` хедер), мутировать его нельзя.

**Решение:** добавить в `HexPathfinder` метод `build(tiles, w, h, blocked_predicate: Callable = ...)` или просто инжектить `_object_registry` в pathfinder и менять `if tile.walkable` на `if tile.walkable and not _object_registry.get(tile.object_id).blocks_movement`. Идём вторым — короче и не меняет публичный API `build()`.

```gdscript
# scripts/core/arena/hex_pathfinder.gd
var _object_registry: TileObjectRegistry  # set externally before build()

func set_object_registry(reg: TileObjectRegistry) -> void:
    _object_registry = reg

func build(tiles: Dictionary, grid_width: int, grid_height: int) -> void:
    ...
    for coord: Vector2i in tiles:
        var tile: HexTile = tiles[coord]
        if tile.walkable and _is_passable_object(tile):
            ...

func _is_passable_object(tile: HexTile) -> bool:
    if _object_registry == null:
        return true
    var obj := _object_registry.get(tile.object_id)
    return not obj.blocks_movement
```

В `HexGrid.initialize()` после создания `_object_registry` вызвать `_pathfinder.set_object_registry(_object_registry)` перед `_build_pathfinder()`. Тоже надо учитывать в `_get_walkable_neighbours` — иначе соседи объектных тайлов всё равно подключатся через `connect_neighbours`. Поэтому добавляем helper в HexGrid:

```gdscript
func _is_tile_passable(tile: HexTile) -> bool:
    if not tile.walkable:
        return false
    if _object_registry == null:
        return true
    return not _object_registry.get(tile.object_id).blocks_movement
```

И в `_get_walkable_neighbours` / `is_walkable` / `get_all_walkable_coords` / `place_actor` / `move_actor` / `step_actor` заменить проверки `tile.walkable` → `_is_tile_passable(tile)`. Это ~6 локальных правок в `hex_grid.gd`. Все additive (логика расширяется, контракты не меняются).

## EventBus signals

Файл: `scripts/infrastructure/event_bus.gd` (autoload). Стиль секций — past-tense snake_case, новый раздел `# Tile Objects (018)` после существующего `# Arena`. Добавляются:

```gdscript
signal tile_object_damaged(coord: Vector2i, hp_remaining: int)
signal tile_object_destroyed(coord: Vector2i, object_id: StringName)
signal tile_object_effect_triggered(coord: Vector2i, target_actor_id: StringName, effect_id: StringName)
signal tile_object_actor_exited(coord: Vector2i, actor_id: StringName, object_id: StringName)
```

Последний сигнал — для linger DoT: при выходе actor'а с тайла, у которого есть `linger_status_id`, resolver слушает этот сигнал и вызывает `actor.add_status(linger_status_id, linger_duration)` (паттерн graceful-degradation как в `scripts/core/abilities/effects/status_effect.gd` — если `add_status` отсутствует, info-лог).

В 018 подписчиков пока нет — это done в follow-up фиче (resolver). 018 только декларирует контракт + эмитит сигнал из hex_grid/pathfinder где actor покидает тайл.

> Если EventBus в проекте не используется (вместо него — direct calls / Resource singletons) — этот пункт пересматривается в T001. Сейчас идём по предположению из CLAUDE.md §Architecture, который явно требует EventBus.

## Триггеры — точная семантика

| Триггер-флаг | Когда срабатывает | Допустимо для | Эффект применяется к |
|---|---|---|---|
| `applies_on_enter` | actor шагнул на тайл | SMALL walkable | actor'у, шагнувшему |
| `applies_on_turn_end` | actor закончил ход стоя на тайле | SMALL walkable | actor'у, стоящему |
| `aura_radius >= 1` | в конце каждого хода (system tick) | LARGE, SMALL non-walkable, SMALL walkable (= тогда сам тайл включается в радиус) | всем actor'ам в радиусе R hexes |
| `applies_on_attacked` | объект получает урон | любой breakable | actor'у-атакующему |
| `linger_effect_id != ""` | actor покинул тайл | SMALL walkable | actor'у, покинувшему — resolver применяет tile_effect с duration (тиканье N ходов) |

Сам runtime-триггер — НЕ в 018. 018 декларирует что и как, исполняет — resolver (отдельный модуль / follow-up фича). 018 только парсит, хранит, эмитит сигналы.

## Migration / совместимость

- Тайлы без `object_id` — работают как сейчас. `Registry.get(&"")` возвращает `_EMPTY`.
- `data/tile_effects/damage_zone.json`, `heal_fountain.json` — НЕ трогаются.
- `HexTile._init` обратно-совместим (новый параметр с default `&""`).
- `TileEffectRegistry` — расширяется парсингом поля `duration: int` (default 0). Existing файлы без `duration` — backward-compat.

## Тестирование

- **Юнит-тестов нет** (как и в 011).
- **Manual smoke** (AC-O8/AC-O9, Sergey):
  1. F5 на `tile_objects_smoke.tscn` → `Loaded 6 tile objects`, `burning.json` в tile_effects без ERROR.
  2. Pathfinder не пускает на mountain/boulder/wooden_barrel/wooden_table/heal_fountain.
  3. Шаг в lava_pool → `tile_object_effect_triggered ... damage_zone` (on_enter).
  4. Turn_end на лаве → второй `tile_object_effect_triggered` (applies_on_turn_end).
  5. Выход → `tile_object_actor_exited` — resolver нет → лог без crash.
  6. Рядом с heal_fountain, turn_end → аура применяется.
  7. 2 удара по barrel → `tile_object_destroyed`, `damage_zone` на тайле.

## Risk / Mitigation

| Риск | Вероятность | Митигация |
|---|---|---|
| Egor не одобряет diff в `hex_tile.gd`/`hex_grid.gd`/`hex_pathfinder.gd` | средняя | diff минимальный и additive. Сообщить в момент открытия PR со ссылкой на спеку. |
| Custom data layer "object_id" в TileSet ещё не существует | высокая | T005a — добавить руками через Godot editor (TileSet inspector). До этого все `object_id = &""`. |
| EventBus не существует в проекте | разрешено T001 | `scripts/infrastructure/event_bus.gd` существует, autoload, snake_case past-tense сигналы. Добавляем 4 новых в раздел `# Tile Objects (018)`. |
| Linger no-op до появления resolver'а | высокая (known) | Graceful — `tile_object_actor_exited` эмитится, подписчиков нет. Resolver — follow-up 019. |
| On_enter + turn_end двойное попадание | ожидаемо | Не баг. Баланс — Стасян правит `amount` в `damage_zone.json`. |

## Godot 4.6 ссылки

- [TileMap.get_cell_tile_data + custom data layers](https://docs.godotengine.org/en/4.6/classes/class_tiledata.html#class-tiledata-method-get-custom-data) — паттерн чтения `object_id` с тайла.
- [TileSet.add_custom_data_layer](https://docs.godotengine.org/en/4.6/classes/class_tileset.html#class-tileset-method-add-custom-data-layer) — для T005a (если слой не создан).
- [DirAccess](https://docs.godotengine.org/en/4.6/classes/class_diraccess.html) — registry pattern, копия из tile_effect_registry.
- [JSON.parse](https://docs.godotengine.org/en/4.6/classes/class_json.html#class-json-method-parse) — same.
- [StringName](https://docs.godotengine.org/en/4.6/classes/class_stringname.html) — для id-полей.
