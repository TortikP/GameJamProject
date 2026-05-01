# 008-enemy-ai — spec

**Owner:** Sergey (claim-on-PR; «hex arena, battle loop, **enemies**» в CLAUDE.md рекомендован Egor — координация ДО merge: tags-поле на Skill/Ability задевает 007 и должно быть согласовано с ним)
**Status:** Draft — open questions внизу, закрыть до /plan

## Цель

Заменить текущий примитивный AI из `godmode_controller.gd` (один монолитный move-or-attack для всех манекенов) на **data-driven систему поведений**: каждый враг ссылается на «сценарий поведения» (melee, ranged caster, support, debuffer …), сценарий — это упорядоченный список тактических правил в стиле Dragon Age, выбирающих навык по приоритету тегов и условиям мира.

Соответствует пилларсам:
- **§1.5.2 Симметрия игрок ↔ монстр** — AI выбирает действие из тех же примитивов (`grid.move_actor`, `Skill/Ability.cast`), что и игрок. Никаких enemy-only путей урона.
- **§1.5.1 Полная информация** — AI обязан публиковать intent (`move_intent_coord`, `cast_intent`) ДО исполнения; телеграфы и стрелки движения остаются работающими.
- **CLAUDE.md "Hard rules / Content"** — поведения, теги, скиллы — JSON в `data/`. Программисты пишут движок, дизайнеры наполняют сценарии. Без новых сценариев «в коде».

## Что меняется vs существующей системы

| Слой | Сейчас | После 008 |
|---|---|---|
| AI | прибит к `godmode_controller._plan_intents` (40 строк, hardcoded «иди к игроку, бей если рядом») | отдельный модуль `scripts/core/ai/`, `EnemyAI` Resource на актёре |
| Поведение | одно для всех манекенов | `BehaviorScenario` Resource, ссылка по id из enemy-данных |
| Выбор действия | if-adjacent then attack else step | упорядоченные `TacticRule` (condition + target + tag-priority) |
| Теги навыков | нет | `tags: Array[StringName]` на Ability (или Skill — Q-AI-1) |
| Данные врага | inline `@export var attack_ability_id` на manekin_view | `data/enemies/<id>.json` со списком навыков и behavior_id |
| Сценарии | нет | `data/ai_behaviors/<id>.json` (melee_brute, ranged_caster, support, …) |
| `_plan_intents`, `_resolve_*_intent` в контроллере | остаются как **executor** (рендер intent → визуал, animate move/cast) | контракт между AI-модулем и контроллером — фиксируется явно |

## Acceptance criteria

### Структура данных

- **AC-S1**: Enemy (любой Actor с `team = &"enemy"`) имеет `behavior_id: StringName`. Если `behavior_id == &""` → используется fallback `default_melee` (текущий «иди и бей»). Сохраняет обратную совместимость: существующие manekin без behavior_id ведут себя как сейчас.
- **AC-S2**: `BehaviorScenario` (Resource) хранит:
  - `id: StringName`
  - `rules: Array[TacticRule]` (длина ≥ 1)
  - `movement_policy: StringName` (`approach_nearest_enemy` / `kite_from_nearest_enemy` / `hold_position` / `follow_lowest_hp_ally` — список открыт)
- **AC-S3**: `TacticRule` (Resource) хранит:
  - `condition: TacticCondition` (см. AC-C*)
  - `target_selector: StringName` (см. AC-T*)
  - `tag_priority: Array[StringName]` (упорядочено: первый тег — самый желанный)
  - `min_skill_count: int = 1` (правило срабатывает, только если найдено хотя бы N подходящих скиллов; 1 = «хоть один»)
- **AC-S4**: Enemy-данные `data/enemies/<id>.json` имеют поля `id, max_hp, team, speed, skills: Array[StringName], behavior_id, fallback_attack_id`. Поле `skills` — список доступных этому врагу навыков (по id). `fallback_attack_id` — что используется если ни одно правило не сработало и враг рядом с целью (для совместимости с текущим manekin).
- **AC-S5**: Skill/Ability получает поле `tags: Array[StringName]`. **Где именно — Q-AI-1.** До решения: тег задаётся на уровне Ability (текущая сущность), при появлении Skill из 007 — переезжает на Skill (с миграцией).

