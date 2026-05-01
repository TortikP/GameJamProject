# 018-tile-objects — plan

**Spec:** [`spec.md`](./spec.md)

> ⚠ Plan written assuming OQ-1=A (aura R=1), OQ-2=A (on_enter only), OQ-3=A (one object per tile). Если Sergey ответит иначе — поменяются: trigger enum, `aura_radius` field semantics, и поле `HexTile.object_id` (на массив). Помечено [DEPENDS-OQ-X] во всех релевантных местах.

## Файлы

| Путь | Что | Размер |
|---|---|---|
| `scripts/core/arena/tile_object.gd` | NEW pure data class | ~40 строк |
| `scripts/core/arena/tile_object_registry.gd` | NEW JSON loader (паттерн из `tile_effect_registry.gd`) | ~80 строк |
| `scripts/core/arena/hex_tile.gd` | +1 поле `object_id: StringName`, +1 параметр в `_init` | +3 |
| `scripts/core/arena/hex_grid.gd` | в `_build_tile_map` читать custom data layer "object_id" | +5 |
| `scripts/core/arena/hex_pathfinder.gd` | injected dep `TileObjectRegistry`, в проверке проходимости — query объект | +10 |
| `scripts/core/event_bus.gd` *(точное имя/путь TBD — проверить)* | +3 сигнала per AC-O7 | +5 |
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

# behavior
var behavior_effect_id: StringName
var behavior_trigger: StringName       # "on_enter" | "on_turn_end" | "aura" | "on_attacked"
var aura_radius: int

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
    # registry уже валидирует level и forces blocks_movement/blocks_abilities_through.
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
    # - level == ELEVATION (1) → behavior_effect_id = "" принудительно (warn если не пуст)
    # - level == LARGE (-1) → blocks_movement=true, blocks_abilities_through=true (force)
    # - level == ELEVATION (1) → blocks_movement=true, blocks_abilities_through=true (force)
    # - level == LARGE и trigger ∈ {on_enter, on_turn_end} → форсим в "aura" + warn
    # - level == SMALL и blocks_movement==true и trigger ∈ {on_enter, on_turn_end} → форсим "aura" + warn
    return data


func get(id: StringName) -> TileObject:
    return _objects.get(id, _EMPTY)


func has(id: StringName) -> bool:
    return _objects.has(id)
```

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
  "behavior_trigger": "on_enter",
  "aura_radius": 0,

  "tags": ["liquid", "hazard"],

  "on_destroy_effect_id": "",
  "on_destroy_spawn_object_id": "",

  "vfx_destroy": "",
  "sfx_destroy": ""
}
```

`heal_fountain.json` (LARGE, aura) — `level: -1`, `behavior_trigger: "aura"`, `aura_radius: 1`. `blocks_movement` и `blocks_abilities_through` в JSON не пишем (всё равно перезатрётся registry-ем) — но в `_schema.md` укажем что для LARGE/ELEVATION эти поля **read-only-derived**.

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

Текущая проверка проходимости (надо посмотреть — не читал детально, в tasks T005 первая под-задача — research). Добавить query в registry:

```gdscript
# pseudocode
func _is_passable(tile: HexTile) -> bool:
    if not tile.walkable:
        return false
    var obj := _object_registry.get(tile.object_id)
    if obj.blocks_movement:
        return false
    return true
```

Registry инжектится в pathfinder при создании (в HexGrid._ready или где сейчас pathfinder создаётся — research в T005).

## EventBus signals

Расположение точное — TBD на T001 (есть либо `scripts/core/event_bus.gd` либо `scripts/infrastructure/event_bus.gd`, надо посмотреть). Добавляются:

```gdscript
signal tile_object_damaged(coord: Vector2i, hp_remaining: int)
signal tile_object_destroyed(coord: Vector2i, object_id: StringName)
signal tile_object_effect_triggered(coord: Vector2i, target_actor_id: StringName, effect_id: StringName)
```

