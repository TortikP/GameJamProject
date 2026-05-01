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

### Компонент: Linger (опциональный, только для SMALL walkable)

При выходе actor'а с тайла на него применяется тайловый эффект с ненулевым `duration` — горит ещё N ходов. Никаких отдельных «статус-систем» — переиспользуется существующий `TileEffectRegistry`.

| Поле | Тип | Описание |
|---|---|---|
| `linger_effect_id` | `StringName` | ID из `data/tile_effects/`. Должен быть эффект с `duration > 0`. `&""` = выкл. |

При выходе: resolver применяет `linger_effect_id` к actor'у на `duration` ходов (тиканье — в resolver, не в 018). Graceful degradation: если resolver ещё не написан — `EventBus.tile_object_actor_exited` эмитится, никто не подписан, эффект молча не тикает.

**Расширение tile_effects схемы** — в рамках 018: добавляем поле `duration: int` к `data/tile_effects/*.json` (default 0 = мгновенный эффект, backward-compat). Новый sample `data/tile_effects/burning.json` (`kind: "damage", amount: 2, duration: 2`). Existing файлы (`damage_zone.json`, `heal_fountain.json`) не трогаются — пустой default = 0.

Запреты:
- `linger_effect_id` допустимо ТОЛЬКО для `level=SMALL` + `blocks_movement=false`. Иначе warn + force-empty при load.
- `linger_effect_id != &""` но referenced effect не имеет `duration > 0` → warn при load (не блокер — resolver просто применит мгновенный эффект один раз).

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

### OQ-2: Триггер behavior для SMALL walkable hazard (лава) — **C+linger** (комбо: on_enter + DoT + эффект с duration после выхода)
Лава: `applies_on_enter=true` (мгновенный урон при входе) + `applies_on_turn_end=true` (DoT пока стоит) + `linger_effect_id="burning"` (после выхода — применяется tile_effect `burning` с `duration=2`, actor ещё 2 хода получает урон). Статус-система на actor'е не нужна — переиспользуется существующий TileEffectRegistry, schema tile_effects расширяется полем `duration: int` (default 0, backward-compat).

### OQ-3: Один объект на тайл или несколько — **A** (один)
`HexTile.object_id: StringName`. Multi-stack отложен.

## Acceptance criteria

- **AC-O1:** `TileObject` data class в `scripts/core/arena/tile_object.gd`. Все поля из секции «Что вводится». Pure data — никаких сигналов, ноды-операций, EventBus calls внутри.
- **AC-O2:** `TileObjectRegistry` в `scripts/core/arena/tile_object_registry.gd` — паттерн копия `tile_effect_registry.gd` (load_from_dir / get / has). При load — schema validation: уровень валиден (`-1/0/1`); для ELEVATION `behavior_effect_id` обнуляется с warn; для LARGE/ELEVATION `blocks_movement`/`blocks_abilities_through` форсятся в `true` независимо от JSON. Не падать при некорректном JSON — warn и пропустить файл.
- **AC-O3:** `HexTile` получает поле `object_id: StringName` (default `&""`). Заполняется из TileMap custom data layer "object_id" в `HexGrid._build_tile_map`.
- **AC-O4:** `HexPathfinder` учитывает `TileObject.blocks_movement` через registry.get(tile.object_id). Тайл с `blocks_movement=true` не доступен для completion хода (но может быть промежуточным для проекций — это пока не в скоупе).
- **AC-O5:** Минимум 6 sample JSON в `data/tile_objects/` + 1 новый tile_effect:
  - `mountain.json` — ELEVATION, все триггеры false.
  - `lava_pool.json` — SMALL, walkable=true, behavior=damage_zone, `applies_on_enter=true`, `applies_on_turn_end=true`, `linger_effect_id="burning"`, tags=[liquid, hazard], not breakable.
  - `heal_fountain.json` — LARGE, behavior=heal_fountain, `aura_radius=1`, остальные триггеры false, not breakable.
  - `wooden_barrel.json` — SMALL, walkable=false, breakable hp=2, armor_tags=[], tags=[wood, flammable], on_destroy_effect_id=damage_zone.
  - `wooden_table.json` — SMALL, walkable=false, breakable hp=2, tags=[wood, furniture, flammable], all triggers false, no on-destroy.
  - `boulder.json` — LARGE, breakable hp=10, armor_tags=[physical], all triggers false.
  - `data/tile_effects/burning.json` — NEW: `kind: "damage", amount: 2, duration: 2`. Используется как linger-эффект лавы.