### Условия (`TacticCondition`)

Условия — типизованные, type-специфичные параметры. Все читаются из мира на момент планирования (не закешированы).

- **AC-C1**: `always` — всегда true. Используется как catch-all в конце списка правил.
- **AC-C2**: `self_hp_below(pct: int)` — true если `actor.hp / actor.max_hp * 100 < pct`.
- **AC-C3**: `self_hp_above(pct: int)` — симметрично C2.
- **AC-C4**: `enemy_in_range(distance: int)` — true если хотя бы один противник на гекс-расстоянии ≤ distance.
- **AC-C5**: `no_enemy_in_range(distance: int)` — инверсия C4. Используется ranged-кастером: «никого рядом → продолжай кастовать на дистанции».
- **AC-C6**: `enemy_count_in_range(distance: int, min_count: int)` — true если в радиусе ≥ min_count противников. Триггер для AOE.
- **AC-C7**: `ally_hp_below(pct: int, distance: int)` — есть ли в радиусе союзник c HP ниже %. Триггер для лекарей.
- **AC-C8**: `skill_ready(skill_id: StringName)` — конкретный навык готов (не на cooldown). До интеграции 007 — всегда true.
- **AC-C9**: Композиция: `all_of([...])`, `any_of([...])`, `not(condition)`. Любое условие из C1-C9 может быть вложено. Ограничение глубины — Q-AI-5.

### Селекторы цели (`target_selector`)

Селектор работает в две фазы: (1) фильтр кандидатов, (2) сортировка → берётся первый. Если кандидатов нет — правило не срабатывает (AI идёт к следующему правилу).

- **AC-T1**: `nearest_enemy` — кандидаты: все живые enemies относительно `actor.team`. Сортировка: по гекс-расстоянию ↑.
- **AC-T2**: `lowest_hp_enemy` — кандидаты: enemies в радиусе максимальной дальности доступных скиллов выбранного тега. Сортировка: по hp ↑. («Добивай»)
- **AC-T3**: `highest_hp_enemy` — симметрично T2. («Танкуй боссa».)
- **AC-T4**: `self` — `[actor]`. Для `heal`/`buff`-тегов.
- **AC-T5**: `lowest_hp_ally` — кандидаты: союзники с HP < max_hp. Для лекарей.
- **AC-T6**: `densest_enemy_hex` — гекс с максимальным количеством enemies в зоне area-эффекта. Для AOE-тегов. Требует знание area от Skill (Q-AI-1).
- **AC-T7**: `random_enemy` — равномерный выбор. Для chaotic-сценариев.

### Теги навыков

Список не закрыт — designer добавляет новые в JSON. Стартовый набор для джема:

- **AC-G1**: `damage` — мгновенный урон одиночной цели.
- **AC-G2**: `damage_aoe` — урон по площади.
- **AC-G3**: `control` — стан, обездвиживание, прерывание (статусы — out of scope этой спеки, но тег существует на будущее).
- **AC-G4**: `knockback` — толкает цель.
- **AC-G5**: `heal` — восстанавливает HP союзнику или себе.
- **AC-G6**: `buff` — позитивный статус.
- **AC-G7**: `debuff` — негативный статус.
- **AC-G8**: `summon` — призыв нового актёра.
- **AC-G9**: `mobility` — собственное перемещение (телепорт, рывок).
- **AC-G10**: Скилл может иметь несколько тегов. Соответствие правилу: совпадение хотя бы одного тега из `tag_priority`.

### Сценарии (примеры — реальные данные пишет Stasyan)

Это **примеры**, не часть спеки. Подтверждают, что схемы AC-S* и AC-C/T/G покрывают типовые архетипы.

- **`melee_brute`**: подходит вплотную, бьёт. При HP<30% — отступает к лоухп цели для добивания.
  - rule: `self_hp_above(30) + enemy_in_range(1)` → `[damage, knockback]`, `nearest_enemy`
  - rule: `self_hp_below(30) + enemy_in_range(1)` → `[damage]`, `lowest_hp_enemy`
  - movement: `approach_nearest_enemy`
