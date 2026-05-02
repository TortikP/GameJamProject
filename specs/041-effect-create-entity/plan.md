# 041-effect-create-entity — plan

См. `spec.md` для **что** и acceptance criteria. Здесь — **как**.

## Файлы и масштаб

| Файл | Изменение | Объём |
|---|---|---|
| `scripts/core/abilities/effects/create_effect.gd` | Реальная implement: split на object-spawn vs actor-spawn, ctx wiring, EventBus emit. | ~80 строк |
| `scripts/core/abilities/ability_database.gd` | `entity_id` parsing — переход на `_parse_status_string` (arity=1, args=[duration]). Boot-time collision check (object-id vs enemy-id). | ~40 строк |
| `scripts/core/maps/level_loader.gd` | Публичный `enemy_data_exists(id) -> bool` (или alias) — был приватный. Чтоб AbilityDatabase / CreateEffect могли проверять без duplicate FileAccess. | ~5 строк (rename + add public) |
| `scripts/core/actors/actor.gd` | 1-line surgery: `if inst.duration < 0: continue` в `tick_statuses_with_ctx`. | 2 строки |
| `scripts/core/statuses/runtimes/summoned_runtime.gd` | NEW — `class_name SummonedRuntime`, только `on_remove` overridden. | ~25 строк |
| `scripts/core/statuses/status_registry.gd` | `&"summoned": preload(...)` в `_RT_BY_ID`. | 1 строка |
| `data/status_effects/summoned.json` | NEW. Family `neutral`, arity 1. | ~10 строк |
| `scripts/core/arena/tile_object_resolver.gd` | `_summon_timers` field, `add_summon_timer`, `_tick_summon_timers`, listener `_on_tile_object_destroyed_summon_cleanup`, hookups в `_connect_signals` + `_on_player_turn_ended`. | ~50 строк |
| `scripts/infrastructure/event_bus.gd` | `signal tile_object_summoned(coord: Vector2i, object_id: StringName, duration: int)`. | 1 строка |
| `scripts/presentation/godmode/cast_fsm.gd` | ctx['actors_node'] + ctx['resolver'] в обеих ctx-build точках (line ~87, ~133). | 4 строки |
| `scripts/presentation/godmode/godmode_input.gd` | Идём по ctx-build на line 191 — добавить два ключа. | 2 строки |
| `scripts/presentation/godmode/ai_driver.gd` | ctx-build на line ~239 (skill cast path) — добавить два ключа. **Не** в `world_ctx` (это для tick_statuses, без spawn). | 2 строки |
| `data/skills/summon_bee.json` | `"entity_id": "bee"` → `"bee(3)"` | 1 строка |
| `data/skills/bee_summon_bee.json` | то же | 1 строка |
| `data/skills/teapot_spill_the_t.json` | то же | 1 строка |
| `CLAUDE.md` | "Currently claimed" — добавить 041-effect-create-entity — Egor. | 1 строка |

**Total:** ~225 строк изменений. 1 NEW status runtime, 1 NEW JSON, 1 NEW signal, 0 NEW classes.

## Парсер: `entity_id: "id(d)"`

В `ability_database.gd:_make_effects_from_dict`, ветка `if key == "entity_id"`:

```gdscript
# было (026):
# Defensive type pattern (CLAUDE.md trap #6): Variant→Object→cast.
var script_v: Variant = EFFECT_KIND_BY_KEY[key]
var inst: Object = (script_v as GDScript).new()
for k in data.keys():
    if k == "kind" or k == "status" or k == "status_id" or k == "duration":
        continue
    inst.set(k, data[k])
var eff := inst as AbilityEffect
if eff != null:
    out.append(eff)

# стало (041) — отдельная ветка ДО общего fan-out:
if key == "entity_id":
    var parsed: Dictionary = _parse_status_string(String(data[key]))
    if parsed.is_empty():
        GameLogger.warn("AbilityDatabase", "%s: malformed entity_id '%s' (expected 'id(duration)')" % [ability_id, str(data[key])])
        continue
    var args: Array[int] = parsed["args"]
    if args.size() != 1:
        GameLogger.warn("AbilityDatabase", "%s: entity_id arity mismatch — expected 1 (duration), got %d" % [ability_id, args.size()])
        continue
    var dur: int = args[0]
    if dur == 0:
        GameLogger.warn("AbilityDatabase", "%s: entity_id duration=0 invalid — skipping" % ability_id)
        continue
    var ce := CreateEffect.new()
    ce.entity_id = parsed["id"]
    ce.duration = dur
    out.append(ce)
    continue
```

