# 041-effect-create-entity — tasks

См. `spec.md` (acceptance) и `plan.md` (HOW).

## Phase 1 — Schema + status definition

- [ ] T001 [P1] `data/status_effects/summoned.json` — NEW. id=summoned, family=neutral, arity=1, param_names=[duration]. См. spec §3.
- [ ] T002 [P1] `scripts/core/statuses/runtimes/summoned_runtime.gd` — NEW. `class_name SummonedRuntime extends StatusRuntime`. Только `compute_snapshot` + `on_remove` per plan §"SummonedRuntime — целиком".
- [ ] T003 [P1] `scripts/core/statuses/status_registry.gd` — добавить `&"summoned": preload("res://scripts/core/statuses/runtimes/summoned_runtime.gd")` в `_RT_BY_ID`. (depends T002)
- [ ] T004 [P1] `scripts/infrastructure/event_bus.gd` — `signal tile_object_summoned(coord: Vector2i, object_id: StringName, duration: int)` в секции "Tile Objects".

## Phase 2 — Public API exposing

- [ ] T005 [P1] `scripts/core/maps/level_loader.gd` — `enemy_data_exists(enemy_id: StringName) -> bool` public alias на `_enemy_data_exists`. (приватный остаётся, чтоб не ломать внутренние вызовы; новый — public delegator).
- [ ] T006 [P1] Smoke сборки: запустить godmode из редактора → no parse errors, summoned status mentioned in StatusRegistry init log. (depends T001-T004)

## Phase 3 — Parser changes

- [ ] T007 [P1] `scripts/core/abilities/ability_database.gd` — `_make_effects_from_dict`, ветка для `key == "entity_id"`. Парсит через `_parse_status_string`, arity=1, проверяет `duration != 0`. Per plan §"Парсер: entity_id". На malformed/missing — warn + skip create-effect (skill всё равно грузится). (depends T006)
- [ ] T008 [P1] `scripts/core/abilities/ability_database.gd` — добавить `entity_id` в exclude-list generic-broadcast loop (line ~268, where `if k == "kind" or k == "status" or k == "status_id" or k == "duration"`). Per plan §"Removed key from generic broadcast filter". (depends T007)
- [ ] T009 [P1] `scripts/core/abilities/effects/create_effect.gd` — добавить `@export var duration: int = 0`. CreateEffect.entity_id остаётся. Чистка stub-логики из `apply` (заменим в Phase 4). (depends T007)

## Phase 4 — CreateEffect runtime

- [ ] T010 [P1] `scripts/core/abilities/effects/create_effect.gd` — полная replace `apply` per plan §"CreateEffect — целиком". Поля: caster, ctx, two-branch resolution (object first, actor fallback), team override. Static `_summon_counter = 9999` per plan §R4. (depends T005, T009)
- [ ] T011 [P1] `scripts/core/abilities/effects/create_effect.gd` — `_validate_id_collisions_once(grid)` static + storage `_collision_check_done_for: Dictionary`. Вызов в начале `apply`. Per plan §"Boot-time id collision check". (depends T010)

## Phase 5 — Actor + Resolver wiring

- [ ] T012 [P1] `scripts/core/actors/actor.gd` — `tick_statuses_with_ctx`: добавить `if inst.duration < 0: continue` per plan §"Actor.tick_statuses_with_ctx — diff". 1 line surgery.
- [ ] T013 [P1] `scripts/core/arena/tile_object_resolver.gd` — добавить `_summon_timers: Dictionary` field; method `add_summon_timer(coord, duration)`; method `_tick_summon_timers()`; method `_on_tile_object_destroyed_summon_cleanup(coord, _obj_id)`; в `_connect_signals` после existing — `EventBus.tile_object_destroyed.connect(_on_tile_object_destroyed_summon_cleanup)`; в `_on_player_turn_ended` после `_tick_linger_stacks()` — вызов `_tick_summon_timers()`. Per plan §"TileObjectResolver — добавления".

## Phase 6 — ctx wiring

