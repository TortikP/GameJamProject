# 018-tile-objects — spec

**Owner:** Sergey (spell-craft module — объекты как контент-слой для модификатор-движка).
**Coordination required:** Egor — PR трогает `scripts/core/arena/hex_tile.gd`, `hex_grid.gd`, `hex_pathfinder.gd` (его модуль, см. CLAUDE.md ownership). Без его approve мерж в staging невозможен.
**Status:** Ready — OQ-1/2/3 разрешены (см. секцию Open Questions ниже). Implement gate в `tasks.md` снят. Имплементацию запускать по отдельной команде Sergey.

## Цель

Сейчас на тайлах ничего не лежит, кроме одноразовых `tile_effects` (`damage_zone`, `heal_fountain` — на-enter триггер, без объектной модели). Для боёвки и спелл-крафта нужна data-driven модель **объектов на тайлах**: камни, лужи лавы, фонтаны, бочки, столы. Объекты не имеют ходов и не двигаются — это статика. Но они влияют на проходимость, line-of-sight для способностей, и могут иметь пассивные эффекты.

После 018:
- модификатор-движок (моё, downstream) сможет писать правила вида «огненный спелл поджигает flammable объект»;
- Стасян добавляет новые объекты JSON-файлом в `data/tile_objects/` без кода;
- Егор-арена получает чистый API `TileObjectRegistry.get(tile.object_id)` вместо хардкода.

## Что вводится

Новая сущность `TileObject` — pure data, грузится из JSON-ов в `data/tile_objects/`. На каждом тайле — максимум 1 объект (см. OQ-3). Тайл хранит только `object_id: StringName` (или пустую `&""` если объекта нет).

### Уровни (TileObject.Level enum)

| Level | Имя | blocks_movement | abilities проходят сквозь | может иметь effect | примеры |
|---|---|---|---|---|---|
| `-1` | `LARGE` | да | нет | да (сильный) | фонтан-хил, большой алтарь, валун с эффектом |
| `0` | `SMALL` | **зависит от флага** `blocks_movement` | да (всегда) | да (слабый) или нет | лава-лужа, замедляющая вода, стол, куст, стул |
| `1` | `ELEVATION` | да | нет | **нет (запрещено схемой)** | гора, скала, холм |

Различие LARGE vs ELEVATION — оба блокируют движение и способности, но ELEVATION **по схеме** не может иметь эффектов (валидатор регистра выбросит warn и обнулит `behavior_effect_id`). Это не оптимизация — это семантика: возвышенность = природный рельеф, а не интерактивный объект.

### Базовые поля (есть у всех объектов)

| Поле | Тип | Описание |
|---|---|---|
| `id` | `StringName` | уникальный, имя файла = `<id>.json` |
| `level` | `int` (-1 / 0 / 1) | см. таблицу выше |
| `blocks_movement` | `bool` | для LARGE/ELEVATION фиксированно `true`, схема валидирует. Для SMALL — настраивается. |
| `blocks_abilities_through` | `bool` | для LARGE/ELEVATION — `true`, фиксированно. Для SMALL — `false`, фиксированно. Поле в JSON опционально, default из level. |
| `sprite_path` | `String` | `res://...` к спрайту, для пресентейшн-слоя |

### Компонент: Destructible (опциональный)

Включается флагом `breakable: true`. Если `false` — остальные поля компонента игнорируются.

| Поле | Тип | Описание |
|---|---|---|
| `breakable` | `bool` | вкл/выкл компонент |
| `hp` | `int` | стартовый HP. <=0 → объект мгновенно уничтожается. |
| `armor_tags` | `Array[StringName]` | какие типы урона его ломают: `["physical", "fire"]`. Пусто = любой. См. tags из 011-skill-tags. |

Damage flow — спелл/удар попадает в тайл с breakable объектом → `EventBus.tile_object_damaged(coord, hp_remaining)`. При hp<=0 → `tile_object_destroyed(coord, object_id)`, далее срабатывает on-destroy логика (см. ниже).

### Компонент: Behavior (опциональный)

Включается ненулевым `behavior_effect_id`. Эффект — ссылка на запись в существующем `TileEffectRegistry` (`damage_zone`, `heal_fountain`, и т.д.). 018 НЕ дублирует tile_effects — переиспользует.

Триггеры — независимые булевы флаги (см. OQ-2 в Open Questions). Объект включает любую комбинацию.

