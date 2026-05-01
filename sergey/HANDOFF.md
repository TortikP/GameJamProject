# Sergey — HANDOFF

**Дата:** 2026-05-02 UTC  
**Ветка:** `sergey/spec-018-tile-objects`  
**Следующий шаг:** implement — сказать Claude «implement» и он пройдёт tasks.md Группы A→H  
**Полное разрешение:** Claude может делать всё с этими наработками без дополнительного approve Sergey

---

## Что сделано в эту сессию

Написан spec-018 «Tile Objects» — data-driven статические объекты на тайлах. Три итерации по мере прояснения деталей (OQ-1/2/3 → разрешены). Код не написан — только спека. Реализация ждёт команды «implement».

---

## Состояние репозитория

```
branch:   sergey/spec-018-tile-objects  (origin в sync, 3 коммита поверх staging)
PR:       не открыт — открыть по https://github.com/TortikP/GameJamProject/pull/new/sergey/spec-018-tile-objects
staging:  чистый (последний мерж — PR#38, 013-refactor-wave-1 Egor'а)
```

Spec файлы:
```
specs/018-tile-objects/spec.md    — что и почему (v3, финальный)
specs/018-tile-objects/plan.md    — как (TileObject API, JSON schema, registry, HexTile diff)
specs/018-tile-objects/tasks.md   — чеклист задач T001..T022
```

---

## Ключевые решения (зафиксированы в spec.md §Open Questions RESOLVED)

### Три уровня объектов

| Level | Имя | blocks_move | blocks_abilities | effects |
|---|---|---|---|---|
| `-1` | LARGE | да (fixed) | да (fixed) | да, aura по радиусу |
| `0` | SMALL | по флагу `blocks_movement` | нет (always) | да, любые триггеры |
| `1` | ELEVATION | да (fixed) | да (fixed) | нет (enforced) |

### Триггеры behavior — 4 независимых bool-флага

```gdscript
applies_on_enter: bool       # SMALL walkable только
applies_on_turn_end: bool    # SMALL walkable только
aura_radius: int             # 0=выкл; >=1=аура на N hexes, turn_end каждый ход
applies_on_attacked: bool    # любой breakable
```

### Linger DoT (после выхода с тайла)

Поле `linger_effect_id: StringName` → ссылка на tile_effect **с `duration > 0`**.
- Новый sample: `data/tile_effects/burning.json` (`kind: damage, amount: 2, duration: 2`)
- `TileEffectRegistry` расширяется парсингом `duration: int` (default 0, backward-compat)
- Лава: `linger_effect_id = "burning"` → после выхода actor горит 2 хода
- Runtime (тиканье duration) — в follow-up `019-tile-object-resolver`; в 018 эмитится `EventBus.tile_object_actor_exited`, подписчика нет → graceful no-op

### Один объект на тайл

`HexTile.object_id: StringName` (default `&""`).

---

## Технический контекст для implement

### Файлы, которые трогает 018 (все изменения additive)

```
НОВЫЕ:
  scripts/core/arena/tile_object.gd          — pure data class
  scripts/core/arena/tile_object_registry.gd — JSON loader
  data/tile_objects/*.json                   — 6 sample объектов
  data/tile_objects/_schema.md               — schema doc для Стасяна
  data/tile_effects/burning.json             — новый tile_effect с duration
  scenes/dev/tile_objects_smoke.tscn         — dev smoke scene

ПРАВКИ (+1..+10 строк каждый):
  scripts/core/arena/hex_tile.gd             — +1 поле object_id + 1 param в _init
  scripts/core/arena/hex_grid.gd             — читать custom data layer "object_id"
  scripts/core/arena/hex_pathfinder.gd       — query registry в _is_passable
  scripts/infrastructure/event_bus.gd        — +4 сигнала (см. ниже)
```

### Новые EventBus сигналы (в `scripts/infrastructure/event_bus.gd`)

