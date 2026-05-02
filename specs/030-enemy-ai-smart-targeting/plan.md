# 030-enemy-ai-smart-targeting — plan

**Owner:** Alexey
**Spec:** spec.md
**Status:** Ready for /tasks → /implement
**Upstream:** 008-enemy-ai, 011-skill-tags, 027-status-effects (all merged)

## Архитектурный обзор

Чисто additive PR. Никаких изменений в EnemyAIPlanner (кроме одной строки), BehaviorDatabase (кроме
новых case-веток в switch), контроллере. Вся логика изолирована в новых файлах в уже существующих папках.

```
новые файлы                              изменяемые файлы
─────────────────────────────────        ──────────────────────────────────
scripts/core/ai/conditions/              scripts/core/ai/enemy_ai_planner.gd
  condition_unclaimed_hex_exists_           +1 строка в _build_target_candidates
    _near_enemy.gd          (AC-C10)
  condition_ally_count_below.gd         scripts/core/ai/behavior_database.gd
                            (AC-C11)       +2 case в _build_condition
                                           +3 case в _build_selector
scripts/core/ai/selectors/               +1 case в _build_policy
  selector_highest_hp_ally.gd (AC-T9)
  selector_unclaimed_hex_near_enemy.gd  data/ai_behaviors/
                            (AC-T8)        melee_fighter.json (AC-J1)
  selector_target_without_status.gd       ranged_mage.json   (AC-J2)
                            (AC-T10)       healer.json        (AC-J3)
                                           buffer.json        (AC-J4)
scripts/core/ai/policies/
  policy_approach_nearest_enemy_unclaimed.gd (AC-MP5)
```

## Детали реализации

### condition_unclaimed_hex_exists_near_enemy.gd

```
class_name ConditionUnclaimedHexExistsNearEnemy
extends TacticCondition

@export var distance: int = 1

evaluate(actor, ctx):
  grid = ctx.grid
  my_coord = grid.get_coord(actor.actor_id)
  # Найти ближайшего живого противника
  target_coord = Vector2i(-1,-1), best_d = INF
  for other in ctx.all_actors (alive, opposite team):
    d = grid.hex_distance(my_coord, other_coord)
    if d < best_d: best_d=d, target_coord=other_coord
  if target_coord == (-1,-1): return false

  # Собрать заявленные гексы союзников (уже спланировавших)
  claimed: Array[Vector2i] = []
  for other in ctx.all_actors (alive, same team):
    if other.cast_intent != null and other.cast_intent.is_valid():
      claimed.append(other.cast_intent.target_coord)

  # Проверить соседей цели + саму цель
  hexes = grid.get_walkable_neighbours(target_coord) + [target_coord]
  for hex in hexes:
    if hex not in claimed: return true
  return false
```

Не hardcode enemy/ally team — используем инверсию `actor.team`.

### condition_ally_count_below.gd

```
class_name ConditionAllyCountBelow
extends TacticCondition

@export var count: int = 2

evaluate(actor, ctx):
  живых союзников (same team, != actor, is_alive()) < count
```

### selector_highest_hp_ally.gd

Зеркало SelectorLowestHpAlly. Кандидаты приходят уже отфильтрованными (союзники, is_alive, != self)
через `_build_target_candidates` после патча AC-PL1. Сортировка по `hp / max_hp` DESC.

```
class_name SelectorHighestHpAlly
extends TargetSelector

resolve(actor, candidates, ctx):
  best = null, best_ratio = -1.0
  for cand in candidates (Actor, != actor, max_hp > 0):
    ratio = float(cand.hp) / float(cand.max_hp)
    if ratio > best_ratio: best_ratio=ratio, best=cand
  return best   # null если никого
```

### selector_unclaimed_hex_near_enemy.gd

```
class_name SelectorUnclaimedHexNearEnemy
extends TargetSelector

resolve(actor, candidates, ctx):
  # 1. Target.kind validation — первым делом
  skill: Skill = ctx.get("candidate_skill")
  if skill == null or skill.abilities.is_empty(): return null
  ab: Ability = skill.abilities[0]
  if ab == null or ab.target == null: return null
  if not (ab.target is HexTarget): return null   # actor-only skill, skip

  # 2. Ближайший противник из кандидатов (логика nearest_enemy)
  grid = ctx.grid
  my_coord = grid.get_coord(actor.actor_id)
  target_coord = Vector2i(-1,-1), best_d = INF
  for cand in candidates (Actor, alive):
    d = grid.hex_distance(my_coord, grid.get_coord(cand.actor_id))
    if d < best_d: target_coord = coord, best_d = d
  if target_coord == (-1,-1): return null

  # 3. Claimed coords от уже спланировавших союзников
  claimed: Array[Vector2i] = []
  for other in ctx.all_actors (alive, same team):
    if other.cast_intent != null and other.cast_intent.is_valid():
      claimed.append(other.cast_intent.target_coord)

  # 4. Перебрать соседние гексы + target_coord
  hexes = grid.get_walkable_neighbours(target_coord) + [target_coord]

  # 5. Tiebreak: если у скилла есть area, считаем кол-во врагов в зоне
  enemy_coords = [grid.get_coord(c.actor_id) for c in candidates if c is Actor and c.is_alive()]
  best_hex = Vector2i(-1,-1), best_hits = -1
  for hex in hexes:
    if hex in claimed: continue
    hits = _count_hits(hex, ab, my_coord, enemy_coords, grid)
    if hits > best_hits: best_hits=hits, best_hex=hex

  return best_hex if best_hex != (-1,-1) else null

# Вспомогательный: считает сколько enemy_coords попадёт в area если primary=hex
_count_hits(hex, ab, caster_coord, enemy_coords, grid):
  if ab.area != null:
    affected = ab.area.get_affected_hexes(caster_coord, hex, grid)
    return affected.filter(lambda h: h in enemy_coords).size()
  return 1   # нет area — считаем 1 (сам hex)
```

