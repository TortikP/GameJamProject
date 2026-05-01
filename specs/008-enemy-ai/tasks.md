# 008-enemy-ai — tasks

**Spec:** [`spec.md`](./spec.md) · **Plan:** [`plan.md`](./plan.md)

Легенда: `[P1]` критический путь · `[P2]` нужно для полноты · `[P3]` nice-to-have, можно дропнуть в субботу
`[P]` = parallel-safe (можно делать одновременно с другими `[P]` той же группы)

**Hard prerequisite:** [011-skill-tags](../011-skill-tags/) merged в staging. AC-S5 фактически реализован там — в этом PR не повторяем.

---

## Группа A — фундамент (CastIntent + Actor)

- [ ] **T001** [P1] `scripts/core/ai/cast_intent.gd` — `class_name CastIntent extends Resource`, поля `skill_id: StringName = &""`, `target_id: StringName = &""`, `target_coord: Vector2i = Vector2i(-1,-1)`, `is_valid() -> bool` (см. plan §Resources/CastIntent).
- [ ] **T002** [P1] `scripts/core/actors/actor.gd` — добавить `@export var behavior_id: StringName = &""` после `team`. Добавить `var cast_intent: CastIntent = null` (не `@export` — runtime-only, как `_skills`). AC-S1, AC-I2. (depends T001)
- [ ] **T003** [P1] `scripts/presentation/godmode/manekin_view.gd` — удалить поля `attack_skill_id`, `attack_intent_coord` (строки 8, 12). Также удалить блок строки 26-27 (грузил skill через attack_skill_id). Skills и `behavior_id` будут грузиться из enemy-data в Группе I. **На этом этапе manekin временно не атакует — починим в T080-T082.** (depends T002)
- [ ] **T004** [P1] `scenes/dev/manekin.tscn` — удалить `attack_skill_id = &"skill_manekin_attack"` (строка 11). Добавить `enemy_data_id = &"manekin"` (новое поле, см. T080). (depends T003)

## Группа B — TacticCondition (parallel после A)

- [ ] **T010** [P1] `scripts/core/ai/conditions/tactic_condition.gd` — abstract base. `evaluate(actor: Actor, ctx: Dictionary) -> bool` (default `false`). См. plan §Resources/TacticCondition. (depends T001)
- [ ] **T011** [P1] [P] `condition_always.gd` — AC-C1. `return true`. (depends T010)
- [ ] **T012** [P1] [P] `condition_self_hp_below.gd` — AC-C2. `@export var pct: int = 50`. `actor.hp * 100 < actor.max_hp * pct`. (depends T010)
- [ ] **T013** [P1] [P] `condition_self_hp_above.gd` — AC-C3. Симметрично T012. (depends T010)
- [ ] **T014** [P1] [P] `condition_enemy_in_range.gd` — AC-C4. `@export var distance: int = 1`. Использует `ctx.grid.get_coord(actor.actor_id)` + `ActorRegistry.all()` фильтр по противоположной team. Считает hex-distance через `hex_grid` helper (если нет — добавить `static func hex_distance(a: Vector2i, b: Vector2i) -> int` в `hex_grid.gd`, координация с Egor — это его модуль, additive). (depends T010)
- [ ] **T015** [P1] [P] `condition_no_enemy_in_range.gd` — AC-C5. Инверсия T014, можно делегировать. (depends T014)
- [ ] **T016** [P1] [P] `condition_enemy_count_in_range.gd` — AC-C6. `@export var distance: int`, `@export var min_count: int`. (depends T014)
- [ ] **T017** [P1] [P] `condition_ally_hp_below.gd` — AC-C7. `@export var pct: int`, `@export var distance: int`. Same-team фильтр. (depends T010)
- [ ] **T018** [P1] [P] `condition_skill_ready.gd` — AC-C8. `@export var skill_id: StringName`. `SkillDatabase.get_skill(skill_id).is_ready()`. (depends T010)
- [ ] **T019** [P1] [P] `condition_all_of.gd` / `condition_any_of.gd` / `condition_not_of.gd` — AC-C9 композеры. `@export var children: Array[TacticCondition]` (для all_of/any_of), `@export var child: TacticCondition` (not_of). Парсер в T053 валидирует что children — только примитивы. (depends T010)