```gdscript
# Tile Objects (018-tile-objects)
signal tile_object_damaged(coord: Vector2i, hp_remaining: int)
signal tile_object_destroyed(coord: Vector2i, object_id: StringName)
signal tile_object_effect_triggered(coord: Vector2i, target_actor_id: StringName, effect_id: StringName)
signal tile_object_actor_exited(coord: Vector2i, actor_id: StringName, object_id: StringName)
```

Стиль — копировать из секции `# Arena` которая уже есть:
```gdscript
signal tile_entered(actor_id: StringName, coord: Vector2i)
signal tile_effect_triggered(actor_id: StringName, coord: Vector2i, effect_id: StringName)
```
Naming convention — snake_case, past tense. ✓

### TileObject data class (скелет из plan.md)

```gdscript
class_name TileObject

enum Level { LARGE = -1, SMALL = 0, ELEVATION = 1 }

var id: StringName
var level: int
var blocks_movement: bool
var blocks_abilities_through: bool
var sprite_path: String

# destructible
var breakable: bool
var hp: int
var armor_tags: Array[StringName]

# behavior triggers
var behavior_effect_id: StringName
var applies_on_enter: bool
var applies_on_turn_end: bool
var aura_radius: int
var applies_on_attacked: bool

# linger
var linger_effect_id: StringName

# synergy tags
var tags: Array[StringName]

# on-destroy
var on_destroy_effect_id: StringName
var on_destroy_spawn_object_id: StringName

# audio/visual
var vfx_destroy: String
var sfx_destroy: String


func _init(p_data: Dictionary) -> void:
    id = StringName(p_data.get("id", ""))
    level = int(p_data.get("level", 0))
    # ... (все поля с дефолтами, валидация в registry)
```

### TileObjectRegistry — паттерн (копия tile_effect_registry.gd)

```gdscript
# scripts/core/arena/tile_effect_registry.gd — оригинал, смотреть туда
# tile_object_registry.gd — тот же паттерн:
#   load_from_dir(dir_path) / get(id) / has(id) / _load_file / _validate_and_normalize
```

Validation rules из spec.md:
- `level ∈ {-1, 0, 1}` → иначе skip + warn
- LARGE/ELEVATION: `blocks_movement=true`, `blocks_abilities_through=true` (force)
- ELEVATION: все trigger-поля → false/0 (force)
- LARGE: `applies_on_enter=false`, `applies_on_turn_end=false` (force)
- SMALL с `blocks_movement=true`: `applies_on_enter=false`, `applies_on_turn_end=false` (force)
- `linger_effect_id != ""` и НЕ (SMALL walkable) → force-empty + warn
- `behavior_effect_id == ""` но триггеры включены → warn + force-zero

Паттерн парсинга Array[StringName] — копировать из `scripts/core/skills/skill_database.gd` `_build_skill` (011-skill-tags добавил туда этот паттерн, graceful degradation при кривом JSON).

### HexTile._init diff

```gdscript
# Добавить параметр ПОСЛЕДНИМ с default &"" (backward-compat)
func _init(
        p_coord: Vector2i,
        p_walkable: bool,
        p_move_cost: int,
        p_tile_kind: StringName,
        p_effect_id: StringName,
        p_object_id: StringName = &""   # NEW
) -> void:
    ...
    object_id = p_object_id             # NEW
```

### HexGrid diff

В `_build_tile_map` после чтения `static_effect_id`:
```gdscript
var obj_id_raw: Variant = tile_data.get_custom_data("object_id")
var obj_id: StringName = StringName(obj_id_raw) if obj_id_raw != null else &""
```
Передать в `HexTile._init(...)` последним аргументом.

Создать `TileObjectRegistry`, вызвать `load_from_dir("res://data/tile_objects/")`. Хранить как поле, передать в HexPathfinder.

### TileEffectRegistry — добавить duration

