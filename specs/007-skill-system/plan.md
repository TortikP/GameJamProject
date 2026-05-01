# 007-skill-system — plan

**Owner:** Egor
**Spec:** [`spec.md`](./spec.md) · **Status:** Ready for /tasks → /implement

## Архитектурный обзор

Расширяем существующий контракт `Ability` (`scripts/core/abilities/`, THEME_PLAN §4) до двухуровневой системы:

```
Skill
├── cooldown: int
└── abilities: Array[Ability]   # упорядоченно
       │
       ├── target: AbilityTarget       # КАТЕГОРИЯ цели: entity / hex / direction / object
       ├── area:   AbilityArea         # как target превращается в Array[victim]: self / chain / zone_*
       ├── effects: Array[AbilityEffect]  # 1..N, упорядоченно
       └── modifiers: Array[ParameterModifier]  # параметр-мутаторы на ability ИЛИ на её effects
```

Ключевые семантические разделения относительно сегодняшнего кода:

- **Target = категория, не resolver.** Сегодня `single_enemy` / `single_enemy_adjacent` совмещают «что игрок может выбрать» и «куда применить». Разводим: `target` = что игрок кликает (hex / entity / direction / object); `area` = как из этого получить список жертв.
- **Area — единственный источник списка жертв.** «Single target» = `chain` с `max_chain_length=1`. Отдельной "self_target" сущности не вводим.
- **Effect[] вместо Effect.** Внутри одной способности эффекты применяются по порядку к каждой жертве: внешний цикл по жертвам, внутренний по эффектам (см. AC-X3).
- **Modifier — параметр-мутатор.** Один класс `ParameterModifier` для всех числовых правок, формула из AC-M5 коммутативна. Старый hook-style `AbilityModifier` удаляется (см. миграцию).

## File layout

### Новые файлы

```
scripts/core/skills/
├── skill.gd                     # class_name Skill
└── skill_database.gd            # autoload, по образцу AbilityDatabase

scripts/core/abilities/
├── ability_area.gd              # abstract base class_name AbilityArea
├── parameter_modifier.gd        # class_name ParameterModifier (заменяет ability_modifier.gd)
├── areas/
│   ├── self_area.gd             # AbilityArea — [caster]
│   ├── chain_area.gd            # max_chain_length, BFS-цепочка по гексам
│   ├── zone_circle_area.gd      # radius
│   ├── zone_cone_area.gd        # range, angle (P2)
│   ├── zone_arc_area.gd         # range, inner_radius, angle (P2)
│   └── zone_line_area.gd        # length
├── effects/
│   ├── heal_effect.gd
│   ├── status_effect.gd
│   ├── move_effect.gd           # push / pull / teleport — поглощает старый knockback_modifier
│   └── create_effect.gd
└── targets/
    ├── entity_target.gd         # любая Actor-сущность по target_id из ctx
    ├── hex_target.gd            # Vector2i из ctx.target_coord
    ├── direction_target.gd      # вектор от caster
    └── object_target.gd         # пассивный объект (P2 — нет такого слоя пока)

data/skills/
└── *.json                       # новый каталог
```

### Изменяемые файлы

```
scripts/core/abilities/ability.gd            # +area; effect→effects[]; новый cast() lifecycle
scripts/core/abilities/ability_effect.gd     # +id, +type, +duration, +requires_alive_target
scripts/core/abilities/ability_target.gd     # упрощается: только категория цели, без resolve→Array[Actor]
scripts/core/abilities/ability_database.gd   # новые registry-словари: AREA_KINDS, расширенный TARGET/EFFECT
scripts/core/abilities/effects/damage_effect.gd  # rename amount→damage; +duration scaffold для DoT
scripts/infrastructure/event_bus.gd          # +signal skill_cast(caster_id, skill_id, target_ids)
project.godot                                # +autoload SkillDatabase
data/abilities/*.json                        # миграция в новую схему
THEME_PLAN.md                                # §4 переписать под новый контракт (документ, не код)
```

### Удаляемые файлы

```
scripts/core/abilities/ability_modifier.gd                  # заменён parameter_modifier.gd
scripts/core/abilities/modifiers/knockback_modifier.gd      # → move_effect.gd
scripts/core/abilities/targets/single_enemy_target.gd       # → entity_target.gd + chain(1)
scripts/core/abilities/targets/single_enemy_adjacent_target.gd  # → entity_target.gd + chain(1) с adjacency-валидатором
```

