# 004-godmode-base — tasks

Один таск — один логический шаг. `[P]` = можно делать параллельно с предыдущим, `[depends Tnnn]` = строгая зависимость. Приоритеты: все P1, кроме F2 и hot-reload (P2).

- [x] T001 [P1] EventBus: добавить 4 сигнала (`player_turn_ended`, `world_turn_ended`, `ability_cast`, `actor_died`). `scripts/infrastructure/event_bus.gd`. Additive.
- [x] T002 [P1] TurnManager autoload. `scripts/core/turn/turn_manager.gd`. Регистрация в `project.godot`. API: `current() -> int`, `advance() -> void`. Сигналы — через EventBus. (depends T001)
- [x] T003 [P1] Actor base. `scripts/core/actors/actor.gd`. Node2D, поля `actor_id`, `max_hp`, `hp`. Методы `take_damage(amount)`, сигналы `died`/`damaged`. Эмитит `EventBus.actor_died` на смерти. (depends T001)
- [x] T004 [P1] [P] ActorRegistry. `scripts/core/actors/actor_registry.gd`. Node, scene-local. API: `register/unregister/get_actor/get_at(grid, coord)`. (depends T003)
- [x] T005 [P1] Ability контракт — три абстрактных Resource: `ability_target.gd`, `ability_effect.gd`, `ability_modifier.gd` в `scripts/core/abilities/`. Виртуальные методы по `plan.md` §5.
- [x] T006 [P1] Ability composition class. `scripts/core/abilities/ability.gd`. Resource: target/effect/modifiers + `cast(caster, ctx)`. Реализация цикла `before_apply → apply × N → after_apply × N → after_cast` ровно по THEME_PLAN §4. (depends T005, T001)
- [x] T007 [P1] [P] SingleEnemyTarget. `scripts/core/abilities/targets/single_enemy_target.gd`. Резолв через `ctx.registry.get_actor(ctx.target_id)`. (depends T004, T005)
- [x] T008 [P1] [P] DamageEffect. `scripts/core/abilities/effects/damage_effect.gd`. `@export var amount: int`. `apply()` → `target.take_damage(amount)`. (depends T003, T005)
- [x] T009 [P1] AbilityDatabase autoload. `scripts/core/abilities/ability_database.gd`. Загружает `data/abilities/*.json`, парсит в `Ability` Resource через kind-реестры. API: `get_ability(id) -> Ability`. Регистрация в `project.godot`. (depends T006, T007, T008)
- [x] T010 [P1] [P] `data/abilities/debug_punch.json` — пример из `plan.md` §6: `{id, single_enemy, damage(5), []}`. (depends T009)
- [x] T011 [P1] Manekin scene + script. `scripts/presentation/godmode/manekin_view.gd` (расширяет Actor) + `scenes/dev/manekin.tscn` — Node2D + Polygon2D (красный гекс r=16). max_hp=20. (depends T003)
- [x] T012 [P1] [P] TurnCounter UI. `scripts/presentation/godmode/turn_counter.gd` (extends Label). Слушает `EventBus.world_turn_ended`. Текст `"Turn: N"`. (depends T001, T002)
- [x] T013 [P1] [P] SlotBar UI. `scripts/presentation/godmode/slot_bar.gd` + сцена `scenes/dev/slot_bar.tscn`. 4 SlotButton (Button + Label). API: `set_slot/get_slot/set_active/get_active`. Сигнал `slot_activated(index)`. Подсветка активного. (depends T006)
- [x] T014 [P1] project.godot input actions: `cast_slot_0..3` (QWER + 1234), `godmode_spawn_dummy` (F1), `godmode_clear` (F2). См. `plan.md` §11.
- [x] T015 [P1] config/game_speed.cfg: добавить секцию `[godmode]` с `ability_cast_delay`. (см. `plan.md` §10)
- [x] T016 [P1] GodmodeController. `scripts/presentation/godmode/godmode_controller.gd`. Резолв нод, инпут, спавн манекенов, каст слотов. RMB-move по тику. (depends T002,T004,T009,T011,T012,T013,T014)
- [x] T017 [P1] Godmode scene. `scenes/dev/godmode.tscn`. Структура: `Node2D/HexGrid (instance hex_grid.tscn) / GodmodeController / ActorRegistry / CanvasLayer/HUD (TurnLabel + SlotBar) / Actors/Player`. Скрипт `hex_placeholder_builder.gd` — не использую, рисую сетку из контроллера (как arena_demo_controller, но проще). (depends T016)
- [x] T018 [P1] main.gd: добавить кнопку "Godmode" → change_scene_to_file. Не ломать существующую "Arena Demo".
- [x] T019 [P1] Smoke-test plan: ручной чеклист в `specs/004-godmode-base/SMOKE.md` — 7 пунктов из spec.md "Acceptance verification". Прогнать, отметить.
- [ ] T020 [P2] F5 hot-reload `game_speed.cfg` тестирован в Godmode. (depends T017)
- [x] T021 [P2] Push ветку, запостить URL для PR. (depends T019)
