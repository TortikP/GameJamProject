# 044-summoned-entity-ai — spec

**Owner:** Egor (AI module + telegraph filter, JSON content for default scenarios).
**Coordination:** Stasyan — `default_range.json` → `default_ranged.json` rename + summon rule are partly designer-facing; этот PR делает renaming + minimal summon rule, дальнейшая балансировка приоритетов и условий — Стасяна.
**Status:** Draft (clarify-round пройден с Egor: вариант (b) — добавляем правило в `default_melee` И переименовываем `default_range.json` → `default_ranged.json`).

**Upstream:**
- 008-enemy-ai (merged) — `EnemyAIPlanner`, `BehaviorScenario`, TacticRule pipeline.
- 030-enemy-ai-smart-targeting (merged) — intent-aware планирование, `unclaimed_hex_near_enemy` selector (template, не reuse).
- 041-effect-create-entity (merged) — `CreateEffect.apply` копирует `caster.team` на спавненного актёра + `summoned(d)` статус. Без 041 нет настоящих player-side призванных существ.

## Цель

После 041 player'у доступен `summon_bee` (и любые будущие `summon_*` навыки). Призванный actor получает `team = caster.team` (= `&"player"` если кастует игрок). **Текущий AI driver ignore'ит таких актёров** — фильтр `team == &"enemy"` в `ai_driver.gd:50,122` и `telegraph_renderer.gd:81`. Pillar 2 (симметрия) ломается: player-team призванный bee не двигается, не атакует, не пишет cast_intent — статуя.

Помимо driver-фикса — создатели саммон-юнитов (bee, burning_bear) должны **приоритизировать summon-скилл над любым другим действием** и спавнить **как можно ближе к ближайшему врагу**.

## Scope-граница

**В скоупе:**

1. **Driver-фильтр** — `ai_driver.gd._run_enemy_turn()` и `replan_all_and_refresh()` итерируют любого `Actor`-а кроме `_ctrl.player`, не только `team == &"enemy"`. Pillar 2 / симметрия: AI планирует за всех не-человеко-управляемых актёров.
2. **Telegraph-фильтр** — `telegraph_renderer.gd:refresh()` рендерит cast_intent / move_intent для всех актёров кроме `_ctrl.player`. Pillar 1 / full information: игрок видит, что собирается сделать его призванная пчела.
3. **Новый selector `nearest_empty_hex_to_enemy`** — для саммон-правил. BFS-кольцами от ближайшего враждебного актёра, возвращает первый walkable hex без актёра/tile-object'а в пределах `skill.range` от кастера, не попавший в claimed-cells союзников.
4. **Правило top-priority `summon`** в `default_melee.json` и в новом `default_ranged.json` — единое: condition `always`, selector `nearest_empty_hex_to_enemy`, tag_priority `["summon"]`, `min_skill_count: 1`.
5. **Rename `default_range.json` → `default_ranged.json`** — на staging 3 врага (`angel`, `bear`, `burning_bear`) ссылаются на `behavior_id: "default_ranged"`, а файла нет (опечатка Стасяна). Переименование консолидирует ссылки. Фолбек на `default_melee` через `EnemyAIPlanner.DEFAULT_BEHAVIOR` сейчас маскирует баг — после rename'а они начнут реально использовать ranged-сценарий, и summon-rule в этом же файле даст burning_bear саммон.

**Out of scope:**

