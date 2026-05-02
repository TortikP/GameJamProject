# 027-status-effects — spec

**Owner:** Egor
**Status:** Ready for /plan (clarify-цикл закрыт в чате 02.05)
**Upstream:** 007-skill-system, 011-skill-tags, 021-skill-system-v2, 026-skill-system-v3

## Цель

Реальный рантайм статус-эффектов поверх stub'а из 026 + новая инлайн-кодировка
аргументов статуса в JSON.

1. **`AbilityEffect.duration` упраздняется как общее поле.** Длительность —
   свойство статуса, а не любого эффекта. Damage/heal/move/create инстантны
   уже сегодня (DoT/HoT-стабы в комментариях не реализованы).
2. **Новый формат `status` в JSON:** `"status_id(arg0, arg1, ...)"`, где
   первый аргумент всегда `duration: int`, остальные — per-status. Парсер
   разворачивает в `StatusEffect` с массивом аргументов; runtime-класс
   статуса знает свою арность.
3. **9 статусов** с поведением рантайма (1 stub, см. ниже).
4. **Re-apply семантика**: один инстанс на пару `(target, status_id)`.
   Повторное применение полностью заменяет старый инстанс (новый duration,
   новые args, новый source). Никаких stack'ов, refresh'ей, additivity.
5. **Tick** статусов — на `EventBus.world_turn_ended` для всех `Actor`'ов
   симметрично (player + AI). DoT-урон применяется через стандартный
   `Actor.take_damage` → существующий канал floating-numbers / damage-dealt
   подхватывает без правок.
6. **Видимость над actor'ом** — `StatusIconStrip` (UI-kit, уже есть)
   инстансится как ребёнок каждого Actor-сцены, рядом с `HealthBar`.
   Подписывается на новый сигнал `Actor.statuses_changed`.

## Контракт статусов

Формат значения в JSON: `"status_id(d, a1, a2, ...)"`. Все аргументы — целые.
Пробелы вокруг запятых допускаются и съедаются парсером.

| status_id | формат | поведение |
|---|---|---|
| `stunned`  | `stunned(d)` | носитель не планирует ход: ни move, ни cast. См. §"Stunned UX". |
| `slowed`   | `slowed(d)` | `effective_speed = floor(speed / 2)`, минимум 0. Не скейлится от lvl. Для AI, у которой `policy_step = 1 hex/turn` независимо от speed — флип-флоп: статус хранит `_skip_next_move: bool`, на каждый tick тогглит, на `true` policy не emit'ит `move_intent_coord`. |
| `poisoned` | `poisoned(d, dmg_pct, lvl_bonus_pct)` | в начале хода: `take_damage(floor(max_hp * (dmg_pct + level * lvl_bonus_pct) / 100))`. `level` = `Skill.level` на момент каста, snapshot'ится в `StatusInstance` (caster может выйти из боя или измениться). |
| `rooted`   | `rooted(d)` | `effective_speed = 0`. AI policy не emit'ит `move_intent_coord`. Кастеры (`cast_intent`) не блокируются. |
| `feared`   | `feared(d)` | **На player'е — статус хранится, runtime no-op** (вариант C из чата). **На AI:** на `add_status` swap'ит `actor.behavior_id` → `&"feared"` (новый сценарий с `policy_kite_specific_actor`); source прокидывается AI-планировщику через ctx-ключ `behavior_target_id`. На `remove_status` (или expire) — restore оригинального `behavior_id`. Если source мёртв на tick — статус expire'ит, что revert'ит behavior. Tactic rules сценария — пустые: feared не атакует. |
| `burning`  | `burning(d, dmg, lvl_bonus)` | в начале хода: `take_damage(dmg + level * lvl_bonus)`. Аналогично poisoned по snapshot'у `level`. |
| `glitched` | `glitched(d)` | **STUB.** Runtime — пустой класс. Хранится, тикает duration, отображается иконкой. Поведение — отдельной фичей. |
| `shielded` | `shielded(d, n_block, lvl_bonus)` | при вызове `take_damage(amount)` на target'е урон уменьшается на `n_block + level * lvl_bonus` (до min 0). Не consume'ится, не decrement'ится от удара — только от tick'а duration. |
| `enraged`  | `enraged(d)` | **На player'е — статус хранится, runtime no-op**. **На AI:** на `add_status` swap'ит `actor.behavior_id` → `&"enraged"` (сценарий: `policy_approach_specific_actor` + один rule с `selector_specific_actor`, `tag_priority: ["damage"]`). Source — через ctx `behavior_target_id`. AI бежит к source и при наличии damage-скилла в range атакует его, игнорируя других врагов. На expire — restore. Source мёртв на tick → expire. |
| `strong`   | `strong(d, n_buff, lvl_bonus)` | Увеличивает весь исходящий урон актера на `n_buff + level * lvl_bonus`. Сложение с `weak` алгебраическое. Не consume'ится от удара. snapshot складывается с `caster.damage_bonus` в `DamageEffect.apply` и `Ability.predicted_damage_to`. |
| `weak`     | `weak(d, n_debuff, lvl_bonus)` | Симметричен strong с обратным знаком. Финальный урон clamp'ится к 0 (через существующий `maxi(0, ...)` в DamageEffect). |

