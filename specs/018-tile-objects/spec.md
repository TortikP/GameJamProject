# 018-tile-objects — spec

**Owner:** Sergey (spell-craft module — объекты как контент-слой для модификатор-движка).
**Coordination required:** Egor — PR трогает `scripts/core/arena/hex_tile.gd`, `hex_grid.gd`, `hex_pathfinder.gd` (его модуль, см. CLAUDE.md ownership). Без его approve мерж в staging невозможен.
**Status:** Draft — заблокирован тремя Open Questions (OQ-1..OQ-3). До ответа на них `tasks.md` не запускается на implement.

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

| Поле | Тип | Описание |
|---|---|---|
| `behavior_effect_id` | `StringName` | ID из `data/tile_effects/`. `&""` = нет эффекта. |
| `behavior_trigger` | `StringName` | один из `on_enter` / `on_turn_end` / `aura` / `on_attacked` (см. OQ-1, OQ-2 ниже) |
| `aura_radius` | `int` | только для `aura`. 0 = только сам тайл (бессмысленно для LARGE), 1 = соседи, 2 = соседи соседей. |

Запреты:
- `level=ELEVATION` → `behavior_effect_id` должен быть `&""`. Иначе warn в логах и forced-zero при load.
- `level=LARGE` → `behavior_trigger` ∈ {`aura`, `on_attacked`} (т.к. `on_enter`/`on_turn_end` бессмысленны — на тайл не зайти).
- `level=SMALL` (walkable=true) → любой trigger.
- `level=SMALL` (walkable=false) → как LARGE: только `aura`/`on_attacked`.

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

## Open Questions

### OQ-1: Триггер behavior для LARGE-объектов
LARGE нельзя войти, значит `on_enter` нельзя применить. Варианты для триггера эффекта (например — фонтан хилит):
- **A (default proposal):** `aura` радиуса 1 (соседи), срабатывает каждый turn-end системой.
- **B:** `on_adjacent_enter` — однократно когда юнит впервые встал на соседний тайл.
- **C:** только `on_attacked` (для бочек-бомб, ловушек, декоративных алтарей-без-эффекта).

Default: **A**. B и C технически добавимы, но загромождают триггер-енам в первой итерации. Если не подходит — скажи, B и C могу влить сразу.

### OQ-2: Триггер behavior для SMALL walkable hazard (лава)
Шагнул в лаву — урон один раз или каждый ход стоя в ней? Существующий `damage_zone` сейчас on-enter (одноразово, см. `data/tile_effects/damage_zone.json`).

- **A (default proposal):** `on_enter` — урон при входе. Стоишь — больше не получаешь. Совместимо с текущим поведением.
- **B:** `on_turn_end_while_standing` — DOT пока стоишь.
- **C:** оба триггера сразу — урон при входе + урон каждый ход пока не вышел.

Default: **A** (минимальные изменения существующего кода). Если хочется DOT — B или C.

### OQ-3: Один объект на тайл или несколько
- **A (default proposal):** один. `HexTile.object_id: StringName`.
- **B:** массив. `HexTile.object_ids: Array[StringName]`. Сложнее визуал, сложнее destructible flow, сложнее коллизии с `static_effect_id`.

Default: **A**. На джем 72ч хватает; B можно позже.

## Acceptance criteria

