# 030-enemy-ai-smart-targeting — spec

**Owner:** Alexey
**Status:** Draft — остановка перед /plan. Требует review Egor'а (модуль `scripts/core/ai/` его зона).
**Upstream:** 008-enemy-ai (merged), 011-skill-tags (merged), 027-status-effects (merged)

## Цель

Добавить «умные» правила выбора цели для 4 архетипов врагов (melee_fighter, ranged_mage, healer, buffer/debuffer)
с учётом действий других врагов на том же ходу. Результат — враги не стакаются на одну клетку, рейнджер бьёт
туда куда не бьёт мили, лекарь лечит себя раньше чем умирает.

Реализация — **только новые selectors/conditions/policies + JSON-файлы архетипов в `data/ai_behaviors/`**.
Движок `EnemyAIPlanner`, `BehaviorDatabase`, контроллер — не трогаются.

## Ключевые концепции

### Intent-awareness (координация через уже-запланированные интенты)

Планирование врагов sequential (008 AC-X1). К моменту вызова `EnemyAIPlanner.plan(enemy_N, ctx)`,
враги 0..N-1 уже записали `cast_intent` и `move_intent_coord` на себя. `ctx.all_actors` — снимок всех
акторов, их интенты читаются напрямую. Никаких изменений в `_world_ctx()` или сигнатуре `plan()` не нужно.

Новые selectors читают `(actor as Actor).cast_intent` из `ctx.all_actors` чтобы определить какие
гексы уже «заняты» другими врагами.

### Три приоритета для damage-архетипов

```
Приоритет 1  (меле-расстояние): атакуй игрока напрямую — если стоишь вплотную.
Приоритет 2  (AOE/рассредоточение): атакуй незаконтестованный hex рядом с игроком —
             если у тебя есть damage_aoe-скилл и хоть один соседний hex не занят другими cast_intent.
Приоритет 3  (fallback): атакуй игрока напрямую — если всё вокруг него уже под ударом.
```

Реализуется через три TacticRule в нужном порядке в JSON-файле архетипа.
Никакой новой логики в EnemyAIPlanner — только правильные condition + selector + tag_priority.

## Acceptance criteria

### Новые TacticCondition

- **AC-C10**: `unclaimed_hex_exists_near_enemy(target_team, distance)` — true если среди гексов на
  hex-расстоянии ≤ `distance` от ближайшего актёра противоположной team (= игрока) есть хотя бы один,
  НЕ совпадающий ни с одним `cast_intent.target_coord` живого врага из `ctx.all_actors`. Используется
  как guard для приоритета 2.
  - Параметры: `target_team: StringName` (кого ищем центром; обычно `player`), `distance: int = 1`.
  - Гексы из `grid.get_walkable_neighbours(target_coord)` + сам `target_coord` (на случай прямого удара).
  - Если ближайший противник не найден → false.

- **AC-C11**: `ally_count_below(count: int)` — true если живых союзников (same team, excl. self) < `count`.
  Триггер для призывателя.

### Новые TargetSelector

- **AC-T8**: `selector_unclaimed_hex_near_enemy` — возвращает `Vector2i` (hex-target, как `densest_enemy_hex`).
  Алгоритм:
  1. Найти ближайшего живого противника из кандидатов (`nearest_enemy` логика).
  2. Собрать соседние гексы (`grid.get_walkable_neighbours(target_coord)`) + `target_coord`.
  3. Из уже спланировавших врагов (`ctx.all_actors` filter: team == actor.team AND `cast_intent != null AND is_valid()`) собрать `claimed_coords: Array[Vector2i]` = их `cast_intent.target_coord`.
  4. Вернуть первый из соседних, НЕ попавший в `claimed_coords`. Tiebreak — hex с наибольшим числом enemies в зоне выбранного damage_aoe скилла (если Skill.abilities[0].area доступна) или просто ближайший к кастующему.
  5. Если все заняты → `null` (правило не срабатывает → следующее).

- **AC-T9**: `selector_highest_hp_ally` — симметрия `lowest_hp_ally`. Кандидаты: союзники с `hp < max_hp`.
  Сортировка по `hp` ↓. Используется бафером для приоритизации front-liner'а.

### Новая MovementPolicy