| Поле | Тип | Описание |
|---|---|---|
| `behavior_effect_id` | `StringName` | ID из `data/tile_effects/`. `&""` = нет эффекта. |
| `applies_on_enter` | `bool` | срабатывает однократно когда actor шагает на тайл. Только для SMALL walkable. |
| `applies_on_turn_end` | `bool` | срабатывает в конце хода для actor'а, стоящего на тайле (DoT). Только для SMALL walkable. |
| `aura_radius` | `int` | 0 = нет ауры. >=1 = в конце каждого хода эффект применяется ко всем актёрам в радиусе R hexes от тайла. Сам тайл (R=0) включается только если actor может на нём стоять (SMALL walkable). |
| `applies_on_attacked` | `bool` | срабатывает на тайле когда объект получает урон. Полезно для бочек-бомб. Требует `breakable=true` иначе бессмысленно. |

Запреты (валидируются registry-ем при load, нарушения → warn + force-correct):
- `level=ELEVATION` → ВСЕ четыре триггер-поля `false`/`0`. Возвышенность не имеет эффектов.
- `level=LARGE` → `applies_on_enter=false`, `applies_on_turn_end=false` (на тайл нельзя войти). `aura_radius>=1` или `applies_on_attacked=true` — допустимо.
- `level=SMALL` (`blocks_movement=true`) — как LARGE: enter/turn_end запрещены, aura/on_attacked — да.
- `level=SMALL` (`blocks_movement=false`) — любая комбинация.
- Если `behavior_effect_id=&""` и любой из триггеров включён → warn и зануление триггеров (бессмысленная конфигурация).

### Компонент: Linger DoT (опциональный, только для SMALL walkable)

Решение OQ-2 (см. ниже): шаг в лаву даёт мгновенный урон + DoT пока стоишь + status-эффект остаётся на actor'е после выхода из тайла. Этот компонент описывает третью часть.

| Поле | Тип | Описание |
|---|---|---|
| `linger_status_id` | `StringName` | ID статус-эффекта на actor'е (например `&"burning"`). При выходе actor'а из тайла вызывается `actor.add_status(linger_status_id, linger_duration)`. `&""` = выкл. |
| `linger_duration` | `int` | сколько ходов status держится на actor'е. Default 0 → если linger_status_id задан, но duration 0 — warn + force-skip. |

Запреты:
- `linger_status_id != &""` допустимо ТОЛЬКО для `level=SMALL` и `blocks_movement=false`. На неprожаваемом тайле некому «выходить». Иначе warn + force-empty.
- Совместимо с любыми триггерами (можно одновременно `applies_on_enter` + `linger_status_id`).

**Важно:** актуальная имплементация actor-side статус-системы пока отсутствует — у `Actor` нет метода `add_status`. Существующий `scripts/core/abilities/effects/status_effect.gd` использует тот же паттерн graceful-degradation: вызывает `add_status` если есть, иначе info-лог. 018 переиспользует этот паттерн — runtime DoT начнёт «работать по-настоящему» когда actor-status фича будет сделана отдельной спекой. Поля декларируются сейчас, чтобы не править JSON-схему позже.

### Компонент: SpellSynergyTags (опциональный, по умолчанию `[]`)

| Поле | Тип | Описание |
|---|---|---|
| `tags` | `Array[StringName]` | `flammable`, `freezable`, `conductive`, `wood`, `stone`, `metal`, `liquid`, `plant`, `furniture` |

Используется модификатор-движком (мой профильный код, downstream после 018) — спелл проверяет `&"flammable" in obj.tags` для синергий. В 018 теги только парсятся и хранятся, поведения нет.

### Компонент: OnDestroy (опциональный)

Срабатывает только если `breakable=true` и hp дошёл до 0.

| Поле | Тип | Описание |
|---|---|---|
| `on_destroy_effect_id` | `StringName` | ID tile_effect, который **остаётся** на тайле после разрушения (баррель → лужа огня; ядовитая бочка → `damage_zone`). `&""` = нет. |
| `on_destroy_spawn_object_id` | `StringName` | ID объекта-замены (лёд → водяная лужа как новый SMALL-объект). `&""` = нет. |

Можно одновременно (например: разрушить ледяной столб → spawnится лужа воды (объект, conductive=true) + ставится `frost_zone` tile_effect). Если оба пусты — тайл просто чистится.

### Компонент: Cover — DEFERRED

Изначально предлагал `cover: float` для SMALL объектов — модификатор урона юниту за тайлом. Решение: **не в 018**. Причины: (а) ranged-механики и точная модель LOS для них пока не финализированы; (б) добавляется тривиально позже одним полем + логикой в spell-resolver. Зафиксировано как «следующая итерация» в `out_of_scope`.

### Компонент: Audio/Visual (опциональный)