- **AC-O6:** Schema doc в `data/tile_objects/_schema.md` (плейсхолдер на JSON-схеме, человекочитаемый — для Стасяна, чтобы добавлял объекты сам). Включает все поля с типами и дефолтами.
- **AC-O7:** EventBus сигналы добавлены: `tile_object_damaged(coord: Vector2i, hp_remaining: int)`, `tile_object_destroyed(coord: Vector2i, object_id: StringName)`, `tile_object_effect_triggered(coord: Vector2i, target_actor_id: StringName, effect_id: StringName)`, `tile_object_actor_exited(coord: Vector2i, actor_id: StringName, object_id: StringName)` — последний нужен для linger (resolver слушает и применяет `linger_effect_id` с duration к actor'у). 018 только декларирует; подписчики — в follow-up resolver-фиче.
- **AC-O8:** Smoke (manual, Sergey): тестовая сцена `scenes/dev/tile_objects_smoke.tscn`. F5 → лог `Loaded 6 tile objects` без WARN. Шаг в lava_pool → лог `tile_object_effect_triggered ... damage_zone` (on_enter). Постоять → второй лог (turn_end). Выйти → `tile_object_actor_exited` (resolver отсутствует — graceful, эффект не тикает, но сигнал ловится логгером). Стоять рядом с heal_fountain → аура в turn_end. Удар по barrel → hp=1, ещё → `tile_object_destroyed` + `damage_zone` на тайле.
- **AC-O9:** `data/tile_effects/burning.json` (`duration: 2`) загружается `TileEffectRegistry` без ошибок. Существующие `damage_zone.json`/`heal_fountain.json` — без `duration` → default 0, backward-compat.

## Out of scope

- **Активные объекты с ходами** (Tesla tower, thorn-spitter). Это actor/entity с AI, отдельная фича.
- **Multi-tile объекты.** Один объект — один тайл.
- **Несколько объектов на тайл** (см. OQ-3).
- **Cover** (defensive bonus за SMALL объектом). Deferred, после ranged-механики.
- **Анимированные объекты.** 018 — статичные спрайты.
- **Процедурный спавн объектов.** Только ручная расстановка в TileMap.
- **Замена существующих tile_effects на объекты.** Они остаются, переиспользуются через `behavior_effect_id`/`linger_effect_id`.
- **Runtime trigger resolver** — кто тикает duration-эффекты по ходам и применяет linger к actor'у. 018 только эмитит `tile_object_actor_exited`. Resolver — `019-tile-object-resolver` (мой скоуп).

## Зависимости

- **Upstream:** 002-hex-grid, `tile_effect_registry` + `tile_effects/*.json`, 011-skill-tags (паттерн Array-парсинга).
- **Downstream:** модификатор-движок (мой) — после 018 могу писать синергии fire-spell + flammable объект.
- **Coordination:**
  - **Egor:** PR review обязателен (3 его файла). Additive изменения, API не переименовывается.
  - **Стасян:** после мержа добавляет JSON объекты по `_schema.md`.
  - **Андрей:** не затронут в 018.

## История правок

- 2026-05-01 — draft v1, OQ-1..OQ-3 открыты.
- 2026-05-02 — v2: OQ-1/2/3 разрешены; 4 bulev флага триггеров; Linger DoT через `linger_status_id`/`linger_duration`; actor-status dependency.
- 2026-05-02 — v3: Linger переработан — вместо actor-status системы используется tile_effect с `duration: int`. Поле `linger_effect_id: StringName` → ссылка на `data/tile_effects/burning.json` (duration=2). Схема tile_effects расширена полем duration (backward-compat, default 0). Actor-side dependency убрана.
