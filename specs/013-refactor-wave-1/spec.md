# 013-refactor-wave-1 — combat-feedback wiring + F6 keybind

**Owner:** Andrey (per `specs/012-ultrareview/findings.md` AC-A5 cluster).
**Implementer:** Egor (override of AC-A5 owner-implements rule, granted in chat).
**Status:** Active.

## Назначение

Фиксы трёх P1-finding'ов из 012 — все в кластере «combat-feedback wiring» + одна зацепленная collision F6.

Без этих фиксов нарушены:
- **Pillar 1 (full information visibility)** — игрок не видит ни floating combat numbers, ни combat log при битве; обе подписки висят на несуществующих сигналах EventBus.
- **010/AC** — F6 как тоггл CrtPostFx «в любой сцене» не работает в godmode, потому что godmode_controller перехватывает F6 первым через `set_input_as_handled()` и кастует test_vamp_strike.

## Findings — что закрываем

| ID | Sev | Файл | Что не работает |
|---|---|---|---|
| F-001 | P1 | `scripts/presentation/godmode/godmode_controller.gd:368-373` + `scripts/presentation/crt/crt_post_fx.gd:25` | F6 перехвачен godmode debug-cast'ом, CrtPostFx тоггл не срабатывает в godmode. |
| F-002 | P1 | `scripts/presentation/floating_number_layer.gd:21-22,38-50` | Подписан на `EventBus.damage_dealt` / `heal_done` — обоих сигналов нет, layer пустой. |
| F-003 | P1 | `scripts/presentation/combat_log.gd:23,25` | Та же мёртвая подписка — combat_log пустой. |

Бонус: F-006 (P2, было запланировано в 014c) закрывается автоматически — `_resolve_actor_pos` parent-walk удаляется, `world_pos` приходит в payload сигнала.

## Acceptance criteria

- **AC-1 (F-001):** в godmode F6 переключает CRT (видно в логе `CrtPostFx toggled ON/OFF`). Standalone debug-cast хоткей удалён вместе с `_debug_cast_test_skill()` — RMB-assign на QWER слот покрывает потребность; `data/skills/test_vamp_strike.json` остаётся как тестовый skill.
- **AC-2 (F-002):** при ударе по manekin'у в godmode над целью спавнится floating number с цветом `UiTheme.SEM_DAMAGE` и знаком `−`. Хил спавнит `+` с `UiTheme.SEM_HEAL`.
- **AC-3 (F-003):** при ударе/хиле строка появляется в `CombatLog` (открывается на L). Цвет соответствует semantic-токену.
- **AC-4 (EventBus contract):** добавлены два сигнала
  - `damage_dealt(target_id: StringName, amount: int, world_pos: Vector2)`
  - `heal_done(target_id: StringName, amount: int, world_pos: Vector2)`
  Эмитятся из `Actor.take_damage` и `Actor.heal` (positive amount only). `world_pos = self.global_position`.
- **AC-5 (no extra scope):** не трогаются `Actor.damaged` (legacy сигнал остаётся), `status_applied` (ждёт status engine, lazy-bind в combat_log не пересматривается), F-014 (skill_cast empty target_ids — это 014).
- **AC-6 (CLAUDE.md hard rule check):** новые сигналы — snake_case past tense, EventBus only, no inline `Color(...)`, no bare `create_timer`, no hardcoded content. Все слова из § Hard rules выполнены.

## Out of scope

- F-004/F-005 (Actor/HexGrid extends Node2D — P2 architecture, 014a).
- F-006 (parent-walk for actor pos) — закрывается побочно, but формально logged как «closed via 013».
- Status_applied wiring (ждёт status engine, не моя зона как 013).
- Manual profiler pass AC-A9 from 012 (отдельная задача Егора — не код-фикс).

## Зависимости

- **Upstream:** `andrey/012-audit-pass` мержен (PR #37), findings.md в staging — ✓.
- **Downstream:** 014c уменьшается на 1 finding (F-006 закрыт здесь).
