# 041-effect-create-entity — spec

**Owner:** Egor (effect runtime + ability database parser changes + new status runtime).
**Coordination:**
- **Andrey** (019-tile-object-resolver) — 1 additive public method on `TileObjectResolver` (`add_summon_timer(coord, duration)`) + new turn-end tick (`_tick_summon_timers`) + listener for self-cleanup on `tile_object_destroyed`. Purely additive, no rename.
- **Sergey/Egor** (007/021/026 skill system) — `entity_id` JSON value format changes from plain id (`"bee"`) to status-style `id(duration)` (`"bee(3)"`, `"bee(-1)"`). Existing summon skills (`summon_bee.json`, `bee_summon_bee.json`, `teapot_spill_the_t.json`) must be migrated in this PR — hard rename, no shim.
- **Stasyan** (balance) — designer-facing: see §"JSON migration" for the bare-id → `id(d)` rule. After merge, Stasyan can author new summon skills with explicit duration.

**Status:** Draft (clarify-round пройден с Egor: variant B — без класса `Entity`, no rename of `tile_object*`).

**Upstream:** 007-skill-system (effect contract), 018-tile-objects (TileObject + registry), 019-tile-object-resolver (resolver, owns turn-end ticks), 026-skill-system-v3 (effect dict parsing, `entity_id` key), 027-status-effects (status runtime contract).

## Цель

`CreateEffect` сейчас — stub: логирует `"would spawn '%s' at %s"`. Скиллы `summon_bee` etc. парсятся, но при касте ничего не происходит. Этот спек реализует реальный спавн — actor'ов **или** tile-object'ов через единый ключ `entity_id` в effect-словаре, плюс ограниченное по времени существование через новый статус `summoned`.

## Scope-граница

