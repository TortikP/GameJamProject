# 019-tile-object-resolver — plan

**Spec:** [`spec.md`](./spec.md)

## Файлы

| Путь | Что | Дельта |
|---|---|---|
| `scripts/core/arena/tile_object_resolver.gd` | NEW. Resolver — Node, подписывается на EventBus, тикает лингер/ауру/on_enter/on_turn_end. | ~170 строк |
| `scripts/core/arena/hex_grid.gd` | +3 методы: `get_tile_object_id`, `set_tile_object_id`, `get_all_tile_object_ids`. Аддитивно, Egor review. | +20 строк |

Всё остальное (EventBus, TileObject, TileObjectRegistry, Actor) — без изменений.

## TileObjectResolver API

```gdscript
class_name TileObjectResolver
extends Node

## Scene-local. Инициализировать через setup() ДО grid_built сигнала контроллера.
func setup(
    grid: HexGrid,
    object_reg: TileObjectRegistry,
    effect_reg: TileEffectRegistry,
    actor_reg: ActorRegistry
) -> void

## Вызывает ability/spell система когда атака попадает в тайл с объектом.
## attacker_id &"" — если атакующего нет (area spell, tile effect chain).
func damage_object(coord: Vector2i, amount: int, attacker_id: StringName = &"") -> void
```

### Внутренняя state

```
_runtime_hp: Dictionary = {}       # Vector2i → int (lazy-init from obj.hp на первом damage)
_linger_stack: Dictionary = {}     # StringName(actor_id) → Array[{effect_id, turns_left}]
```

### Сигнальные подписки

| EventBus signal | Handler |
|---|---|
| `tile_entered(actor_id, coord)` | `_on_tile_entered` → applies_on_enter |
| `player_turn_ended(turn)` | `_on_player_turn_ended` → turn_end + aura + linger tick |
| `tile_object_actor_exited(coord, actor_id, obj_id)` | `_on_tile_object_actor_exited` → linger push |

## HexGrid новые методы

```gdscript
## Возвращает object_id на тайле; &"" если тайла нет или объекта нет.
func get_tile_object_id(coord: Vector2i) -> StringName:
    if not _tiles.has(coord):
        return &""
    return _tiles[coord].object_id

## Записывает object_id на тайл (для on_destroy_spawn и clearup при разрушении).
func set_tile_object_id(coord: Vector2i, id: StringName) -> void:
    if _tiles.has(coord):
        _tiles[coord].object_id = id

## Возвращает словарь {Vector2i: StringName} только для тайлов с непустым object_id.
## Используется resolver'ом для обхода aura-объектов каждый ход.
func get_all_tile_object_ids() -> Dictionary:
    var result: Dictionary = {}
    for coord: Variant in _tiles:
        var tile: HexTile = _tiles[coord]
        if tile.object_id != &"":
            result[coord] = tile.object_id
    return result
```

## Aura — почему `reachable_within`

LARGE-объекты (heal_fountain) непроходимы — pathfinder на их координату не стартует через walk. Но `reachable_within` стартует BFS с _from_ как начальной точкой и итерирует `_get_walkable_neighbours(from)` — т.е. находит все проходимые соседи вокруг непроходимого LARGE-тайла. Это семантически правильно: аура распространяется в стороны, а не проходит сквозь блокирующий объект.

## Linger — graceful для уже мёртвых actor'ов

При тике `_linger_stack`: если `actor_registry.get_actor(id) == null` или `!actor.is_alive()` — apply пропускается, запись всё равно декрементируется и удаляется по истечении. Мёртвые не продолжают гореть.

## Контроллер-сторона

Контроллер арены (godmode_controller, будущий arena_controller) создаёт resolver и вызывает setup:

```gdscript
# в _ready() или после grid_built:
var resolver := TileObjectResolver.new()
add_child(resolver)
resolver.setup(_grid, _grid._object_registry, _grid._effect_registry, _registry)
```

`_grid._object_registry` и `_grid._effect_registry` — технически private, но resolver читает их через grid (см. ниже). Альтернатива: добавить `get_object_registry()` / `get_effect_registry()` к HexGrid. Для джема — инжектируем напрямую от контроллера, который создаёт grid и знает оба registry. **Контроллер должен вызывать `setup()` после `grid.initialize()` чтобы registry уже были наполнены.**

## Зависимости

- **Upstream:** 018-tile-objects (TileObject, TileObjectRegistry, EventBus signals, TileEffectRegistry.duration field).
- **Downstream:** Sergey's spell system вызывает `resolver.damage_object(coord, amount, attacker_id)`.
- **Coordination:** Egor review на 3 метода в `hex_grid.gd`.