### Behavior-override mutual exclusivity

`feared` и `enraged` оба swap'ят `actor.behavior_id`. На один Actor может быть
наложен только один из них одновременно — применение одного **полностью
удаляет** инстанс другого (даже если у того ещё есть duration). Это
позволяет хранить ровно один `_original_behavior_id` slot на Actor'е и
избежать вложенной семантики восстановления при пересечении эффектов.
Other status-id (poisoned, burning, etc.) с feared/enraged не конфликтуют.

**Snapshot levels.** `poisoned`, `burning`, `shielded` пересчитывают свой эффективный
числовой параметр в момент каста (`level` берётся с `Skill.level`) и сохраняют его
в `StatusInstance.snapshot_value: int` — runtime затем читает только snapshot.
Это снимает зависимость от живости / level-ап'а кастера после каста.

## Изменения схемы

### AbilityEffect (база)

```gdscript
class_name AbilityEffect extends Resource
@export var requires_alive_target: bool = true
# duration — УДАЛЁН
```

`duration` пропадает целиком. Уезжает в `StatusEffect` как часть парсинга
строки. Все 4 концrete-effect'а (`DamageEffect`, `HealEffect`, `MoveEffect`,
`CreateEffect`) теряют поле `duration` (которое и так нигде не читалось вне
StatusEffect и no-op-скейлинга в MoveEffect.apply_level).

### StatusEffect (новая форма)

```gdscript
class_name StatusEffect extends AbilityEffect
@export var status_id: StringName = &""
@export var args: Array[int] = []   # [duration, ...rest]
```

Парсер `AbilityDatabase._make_effects_from_dict` на ключе `"status"` берёт
строковое значение, прогоняет через `_parse_status_string()` →
`{id: StringName, args: Array[int]}`. На invalid строке (нет `(`, не int,
unknown id) — `GameLogger.warn`, инстанс не создаётся.

`StatusEffect.apply()`:
```
1. cast target → Actor; bail если null
2. args.is_empty() → warn, return
3. duration = args[0]; bail если duration <= 0
4. registry-lookup runtime-класса по status_id
5. инстанцировать StatusInstance(status_id, args, caster.actor_id, snapshot_value=runtime.compute_snapshot(args, ctx.skill_level))
6. actor.add_status(instance) — заменит существующий с тем же id
```

### Effect JSON — было/стало

Было (026):
```json
{"duration": 2, "status": "burning"}
```

Стало:
```json
{"status": "burning(2, 3, 1)"}
```

Multi-key объект, было:
```json
{"duration": 1, "damage": 8, "status": "burning"}
```

Стало:
```json
{"damage": 8, "status": "burning(1, 2, 1)"}
```

Hard rename, без шима — как 021/026. Все production+test JSON мигрируются
in-place в этой же фиче.

### Status registry

Папка `data/status_effects/<id>.json` — один файл на статус для
designer-side метаданных:

```json
{
  "id": "poisoned",
  "family": "dot",
  "icon": "",
  "arity": 3,
  "param_names": ["duration", "damage_pct", "lvl_bonus_pct"],
  "loc_name": "status.poisoned.name",
  "loc_desc": "status.poisoned.desc"
}
```

`family` — для UI-pill цвета (`buff` / `debuff` / `dot` / `hot` / `control` /
`shield`), уже определены в `status_icon_strip._ICON_BY_FAMILY`.

