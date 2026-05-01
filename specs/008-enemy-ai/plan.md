# 008-enemy-ai — plan

**Owner:** Sergey (claim) → continued by Egor (Sergey out of tokens). Решения Сергея в spec.md (Q-AI-1..6) не пересматриваются — план реализует ровно их.
**Spec:** [`spec.md`](./spec.md)
**Status:** Ready for /tasks → /implement
**Prerequisite:** [`011-skill-tags`](../011-skill-tags/spec.md) merged to staging — `Skill.tags` доступен. Без 011 правила фильтрации скиллов по тегу не работают.

## Архитектурный обзор

Заменяем монолит `_plan_intents` (40 строк в `godmode_controller.gd`) на data-driven AI-модуль в `scripts/core/ai/`. Контроллер godmode остаётся **executor**'ом intent'ов — рендер animation, resolve cast, animate move. Контракт между AI и controller — `cast_intent: CastIntent` Resource на Actor.

```
EventBus.world_turn_ended
        │
        ▼
GodmodeController._run_enemy_turn(enemy)
   │
   ├── 1. EnemyAIPlanner.plan(enemy, world_ctx)          ◄── НОВОЕ (был _plan_intents)
   │       │
   │       ├── BehaviorDatabase.get(enemy.behavior_id)   ◄── BehaviorScenario Resource
   │       │
   │       ├── for rule in scenario.rules:
   │       │     condition.evaluate(actor, ctx)?
   │       │     selector → candidates ∩ tag_priority    ◄── фильтр по Skill.tags (011)
   │       │     первый годный → cast_intent
   │       │
   │       └── fallback → movement_policy → move_intent_coord  (или hold)
   │
   ├── 2. await _resolve_move_intent(enemy)              ◄── без изменений
   │
   └── 3. await _resolve_cast_intent(enemy)              ◄── рефакторинг: читает cast_intent, кастует ЛЮБОЙ Skill
```

### Ключевые семантические выборы

- **AI = чистый planner.** `EnemyAIPlanner.plan(actor, ctx)` записывает на актёра `move_intent_coord` и/или `cast_intent` и больше ничего. Никаких side-effect'ов — нет анимаций, нет cast'а, нет change'а HP. Resolve в следующем step'е controller'а.
- **Pillar §1.5.2 жёстко:** AI зовёт `Skill.cast(caster, ctx)` через тот же controller-resolver, что и игрок. Никаких enemy-only путей урона.
- **Pillar §1.5.1 жёстко:** план фиксируется в `cast_intent` ДО рендера телеграфа. Telegraph читает `cast_intent` и `move_intent_coord` — игрок видит intent ровно как сейчас, плюс цвет hex по primary-тегу скилла.
- **Composition rules — flat:** один уровень обёрток (`all_of` / `any_of` / `not_of`), внутри только примитивы. Парсер JSON отвергает вложенные обёртки → `condition = always` + warn (Q-AI-5, AC-C9).
- **Ownership:** AI-модуль (`scripts/core/ai/`) — новая зона, claim Sergey'я через первый PR (был #28). Egor переносит дальше; merge-time Сергей подтверждает или просит rework. Не лезем в `core/abilities/`, `core/skills/` — это чужой модуль (Egor, 007). `Actor` (extension `behavior_id` + `cast_intent`) — additive, согласовано через 008/AC-I2 в spec'е.

## File layout

### Новые файлы