## Module API contracts

### `Skill` (`scripts/core/skills/skill.gd`)

```gdscript
class_name Skill
extends Resource

@export var id: StringName
@export var cooldown: int = 0
@export var abilities: Array[Ability] = []

# State (runtime, не в JSON)
var _cd_remaining: int = 0

func is_ready() -> bool
func cast(caster: Actor, ctx: Dictionary) -> bool   # true если хотя бы одна способность отработала
func tick_cooldown(by: int = 1) -> void             # уменьшает _cd_remaining; вызывается из turn_manager
```

Конкретика тика cooldown (per-turn / per-cast / на чьём ходе) уточняется в /implement — но контракт `tick_cooldown` стабильный.

### `Ability` (existing, расширяется)

```gdscript
class_name Ability
extends Resource

@export var id: StringName
@export var target: AbilityTarget
@export var area: AbilityArea
@export var effects: Array[AbilityEffect] = []
@export var modifiers: Array[ParameterModifier] = []

func can_apply(caster: Actor, ctx: Dictionary) -> bool
func cast(caster: Actor, ctx: Dictionary) -> bool
func predicted_damage_to(caster: Actor, t: Actor, ctx: Dictionary) -> int  # учёт modifier-формулы
```

### `AbilityTarget` (упрощается)

```gdscript
class_name AbilityTarget
extends Resource
# Категория цели. resolve() возвращает ОДНО значение (не массив).

func resolve(caster: Actor, ctx: Dictionary) -> Variant   # Actor | Vector2i | Vector2 | Object
func can_apply(caster: Actor, ctx: Dictionary) -> bool
func get_range_hexes(caster_coord: Vector2i, grid: HexGrid) -> Array[Vector2i]
```

Подклассы: `entity_target`, `hex_target`, `direction_target`, `object_target`.

### `AbilityArea` (новый)

```gdscript
class_name AbilityArea
extends Resource
# Превращает target в упорядоченный список жертв (ближайшая → дальняя).

func resolve(caster: Actor, primary_target: Variant, ctx: Dictionary) -> Array
func get_affected_hexes(caster_coord: Vector2i, primary: Variant, grid: HexGrid) -> Array[Vector2i]
```

Подклассы:
- `SelfArea` — `[caster]`, игнорирует target.
- `ChainArea` — `@export var max_chain_length: int = 1`. BFS-цепочка ближайших соседей по гексам, без повторов.
- `ZoneCircleArea` — `@export var radius: int`. Круг гексов вокруг target.
- Прочие зоны (cone/arc/line) — те же контракты, разная геометрия.

«Single target» = `ChainArea(max_chain_length=1)`. Отдельный класс не нужен.

### `AbilityEffect` (расширяется)

```gdscript
class_name AbilityEffect
extends Resource

@export var id: StringName
@export var type: StringName                   # "damage" | "heal" | "status" | "move" | "create"
@export var duration: int = 0                  # 0 = мгновенный, >0 = тиков/ходов
@export var requires_alive_target: bool = true # дефолт безопасный

func apply(caster: Actor, target: Variant, ctx: Dictionary) -> void
```

Подклассы: `DamageEffect(damage: int)`, `HealEffect(heal: int)`, `StatusEffect(status: StringName)`, `MoveEffect(move_type: StringName, move_distance: int)`, `CreateEffect(game_object_id: StringName)`.

`requires_alive_target` дефолты по типу: damage/heal/status/move = `true`; create = `false`.

`target: Variant` потому что разные эффекты бьют по разным сущностям (Actor / Vector2i / Object). Эффект сам приводит тип и валидирует — тихий no-op если не подходит (стиль уже есть в проекте: «Лучше странно работает чем упало», THEME_PLAN §4).

### `ParameterModifier` (новый, заменяет старый AbilityModifier)

```gdscript
class_name ParameterModifier
extends Resource

@export var id: StringName
@export var target_param: StringName           # "damage", "heal", "max_chain_length", "duration", ...
@export var op: StringName = &"add"            # "add" | "mul"
@export var value: float = 0.0

func applies_to(obj: Object) -> bool           # true если obj имеет свойство target_param
```

