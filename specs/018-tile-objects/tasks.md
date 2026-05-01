# 018-tile-objects — tasks

**Spec:** [`spec.md`](./spec.md) · **Plan:** [`plan.md`](./plan.md)

Легенда: `[P1]` критический путь · `[P2]` контент · `[P3]` doc/coord
`[P]` = parallel-safe (можно делать независимо после удовлетворения dependency)

> ✅ **OQ-1/2/3 разрешены** в spec.md (A / C+linger / A). Implement gate снят. `lava_pool.json` использует комбо-триггер (`applies_on_enter=true` + `applies_on_turn_end=true`) и `linger_status_id="burning"` / `linger_duration=2` (graceful degradation если `Actor.add_status` отсутствует — паттерн `status_effect.gd`).
>
> Старт implement — по отдельной команде Sergey.

---

## Группа A — research / схема (must precede code)

- [x] **T001** [P1] Research: открыть `scripts/` и определить точно — (а) есть ли EventBus и где, (б) как именно создаётся `HexPathfinder` и куда инжектить registry, (в) есть ли уже custom data layer "object_id" в TileSet или его надо добавить руками. Пометить ответы в `plan.md` Risk/Mitigation секции (заменить «TBD» на факты). depends: ничего.
  - **Ответы:** (а) `scripts/infrastructure/event_bus.gd`, autoload, snake_case past-tense. (б) `HexPathfinder` создаётся в `HexGrid` как `_pathfinder := HexPathfinder.new()` (поле). `build()` вызывается из `HexGrid._build_pathfinder()` после `_effect_registry.load_from_dir`. Registry инжектится через новый метод `set_object_registry(reg)` ДО `build()`. Также добавляется helper `HexGrid._is_tile_passable(tile)` и заменяет проверки `tile.walkable` в 5 местах (`_get_walkable_neighbours`, `is_walkable`, `get_all_walkable_coords`, `place_actor`, `move_actor` / `step_actor`-проверки `to`). (в) Custom data layer `"object_id"` типа String в TileSet **отсутствует** — добавить руками в editor (T005a). До этого все `object_id = &""`, registry-ноль, всё работает как сейчас.

## Группа B — код core

- [x] **T002** [P1] `scripts/core/arena/tile_object.gd` — NEW. Pure data class по плану §"TileObject API". Без логики, без сигналов. depends: T001.
- [x] **T003** [P1] `scripts/core/arena/tile_object_registry.gd` — NEW. Копировать структуру `tile_effect_registry.gd`, добавить `_validate_and_normalize` per AC-O2 правилам. depends: T002.

## Группа C — интеграция с arena (трогает файлы Egor — coord required)

- [x] **T004** [P1] `scripts/core/arena/hex_tile.gd` — добавить `var object_id: StringName` и параметр в `_init` с default `&""`. Никаких других правок. depends: T002.
- [x] **T005** [P1] `scripts/core/arena/hex_grid.gd` — в `_build_tile_map` читать custom data layer `"object_id"`, передавать в `HexTile._init`. Создать инстанс `TileObjectRegistry`, вызвать `load_from_dir("res://data/tile_objects/")`. depends: T003, T004.
  - **T005a** [P1] [P] Проверить (T001) что в TileSet есть custom data layer `"object_id"` типа String. Если нет — добавить руками в Godot editor (TileSet inspector → Custom Data → +). Это не код-задача. Делает Sergey локально перед F5.
  - **DONE (Andrey, текстом):** добавлен слой `custom_data_layer_4` в `scenes/arena/tilesets/hex_terrain.tres`. Тип `21` (StringName) — консистентно с `effect_id` и `tile_kind`. Existing атлас-тайлы не имеют значения для этого слоя → получают default `&""` → `HexTile.object_id = &""` → registry-noop. Backward-compat сохранён. Painting объектов на конкретные ячейки TileMap-а — отдельный шаг дизайнера в редакторе (для smoke-сцены или production-арены).