```
scripts/core/ai/
├── cast_intent.gd                       # class_name CastIntent extends Resource
├── enemy_ai_planner.gd                  # autoload, API: plan(actor, ctx)
├── behavior_database.gd                 # autoload, scans data/ai_behaviors/*.json
├── behavior_scenario.gd                 # class_name BehaviorScenario extends Resource
├── tactic_rule.gd                       # class_name TacticRule extends Resource
├── conditions/
│   ├── tactic_condition.gd              # abstract base; evaluate(actor, ctx) -> bool
│   ├── condition_always.gd              # AC-C1
│   ├── condition_self_hp_below.gd       # AC-C2
│   ├── condition_self_hp_above.gd       # AC-C3
│   ├── condition_enemy_in_range.gd      # AC-C4
│   ├── condition_no_enemy_in_range.gd   # AC-C5
│   ├── condition_enemy_count_in_range.gd # AC-C6
│   ├── condition_ally_hp_below.gd       # AC-C7
│   ├── condition_skill_ready.gd         # AC-C8
│   ├── condition_all_of.gd              # AC-C9 composer (1 уровень)
│   ├── condition_any_of.gd              # AC-C9 composer (1 уровень)
│   └── condition_not_of.gd              # AC-C9 composer (1 уровень, terminal — primitive only)
├── selectors/
│   ├── target_selector.gd               # abstract base; resolve(actor, candidates, ctx) -> Variant
│   ├── selector_nearest_enemy.gd        # AC-T1
│   ├── selector_lowest_hp_enemy.gd      # AC-T2
│   ├── selector_highest_hp_enemy.gd     # AC-T3
│   ├── selector_self.gd                 # AC-T4
│   ├── selector_lowest_hp_ally.gd       # AC-T5
│   ├── selector_densest_enemy_hex.gd    # AC-T6 (returns target_coord, not target_id)
│   └── selector_random_enemy.gd         # AC-T7
└── policies/
    ├── movement_policy.gd               # abstract base; pick_step(actor, ctx) -> Vector2i (-1,-1 = hold)
    ├── policy_approach_nearest_enemy.gd # AC-S2
    ├── policy_kite_from_nearest_enemy.gd # AC-S2
    ├── policy_hold_position.gd          # AC-S2
    └── policy_follow_lowest_hp_ally.gd  # AC-S2

data/ai_behaviors/
└── default_melee.json                   # AC-S1 backward-compat (бит-в-бит current manekin)

data/enemies/
└── manekin.json                         # AC-S4 backward-compat (legacy manekin переведён на enemy-data)
```

### Изменяемые файлы

| Путь | Что меняется |
|---|---|
| `scripts/core/actors/actor.gd` | + `@export var behavior_id: StringName = &""`, `@export var cast_intent: CastIntent` (default null). AC-S1, AC-I2. |
| `scripts/presentation/godmode/manekin_view.gd` | удалить `attack_skill_id`/`attack_intent_coord` поля (AC-I2). manekin грузит skills + behavior_id из `data/enemies/manekin.json` через новый helper (см. ниже). |
| `scenes/dev/manekin.tscn` | удалить inline-set `attack_skill_id`. enemy_data_id (StringName) указывает на `data/enemies/manekin.json`. |
| `scripts/presentation/godmode/godmode_controller.gd` | `_plan_intents` → удаляется, заменяется вызовом `EnemyAIPlanner.plan(enemy, world_ctx)`. `_resolve_attack_intent` → `_resolve_cast_intent` (читает `cast_intent`, кастует любой Skill). Telegraph rendering читает `cast_intent` вместо `attack_intent_coord`. |
| `scripts/presentation/godmode/godmode_controller.gd` | новая helper-функция `_telegraph_color_for_skill(skill: Skill) -> Color` — single mapping (AC-I4). Делегирует к `UiTheme` для цветовых констант (см. CLAUDE.md hard rule §5: "UI цвета только через UiTheme"). |
| `scripts/presentation/ui_theme.gd` | новые константы: `COLOR_TELEGRAPH_DAMAGE` / `_HEAL` / `_CONTROL` / `_BUFF` / `_SUMMON` / `_MOBILITY` / `_UNKNOWN`. Координация с Андреем (009). |
| `project.godot` | `[autoload]` + `BehaviorDatabase=...`, `EnemyAIPlanner=...`. Порядок: BehaviorDatabase **до** EnemyAIPlanner (planner получает ссылку на DB при `_ready`). После SkillDatabase. |

## Resources / классы

### `CastIntent` (`scripts/core/ai/cast_intent.gd`)

```gdscript
class_name CastIntent
extends Resource

@export var skill_id: StringName = &""
@export var target_id: StringName = &""           # entity-target; пустой = читай target_coord
@export var target_coord: Vector2i = Vector2i(-1, -1)  # hex-target

func is_valid() -> bool:
    return skill_id != &""
```