Важно: `candidates` в этом selector содержат врагов (opposite team) — `_build_target_candidates`
для non-ally/non-self selectors возвращает opposing team. Claimed берём у союзников (actor.team).

### selector_target_without_status.gd

```
class_name SelectorTargetWithoutStatus
extends TargetSelector

@export var status_id: StringName = &""

resolve(actor, candidates, ctx):
  if status_id == &"": return null   # misconfigured — bail
  for cand in candidates (Actor, alive):
    if not cand.has_status(status_id): return cand   # первый без статуса
  return null   # все под дебафом
```

`actor.has_status(id)` подтверждён в actor.gd:201.
Порядок кандидатов — `nearest_enemy` логика (из `_build_target_candidates` which sorts by order in registry).
Для «выбрать ближайшего без дебафа» достаточно nearest first — candidates уже приходят без явной сортировки
по дистанции, но это нас устраивает (первый незадебаференный = хорошо).

### policy_approach_nearest_enemy_unclaimed.gd

```
class_name PolicyApproachNearestEnemyUnclaimed
extends MovementPolicy

pick_step(actor, ctx):
  # Копируем логику PolicyApproachNearestEnemy полностью
  grid, my_coord, target_coord, blocked — аналогично approach_nearest_enemy.gd

  path = grid.find_path_around(my_coord, target_coord, blocked)
  if path.size() < 2: return Vector2i(-1,-1)

  # Собрать занятые шаги у союзников
  taken: Array[Vector2i] = []
  for other in ctx.all_actors (alive, same team, != actor):
    if other.move_intent_coord != Vector2i(-1,-1):
      taken.append(other.move_intent_coord)

  # Попробовать path[1], затем path[2]
  for i in [1, 2]:
    if i >= path.size(): break
    if path[i] not in taken: return path[i]

  return path[1]   # fallback — не блокировать движение
```

`blocked` для pathfinding = координаты живых союзников (как в оригинальном approach policy).
Это не пересекается с `taken` — `taken` только интенты.

### EnemyAIPlanner — патч AC-PL1

Файл: `scripts/core/ai/enemy_ai_planner.gd`, строка с `want_allies`.

Было:
```gdscript
var want_allies: bool = selector is SelectorLowestHpAlly
```
Стало:
```gdscript
var want_allies: bool = selector is SelectorLowestHpAlly or selector is SelectorHighestHpAlly
```

Одна строка, никакой функциональности не меняет для существующих selectors.

### BehaviorDatabase — парсер-расширения

Файл: `scripts/core/ai/behavior_database.gd`

`_build_condition` match — добавить до `_:` дефолта:
```gdscript
"unclaimed_hex_exists_near_enemy":
    var c := ConditionUnclaimedHexExistsNearEnemy.new()
    c.distance = int(data.get("distance", 1))
    return c
"ally_count_below":
    var c := ConditionAllyCountBelow.new()
    c.count = int(data.get("count", 2))
    return c
```

`_build_selector` match:
```gdscript
"unclaimed_hex_near_enemy": return SelectorUnclaimedHexNearEnemy.new()
"highest_hp_ally":          return SelectorHighestHpAlly.new()
"target_without_status":
    var s := SelectorTargetWithoutStatus.new()
    s.status_id = StringName(data.get("status_id", ""))
    return s
```

`_build_policy` match:
```gdscript
"approach_nearest_enemy_unclaimed": return PolicyApproachNearestEnemyUnclaimed.new()
```

### JSON-файлы архетипов

**melee_fighter.json**
```json
{
  "id": "melee_fighter",
  "rules": [
    {
      "condition": {"kind": "enemy_in_range", "distance": 1},
      "target_selector": {"kind": "nearest_enemy"},
      "tag_priority": ["damage", "knockback"],
      "min_skill_count": 1
    }
  ],
  "movement_policy": {"kind": "approach_nearest_enemy_unclaimed"},
  "fallback_skill_id": ""
}
```