- **`ranged_caster`**: держит дистанцию, при подходе к нему — отступает с control.
  - rule: `enemy_in_range(1)` → `[control, knockback, mobility]`, `nearest_enemy`
  - rule: `enemy_count_in_range(3, 2)` → `[damage_aoe]`, `densest_enemy_hex`
  - rule: `always` → `[damage]`, `lowest_hp_enemy`
  - movement: `kite_from_nearest_enemy`
- **`support`**: лечит, бафает.
  - rule: `ally_hp_below(50, 3)` → `[heal]`, `lowest_hp_ally`
  - rule: `always + skill_ready(buff_haste)` → `[buff]`, `lowest_hp_ally`
  - rule: `always` → `[debuff, damage]`, `nearest_enemy`
  - movement: `follow_lowest_hp_ally`
- **`debuffer`**: кидает дебафы на разные цели, не танкует.
  - rule: `enemy_in_range(1)` → `[mobility]`, `self`
  - rule: `always` → `[debuff]`, `highest_hp_enemy`
  - rule: `always` → `[damage]`, `nearest_enemy`
  - movement: `kite_from_nearest_enemy`

### Цикл планирования

- **AC-X1**: AI вызывается на каждый `EventBus.world_turn_ended`. Для каждого живого enemy — по очереди (sequential, как сейчас).
- **AC-X2**: Шаг 1 — гейт «может действовать?» (см. AC-G-ACT). Если нет — enemy пропускается (никаких intent на этот ход).
- **AC-X3**: Шаг 2 — выбор действия по сценарию. Алгоритм:
  1. Для каждого правила в `behavior.rules` сверху вниз:
     a. Проверить `condition` против актуального состояния мира.
     b. Если false → следующее правило.
     c. Если true: собрать кандидаты-навыки `actor.skills ∩ behavior.tag_priority`. Сортировать по позиции тега в `tag_priority` (первый тег = высший приоритет). Из этого списка отфильтровать те, у которых `skill_ready` И есть валидная цель по `target_selector`.
     d. Если осталось ≥ `min_skill_count` (по умолчанию 1) → выбираем **первый** (детерминизм для дебага).
     e. Если 0 → следующее правило.
  2. Если ни одно правило не сработало → решение по `movement_policy`: куда идти (или стоять).
  3. Если `movement_policy` тоже не даёт целевого гекса → ход пропускается (`move_intent_coord = (-1,-1)`, `cast_intent = null`).
- **AC-X4**: AI делает **одно** действие за ход — move ИЛИ cast (Pillar §1.5.2, симметрия с player). Кейсы вроде «прибежал и сразу ударил» — Q-AI-2.
- **AC-X5**: Цели выбираются на момент **планирования** (под телеграф). При резолве в следующем тике — перепроверка: цель ещё жива, в радиусе, навык ещё ready. Если нет — действие отменяется (как сейчас «attack missed»).

### Гейт «враг может действовать?» (AC-G-ACT)

Узел в схеме «Враг может действовать?» — точка проверки. На текущей спеке:

- **AC-GACT-1**: false если `not actor.is_alive()`.
- **AC-GACT-2**: false если у актёра нет ни одного навыка (`skills` пуст) И `movement_policy = hold_position` (нечего делать в принципе).
- **AC-GACT-3**: Хуки на статусы (stun, root, paralyze) — out of scope. Когда статусы появятся (отдельная фича) — добавляется AC-GACT-4 «false если в `stun`-статусе» в той же фиче, не в 008.

### Контракт между AI-модулем и контроллером (Pillar 1.5.2 — телеграфы)

AI публикует intent, контроллер исполняет в следующем тике. Существующий протокол расширяется, не ломается.

- **AC-I1**: Поле `move_intent_coord: Vector2i` на Actor — без изменений.
- **AC-I2**: Поле `attack_intent_coord: Vector2i` (текущее) переименовывается / заменяется на `cast_intent: CastIntent` (Resource): `{skill_id: StringName, target_id: StringName, target_coord: Vector2i}`. Старый `attack_intent_coord` остаётся, но deprecated; миграция за этой спекой. Конкретика — в plan.
- **AC-I3**: Контроллер godmode (`_resolve_attack_intent`) расширяется: умеет резолвить любую Ability (не только melee single-target). Дальняя атака, AOE — допускаются на уровне контракта; конкретика анимаций / снарядов — out of scope.
- **AC-I4**: Telegraph аггрегирует урон по hex как сейчас (`predicted_damage_to`). Для не-damage скиллов телеграф показывает hex с пометкой типа эффекта (heal / control / debuff) — **только семантика в данных**, визуальная иконка/цвет — отдельная UX-фича (Q-AI-4).