- **AC-O1:** `TileObject` data class в `scripts/core/arena/tile_object.gd`. Все поля из секции «Что вводится». Pure data — никаких сигналов, ноды-операций, EventBus calls внутри.
- **AC-O2:** `TileObjectRegistry` в `scripts/core/arena/tile_object_registry.gd` — паттерн копия `tile_effect_registry.gd` (load_from_dir / get / has). При load — schema validation: уровень валиден (`-1/0/1`); для ELEVATION `behavior_effect_id` обнуляется с warn; для LARGE/ELEVATION `blocks_movement`/`blocks_abilities_through` форсятся в `true` независимо от JSON. Не падать при некорректном JSON — warn и пропустить файл.
- **AC-O3:** `HexTile` получает поле `object_id: StringName` (default `&""`). Заполняется из TileMap custom data layer "object_id" в `HexGrid._build_tile_map`.
- **AC-O4:** `HexPathfinder` учитывает `TileObject.blocks_movement` через registry.get(tile.object_id). Тайл с `blocks_movement=true` не доступен для completion хода (но может быть промежуточным для проекций — это пока не в скоупе).
- **AC-O5:** Минимум 6 sample JSON в `data/tile_objects/`:
  - `mountain.json` — ELEVATION, no effects.
  - `lava_pool.json` — SMALL, walkable=true, behavior=damage_zone (trigger per OQ-2), tags=[liquid, hazard], not breakable.
  - `heal_fountain.json` — LARGE, behavior=heal_fountain (aura R=1 per OQ-1), not breakable.
  - `wooden_barrel.json` — SMALL, walkable=false, breakable hp=2, armor_tags=any, tags=[wood, flammable], on_destroy_effect_id=damage_zone (огненная лужа после взрыва — пока используем damage_zone как proxy, отдельный fire_zone — задача Стасяна).
  - `wooden_table.json` — SMALL, walkable=false, breakable hp=2, tags=[wood, furniture, flammable], no behavior, no on-destroy.
  - `boulder.json` — LARGE, breakable hp=10, armor_tags=[physical], no behavior.
- **AC-O6:** Schema doc в `data/tile_objects/_schema.md` (плейсхолдер на JSON-схеме, человекочитаемый — для Стасяна, чтобы добавлял объекты сам). Включает все поля с типами и дефолтами.
- **AC-O7:** EventBus сигналы добавлены: `tile_object_damaged(coord: Vector2i, hp_remaining: int)`, `tile_object_destroyed(coord: Vector2i, object_id: StringName)`, `tile_object_effect_triggered(coord: Vector2i, target_actor_id: StringName, effect_id: StringName)`. Эмитятся, но в 018 на них никто не подписывается — подписки придут в follow-up фичах.
- **AC-O8:** Smoke (manual, Sergey + Egor): тестовая сцена `scenes/dev/tile_objects_smoke.tscn` с расставленными 6 объектами. F5 → визуально все спрайты на месте, pathfinder обходит ELEVATION/LARGE/non-walkable SMALL, шаг в lava_pool логирует `tile_object_effect_triggered`, удар по `wooden_barrel` снижает hp в логе, при hp=0 объект исчезает + спавнится `damage_zone` static_effect.

## Out of scope

- **Активные объекты с ходами** (Tesla tower, thorn-spitter, всё что «делает что-то по своему таймеру»). Это actor/entity с AI, отдельная фича. 018 — только статика.
- **Multi-tile объекты** (большой собор на 7 гексов). Один объект — один тайл.
- **Несколько объектов на тайл** (см. OQ-3).
- **Cover** (defensive bonus за SMALL объектом). Deferred, отдельная фича после ranged-механики.
- **Анимированные объекты** (idle-анимации, флаги развеваются и т.п.). 018 — статичные спрайты.
- **Автоматический процедурный спавн объектов** (room generation). Все sample-объекты ставятся вручную в TileMap при сборке арены.
- **Замена существующих `data/tile_effects/damage_zone.json` и `heal_fountain.json` на объекты.** Они остаются как tile_effects, переиспользуются через `behavior_effect_id`. Дедупликация — отдельной фичей если будет нужна.
- **Schema-валидатор как отдельный CLI/тулинг.** Валидация только на load, в логах. Стасян правит JSON, F5 — увидит warn в console.

## Зависимости

- **Upstream:** 002-hex-grid (HexTile/HexGrid в текущем виде), `tile_effect_registry` (есть в `scripts/core/arena/`), 011-skill-tags (паттерн `Array[StringName]` парсинга — копируем оттуда).
- **Downstream:** модификатор-движок (мой, в работе) — после 018 я могу писать спелл-модификаторы которые читают `obj.tags`. Без 018 fire-spell не отличает баррель от стола.
- **Coordination:**
  - **Egor (arena owner):** PR review обязателен — трогаю 3 его файла. Все изменения additive (новое поле + read-path), public API не переименовывается → должно проходить.
  - **Стасян (content):** после мержа — пишет реальные balance-tuned JSON-ы поверх 6 sample. Schema-doc `_schema.md` для него.
  - **Андрей (presentation/UX):** не затронут в 018. Когда дойдёт до VFX интеграции при разрушении — отдельный пинг.

## История правок

- 2026-05-01 — draft v1, OQ-1..OQ-3 открыты, ждёт ответа Sergey перед implement.