## Группа C — TargetSelector (parallel после A)

- [ ] **T020** [P1] `scripts/core/ai/selectors/target_selector.gd` — abstract base. `resolve(actor, candidates: Array, ctx) -> Variant`. См. plan §Resources/TargetSelector. (depends T001)
- [ ] **T021** [P1] [P] `selector_nearest_enemy.gd` — AC-T1. Сортировка кандидатов по hex-distance ↑. (depends T020)
- [ ] **T022** [P1] [P] `selector_lowest_hp_enemy.gd` — AC-T2. По `hp` ↑. (depends T020)
- [ ] **T023** [P2] [P] `selector_highest_hp_enemy.gd` — AC-T3. По `hp` ↓. (depends T020)
- [ ] **T024** [P1] [P] `selector_self.gd` — AC-T4. Возвращает `actor`. (depends T020)
- [ ] **T025** [P2] [P] `selector_lowest_hp_ally.gd` — AC-T5. Allies (same team), `hp < max_hp`. (depends T020)
- [ ] **T026** [P2] [P] `selector_densest_enemy_hex.gd` — AC-T6. Использует `Skill.abilities[0].area.get_affected_hexes(caster_coord, primary_coord, grid)`. Возвращает `Vector2i`, не Actor. (depends T020)
- [ ] **T027** [P3] [P] `selector_random_enemy.gd` — AC-T7. (depends T020)

## Группа D — MovementPolicy (parallel после A)

- [ ] **T030** [P1] `scripts/core/ai/policies/movement_policy.gd` — abstract base. `pick_step(actor, ctx) -> Vector2i`. (depends T001)
- [ ] **T031** [P1] [P] `policy_approach_nearest_enemy.gd` — AC-S2. `find_path_around` к ближайшему врагу, возвращает `path[1]` или `(-1,-1)`. (depends T030)
- [ ] **T032** [P2] [P] `policy_kite_from_nearest_enemy.gd` — AC-S2. Соседний hex, максимизирующий distance к ближайшему врагу. (depends T030)
- [ ] **T033** [P1] [P] `policy_hold_position.gd` — AC-S2. Всегда `(-1,-1)`. (depends T030)
- [ ] **T034** [P3] [P] `policy_follow_lowest_hp_ally.gd` — AC-S2. `find_path_around` к lowest-hp ally. (depends T030)

## Группа E — TacticRule + BehaviorScenario (после B/C/D)

- [ ] **T040** [P1] `scripts/core/ai/tactic_rule.gd` — `class_name TacticRule extends Resource`. `@export var condition: TacticCondition`, `@export var target_selector: TargetSelector`, `@export var tag_priority: Array[StringName]`, `@export var min_skill_count: int = 1`. См. plan §Resources/TacticRule. (depends T010, T020)
- [ ] **T041** [P1] `scripts/core/ai/behavior_scenario.gd` — `class_name BehaviorScenario extends Resource`. `@export var id: StringName`, `@export var rules: Array[TacticRule]`, `@export var movement_policy: MovementPolicy`, `@export var fallback_skill_id: StringName = &""`. (depends T030, T040)

## Группа F — BehaviorDatabase autoload + parser