`icon` — путь к Texture2D (например `"res://assets/icons/status/poisoned.png"`)
или пустая строка. Если задан и ресурс существует, pill рендерит его как
`TextureRect`. Иначе fallback — unicode-glyph по `family`. Дизайнер может
точечно переопределить иконку без замены family.

`arity` и `param_names` — для парсера: warn если кол-во аргументов в строке
не сходится с arity. `loc_*` — стабы под локализацию (как у Skill).

Runtime-классы статусов — код в `scripts/core/statuses/runtimes/`. Один
класс на статус, владеет ПОВЕДЕНИЕМ (compute_snapshot, on_turn_start,
modify_speed, …). JSON владеет МЕТАДАННЫМИ (family, arity, loc keys) —
дизайнер тюнит без правок кода.

`StatusRegistry` (autoload) — две таблицы: `_RT_BY_ID` (preload) →
`runtime_for(id) -> GDScript`, `_meta` (loaded from JSON) →
`family_of(id) / arity_of(id) / meta_for(id)`. **Регистрируется ДО
AbilityDatabase в project.godot** — парсер skill'ов вызывает arity_of
синхронно при загрузке.

### Actor — новая поверхность

```gdscript
signal statuses_changed(actor_id: StringName)

var _statuses: Dictionary = {}   # StringName status_id -> StatusInstance
                                 # Dictionary не Array — обход CLAUDE trap #6
                                 # (Array[Resource] capricious с подклассами)

func add_status(instance: StatusInstance) -> void
func remove_status(id: StringName) -> void
func get_statuses() -> Array              # Array[StatusInstance], для UI
func has_status(id: StringName) -> bool
func is_stunned() -> bool                 # удобный шорткат
func effective_speed() -> int             # учитывает rooted/slowed
func tick_statuses() -> void              # вызывается контроллером per turn
func damage_reduction() -> int            # сумма shielded snapshot_value
```

`take_damage(amount)` правится: `amount = maxi(0, amount - damage_reduction())`
до текущей логики. Heal не модифицируется.

### StatusInstance

Простой data-resource:
```gdscript
class_name StatusInstance extends Resource
@export var status_id: StringName
@export var duration: int                 # decrements per tick
@export var args: Array[int]              # raw args [duration, ...]
@export var source_id: StringName         # actor_id of caster, &"" if none
@export var snapshot_value: int           # pre-computed scaling result
```

Runtime-класс получает StatusInstance + Actor + ctx и применяет поведение.

## Tick flow

`world_turn_ended(turn: int)` — текущий путь:
- godmode_controller подписан, вызывает `_run_enemy_turn()`.

После 027:
- godmode_controller в начале `_on_world_turn_ended`, ДО `_run_enemy_turn`,
  вызывает `_tick_all_statuses()` — обходит `actor_registry.all()`,
  для каждого живого actor'а: `actor.tick_statuses()`.