В 018 эмиттеров пока нет — это done в follow-up фиче (resolver, который обрабатывает damage event'ы и триггерит эффекты). 018 только декларирует контракт.

> Если EventBus в проекте не используется (вместо него — direct calls / Resource singletons) — этот пункт пересматривается в T001. Сейчас идём по предположению из CLAUDE.md §Architecture, который явно требует EventBus.

## Триггеры — точная семантика [DEPENDS-OQ-1, OQ-2]

Пока на default A/A:

| Trigger | Когда | Допустимо для |
|---|---|---|
| `on_enter` | actor шагнул на тайл | SMALL walkable |
| `on_turn_end` | actor закончил ход на тайле | SMALL walkable |
| `aura` | каждый turn-end системой, для всех актёров в `aura_radius` | LARGE, SMALL non-walkable |
| `on_attacked` | при получении урона объектом | любой breakable |

Сам runtime-триггер — НЕ в 018. 018 декларирует что и как, исполняет — resolver (отдельный модуль). 018 только парсит и хранит.

## Migration / совместимость

- Тайлы без `object_id` (т.е. все существующие на момент 018) — работают как сейчас. Registry.get(&"") возвращает `_EMPTY`, `blocks_movement=false`.
- `data/tile_effects/damage_zone.json`, `heal_fountain.json` — НЕ трогаются. Объекты ссылаются на них по id через `behavior_effect_id`.
- `HexTile._init` обратно-совместим (новый параметр с default).

## Тестирование

- **Юнит-тестов нет** (как и в 011).
- **Manual smoke** (AC-O8, делает Sergey совместно с Egor):
  1. Открыть `scenes/dev/tile_objects_smoke.tscn` в Godot 4.6.2, F5.
  2. Лог: `[INFO][TileObjectRegistry] Loaded 6 tile objects` без ERROR/WARN.
  3. Pathfinder visualizer (если есть в dev-сцене) показывает что mountain/boulder/wooden_barrel/wooden_table недоступны для completion хода. lava_pool — доступен.
  4. Шагнуть в lava_pool → лог `[DEBUG] tile_object_effect_triggered ... damage_zone`.
  5. Атаковать wooden_barrel debug-skill'ом → лог `tile_object_damaged hp=N`. После 2 ударов → `tile_object_destroyed`, на тайле появляется static_effect `damage_zone`.

Если Godot CLI/headless smoke возможен — TBD (не приоритет).

## Risk / Mitigation

| Риск | Вероятность | Митигация |
|---|---|---|
| Egor не одобряет diff в `hex_tile.gd`/`hex_grid.gd`/`hex_pathfinder.gd` | средняя | diff минимальный и additive. Сообщить Egor'у в момент открытия PR, дать ссылку на спеку. Если refuse — выносим object-aware-checks в pathfinder без правок HexTile (object_id живёт в отдельной структуре). |
| Custom data layer "object_id" в TileSet ещё не существует | высокая | T005a — добавить custom data layer в TileSet вручную через Godot editor (Стасян/Андрей). До этого вся загрузка — пустые object_id. |
| EventBus не существует в проекте | низкая (упомянут в CLAUDE.md) | T001 — research-задача. Если нет — добавить отдельной микро-фичей перед 018, или использовать ad-hoc сигналы на узле. |
| OQ-3 ответ = B (массив объектов) | низкая | Меняется тип `HexTile.object_id` → `HexTile.object_ids: Array[StringName]`, цикл в pathfinder. Не катастрофа, но diff растёт ~×2. |

## Godot 4.6 ссылки

- [TileMap.get_cell_tile_data + custom data layers](https://docs.godotengine.org/en/4.6/classes/class_tiledata.html#class-tiledata-method-get-custom-data) — паттерн чтения `object_id` с тайла.
- [TileSet.add_custom_data_layer](https://docs.godotengine.org/en/4.6/classes/class_tileset.html#class-tileset-method-add-custom-data-layer) — для T005a (если слой не создан).
- [DirAccess](https://docs.godotengine.org/en/4.6/classes/class_diraccess.html) — registry pattern, копия из tile_effect_registry.
- [JSON.parse](https://docs.godotengine.org/en/4.6/classes/class_json.html#class-json-method-parse) — same.
- [StringName](https://docs.godotengine.org/en/4.6/classes/class_stringname.html) — для id-полей.