- [x] **T006** [P1] `scripts/core/arena/hex_pathfinder.gd` — добавить query в registry в проверке проходимости. Точное место — по результату T001. depends: T003, T005.

## Группа D — EventBus (опционально, по результату T001)

- [x] **T007** [P1] EventBus файл (путь по T001) — добавить 3 сигнала per AC-O7. Если EventBus отсутствует — открыть как **отдельную мини-фичу** перед 018 (тогда T007 → блокер; иначе ловушка по архитектуре). depends: T001.

## Группа E — content (parallel после T003)

- [x] **T008** [P2] [P] `data/tile_objects/_schema.md` — schema doc для Стасяна. Описывает все поля, их типы, дефолты, ограничения по level. depends: T003.
- [x] **T009** [P2] [P] `data/tile_objects/mountain.json` — ELEVATION, no behavior, no destructible. depends: T003.
- [x] **T010** [P2] [P] `data/tile_objects/lava_pool.json` — SMALL walkable=true, behavior=damage_zone, `applies_on_enter=true`, `applies_on_turn_end=true`, `aura_radius=0`, `applies_on_attacked=false`, `linger_effect_id="burning"`, tags=[liquid, hazard]. depends: T003.
- [x] **T010b** [P2] [P] `data/tile_effects/burning.json` — NEW tile_effect: `kind: "damage", amount: 2, duration: 2, applies_to: ["player", "enemy"]`. Расширение TileEffectRegistry для парсинга `duration` int (default 0 — backward-compat). depends: T003.
- [x] **T011** [P2] [P] `data/tile_objects/heal_fountain.json` — LARGE, behavior=heal_fountain, `aura_radius=1`, остальные триггеры false, `linger_*` пустые, not breakable. depends: T003.
- [x] **T012** [P2] [P] `data/tile_objects/wooden_barrel.json` — SMALL non-walkable, breakable hp=2, tags=[wood, flammable], on_destroy_effect_id=damage_zone. depends: T003.
- [x] **T013** [P2] [P] `data/tile_objects/wooden_table.json` — SMALL non-walkable, breakable hp=2, tags=[wood, furniture, flammable], no behavior. depends: T003.
- [x] **T014** [P2] [P] `data/tile_objects/boulder.json` — LARGE, breakable hp=10, armor_tags=[physical], no behavior. depends: T003.

## Группа F — dev smoke

- [x] **T015** [P1] `scenes/dev/tile_objects_smoke.tscn` — NEW dev-сцена. **Скоуп урезан:** без TileMap-painting, т.к. T005a (custom data layer в TileSet) — manual editor-step. Сцена грузит обе registry, дампит все 6 объектов + verify `burning.duration=2`, подписывается на 4 новых EventBus сигнала, F1–F4 эмитят их вручную для smoke. После T005a + покраски TileMap-а в редакторе можно дополнить сценой HexGrid + actors. depends: T005, T009-T014, T005a.
- [ ] **T016** [P1] *manual: Sergey* — F5 на `tile_objects_smoke.tscn`, прогнать AC-O8 чек-лист (см. plan §Тестирование). Записать в `tasks.md` под T016 — pass/fail и что отвалилось. depends: T015.

## Группа G — doc / coord

- [x] **T017** [P3] [P] Обновить root `CLAUDE.md` ownership table: добавить строку «Tile objects (data + registry) — Sergey» в подходящее место. Или, если ownership уже разбит по модулям — упомянуть в `Spell-craft, modifier engine | Sergey` строке расширение скоупа. depends: T002 концептуально.
- [x] **T018** [P3] [P] `HANDOFF.md` — упомянуть 018 в «текущие специ» / соответствующей секции (точное место — по результату чтения HANDOFF при implement). depends: T002.

## Группа H — push + PR

