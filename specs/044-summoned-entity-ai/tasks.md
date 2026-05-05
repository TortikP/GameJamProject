# 044-summoned-entity-ai — tasks

Порядок: сначала независимые блоки (selector + JSON), потом driver/telegraph (требуют smoke). Между блоками — компиляция в Godot и ручной запуск, чтобы поймать regressions точечно.

## T1 — Selector

- [x] T1.1: Создать `scripts/core/ai/selectors/selector_nearest_empty_hex_to_enemy.gd` по шаблону из plan.md §1. AC-S1..S7.
- [x] T1.2: Добавить регистрацию в `scripts/core/ai/behavior_database.gd` `_build_selector` (после `unclaimed_hex_near_enemy`):
      ```
      "nearest_empty_hex_to_enemy": return SelectorNearestEmptyHexToEnemy.new()
      ```
- [ ] T1.3: Запустить Godot, убедиться что нет parse-error'а (autoload поднимается чисто), `BehaviorDatabase` логирует `loaded N scenarios` без warn'ов про новый ключ.

## T2 — JSON content

- [x] T2.1: Edit `data/ai_behaviors/default_melee.json` — prepend summon-rule (plan.md §3). AC-J1.
- [x] T2.2: Создать `data/ai_behaviors/default_ranged.json` (plan.md §3). AC-J2.
- [x] T2.3: `git rm data/ai_behaviors/default_range.json`. AC-J4.
- [x] T2.4: Grep `git grep '"default_range"'` — пусто (только spec/tasks references).
- [ ] T2.5: Запустить Godot godmode-сцену → BehaviorDatabase логирует `default_melee`, `default_ranged` загружены, нет warn'ов «scenario missing 'id'» / «unknown target_selector kind».

## T3 — Driver filter

- [x] T3.1: Edit `scripts/presentation/godmode/ai_driver.gd` `replan_all_and_refresh()` — заменить team-фильтр на `actor != _ctrl.player`. AC-D1/D2.
- [x] T3.2: Edit `_run_enemy_turn()` — то же самое. AC-D1.
- [x] T3.3: Обновить doc-комментарии метода (упоминание «enemies» → «AI-controlled world actors» где уместно). Метод-имя оставить (AC-D3).
- [ ] T3.4: Smoke 1 — godmode без player-summon'ов: запустить, заспавнить manekin'ов, провернуть 5 ходов. Поведение enemies должно быть идентично pre-PR (детерминистика scenario'ев + порядок registry.all() сохранён). AC-D5.

## T4 — Telegraph filter

- [x] T4.1: Edit `scripts/presentation/godmode/telegraph_renderer.gd` `refresh()` — заменить team-фильтр на `actor == _ctrl.player`. AC-T1.
- [ ] T4.2: Smoke 2 — повторить smoke 1, проверить что telegraph для enemies рендерятся как раньше. AC-T2.

## T5 — Smoke: player-side summon

- [ ] T5.1: В godmode-сцене — добавить `summon_bee` в slot bar (через editor / dev panel / manekin spawner — что доступно). Заспавнить manekin'а как target.
- [ ] T5.2: Кастануть `summon_bee` на пустой hex в радиусе 3. Проверить:
  - Bee появилась с `team=player` (ActorInspector / debug overlay).
  - HP-bar и overhead-надписи рендерятся как у enemies (= общий рендер-путь). Если визуально неотличима — flag в HANDOFF, но не блокер.
- [ ] T5.3: Завершить ход → world_turn_ended:
  - В Phase 2 (PLAN) bee получает intent (либо summon target_coord, либо damage target_id).
  - В Phase 1 (RESOLVE) на следующем ходу — bee движется и/или кастует.
- [ ] T5.4: AC-B1 пройден: повторить 3-5 ходов, watch logs (`AI` / `CreateEffect` каналы) — нет warn / error.
- [ ] T5.5: Проверить chain summon: если bee'и саммонят bee'й → счётчик растёт, нет ID-collision warn'ов (за это отвечает 041 `_summon_counter` static).

## T6 — Smoke: enemy-side summoner

- [ ] T6.1: Запустить wave с `burning_bear`. Если waves-конфиги не имеют такой записи — заспавнить через ManekinSpawner (если поддерживает enemy_id).
- [ ] T6.2: Watch ход 1: bear использует `burning_bear_summon_bear` (на cooldown=5 первый каст fires). Bear-актёр спавнится в radius=−1 (unbounded) от bear'а, ближайший ring к player'у.
- [ ] T6.3: AC-B4: после summon bear переходит на ranged-фолбек на след. ходах.
- [ ] T6.4: Дать bee'е (отдельный manekin / wave) попробовать саммон в default_melee. AC-B5.

## T7 — Smoke: edge cases

- [ ] T7.1: AC-B2 — пустая арена с player + одной bee'ей: bee саммон fizzles (нет врагов) → damage rule fizzles → hold. Watch logs — `no action this turn (no anchor)` info.
- [ ] T7.2: AC-B3 — заполнить radius=1 от player'а manekin'ами, заспавнить burning_bear подальше: bear саммонит на radius=2+ кольце.
- [ ] T7.3: AC-B6 — player-bee + enemy-bee на одной арене: обе саммонят свои bee'и, не падают, телеграфы рендерятся.

## T8 — HANDOFF + closure

- [ ] T8.1: Создать `specs/044-summoned-entity-ai/HANDOFF.md` с:
  - Smoke results (что прошло, что красное).
  - Findings / known issues (например: одинаковые цвета телеграфов; chain-summon экспоненциал — заметки для Стасяна).
  - Cross-branch warning про rename `default_range.json`.
- [ ] T8.2: Marked `[x]` все таски.
- [ ] T8.3: Push, открыть PR `egor/044-summoned-entity-ai → staging`. PR-описание ссылается на spec.md, перечисляет AC.
- [ ] T8.4: Передать PR-URL Egor'у для review.

## Dependencies

- T1 → T2 (JSON ссылается на ключ, который регистрирует T1.2).
- T2 → T3/T4 (без сценариев driver-loop спокойно работает на pre-rename `default_range`, но интегральный smoke невозможен).
- T3 ⟂ T4 (independent, can be in any order; both feed T5/T6).
- T5/T6 → T8 (smoke validates AC-B*, then HANDOFF).

## Out-of-scope reminders (см. spec §Scope-граница)

- Не создаём `default_caster.json`.
- Не различаем визуал телеграфов player vs enemy team.
- Не вводим `summoner_*` сценарии.
- Не балансируем cooldown / chain-cap.