В `_load_file` при построении dict — поле `duration` уже будет в raw data. Клиент читает `data["duration"]` или `data.get("duration", 0)`. Никаких правок в логику не нужно — registry хранит raw dict, `get_effect(id)` возвращает его. Resolver (019) сам прочитает `duration`.

### Sample JSONs (итоговые значения)

**lava_pool.json**
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

**heal_fountain.json**
```json
{
  "id": "heal_fountain",
  "level": -1,
  "sprite_path": "res://assets/sprites/tiles/fountain.png",
  "breakable": false,
  "behavior_effect_id": "heal_fountain",
  "applies_on_enter": false,
  "applies_on_turn_end": false,
  "aura_radius": 1,
  "applies_on_attacked": false,
  "linger_effect_id": "",
  "tags": ["stone", "construct"],
  "on_destroy_effect_id": "",
  "on_destroy_spawn_object_id": "",
  "vfx_destroy": "",
  "sfx_destroy": ""
}
```

**wooden_barrel.json**
```json
{
  "id": "wooden_barrel",
  "level": 0,
  "blocks_movement": true,
  "sprite_path": "res://assets/sprites/tiles/barrel.png",
  "breakable": true,
  "hp": 2,
  "armor_tags": [],
  "behavior_effect_id": "",
  "applies_on_enter": false,
  "applies_on_turn_end": false,
  "aura_radius": 0,
  "applies_on_attacked": false,
  "linger_effect_id": "",
  "tags": ["wood", "flammable"],
  "on_destroy_effect_id": "damage_zone",
  "on_destroy_spawn_object_id": "",
  "vfx_destroy": "",
  "sfx_destroy": ""
}
```

**burning.json** (`data/tile_effects/`)
```json
{
  "id": "burning",
  "kind": "damage",
  "amount": 2,
  "duration": 2,
  "applies_to": ["player", "enemy"],
  "vfx": "",
  "sfx": ""
}
```

---

## Что не реализовано (follow-up)

| Фича | Спека | Скоуп |
|---|---|---|
| Runtime trigger resolver (тиканье аур, on_enter/turn_end hook-и, linger duration) | `019-tile-object-resolver` (не написана) | Sergey |
| Визуальный рендер объектов на тайлах (спрайты) | часть presentation — договориться с Андреем | Андрей/Sergey |
| Реальный контент объектов (balance) | редактировать JSON в `data/tile_objects/` | Стасян |
| Actor-status UI (иконки статусов на HUD) | при необходимости — отдельная спека | Alexey |

---

## Координация

- **Egor** — primary reviewer PR. Трогаем `hex_tile.gd`, `hex_grid.gd`, `hex_pathfinder.gd`. Все изменения additive (+поле, +param с default, +registry query). Должен одобрить перед мержем в staging.
- **Стасян** — после мержа: пинг что можно добавлять объекты через `data/tile_objects/*.json`, схема в `data/tile_objects/_schema.md`.
- **Андрей** — не трогается в 018. Пинг когда дойдём до visual рендера объектов на тайлах.

---

## Как продолжить на новом компьютере/аккаунте

```bash
# Session start (стандартный, из PROJECT_INSTRUCTIONS.md)
git config --global user.email "claude@jam.local"
git config --global user.name  "Claude (jam)"
git config --global credential.helper store
TOKEN='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'
printf 'https://x-access-token:%s@github.com\n' "$TOKEN" > ~/.git-credentials
chmod 600 ~/.git-credentials && unset TOKEN

git clone --quiet https://github.com/TortikP/GameJamProject.git
cd GameJamProject
git checkout sergey/spec-018-tile-objects
```

Затем в чате:

> **«Я Sergey. Прочитай `sergey/HANDOFF.md` и продолжи implement spec-018.»**

Claude прочитает этот файл, перечитает `specs/018-tile-objects/tasks.md` и пройдёт все `[ ]` задачи без дополнительных вопросов.