Применение — централизованно в `Ability.cast()`, по группам по параметру (см. ниже).

## Lifecycle: `Ability.cast(caster, ctx)`

```
1. if target == null or area == null or effects.is_empty(): error → false
2. primary = target.resolve(caster, ctx)
3. eff_area = area.duplicate(); _apply_param_modifiers(eff_area, modifiers)
4. victims = eff_area.resolve(caster, primary, ctx)   # уже упорядочены ближайшая→дальняя
5. if victims.is_empty(): return false (без ошибки, навык продолжается)
6. for victim in victims:
       for base_eff in effects:
           eff_dup = base_eff.duplicate()
           _apply_param_modifiers(eff_dup, modifiers)
           if eff_dup.requires_alive_target and _is_dead(victim): continue
           eff_dup.apply(caster, victim, ctx)
7. EventBus.ability_cast.emit(caster.actor_id, id, _ids_of(victims))
8. return true
```

`_apply_param_modifiers(obj, mods)` — группирует модификаторы по `target_param`:
```
for each param p in {m.target_param for m in mods if m.applies_to(obj)}:
    add_sum = Σ m.value where m.target_param == p and m.op == "add"
    mul_prod = Π m.value where m.target_param == p and m.op == "mul"
    base = obj.get(p)
    final = (base + add_sum) * mul_prod
    obj.set(p, _coerce(final, type_of(base)))   # int → floor, float → as-is
```

## Lifecycle: `Skill.cast(caster, ctx)`

```
1. if not is_ready(): return false
2. for ab in abilities: ab.cast(caster, ctx)   # каждая может вернуть false (нет целей) — навык продолжается
3. _cd_remaining = cooldown
4. EventBus.skill_cast.emit(caster.actor_id, id, _aggregated_target_ids)
5. return true
```

Обрати внимание: между `ab.cast()` цели мира меняются (кто-то мёртв, переместился). Каждая способность резолвит цели заново — это и обеспечивает кейс вампиризма (AC-X7).

## Data schemas

### `data/skills/*.json`

```json
{
  "id": "vamp_strike",
  "cooldown": 2,
  "tags": ["damage"],
  "abilities": [
    {
      "id": "vamp_strike_dmg",
      "target": {"kind": "entity"},
      "area":   {"kind": "chain", "max_chain_length": 1},
      "effects": [
        {"kind": "damage", "id": "vs_dmg", "duration": 0, "damage": 12}
      ],
      "modifiers": []
    },
    {
      "id": "vamp_strike_heal",
      "target": {"kind": "entity"},
      "area":   {"kind": "self"},
      "effects": [
        {"kind": "heal", "id": "vs_heal", "duration": 0, "heal": 6}
      ],
      "modifiers": []
    }
  ]
}
```

### `data/abilities/*.json` (новая схема одиночной способности)

```json
{
  "id": "fireball",
  "target": {"kind": "hex"},
  "area":   {"kind": "zone_circle", "radius": 2},
  "effects": [
    {"kind": "damage", "id": "fb_dmg", "duration": 0, "damage": 15},
    {"kind": "status", "id": "fb_burn", "duration": 3, "status": "burning"}
  ],
  "modifiers": [
    {"kind": "parameter", "id": "fb_extra", "target_param": "damage", "op": "add", "value": 5},
    {"kind": "parameter", "id": "fb_amped", "target_param": "damage", "op": "mul", "value": 1.5}
  ]
}
```

### Registry-словари в `AbilityDatabase`

```gdscript
const TARGET_KINDS := {
    "entity":    preload("res://scripts/core/abilities/targets/entity_target.gd"),
    "hex":       preload("res://scripts/core/abilities/targets/hex_target.gd"),
    "direction": preload("res://scripts/core/abilities/targets/direction_target.gd"),
    "object":    preload("res://scripts/core/abilities/targets/object_target.gd"),
}

const AREA_KINDS := {
    "self":         preload(".../areas/self_area.gd"),
    "chain":        preload(".../areas/chain_area.gd"),
    "zone_circle":  preload(".../areas/zone_circle_area.gd"),
    "zone_cone":    preload(".../areas/zone_cone_area.gd"),
    "zone_arc":     preload(".../areas/zone_arc_area.gd"),
    "zone_line":    preload(".../areas/zone_line_area.gd"),
}

const EFFECT_KINDS := {
    "damage": preload(".../effects/damage_effect.gd"),
    "heal":   preload(".../effects/heal_effect.gd"),
    "status": preload(".../effects/status_effect.gd"),
    "move":   preload(".../effects/move_effect.gd"),
    "create": preload(".../effects/create_effect.gd"),
}

const MODIFIER_KINDS := {
    "parameter": preload(".../parameter_modifier.gd"),
}
```