- [ ] **T050** [P1] `scripts/core/ai/behavior_database.gd` — `extends Node`. Сканит `data/ai_behaviors/*.json` в `_ready`. `_by_id: Dictionary` (StringName → BehaviorScenario). `get(id) -> BehaviorScenario`. По образцу `SkillDatabase`. (depends T041)
- [ ] **T051** [P1] `_build_scenario(data) -> BehaviorScenario` — парсит JSON. Использует helper'ы T052/T053. Невалидный scenario → `GameLogger.warn` + `return null`. (depends T050)
- [ ] **T052** [P1] `_build_rule(data) -> TacticRule` — парсер правила. Switch на `condition.kind` (9 вариантов + 3 композера), `target_selector.kind` (7 вариантов). (depends T051)
- [ ] **T053** [P1] `_build_condition(data) -> TacticCondition` — парсер условия. Внутри `all_of`/`any_of` проходит по `children`, **отвергает вложенные композеры** (AC-C9): если child имеет `kind in [all_of, any_of, not_of]` → `GameLogger.warn` + подменяет всё условие на `condition_always`. Scenario test #11. (depends T051)
- [ ] **T054** [P1] `_build_policy(data) -> MovementPolicy` — парсер policy. Switch на `kind`. Невалидный → `policy_hold_position` + warn. (depends T051)
- [ ] **T055** [P1] `project.godot` — добавить autoload `BehaviorDatabase="*res://scripts/core/ai/behavior_database.gd"` после `SkillDatabase`. (depends T050)

## Группа G — EnemyAIPlanner autoload

- [ ] **T060** [P1] `scripts/core/ai/enemy_ai_planner.gd` — `extends Node`. `plan(actor: Actor, ctx: Dictionary) -> void`. См. plan §Цикл планирования. (depends T055)
- [ ] **T061** [P1] Внутри `plan()` — гейт actor-can-act (AC-GACT-1..3). (depends T060)
- [ ] **T062** [P1] Iterate rules: для каждого rule — evaluate condition, build candidates, filter by tags (`Skill.tags ∩ rule.tag_priority`), sort by tag-priority position, filter by `is_ready()` и валидной target. Если ≥ `min_skill_count` — формируем `cast_intent` и стоп. (depends T061)
- [ ] **T063** [P1] Movement fallback: `scenario.movement_policy.pick_step(actor, ctx)`. Если `(-1,-1)` И `fallback_skill_id` есть И ready И target валиден → cast fallback. Иначе hold + лог `[INFO][AI] %s: no action this turn (no anchor)` (Q-AI-6). (depends T062)
- [ ] **T064** [P1] `project.godot` — autoload `EnemyAIPlanner=...` **после** BehaviorDatabase. (depends T060, T055)

## Группа H — godmode_controller refactor

- [ ] **T070** [P1] `godmode_controller.gd` — удалить функцию `_plan_intents` целиком (строки ~697-732). (depends T064)
- [ ] **T071** [P1] `godmode_controller.gd` — заменить `_plan_intents(actor as Actor, enemies)` на `EnemyAIPlanner.plan(actor as Actor, _build_world_ctx())` (строка ~535). Аналогично строка ~641. (depends T070)
- [ ] **T072** [P1] `godmode_controller.gd` — добавить `_build_world_ctx() -> Dictionary` helper: `{registry, grid, all_actors: registry.all(), turn: TurnManager.current_turn}`. (depends T071)
- [ ] **T073** [P1] `godmode_controller.gd` — `_resolve_attack_intent` → переименовать в `_resolve_cast_intent`. Логика: читает `enemy.cast_intent`, проверяет `is_valid()`, проверяет цель ещё жива/в радиусе/skill ready (AC-X5), `ctx = {registry, grid, target_id, target_coord}`, дёргает `skill.cast`. Старая логика читавшая `attack_intent_coord`/`attack_skill_id` — выкинуть полностью. (depends T002, T070)
- [ ] **T074** [P1] `godmode_controller.gd` — все остальные `enemy.get("attack_intent_coord")` / `enemy.get("attack_skill_id")` (строки 757, 762, 798) — переписать на чтение `enemy.cast_intent` (см. plan §Migration). После grep — ноль residual references. (depends T073)
- [ ] **T075** [P1] `godmode_controller.gd` — `_telegraph_color_for_skill(skill: Skill) -> Color` helper. Match по `skill.tags[0]`, ссылается на `UiTheme.COLOR_TELEGRAPH_*`. См. plan §Telegraph color mapping. AC-I4. (depends T002)
- [ ] **T076** [P1] `godmode_controller.gd` — telegraph rendering (`_refresh_telegraphs`) — для каждого hex использует `_telegraph_color_for_skill(skill)` вместо текущего hardcoded orange. Damage number показывается только если tag[0] in `[damage, damage_aoe, knockback]`. AC-I4, scenario #9. (depends T075)

