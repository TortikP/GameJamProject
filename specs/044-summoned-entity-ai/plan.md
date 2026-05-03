# 044-summoned-entity-ai — plan

Реализация по AC из spec.md. Порядок — независимые блоки сначала (selector + JSON), driver/telegraph последними (требуют smoke-теста).

## File map

| Path | Operation | Reason |
|---|---|---|
| `scripts/core/ai/selectors/selector_nearest_empty_hex_to_enemy.gd` | CREATE | AC-S1..S7 |
| `scripts/core/ai/behavior_database.gd` | EDIT | +1 строка в `_build_selector` match |
| `data/ai_behaviors/default_melee.json` | EDIT | AC-J1: новое первое правило |
| `data/ai_behaviors/default_range.json` | DELETE | AC-J2/J4 |
| `data/ai_behaviors/default_ranged.json` | CREATE | AC-J2: контент = old default_range + summon rule first |
| `scripts/presentation/godmode/ai_driver.gd` | EDIT | AC-D1/D2: 2 фильтра |
| `scripts/presentation/godmode/telegraph_renderer.gd` | EDIT | AC-T1: 1 фильтр |
| `specs/044-summoned-entity-ai/HANDOFF.md` | CREATE | след за смок-тестом |

## Implementation details

### 1. `SelectorNearestEmptyHexToEnemy` (новый файл)

```gdscript
class_name SelectorNearestEmptyHexToEnemy
extends TargetSelector
## Возвращает Vector2i hex для саммон-скиллов: empty (нет actor / tile-object),
## walkable, в пределах range кастера, ближайший по BFS-кольцам к ближайшему
## opposing-team актёру. Не выбирает hex'ы, заклеймленные cast_intent союзников.
##
## Симметрично с `unclaimed_hex_near_enemy` (030 AC-T8) по входному контракту,
## но семантика другая: тот ищет hex для AOE-урона (max enemy-hits в area), этот —
## для спавна (empty + close to enemy).

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const MAX_RING: int = 32   # AC-S5 safety cap


func resolve(actor: Actor, candidates: Array, ctx: Dictionary) -> Variant:
    var grid: HexGrid = ctx.get("grid")
    if grid == null:
        return null

    # AC-S2: HexTarget validation.
    var skill: Skill = ctx.get("candidate_skill")
    if skill == null or skill.abilities.is_empty():
        return null
    var ab: Ability = skill.abilities[0]
    if ab == null or ab.target == null or not (ab.target is HexTarget):
        return null
    var max_range: int = int(ab.target.range)   # -1 → unbounded

    # AC-S3: nearest opposing-team actor.
    var my_coord: Vector2i = grid.get_coord(actor.actor_id)
    if my_coord == Vector2i(-1, -1):
        return null
    var enemy_coord: Vector2i = Vector2i(-1, -1)
    var best_d: int = 0x7fffffff
    for cand_v in candidates:
        if not (cand_v is Actor):
            continue
        var cand: Actor = cand_v
        if not cand.is_alive():
            continue
        var c: Vector2i = grid.get_coord(cand.actor_id)
        if c == Vector2i(-1, -1):
            continue
        var d: int = grid.hex_distance(my_coord, c)
        if d >= 0 and d < best_d:
            best_d = d
            enemy_coord = c
    if enemy_coord == Vector2i(-1, -1):
        return null

    # Claimed by allies' cast_intent (030 intent-awareness, AC-S4).
    var claimed: Dictionary = {}   # Vector2i -> bool
    var all_actors: Array = ctx.get("all_actors", [])
    for other_v in all_actors:
        if not (other_v is Actor):
            continue
        var other: Actor = other_v
        if other == actor or not other.is_alive() or other.team != actor.team:
            continue
        if other.cast_intent != null and other.cast_intent.is_valid():
            claimed[other.cast_intent.target_coord] = true

    # AC-S5/S6: BFS rings outward from enemy_coord. Ring 0 = enemy hex itself
    # (will fail get_actor_at check, but kept for symmetry). Ring N = hexes at
    # hex_distance == N. We rely on grid having neighbour traversal; we don't
    # need a full BFS — just iterate distance using hex_distance().
    #
    # Implementation: collect all candidate hexes via grid neighbour expansion,
    # ordered by ring. Use a visited-set to avoid duplicates.
    var visited: Dictionary = {}   # Vector2i -> bool
    var frontier: Array = [enemy_coord]
    visited[enemy_coord] = true
    var ring: int = 0
    while ring <= MAX_RING and not frontier.is_empty():
        # Test current ring (frontier).
        var best_hex: Vector2i = Vector2i(-1, -1)
        var best_caster_d: int = 0x7fffffff
        for hex_v in frontier:
            var hex: Vector2i = hex_v
            if _is_summon_target_ok(hex, grid, max_range, my_coord, claimed):
                var cd: int = grid.hex_distance(my_coord, hex)
                if cd >= 0 and cd < best_caster_d:
                    best_caster_d = cd
                    best_hex = hex
        if best_hex != Vector2i(-1, -1):
            return best_hex

        # Build next ring.
        var next_frontier: Array = []
        for hex_v in frontier:
            var hex: Vector2i = hex_v
            for nb in grid.get_walkable_neighbours(hex):
                if visited.has(nb):
                    continue
                visited[nb] = true
                next_frontier.append(nb)
        frontier = next_frontier
        ring += 1
    return null


func _is_summon_target_ok(hex: Vector2i, grid: HexGrid, max_range: int,
        caster_coord: Vector2i, claimed: Dictionary) -> bool:
    if not grid.is_walkable(hex):
        return false
    if grid.get_actor_at(hex) != &"":
        return false
    if grid.get_tile_object_id(hex) != &"":
        return false
    if max_range >= 0:
        var d: int = grid.hex_distance(caster_coord, hex)
        if d < 0 or d > max_range:
            return false
    if claimed.has(hex):
        return false
    return true
```

