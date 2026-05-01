# 013-refactor-wave-1 — tasks

Sequential. Один коммит = один блок.

## A — F-001 (F6 keybind)

- [x] A1. `scripts/presentation/godmode/godmode_controller.gd:370` — `KEY_F6` → `KEY_F8`.
- [x] A2. `scripts/presentation/godmode/godmode_controller.gd:136` — startup log: добавить `F8=debug-cast`.
- [x] A3. Manual: F5, F6 переключает CRT, F8 кастует. Лог сверить. (deferred to Egor manual run)
- [x] A4. Commit: `feat(013): F-001 — move godmode debug-cast F6 → F8`.

## B — F-002 + F-003 (EventBus signals + Actor emit + receiver wiring)

- [x] B1. `scripts/infrastructure/event_bus.gd` — добавить блок Combat feedback с `damage_dealt(target_id, amount, world_pos)` и `heal_done(target_id, amount, world_pos)` после `actor_died`.
- [x] B2. `scripts/core/actors/actor.gd:73` — после `damaged.emit(...)` в `take_damage`: `EventBus.damage_dealt.emit(actor_id, amount, global_position)`.
- [x] B3. `scripts/core/actors/actor.gd:92` — после `damaged.emit(...)` в `heal`: `EventBus.heal_done.emit(actor_id, healed, global_position)`.
- [x] B4. `scripts/presentation/floating_number_layer.gd` — handlers принимают `world_pos: Vector2` 3-м аргументом, `spawn(to_local(world_pos), ...)`.
- [x] B5. `scripts/presentation/floating_number_layer.gd` — удалить `_resolve_actor_pos()` (lines 61-73).
- [x] B6. `scripts/presentation/floating_number_layer.gd` — обновить шапочный комментарий (строки 7-10).
- [x] B7. `scripts/presentation/combat_log.gd` — handlers принимают `_world_pos: Vector2` 3-м аргументом (имя с подчёркиванием = ignore).
- [x] B8. `scripts/presentation/combat_log.gd` — обновить шапочный комментарий (lines 5-6).
- [x] B9. Manual: F5, спавн manekin (F1), select player → ЛКМ по manekin'у с активным slot 0 (skill_debug_punch). Floating `-N` появилась + строка в combat log (L). (deferred to Egor manual run)
- [x] B10. Commit: `feat(013): F-002+F-003 — EventBus damage_dealt/heal_done + Actor emit + receivers`.

## C — Closeout

- [x] C1. Отметить все [x] в этом файле.
- [x] C2. ~~Записать в `spec.md` под Acceptance criteria, что AC-1..AC-6 выполнены~~ — нет, не нужно, AC просто исполнены кодом, в спеке не отмечаем (это плана дело).
- [x] C3. Commit `docs(013): mark tasks [x]`.
- [ ] C4. Push, отдать PR-URL Andrey'ю / Егору в чат.

## Зависимости

- B1 → B2 → B3 → B4/B7 (parallel) → B5/B6/B8 (parallel) → B9 → B10.
- A независим, можно делать первым.