## Группа I — manekin migration на enemy-data

- [ ] **T080** [P1] `scripts/presentation/godmode/manekin_view.gd` — добавить `@export var enemy_data_id: StringName = &"manekin"`. В `_ready` загрузить enemy-data через новый helper (см. T081), применить `behavior_id`, `skills` (через `set_skills` из 007), `max_hp`, `team`, `speed`. (depends T002)
- [ ] **T081** [P1] `scripts/core/actors/enemy_data_loader.gd` — `static func load_enemy_data(id: StringName) -> Dictionary` — читает `data/enemies/<id>.json`, возвращает Dictionary. Невалидный ID → `null` + warn. (depends T002)
- [ ] **T082** [P1] grep по проекту: ноль references к `attack_skill_id` / `attack_intent_coord`. AC-I2. (depends T003, T004, T074, T080)

## Группа J — data files

- [ ] **T090** [P1] `data/enemies/manekin.json` — backward-compat для текущего manekin'а: `{id, max_hp: 30, team: enemy, speed: 1, skills: [skill_manekin_attack], behavior_id: default_melee, fallback_skill_id: skill_manekin_attack}`. См. plan §JSON schemas. (depends T081)
- [ ] **T091** [P1] `data/ai_behaviors/default_melee.json` — backward-compat (AC-S1): одно правило `enemy_in_range(1) → nearest_enemy → tags=[damage]`, `policy: approach_nearest_enemy`, `fallback_skill_id: skill_manekin_attack`. См. plan §Backward-compat. Scenario test #1. (depends T055)

## Группа K — UiTheme color tokens (Andrey-coordinated)

- [ ] **T100** [P2] `scripts/presentation/ui_theme.gd` — добавить `const COLOR_TELEGRAPH_DAMAGE = Color(...)` (текущий orange, copy-paste из текущего telegraph hardcoded), `_HEAL` (зелёный), `_CONTROL` (фиолетовый), `_BUFF` (синий), `_SUMMON` (золотой), `_MOBILITY` (белый), `_UNKNOWN` (серый). Конкретные RGB — placeholder, пинг Андрея в T130 для финальных значений из 009-ui-kit палитры. CLAUDE.md hard rule §5 — никаких inline `Color()` в presentation. (depends T076)

## Группа L — smoke (manual в Godot, на Egor'е)

Каждый scenario из spec.md секции "Acceptance scenarios" — ручная проверка в редакторе. Результаты пишутся в `specs/008-enemy-ai/SMOKE.md` (создаётся в T110).