- [ ] T014 [P1] `scripts/presentation/godmode/cast_fsm.gd` — site 1 (~line 87, `try_start`): добавить `actors_node` и `resolver` в pre_ctx. Per plan §"ctx wiring".
- [ ] T015 [P1] `scripts/presentation/godmode/cast_fsm.gd` — site 2 (~line 133, `_commit_step`): добавить те же два ключа.
- [ ] T016 [P1] `scripts/presentation/godmode/godmode_input.gd` — line ~191: добавить `actors_node` + `resolver`. Если `_ctrl` ref недоступен в этом scope — пробросить через caller (cast_fsm уже передаёт, или брать через grid.get_parent()).
- [ ] T017 [P1] `scripts/presentation/godmode/ai_driver.gd` — line ~239 (skill cast ctx): добавить `actors_node` + `resolver`. **НЕ** трогать `world_ctx` (line 36).

## Phase 7 — Migration sample skills

- [ ] T018 [P1] `data/skills/summon_bee.json` — `"entity_id": "bee"` → `"entity_id": "bee(3)"`.
- [ ] T019 [P1] `data/skills/bee_summon_bee.json` — то же.
- [ ] T020 [P1] `data/skills/teapot_spill_the_t.json` — то же. Если duration отличается от 3 — спросить Stasyan / себе zoom; default 3.
- [ ] T021 [P1] `grep -rn '"entity_id":' data/skills/ | grep -v '("` — verify нет других bare-id summon'ов. (depends T018-T020)

## Phase 8 — Smoke tests

- [ ] T022 [P1] Smoke #1 (object summon + expire) per plan §"Test plan". Edit `summon_bee` → `wooden_barrel(3)`. Cast. Проверить лог `summoned object 'wooden_barrel' at ... for 3 turns`, потом 3 turn'a → `expired` + `destroyed`. (depends T010, T013)
- [ ] T023 [P1] Smoke #2 (object early destroy) — barrel(5), break на 2-м ходу, убедиться что нет повторного destroy на 5-м. (depends T022)
- [ ] T024 [P1] Smoke #3 (actor summon + team) — `bee(3)` cast'нуть, ActorInspector на спавненную bee → team=`player`, bee атакует enemies. После 3 ходов — `actor_died` для bee. (depends T010)
- [ ] T025 [P1] Smoke #4 (actor early death) — `bee(5)` cast, kill manually на 2-м ходу, на 5-м ходу нет повторного take_damage в логе. (depends T024)
- [ ] T026 [P1] Smoke #5 (infinite) — edit summon to `bee(-1)`. Cast. 10 turns spectated → bee жив, `_statuses["summoned"].duration == -1`. Manual kill — стандартный путь. (depends T012, T024)
- [ ] T027 [P1] Smoke #6 (multi-hex area) — edit summon area на `zone_circle area_radius=1`. Cast в пустую группу — несколько bees. Если в зоне есть occupied хексы — там skip без crash. (depends T024)
- [ ] T028 [P2] Smoke #7 (unknown id) — edit `entity_id: "nonsense(3)"` → cast → warn лог + no spawn + no crash. (depends T010)
- [ ] T029 [P2] Smoke #8 (malformed) — edit `entity_id: "bee"` без скобок → boot warn `malformed entity_id 'bee'`, skill грузится, cast — no create-effect. (depends T007)
- [ ] T030 [P2] Smoke #9 (id collision) — создать `data/tile_objects/manekin.json` (или временный duplicate id) → cast любого summon → один warn `id collision: 'manekin'`. Удалить тестовый файл после. (depends T011)
- [ ] T031 [P2] Smoke #10 (AI replan after summon) — cast `bee(3)` рядом с manekin → manekin на следующий turn планирует против bee'и (или игнорирует — зависит от AI tactic), но не игнорирует факт нового actor'а. (depends T024)

## Phase 9 — Bookkeeping

- [ ] T032 [P1] `CLAUDE.md` "Currently claimed" — добавить строку `| 041-effect-create-entity | Egor |`.
- [ ] T033 [P2] Если в smoke #1 обнаружен pathfinder bug (R1) — добавить `grid.rebuild_pathfinder()` в `_spawn_object` после `set_tile_object_id`. Иначе skip task.

## Cut list

См. plan §"Cut list". Default ship — без cut'ов.

## Out-of-tasks notes

- `summoned` family color (neutral vs debuff) — UI-полиш отдельным спеком.
- `-1` rendering в StatusIconStrip (показывать ∞ или скрыть цифру) — UI-полиш отдельным спеком.
- Save/load статусов и summon timers — нет save системы вообще, не в скоупе.