- [ ] **T019** [P1] Commit messages:
  - `feat(018): TileObject data class + registry`
  - `feat(018): HexTile.object_id + HexGrid wiring + Pathfinder integration`
  - `feat(018): EventBus signals for tile object events`
  - `content(018): 6 sample tile objects + schema doc`
  - `docs(018): CLAUDE.md/HANDOFF.md update`
  - `dev(018): tile_objects_smoke scene`
  
  6 коммитов, в порядке зависимости. Не один большой — фича крупная, ревью Egor'у легче по частям.
  
  Push `sergey/spec-018-tile-objects` → origin. depends: T016.

- [ ] **T020** [P1] *manual: Sergey* — открыть PR `sergey/spec-018-tile-objects → staging` в браузере по URL из push output (Claude не может через api.github.com). В описании:
  - Линк на `specs/018-tile-objects/spec.md`.
  - **Tag Egor** primary reviewer (трогаются `hex_tile.gd`, `hex_grid.gd`, `hex_pathfinder.gd`).
  - Tag Стасян для review schema doc и sample JSON-ов.
  - Указать решения OQ-1/2/3: A (aura) / C+linger / A — все зафиксированы в spec.md.
  - Упомянуть зависимость от actor-status фичи (linger no-op до её появления — это by design, см. AC-O9).
  
  depends: T019.

## Группа I — post-merge

- [ ] **T021** [P3] *manual: Sergey* — после merge в staging: пинг Стасяну «018 в staging, можешь добавлять tile objects через JSON, схема в `data/tile_objects/_schema.md`». depends: T020 + merge.
- [ ] **T022** [P3] *manual: Sergey* — после 018 merge: запланировать **`019-tile-object-resolver`** (мой скоуп) — runtime-триггеры: подписка на EventBus сигналы, применение `behavior_effect_id` per флагам, применение `linger_effect_id` с duration при `tile_object_actor_exited`, aura-тик в turn system. Без resolver'а 018 — данные без поведения. depends: T020 + merge.

---

## Заметки для Клода если возьмёт implement

- **Перед стартом:** перечитать `spec.md` на предмет зафиксированных ответов на OQ-1/2/3. Если default A/A/A — идём как написано. Если что-то другое — сначала обновить `plan.md` секции [DEPENDS-OQ-X], потом T-задачи.
- **T001 — обязательно первой.** Без него весь plan имеет TBD. Не пропускать.
- **T002-T003** — atomic пара, в одном коммите. Это `feat(018): TileObject data class + registry`.
- **T004-T006** — отдельный коммит, потому что трогает Egor'овы файлы и diff там имеет значение для ревью.
- **Sample JSON-ы (T009-T014)** — копируй формат `data/tile_effects/heal_fountain.json` как стартовую точку, добавляй новые поля по schema.
- **HexTile `_init`** — НЕ менять порядок существующих параметров. Новый параметр `p_object_id` строго последним с default `&""`. Иначе сломается всё что вызывает `HexTile.new(...)`.
- **TileObjectRegistry** — точная копия паттерна `tile_effect_registry.gd`. Не пытайся «улучшить» (нагрянет CLAUDE.md §Architecture pillars: «Don't propose abstractions for the future»).
- **T015 (smoke scene)** — Godot из container не запустить (нет GUI). Сцену создаём в Claude (текстовый .tscn рисуем по примеру в `scenes/dev/`), F5 делает Sergey локально.
- **T020 PR URL** — `git push -u origin sergey/spec-018-tile-objects` вернёт PR-creation URL в stderr. Захватить и отдать Sergey verbatim.
- **api.github.com заблокирован** — никаких попыток открыть PR через `gh`/curl. Только git push, остальное — Sergey в браузере.

## История правок

- 2026-05-01 — draft v1, заблокирован OQ-ответами.
- 2026-05-02 — v2: OQ gate снят; flag-based триггеры; linger через linger_status_id (actor-status dep).
- 2026-05-02 — v3: linger упрощён — `linger_effect_id` → tile_effect с `duration`. T010 обновлён, добавлен T010b (burning.json + duration-парсинг в TileEffectRegistry). Actor-status dependency убрана. T022 упрощён до одной follow-up фичи.