- [ ] **T110** [P1] Создать `specs/008-enemy-ai/SMOKE.md` с шаблоном (как в `004-godmode-base/SMOKE.md`). (depends T091)
- [ ] **T111** [P1] Smoke #1 — Backward-compat: manekin без изменений в behavior, ведёт себя как до 008. AC-S1, AC-T1. (depends T091, T100)
- [ ] **T112** [P2] Smoke #2 — Melee brute с low-hp switch. Требует данных от Стасяна (см. T130) или временный JSON для теста. (depends T130)
- [ ] **T113** [P2] Smoke #3 — Ranged caster держит дистанцию. Требует Стасяна или temp JSON. (depends T130)
- [ ] **T114** [P2] Smoke #4 — AOE-триггер. (depends T130)
- [ ] **T115** [P2] Smoke #5 — Support-лекарь. (depends T130)
- [ ] **T116** [P3] Smoke #6 — каскад правил (support fallback). (depends T130)
- [ ] **T117** [P1] Smoke #7 — skill-ready гейтинг. CD = 2 на skill, проверить пропуск правила. (depends T111)
- [ ] **T118** [P1] Smoke #8 — Move OR cast (не оба). (depends T111)
- [ ] **T119** [P2] Smoke #9 — telegraph color для не-damage. (depends T130)
- [ ] **T120** [P1] Smoke #10 — actor-can-act gate. Враг с пустым skills + hold_position. (depends T111)
- [ ] **T121** [P1] Smoke #11 — нестандартный JSON (вложенный all_of) → парсер логирует error, condition→always, не падает. AC-C9. (depends T053)
- [ ] **T122** [P1] Smoke #12 — empty tags backward-compat. Test_*.json (без тегов из 011) — AI их не выбирает. AC-G11. (depends T111)
- [ ] **T123** [P2] Smoke #13 — no-anchor policy. Один враг на карте, всех зачистили. → hold + лог. (depends T111)

## Группа M — координация и close-out

- [ ] **T130** [P1] Пинг Стасяну в чате: «AI-движок 008 готов, JSON-схема `data/enemies/*.json` и `data/ai_behaviors/*.json` зафиксирована (см. plan.md §JSON schemas). Можешь наполнять 4 архетипа: melee_brute, ranged_caster, support, debuffer.» Прикрепить ссылку на plan.md. (depends T111)
- [ ] **T131** [P1] Пинг Андрею: «008 завёл `UiTheme.COLOR_TELEGRAPH_*` константы (T100), placeholder RGB. Когда придёт твой 009 UI Kit — обнови финальными цветами палитры. Coordination AC-I4.» (depends T100)
- [ ] **T132** [P1] Пинг Сергею (когда токены вернутся): «008 plan/tasks написаны, имплемент идёт по группам A→M. Текущий статус — [укажи]. Review когда сможешь.» (depends T060)
- [ ] **T133** [P1] PR `egor/008-plan-tasks → staging`. В описании ссылка на 011 как hard-prereq. Сергей primary reviewer (когда сможет), Андрей secondary. (depends T132 для пинга, иначе можно открывать сразу)
- [ ] **T134** [P3] После всего — обновить `specs/008-enemy-ai/spec.md` AC-S5: добавить пометку «реализовано в 011». Doc-only, не меняет контракт. Можно отдельным мини-PR. (depends T133 + 011 merge)

---

## Заметки для Клода если возьмёт implement

- **Order matters:** Группа A → B|C|D parallel → E → F → G → H → I → J → L. K и M — параллельно с L.
- **PR strategy:** одна ветка, имплемент по группам. Внутри группы — параллельные таски можно одним коммитом, между группами — отдельные коммиты для удобства review. **НЕ** один гигантский commit на весь 008.
- **Перед каждым commit'ом:** `git diff --stat` — убедиться что diff соответствует tasks отмеченным `[x]`.
- **Smoke (T111-T123)** — на Egor'е локально. Godot из container'а не запустить. Клод реализует код+тесты, Egor смок-тестит.
- **Если что-то сломается на T070-T076 (godmode rename):** скорее всего residual `enemy.get("attack_*")` где-то остался — re-grep, пофиксить, не катить дальше.
- **Если `Array[TacticRule]` ругается** на парсе (CLAUDE.md trap §typed-arrays + Variant): переключаемся на plain `Array` в `BehaviorScenario`/композерах, явный cast в planner. Не тратим время на типобезопасность ради автокомплита — это джем.
- **011 dep:** перед T062 (фильтр по тегам) убедиться что `Skill.tags` существует (011 в staging, ветка отребейзена). Иначе фильтр будет на пустых массивах и AI ничего не выберет.