## EventBus integration

```gdscript
# event_bus.gd — добавить:
signal skill_cast(caster_id: StringName, skill_id: StringName, target_ids: Array)
```

`ability_cast` остаётся: эмитится из каждой способности внутри навыка. UI получает оба сигнала — `skill_cast` для глобального cooldown-индикатора, `ability_cast` для локальных pop-up'ов урона.

## Hex-геометрия — что используем

- `hex_grid.get_walkable_neighbours(coord)` — для chain (соседи).
- `hex_grid.reachable_within(from, max_steps, occupied)` — для zone_circle (radius == max_steps, occupied = []).
- Для zone_cone / zone_arc / zone_line нужны новые геометрические хелперы — ставим в /implement, могут потребовать `hex_grid.gd` правки. Если правок hex_grid не избежать — мерджить отдельно через Egor (owner модуля).

## Migration of existing `data/abilities/*.json`

| Файл | Старая семантика | Новая схема |
|---|---|---|
| `melee_punch.json` | single_enemy_adjacent + damage(8) | target=entity, area=chain(1), effects=[damage(8)] + adjacency-проверка в `EntityTarget.can_apply` через `ctx.requires_adjacent` или валидатор на стороне caller |
| `debug_punch.json` | single_enemy + damage(5) | target=entity, area=chain(1), effects=[damage(5)] |
| `manekin_attack.json` | single_enemy_adjacent + damage(4) | target=entity, area=chain(1), effects=[damage(4)] + adjacency |
| `knockback_punch.json` | single_enemy_adjacent + damage(4) + knockback(2) | target=entity, area=chain(1), effects=[damage(4), move(push, 2)] |

Adjacency-семантика старого `single_enemy_adjacent` решается одним из двух способов (выбираем в /implement):
- (a) Поле `range: int = -1` на `EntityTarget` (–1 = неограниченно, 0 = self, 1 = соседи). Семантика «можно кастовать на эту цель» = `ctx.target_distance ≤ range`.
- (b) Перенос adjacency-логики в caller (godmode_controller выбирает кандидата по правилу), `EntityTarget` нейтрален.

Предпочтительнее (a) — данные остаются в JSON, не растекаются по контроллерам. Решение фиксируем в первом таске миграции.

## Migration of `knockback_modifier.gd`

```
OLD: modifier "knockback" с distance — вызывался в after_apply, толкал target.
NEW: effect "move" с move_type="push", move_distance=N — стоит в effects[] после damage.
```

Реализация push/pull в `MoveEffect.apply` дёргает `hex_grid.move_actor` или новый хелпер `hex_grid.shove_actor(id, direction, distance)`. Конкретика — /implement.

## Out of plan (намеренно)

- Конкретные значения cooldown, damage, duration в JSON — балансные, делает Стасян отдельно.
- Cooldown UI (индикаторы на slot bar) — отдельная UX-фича.
- Status-система (что значит «burning», «stunned») — `StatusEffect.apply` в этой фиче лишь регистрирует статус через будущий `Actor.add_status(id, duration)`. Если метода нет — заглушка с логом, никто не падает.
- Object-сущности (ящики, колонны) — `ObjectTarget` создаётся как stub, реальная игровая модель объекта вне scope.
- Триггерные модификаторы (`freeze_on_hit`, `extra_cast`) — out of scope per spec.

## Acceptance gate для plan→tasks

План считается принятым, если:
- [ ] API-контракты Skill / Ability / AbilityArea / AbilityEffect / ParameterModifier выше — приняты Egor'ом.
- [ ] Координация с Sergey (его лейн «spell-craft / modifier engine») — на чате, не блокирует start.
- [ ] Никто из других owners (Andrey по infra, Alexey по dialogue/ui) не блокирует EventBus-расширение.
