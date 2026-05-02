# 027-status-effects — plan

**Owner:** Egor
**Spec:** `specs/027-status-effects/spec.md`

Технический план: классы, файлы, точки правок. Tasks — `tasks.md`.

## Файловое дерево (новое)

```
data/status_effects/
  stunned.json
  slowed.json
  poisoned.json
  rooted.json
  feared.json
  burning.json
  glitched.json
  shielded.json
  enraged.json

data/skills/
  test_status_runtime.json     # NEW — для AC-X3

scripts/core/statuses/
  status_instance.gd           # data resource
  status_registry.gd           # autoload (preload table → runtime classes + JSON metadata)
  status_runtime.gd            # base abstract
  runtimes/
    stunned_runtime.gd
    slowed_runtime.gd
    poisoned_runtime.gd
    rooted_runtime.gd
    feared_runtime.gd
    burning_runtime.gd
    glitched_runtime.gd
    shielded_runtime.gd
    enraged_runtime.gd
```

## Изменяемые файлы

```
scripts/core/abilities/
  ability_effect.gd            # remove `duration` field
  effects/damage_effect.gd     # remove duration usage (none currently — confirm)
  effects/heal_effect.gd       # remove duration usage (none currently)
  effects/move_effect.gd       # apply_level — drop duration scaling branch
  effects/create_effect.gd     # nothing (already no duration usage)
  effects/status_effect.gd     # rewrite — new fields, args parsing, instance creation
  ability_database.gd          # parse `status` value as string → id+args; drop legacy `duration` parsing softly

scripts/core/actors/
  actor.gd                     # add _statuses, signals, methods, take_damage delta

scripts/core/ai/
  enemy_ai_planner.gd          # if actor.is_stunned() → bail
  policies/policy_approach_nearest_enemy.gd  # honor effective_speed (just for rooted)
  policies/policy_kite_from_nearest_enemy.gd # same

scripts/core/turn/
  turn_manager.gd              # nothing (uses existing world_turn_ended)

scripts/presentation/
  status_icon_strip.gd         # bind_actor → real subscription
  godmode/godmode_controller.gd  # _on_world_turn_ended: tick statuses first; player stun-skip path; slot grey if stunned
  godmode/move_range_overlay.gd  # use actor.effective_speed() not actor.speed

scenes/dev/
  player.tscn                  # add StatusIconStrip child node
  manekin.tscn                 # add StatusIconStrip child node

config/
  game_speed.cfg               # add `arena.stun_skip_delay = 0.4`

project.godot                  # autoload StatusRegistry

data/skills/                   # ALL 15 skill files — migrate effects
  ...
```

## Компонентная разводка

### `StatusInstance` (data, no behaviour)

```gdscript
class_name StatusInstance
extends Resource

@export var status_id: StringName = &""
@export var duration: int = 0
@export var args: Array[int] = []
@export var source_id: StringName = &""
@export var snapshot_value: int = 0       # pre-computed scaling result
# Stateful flag for slowed flip-flop. Per-runtime, initialised as needed.
@export var rt_flag: int = 0
```