`null` = "нет cast'а в этот ход". Controller проверяет `enemy.cast_intent != null and enemy.cast_intent.is_valid()`.

### `TacticCondition` (abstract)

```gdscript
class_name TacticCondition
extends Resource

# Subclasses override. ctx содержит {registry, grid, all_actors, turn}.
func evaluate(actor: Actor, ctx: Dictionary) -> bool:
    return false
```

Каждый подкласс — `@export` параметры из spec'а (`pct`, `distance`, `min_count`, `skill_id`).
Композеры (`all_of` / `any_of` / `not_of`) хранят `@export var children: Array[TacticCondition]` и при парсинге проверяют что `children` — только примитивы (см. AC-C9).

### `TargetSelector` (abstract)

```gdscript
class_name TargetSelector
extends Resource

# candidates — отфильтрованные актёры по типу (enemy/ally/self) и в радиусе скиллов rule'а.
# Возвращает Variant: Actor | Vector2i | null.
func resolve(actor: Actor, candidates: Array, ctx: Dictionary) -> Variant:
    return null
```

`densest_enemy_hex` — единственный селектор, возвращающий `Vector2i` (target_coord), остальные возвращают `Actor`.

### `MovementPolicy` (abstract)

```gdscript
class_name MovementPolicy
extends Resource

# Возвращает целевой соседний hex. Vector2i(-1,-1) = "нет якоря, hold_position".
func pick_step(actor: Actor, ctx: Dictionary) -> Vector2i:
    return Vector2i(-1, -1)
```

`hold_position` всегда возвращает `(-1,-1)`. Остальные ищут anchor (nearest enemy / lowest-hp ally) и считают `find_path_around` через `hex_grid`.

### `TacticRule`

```gdscript
class_name TacticRule
extends Resource

@export var condition: TacticCondition
@export var target_selector: TargetSelector
@export var tag_priority: Array[StringName] = []
@export var min_skill_count: int = 1
```

### `BehaviorScenario`

```gdscript
class_name BehaviorScenario
extends Resource

@export var id: StringName = &""
@export var rules: Array[TacticRule] = []
@export var movement_policy: MovementPolicy
```

## JSON schemas

### `data/ai_behaviors/<id>.json` (BehaviorScenario)

```json
{
  "id": "default_melee",
  "rules": [
    {
      "condition": {"kind": "enemy_in_range", "distance": 1},
      "target_selector": {"kind": "nearest_enemy"},
      "tag_priority": ["damage"],
      "min_skill_count": 1
    }
  ],
  "movement_policy": {"kind": "approach_nearest_enemy"},
  "fallback_skill_id": "skill_manekin_attack"
}
```

`condition.kind` — switch на 9 вариантов из AC-C1..C8 + 3 композера. `all_of`/`any_of` имеют поле `children: Array<condition>`, `not_of` — `child: condition`.

### `data/enemies/<id>.json`

```json
{
  "id": "manekin",
  "max_hp": 30,
  "team": "enemy",
  "speed": 1,
  "skills": ["skill_manekin_attack"],
  "behavior_id": "default_melee",
  "fallback_skill_id": "skill_manekin_attack"
}
```

Дизайнер (Стасян) наполняет 4 архетипа: `melee_brute`, `ranged_caster`, `support`, `debuffer` — после того как движок собран. Я кладу только `manekin.json` для backward-compat.

### Парсер behavior_database

