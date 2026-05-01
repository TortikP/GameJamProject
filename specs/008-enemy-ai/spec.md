# 008-enemy-ai — spec

**Owner:** Sergey (claim-on-PR; «hex arena, battle loop, **enemies**» в CLAUDE.md рекомендован Egor — координация ДО merge)
**Status:** Draft — open questions closed, готово к /plan

## Цель

Заменить текущий примитивный AI из `godmode_controller.gd` (один монолитный move-or-attack для всех манекенов) на **data-driven систему поведений**: каждый враг ссылается на «сценарий поведения» (melee, ranged caster, support, debuffer …), сценарий — это упорядоченный список тактических правил в стиле Dragon Age, выбирающих **навык по приоритету тегов** и условиям мира.

Соответствует пилларсам:
- **§1.5.2 Симметрия игрок ↔ монстр** — AI выбирает действие из тех же примитивов (`grid.move_actor`, `Skill.cast`), что и игрок. Никаких enemy-only путей урона.
- **§1.5.1 Полная информация** — AI обязан публиковать intent (`move_intent_coord`, `cast_intent`) ДО исполнения; телеграфы и стрелки движения остаются работающими, для не-damage скиллов добавляется минимальная семантическая раскраска.
- **CLAUDE.md "Hard rules / Content"** — поведения, теги, скиллы — JSON в `data/`. Программисты пишут движок, дизайнеры наполняют сценарии. Без новых сценариев «в коде».

## Resolved questions (фикс на момент /plan)

- **Q-AI-1 → (b)**: теги живут на `Skill.tags: Array[StringName]`. Ability-tags нет (Ability сейчас в принципе не существует как самостоятельная JSON-сущность — только embedded внутри Skill, см. 007 architecture §1).
- **Q-AI-2 → (b)**: один action в ход — default. Исключение: «рывок-атака» и подобные — это **один Skill** с двумя abilities внутри (например, `MoveEffect` + `DamageEffect`), которые исполняются как один cast. Pillar симметрии не нарушается, потому что игрок получает ровно такой же Skill через JSON.
- **Q-AI-3 → (a)**: tiebreak — первый по порядку в `actor.skills` среди прошедших фильтр. Детерминизм для дебага.
- **Q-AI-4 → (c)**: минимум на этой спеке — цвет hex телеграфа по семантике первого тега Skill (orange=damage, green=heal, purple=control/debuff, blue=buff, gold=summon, white=mobility). Иконки — отдельная UX-фича.
- **Q-AI-5 → (a)**: композиция условий — 1 уровень. Правило содержит ровно один оператор (`all_of` | `any_of` | `not_of`), внутри только плоские примитивы. Без вложенности.
- **Q-AI-6 → (b)+(I)**: fallback не глобальный, всегда отрабатывает `movement_policy` сценария. Если у policy не нашлось якоря (нет враждебных целей при `kite_from_nearest_enemy`, нет союзников при `follow_lowest_hp_ally`) → `hold_position` + `GameLogger.info("AI", "%s: no action this turn (no anchor)" % actor_id)`.

## Что меняется vs существующей системы (после 007 merge)

| Слой | Сейчас | После 008 |
|---|---|---|
| AI | прибит к `godmode_controller._plan_intents` (40 строк, hardcoded «иди к игроку, бей если рядом») | отдельный модуль `scripts/core/ai/`, `EnemyAIPlanner` |
| Поведение | одно для всех манекенов | `BehaviorScenario` Resource, ссылка по id из enemy-данных |
| Выбор действия | if-adjacent then attack else step | упорядоченные `TacticRule` (condition + target_selector + tag_priority) |
| Теги | нет | `Skill.tags: Array[StringName]` (additive поле; legacy skills работают с пустым массивом тегов и не выбираются никаким правилом — попадают только в catch-all `tags: []` rule, см. AC-G11) |
| Данные врага | inline `@export var attack_skill_id` на `manekin_view` | `data/enemies/<id>.json` со списком навыков и behavior_id |
| Сценарии | нет | `data/ai_behaviors/<id>.json` (default_melee, ranged_caster, support, debuffer, …) |
| Intent на актёре | пара `attack_skill_id` (declared) + `attack_intent_coord` (planned) — слабо для chain/zone (нет `target_id`) | `cast_intent: CastIntent` Resource = `{skill_id, target_id, target_coord}` единое поле |
| `_plan_intents`, `_resolve_*_intent` в контроллере | остаются как **executor** (рендер intent → визуал, animate move/cast) | контракт между AI-модулем и контроллером — фиксируется явно |