**Notes:**
- BFS uses `grid.get_walkable_neighbours` for ring expansion → unwalkable cells are pruned at the **frontier-build** step, but the hex itself is also re-checked in `_is_summon_target_ok` (defensive — `get_walkable_neighbours` may return walkable cells, the test handles edge cases like newly-changed terrain).
- Tiebreak (AC-S6): within a ring, picks min `hex_distance(my_coord, hex)`. If still tied, first by iteration order — deterministic given `frontier` is array (insertion order from previous expansion, which itself comes from `grid.get_walkable_neighbours` ordering).
- Если HexGrid не имеет `is_walkable` или `get_tile_object_id` под этими именами — заменить на actual API. Проверить во время implement.

### 2. `behavior_database.gd` — регистрация

Add one line in `_build_selector` match block (line ~226 after `unclaimed_hex_near_enemy`):

```gdscript
"nearest_empty_hex_to_enemy": return SelectorNearestEmptyHexToEnemy.new()
```

### 3. JSON

`data/ai_behaviors/default_melee.json` — prepend rule:

```json
{
  "id": "default_melee",
  "rules": [
    {
      "condition": { "kind": "always" },
      "target_selector": { "kind": "nearest_empty_hex_to_enemy" },
      "tag_priority": ["summon"],
      "min_skill_count": 1
    },
    {
      "condition": {
        "kind": "all_of",
        "children": [
          { "kind": "enemy_in_range", "distance": 1 },
          { "kind": "aoe_net_positive", "check_radius": 1 }
        ]
      },
      "target_selector": { "kind": "nearest_enemy" },
      "tag_priority": ["damage", "melee"],
      "min_skill_count": 1
    }
  ],
  "movement_policy": { "kind": "spread_from_allies", "crowd_radius": 1 },
  "fallback_skill_id": ""
}
```

`data/ai_behaviors/default_ranged.json` — new file, replaces `default_range.json`:

```json
{
  "id": "default_ranged",
  "rules": [
    {
      "condition": { "kind": "always" },
      "target_selector": { "kind": "nearest_empty_hex_to_enemy" },
      "tag_priority": ["summon"],
      "min_skill_count": 1
    },
    {
      "condition": {
        "kind": "all_of",
        "children": [
          { "kind": "enemy_in_range", "distance": 4 },
          { "kind": "aoe_net_positive", "check_radius": 1 }
        ]
      },
      "target_selector": { "kind": "nearest_enemy" },
      "tag_priority": ["damage", "ranged", "debuff"],
      "min_skill_count": 1
    }
  ],
  "movement_policy": { "kind": "maintain_range", "desired_min": 2, "desired_max": 3 },
  "fallback_skill_id": ""
}
```

`data/ai_behaviors/default_range.json` — delete (`git rm`).

### 4. `ai_driver.gd` — driver-фильтр

Two diff sites. Both replace `team == &"enemy"` with `actor != _ctrl.player`.

`replan_all_and_refresh()` (line ~50):
```gdscript
# Before:
for actor in registry.all():
    if actor is Actor and (actor as Actor).team == &"enemy":
        enemies.append(actor)
# After:
for actor in registry.all():
    if actor is Actor and (actor as Actor) != _ctrl.player:
        ai_actors.append(actor)
```

`_run_enemy_turn()` (line ~122) — same replacement. Local var `enemies` → `ai_actors` для читаемости (внутри loop'а — без переименования). Имя метода `_run_enemy_turn` сохраняем (AC-D3).

### 5. `telegraph_renderer.gd` — telegraph-фильтр

`refresh()` (line ~81):
```gdscript
# Before:
if enemy.team != &"enemy" or not enemy.is_alive():
    continue
# After:
if actor == _ctrl.player or not actor.is_alive():
    continue
```

Local var `enemy` лучше переименовать в `npc` или `world_actor`. Минимизируем переименование — оставим `enemy` как есть, но переменная теперь означает «AI-controlled actor». Один комментарий-капстон над блоком.

## Pathfinder rebuild

Не нужен. Player-summoned actor проходит через `LevelLoader.spawn_enemy_at` (см. 041 plan), который уже обновляет grid actor index. Pathfinder перебирает живых актёров на каждом call-сайте через `find_path_around(blocked)`.

## Boot-time validation

Не нужен. Селектор регистрируется по строке-ключу; ошибка регистрации даст warn в `BehaviorDatabase` ("unknown target_selector kind"), сценарий продолжит работать без саммон-rule (правило fizzles). Без silent failure.

## Performance

BFS селектора: см. risks в spec'е. Для типичной арены 1-2 кольца → 6-18 hex'ов проверяется. Cap MAX_RING=32 — теоретический потолок ~3K hex'ов; не достижим на джемовых картах.

## Backward compatibility

- `default_range.json` удалён, на staging нет ссылок (см. AC-J3). На других неактивных feature-ветках может остаться → conflict при мёрдже их в staging после 044 → разработчик ветки переключает на `default_ranged`.
- Старое поведение `default_melee` сохраняется как второе правило → саммонеры с ready cooldown'ом саммонят, без ready cooldown'а — fizzles → бьют как раньше.
- Player без саммон-скиллов: driver-loop получает дополнительный no-op iteration по 0 player-team AI-actors → нулевой overhead.

## Migration / risks (повтор из spec'а)

- Cross-branch reference на `default_range`: grep чист на staging, на других ветках возможен → решается на их merge.
- Telegraph spam при большом числе саммонов: monitor на playtest'е.
- Симметрия player-vs-enemy цветов: out of scope; flag для UX-ревью.
