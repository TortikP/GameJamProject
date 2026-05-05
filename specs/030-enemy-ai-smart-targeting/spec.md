# 030-enemy-ai-smart-targeting — spec

**Owner:** Alexey
**Status:** Draft v2 — остановка перед /plan. Требует review Egor'а (модуль `scripts/core/ai/` его зона).
**Upstream:** 008-enemy-ai (merged), 011-skill-tags (merged), 027-status-effects (merged)

## Цель

Добавить «умные» правила выбора цели для 4 архетипов врагов (melee_fighter, ranged_mage, healer, buffer)
с учётом действий других врагов на том же ходу. Враги не стакаются на одну клетку, рейнджер бьёт туда
куда не бьёт мили, лекарь лечит себя раньше чем умирает.

Реализация — **только новые selectors/conditions/policies + JSON-файлы архетипов в data/ai_behaviors/**.
Движок EnemyAIPlanner, BehaviorDatabase, контроллер — не трогаются кроме двух additive строк (AC-PL1).

## Ключевые концепции

### Intent-awareness

Планирование sequential (008 AC-X1). К моменту вызова EnemyAIPlanner.plan(enemy_N, ctx),
враги 0..N-1 уже записали cast_intent и move_intent_coord на себя. ctx.all_actors — снимок
всех акторов; интенты читаются напрямую. Изменений в _world_ctx() или сигнатуре plan() не нужно.

### Три приоритета для damage-архетипов

  Приоритет 1  (melee-range): атаковать игрока напрямую когда стоим вплотную.
  Приоритет 2  (hex/AOE): атаковать незаконтестованный hex рядом с игроком, если есть
               hex-targeting скилл и хотя бы один соседний hex не занят другими cast_intent.
  Приоритет 3  (fallback): атаковать игрока напрямую (все hex заняты или нет hex-скиллов).

Реализуется тремя TacticRule в JSON. Никакой логики в EnemyAIPlanner.

### Hex-targeting validation

Planner не проверяет соответствие target.kind с возвращаемым типом selector'а.
selector_unclaimed_hex_near_enemy сам читает sel_ctx["candidate_skill"].abilities[0].target
и возвращает null если это не HexTarget. Тогда planner выфильтровывает скилл.
Если у врага нет ни одного HexTarget-скилла с нужным тегом → правило не срабатывает → Rule 3.
HexTarget: res://scripts/core/abilities/targets/hex_target.gd

## Acceptance criteria

### Новые TacticCondition

- **AC-C10**: unclaimed_hex_exists_near_enemy(distance: int = 1)
  True если среди гексов на hex-расстоянии <= distance от ближайшего живого врага
  хотя бы один НЕ совпадает с cast_intent.target_coord живого союзника из ctx.all_actors.
  Гексы: grid.get_walkable_neighbours(target_coord) + target_coord.
  Ближайший противник не найден -> false.

- **AC-C11**: ally_count_below(count: int)
  True если живых союзников (same team, excl. self) < count. Хук для призывателя (summoner.json out of scope).

### Новые TargetSelector

- **AC-T8**: selector_unclaimed_hex_near_enemy -> Vector2i
  1. Найти ближайшего живого противника из кандидатов (логика nearest_enemy).
  2. Гексы: grid.get_walkable_neighbours(target_coord) + target_coord.
  3. Из уже спланировавших союзников (same team AND cast_intent != null AND is_valid())
     собрать claimed: Array[Vector2i] = их cast_intent.target_coord.
  4. Target.kind validation: проверить sel_ctx[candidate_skill].abilities[0].target is HexTarget.
     Если нет -> return null (actor-only скилл, planner выфильтрует).
  5. Вернуть первый гекс из шага 2 не попавший в claimed.
     Tiebreak: гекс с наибольшим числом врагов в зоне AoE (если area доступна), иначе первый.
  6. Все заняты -> null.

- **AC-T9**: selector_highest_hp_ally -> Actor
  Симметрия selector_lowest_hp_ally. Кандидаты: союзники с hp < max_hp. Сортировка по hp DESC.
  Используется бафером для приоритизации front-liner'а.

- **AC-T10**: selector_target_without_status(status_id: StringName) -> Actor (hook)
  Из кандидатов-противников выбирает первого без активного статуса status_id.
  Требует actor.has_status(status_id) -> bool из 027-status-effects.
  Если все под дебафом -> null -> следующее правило.
  Если API недоступен -> fallback selector_nearest_enemy + GameLogger.warn.

### Плановое изменение в EnemyAIPlanner (additive, AC-PL1)

_build_target_candidates: добавить SelectorHighestHpAlly в want_allies-ветку:

  var want_allies: bool = selector is SelectorLowestHpAlly or selector is SelectorHighestHpAlly

Без этого selector_highest_hp_ally получит список врагов вместо союзников.
selector_target_without_status использует врагов (want_allies = false) — изменений не нужно.

### Новая MovementPolicy

- **AC-MP5**: policy_approach_nearest_enemy_unclaimed
  Как approach_nearest_enemy, но step-кандидат path[1] проверяется:
  не совпадает ли с move_intent_coord другого союзника из ctx.all_actors.
  Если совпадает -> пробует path[2] (не дальше 2 вперёд).
  Если нет незанятого -> возвращает path[1] (не блокировать движение).

### JSON-архетипы в data/ai_behaviors/

Числовые значения (pct, distance) — placeholder, финальные ставит Стасян.

**melee_fighter.json** (AC-J1)
  Rule 1: enemy_in_range(1) -> nearest_enemy -> [damage, knockback]
  Rule 2: always -> нет cast; только movement
  movement_policy: approach_nearest_enemy_unclaimed

**ranged_mage.json** (AC-J2)
  Rule 1: no_enemy_in_range(2) -> nearest_enemy -> [damage, damage_aoe]
    (игрок далеко 3+ hex — обычный выстрел)
  Rule 2: all_of([enemy_in_range(2), unclaimed_hex_exists_near_enemy(1)])
           -> unclaimed_hex_near_enemy -> [damage_aoe, damage]
    (игрок близко, есть свободный hex; [damage_aoe, damage] покрывает non-AoE hex-скиллы;
     actor-only скилл -> selector вернёт null -> правило не сработает -> Rule 3)
  Rule 3: enemy_in_range(2) -> nearest_enemy -> [damage, damage_aoe]
    (fallback: все hex заняты или нет hex-скиллов)
  movement_policy: kite_from_nearest_enemy

**healer.json** (AC-J3)
  Rule 1: self_hp_below(40) -> self -> [heal]
  Rule 2: ally_hp_below(60, 3) -> lowest_hp_ally -> [heal]
  Rule 3: always -> nearest_enemy -> [damage]
  movement_policy: follow_lowest_hp_ally

**buffer.json** (AC-J4)
  Rule 1: self_hp_below(40) -> self -> [heal]
  Rule 2: ally_hp_below(50, 2) -> lowest_hp_ally -> [heal]
  Rule 3: always -> highest_hp_ally -> [buff]
  Rule 4: always -> nearest_enemy -> [damage]
  movement_policy: approach_nearest_enemy

### Прочее

- **AC-BW1**: default_melee.json, enraged.json, feared.json — не трогаются.
- **AC-BW2**: BehaviorDatabase парсер — новые kind в switch:
  conditions: unclaimed_hex_exists_near_enemy, ally_count_below
  selectors: unclaimed_hex_near_enemy, highest_hp_ally, target_without_status
  policy: approach_nearest_enemy_unclaimed
- **AC-BW3**: Новые GDScript — с class_name (как остальные в папках). Autoload-файлов нет.

## Out of scope

- selector_target_without_status полная работоспособность — зависит от actor.has_status() в 027.
  Хук реализуем, API проверяется в _ready-фазе selector'а.
- summoner.json — ally_count_below готов, JSON не делаем.
- Многошаговый lookahead, formation/flanking.
- Значения баланса — Стасян.

## Координация

- **Egor**: review. Одна строка в enemy_ai_planner.gd (AC-PL1). Новые файлы additive, его код не трогаем.
- **Stasyan**: JSON числа после green smoke.
- **Sergey**: review не нужен (additive к 008).