## Acceptance criteria

### Структура данных

- **AC-S1**: Enemy (любой Actor с `team = &"enemy"`) имеет `behavior_id: StringName`. Если `behavior_id == &""` → используется fallback `default_melee` (текущий «иди и бей»). Backward-compat: существующие manekin без `behavior_id` ведут себя как сейчас.
- **AC-S2**: `BehaviorScenario` (Resource) хранит:
  - `id: StringName`
  - `rules: Array[TacticRule]` (длина ≥ 1)
  - `movement_policy: StringName` (`approach_nearest_enemy` / `kite_from_nearest_enemy` / `hold_position` / `follow_lowest_hp_ally` — список открыт, designer добавляет в коде нового policy при необходимости — не data-only).
- **AC-S3**: `TacticRule` (Resource) хранит:
  - `condition: TacticCondition` (см. AC-C*)
  - `target_selector: StringName` (см. AC-T*)
  - `tag_priority: Array[StringName]` (упорядочено: первый тег — самый желанный)
  - `min_skill_count: int = 1` (правило срабатывает, только если найдено хотя бы N подходящих скиллов; 1 = «хоть один»).
- **AC-S4**: Enemy-данные `data/enemies/<id>.json` имеют поля:
  - `id: StringName`
  - `max_hp: int`
  - `team: StringName` (опционально, default `enemy`)
  - `speed: int`
  - `skills: Array[StringName]` — **список skill-id из `SkillDatabase`**, не ability-id.
  - `behavior_id: StringName`
  - `fallback_skill_id: StringName` — что использовать если ни одно правило не сработало и враг рядом с anchor (для совместимости с текущим manekin: `skill_manekin_attack`). Может быть `&""` (нет fallback).
- **AC-S5**: `Skill` получает поле `tags: Array[StringName]` (additive в `data/skills/*.json`, `breaking:` префикс не нужен — пустой default не ломает существующий контент). Migration: к существующим skill_*.json добавить `"tags": [...]` сразу в этом же PR — без тегов AI их выбрать не сможет, но игрок продолжает кастовать через слоты.

### Условия (`TacticCondition`)

Условия — типизованные. Все читаются из мира на момент планирования (не закешированы между ходами).

- **AC-C1**: `always` — всегда true. Используется как catch-all в конце списка правил.
- **AC-C2**: `self_hp_below(pct: int)` — true если `actor.hp / actor.max_hp * 100 < pct`.
- **AC-C3**: `self_hp_above(pct: int)` — симметрично C2.
- **AC-C4**: `enemy_in_range(distance: int)` — true если хотя бы один противник на гекс-расстоянии ≤ distance.
- **AC-C5**: `no_enemy_in_range(distance: int)` — инверсия C4. Используется ranged-кастером.
- **AC-C6**: `enemy_count_in_range(distance: int, min_count: int)` — true если в радиусе ≥ min_count противников. Триггер для AOE.
- **AC-C7**: `ally_hp_below(pct: int, distance: int)` — есть ли в радиусе союзник с HP ниже %. Триггер для лекарей.
- **AC-C8**: `skill_ready(skill_id: StringName)` — `SkillDatabase.get_skill(skill_id).is_ready()`. Работает прямо сейчас (CD движок уже в 007).
- **AC-C9**: Композиция — **ровно 1 уровень**. Условие — это либо примитив C1-C8, либо одна обёртка `all_of([…])` / `any_of([…])` / `not_of(prim)`, где терминалы — только примитивы. Вложение операторов друг в друга **запрещено**. Парсер JSON делает плоскую проверку и должен **отвергать** невалидные структуры с логом и `condition = always` fallback.

### Селекторы цели (`target_selector`)

Селектор работает в две фазы: (1) фильтр кандидатов с учётом доступных Skill (range, тип target), (2) сортировка → берётся первый. Если кандидатов нет — правило не срабатывает.