- **`default_caster.json`** — отсутствует на staging (bush, teapot ссылаются), но не саммонеры → не моя зона. Стасян / Андрей.
- **Различение визуала телеграфов player-team vs enemy-team** — цвета по тегу скилла одинаковые. Player-bee'ин «damage»-телеграф выглядит как enemy-bee'ин. Допустимо для джема (актёр на origin-хексе + наведение раскроют принадлежность). Если позже окажется проблемой — отдельный спек, возможно через расширение `UiTheme.semantic_color`.
- **Цепные саммоны / экспоненциал** — `bee(-1)` + cooldown=4 на `bee_summon_bee` → каждые 4 хода каждый bee саммонит. Принято фичей в 041 §"Out of scope". Балансировка через cooldown / `ally_count_below(N)` condition — Стасяна, отдельным PR при необходимости.
- **Новый dedicated `summoner_*` сценарий** — обсуждалось в clarify-round, отказались: rules внутри `default_melee` / `default_ranged` достаточно. Не множим scenario-инвентарь.
- **Ally-aware саммон-таргетинг** (выбирать hex который ещё и блокирует наступление врага / прикрывает союзника / etc.) — overengineering на этом этапе. Селектор только «empty + closest to enemy».
- **`replan_all_and_refresh`** при появлении player-summoned (после `summon_bee` каста) — текущий поток уже вызывает планнер на следующем `world_turn_ended` перед фазой PLAN. Один ход задержки до первого действия призванного — приемлемо, даёт игроку «чтение интента» как у обычных enemy.
- **Поведение когда призванный — единственный actor своей team'ы** (например, player умер, bee осталась) — bee продолжает работать через симметричную логику (она ищет любого `team != &"player"` как врага). Дополнительной обработки death-сценария игрока в этом спеке не делаем.
- **UI-маркер «союзник»** на overhead actor info — presentation polish, отдельный спек если нужно.

## Acceptance criteria

### Driver-фильтр

- **AC-D1**: `ai_driver._run_enemy_turn()` итерирует `registry.all()` и берёт в работу любого `Actor`'а удовлетворяющего `(actor != _ctrl.player) and actor.is_alive()`. `team`-чек удалён.
- **AC-D2**: Аналогично — `ai_driver.replan_all_and_refresh()`.
- **AC-D3**: Имена `_run_enemy_turn` / комментарии «enemy turn» сохраняются (минимизируем diff). Внутри — обновлённые комменты «AI-controlled actors» где это смыслово важно.
- **AC-D4**: `_tick_all_statuses` / `_tick_all_skills` — без изменений (они уже итерируют `registry.all()`).
- **AC-D5**: Игрок (`_ctrl.player`) никогда не попадает в loop — его cast_intent не пишется AI'ем, его move_intent_coord не пишется AI'ем.

### Telegraph-фильтр

- **AC-T1**: `telegraph_renderer.refresh()` рендерит intent-телеграф и intent-стрелку для любого `Actor`-а удовлетворяющего `(actor != _ctrl.player) and actor.is_alive()`.
- **AC-T2**: Цветовая схема — без изменений (по `tag_for_skill()` маппингу). Player-bee и enemy-bee рисуют одинаковый «damage»-цвет.
- **AC-T3**: Стрелка движения player-summoned пчелы видна игроку до того, как мир провернётся.

### Новый selector — `nearest_empty_hex_to_enemy`

- **AC-S1**: `SelectorNearestEmptyHexToEnemy extends TargetSelector`, реализована в `scripts/core/ai/selectors/selector_nearest_empty_hex_to_enemy.gd`. Зарегистрирована в `BehaviorDatabase._build_selector` под ключом `"nearest_empty_hex_to_enemy"`.
- **AC-S2**: Возвращает `Vector2i` или `null`. Возвращает `null` при:
  - `ctx.grid == null` или `ctx.candidate_skill == null` или `skill.abilities.is_empty()`.
  - Первая ability не `HexTarget` (saммон-скиллы все hex-targeted, симметрично `unclaimed_hex_near_enemy`).
  - Нет ни одного живого враждебного (opposing-team) актёра в `candidates`.
  - Не нашёлся подходящий hex в обозримых кольцах (см. AC-S5).
