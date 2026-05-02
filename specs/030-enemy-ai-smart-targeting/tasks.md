# 030-enemy-ai-smart-targeting — tasks

**Spec:** spec.md · **Plan:** plan.md
**Owner:** Alexey

Легенда: `[P1]` критический путь · `[P2]` нужно для полноты · `[P3]` nice-to-have
`[P]` = parallel-safe внутри группы

---

## Группа A — Новые TacticCondition (parallel)

- [ ] **T001** [P1] [P] `scripts/core/ai/conditions/condition_unclaimed_hex_exists_near_enemy.gd`
  `class_name ConditionUnclaimedHexExistsNearEnemy extends TacticCondition`.
  `@export var distance: int = 1`.
  Алгоритм: найти ближайшего живого противника (opposite team), собрать `claimed` coords из
  `cast_intent.target_coord` живых союзников у которых `cast_intent != null and is_valid()`,
  взять `grid.get_walkable_neighbours(target_coord) + [target_coord]`, вернуть true если хоть
  один не в `claimed`. `claimed` — plain `Array` (не Array[Vector2i], CLAUDE.md trap §typed-arrays).
  AC-C10.

- [ ] **T002** [P1] [P] `scripts/core/ai/conditions/condition_ally_count_below.gd`
  `class_name ConditionAllyCountBelow extends TacticCondition`.
  `@export var count: int = 2`.
  evaluate: считает живых союзников (same team, != actor) в `ctx.all_actors`, возвращает `< count`.
  AC-C11.

## Группа B — Новые TargetSelector (parallel)

- [ ] **T010** [P1] [P] `scripts/core/ai/selectors/selector_highest_hp_ally.gd`
  `class_name SelectorHighestHpAlly extends TargetSelector`.
  resolve: из кандидатов (союзники, alive, != actor, max_hp > 0) выбрать с максимальным
  `hp / max_hp` ratio. Вернуть Actor или null. Зеркало SelectorLowestHpAlly.
  AC-T9.

- [ ] **T011** [P1] [P] `scripts/core/ai/selectors/selector_unclaimed_hex_near_enemy.gd`
  `class_name SelectorUnclaimedHexNearEnemy extends TargetSelector`. Возвращает `Vector2i`.
  Шаги (см. plan.md §selector_unclaimed_hex_near_enemy):
  1. Проверить `candidate_skill.abilities[0].target is HexTarget` → если нет return null.
  2. Найти ближайшего врага из кандидатов (nearest by hex_distance).
  3. Собрать `claimed` (plain Array) из `cast_intent.target_coord` живых союзников.
  4. Перебрать `get_walkable_neighbours(target_coord) + [target_coord]`.
  5. Для каждого незанятого hex считать hits через `ab.area.get_affected_hexes` если доступно.
  6. Вернуть hex с max hits; если все заняты → null.
  AC-T8.

- [ ] **T012** [P1] [P] `scripts/core/ai/selectors/selector_target_without_status.gd`
  `class_name SelectorTargetWithoutStatus extends TargetSelector`.
  `@export var status_id: StringName = &""`.
  resolve: если `status_id == &""` → return null. Перебрать кандидатов (враги, alive),
  вернуть первого у кого `not cand.has_status(status_id)`. Если все под статусом → null.
  `actor.has_status(id)` подтверждён — actor.gd:201.
  AC-T10.

## Группа C — Новая MovementPolicy

- [ ] **T020** [P1] `scripts/core/ai/policies/policy_approach_nearest_enemy_unclaimed.gd`
  `class_name PolicyApproachNearestEnemyUnclaimed extends MovementPolicy`.
  Копировать логику `policy_approach_nearest_enemy.gd` полностью (find nearest enemy, build blocked,
  find_path_around). После получения `path`: собрать `taken` (plain Array) из `move_intent_coord`
  живых союзников (same team, != actor) где coord != `Vector2i(-1,-1)`. Пробовать `path[1]`,
  затем `path[2]` (если есть). Возвращать первый не в `taken`. Fallback: `path[1]`.
  AC-MP5.

## Группа D — EnemyAIPlanner патч (независима от A/B/C)

- [ ] **T030** [P1] `scripts/core/ai/enemy_ai_planner.gd` — str_replace одной строки:
  Было:   `var want_allies: bool = selector is SelectorLowestHpAlly`
  Стало:  `var want_allies: bool = selector is SelectorLowestHpAlly or selector is SelectorHighestHpAlly`
  Ничего кроме этой строки не трогать. AC-PL1.
  (depends: T010 должен существовать чтобы class_name SelectorHighestHpAlly был доступен)

## Группа E — BehaviorDatabase парсер (после A/B/C)

- [ ] **T040** [P1] `scripts/core/ai/behavior_database.gd` — `_build_condition` match:
  Добавить два case перед `_:` дефолтом:
  ```
  "unclaimed_hex_exists_near_enemy":
      var c := ConditionUnclaimedHexExistsNearEnemy.new()
      c.distance = int(data.get("distance", 1))
      return c
  "ally_count_below":
      var c := ConditionAllyCountBelow.new()
      c.count = int(data.get("count", 2))
      return c
  ```
  (depends T001, T002)

