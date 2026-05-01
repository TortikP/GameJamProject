# 019-tile-object-resolver — tasks

**Spec:** [`spec.md`](./spec.md) · **Plan:** [`plan.md`](./plan.md)

Легенда: `[P1]` критический путь · `[P2]` опционально · `[P3]` doc/coord

---

## Группа A — код

- [x] **T001** [P1] `scripts/core/arena/hex_grid.gd` — добавить 3 публичных метода: `get_tile_object_id`, `set_tile_object_id`, `get_all_tile_object_ids`. Аддитивно. depends: ничего.
- [x] **T002** [P1] `scripts/core/arena/tile_object_resolver.gd` — NEW. Полная реализация: `setup()`, `_connect_signals()`, `_on_tile_entered`, `_on_player_turn_ended`, `_on_tile_object_actor_exited`, `_tick_turn_end_effects`, `_tick_aura_effects`, `_tick_linger_stacks`, `damage_object`, `_destroy_object`, `_apply_effect_to_actor`. depends: T001.

## Группа B — docs

- [x] **T003** [P3] `specs/019-tile-object-resolver/spec.md` + `plan.md` + `tasks.md` — этот файл. depends: ничего.

## Группа C — commit + push

- [x] **T004** [P1] Commit 1: `feat(019): HexGrid get/set_tile_object_id + get_all_tile_object_ids`
- [x] **T005** [P1] Commit 2: `feat(019): TileObjectResolver — runtime trigger engine`
- [x] **T006** [P1] Commit 3: `docs(019): spec/plan/tasks`
- [x] **T007** [P1] `git push -u origin andrey/spec-019-tile-object-resolver` → взять PR URL из stderr, дать Andrey.

## Группа D — post-merge (manual)

- [x] **T008** [P2] *manual: Andrey* — в godmode_controller добавить `TileObjectResolver` по паттерну из plan.md. Smoke: шаг в lava_pool → damage лог. **DONE в этой сессии.**
- [ ] **T009** [P3] *manual: Sergey* — вызвать `resolver.damage_object(coord, amount, caster_id)` из spell/ability resolve path когда цель — тайл с объектом.
- [ ] **T010** [P3] *manual: Egor* — review 3 методов в `hex_grid.gd` (аддитивно, не ломает API).