**В скоупе:**
- Парсер: `entity_id: "bee(3)"` (status-style: id + arity-1 args = `[duration]`) вместо текущего bare `entity_id: "bee"`. `duration > 0` — N ходов до автодеспавна; `duration = -1` — бесконечно (живёт до смерти/уничтожения обычным путём).
- `CreateEffect.apply` — резолв `entity_id` через два registry: сначала `TileObjectRegistry`, затем `EnemyDatabase` (через `LevelLoader.spawn_enemy_at`). Дубликат id в обоих — warn, выбираем object.
- Спавн actor'а — `caster.team` копируется на спавненного (универсально, без условий).
- Спавн object'а — через `HexGrid.set_tile_object_id` + `TileObjectResolver.add_summon_timer`. Пути инициализации tile-object'а: `_pathfinder` rebuild не делаем (на одну клетку — overkill; resolver и так уже handle'ит). См. plan §"Pathfinder rebuild".
- Новый статус `summoned(d)` — для actor'ов. Runtime — minimal: при expire (`duration` стал ≤0) `on_remove` убивает actor через `take_damage(actor.hp)`. Никаких modify_speed / damage_amplifier / on_turn_start логик. UI (StatusIconStrip) подхватывает автоматом через existing pill-rendering.
- `Actor.tick_statuses_with_ctx` — 1-line surgery: `if inst.duration < 0: continue` перед декрементом. Сделано generic, не только для summoned, чтобы любой будущий "perma" статус работал через тот же sentinel.
- `TileObjectResolver` — новое поле `_summon_timers: Dictionary[Vector2i, int]`, метод `add_summon_timer(coord, duration)`, тик в существующем `_on_player_turn_ended` после `_tick_linger_stacks`, listener на `tile_object_destroyed` для self-cleanup. Истечение → `_destroy_object(coord, obj)` (использует существующую приватную функцию).
- Migration sample skills: `summon_bee.json`, `bee_summon_bee.json`, `teapot_spill_the_t.json` — `"entity_id": "bee"` → `"entity_id": "bee(3)"`. `teapot_spill_the_t` — pick duration based on existing balance (TBD в /plan, скорее всего тоже 3).

**Out of scope:**
- **Класс `Entity`** — не вводим вообще. Резолюция через два registry, термин "entity" — собирательный в коде/комментах.
- **Rename `tile_object*` → `object*`** — отложено в отдельный спек.
- **Status `summoned` для tile-object'ов** — у TileObject нет статусной системы (data class, shared sentinel pattern). Используется side-table `_summon_timers` в resolver'е. Симметрия с actor — на уровне семантики, не реализации.
- **Multi-arg duration encoding** (`"bee(3, 50)"` для скейла HP по уровню скилла) — arity=1 жёстко. Если позже понадобится — отдельный спек.
- **Object-as-caster** — `CreateEffect.apply(caster: Actor, ...)` — caster всегда Actor по контракту 026. TileObject-on-destroy-spawn использует другой путь (`on_destroy_spawn_object_id` в TileObjectResolver), не через CreateEffect.
- **VFX/SFX спавна** — presentation-слой; `collision_effect` / `sound_end` уже есть на Ability (026), они не требуют изменений в CreateEffect.
- **Призыв спавнить себя** — нет защиты от рекурсии; если призванный actor имеет skill с CreateEffect, он легально его кастует. Цепные саммоны — feature, не bug. Лимит — стандартный turn budget.
- **Save/load в середине duration** — нет save/load системы вообще; если появится, _summon_timers и `summoned` instances должны попасть в snapshot. Out of scope.

## Что вводится

### 1. JSON: `entity_id` value format

**Было** (007/026):
```json
"effects": [{"entity_id": "bee"}]
```

**Стало:**
```json
"effects": [{"entity_id": "bee(3)"}]
```

Грамматика — идентичная статусам: `id(arg0[, arg1, ...])`, но `arity=1`, `args = [duration]`.

Парсинг — переиспользуем `_parse_status_string` из `ability_database.gd` (уже умеет `id(n)`, поддерживает отрицательные через `String.to_int()`).

| Случай | Поведение |
|---|---|
| `"bee(3)"` | Корректно — duration=3 ходов |
| `"bee(-1)"` | Корректно — infinite (no tick, no expire) |
| `"bee(0)"` | Warn + skip эффект (duration=0 нонсенс — entity исчезает в тот же ход) |
| `"bee"` | Warn (no parens) + skip эффект (legacy bare id больше не валиден) |
| `"bee()"` | Warn (empty args) + skip |
| `"bee(3, 5)"` | Warn (arity mismatch) + skip |
| `"unknown(3)"` | Warn (id не найден ни в TileObjectRegistry, ни в EnemyDatabase) + skip; проверка происходит в `CreateEffect.apply`, не в парсере |

**Парсер не валидирует id** — резолюция в runtime. Это симметрично подходу `status_id`: парсер только чекает arity, runtime ловит unknown.

### 2. CreateEffect — runtime

**Изменения в** `scripts/core/abilities/effects/create_effect.gd`:

```gdscript
class_name CreateEffect
extends AbilityEffect

@export var entity_id: StringName = &""
@export var duration: int = 0   # 0 — invalid, parser writes >0 or -1

# apply(caster: Actor, target: Variant, ctx: Dictionary)
# - caster.team — копируется на actor-spawn
# - ctx["target_coord"] — Vector2i спавн-хекса
# - ctx["grid"] — HexGrid
# - ctx["registry"] — ActorRegistry (для actor-spawn)
# - ctx["actors_node"] — Node-родитель для actor scene (или fallback grid)
# - ctx["resolver"] — TileObjectResolver (для object-spawn timer и hp/destruction)
```

**Алгоритм:**

```
1. Validate: ctx["target_coord"] is Vector2i, ctx["grid"] != null.
2. coord = ctx["target_coord"]; if grid.get_actor_at(coord) != "": return  # AC-E5 unchanged
3. If TileObjectRegistry.has_object(entity_id):
     if grid.get_tile_object_id(coord) != "": return  # hex already has object → skip
     Pre-check existing actor on coord — already done step 2.
     grid.set_tile_object_id(coord, entity_id)
     resolver.add_summon_timer(coord, duration)
     EventBus.tile_object_summoned.emit(coord, entity_id, duration)   # NEW signal
     log info
   ELIF EnemyDatabase has entity_id (= file exists in data/enemies/):
     spawned = LevelLoader.spawn_enemy_at(grid, registry, actors_node, coord, entity_id, idx)
     if spawned == null: log warn + return
     spawned.team = caster.team   # universal team override
     # Apply summoned status:
     summoned_inst = StatusInstance.new()
     summoned_inst.status_id = &"summoned"
     summoned_inst.duration = duration
     summoned_inst.args = [duration]
     summoned_inst.source_id = caster.actor_id
     spawned.add_status(summoned_inst)
     EventBus.actor_spawned.emit(spawned.actor_id)   # already done by other paths
     log info
   ELSE:
     log warn ("unknown entity_id" — not in either registry)
```

**Резолюция приоритетов:** object > actor. Дубликат id (id есть в обоих registry) — `AbilityDatabase` логирует warn один раз при загрузке (см. plan), потом runtime берёт object без повторного warn.

**Идемпотентность дубликата id:** проверка дубликатов делается **один раз при boot** (после загрузки databases), не на каждый каст. См. plan §"Boot-time validation".

### 3. Status `summoned`

**Метаданные** (`data/status_effects/summoned.json`):

```json
{
  "id": "summoned",
  "family": "neutral",
  "icon": "",
  "arity": 1,
  "param_names": ["duration"],
  "loc_name": "status.summoned.name",
  "loc_desc": "status.summoned.desc"
}
```

`family = "neutral"` — новый pill-color tier (not buff, not debuff, not dot). UI fallback должен показать нейтральный цвет; если `UiTheme` не имеет такого family → дефолт debuff. Не блокер.

**Runtime** (`scripts/core/statuses/runtimes/summoned_runtime.gd`):

```gdscript
class_name SummonedRuntime
extends StatusRuntime

# only on_remove implemented — kills actor when status expires
static func on_remove(actor: Actor, instance: StatusInstance) -> void:
    if not actor.is_alive():
        return   # already dead by combat, status removed via dead-cleanup; no-op
    if instance.duration > 0:
        # Status was removed externally (dispel) before natural expire.
        # No dispels exist in 041 — log warn, but tolerate (don't kill if removed early).
        GameLogger.info("SummonedRuntime", "%s summoned removed early (duration=%d) — not killing" % [actor.actor_id, instance.duration])
        return
    GameLogger.info("SummonedRuntime", "%s summoned expired — destroying" % actor.actor_id)
    actor.take_damage(actor.hp)   # routes through normal death pipeline → actor_died → registry cleanup
```

**Регистрация в `StatusRegistry._RT_BY_ID`** — добавить `&"summoned": preload(...)`.

### 4. `Actor.tick_statuses_with_ctx` — infinite-duration sentinel

В существующем loop'е (`scripts/core/actors/actor.gd`, около строки 320):

```gdscript
# was:
inst.duration -= 1
any_decremented = true
if inst.duration <= 0:
    to_remove.append(inst.status_id)

# becomes:
if inst.duration < 0:
    continue   # 041: infinite-duration sentinel — never decrement, never expire
inst.duration -= 1
any_decremented = true
if inst.duration <= 0:
    to_remove.append(inst.status_id)
```

**Generic, not summoned-specific.** Любой будущий статус с `duration=-1` получит ту же семантику бесплатно.

### 5. `TileObjectResolver` — summon timers

**Изменения в** `scripts/core/arena/tile_object_resolver.gd`:

```gdscript
# new field
var _summon_timers: Dictionary = {}   # Vector2i coord -> int turns_left (>=1, или -1 infinite)

# new public API
func add_summon_timer(coord: Vector2i, duration: int) -> void:
    if duration == 0:
        GameLogger.warn("TileObjectResolver", "add_summon_timer: duration=0 invalid for %s — ignored" % str(coord))
        return
    _summon_timers[coord] = duration
    GameLogger.info("TileObjectResolver", "summon timer set at %s for %d turns" % [str(coord), duration])

# new internal tick — called from existing _on_player_turn_ended
func _tick_summon_timers() -> void:
    var done: Array[Vector2i] = []
    for coord_v in _summon_timers.keys():
        var c: Vector2i = coord_v
        var t: int = int(_summon_timers[c])
        if t < 0:
            continue   # infinite
        t -= 1
        if t <= 0:
            done.append(c)
        else:
            _summon_timers[c] = t
    for c in done:
        _summon_timers.erase(c)
        var obj_id: StringName = _grid.get_tile_object_id(c)
        if obj_id == &"":
            continue   # already destroyed by combat; cleanup-listener already erased entry — defensive
        var obj: TileObject = _object_registry.get_object(obj_id)
        GameLogger.info("TileObjectResolver", "summoned object %s at %s expired" % [obj_id, str(c)])
        _destroy_object(c, obj)

# new listener — clean up timer if object destroyed by combat before expire
func _on_tile_object_destroyed_summon_cleanup(coord: Vector2i, _obj_id: StringName) -> void:
    _summon_timers.erase(coord)
```

**Connect в `_connect_signals`** (after existing connects):
```gdscript
EventBus.tile_object_destroyed.connect(_on_tile_object_destroyed_summon_cleanup)
```

**Call в `_on_player_turn_ended`** (after `_tick_linger_stacks`):
```gdscript
_tick_summon_timers()
```

### 6. EventBus signal `tile_object_summoned` (new, additive)

```gdscript
signal tile_object_summoned(coord: Vector2i, object_id: StringName, duration: int)
```

Emit в `CreateEffect.apply` после успешного `set_tile_object_id` + `add_summon_timer`. Listener'ов в 041 не вводим — задел для presentation (sparkle FX, "summoned" outline на спрайте).

### 7. CreateEffect ctx requirements

godmode_controller (caster context builder) уже передаёт `grid` и `target_coord` в ctx. Для 041 нужно ещё:
- `ctx["registry"]: ActorRegistry` — godmode уже так делает (см. 026 ability dispatch).
- `ctx["actors_node"]: Node` — потенциально новый ключ. Если godmode сейчас не передаёт — добавить (передаёт `grid.get_node_or_null("Actors")` или fallback на grid).
- `ctx["resolver"]: TileObjectResolver` — godmode не передаёт сейчас. Добавить в ctx-builder. Resolver — scene-local, godmode владеет ссылкой через 019 setup.

См. plan §"ctx wiring" — точные точки правки.

## Acceptance criteria

### AC-1 — Parser: `entity_id` arity
- **AC-1.1:** `_make_effects_from_dict` для key `"entity_id"` использует тот же `_parse_status_string` (или эквивалент с arity-чек), arity=1.
- **AC-1.2:** Малформd value (no parens, empty args, wrong arity, duration=0) — warn + не создаёт CreateEffect инстанс. Skill грузится без эффекта; остальные эффекты в том же dict — не затронуты.
- **AC-1.3:** `duration < 0` (любое) интерпретируется как infinite, на уровне парсера сохраняется как-есть (не нормализуется к -1).
- **AC-1.4:** При парсе `CreateEffect.entity_id = id`, `CreateEffect.duration = args[0]`.

### AC-2 — CreateEffect runtime: object spawn
- **AC-2.1:** id из `TileObjectRegistry` → `grid.set_tile_object_id(coord, id)` + `resolver.add_summon_timer(coord, duration)` + emit `tile_object_summoned(coord, id, duration)`.
- **AC-2.2:** Если `grid.get_tile_object_id(coord) != ""` → no-op, log info.
- **AC-2.3:** Если `grid.get_actor_at(coord) != ""` → no-op (не блокируем актором заходом наверх — actors могут стоять на small-walkable объектах, но spawn-в-actor'а блокируем; consistency с AC-E5).
- **AC-2.4:** После `duration` ходов resolver вызывает `_destroy_object(coord, obj)` — стандартный путь, эмитит `tile_object_destroyed`, обрабатывает `on_destroy_*`.
- **AC-2.5:** Если объект уничтожен боем до истечения — `_summon_timers[coord]` чистится через `tile_object_destroyed` listener; повторный destroy не происходит.

### AC-3 — CreateEffect runtime: actor spawn
- **AC-3.1:** id из EnemyDatabase (file `data/enemies/<id>.json` существует — проверка через `LevelLoader._enemy_data_exists` — нужна публичная exposing, см. plan) → `LevelLoader.spawn_enemy_at(...)` создаёт Actor, регистрирует в registry.
- **AC-3.2:** `spawned.team = caster.team` ставится **после** `spawn_enemy_at` (которое ставит team из JSON), **до** `add_status(summoned)`.
- **AC-3.3:** На spawned actor'а вешается StatusInstance `summoned(duration)` через `add_status` — стандартный путь.
- **AC-3.4:** `EventBus.actor_spawned.emit(spawned.actor_id)` — сразу после регистрации.
- **AC-3.5:** Если `spawn_enemy_at` вернул null (place_actor failure / unknown id) — log warn, no signal.
- **AC-3.6:** Если на хексе уже стоит actor (`grid.get_actor_at(coord) != ""`) — no-op, log info.

### AC-4 — Summoned status runtime
- **AC-4.1:** `summoned(d)` парсится в `_make_status_effects` как любой другой статус — arity=1.
- **AC-4.2:** Тикает через стандартный `Actor.tick_statuses_with_ctx`. Decrement по 1 за turn.
- **AC-4.3:** При `duration <= 0` → `remove_status(&"summoned")` → `SummonedRuntime.on_remove` → `actor.take_damage(actor.hp)` → `actor_died` → registry cleanup.
- **AC-4.4:** `duration = -1` (infinite) — не тикает, не expire'ит. Снимается только если actor умирает по другой причине (combat damage). Status persistence на dead actor не имеет визуальных последствий — actor unregistered.
- **AC-4.5:** Внешнее снятие статуса при `duration > 0` (не реализован путь в 041, но runtime защищён) — actor НЕ убивается, log info.
- **AC-4.6:** Симметрия player↔enemy: any actor can carry summoned (не специфично для team).

### AC-5 — Team override
- **AC-5.1:** Player summons enemy id `bee` → `spawned.team = &"player"`.
- **AC-5.2:** Enemy actor (manekin) summons `bee` через свой skill → `spawned.team = &"enemy"`.
- **AC-5.3:** Spawned actor хранит team в runtime (Actor field), не персистится в JSON; если игра перезапускается — JSON team снова дефолт.
- **AC-5.4:** AI behavior нового spawned actor'а реагирует на свежий team. AI plans next turn после `actor_spawned` (existing 008/034 path).

### AC-6 — Actor tick infinite-duration
- **AC-6.1:** `Actor.tick_statuses_with_ctx` для `inst.duration < 0` пропускает декремент целиком (не зовёт `to_remove.append`).
- **AC-6.2:** Изменение generic — действует на любой статус с `duration < 0`, не специфично для summoned.
- **AC-6.3:** UI (StatusIconStrip) — рисует пилюлю с `-1` или `∞` в зависимости от существующего рендера. Не правим в 041; если читается уродливо — отдельная UI-задача.

### AC-7 — Resolver summon timers
- **AC-7.1:** `add_summon_timer(coord, duration)` хранит entry. `duration=0` — warn + ignore.
- **AC-7.2:** `duration < 0` — entry хранится без декремента; check в `_tick_summon_timers` skip'ает infinite.
- **AC-7.3:** `_tick_summon_timers` вызывается раз за `_on_player_turn_ended`, после `_tick_linger_stacks`.
- **AC-7.4:** На expire — `_destroy_object(coord, obj)` (existing private). Emits `tile_object_destroyed`, on_destroy chains работают.
- **AC-7.5:** Listener `_on_tile_object_destroyed_summon_cleanup(coord, _id)` — `_summon_timers.erase(coord)`. Idempotent: если destroy пришёл из самого `_tick_summon_timers`, повторная erase — no-op.

### AC-8 — Migration sample skills
- **AC-8.1:** `data/skills/summon_bee.json` — `entity_id` value: `"bee"` → `"bee(3)"`.
- **AC-8.2:** `data/skills/bee_summon_bee.json` — то же.
- **AC-8.3:** `data/skills/teapot_spill_the_t.json` — то же (duration=3 для согласованности; balance — Stasyan reviews).
- **AC-8.4:** Никаких других .json в `data/skills/` не использует bare `entity_id` (grep verify).
- **AC-8.5:** Bare-id формат больше не парсится — load summon_bee со старым форматом → AbilityDatabase warn + skip create-effect; skill ability грузится без CreateEffect, остальные эффекты ОК.

### AC-9 — Boot-time id collision check
- **AC-9.1:** После загрузки `TileObjectRegistry` и `LevelLoader._enemy_data_exists` (через scan dir) — boot-time валидатор перебирает intersect и логирует warn-once для каждого дубликата.
- **AC-9.2:** Дубликат не блокирует загрузку. CreateEffect runtime берёт object вариант (детерминированный приоритет).
- **AC-9.3:** Валидатор живёт в `CreateEffect` static block (или в новом утильном `EntitySpawnHelper.gd` — TBD в plan).

## JSON migration

Designer-facing миграция — все existing summon skills:

| Файл | Было | Стало |
|---|---|---|
| `data/skills/summon_bee.json` | `"entity_id": "bee"` | `"entity_id": "bee(3)"` |
| `data/skills/bee_summon_bee.json` | `"entity_id": "bee"` | `"entity_id": "bee(3)"` |
| `data/skills/teapot_spill_the_t.json` | `"entity_id": "..."` | `"entity_id": "...(3)"` |

После merge — для всех новых summon skills использовать формат `id(d)`. Bare-id больше не валиден.

## Open after playtest

- **Default duration для balance** — все санплы 3 хода. Stasyan подкручивает per-skill после плейтеста.
- **`summoned` family color** — `neutral` или новый tier. UI ставит дефолт debuff если family unknown — отслеживаем после первого плейтеста.
- **`-1` infinite UI rendering** — пилюля с `-1`/`∞`/нет цифры — TBD по визуалу.
- **Обработка id collision** — сейчас priority object>actor + warn. Если коллизии случатся (одинаковые имена в data/enemies/ и data/tile_objects/) — может оказаться удобнее force-prefix или namespace. Решение откладываем до первого реального конфликта.
- **Object summon — UI duration display** — у TileObject нет статусной системы → нет пилюли. Презентация (если нужна) — отдельный спек.

## Out of scope

- Класс `Entity` (см. clarify-round, variant B).
- Rename `tile_object*` → `object*` (см. clarify-round, variant C).
- `Entity` базовый класс / Spawnable trait / common interface.
- `(d, hp, dmg)` мультиаргс для скейла spawned actor'а — arity жёстко 1.
- Object-as-caster — caster всегда Actor.
- TileObject status-system — у объектов нет _statuses dict, не вводим.
- Save/load duration mid-summon.
- VFX/SFX summon-channel (collision_effect / sound_end уже на Ability).
- Multi-area summon FX flourish (chain BFS уже работает per existing area kind).
- Recursive summon limit / budget.
- Summon-skill icon hint (UI-полиш).