- **AC-S3**: Поиск идёт BFS-кольцами от координаты ближайшего opposing-team актёра (= минимум `grid.hex_distance(my_coord, enemy_coord)` среди живых candidates). При равенстве distance — детерминистический tiebreak: первый по порядку в `candidates` (источником порядка является `ctx.all_actors` снимок, который определяется `ActorRegistry.all()` — порядок регистрации).
- **AC-S4**: Hex считается «подходящим», если **все** условия:
  - `grid.is_walkable(hex)` (`grid.get_walkable_neighbours` уже фильтрует, плюс ring=0 hex проверяется отдельно).
  - `grid.get_actor_at(hex) == &""` — нет актёра. (CreateEffect всё равно skip'нет, но мы фильтруем заранее, чтобы саммон-rule не съедало ход вхолостую.)
  - `grid.get_tile_object_id(hex) == &""` — нет tile-object'а (CreateEffect для actor-spawn'а не блокируется tile-object'ом, но логически ставить пчелу на лава-тайл / препятствие нерационально). Если позже окажется что нужно — снять.
  - Hex ≤ `skill.abilities[0].target.range` от `actor`'а (= кастера). Если `range == -1` → unbounded, проверка снимается.
  - Hex ∉ `claimed` — там, где `claimed` это все `cast_intent.target_coord` живых same-team союзников с `cast_intent != null and cast_intent.is_valid()`.
- **AC-S5**: Расширение колец — до тех пор, пока не найдётся hex или пока кольцо не охватит всю grid. Лимит безопасности: `MAX_RING = 32`. На стандартной арене (~10×10) этого достаточно с большим запасом; лимит — защита от бесконечного цикла на патологических картах.
- **AC-S6**: Если несколько hex'ов в одном кольце удовлетворяют — выбирается ближайший к **кастеру** (не к врагу — в кольце все hex'ы равноудалены от врага, но не от кастера). Tiebreak — детерминистичный порядок BFS-обхода.
- **AC-S7**: Селектор не использует `ctx.behavior_target_id` (это feared/enraged-сценарии, не наш кейс).

### JSON: scenarios

- **AC-J1**: `data/ai_behaviors/default_melee.json` — добавлено новое **первое** правило в `rules`:
  ```json
  {
    "condition": { "kind": "always" },
    "target_selector": { "kind": "nearest_empty_hex_to_enemy" },
    "tag_priority": ["summon"],
    "min_skill_count": 1
  }
  ```
  Существующее `damage`/`melee`-правило остаётся вторым. `movement_policy` без изменений.

- **AC-J2**: `data/ai_behaviors/default_range.json` **переименован** в `default_ranged.json`. `id` внутри — `"default_ranged"`. Контент = старый `default_range` + такое же top-priority summon-правило, добавленное **первым** в `rules`. `movement_policy` (`maintain_range`) без изменений.

- **AC-J3**: Никаких изменений в `data/enemies/*.json` — они уже ссылаются на `"default_ranged"` (это и был драйвер ренейма). После rename'а bear / angel / burning_bear перестают фолбечиться на `default_melee`.