Не наследуется. Поведение — в `StatusRuntime`-классах. Один шейп для всех
9 статусов; runtime-конкретные стейты идут в `args` (чтение) и `rt_flag`
(запись на tick'е). Простота > чистота.

### `StatusRuntime` (abstract base)

```gdscript
class_name StatusRuntime
extends RefCounted

# Called once at apply-time. Returns precomputed snapshot_value
# (scales args by skill_level per runtime's formula).
# Default — 0.
static func compute_snapshot(_args: Array[int], _skill_level: int) -> int:
    return 0

# Called at start of actor's tick. May call actor.take_damage,
# may set instance.duration = 0 to expire early, may set rt_flag.
static func on_turn_start(_actor: Actor, _instance: StatusInstance, _ctx: Dictionary) -> void:
    pass

# Called from actor.effective_speed(). Returns post-modifier speed
# (typically `current` or 0 or current/2). Chain: each runtime sees
# previous result. Order: rooted → slowed → others (rooted wins).
static func modify_speed(_current: int, _instance: StatusInstance) -> int:
    return _current

# Called from actor.damage_reduction() — sums all instances.
# Default 0. Only shielded overrides.
static func damage_reduction(_instance: StatusInstance) -> int:
    return 0

# Called by AI movement_policy to override step pick.
# Returns Vector2i(-1,-1) to defer to default policy.
static func override_movement(_actor: Actor, _instance: StatusInstance, _ctx: Dictionary) -> Vector2i:
    return Vector2i(-1, -1)

# Called by AI cast_intent target selector — returns preferred victim_id
# (or &"" to defer).
static func override_cast_target(_actor: Actor, _instance: StatusInstance, _ctx: Dictionary) -> StringName:
    return &""
```

Все методы — `static`. Runtime — stateless, состояние живёт в
`StatusInstance`. Нет инстанцирования runtime-объектов; lookup даёт
GDScript-класс через `StatusRegistry`.

### `StatusRegistry` (autoload)

```gdscript
extends Node
const _RT_BY_ID: Dictionary = {
    &"stunned":  preload("res://scripts/core/statuses/runtimes/stunned_runtime.gd"),
    &"slowed":   preload("res://scripts/core/statuses/runtimes/slowed_runtime.gd"),
    ...
}

var _meta: Dictionary = {}   # status_id -> {family, arity, param_names, loc_*}

func _ready():
    # load all data/status_effects/*.json into _meta
    ...

func runtime_for(id: StringName) -> Variant:  # returns GDScript or null
func meta_for(id: StringName) -> Dictionary
func family_of(id: StringName) -> StringName
func arity_of(id: StringName) -> int
```

Регистрируется в `project.godot` autoloads (как EventBus, GameSpeed).

### `Actor` (delta)

```gdscript
signal statuses_changed(actor_id: StringName)

# CLAUDE trap #6: Dictionary not Array[StatusInstance].
var _statuses: Dictionary = {}   # status_id -> StatusInstance

func add_status(instance: StatusInstance) -> void:
    _statuses[instance.status_id] = instance       # re-apply replaces (AC-RA1)
    statuses_changed.emit(actor_id)

func remove_status(id: StringName) -> void:
    if _statuses.erase(id):
        statuses_changed.emit(actor_id)

func get_statuses() -> Array:
    return _statuses.values()

func has_status(id: StringName) -> bool:
    return _statuses.has(id)

func is_stunned() -> bool:
    return _statuses.has(&"stunned")

func effective_speed() -> int:
    var s: int = speed
    for inst_v in _statuses.values():
        var inst := inst_v as StatusInstance
        var rt: Variant = StatusRegistry.runtime_for(inst.status_id)
        if rt != null:
            s = rt.modify_speed(s, inst)
    return maxi(0, s)

func damage_reduction() -> int:
    var sum: int = 0
    for inst_v in _statuses.values():
        var inst := inst_v as StatusInstance
        var rt: Variant = StatusRegistry.runtime_for(inst.status_id)
        if rt != null:
            sum += rt.damage_reduction(inst)
    return sum

func tick_statuses() -> void:
    if _dead: return
    var to_remove: Array[StringName] = []
    var ctx: Dictionary = {}   # filled by caller via set_meta? — see below
    # Snapshot keys to allow safe expire-during-iter.
    var ids: Array = _statuses.keys()
    for id_v in ids:
        if not _statuses.has(id_v):  # may have been removed mid-loop (cascading)
            continue
        var inst := _statuses[id_v] as StatusInstance
        var rt: Variant = StatusRegistry.runtime_for(inst.status_id)
        if rt != null:
            rt.on_turn_start(self, inst, ctx)
        if _dead:
            return  # actor died from DoT; short-circuit
        inst.duration -= 1
        if inst.duration <= 0:
            to_remove.append(inst.status_id)
    for id in to_remove:
        _statuses.erase(id)
    if not to_remove.is_empty():
        statuses_changed.emit(actor_id)

# take_damage delta
func take_damage(amount: int) -> void:
    if _dead or amount <= 0: return
    var reduced: int = maxi(0, amount - damage_reduction())
    if reduced <= 0:
        # absorbed entirely — still emit a "0-dmg" feedback? skip for now.
        return
    hp = max(0, hp - reduced)
    damaged.emit(actor_id, reduced, hp)
    EventBus.damage_dealt.emit(actor_id, reduced, global_position)
    GameLogger.info("Actor", "%s -%d hp (%d/%d) [reduced from %d]" % [actor_id, reduced, hp, max_hp, amount])
    if hp == 0:
        _dead = true
        died.emit(actor_id)
        EventBus.actor_died.emit(actor_id)
```

`tick_statuses` берёт `ctx: Dictionary` пустым — runtime-методам, которым
нужны `grid` или `actor_registry`, выдёргивают через autoload (ActorRegistry,
HexGrid из ctx-supplier). Альтернатива — `tick_statuses(ctx)` с прокидыванием
из godmode_controller. Беру **второй** вариант для явности; см. tasks.

### Runtime-классы — конкретика

**`stunned_runtime`:**
- `compute_snapshot` → 0 (не нужен)
- `on_turn_start` → no-op (логика «skip turn» — на стороне planner'а через `actor.is_stunned()`)

**`slowed_runtime`:**
- `compute_snapshot` → 0
- `modify_speed(s, inst)` → `floor(s / 2)`
- `on_turn_start` → toggle `inst.rt_flag = 1 - inst.rt_flag` — для AI флип-флопа в `override_movement` ниже не нужно: проще чем в AI, дёргаем `effective_speed`. Player — speed/2 через MoveRangeOverlay, без флип-флопа.
- AI policy — после правки честно использует speed → если 0, не двигается. Но baseline AI шагает 1 хекс/turn, не speed. Нужно: AI policy honor `actor.effective_speed()`. Если 0 — bail. Если ≥1 — берёт path[1] как сейчас. Slowed, у которого speed=1 → effective=0 → не двигается. Слишком жёстко (AI с slowed не двигается совсем). Альтернатива: per-instance флип-флоп — `on_turn_start` тогглит rt_flag, `override_movement` возвращает `Vector2i(-2,-2)` (sentinel «hold») при rt_flag==1. См. ниже.

**Решение для slowed-AI:** добавить sentinel `Vector2i(-2,-2)` от `override_movement` означающий «hold this turn» (отличный от `(-1,-1)` = «defer»). `enemy_ai_planner` чекает override result; `(-2,-2)` → не emit'ит move_intent. `slowed_runtime.override_movement`: тоггли `rt_flag`, на rt_flag==1 → return `(-2,-2)`, иначе `(-1,-1)`. Player не использует override_movement (управление вручную) — для player'а slowed работает только через `effective_speed`.

**`poisoned_runtime`:**
- `compute_snapshot(args, level)` → `args[1] + level * args[2]` (т.е. `dmg_pct + level * lvl_bonus_pct`)
- `on_turn_start(actor, inst, _ctx)` → `actor.take_damage(floor(actor.max_hp * inst.snapshot_value / 100))`

**`rooted_runtime`:**
- `modify_speed(_s, _inst)` → `0`
- `override_movement` → `(-2,-2)` (hold)

**`feared_runtime`:**
- `compute_snapshot` → 0
- `on_turn_start(actor, inst, ctx)`:
  - `var src := ActorRegistry.get_actor(inst.source_id)`
  - if src == null или not is_alive() → `inst.duration = 0` (expire next sweep)
- `override_movement(actor, inst, ctx)`:
  - на player'е (variant C): defer → `(-1,-1)`. Но как runtime знает, что target — player? Через `actor.team == &"player"`. Это знание на core-уровне допустимо (team — поле Actor).
  - На AI: вычислить шаг, который максимизирует `hex_distance(self, source)`; см. plan §"AI movement override impl".

**`burning_runtime`:**
- `compute_snapshot(args, level)` → `args[1] + level * args[2]`
- `on_turn_start(actor, inst, _ctx)` → `actor.take_damage(inst.snapshot_value)`

**`glitched_runtime`:**
- pure stub. Все методы — defaults.

**`shielded_runtime`:**
- `compute_snapshot(args, level)` → `args[1] + level * args[2]`
- `damage_reduction(inst)` → `inst.snapshot_value`

**`enraged_runtime`:**
- `compute_snapshot` → 0
- `on_turn_start` — source-validity check как у feared
- `override_movement(actor, inst, ctx)`:
  - на player'е: defer → `(-1,-1)`
  - на AI: шаг к source (ровно как `policy_approach_nearest_enemy`, но target_coord = source_coord фиксирован)
- `override_cast_target(actor, inst, ctx)`:
  - на AI: если source_coord в `actor.cast_intent.ability.target.range` — return `inst.source_id` как preferred victim.
  - на player'е: defer → `&""`

### AI movement override impl (feared / enraged)

`enemy_ai_planner.plan` после bail-on-stunned, ДО existing scenario logic:

```gdscript
# Status overrides win over scenario.movement_policy.
for inst_v in actor.get_statuses():
    var inst := inst_v as StatusInstance
    var rt: Variant = StatusRegistry.runtime_for(inst.status_id)
    if rt == null: continue
    var override: Vector2i = rt.override_movement(actor, inst, ctx)
    if override == Vector2i(-2, -2):
        actor.move_intent_coord = Vector2i(-1, -1)
        return  # hold completely
    if override != Vector2i(-1, -1):
        actor.move_intent_coord = override
        # don't return — cast planning may still proceed
        break
```

Аналогично для cast-target override — patch'им `_resolve_cast_intent` в
godmode_controller (или, лучше, в AI-target-selector — но где он?).

Проверить, где AI выбирает victim_coord для cast'а. Если централизованно
в `_resolve_cast_intent` — патчим там; если в каждом scenario rule —
проще прокинуть через `_select_cast_target(actor, ability) -> coord`
helper. Конкретный путь — выяснить во время implement'а; добавить TODO
в task.

### Парсер — `_make_effects_from_dict` delta

```gdscript
const EFFECT_KEY_ORDER: Array[String] = ["damage", "heal", "status", "move_type", "entity_id"]

func _make_effects_from_dict(data: Dictionary, ability_id: String) -> Array[AbilityEffect]:
    if data.has("kind"):
        GameLogger.warn("AbilityDatabase", "%s: legacy 'kind' in effect — ignoring" % ability_id)
    if data.has("duration"):
        GameLogger.info("AbilityDatabase", "%s: legacy 'duration' in effect — ignoring (027 schema)" % ability_id)
    var out: Array[AbilityEffect] = []
    for key in EFFECT_KEY_ORDER:
        if not data.has(key): continue
        if key == "status":
            var eff := _make_status_effect(data["status"], ability_id)
            if eff != null: out.append(eff)
            continue
        # existing logic for other keys (damage, heal, move_type, entity_id)
        ...
    return out

func _make_status_effect(value: Variant, ability_id: String) -> StatusEffect:
    if not (value is String):
        GameLogger.warn("AbilityDatabase", "%s: status must be string, got %s" % [ability_id, type_string(typeof(value))])
        return null
    var parsed: Dictionary = _parse_status_string(value as String)
    if parsed.is_empty():
        GameLogger.warn("AbilityDatabase", "%s: malformed status string '%s'" % [ability_id, value])
        return null
    var id: StringName = parsed["id"]
    var args: Array = parsed["args"]   # Array[int]
    var expected_arity: int = StatusRegistry.arity_of(id)
    if expected_arity == 0:
        GameLogger.warn("AbilityDatabase", "%s: unknown status_id '%s'" % [ability_id, id])
        return null
    if args.size() != expected_arity:
        GameLogger.warn("AbilityDatabase", "%s: status '%s' arity mismatch — expected %d, got %d" % [ability_id, id, expected_arity, args.size()])
        return null
    var eff := StatusEffect.new()
    eff.status_id = id
    eff.args = args
    return eff

# "burning(2, 3, 1)" -> {id: &"burning", args: [2, 3, 1]}
# "stunned(2)"      -> {id: &"stunned", args: [2]}
# Returns {} on malformed input.
func _parse_status_string(s: String) -> Dictionary:
    var open := s.find("(")
    var close := s.rfind(")")
    if open <= 0 or close < 0 or close <= open: return {}
    var id := s.substr(0, open).strip_edges()
    if id.is_empty(): return {}
    var argstr := s.substr(open + 1, close - open - 1)
    var args: Array[int] = []
    if argstr.strip_edges() != "":
        for piece in argstr.split(","):
            var trimmed := piece.strip_edges()
            if not trimmed.is_valid_int(): return {}
            args.append(trimmed.to_int())
    return {"id": StringName(id), "args": args}
```

### `StatusEffect.apply` delta

```gdscript
class_name StatusEffect extends AbilityEffect

@export var status_id: StringName = &""
@export var args: Array[int] = []

const _StatusInstance = preload("res://scripts/core/statuses/status_instance.gd")

# `_skill_level` is filled by Ability.cast (021) — Ability.cast(caster, ctx, level)
# duplicates each effect and calls apply_level(level) before apply.
# We snapshot level into a private field via apply_level.
var _level: int = 0

func apply_level(level: int) -> void:
    _level = level

func apply(caster: Actor, target: Variant, _ctx: Dictionary) -> void:
    var actor := target as Actor
    if actor == null: return
    if status_id == &"" or args.is_empty(): return
    var rt: Variant = StatusRegistry.runtime_for(status_id)
    if rt == null:
        GameLogger.warn("StatusEffect", "no runtime for '%s'" % status_id)
        return
    var inst := _StatusInstance.new()
    inst.status_id = status_id
    inst.duration = args[0]
    inst.args = args.duplicate()
    inst.source_id = caster.actor_id if caster != null else &""
    inst.snapshot_value = rt.compute_snapshot(args, _level)
    actor.add_status(inst)
```

### `godmode_controller` delta

```gdscript
func _on_world_turn_ended(_turn: int) -> void:
    if _world_processing: return
    if player == null or not player.is_alive(): return
    _world_processing = true
    _tick_all_statuses()
    if player.is_alive() and player.is_stunned():
        await get_tree().create_timer(GameSpeed.get_value("arena", "stun_skip_delay", 0.4)).timeout
        # advance player turn — but wait, advance fires world_turn_ended again, recursion.
        # Order: end player processing FIRST, THEN advance. See below.
        _world_processing = false
        TurnManager.advance()
        return
    await _run_enemy_turn()
    _world_processing = false
    _refresh_overlay()

func _tick_all_statuses() -> void:
    var ctx: Dictionary = _world_ctx()
    for actor in registry.all():
        if actor is Actor and (actor as Actor).is_alive():
            (actor as Actor).tick_statuses_with_ctx(ctx)
```

**Важно — рекурсия.** `TurnManager.advance` emit'ит `world_turn_ended` →
`_on_world_turn_ended` снова. Это не плохо: на следующем тике статусы
снова тикнутся, если stunned ещё активен — снова skip; пока не expire
или player не умрёт. `_world_processing` flag предотвращает re-entrancy
в пределах одного фрейма. Цепочка stun-tick-skip-tick-skip... выглядит
как «несколько тёмных кадров» — желательно с visual feedback'ом, но
icon'а stunned над player'ом достаточно (AC-X5).

Player slot grey: добавить в HUD-обработчик ввода Q/W/E/R чек
`if player.is_stunned(): return` (и визуально — отдельный путь: HUD
подписан на `statuses_changed`, рисует `disabled`-overlay на слотах
если stunned). Конкретный путь UI — в существующем skill_slot widget'е
(найти при impl'е, добавить task).

### `MoveRangeOverlay` delta

```gdscript
# Was: actor.speed
# Now: actor.effective_speed()
var reachable: Array[Vector2i] = _grid.reachable_within(actor_coord, actor.effective_speed(), occupied)
```

Один touch.

## Order of operations (sanity check)

```
world_turn_ended(N)
  godmode_controller._on_world_turn_ended:
    _tick_all_statuses():
      for each alive actor:
        actor.tick_statuses_with_ctx(ctx)
          for each status (insertion order):
            runtime.on_turn_start(actor, inst, ctx)  # DoT damage, source-check
            if actor died → break out
            inst.duration -= 1
          remove expired, emit statuses_changed
    if player.is_stunned():
      delay → TurnManager.advance() → recursion to top
      RETURN  (no enemy phase)
    _run_enemy_turn():
      for each enemy:
        if enemy.is_stunned(): skip plan/resolve
        else: existing logic, with movement-override hooks
```

## Тесты / smoke

- AC-X-серия — godmode-сцена. Дополнительно:
- `test_status_runtime.json` — single-ability, `{"status": "poisoned(3, 10, 2)"}`,
  target_actor range 4. Бинд на debug-слот. Каст по manekin'у → 3 turn'а
  visible -10hp/turn (через floating numbers).
- `test_combo_hex_circle_damage_status.json` — после миграции,
  ability с `{"damage": 8}, {"status": "burning(2, 3, 1)"}` — мгновенный
  damage 8 + burning visible 2 turn'а.

## Open questions / TODO в коде

- AI cast-target selector path — найти централизованную точку, где AI
  выбирает victim_coord. Если её нет (каждый scenario rule сам выбирает) —
  добавить hook через override_cast_target. Точное место — в task'е.
- Если actor спавнится без `StatusIconStrip` ребёнка (тестовые сцены) —
  Actor не падает, лог info. Уже учтено в spec AC-UI.
- `glitched` runtime — пустой класс. Если в будущем нужно реальное
  поведение — добавить отдельным spec'ом, runtime-класс уже зарегистрирован.

## Зависимости с другими ветвями

- 026 ветка (если ещё не merged в staging) — конфликтует на
  `ability_database.gd` (`_make_effects_from_dict`) и `status_effect.gd`.
  Резолв: 027 после 026 в очереди мержей. Если 026 в staging на момент
  старта 027 — ребейз тривиальный.
- 008-ветки Сергея на enemy_ai_planner — feared/enraged hook'и
  пересекаются с его scenario rules. Координация в чате до push'а.