Rule 2 (только движение) не нужна отдельным правилом — если Rule 1 не сработала,
EnemyAIPlanner сам падает в movement_policy (behaviour 008 AC-X3.2).

**ranged_mage.json**
```json
{
  "id": "ranged_mage",
  "rules": [
    {
      "condition": {"kind": "no_enemy_in_range", "distance": 2},
      "target_selector": {"kind": "nearest_enemy"},
      "tag_priority": ["damage", "damage_aoe"],
      "min_skill_count": 1
    },
    {
      "condition": {
        "kind": "all_of",
        "children": [
          {"kind": "enemy_in_range", "distance": 2},
          {"kind": "unclaimed_hex_exists_near_enemy", "distance": 1}
        ]
      },
      "target_selector": {"kind": "unclaimed_hex_near_enemy"},
      "tag_priority": ["damage_aoe", "damage"],
      "min_skill_count": 1
    },
    {
      "condition": {"kind": "enemy_in_range", "distance": 2},
      "target_selector": {"kind": "nearest_enemy"},
      "tag_priority": ["damage", "damage_aoe"],
      "min_skill_count": 1
    }
  ],
  "movement_policy": {"kind": "kite_from_nearest_enemy"},
  "fallback_skill_id": ""
}
```

**healer.json**
```json
{
  "id": "healer",
  "rules": [
    {
      "condition": {"kind": "self_hp_below", "pct": 40},
      "target_selector": {"kind": "self"},
      "tag_priority": ["heal"],
      "min_skill_count": 1
    },
    {
      "condition": {"kind": "ally_hp_below", "pct": 60, "distance": 3},
      "target_selector": {"kind": "lowest_hp_ally"},
      "tag_priority": ["heal"],
      "min_skill_count": 1
    },
    {
      "condition": {"kind": "always"},
      "target_selector": {"kind": "nearest_enemy"},
      "tag_priority": ["damage"],
      "min_skill_count": 1
    }
  ],
  "movement_policy": {"kind": "follow_lowest_hp_ally"},
  "fallback_skill_id": ""
}
```

**buffer.json**
```json
{
  "id": "buffer",
  "rules": [
    {
      "condition": {"kind": "self_hp_below", "pct": 40},
      "target_selector": {"kind": "self"},
      "tag_priority": ["heal"],
      "min_skill_count": 1
    },
    {
      "condition": {"kind": "ally_hp_below", "pct": 50, "distance": 2},
      "target_selector": {"kind": "lowest_hp_ally"},
      "tag_priority": ["heal"],
      "min_skill_count": 1
    },
    {
      "condition": {"kind": "always"},
      "target_selector": {"kind": "highest_hp_ally"},
      "tag_priority": ["buff"],
      "min_skill_count": 1
    },
    {
      "condition": {"kind": "always"},
      "target_selector": {"kind": "nearest_enemy"},
      "tag_priority": ["damage"],
      "min_skill_count": 1
    }
  ],
  "movement_policy": {"kind": "approach_nearest_enemy"},
  "fallback_skill_id": ""
}
```

## Godot 4.6 ловушки

- `Array[Vector2i]` + `has()` / `in` — использовать `Dictionary` вместо Array если будут краши
  (CLAUDE.md trap §typed-arrays). В selector'е и condition — `claimed` и `taken` объявлять как plain `Array`,
  не `Array[Vector2i]`, чтобы не словить типовой краш при сравнении через `in`.
- `grid.get_walkable_neighbours(coord)` — возвращает `Array[Vector2i]`, это OK для итерации.
- Не использовать `create_timer` — нет тайминг-кода в planner'ах (CLAUDE.md §Timing).
- GDScript-файлы писать через create_file tool или str_replace, не через bash heredoc
  (CLAUDE.md trap §heredoc).

## Зависимости

| Что | Статус |
|---|---|
| `actor.has_status(id)` | Готово — actor.gd:201 |
| `HexTarget` class | Готово — scripts/core/abilities/targets/hex_target.gd |
| `grid.get_walkable_neighbours(coord)` | Готово — 008/005 |
| `grid.hex_distance(a, b)` | Готово — 008/005 |
| `Ability.area.get_affected_hexes(caster, primary, grid)` | Готово — 007 |
| `Actor.cast_intent: CastIntent` | Готово — 008 |
| `Actor.move_intent_coord: Vector2i` | Готово — 008 |
| `SelectorHighestHpAlly` class_name для isinstance | Создаётся в этом PR |

## Порядок реализации

```
Группа A (conditions, parallel) ──┐
Группа B (selectors, parallel) ───┤─→ Группа D (BehaviorDatabase parser) → Группа E (JSON)
Группа C (policy)              ───┘
                                   └─→ Группа F (planner patch, независима)
```

Всё кроме Группы F не трогает существующий код — порядок внутри A/B/C не важен.
Группа F (enemy_ai_planner.gd) — одна строка, можно делать в любой момент.
Группа D нужна после A/B/C чтобы class_name'ы были доступны парсеру.