### Acceptance scenarios (тесты)

1. **Backward-compat.** Manekin без `behavior_id` (как сейчас) ведёт себя ровно как до 008: подходит к игроку, бьёт. Pillar — не сломан.
2. **Melee brute с лоу-хп переключением.** Враг с `behavior_id=melee_brute`, hp=10/100, рядом игрок hp=20 и манекен hp=5. Сработает rule «self_hp_below(30)» → `lowest_hp_enemy` → выберет манекена (5<20).
3. **Ranged caster держит дистанцию.** Враг `ranged_caster`, игрок на расстоянии 1. Rule `enemy_in_range(1)` → `[control, mobility]` → если `control`-скилл готов и в радиусе игрок → каст control. Если оба нет — следующее правило.
4. **AOE-триггер.** Враг `ranged_caster`, в радиусе 3 игрок и 2 союзника игрока (= 3 enemies для каста). Rule `enemy_count_in_range(3, 2)` → `damage_aoe` → `densest_enemy_hex`. Гекс с максимумом целей выбран.
5. **Support-лекарь.** Враг `support`, рядом союзник hp=20/100. Rule `ally_hp_below(50, 3)` → `heal` → `lowest_hp_ally`. Союзник вылечен.
6. **Каскад правил.** `support` без задетого ally_hp и без `buff_haste` (на CD). Падает в третье правило (`always → debuff/damage on nearest`).
7. **Skill-ready гейтинг (после 007).** Рулу `[heal]` нужен `skill_ready(small_heal)`; small_heal на cooldown → правило пропускается, идём к следующему.
8. **Move OR cast — не оба.** AI выбрал `damage` на цели вне радиуса каста: правило не срабатывает (нет валидной цели), последующее правило/политика — `approach_nearest_enemy` → move. В тот же ход cast не происходит.
9. **Detalled telegraph для non-damage.** Heal-каст на союзника: hex союзника помечен как «heal-intent» (семантика — `cast_intent.skill_id`, тег `heal`). Игрок видит **что** случится, не только **кто** получит.
10. **Гейт actor-can-act.** Враг `skills=[]` и `movement_policy=hold_position` → пропускается, intent чистый, телеграф пустой.

## Out of scope

- **Cooldown-движок.** Зависим от 007. До его merge `skill_ready` всегда true. После 007 — меняется одна функция в AI-модуле, не схема правил.
- **Status effects** (stun, root, silence). Тег `control` существует, но что он *делает* — отдельная фича. AI-гейт «может действовать» статусы пока не учитывает.
- **Объекты как цели/препятствия** (ящики, колонны — спека 007 их вводит как future entity). На 008 актёры only. Когда 007 даст `Object`, AI-target расширяется в **отдельном** PR без переписи правил.
- **AI-редактор сценариев** (UI или DSL). Сценарии — голый JSON, designer редактирует руками.
- **Group / squad behaviors** (фланкинг, focus fire по приказу лидера, формации). Каждый враг планирует независимо. Если в джеме хочется — отдельная фича поверх.
- **Path heuristics за пределами текущего find_path_around.** «Спрятаться за стенку», «занять high ground» — после джема.
- **Конкретные значения балансa** (какой % HP у melee_brute триггерит retreat, какие скиллы у ranged_caster). Stasyan наполняет JSON в `data/ai_behaviors/` и `data/enemies/` уже после движка.
- **Анимации, VFX, звук, голосовые реакции AI** на действия. Pillar §1.5.1 требует только **визуальную** инфу (telegraph, icon-on-hex для не-damage). Звук/VFX — отдельный polish.
- **Save/load AI state** (накопленные cooldown-таймеры, persistent intent между сейвами). Игра не саевится в джеме.
- **Migration of `attack_intent_coord` → `cast_intent`** code-wise — расписывается в plan.md; здесь спека только фиксирует, что новый контракт нужен.
- **PR-координация с 007 на тему tags** (на Skill или на Ability) — открытый вопрос Q-AI-1, обсуждается в чате до /plan.