- **AC-T1**: `nearest_enemy` — кандидаты: все живые enemies относительно `actor.team`. Сортировка по гекс-расстоянию ↑.
- **AC-T2**: `lowest_hp_enemy` — кандидаты: enemies в радиусе максимальной дальности доступных скиллов выбранного тега. Сортировка по `hp` ↑.
- **AC-T3**: `highest_hp_enemy` — симметрично T2.
- **AC-T4**: `self` — `[actor]`. Для `heal`/`buff`-тегов на себя.
- **AC-T5**: `lowest_hp_ally` — кандидаты: союзники с `hp < max_hp` в радиусе скиллов. Для лекарей.
- **AC-T6**: `densest_enemy_hex` — гекс с максимальным числом enemies, попадающих в зону Skill (использует `Skill.abilities[0].area.get_affected_hexes()`, см. 007 architecture §6). Для AOE-тегов. Возвращает `target_coord`, не `target_id`.
- **AC-T7**: `random_enemy` — равномерный выбор. Для chaotic-сценариев.

### Теги навыков

Список не закрыт — designer добавляет новые в JSON. Стартовый набор для джема:

- **AC-G1**: `damage` — мгновенный урон одиночной цели.
- **AC-G2**: `damage_aoe` — урон по зоне (Skill с не-chain area).
- **AC-G3**: `control` — стан, обездвиживание, прерывание (статусы — out of scope этой спеки, но тег существует).
- **AC-G4**: `knockback` — толкает цель.
- **AC-G5**: `heal` — восстанавливает HP союзнику или себе.
- **AC-G6**: `buff` — позитивный статус.
- **AC-G7**: `debuff` — негативный статус.
- **AC-G8**: `summon` — призыв нового актёра (через `CreateEffect`).
- **AC-G9**: `mobility` — собственное перемещение (телепорт, рывок).
- **AC-G10**: Skill может иметь несколько тегов. Соответствие правилу: совпадение хотя бы одного тега из `tag_priority`. Приоритет внутри правила — по позиции тега в `tag_priority`, не в `Skill.tags`.
- **AC-G11**: Skill с пустым `tags: []` AI **никогда не выбирает** через тег-фильтр — попадёт только в `fallback_skill_id`. Это пристойный default для legacy-скиллов, которые не успели разметить.

### Цикл планирования