- `Actor.tick_statuses()`:
  1. собирает упорядоченный список инстансов (стабильный порядок: insertion order Dictionary'я).
  2. для каждого: `runtime.on_turn_start(actor, instance)` — DoT-урон, source-validity check для feared/enraged, etc. Может expire'нуть инстанс.
  3. `instance.duration -= 1`; если `duration <= 0` — пометить на удаление.
  4. в конце цикла — удалить помеченные, emit `statuses_changed(actor_id)`.

**Player skip при stunned.** В `godmode_controller._tick_all_statuses` после
тика: если `player.is_stunned()` — вызвать `TurnManager.advance()` через
`GameSpeed.wait("arena", "stun_skip_delay", 0.4)` (новый ключ в
`game_speed.cfg`), чтобы у игрока было видно «pill глитчнул, ход
пропустился». Без delay — мгновенный flip двух turn'ов выглядит как фриз.
Player UI слоты на этом «ходу» — все greyed (см. AC-UI).

## Status visibility (StatusIconStrip над actor'ом)

Цель: каждый Actor на сцене несёт инстанс существующего
`scenes/ui/status_icon_strip.tscn` как ребёнка, размещённый над
`HealthBar`'ом (offset `Vector2(0, -BAR_HEIGHT - SP_2)` от спрайта).
Виджет уже умеет `set_statuses(entries)` — мы дополняем `bind_actor`
реальной подпиской на `actor.statuses_changed`.

Изменения:
1. `StatusIconStrip.bind_actor`:
   - подписаться на `actor.statuses_changed` → `_rebuild`
   - `_rebuild()` собирает entries из `actor.get_statuses()`, маппит
     через StatusRegistry → `{id, family, duration}`, дёргает существующий
     `set_statuses`.
2. `scenes/dev/player.tscn` и `scenes/dev/manekin.tscn` — добавить
   instance `StatusIconStrip` рядом с `HealthBar`.
3. `Actor._ready` (или соответствующий subclass) — найти `$StatusIconStrip`
   и вызвать `bind_actor(self)`. Если нет — log info, не warn (статус-strip
   опционален: dev-сценам, ботам, тестовым actor'ам он может быть не нужен).

Размер pill'ов и шрифты — как сейчас в виджете (UiTheme constants), без
правок. Иконки на этой итерации — placeholder unicode-glyphs из существующей
`_ICON_BY_FAMILY`. Спрайты Кати — отдельный downstream.

## Stunned UX

- AI: `enemy_ai_planner.plan` в самом верху — `if actor.is_stunned(): return`.
  `move_intent_coord = (-1,-1)`, `cast_intent = null` — actor не делает
  ничего на этом тике.
- Player: `godmode_controller` после тика статусов проверяет
  `player.is_stunned()`. Если да — Q/W/E/R входы блокируются (slot greyed,
  визуально как cooldown), движение блокируется, через `stun_skip_delay`
  → `TurnManager.advance()`.
- Видимость — pill `stunned` над аватаром игрока. Этого достаточно по
  pillar 1: игрок видит иконку → понимает почему ход скипнулся.
  Дополнительный floating-text «Stunned!» — out of scope.

## Migration

Все production+test JSON в `data/skills/` — миграция формата effects.

| Файл | Изменение |
|---|---|
| `skill_debug_punch.json`, `skill_melee_punch.json`, `skill_manekin_attack.json`, `skill_knockback_punch.json`, `test_area_strike.json`, `test_chain_lightning.json`, `test_combo_actor_chain_damage.json`, `test_combo_actor_chain_move.json`, `test_combo_hex_circle_create.json`, `test_combo_self_self_heal.json`, `test_level_scaling.json`, `test_target_area_strike.json`, `test_vamp_strike.json` | Удалить ключ `"duration"` из всех effect-объектов (везде он был `0`, no-op). |
| `test_combo_hex_circle_damage_status.json` | `{"duration": 0, "damage": 8}, {"duration": 2, "status": "burning"}` → `{"damage": 8}, {"status": "burning(2, 3, 1)"}` |
| `test_combo_multikey_effect.json` | `{"duration": 1, "damage": 8, "status": "burning"}` → `{"damage": 8, "status": "burning(1, 2, 1)"}` |

Числа для `burning(d, dmg, lvl_bonus)` — placeholder'ы, отбалансит Стасян
после плейтеста (TODO в JSON-комментарии — и в `specs/027-.../tasks.md`).

Новый файл: `data/skills/test_status_runtime.json` — minimal-скилл с одним
ability, один effect-объект `{"status": "poisoned(3, 10, 2)"}`. Для AC-X
покрытия poisoned-runtime в godmode-сцене.

## Acceptance criteria

### Структурные
- **AC-S1**: `AbilityEffect.duration` поле удалено. Все 4 effect-наследника
  (`DamageEffect`, `HealEffect`, `MoveEffect`, `CreateEffect`) — `duration`
  отсутствует, `apply_level` MoveEffect не ссылается на duration.
- **AC-S2**: `StatusEffect` имеет `status_id: StringName`, `args: Array[int]`.
  `StatusEffect.duration` отсутствует как @export — duration живёт в args[0].
- **AC-S3**: `StatusInstance` resource определён с полями: `status_id`,
  `duration`, `args`, `source_id`, `snapshot_value`.
- **AC-S4**: `Actor` имеет: `_statuses: Dictionary`, методы `add_status`,
  `remove_status`, `get_statuses`, `has_status`, `is_stunned`,
  `effective_speed`, `tick_statuses`, `damage_reduction`; сигнал
  `statuses_changed(actor_id)`.
- **AC-S5**: `Actor.take_damage` уменьшает входящий amount на
  `damage_reduction()`. Heal не затронут.

### Парсер
- **AC-P1**: `AbilityDatabase._make_effects_from_dict` для ключа `"status"`
  принимает строку формата `"id(n0, n1, ...)"`, парсит в `status_id` +
  `args: Array[int]`. Пробелы вокруг запятых допускаются.
- **AC-P2**: arity-mismatch (число args в строке ≠ `arity` в registry) —
  `GameLogger.warn`, инстанс не создаётся.
- **AC-P3**: unknown `status_id` (нет в registry) — `GameLogger.warn`,
  инстанс не создаётся.
- **AC-P4**: malformed строка (нет скобок, не int, дублированные запятые) —
  `GameLogger.warn`, инстанс не создаётся; AbilityDatabase не падает.
- **AC-P5**: legacy ключ `"duration"` на уровне effect-объекта — парсер
  логирует `info` один раз на ability и игнорирует. После миграции (AC-M1)
  таких объектов в репе нет, но шим оставляем тихим — поможет при подтяжке
  ветвей в процессе джема.

### Registry
- **AC-R1**: `data/status_effects/` содержит ровно 9 JSON-файлов: stunned,
  slowed, poisoned, rooted, feared, burning, glitched, shielded, enraged.
- **AC-R2**: `StatusRegistry` загружает все 9, преложен через
  preload-таблицу runtime-классов; missing JSON / missing GD-класс →
  `GameLogger.error` на autoload, не crash.
- **AC-R3**: `StatusRegistry.runtime_for(&"unknown")` → null, `GameLogger.warn`.

### Runtime
- **AC-RT-stunned**: actor с stunned пропускает `enemy_ai_planner.plan`
  (move_intent и cast_intent остаются дефолтными). Player с stunned —
  слоты Q/W/E/R greyed, движение по карте заблокировано, через
  `stun_skip_delay` — `TurnManager.advance()`.
- **AC-RT-slowed**: AI с slowed двигается через ход (флип-флоп флага в
  StatusInstance.args[1]? нет — runtime stateful per instance, см. plan).
  Player.effective_speed = `floor(speed / 2)`, MoveRangeOverlay читает
  effective_speed (если уже читает speed напрямую — патч).
- **AC-RT-rooted**: `effective_speed == 0` для player и AI. AI policy не
  emit'ит move_intent. Cast не блокируется.
- **AC-RT-poisoned**: на tick — `take_damage(floor(max_hp * snapshot_value / 100))`.
  Floating-number и damage_dealt event приходят через стандартный канал
  (без правок в presentation).
- **AC-RT-burning**: на tick — `take_damage(snapshot_value)`. Аналогично.
- **AC-RT-feared**: AI с feared имеет `behavior_id == &"feared"` (overridden).
  Сценарий feared двигает actor'а ОТ source через `policy_kite_specific_actor`;
  rules пусты (cast не происходит). Если source мёртв на tick — статус expire
  в этот же tick, behavior_id restore'ится. Player с feared — статус
  отображается иконкой, поведение игрока не меняется.
- **AC-RT-enraged**: AI с enraged имеет `behavior_id == &"enraged"`. Сценарий
  enraged двигает actor'а К source через `policy_approach_specific_actor`;
  один rule с `condition_always` + `selector_specific_actor` + `tag_priority:
  ["damage"]` — при наличии damage-скилла в range, кастит его в source,
  игнорируя всех остальных врагов. Source мёртв на tick → expire + restore.
  Player с enraged — runtime no-op.
- **AC-RT-glitched**: runtime — пустой класс, тик только декрементит
  duration. Иконка отображается, поведения нет.
- **AC-RT-shielded**: `Actor.damage_reduction()` суммирует `snapshot_value`
  всех инстансов с status_id == &"shielded" (стэк нескольких источников
  pull-через-разные-cast'ы — невозможен по re-apply-семантике, но
  суммируем на случай если в будущем разрешим многоисточниковый shield;
  пока всегда ≤1 инстанс).
- **AC-RT-strong**: `Actor.damage_amplifier()` суммирует все snapshot'ы
  активных инстансов strong (положительный знак). `DamageEffect.apply` и
  `Ability.predicted_damage_to` оба читают этот суммарный bonus в
  паре с `damage_bonus`. Final damage clamp'ится к 0.
- **AC-RT-weak**: симметрично strong, но `damage_amplifier` возвращает
  отрицательное (сложение с strong алгебраическое). Достаточно weak'а
  больше базового урона → итоговый урон 0 (`maxi(0, ...)` в DamageEffect).

### Re-apply семантика
- **AC-RA1**: `actor.add_status(instance_b)` при существующем инстансе с
  тем же `status_id` — старый инстанс полностью замещается. Никакого
  `max(old.duration, new.duration)`, никакого суммирования.
- **AC-RA2**: re-apply emit'ит `statuses_changed` один раз.
- **AC-RA3**: применение `feared` при активном `enraged` (или наоборот) —
  старый инстанс удаляется через стандартный `remove_status` путь
  (включая runtime.on_remove → restore behavior_id), затем добавляется
  новый. Behavior-override slot на Actor'е содержит ровно один
  feared/enraged инстанс одновременно.

### AI scenario building blocks (feared/enraged)
- **AC-AI1**: `BehaviorDatabase` распознаёт новые `kind`-значения:
  - `target_selector.kind == "specific_actor"` → `SelectorSpecificActor`
  - `movement_policy.kind == "approach_specific_actor"` → `PolicyApproachSpecificActor`
  - `movement_policy.kind == "kite_specific_actor"` → `PolicyKiteSpecificActor`
  Unknown kind на этих позициях — warn + fallback (`SelectorNearestEnemy` /
  `PolicyHoldPosition`) как у существующих ветвей match.
- **AC-AI2**: `data/ai_behaviors/feared.json` и `enraged.json` загружаются
  `BehaviorDatabase` без warn'ов.
- **AC-AI3**: `EnemyAIPlanner.plan` перед обходом `scenario.rules` обогащает
  ctx ключом `behavior_target_id: StringName` — id source'а из активного
  feared/enraged status (если есть). Если на actor'е нет ни feared, ни
  enraged — ключ не выставляется (или пустой).
- **AC-AI4**: `EnemyAIPlanner._build_target_candidates` для `SelectorSpecificActor`
  возвращает `[ActorRegistry.get_actor(ctx["behavior_target_id"])]` без
  team-фильтра. Null или dead source → пустой список → правило не сработает,
  AI fallthrough на movement.
- **AC-AI5**: `PolicyApproachSpecificActor.pick_step` / `PolicyKiteSpecificActor.pick_step`
  читают `ctx["behavior_target_id"]`. Источник null/dead → return `(-1,-1)`
  (defer); следом `enemy_ai_planner` опционально сваливается на
  `fallback_skill_id` (в наших сценариях он пустой → hold).

### Behavior-override apply / restore
- **AC-BO1**: `feared_runtime.on_apply(actor, inst)` / `enraged_runtime.on_apply`:
  - если `actor._behavior_override_id == &""` — сохраняет
    `actor._original_behavior_id = actor.behavior_id`
  - устанавливает `actor._behavior_override_id = inst.status_id`,
    `actor.behavior_id = inst.status_id`
- **AC-BO2**: `feared_runtime.on_remove` / `enraged_runtime.on_remove`:
  - если `actor._behavior_override_id == inst.status_id` —
    restore `actor.behavior_id = actor._original_behavior_id`,
    очистить `_behavior_override_id` и `_original_behavior_id`
  - иначе (status был silently удалён ради другого override'а) — no-op
- **AC-BO3**: `Actor.add_status(inst)` — для feared/enraged, ДО store'а
  в `_statuses` снимает противоположный статус через `remove_status`
  (триггерит on_remove + restore), затем уже store'ит и вызывает on_apply.

### Cast-flow / tick-order
- **AC-CT1**: `_on_world_turn_ended` — статусы тикаются ПЕРЕД `_run_enemy_turn`.
- **AC-CT2**: tick-порядок инстансов на одном actor — insertion order Dictionary
  (стабильный, нет случайности).
- **AC-CT3**: DoT-урон от tick'а может убить actor'а; в этот же tick его
  оставшиеся статусы не применяются, registry/grid очистка идёт через
  существующий `EventBus.actor_died` flow.
- **AC-CT4**: feared/enraged tick проверяет `source_id` живость через
  `actor_registry.get_actor(source_id)`; null или dead → expire.

### UI / визибилити
- **AC-UI1**: `StatusIconStrip` инстансится в `scenes/dev/player.tscn` и
  `scenes/dev/manekin.tscn` как ребёнок Actor-узла, выше `HealthBar`.
- **AC-UI2**: `StatusIconStrip.bind_actor(actor)` подключается к
  `actor.statuses_changed`; на emit виджет ребилдится из
  `actor.get_statuses()`.
- **AC-UI3**: Pill для каждого активного статуса показывается с правильным
  family-glyph'ом (по StatusRegistry.family) и duration-числом (через
  существующий API виджета).
- **AC-UI4**: При player.is_stunned() Q/W/E/R слоты в HUD'е визуально
  greyed (через существующий cooldown-стиль, не новая визуалка).

### Migration
- **AC-M1**: 13 production+test skill JSON'ов потеряли все ключи
  `"duration"` на уровне effect-объектов. `grep -R '"duration":' data/skills/`
  — пусто.
- **AC-M2**: `test_combo_hex_circle_damage_status.json` и
  `test_combo_multikey_effect.json` используют новый формат
  `"status": "burning(N, M, L)"`.
- **AC-M3**: Новый файл `data/skills/test_status_runtime.json` с
  `"status": "poisoned(3, 10, 2)"` — для AC-X3.

### Smoke / scenarios
- **AC-X1**: Запуск проекта → `SkillDatabase` грузит все skills без warn'ов;
  `StatusRegistry` грузит 11 статусов (stunned, slowed, poisoned, rooted,
  feared, burning, glitched, shielded, enraged, strong, weak) без warn'ов.
- **AC-X2**: Godmode — каст `test_combo_hex_circle_damage_status` по группе
  врагов: damage применяется сразу (8), на следующем `world_turn_ended`
  burning(2,3,1) тикает по 3 урона, через 2 хода expire.
- **AC-X3**: Godmode — каст `test_status_runtime` по manekin'у (max_hp=100):
  poisoned(3,10,2) при level=0 → 10% от 100 = 10 урона на tick × 3 хода =
  30 total. При level=2 → (10 + 2*2) = 14% × 3 хода = 42 total. Snapshot
  виден в логе StatusInstance.
- **AC-X4**: Self-cast `stunned` на manekin (через тестовый скилл или
  debug-инструмент) — manekin на следующем `world_turn_ended` не
  движется и не атакует, через `d` ходов snap'ится.
- **AC-X5**: Stunned на player — Q/W/E/R greyed, движение мышью блок'нуто,
  через delay авто-advance. После expire — контроль возвращается без
  ручного refresh'а.
- **AC-X6**: shielded(3, 5, 0) на manekin → ability с damage=8 → manekin
  получает 3 урона (8-5).
- **AC-X7**: Re-apply burning(5,3,1) поверх burning(2,3,1) — duration
  скакнул до 5, args заменились, не «burning(7,3,1)».
- **AC-X8**: AI manekin с feared(3, source=player_id) — `behavior_id`
  меняется на `&"feared"`, manekin двигается ОТ player'а 3 хода (через
  `policy_kite_specific_actor`), не атакует. На ходе 4 — статус expire,
  `behavior_id` restore'ится на `&"default_melee"`, AI возвращается к
  approach+attack. Если player умирает на ходу 2 — feared expire'ит сразу
  на следующем tick'е (source мёртв), AI back to default с хода 3.
- **AC-X9**: AI manekin с enraged(3, source=player_id), баргу-другие враги
  на карте (например другой manekin) — manekin игнорирует второго и идёт
  к player'у; в range атакует ТОЛЬКО player'а. На expire — обычная default
  policy (атакует ближайшего).
- **AC-X10**: AI manekin с feared(2), затем кастят enraged(3): feared
  инстанс удаляется (один на одного — mutual exclusivity), enraged
  применяется. `behavior_id` сразу `&"enraged"`. Player'а атакует.

## Out of scope

- **Floating-text "Stunned!" / "Poisoned!"** над actor'ом — pill-icon
  достаточен, доп. визуал — отдельная фича после плейтеста.
- **Real `glitched` behaviour** — stub, отдельный spec.
- **Fear/enrage на player'е** — runtime no-op, статус хранится но не
  переопределяет управление (вариант C из чата).
- **AudioDB / VFXDB hook на add_status / on_tick** — фича аудио-системы
  отдельная (как в 026 для sound_start/end).
- **Status-icon Sprites Кати** — placeholder unicode-glyphs из текущего
  `_ICON_BY_FAMILY`, sprite assets — отдельный downstream.
- **Stack семантика для shielded** (несколько источников складываются) —
  сейчас один инстанс на (target, id). Если плейтест покажет потребность
  в multi-shield — отдельная фича.
- **Status immunity / cleanse** — не блокируем re-apply / нет dispel'а.
  Отдельная механика, не в 027.
- **Localized loc-keys для статусов** — `loc_name` / `loc_desc` хранятся
  в JSON, не диспатчатся (как `Skill.name` / 026).
- **Балансные числа** в migrated burning skill'ах — placeholder'ы,
  Стасян после плейтеста.
- **`AbilityEffect.duration` шим** — нет (hard removal, как 021/026).
- **Tooltip на pill'ах** — `status_icon_strip` уже эмитит
  `status_pill_hovered`, но потребитель — отдельная фича UI-kit'а.
- **`ConditionSpecificActorInRange`** — НЕ нужен. Сценарий enraged
  использует `condition_always` + `selector_specific_actor`; out-of-range
  source автоматически отсекается через существующий `_target_in_skill_range`
  → правило не fire'ит → fallthrough на approach-policy.
- **Coexistence feared+enraged** — exclusive (см. AC-RA3). Если плейтест
  покажет потребность в стаке — отдельная фича.

## Open after playtest

1. **Stack-семантика для shielded** — один источник или сумма всех?
2. **Stun-skip delay** — `0.4s` дефолт, может быть слишком долго /
   слишком быстро. Tunable в `game_speed.cfg`.
3. **Slowed для player** — `floor(speed / 2)` или пропуск-через-ход как у AI?
   Сейчас выбрана первая, потому что у player'а speed > 1 (отображается
   через MoveRangeOverlay), у AI policy жёстко 1 hex/turn.