- **AC-MP5**: `policy_approach_nearest_enemy_unclaimed` — как `approach_nearest_enemy`, но:
  1. Находит ближайшего живого врага (игрока).
  2. Строит path к нему (`find_path_around`).
  3. Целевой step `path[1]` проверяет: не совпадает ли он с `move_intent_coord` другого врага из
     `ctx.all_actors`. Если совпадает → проверяет `path[2]` и т.д. (не дальше 2 шагов вперёд).
  4. Если нет незанятого step → возвращает `path[1]` как есть (не блокировать движение полностью).
  - Без геймспид-таймеров. Чистый planner.

### JSON-архетипы в `data/ai_behaviors/`

Четыре новых файла. Стасян наполняет конкретные значения — движок только должен уметь их распарсить.

- **AC-J1**: `melee_fighter.json`
  - Rule 1: `enemy_in_range(1)` → `nearest_enemy` → `[damage, knockback]` — атаковать игрока вплотную.
  - Rule 2: `always` → `always` (нет cast, только move) — fallback на движение.
  - `movement_policy`: `approach_nearest_enemy_unclaimed`.

- **AC-J2**: `ranged_mage.json`
  - Rule 1: `no_enemy_in_range(2)` → `nearest_enemy` → `[damage]` — если игрок далеко, обычный выстрел.
  - Rule 2: `all_of([enemy_in_range(2), unclaimed_hex_exists_near_enemy(player, 1)])` → `unclaimed_hex_near_enemy` → `[damage_aoe]` — AOE в незаконтестованный hex.
  - Rule 3: `enemy_in_range(2)` → `nearest_enemy` → `[damage, damage_aoe]` — fallback: все hex заняты, бьём напрямую.
  - `movement_policy`: `kite_from_nearest_enemy`.

- **AC-J3**: `healer.json`
  - Rule 1: `self_hp_below(40)` → `self` → `[heal]` — лечить себя первым.
  - Rule 2: `ally_hp_below(60, 3)` → `lowest_hp_ally` → `[heal]` — лечить ближайшего раненого союзника.
  - Rule 3: `always` → `nearest_enemy` → `[damage]` — атаковать если нечего лечить.
  - `movement_policy`: `follow_lowest_hp_ally`.

- **AC-J4**: `buffer.json`
  - Rule 1: `ally_hp_below(50, 2)` → `lowest_hp_ally` → `[heal]` — экстренное лечение.
  - Rule 2: `always` → `highest_hp_ally` → `[buff]` — баффать front-liner'а.
  - Rule 3: `always` → `nearest_enemy` → `[damage]` — атаковать если некого баффать/лечить.
  - `movement_policy`: `follow_lowest_hp_ally`.

### Прочее

- **AC-BW1**: Backward-compat. `default_melee.json`, `enraged.json`, `feared.json` — не трогаются.
- **AC-BW2**: Парсер `BehaviorDatabase` — добавляются новые `kind` в switch (`unclaimed_hex_exists_near_enemy`,
  `ally_count_below`, `unclaimed_hex_near_enemy`, `highest_hp_ally`, `approach_nearest_enemy_unclaimed`).
  Существующие `kind`-ветки — без изменений.
- **AC-BW3**: Все новые GDScript-файлы — без `class_name` для autoload'ов (CLAUDE.md trap §Logger).
  Conditions/Selectors/Policies — с `class_name` как все остальные в своих папках.

## Out of scope

- **Дебаф-aware targeting** (`target_has_no_status(status_id)`) — нужен query в StatusEffectManager,
  API не стабилизирован. Заводим hook в condition-парсер (`kind = target_has_no_status` → `always` + warn),
  реализацию — отдельной фичей после 027 stabilization.
- **Summoner архетип** — `ally_count_below` condition реализуется в 030 (AC-C11), но сам `summoner.json`
  потребует `selector_self` + тег `summon` + данных от Стасяна. JSON — вне этого PR.
- **Многошаговое планирование / lookahead** — каждый враг планирует один ход независимо.
- **Formation / flanking** — координация через `unclaimed_hex` решает pile-up, полноценные формации — post-jam.
- **Multi-target player** — логика строится под одного player-team актёра (текущий сетап).
- **Значения баланса** в JSON (pct, distance, count) — Стасян наполняет после движка.

## Координация

- **Egor**: review перед merge в staging — `scripts/core/ai/` его зона. Новые файлы в `selectors/`,
  `conditions/`, `policies/` — additive, existing files не трогаем.
- **Stasyan**: получает JSON-схему архетипов после green smoke, наполняет числа в `data/ai_behaviors/*.json`.
- **Sergey**: не требует review (spec-008 уже его, но 030 — additive extensions).
