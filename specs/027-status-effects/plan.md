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

data/ai_behaviors/
  feared.json                  # NEW — feared scenario (kite_specific_actor)
  enraged.json                 # NEW — enraged scenario (approach_specific_actor + damage rule)

scripts/core/statuses/
  status_instance.gd           # data resource
  status_registry.gd           # autoload (preload table → runtime classes + JSON metadata)
  status_runtime.gd            # base abstract
  runtimes/
    stunned_runtime.gd
    slowed_runtime.gd
    poisoned_runtime.gd
    rooted_runtime.gd
    feared_runtime.gd          # behavior_id swap
    burning_runtime.gd
    glitched_runtime.gd
    shielded_runtime.gd
    enraged_runtime.gd         # behavior_id swap

scripts/core/ai/
  selectors/selector_specific_actor.gd          # NEW — reads ctx.behavior_target_id
  policies/policy_approach_specific_actor.gd    # NEW
  policies/policy_kite_specific_actor.gd        # NEW
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
  enemy_ai_planner.gd          # bail-on-stunned; ctx-enrichment behavior_target_id;
                               # _build_target_candidates special-case for SelectorSpecificActor
  behavior_database.gd         # register new selector/policy kinds
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

# Called by Actor.add_status AFTER the instance is stored. Side effects
# on the actor are allowed (e.g. behavior_id swap for feared/enraged).
# Default — no-op.
static func on_apply(_actor: Actor, _instance: StatusInstance) -> void:
    pass

# Called by Actor.remove_status BEFORE the instance is erased. Symmetric
# to on_apply (e.g. restore behavior_id). Default — no-op.
static func on_remove(_actor: Actor, _instance: StatusInstance) -> void:
    pass

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

# Called by AI planner BEFORE scenario.movement_policy.pick_step.
# Sentinel return values:
#   Vector2i(-1,-1) → defer to default policy (no override)
#   Vector2i(-2,-2) → hold this turn (no move_intent set)
#   Any other Vector2i → use as actor.move_intent_coord
# Used ONLY by slowed (flip-flop) and rooted (always hold).
# Feared/enraged DO NOT use this hook — they swap behavior_id via on_apply
# and let the dedicated scenario's movement_policy handle steering.
static func override_movement(_actor: Actor, _instance: StatusInstance, _ctx: Dictionary) -> Vector2i:
    return Vector2i(-1, -1)
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

# Behavior-override state (used by feared/enraged runtimes).
# &"" when no override is active.
var _original_behavior_id: StringName = &""
var _behavior_override_id: StringName = &""

const _BEHAVIOR_OVERRIDE_IDS: Array[StringName] = [&"feared", &"enraged"]

func add_status(instance: StatusInstance) -> void:
    # Mutual exclusivity for behavior-override statuses (AC-RA3):
    # applying feared while enraged is active (or vice versa) — silently
    # remove the active one first. Same status_id re-apply is handled by
    # the standard replace branch below; no special case needed.
    if instance.status_id in _BEHAVIOR_OVERRIDE_IDS:
        for other_id in _BEHAVIOR_OVERRIDE_IDS:
            if other_id != instance.status_id and _statuses.has(other_id):
                remove_status(other_id)   # triggers other.on_remove → restore

    # Re-apply branch: if same status_id exists, fire its on_remove first
    # (so e.g. shielded.snapshot doesn't leak; on_apply will set the new one).
    if _statuses.has(instance.status_id):
        var old: StatusInstance = _statuses[instance.status_id]
        var old_rt: Variant = StatusRegistry.runtime_for(old.status_id)
        if old_rt != null:
            old_rt.on_remove(self, old)

    _statuses[instance.status_id] = instance       # store (AC-RA1 — replace)
    var rt: Variant = StatusRegistry.runtime_for(instance.status_id)
    if rt != null:
        rt.on_apply(self, instance)
    statuses_changed.emit(actor_id)

func remove_status(id: StringName) -> void:
    if not _statuses.has(id):
        return
    var inst: StatusInstance = _statuses[id]
    var rt: Variant = StatusRegistry.runtime_for(id)
    if rt != null:
        rt.on_remove(self, inst)
    _statuses.erase(id)
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

func tick_statuses_with_ctx(ctx: Dictionary) -> void:
    if _dead: return
    var to_remove: Array[StringName] = []
    var ids: Array = _statuses.keys()
    for id_v in ids:
        if not _statuses.has(id_v):  # may have been removed mid-loop
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
        # Use full remove_status path so on_remove fires (AC-BO2 for feared/enraged).
        remove_status(id)

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

`tick_statuses_with_ctx` берёт `ctx: Dictionary` от caller'а
(godmode_controller передаёт `_world_ctx()`). `remove_status` — единая
точка для expire-on-tick и manual-remove (например при mutual exclusivity);
гарантирует, что `on_remove` всегда фирится.

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
- `on_apply(actor, inst)` — behavior swap:
  - `if actor._behavior_override_id == &"": actor._original_behavior_id = actor.behavior_id`
  - `actor._behavior_override_id = &"feared"`
  - `actor.behavior_id = &"feared"`