| Поле | Тип | Описание |
|---|---|---|
| `vfx_destroy` | `String` | `res://assets/vfx/...` |
| `sfx_destroy` | `String` | `res://assets/audio/sfx/...` |

Нет `vfx_idle`/`sfx_idle` — спрайт уже в `sprite_path`. Если когда-нибудь нужны анимированные объекты — отдельной фичей.

## Open Questions — RESOLVED

### OQ-1: Триггер behavior для LARGE-объектов — **A** (aura, configurable radius)
Эффект LARGE-объекта применяется в конце каждого хода ко всем actor'ам в `aura_radius` hexes. Радиус настраивается per-object в JSON (default 1 для соседей; фонтан — R=1; гипотетический «алтарь зоны» — R=3). Дополнительно допускается `applies_on_attacked` для бочек-бомб.

### OQ-2: Триггер behavior для SMALL walkable hazard (лава) — **C+linger** (комбо: on_enter + DoT + сохраняется после выхода)
Лава: `applies_on_enter=true` (мгновенный урон при входе) + `applies_on_turn_end=true` (DoT пока стоит) + `linger_status_id="burning"`, `linger_duration=2` (после выхода — два хода продолжает гореть). Триггеры реализованы как 4 независимых булевых флага (см. секцию Behavior выше) — любая комбинация допустима, валидатор обрезает запрещённые для уровня.

### OQ-3: Один объект на тайл или несколько — **A** (один)
`HexTile.object_id: StringName`. Multi-stack отложен.

## Acceptance criteria

- **AC-O1:** `TileObject` data class в `scripts/core/arena/tile_object.gd`. Все поля из секции «Что вводится». Pure data — никаких сигналов, ноды-операций, EventBus calls внутри.
- **AC-O2:** `TileObjectRegistry` в `scripts/core/arena/tile_object_registry.gd` — паттерн копия `tile_effect_registry.gd` (load_from_dir / get / has). При load — schema validation: уровень валиден (`-1/0/1`); для ELEVATION `behavior_effect_id` обнуляется с warn; для LARGE/ELEVATION `blocks_movement`/`blocks_abilities_through` форсятся в `true` независимо от JSON. Не падать при некорректном JSON — warn и пропустить файл.
- **AC-O3:** `HexTile` получает поле `object_id: StringName` (default `&""`). Заполняется из TileMap custom data layer "object_id" в `HexGrid._build_tile_map`.
- **AC-O4:** `HexPathfinder` учитывает `TileObject.blocks_movement` через registry.get(tile.object_id). Тайл с `blocks_movement=true` не доступен для completion хода (но может быть промежуточным для проекций — это пока не в скоупе).
- **AC-O5:** Минимум 6 sample JSON в `data/tile_objects/`:
  - `mountain.json` — ELEVATION, все триггеры false.
  - `lava_pool.json` — SMALL, walkable=true, behavior=damage_zone, `applies_on_enter=true`, `applies_on_turn_end=true`, `linger_status_id="burning"`, `linger_duration=2`, tags=[liquid, hazard], not breakable.
  - `heal_fountain.json` — LARGE, behavior=heal_fountain, `aura_radius=1`, остальные триггеры false, not breakable.
  - `wooden_barrel.json` — SMALL, walkable=false, breakable hp=2, armor_tags=[], tags=[wood, flammable], on_destroy_effect_id=damage_zone (огненная лужа после взрыва — пока используем damage_zone как proxy, отдельный fire_zone — задача Стасяна), `applies_on_attacked=true` опционально (если хотим эффект при ударе ДО разрушения).
  - `wooden_table.json` — SMALL, walkable=false, breakable hp=2, tags=[wood, furniture, flammable], all triggers false, no on-destroy.
  - `boulder.json` — LARGE, breakable hp=10, armor_tags=[physical], all triggers false.
- **AC-O6:** Schema doc в `data/tile_objects/_schema.md` (плейсхолдер на JSON-схеме, человекочитаемый — для Стасяна, чтобы добавлял объекты сам). Включает все поля с типами и дефолтами.
- **AC-O7:** EventBus сигналы добавлены: `tile_object_damaged(coord: Vector2i, hp_remaining: int)`, `tile_object_destroyed(coord: Vector2i, object_id: StringName)`, `tile_object_effect_triggered(coord: Vector2i, target_actor_id: StringName, effect_id: StringName)`, `tile_object_actor_exited(coord: Vector2i, actor_id: StringName, object_id: StringName)` — последний нужен для linger-логики (resolver слушает и вызывает `actor.add_status(linger_status_id, linger_duration)`). Эмиттеры в 018 пока ad-hoc (в hex_grid/pathfinder где удобно), подписчики — в follow-up resolver-фиче.
- **AC-O8:** Smoke (manual, Sergey + Egor): тестовая сцена `scenes/dev/tile_objects_smoke.tscn` с расставленными 6 объектами. F5 → визуально все спрайты на месте, pathfinder обходит ELEVATION/LARGE/non-walkable SMALL, шаг в lava_pool логирует `tile_object_effect_triggered` (on_enter), стояние в lava_pool ещё хотя бы один turn_end логирует второй trigger, выход из lava_pool логирует `[INFO][StatusEffect-pattern] would apply 'burning' for 2 turns` (т.к. `Actor.add_status` пока no-op, см. `status_effect.gd` graceful pattern), удар по `wooden_barrel` снижает hp в логе, при hp=0 объект исчезает + спавнится `damage_zone` static_effect.