- **AC-X1**: AI вызывается на каждый `EventBus.world_turn_ended`. Для каждого живого enemy — по очереди (sequential, как сейчас в `_run_enemy_turn`).
- **AC-X2**: Шаг 1 — гейт «может действовать?» (см. AC-GACT-*). Если нет — enemy пропускается (никаких intent на этот ход).
- **AC-X3**: Шаг 2 — выбор действия по сценарию. Алгоритм:
  1. Для каждого правила в `behavior.rules` сверху вниз:
     a. Проверить `condition` против актуального состояния мира.
     b. Если false → следующее правило.
     c. Если true: собрать кандидаты-навыки `actor.skills` ∩ `{skill | skill.tags ∩ rule.tag_priority ≠ ∅}`. Сортировать по позиции **наилучшего совпадающего** тега в `tag_priority` ↑ (меньший индекс = выше приоритет). Tiebreak — порядок в `actor.skills` (Q-AI-3).
     d. Из этого списка отфильтровать те, у которых `skill.is_ready()` И есть валидная цель по `target_selector` (учитывая `range` skill'а).
     e. Если осталось ≥ `min_skill_count` → выбираем **первый** → формируем `cast_intent = {skill_id, target_id, target_coord}` (см. AC-I2). **Стоп.**
     f. Иначе → следующее правило.
  2. Если ни одно правило не сработало → решение по `movement_policy`: куда идти (или стоять).
  3. Если `movement_policy` тоже не даёт целевого гекса (нет якоря) → `hold_position` + лог (Q-AI-6).
- **AC-X4**: AI делает **одно** действие за ход — move ИЛИ cast (Pillar §1.5.2, симметрия с player). Skill, который содержит movement-ability + damage-ability внутри (см. Q-AI-2), — это всё ещё **один cast**, не два действия.
- **AC-X5**: Цели выбираются на момент **планирования** (для телеграфа). При резолве в следующем тике — перепроверка: цель ещё жива, в радиусе, навык ещё ready. Если нет — действие отменяется (как сейчас «attack missed»).

### Гейт «враг может действовать?» (AC-GACT-*)

Узел в схеме «Враг может действовать?» — единая точка проверки.

- **AC-GACT-1**: false если `not actor.is_alive()`.
- **AC-GACT-2**: false если у актёра пустые `skills` И `movement_policy = hold_position`.
- **AC-GACT-3**: Хуки на статусы (stun, root, paralyze, silence) — **out of scope**. Когда status-движок появится отдельной фичей — добавляются AC-GACT-4..6 «false если в `stun`-статусе» и т.д. в той же фиче, не в 008.

### Контракт между AI-модулем и контроллером

AI публикует intent, контроллер исполняет в следующем тике. Существующий протокол расширяется, не ломается.

- **AC-I1**: `move_intent_coord: Vector2i` на Actor — без изменений.
- **AC-I2**: Пара `attack_skill_id` (declared) + `attack_intent_coord` (planned) → объединяется в `cast_intent: CastIntent` Resource: `{skill_id: StringName, target_id: StringName, target_coord: Vector2i}`. `target_id == &""` означает «hex-target, читай target_coord»; `target_id != &""` — «entity-target, читай target_id». Старые поля manekin'а (`attack_skill_id` declared) переезжают в `data/enemies/*.json` (`skills` массив + `fallback_skill_id`) — `attack_skill_id` удаляется на manekin'е тем же PR. `attack_intent_coord` удаляется в пользу `cast_intent` тем же PR.
- **AC-I3**: Контроллер godmode (`_resolve_attack_intent` → переименовать в `_resolve_cast_intent`) расширяется: умеет резолвить любой `Skill` (не только melee single-target). Дальняя атака, AOE — допускаются на уровне контракта; конкретика анимаций / снарядов — out of scope.
- **AC-I4**: Telegraph аггрегирует урон по hex как сейчас (`predicted_damage_to`, см. 007 architecture §1.5.1). Для не-damage скиллов телеграф рисует hex с цветом по primary-тегу `Skill.tags[0]`:
  - `damage` / `damage_aoe` / `knockback` → orange (текущий цвет, без изменений).
  - `heal` → green.
  - `control` / `debuff` → purple.
  - `buff` → blue.
  - `summon` → gold.
  - `mobility` → white.
  - empty/unknown → серый, без damage-числа.
  Mapping в коде в одном месте, designer не редактирует.

### Acceptance scenarios (тесты)

1. **Backward-compat.** Manekin с `behavior_id = &""` (или отсутствием поля) ведёт себя ровно как до 008: подходит к игроку, бьёт через `default_melee`. Pillar — не сломан.
2. **Melee brute с лоу-хп переключением.** Враг с `behavior_id=melee_brute`, hp=10/100, рядом игрок hp=20 и манекен hp=5. Сработает rule «`self_hp_below(30)`» → `lowest_hp_enemy` → выберет манекена (5<20). Skill с тегом `damage`, доступный по range 1.
3. **Ranged caster держит дистанцию.** Враг `ranged_caster`, игрок на расстоянии 1. Rule `enemy_in_range(1)` → `[control, mobility]` → если control-skill готов и в радиусе игрок → cast control. Иначе — следующее правило.
4. **AOE-триггер.** Враг `ranged_caster`, в радиусе 3 игрок и 2 союзника игрока (= 3 enemies для каста). Rule `enemy_count_in_range(3, 2)` → `damage_aoe` → `densest_enemy_hex` (`target_coord` рассчитан через `Skill.abilities[0].area.get_affected_hexes()`).
5. **Support-лекарь.** Враг `support`, рядом союзник hp=20/100. Rule `ally_hp_below(50, 3)` → `heal` → `lowest_hp_ally`. Союзник вылечен. Telegraph hex союзника зелёный.
6. **Каскад правил.** `support` без задетого ally_hp и `buff_haste` на CD. Падает в третье правило (`always → debuff/damage on nearest`).
7. **Skill-ready гейтинг.** Rule `[heal]` не находит готовый skill (small_heal на cooldown) → правило пропускается → следующее правило.
8. **Move OR cast — не оба.** AI выбрал damage на цели вне радиуса каста: правило не срабатывает (нет валидной цели), последующее правило/policy → `approach_nearest_enemy` → move. Cast в этот ход не происходит.
9. **Detailed telegraph для не-damage.** Heal-каст на союзника: hex союзника зелёный, цифры урона нет.
10. **Гейт actor-can-act.** Враг `skills=[]` и `movement_policy=hold_position` → пропускается, intent пустой, телеграф пустой.
11. **Композиция условий — валидация.** В JSON: `{"all_of": [{"all_of": [...]}]}` (вложенный all_of) → парсер логирует error и подменяет на `condition = always`. Не падает.
12. **Empty tags backward-compat.** Skill без `tags` → ни одно правило с тегами его не выбирает; используется только если попадает в `fallback_skill_id`.
13. **No-anchor policy.** `ranged_caster` остался один на карте (всех зачистили). Все правила требуют врага. `kite_from_nearest_enemy` — нет якоря. → `hold_position` + лог `[INFO][AI] %s: no action this turn (no anchor)`.

## Out of scope

- **Status effects** (stun, root, silence). Тег `control` существует, но что он *делает* — отдельная фича. AI-гейт «может действовать» статусы пока не учитывает.
- **Объекты как цели/препятствия** (ящики, колонны — `ObjectTarget` в 007 stub). На 008 актёры only.
- **AI-редактор сценариев** (UI/DSL). Сценарии — голый JSON, designer редактирует руками.
- **Group / squad behaviors** (фланкинг, focus fire по приказу лидера, формации). Каждый враг планирует независимо.
- **Path heuristics за пределами текущего `find_path_around`.** «Спрятаться за стенку», «занять high ground» — после джема.
- **Конкретные значения баланса** (какой % HP у melee_brute триггерит retreat, какие скиллы у ranged_caster). Stasyan наполняет JSON в `data/ai_behaviors/` и `data/enemies/` уже после движка.
- **Анимации, VFX, звук, голосовые реакции AI** на действия. Pillar §1.5.1 требует только **визуальную** инфу (telegraph, цвет hex). Звук/VFX — отдельный polish.
- **Save/load AI state** (накопленные cooldown-таймеры, persistent intent). Игра не сейвится в джеме.
- **Иконки на телеграфе** (Q-AI-4 (a)/(b)) — отдельная UX-фича. На 008 — только цвет hex.
- **Tags-добавление на уже существующие 4 production-skill JSONа** — это часть migration этой фичи (см. AC-S5), не отдельный PR.

## Заметки реализации (для будущей plan.md)

- **AI-модуль = `scripts/core/ai/`.** Не трогать `core/abilities/` и `core/skills/`. Расширения на `Actor` (`behavior_id`, `cast_intent`) — additive.
- **`EnemyAIPlanner`** — autoload (по симметрии с `AbilityDatabase`/`SkillDatabase`). API: `plan(actor, ctx) -> void` (пишет на актёра `move_intent_coord` и `cast_intent`). Без статуса между вызовами.
- **`BehaviorDatabase`** — autoload, сканит `data/ai_behaviors/*.json` при старте. Парсит в `BehaviorScenario` Resource. Регистрирует ID → ресурс.
- **Контракт с `godmode_controller`:** `_plan_intents` исчезает, заменяется на `EnemyAIPlanner.plan(actor, world_ctx)`. `_resolve_attack_intent` → `_resolve_cast_intent` (читает `cast_intent`, кастует любой Skill).
- **Backward-compat:** `data/ai_behaviors/default_melee.json` пишется так, чтобы поведение бит-в-бит совпало с текущим manekin AI (правило: `enemy_in_range(1) → [damage]`, `nearest_enemy`, `fallback_skill_id` на тот же melee_punch; movement: `approach_nearest_enemy`). Тест #1 в Acceptance это проверяет.
- **Tags на existing skills:** в этом же PR размечаются 4 production skill_*.json — `skill_debug_punch`/`skill_melee_punch`/`skill_manekin_attack` → `["damage"]`; `skill_knockback_punch` → `["damage", "knockback"]`. test_*.json (внутренние тесты Egor'а) — оставить пустыми, AI их не использует.
- **Migration `attack_skill_id` + `attack_intent_coord` → `cast_intent`:** чисто refactoring, никакой функциональности не меняет — godmode_controller строит CastIntent из текущей пары. Делается ОДНИМ commit'ом сразу после введения `cast_intent` Resource.
- **Стасян** наполняет `data/enemies/<id>.json` (4 архетипа: melee_brute, ranged_caster, support, debuffer) после того как движок собран. Я не лезу в баланс.
- **Координация с Egor:** `Skill.tags` — additive поле, prefix `breaking:` не нужен (default=`[]` сохраняет старое поведение). Перед запушем PR в staging — пинг в чате на «добавляю tags на Skill, OK?».