4. **Slowed-stack с rooted** — rooted сейчас побеждает (`effective_speed = 0`).
   Тривиально, но если плейтест покажет что rooted+slowed = «двойной
   рут» нелогичен — поправим.
5. **DoT-урон vs death timing** — если burning убивает в начале хода,
   actor лишается своего хода целиком. Альтернатива — DoT в конце хода.
   Сейчас в начале — симметрично с poisoned по описанию из чата.
6. **Full-absorb damage UX** — когда shielded полностью гасит входящий
   урон, `Actor.take_damage` молча возвращает без `damage_dealt` event'а.
   Игрок видит pill `◆` но никаких floating numbers — выглядит как
   промах. Опции: emit'ить damage_dealt(amount=0), отдельный
   `EventBus.damage_absorbed` сигнал, или floating-text «ABSORBED».
7. **Slowed AI 1-tick lag** — slowed начинает действовать со ВТОРОГО
   `world_turn_ended` после apply'а (resolve выполняется до plan'а в том же
   фрейме, поэтому первый ход после применения уже spent на resolve старого
   плана). Acceptable для джема; если очевидно playtester'ам — apply-time
   set rt_flag=1 фиксит.
8. **Stun multi-tick recursion** — N тиков stun = N×`stun_skip_delay`
   «тёмных кадров» с pill'ом. Если играет нудно — можно тикать все
   decrement'ы за один кадр без advance/recursion.

## Зависимости

- **Upstream:** 026 (effect-разворот, schema), 021 (level scaling), 007
  (Skill/Ability контракт), 011 (UI-kit StatusIconStrip).
- **Downstream:** 008 (enemy AI — feared/enraged hook в movement_policy
  и target-selector), будущая фича audio/VFX dispatch для on_apply / on_tick.
- **Координация:** Sergey (008) — добавляем 1 selector + 2 movement-policy
  + 2 scenario JSON'а в его территорию AI. Хук в `EnemyAIPlanner.plan`
  (ctx-enrichment с `behavior_target_id`) и `_build_target_candidates`
  (специальная ветка для `SelectorSpecificActor`) — на его стороне 2 файла.
  Без правок tactic_rule / selectors API. Согласовать через PR-review.
  Andrey (009) — StatusIconStrip уже UI-kit, патчим только `bind_actor`
  (low-touch). Стасян — балансные числа в burning skill'ах после имплемента.