`BehaviorDatabase._build_scenario(data)` — switch на `condition.kind`, `target_selector.kind`, `movement_policy.kind`. Невалидный kind → `GameLogger.warn` + skip rule (целиком, не just condition). Невалидная вложенность композеров → `condition = always` + warn (AC-C9, scenario-test #11).

## Цикл планирования

`EnemyAIPlanner.plan(actor, ctx)`:

1. **Гейт actor-can-act** (AC-GACT-1..3): `not actor.is_alive()` или (`actor.skills.is_empty()` and `policy = hold_position`) → return.
2. Очистить `cast_intent = null`, `move_intent_coord = (-1,-1)` на актёре.
3. Получить scenario через `BehaviorDatabase.get(actor.behavior_id)`. Если `behavior_id == &""` или scenario нет → fallback на `default_melee`.
4. **Iterate rules** (AC-X3):
   - Для каждого rule сверху-вниз:
     - `condition.evaluate(actor, ctx)`. False → next.
     - True → собрать `candidates` по типу селектора (enemy/ally/self) И в радиусе любого rule'овского tag'а (берём max range среди скиллов с тегом). Тут же фильтр `is_alive()`.
     - Из `actor.skills` оставить те, у которых `skill.tags ∩ rule.tag_priority ≠ ∅`. Сортировать по позиции **наилучшего** matching tag в `tag_priority` ↑ (меньший индекс = выше). Tiebreak — порядок в `actor.skills` (Q-AI-3).
     - Отфильтровать `is_ready()` И есть валидная цель по селектору с учётом range.
     - Если осталось ≥ `min_skill_count` → берём первый, формируем `cast_intent = {skill_id, target_id, target_coord}`. **Стоп**.
   - Иначе → next rule.
5. **Movement fallback** (если ни одно правило не сработало):
   - `scenario.movement_policy.pick_step(actor, ctx)` → `move_intent_coord` или `(-1,-1)`.
   - Если `(-1,-1)` И `scenario.fallback_skill_id != &""` И actor имеет этот skill ready И есть валидная цель → cast fallback (бит-в-бит как сейчас manekin).
   - Иначе → hold + `GameLogger.info("AI", "%s: no action this turn (no anchor)" % actor.actor_id)` (Q-AI-6, AC-X3.3).

## Telegraph color mapping

В `godmode_controller._telegraph_color_for_skill(skill)`:

```gdscript
if skill.tags.is_empty():
    return UiTheme.COLOR_TELEGRAPH_UNKNOWN  # gray, no damage number
match skill.tags[0]:
    &"damage", &"damage_aoe", &"knockback":
        return UiTheme.COLOR_TELEGRAPH_DAMAGE  # текущий orange — без изменений
    &"heal":
        return UiTheme.COLOR_TELEGRAPH_HEAL    # green
    &"control", &"debuff":
        return UiTheme.COLOR_TELEGRAPH_CONTROL # purple
    &"buff":
        return UiTheme.COLOR_TELEGRAPH_BUFF    # blue
    &"summon":
        return UiTheme.COLOR_TELEGRAPH_SUMMON  # gold
    &"mobility":
        return UiTheme.COLOR_TELEGRAPH_MOBILITY # white
    _:
        return UiTheme.COLOR_TELEGRAPH_UNKNOWN
```

Damage number (`predicted_damage_to`) показывается только если `skill.tags[0] in [damage, damage_aoe, knockback]` — иначе число нерелевантно (heal/buff/...).

## Migration: `attack_skill_id` + `attack_intent_coord` → `cast_intent`

Чисто refactoring, никакой функциональности не меняет.

| Было | Стало |
|---|---|
| `manekin_view.attack_skill_id: StringName` (`@export`) | удаляется. skills и `behavior_id` приходят из `data/enemies/manekin.json` |
| `manekin_view.attack_intent_coord: Vector2i` | удаляется |
| `enemy.set("move_intent_coord", ...)` в `_plan_intents` | остаётся (AC-I1) |
| `enemy.set("attack_intent_coord", ...)` | заменяется на `enemy.cast_intent = CastIntent.new(); enemy.cast_intent.skill_id = ...; ...` |
| `_resolve_attack_intent(enemy)` | `_resolve_cast_intent(enemy)` — читает `enemy.cast_intent`, проверяет валидность, дёргает `skill.cast(enemy, ctx)` где `ctx = {registry, grid, target_id, target_coord}` |

`_plan_intents` (40 строк) — целиком удаляется. Вместо него один вызов `EnemyAIPlanner.plan(enemy, world_ctx)` в `_run_enemy_turn`.

## Backward-compat (AC-S1, scenario test #1)

`data/ai_behaviors/default_melee.json` пишется так, чтобы существующий manekin вёл себя бит-в-бит как сейчас:

- Одно правило: `enemy_in_range(1) → nearest_enemy → tags=[damage]`.
- `movement_policy: approach_nearest_enemy`.
- `fallback_skill_id: skill_manekin_attack`.

`data/enemies/manekin.json` указывает `behavior_id: default_melee`, `skills: [skill_manekin_attack]`. Манекен ставится через `manekin_view.tscn` + новый load-helper (тоже `_ready` фаза).

## Сценарии тестирования (smoke, ручной)

Все 13 scenario из spec.md секции "Acceptance scenarios" — ручной smoke в Godot. Автотестов нет (в джеме нет фреймворка). Каждый тест → строка в `specs/008-enemy-ai/SMOKE.md` (создаётся в Группе L) с фактическим результатом и timestamp.

## Зависимости

| Что | Откуда | Статус |
|---|---|---|
| `Skill.tags: Array[StringName]` (AC-S5 в spec'е) | 011-skill-tags (Egor's PR) | **Hard prereq** — без 011 фильтр по тегу не работает. Не запускать имплемент 008 пока 011 не в staging. AC-S5 в spec.md формально остаётся, но фактически реализован 011. |
| `Skill.cast(caster, ctx)`, `is_ready()` | 007-skill-system (merged) | Готово |
| `hex_grid.find_path_around`, `reachable_within`, `get_walkable_neighbours` | 005-camera-and-arena (merged) | Готово |
| `ActorRegistry.all()`, `get_actor()`, `get_at()` | 004-godmode-base (merged) | Готово |
| Цвета телеграфа (UiTheme) | 009-ui-kit (Phase 4 blocked on 007+008) | **Soft dep** — Андрей координирует. Если до его UI Kit'а — заводим временные `Color(...)` в `UiTheme` с TODO-меткой, после 009 он перевешает. |
| `data/enemies/<archetype>.json` для 4 архетипов (Стасян) | downstream | После имплемента движка пингаем Стасяна. Сейчас закладываем только `manekin.json` для backward-compat. |

## Координация

- **Сергей (vacancy):** PR-овнер 008 формально. Когда токены вернутся — даёт ack или просит rework. Не мерж до его review.
- **Egor:** continuing implementation. PR `egor/008-plan-tasks` со spec.md (verbatim из sergey's branch) + plan.md + tasks.md. Имплемент-PR'ы — отдельные ветки, по одной на группу T0XX.
- **Andrey:** color tokens в UiTheme — в этой же фиче, временные значения. Андрей обновит при выкатке 009.
- **Stasyan:** не лезет в код. Получает JSON-схему (см. выше) и наполняет `data/enemies/*.json` + `data/ai_behaviors/*.json` после того как движок зелёный (smoke #1, AC-T1). Пинг ему явный в T130.

## Заметки реализации

- **Autoload порядок** (CLAUDE.md trap §`_ready` order): BehaviorDatabase до EnemyAIPlanner. Planner делает lookup в `_ready`? Нет — planner stateless, lookup в `plan()`. Безопаснее. Но всё равно — в project.godot ставим в правильном порядке для определённости.
- **`Array[Resource]` ловушка** (CLAUDE.md trap): `BehaviorScenario.rules: Array[TacticRule]` — если при парсинге будет упираться, переключаемся на `Array` (plain) и явный cast в `EnemyAIPlanner.plan`. То же для `TacticCondition.children` композеров.
- **Godot 4.6 docs ссылки:**
  - [`Resource`](https://docs.godotengine.org/en/4.6/classes/class_resource.html) — base для всех AI-ресурсов.
  - [`@export`](https://docs.godotengine.org/en/4.6/tutorials/scripting/gdscript/gdscript_exports.html) — типизованные массивы `Array[T]`, `Resource`-подклассы.
  - [`Node._ready`](https://docs.godotengine.org/en/4.6/classes/class_node.html#class-node-method-ready) — autoload init order.
- **NOT использовать `class_name` для autoload-ов** (CLAUDE.md trap §Logger): `EnemyAIPlanner` autoload — без `class_name`, через `preload` или global name из autoload registry.
- **Никаких `create_timer`** в AI-коде (CLAUDE.md hard rule §5). AI чистый planner — нет анимаций, нет ожиданий.
- **Условия — read-only** на актёра: не мутируют state, только читают `actor.hp`, `grid.get_coord(...)`, etc.