- **AC-J4**: `data/ai_behaviors/default_range.json` после операции отсутствует. Никаких stale-ссылок на `"default_range"` в `data/enemies/*.json` (проверено grep'ом).

### Поведенческие AC (smoke)

- **AC-B1**: Игрок на godmode-сцене кастует `summon_bee` на пустой hex в радиусе 3 → бочка с `team=player` с behavior_id=default_melee появляется. Через 1 world_turn_ended bee получает планируемый intent (cast_intent + telegraph + arrow видны). На следующем world_turn_ended bee исполняет план: либо саммонит ещё bee (если `bee_summon_bee` ready и есть пустой hex рядом с врагом), либо движется к врагу + жалит.
- **AC-B2**: Пустая арена (нет врагов вообще): саммон-правило fizzles (selector → null), bee переходит к damage-правилу (тоже null target), движется в hold (нет anchor). Эквивалент enemy-стороны без целей.
- **AC-B3**: Все hex'ы вокруг ближайшего врага заняты другими актёрами / ally cast_intent'ами → selector расширяет кольца до первого свободного. Если в `MAX_RING` ничего → null → правило fizzles → следующее правило (damage) пробует.
- **AC-B4**: На enemy-стороне — burning_bear с `default_ranged` после rename'а: правило 1 (summon) пробует через `nearest_empty_hex_to_enemy` (range=-1 → unbounded), bear-юнит спавнится. Правило 2 (damage/ranged/debuff) — fallback если summon-skill на cooldown.
- **AC-B5**: На enemy-стороне — bee с `default_melee`: правило 1 (summon) пробует, range=3 ограничивает. Если все хексы в радиусе 3 от bee'и не подходят → fizzles → правило 2 (melee/damage). Симметрично с тем, как player-bee работает.
- **AC-B6**: Player-bee и enemy-bee на одной арене: bee'и взаимно враги (`other.team != my.team`). Player-bee саммонит вне ring'а enemy-bee'и, enemy-bee саммонит вне ring'а player-bee'и. Никаких краш'ев / null-deref'ов. Симметричное поведение.

## Test plan

Smoke (godmode):
1. Загрузить scene `godmode_main` (или эквивалент с player + ManekinSpawner).
2. Заспавнить через ManekinSpawner врага рядом.
3. Кастануть `summon_bee` на пустой hex. Проверить — bee появилась с правильным цветом team-маркера (если есть; см. out of scope), HP-bar читается.
4. Завершить ход. Watch: bee'и intent отрисован, она движется к врагу / атакует.
5. Заспавнить ещё врагов. Проверить chained behavior на 4-5 ходах. Watch logs на `CreateEffect` / `AI` / `BehaviorDatabase` — нет warn'ов после 1 ready-фразы старта.

Smoke (enemy summoner — burning_bear через level / wave):
1. Запустить wave с burning_bear.
2. Watch: на первом турне bear использует `burning_bear_summon_bear` (в пределах cooldown=5), тот спавнится в кольце 1 от player'а. Если кольцо 1 занято — кольцо 2.
3. Watch: после спавна bear'a продолжается ranged-фолбек.

Edge cases:
- Player умирает первым ходом (от вражеского заранее планируемого cast'а). Player-bee остаётся жива → её AI всё ещё работает (AI-loop не пропускает её, она не зависит от player's existence для своего планирования). Ожидаемо: bee продолжает атаковать врагов (при их наличии). Win/lose check у game loop'а — не наша зона.
- Все player-summoned'ов > всех enemy-team'ов: enemy-side AI fizzles на target-less rule'ах, держит. Корректно.

## Risks

- **Производительность BFS**: на 32-кольцах в худшем случае ~1+6+12+...+32×6 ≈ 3000 ячеек на selector-call. На 4-х саммонеров за ход × 32 кольца — впритык, но допустимо. Реальные карты ~10×10 → 1-2 кольца на 99% случаев.
- **Player-bee'и infinite duration**: со временем накопится много bees → telegraph-spam. Мониторить на playtest'ах. Если визуальный шум критичен — отдельный hotfix урезает визуал (например, только адресный telegraph без area-shape для союзников).
- **Confusion**: одинаковый цвет телеграфа player-side и enemy-side создаёт читаемость-проблему при большом скоплении. Out of scope, но flag.
- **Rename `default_range.json` → `default_ranged.json`**: на других ветках кто-то может ссылаться на старое имя. На staging — нет (grep чист). На активных feature-ветках (`andrey/043-intro-cutscene` и т.п.) — после мёрджа 044 → conflict только если кто-то трогал `data/ai_behaviors/`. Низкий риск.

## Success criteria

- Player-кастуемый `summon_bee` приводит к появлению живого AI-управляемого союзника, который через 1 ход начинает действовать против врагов.
- В тех же скиллах enemy-side `burning_bear` и `bee` приоритизируют свой саммон-навык, спавн происходит около ближайшего враждебного актёра (= игрока для enemy-side, = ближайшего enemy-team'а для player-side).
- Никаких crash / null-deref / log-spam на 100-турновом playtest'е.
- Diff в коде ≤ 100 строк (driver: ~6, renderer: ~3, новый selector: ~70, BehaviorDatabase: 1 строка). JSON: 2 файла.