- [ ] **T041** [P1] `scripts/core/ai/behavior_database.gd` — `_build_selector` match:
  Добавить три case перед `_:` дефолтом:
  ```
  "unclaimed_hex_near_enemy": return SelectorUnclaimedHexNearEnemy.new()
  "highest_hp_ally":          return SelectorHighestHpAlly.new()
  "target_without_status":
      var s := SelectorTargetWithoutStatus.new()
      s.status_id = StringName(data.get("status_id", ""))
      return s
  ```
  (depends T010, T011, T012)

- [ ] **T042** [P1] `scripts/core/ai/behavior_database.gd` — `_build_policy` match:
  Добавить один case перед `_:` дефолтом:
  ```
  "approach_nearest_enemy_unclaimed": return PolicyApproachNearestEnemyUnclaimed.new()
  ```
  (depends T020)

## Группа F — JSON архетипы (после Группы E)

- [ ] **T050** [P1] [P] `data/ai_behaviors/melee_fighter.json`
  id: melee_fighter. Одно правило: enemy_in_range(1) → nearest_enemy → [damage, knockback].
  movement_policy: approach_nearest_enemy_unclaimed. fallback_skill_id: "".
  Числовые placeholder — Стасян правит позже. Точная схема в plan.md.
  (depends T040, T041, T042)

- [ ] **T051** [P1] [P] `data/ai_behaviors/ranged_mage.json`
  id: ranged_mage. Три правила: no_enemy_in_range(2)/nearest_enemy/[damage,damage_aoe],
  all_of([enemy_in_range(2), unclaimed_hex_exists_near_enemy(1)])/unclaimed_hex_near_enemy/[damage_aoe,damage],
  enemy_in_range(2)/nearest_enemy/[damage,damage_aoe].
  movement_policy: kite_from_nearest_enemy. Точная схема в plan.md.
  (depends T040, T041, T042)

- [ ] **T052** [P1] [P] `data/ai_behaviors/healer.json`
  id: healer. Три правила: self_hp_below(40)/self/[heal], ally_hp_below(60,3)/lowest_hp_ally/[heal],
  always/nearest_enemy/[damage]. movement_policy: follow_lowest_hp_ally. Схема в plan.md.
  (depends T040, T041, T042)

- [ ] **T053** [P2] [P] `data/ai_behaviors/buffer.json`
  id: buffer. Четыре правила: self_hp_below(40)/self/[heal], ally_hp_below(50,2)/lowest_hp_ally/[heal],
  always/highest_hp_ally/[buff], always/nearest_enemy/[damage].
  movement_policy: approach_nearest_enemy. Схема в plan.md.
  (depends T040, T041, T042)

## Группа G — Smoke (ручной в Godot, на Alexey/Egor)

- [ ] **T060** [P1] Создать `specs/030-enemy-ai-smart-targeting/SMOKE.md` с шаблоном.
  (depends T053)

- [ ] **T061** [P1] Smoke #1 — Backward-compat: default_melee.json, enraged.json, feared.json
  работают без изменений.

- [ ] **T062** [P1] Smoke #2 — Melee pile-up: 3 melee_fighter'а идут к игроку. Все три
  занимают РАЗНЫЕ клетки (не стакаются). `approach_nearest_enemy_unclaimed` работает.

- [ ] **T063** [P1] Smoke #3 — Ranged Rule 2: рейнджер с AoE-скиллом при близком игроке
  бьёт в незаконтестованный соседний hex, а не напрямую.

- [ ] **T064** [P1] Smoke #4 — Ranged без hex-скилла: рейнджер с actor-only скиллами
  пропускает Rule 2 и бьёт напрямую (Rule 3).

- [ ] **T065** [P1] Smoke #5 — Healer self-heal: лекарь с <40% HP лечит себя прежде союзника.

- [ ] **T066** [P1] Smoke #6 — Healer ally: лекарь с >40% HP и раненым союзником
  (<60% HP) лечит союзника, а не атакует.

- [ ] **T067** [P2] Smoke #7 — Buffer: баффает союзника с наибольшим HP (не низшим).

- [ ] **T068** [P2] Smoke #8 — Debuff hook: selector_target_without_status корректно
  пропускает уже задебаференных и берёт первого без статуса.

- [ ] **T069** [P2] Smoke #9 — All hexes contested: если все соседние hex игрока
  заняты cast_intent'ами, рейнджер падает в Rule 3 и атакует напрямую.

## Группа H — Координация

- [ ] **T080** [P1] Пинг Egor'у: «030 plan/tasks готовы, имплемент идёт. Один патч в
  enemy_ai_planner.gd (T030, одна строка). Новые файлы в core/ai/ additive. Review когда сможешь.»

- [ ] **T081** [P1] Пинг Stasyan'у: «030 JSON-схема готова (data/ai_behaviors/*.json).
  Числа — placeholder, ставь финальные: melee_fighter distance=1 ok; ranged_mage distance=2 check;
  healer pct=40/60 check; buffer pct=40/50 check.»
  (depends T060)

- [ ] **T082** [P1] PR `alexey/030-smart-targeting → staging`. Egor primary reviewer.
  (depends T069 или хотя бы T061-T064 green)