Ветка должна стоять **до** общего блока `EFFECT_KIND_BY_KEY[key].new()` в loop. CreateEffect больше не получает entity_id через `inst.set("entity_id", ...)` из generic broadcast.

**Removed key from generic broadcast filter** (line ~268):
```gdscript
# было:
if k == "kind" or k == "status" or k == "status_id" or k == "duration":
# стало:
if k == "kind" or k == "status" or k == "status_id" or k == "duration" or k == "entity_id":
```

(защита: если effect dict содержит и `damage` и `entity_id`, generic loop не должен попытаться set'ить entity_id на DamageEffect.)

## CreateEffect — целиком

```gdscript
class_name CreateEffect
extends AbilityEffect
## Spawns an entity (tile-object or actor) at ctx["target_coord"] for `duration` turns.
## entity_id resolved via TileObjectRegistry first, then EnemyDatabase (data/enemies/<id>.json).
## Object: grid.set_tile_object_id + resolver.add_summon_timer.
## Actor:  LevelLoader.spawn_enemy_at + add_status(summoned). Caster.team copies onto spawned.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@export var entity_id: StringName = &""
@export var duration: int = 0   # 0 invalid (parser rejects); >0 turns; -1 infinite

# Static counter for unique enemy_id suffixes — shared across all CreateEffect instances.
# Bumped per-spawn; collision with WaveController's _enemy_id_counter is harmless
# (different scope of name uniqueness — registry just dedupes by full id).
static var _summon_counter: int = 0


func _init() -> void:
    requires_alive_target = false


func apply(caster: Actor, _target: Variant, ctx: Dictionary) -> void:
    var coord_var: Variant = ctx.get("target_coord")
    if not coord_var is Vector2i:
        return
    var coord: Vector2i = coord_var

    var grid: HexGrid = ctx.get("grid")
    if grid == null:
        GameLogger.warn("CreateEffect", "no grid in ctx — skip")
        return

    if entity_id == &"":
        return
    if duration == 0:
        return  # parser already filters but defensive

    # AC-E5: occupied actor blocks both object and actor spawns.
    if grid.get_actor_at(coord) != &"":
        GameLogger.info("CreateEffect", "%s: actor on hex %s — skip spawn '%s'" % [caster.actor_id, str(coord), entity_id])
        return

    # Resolution: object first, actor fallback.
    var object_reg: TileObjectRegistry = grid.get_object_registry()
    if object_reg != null and object_reg.has_object(entity_id):
        _spawn_object(coord, grid, ctx)
        return
    if LevelLoader.enemy_data_exists(entity_id):
        _spawn_actor(coord, caster, ctx)
        return
    GameLogger.warn("CreateEffect", "unknown entity_id '%s' (not in TileObjectRegistry nor data/enemies/)" % entity_id)


func _spawn_object(coord: Vector2i, grid: HexGrid, ctx: Dictionary) -> void:
    if grid.get_tile_object_id(coord) != &"":
        GameLogger.info("CreateEffect", "tile %s already has object — skip object-spawn '%s'" % [str(coord), entity_id])
        return
    var resolver: TileObjectResolver = ctx.get("resolver")
    if resolver == null:
        GameLogger.warn("CreateEffect", "no resolver in ctx — skip object-spawn '%s' at %s" % [entity_id, str(coord)])
        return
    grid.set_tile_object_id(coord, entity_id)
    resolver.add_summon_timer(coord, duration)
    EventBus.tile_object_summoned.emit(coord, entity_id, duration)
    GameLogger.info("CreateEffect", "summoned object '%s' at %s for %d turns" % [entity_id, str(coord), duration])


func _spawn_actor(coord: Vector2i, caster: Actor, ctx: Dictionary) -> void:
    var grid: HexGrid = ctx["grid"]
    var registry: ActorRegistry = ctx.get("registry")
    if registry == null:
        GameLogger.warn("CreateEffect", "no registry in ctx — skip actor-spawn '%s'" % entity_id)
        return
    var actors_node: Node = ctx.get("actors_node")
    if actors_node == null:
        actors_node = grid.get_node_or_null("Actors")
    if actors_node == null:
        actors_node = grid

    _summon_counter += 1
    var spawned: Actor = LevelLoader.spawn_enemy_at(grid, registry, actors_node, coord, entity_id, _summon_counter)
    if spawned == null:
        return  # spawn_enemy_at already warned

    # Universal team override — spawned inherits caster's team.
    spawned.team = caster.team

    # Apply summoned status (drives lifetime).
    var inst := StatusInstance.new()
    inst.status_id = &"summoned"
    inst.duration = duration
    inst.args = [duration] as Array[int]
    inst.source_id = caster.actor_id
    spawned.add_status(inst)

    EventBus.actor_spawned.emit(spawned.actor_id)
    GameLogger.info("CreateEffect", "summoned actor '%s' (id=%s, team=%s) at %s for %d turns" %
        [entity_id, spawned.actor_id, spawned.team, str(coord), duration])
```

**Зависимости:**
- `LevelLoader.enemy_data_exists` — public alias на `_enemy_data_exists`.
- `HexGrid.get_object_registry()` — already exists (см. godmode_setup.gd:86).
- `TileObjectResolver.add_summon_timer` — новый метод.

## SummonedRuntime — целиком

```gdscript
class_name SummonedRuntime
extends StatusRuntime
## summoned(d) — entity lifetime tracker. Decrement по 1 за turn (через
## стандартный Actor.tick_statuses); при duration<=0 → on_remove убивает.
## d=-1 → infinite (Actor.tick_statuses пропускает декремент при duration<0).
##
## NB: только для actor'ов. Tile-object'ы используют side-table в
## TileObjectResolver._summon_timers — у них нет статусной системы.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")


static func compute_snapshot(args: Array[int], _skill_level: int) -> int:
    return args[0] if args.size() > 0 else 0   # store original duration for inspectors; not used in logic


static func on_remove(actor: Actor, instance: StatusInstance) -> void:
    if not actor.is_alive():
        return
    if instance.duration > 0:
        GameLogger.info("SummonedRuntime", "%s summoned removed early (duration=%d) — not killing" % [actor.actor_id, instance.duration])
        return
    GameLogger.info("SummonedRuntime", "%s summoned expired — destroying" % actor.actor_id)
    actor.take_damage(actor.hp)
```

## TileObjectResolver — добавления

В `scripts/core/arena/tile_object_resolver.gd`:

```gdscript
# (после существующих var _runtime_hp, _linger_stack:)
# 041: coord -> int turns_left. >0 ticks down; -1 infinite.
var _summon_timers: Dictionary = {}


# в setup() / _connect_signals — после existing connects:
EventBus.tile_object_destroyed.connect(_on_tile_object_destroyed_summon_cleanup)


# Public API — called by CreateEffect after grid.set_tile_object_id.
func add_summon_timer(coord: Vector2i, duration: int) -> void:
    if duration == 0:
        GameLogger.warn("TileObjectResolver", "add_summon_timer: duration=0 invalid for %s — ignored" % str(coord))
        return
    _summon_timers[coord] = duration
    GameLogger.info("TileObjectResolver", "summon timer set at %s for %d turns" % [str(coord), duration])


# в _on_player_turn_ended — после _tick_linger_stacks():
_tick_summon_timers()


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
            continue
        var obj: TileObject = _object_registry.get_object(obj_id)
        GameLogger.info("TileObjectResolver", "summoned object %s at %s expired" % [obj_id, str(c)])
        _destroy_object(c, obj)


func _on_tile_object_destroyed_summon_cleanup(coord: Vector2i, _obj_id: StringName) -> void:
    _summon_timers.erase(coord)
```

**Pathfinder rebuild?** Не делаем после spawn / despawn одного object. `_destroy_object` уже не дёргает `rebuild_pathfinder` (см. existing implementation), и existing `set_tile_object_id` в `LevelLoader.apply_to` тоже rebuild'ит **один раз batch'ом**. Для одиночного summon — pathfinder может оставаться чуть устаревшим до следующего batch update / wave change. Acceptable trade-off для джема. Если AI начнёт ходить через свежеспавнённый wall — добавим `grid.rebuild_pathfinder()` в `_spawn_object`. **Не делаем preemptively.**

## Actor.tick_statuses_with_ctx — diff

Точная замена в `scripts/core/actors/actor.gd` (около строки 320):

```gdscript
# === BEFORE ===
        if rt != null:
            rt.on_turn_start(self, inst, ctx)
        if _dead:
            return   # DoT killed us; remaining statuses won't tick this turn
        inst.duration -= 1
        any_decremented = true
        if inst.duration <= 0:
            to_remove.append(inst.status_id)

# === AFTER ===
        if rt != null:
            rt.on_turn_start(self, inst, ctx)
        if _dead:
            return   # DoT killed us; remaining statuses won't tick this turn
        if inst.duration < 0:
            continue   # 041: infinite-duration sentinel — never decrement, never expire
        inst.duration -= 1
        any_decremented = true
        if inst.duration <= 0:
            to_remove.append(inst.status_id)
```

## ctx wiring — точные точки

### `scripts/presentation/godmode/cast_fsm.gd`

Site 1 — около строки 87, в `try_start`:
```gdscript
var pre_ctx: Dictionary = {
    "registry": registry, "grid": grid,
    "target_id": grid.get_actor_at(coord), "target_coord": coord,
    "actors_node": grid.get_node_or_null("Actors"),         # 041
    "resolver": _ctrl.tile_object_resolver,                  # 041
}
```

Site 2 — около строки 133, в `_commit_step`:
```gdscript
var ctx: Dictionary = {
    "registry": _ctrl.registry, "grid": _ctrl.grid,
    "target_id": ..., "target_coord": ...,
    "actors_node": _ctrl.grid.get_node_or_null("Actors"),    # 041
    "resolver": _ctrl.tile_object_resolver,                  # 041
}
```

### `scripts/presentation/godmode/godmode_input.gd`

Около строки 191 — same pattern. Получит `_ctrl` reference (уже имеется через cast_fsm caller path; если в этой функции нет — брать из nearest scope).

### `scripts/presentation/godmode/ai_driver.gd`

Около строки 239 (skill cast ctx — НЕ `world_ctx` line 36). `world_ctx` для status tick остаётся без изменений.

```gdscript
# было:
var ctx: Dictionary = {
    "registry": registry, "grid": grid,
    ...
}
# стало:
var ctx: Dictionary = {
    "registry": registry, "grid": grid,
    "actors_node": grid.get_node_or_null("Actors"),
    "resolver": _ctrl.tile_object_resolver,
    ...
}
```

## Boot-time id collision check

В `AbilityDatabase._ready` — после `_load_dir`, или новым явным validator method, который вызывается из autoload init после загрузки databases. Точное место: **в конце** `AbilityDatabase._ready`, потому что к тому моменту все skills и tile_objects уже загружены (autoload order: StatusRegistry → TileObjectRegistry-internal-load-from-grid... — но `TileObjectRegistry` создаётся per-grid, не autoload).

**Проблема:** `TileObjectRegistry` — НЕ autoload. Он создаётся в `HexGrid.initialize()`, scene-local. На момент `AbilityDatabase._ready` он ещё не существует.

**Решение:** validator живёт **в первом успешном CreateEffect.apply за сцену** (lazy, once-per-grid). Хранится statically:

```gdscript
# в create_effect.gd:
static var _collision_check_done_for: Dictionary = {}   # WeakRef[HexGrid] -> bool

static func _validate_id_collisions_once(grid: HexGrid) -> void:
    var key := grid.get_instance_id()
    if _collision_check_done_for.has(key):
        return
    _collision_check_done_for[key] = true
    var object_reg: TileObjectRegistry = grid.get_object_registry()
    if object_reg == null:
        return
    for obj_id in object_reg.get_all_ids():
        if LevelLoader.enemy_data_exists(obj_id):
            GameLogger.warn("CreateEffect", "id collision: '%s' is BOTH a tile-object and an enemy — runtime picks tile-object" % obj_id)
```

Вызывается первой строкой `CreateEffect.apply` через `_validate_id_collisions_once(grid)`. Один лог за scene-load. WeakRef через `get_instance_id()` — если grid пересоздан, key отличается, валидатор перезапустится; для джема приемлемо (лишний раз залогирует, не более).

## Test plan (manual smoke)

1. **Object summon + expire:**
   - В godmode, дать игроку skill `summon_bee` отредактированный на object id (например, `wooden_barrel(3)`).
   - Кастуем в пустую клетку → видим объект (если sprite загружен) + лог `summoned object 'wooden_barrel' at (x,y) for 3 turns`.
   - 3 раза ходим player_turn_end → лог `summoned object wooden_barrel at (x,y) expired` + лог `destroyed wooden_barrel at (x,y)`.

2. **Object summon + early destroy:**
   - Summon `wooden_barrel(5)`, после 2 ходов attack barrel → `tile_object_destroyed`. На 5-м ходу нет повторного destroy log (timer был очищен через listener).

3. **Actor summon + team override:**
   - Skill `summon_bee` (`bee(3)`). Кастуем игроком в пустую клетку.
   - Проверяем `spawned.team == &"player"` через ActorInspector / лог.
   - Bee начинает атаковать enemies вместо player'а.
   - Через 3 хода — `summoned expired` → `bee_001 take_damage(hp)` → `actor_died`.

4. **Actor summon + early death:**
   - Призываем `bee(5)`, бьём его до 0 hp на 2-м ходу. Ничего падает не должно. На 5-м ходу — нет повторного take_damage (actor уже dead).

5. **Infinite duration:**
   - Edit skill: `bee(-1)`. Cast. После 10 player turns — bee всё ещё жив. `_statuses["summoned"].duration` остаётся `-1` всё время. Killing him manually работает нормально.

6. **Multi-hex area summon:**
   - Edit `summon_bee.json` area to `zone_circle area_radius=1` (3 хекса вокруг target, ну ± occupy filtering).
   - Cast в центр пустой группы — спавнятся 7 bees? Нет, spawn check — actor on target hex (per-hex применение из area resolution). Каждая bee — отдельный CreateEffect.apply call. Для каждого hex: occupied? skip; иначе spawn.

7. **Unknown id:**
   - Skill с `entity_id: "nonsense(3)"`. Cast → лог warn `unknown entity_id 'nonsense'`. Никакого спавна, ничего не падает.

8. **Malformed JSON:**
   - Skill с `entity_id: "bee"` (без скобок). Boot — лог warn `malformed entity_id 'bee'`. Skill грузится, ability грузится, но без CreateEffect; cast → no-op для эффекта create, но другие эффекты в том же dict работают.

9. **Id collision warning:**
   - Создать `data/tile_objects/manekin.json` (id collision с enemy `manekin`). Запустить godmode → cast любой summon skill → один-раз warn `id collision: 'manekin' is BOTH a tile-object and an enemy`.

10. **Player summon + enemy AI replan:**
    - Cast `summon_bee` рядом с manekin. На следующий world_turn manekin должен в `actor_status_added` уже учитывать новую bee как ally игрока (не атаковать её).

## Risks

- **R1: Pathfinder stale после object-summon.** Если призванный wall блокирует AI route — AI может попытаться идти через него и зависнуть (или рухнуть). Mitigation: smoke в test plan #1 видит это; если найдём — добавим `grid.rebuild_pathfinder()` в `_spawn_object`.
- **R2: enemy.tscn _ready vs add_status timing.** `spawn_enemy_at` делает `add_child(enemy)` → `_ready` запускается; `add_status(summoned)` идёт **после** `_ready` (в нашем коде). `_ready` инициализирует `hp = max_hp`, статусные коллекции пустые. На момент `add_status` всё готово. ✓
- **R3: AI планирует cast'ы до spawned bee'и.** AI делает план в начале своего turn'а. Spawn в player'овский turn → `actor_spawned` эмитится → `actor_status_added` тоже (через `add_status`) → existing 034 replan handler в godmode_controller перепланирует enemies. ✓ (но это — existing behavior; верифицируем в smoke #10).
- **R4: `_summon_counter` static — collision с `WaveController._enemy_id_counter`.** Оба формируют id `<entity_id>_NNN`. Если оба считают с 1 и оба спавнят `bee` → возможна коллизия `bee_001`. Mitigation: префикс — стартануть с большого числа (`_summon_counter` от 10000) или пропускать через registry conflict check (registry уже warn'ит и overwrite'ит). Я выбираю — стартануем с 10000 для prefix-disambiguation. **Implement note:** в init `_summon_counter = 9999`, первый bump делает 10000.
- **R5: TileObject sprite/visual.** TileObject — data class. Visual представление tile_objects обычно через TileMap source 1 (`hex_atlas.png`) — если spawned id не имеет atlas tile, на гриде ничего не нарисуется (data-only). Mitigation: для smoke берём существующие id (`wooden_barrel`, `bush` — те что уже в data/tile_objects/ и имеют визуал). Не блокер для логики.
- **R6: `summoned.json` family `neutral` — UI fallback.** Если `UiTheme.STATUS_PILL_COLORS` не имеет `neutral` ключа — strip отрисует дефолтным. Возможный косяк: пилюля `summoned` совпадёт по цвету с debuff. Mitigation: оставляем; визуал-полиш — отдельная задача.
- **R7: status save через get_status before tick.** Никаких snapshots / save — out of scope. Всё runtime-only.

## Cut list (если время поджимает)

1. **Hard cut: убрать infinite (-1).** Парсер требует `duration > 0`, runtime path для `duration < 0` не нужен. Actor.tick_statuses surgery откатывается. Resolver: `_summon_timers` всегда тикает. **Save:** ~10 строк, удаляет 1 acceptance branch.
2. **Hard cut: убрать object-summon path.** Только actors. CreateEffect — один branch. Resolver `_summon_timers` не нужен, `tile_object_summoned` signal не нужен. **Save:** ~50 строк. Жертва: skills, призывающие лужи/барьеры, не работают; но в текущем pool таких нет — все summon'ы actor'ов.
3. **Cut id collision warning (boot validator).** Дубликаты id — warn в runtime CreateEffect.apply при попадании в обе ветки (already implicit: object-first, второй registry даже не проверяется). Implementation simpler.
4. **Cut `tile_object_summoned` signal.** Если presentation не подписывается — никому не нужен. Удалить emit.
5. **Cut team override.** Spawned actor сохраняет JSON team. Тогда player summon bee — bee.team = `&"enemy"` (из JSON), bee бьёт игрока. Игровая логика бьётся. **Не cut'аем без острой нужды.**

Default — без cut'ов. Cut'ы по приоритету сверху.