- `on_remove(actor, inst)` — behavior restore:
  - `if actor._behavior_override_id == &"feared":`
  - `    actor.behavior_id = actor._original_behavior_id`
  - `    actor._behavior_override_id = &""`
  - `    actor._original_behavior_id = &""`
- `on_turn_start(actor, inst, ctx)`: source-validity check —
  `var src := ActorRegistry.get_actor(inst.source_id); if src == null or not src.is_alive(): inst.duration = 0` (expire next sweep, on_remove restore'ит behavior).
- `override_movement` — НЕ override'ит. Steering — на dedicated `feared` сценарии.

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
- `on_apply(actor, inst)` — поведение симметрично feared, но с
  `actor.behavior_id = &"enraged"`. Mutual-exclusivity между feared и
  enraged ensure'ится в `Actor.add_status` (см. delta выше) — runtime
  предполагает, что предыдущий behavior-override уже снят.
- `on_remove(actor, inst)` — restore (то же тело, что у feared, но
  чек на `&"enraged"`).
- `on_turn_start(actor, inst, ctx)`: source-validity check (то же что у feared).
- `override_movement` — не override'ит. Steering — на сценарии `enraged`.

### AI scenario building blocks (для feared / enraged)

Feared и enraged НЕ override'ят policy/selector через runtime hooks.
Вместо этого они **swap'ят `actor.behavior_id`** на dedicated сценарий.
Сценарий читает `behavior_target_id: StringName` из ctx (добавленного
планировщиком из активного status'а).

**1. Новые AI-блоки.**

`scripts/core/ai/selectors/selector_specific_actor.gd`:
```gdscript
class_name SelectorSpecificActor
extends TargetSelector

func resolve(_actor: Actor, candidates: Array, _ctx: Dictionary) -> Variant:
    # candidates уже отфильтрован _build_target_candidates'ом
    # (singleton с этим actor'ом, или пустой если source мёртв).
    return candidates[0] if not candidates.is_empty() else null
```

`scripts/core/ai/policies/policy_approach_specific_actor.gd`:
```gdscript
class_name PolicyApproachSpecificActor
extends MovementPolicy

func pick_step(actor: Actor, ctx: Dictionary) -> Vector2i:
    var grid: HexGrid = ctx.get("grid")
    var bid: StringName = ctx.get("behavior_target_id", &"")
    if grid == null or bid == &"":
        return Vector2i(-1, -1)
    var src: Actor = ActorRegistry.get_actor(bid)
    if src == null or not src.is_alive():
        return Vector2i(-1, -1)
    var my_coord: Vector2i = grid.get_coord(actor.actor_id)
    var src_coord: Vector2i = grid.get_coord(src.actor_id)
    if my_coord == Vector2i(-1, -1) or src_coord == Vector2i(-1, -1):
        return Vector2i(-1, -1)
    # Block all other actors (same logic as PolicyApproachNearestEnemy).
    var blocked: Array[Vector2i] = []
    for other_v in ctx.get("all_actors", []):
        if not (other_v is Actor): continue
        var other: Actor = other_v
        if other == actor or other == src or not other.is_alive(): continue
        var c: Vector2i = grid.get_coord(other.actor_id)
        if c != Vector2i(-1, -1): blocked.append(c)
    var path: Array = grid.find_path_around(my_coord, src_coord, blocked)
    if path.size() < 2:
        return Vector2i(-1, -1)
    return path[1]
```

`scripts/core/ai/policies/policy_kite_specific_actor.gd`:
```gdscript
class_name PolicyKiteSpecificActor
extends MovementPolicy

func pick_step(actor: Actor, ctx: Dictionary) -> Vector2i:
    # Симметрично approach: source-валидация одинакова, но шаг — на
    # соседний хекс с максимальным hex_distance до source. Если все
    # доступные шаги уменьшают дистанцию — return (-1,-1) (hold).
    var grid: HexGrid = ctx.get("grid")
    var bid: StringName = ctx.get("behavior_target_id", &"")
    if grid == null or bid == &"": return Vector2i(-1, -1)
    var src: Actor = ActorRegistry.get_actor(bid)
    if src == null or not src.is_alive(): return Vector2i(-1, -1)
    var my_coord: Vector2i = grid.get_coord(actor.actor_id)
    var src_coord: Vector2i = grid.get_coord(src.actor_id)
    if my_coord == Vector2i(-1, -1) or src_coord == Vector2i(-1, -1):
        return Vector2i(-1, -1)
    var current_d: int = grid.hex_distance(my_coord, src_coord)
    var best_step: Vector2i = my_coord
    var best_d: int = current_d
    for n in grid.tile_map_layer.get_surrounding_cells(my_coord):
        if not grid.is_walkable(n): continue
        if grid.get_actor_at(n) != &"": continue
        var d: int = grid.hex_distance(n, src_coord)
        if d > best_d:
            best_d = d; best_step = n
    if best_step == my_coord: return Vector2i(-1, -1)
    return best_step
```

**2. Регистрация в `behavior_database.gd`** — добавить case'ы в три match:

```gdscript
# _build_selector
"specific_actor": return SelectorSpecificActor.new()

# _build_policy
"approach_specific_actor": return PolicyApproachSpecificActor.new()
"kite_specific_actor":     return PolicyKiteSpecificActor.new()
```

**3. Сценарии — `data/ai_behaviors/feared.json`:**
```json
{
  "id": "feared",
  "rules": [],
  "movement_policy": {"kind": "kite_specific_actor"},
  "fallback_skill_id": ""
}
```

**`data/ai_behaviors/enraged.json`:**
```json
{
  "id": "enraged",
  "rules": [
    {
      "condition": {"kind": "always"},
      "target_selector": {"kind": "specific_actor"},
      "tag_priority": ["damage"],
      "min_skill_count": 1
    }
  ],
  "movement_policy": {"kind": "approach_specific_actor"},
  "fallback_skill_id": ""
}
```

Note: enraged rule использует `condition_always` — out-of-range source
автоматически отсекается на existing'е `_target_in_skill_range` →
правило не fire'ит → планировщик сваливается на `policy_approach_specific_actor`.
Не нужен новый `condition_specific_actor_in_range`.

**4. `enemy_ai_planner.plan` delta:**

```gdscript
func plan(actor: Actor, ctx: Dictionary) -> void:
    actor.cast_intent = null
    actor.move_intent_coord = Vector2i(-1, -1)
    if not actor.is_alive(): return

    # 027: stunned bail
    if actor.is_stunned(): return

    # 027: ctx-enrichment with behavior_target_id from active feared/enraged.
    # Read in priority order — last applied wins per AC-RA3, but in practice
    # mutual exclusivity means at most one is active.
    var bid: StringName = &""
    if actor.has_status(&"enraged"):
        bid = (actor.get_statuses_by_id(&"enraged") as StatusInstance).source_id
    elif actor.has_status(&"feared"):
        bid = (actor.get_statuses_by_id(&"feared") as StatusInstance).source_id
    if bid != &"":
        ctx["behavior_target_id"] = bid

    # 027: status-driven movement override (slowed flip-flop / rooted hold).
    # Runs BEFORE scenario logic — if any status returns (-2,-2), we hold
    # the movement step but still let scenario rules try to cast.
    var hold_movement: bool = false
    for inst_v in actor.get_statuses():
        var inst := inst_v as StatusInstance
        var rt: Variant = StatusRegistry.runtime_for(inst.status_id)
        if rt == null: continue
        var ov: Vector2i = rt.override_movement(actor, inst, ctx)
        if ov == Vector2i(-2, -2):
            hold_movement = true
            break

    # ... existing scenario-resolve / rules-loop / movement-policy fallthrough ...
    # The movement_policy.pick_step result is suppressed if hold_movement.
```

`Actor.get_statuses_by_id(id)` — вспомогательный, возвращает StatusInstance
или null. Тривиальный — добавить в Actor delta.

**5. `_build_target_candidates` delta** — special-case для SelectorSpecificActor:

```gdscript
func _build_target_candidates(actor: Actor, selector: TargetSelector, ctx: Dictionary) -> Array:
    if selector is SelectorSelf:
        return [actor]
    # 027: SelectorSpecificActor reads behavior_target_id, ignores team filter.
    if selector is SelectorSpecificActor:
        var bid: StringName = ctx.get("behavior_target_id", &"")
        if bid == &"": return []
        var src: Actor = ActorRegistry.get_actor(bid)
        if src == null or not src.is_alive(): return []
        return [src]
    # ... existing ally/enemy filter logic ...
```

### Зачем такая раздача

- Steering feared/enraged живёт в данных (`data/ai_behaviors/*.json`), а не в коде runtime'а.
- Designer может (при добавлении новых behavior-override статусов) создать новый
  сценарий + JSON-метаданные status'а без правок планировщика.
- Test'ировать поведение проще — debug-скрипты могут принудительно
  установить `actor.behavior_id = &"feared"` без статус-системы.
- Изолированность: код status-runtime'а трогает только `behavior_id` +
  `_original_behavior_id`, ничего больше из AI surface.

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
          for each expired status:
            actor.remove_status(id)  # fires on_remove → behavior_id restore for feared/enraged
          emit statuses_changed (if any change)
    if player.is_stunned():
      delay → TurnManager.advance() → recursion to top
      RETURN  (no enemy phase)
    _run_enemy_turn():
      for each enemy:
        if enemy.is_stunned(): skip plan/resolve
        else:
          enemy_ai_planner.plan(enemy, ctx_enriched_with_behavior_target_id):
            scenario := BehaviorDatabase.get_scenario(enemy.behavior_id)
                       # for feared/enraged AI — this is "feared"/"enraged"
                       # scenario, not default_melee
            try rules → try movement_policy → fallback skill
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

- `Actor.get_statuses_by_id(id) -> StatusInstance` helper — добавить в
  Actor delta (тривиальный getter).
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