## Открытые вопросы (закрыть до /plan)

- **Q-AI-1 (где живут теги).** Spec-007 вводит Skill (надстройка над массивом Ability). Тег — атрибут чего:
  - (a) `Ability.tags` (текущая сущность). Skill наследует объединение тегов своих Ability.
  - (b) `Skill.tags`, отдельно от Ability. AI оперирует Skill-уровнем; Ability-теги не существуют.
  - (c) Оба: `Skill.tags` (declared by designer), Ability.tags не существует.
  Влияние: data layout, target selector AC-T6 (densest_enemy_hex требует area — Skill-уровень).
  **Координация:** Egor (007). Решить совместным голосованием, не в одиночку.

- **Q-AI-2 (move + cast в один ход).** Pillar §1.5.2 (симметрия с player) → один action в ход. Текущий AI это соблюдает. Хотим ли исключение для конкретных behaviors («charger» = move до цели + удар, как Dragon Age «charge»)?
  - (a) Нет, никогда (default — самое простое и симметричное).
  - (b) Да, через специальный movement_policy или специальное правило `move_then_cast`.
  - (c) Да, но только если у игрока есть аналогичная механика (тогда симметрия не нарушается).

- **Q-AI-3 (tiebreak в правиле).** Когда несколько скиллов с одинаковым приоритетом тегов и валидной целью, кого выбрать?
  - (a) Первый по порядку в `actor.skills` (детерминизм, стабильно для дебага).
  - (b) Случайный (variability, но debug сложнее).
  - (c) С наибольшим predicted damage / predicted heal (AC-T2-стиль).

- **Q-AI-4 (визуал телеграфа для не-damage).** AC-I4 фиксирует, что семантика в данных есть. Но иконка/цвет на hex для heal/control/debuff — на этой спеке или отдельной?
  - (a) В этой (надо до плейтеста, иначе игрок не понимает что AI делает).
  - (b) В отдельной UX-полировке (после движка).
  - (c) Минимум на этой: разный цвет hex (зелёный = heal на ally, фиолетовый = control, оранжевый = damage). Без иконок.

- **Q-AI-5 (глубина композиции условий).** AC-C9 не задаёт лимит вложенности `all_of/any_of/not`. Простая реализация — поддержать ровно 1 уровень (один `all_of` на правило, не вложенный). Сложная — рекурсивная (любая глубина). Что берём?
  - (a) 1 уровень. Достаточно для всех примеров в спеке.
  - (b) Рекурсия. Сложнее парсер JSON, но designer-friendly.

- **Q-AI-6 (fallback при пустых правилах).** Если все правила не сработали И `movement_policy` тоже не даёт цели (например, нет ни одного enemy на карте) — что делать?
  - (a) `hold_position` молча (текущий поведенческий дефолт «стоять»).
  - (b) Лог `[INFO][AI] %s: no action this turn`, hold_position.
  - (c) Random walk на 1 гекс (chaotic, но «жизнь на карте»).

## Заметки реализации (для будущей plan.md)

- AI-модуль = отдельный namespace `scripts/core/ai/`. Не трогать `core/abilities/` и `core/actors/` (только дорасширить Actor нужными полями `behavior_id`, `skills`, `cast_intent`).
- `EnemyAIPlanner` — статический хелпер или Resource? Оба варианта рабочие; выбрать в plan по симметрии с `AbilityDatabase` (autoload, статический API).
- Контракт с `godmode_controller`: `_plan_intents` исчезает, заменяется на `EnemyAIPlanner.plan(actor, world_ctx)` → пишет на актёра `move_intent_coord` и `cast_intent`. `_resolve_*_intent` остаются как **executor**, дополняются генерализацией под Skill/Ability разных типов.
- Backward-compat: Actor без `behavior_id` получает дефолтный `default_melee` сценарий — точную схему которого я лично пишу в `data/ai_behaviors/default_melee.json` так, чтобы поведение бит-в-бит совпало с текущим manekin AI. Тест #1 в Acceptance scenarios это проверяет.
- Перед закрытием спеки: смешанный playtest — `data/enemies/` минимум на 4 архетипа (melee_brute, ranged_caster, support, debuffer), Stasyan тюнит, я не лезу в баланс.