- **AC-O9:** Linger gracefully degrades: 018 НЕ требует существующего `Actor.add_status` метода — если его нет, регистрируется info-лог по паттерну `scripts/core/abilities/effects/status_effect.gd`. Если `add_status` появится позже (отдельной фичей actor-status) — линкер начнёт работать без правок 018.

## Out of scope

- **Активные объекты с ходами** (Tesla tower, thorn-spitter, всё что «делает что-то по своему таймеру»). Это actor/entity с AI, отдельная фича. 018 — только статика.
- **Multi-tile объекты** (большой собор на 7 гексов). Один объект — один тайл.
- **Несколько объектов на тайл** (см. OQ-3).
- **Cover** (defensive bonus за SMALL объектом). Deferred, отдельная фича после ranged-механики.
- **Анимированные объекты** (idle-анимации, флаги развеваются и т.п.). 018 — статичные спрайты.
- **Автоматический процедурный спавн объектов** (room generation). Все sample-объекты ставятся вручную в TileMap при сборке арены.
- **Замена существующих `data/tile_effects/damage_zone.json` и `heal_fountain.json` на объекты.** Они остаются как tile_effects, переиспользуются через `behavior_effect_id`. Дедупликация — отдельной фичей если будет нужна.
- **Schema-валидатор как отдельный CLI/тулинг.** Валидация только на load, в логах. Стасян правит JSON, F5 — увидит warn в console.
- **Actor-side status effect система** (`Actor.add_status`, тиканье статусов по ходам, отображение статусов в UI). 018 только декларирует data-контракт `linger_status_id`/`linger_duration` и вызывает `Actor.add_status` если он есть. Реализация — отдельной спекой (нужна для `StatusEffect` ability-эффекта тоже, который сейчас в том же no-op состоянии — см. `scripts/core/abilities/effects/status_effect.gd`). Хорошая координация: совместить эти две фичи в одну `019-actor-status` спеку (но это уже не Sergey'ский скоуп — actor module, скорее Alexey).
- **Runtime trigger resolver** (кто именно слушает `tile_object_effect_triggered` и применяет эффект к актёру). 018 эмиттит сигналы. Подписчик — отдельная микро-фича в spell-resolver (мой скоуп) либо в turn manager. Пометил в Группе I tasks как T022.

## Зависимости

- **Upstream:** 002-hex-grid (HexTile/HexGrid в текущем виде), `tile_effect_registry` (есть в `scripts/core/arena/`), 011-skill-tags (паттерн `Array[StringName]` парсинга — копируем оттуда).
- **Downstream:** модификатор-движок (мой, в работе) — после 018 я могу писать спелл-модификаторы которые читают `obj.tags`. Без 018 fire-spell не отличает баррель от стола.
- **Coordination:**
  - **Egor (arena owner):** PR review обязателен — трогаю 3 его файла. Все изменения additive (новое поле + read-path), public API не переименовывается → должно проходить.
  - **Стасян (content):** после мержа — пишет реальные balance-tuned JSON-ы поверх 6 sample. Schema-doc `_schema.md` для него.
  - **Андрей (presentation/UX):** не затронут в 018. Когда дойдёт до VFX интеграции при разрушении — отдельный пинг.

## История правок

- 2026-05-01 — draft v1, OQ-1..OQ-3 открыты, ждёт ответа Sergey перед implement.
- 2026-05-02 — v2: OQ-1/2/3 разрешены (A / C+linger / A). Behavior-триггер реструктурирован из enum-string в 4 независимых булевых флага. Добавлен компонент Linger DoT с `linger_status_id`/`linger_duration`. Добавлен AC-O9 (graceful degradation если `Actor.add_status` отсутствует — повторяет паттерн `status_effect.gd`). Добавлен 4-й EventBus сигнал `tile_object_actor_exited`. Status: Ready.
