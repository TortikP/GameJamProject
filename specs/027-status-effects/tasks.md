# 027-status-effects — tasks

**Owner:** Egor
**Spec/Plan:** `spec.md`, `plan.md`

Чек-лист в порядке зависимостей. `[ ]` → `[x]` по факту коммита.

## A. Контракты данных (no-deps, делается первым)

- [ ] **A1.** Создать `scripts/core/statuses/status_instance.gd` —
  `class_name StatusInstance extends Resource`, поля
  `status_id / duration / args / source_id / snapshot_value / rt_flag`
  (см. plan §"StatusInstance").
- [ ] **A2.** Создать `scripts/core/statuses/status_runtime.gd` —
  abstract base со static-методами `compute_snapshot / on_turn_start /
  modify_speed / damage_reduction / override_movement /
  override_cast_target` (defaults как в plan).
- [ ] **A3.** Создать 9 runtime-классов в `scripts/core/statuses/runtimes/`:
  - [ ] `stunned_runtime.gd` — defaults
  - [ ] `slowed_runtime.gd` — `modify_speed = floor(s/2)`,
        `override_movement` с rt_flag flip-flop → `(-2,-2)` при rt_flag==1
  - [ ] `poisoned_runtime.gd` — `compute_snapshot = args[1] + level * args[2]`,
        `on_turn_start = take_damage(floor(max_hp * snapshot / 100))`
  - [ ] `rooted_runtime.gd` — `modify_speed → 0`,
        `override_movement → (-2,-2)`
  - [ ] `feared_runtime.gd` — source-validity на `on_turn_start`,
        `override_movement` максимизирует hex_distance до source (AI only;
        skip если actor.team == &"player")
  - [ ] `burning_runtime.gd` — `compute_snapshot = args[1] + level * args[2]`,
        `on_turn_start = take_damage(snapshot)`
  - [ ] `glitched_runtime.gd` — pure stub (все defaults)
  - [ ] `shielded_runtime.gd` — `compute_snapshot = args[1] + level * args[2]`,
        `damage_reduction = inst.snapshot_value`
  - [ ] `enraged_runtime.gd` — source-validity, `override_movement` к source
        (AI only), `override_cast_target` возвращает source_id если в range
- [ ] **A4.** Создать `scripts/core/statuses/status_registry.gd` (autoload):
  - preload-таблица `_RT_BY_ID` со всеми 9
  - `_ready` — load `data/status_effects/*.json` в `_meta`
  - методы `runtime_for / meta_for / family_of / arity_of`
- [ ] **A5.** Зарегистрировать `StatusRegistry` в `project.godot` autoloads,
  ПОСЛЕ EventBus / GameSpeed / GameLogger.

## B. Status registry data

- [ ] **B1.** Создать `data/status_effects/` с 9 файлами:
  - [ ] `stunned.json` — family `control`, arity 1, params `[duration]`
  - [ ] `slowed.json` — family `debuff`, arity 1, params `[duration]`
  - [ ] `poisoned.json` — family `dot`, arity 3,
        params `[duration, damage_pct, lvl_bonus_pct]`
  - [ ] `rooted.json` — family `control`, arity 1, params `[duration]`
  - [ ] `feared.json` — family `control`, arity 1, params `[duration]`
  - [ ] `burning.json` — family `dot`, arity 3,
        params `[duration, damage, lvl_bonus]`
  - [ ] `glitched.json` — family `debuff`, arity 1, params `[duration]`
  - [ ] `shielded.json` — family `shield`, arity 3,
        params `[duration, n_block, lvl_bonus]`
  - [ ] `enraged.json` — family `debuff`, arity 1, params `[duration]`
  - Каждый файл также содержит `loc_name`, `loc_desc` placeholder loc-keys.

## C. Effect-схема — drop duration

- [ ] **C1.** `scripts/core/abilities/ability_effect.gd`:
  - удалить `@export var duration`
  - оставить `requires_alive_target`
- [ ] **C2.** `scripts/core/abilities/effects/move_effect.gd`:
  - `apply_level` — удалить ветку scaling по duration; функция станет no-op,
    оставить `pass` (move_distance — designed value, не скейлится).
- [ ] **C3.** `scripts/core/abilities/effects/damage_effect.gd`,
  `heal_effect.gd`, `create_effect.gd` — удалить TODO-комментарии про DoT/HoT
  (они зависели от duration). Других правок не нужно.
- [ ] **C4.** `scripts/core/abilities/effects/status_effect.gd` — переписать:
  - поля `status_id: StringName`, `args: Array[int]`, private `_level: int`
  - `apply_level(level) -> void: _level = level`
  - `apply(caster, target, ctx)` — см. plan §"StatusEffect.apply"
  - удалить старое поле `status` и старый apply.

## D. Парсер `_make_effects_from_dict`

- [ ] **D1.** `scripts/core/abilities/ability_database.gd` —
  переписать ветку обработки ключа `"status"`:
  - не использовать `_apply_params` для status-keya
  - вызывать новый `_make_status_effect(value, ability_id) -> StatusEffect`
  - см. plan §"Парсер delta"
- [ ] **D2.** Добавить `_parse_status_string(s: String) -> Dictionary`
  (частный, см. plan).
- [ ] **D3.** Soft-shim: если в effect-объекте есть ключ `"duration"` —
  `GameLogger.info`, игнорировать. Не warn (после миграции AC-M1 их не
  будет, но info полезен при rebase'ах с других веток).

## E. Actor surface

- [ ] **E1.** `scripts/core/actors/actor.gd` — добавить:
  - сигнал `statuses_changed(actor_id: StringName)`
  - `var _statuses: Dictionary = {}` (CLAUDE trap #6 — Dictionary, not Array[Resource])
  - методы `add_status / remove_status / get_statuses / has_status /
    is_stunned / effective_speed / damage_reduction`
- [ ] **E2.** Добавить метод `tick_statuses_with_ctx(ctx: Dictionary) -> void`
  (см. plan §"Actor delta"). Игнорировать при `_dead`.
- [ ] **E3.** Модифицировать `take_damage`: применить `damage_reduction()`
  до клампинга hp. Если reduced ≤ 0 — return без emit (полное поглощение).
- [ ] **E4.** `_ready` — попытаться bind'нуть `$StatusIconStrip` если
  существует: `if has_node("StatusIconStrip"): $StatusIconStrip.bind_actor(self)`.
  Лог info если нет.

## F. AI / movement honor speed

- [ ] **F1.** `scripts/core/ai/enemy_ai_planner.gd`:
  - в начале `plan(actor, ctx)` — `if actor.is_stunned(): clear intents, return`
  - после bail-on-stunned, до scenario.movement_policy:
    - обойти `actor.get_statuses()`, для каждого вызвать
      `runtime.override_movement(actor, inst, ctx)`
    - если `(-2,-2)` — clear move_intent, продолжить к cast_intent (rooted/slowed-skip ещё может cast'ить)
    - если другой Vector2i — записать в `actor.move_intent_coord`, break
  - см. plan §"AI movement override impl"
- [ ] **F2.** AI cast-target override:
  - найти точку, где AI выбирает victim_coord для `cast_intent` (вероятно
    в `enemy_ai_planner` или `tactic_rule.gd` / `selectors/*.gd` —
    инспектировать при импле)
  - после выбора default'ного — обойти статусы, вызвать
    `override_cast_target(actor, inst, ctx)`; первый non-empty StringName
    переопределяет victim
  - **TODO в коде:** если selector-логика разбросана по rule'ам, вынести
    хук в общий помощник `_pick_victim_coord(actor, ability)` — но
    рефактор только если естественно укладывается; иначе — в каждом
    selector'е добавить override-чек, и оставить TODO для пост-джем чистки.
- [ ] **F3.** Выяснить, читают ли существующие movement-policy
  (`policy_approach_nearest_enemy`, `policy_kite_from_nearest_enemy`)
  `actor.speed` или жёстко 1 hex/turn. Если читают — заменить на
  `actor.effective_speed()`. Если нет — оставить 1 hex/turn (slowed/rooted
  всё равно перехватит через `override_movement → (-2,-2)`).

## G. Godmode controller — tick + stun-skip

- [ ] **G1.** `scripts/presentation/godmode/godmode_controller.gd._on_world_turn_ended`:
  - в начале (после `_world_processing` guard) — `_tick_all_statuses()`
  - после tick'а — `if player.is_alive() and player.is_stunned():`
    - `await get_tree().create_timer(GameSpeed.get_value("arena", "stun_skip_delay", 0.4)).timeout`
    - `_world_processing = false; TurnManager.advance(); return`
- [ ] **G2.** Добавить `_tick_all_statuses()` метод:
  - `var ctx := _world_ctx()`
  - for each `actor in registry.all()` if alive — `actor.tick_statuses_with_ctx(ctx)`
- [ ] **G3.** Add `arena.stun_skip_delay = 0.4` в `config/game_speed.cfg`.

## H. Player input gating при stunned

- [ ] **H1.** Найти HUD skill-slot widget (обработчик Q/W/E/R) —
  вероятно в `scripts/presentation/skill_slot.gd` или
  `scenes/ui/hud_*.tscn`. Подключить к `player.statuses_changed`,
  на emit — пересчитать `disabled`-state: если `player.is_stunned()` →
  все слоты visually disabled (через существующий cooldown-стиль).
- [ ] **H2.** Godmode-controller path движения мышью:
  в начале handler'а ЛКМ для move — `if player.is_stunned(): return`.
  Не нужно показывать «cant move» — pill уже виден.

## I. Status visibility (UI-kit wiring)

- [ ] **I1.** `scripts/presentation/status_icon_strip.gd.bind_actor(actor)`:
  - сохранить ref
  - подписаться `actor.statuses_changed.connect(_on_statuses_changed)`
  - вызвать `_rebuild()` сразу для starting state
- [ ] **I2.** Добавить приватный `_rebuild() -> void`:
  - собрать entries из `actor.get_statuses()`:
    `{id: inst.status_id, family: StatusRegistry.family_of(inst.status_id),
      duration: inst.duration}`
  - вызвать `set_statuses(entries)`
- [ ] **I3.** `unbind()` — disconnect signal, очистка.
- [ ] **I4.** `scenes/dev/player.tscn` — добавить child node
  `StatusIconStrip` (instance of `scenes/ui/status_icon_strip.tscn`),
  position offset `Vector2(0, -BAR_HEIGHT - SP_2)` от Actor-origin.
  Точные значения — UiTheme constants.
- [ ] **I5.** `scenes/dev/manekin.tscn` — то же.
- [ ] **I6.** `scripts/presentation/move_range_overlay.gd:77` — заменить
  `actor.speed` на `actor.effective_speed()`.

## J. Migration JSON

- [ ] **J1.** Удалить ключи `"duration"` из всех effect-объектов в:
  - `data/skills/skill_debug_punch.json`
  - `data/skills/skill_melee_punch.json`
  - `data/skills/skill_manekin_attack.json`
  - `data/skills/skill_knockback_punch.json`
  - `data/skills/test_area_strike.json`
  - `data/skills/test_chain_lightning.json`
  - `data/skills/test_combo_actor_chain_damage.json`
  - `data/skills/test_combo_actor_chain_move.json`
  - `data/skills/test_combo_hex_circle_create.json`
  - `data/skills/test_combo_self_self_heal.json`
  - `data/skills/test_level_scaling.json`
  - `data/skills/test_target_area_strike.json`
  - `data/skills/test_vamp_strike.json`
  Проверка: `grep -R '"duration":' data/skills/` — пусто.
- [ ] **J2.** `data/skills/test_combo_hex_circle_damage_status.json`:
  `{"duration":0,"damage":8}, {"duration":2,"status":"burning"}`
  → `{"damage":8}, {"status":"burning(2, 3, 1)"}`.
- [ ] **J3.** `data/skills/test_combo_multikey_effect.json`:
  `{"duration":1,"damage":8,"status":"burning"}`
  → `{"damage":8, "status":"burning(1, 2, 1)"}`.
- [ ] **J4.** **NEW** `data/skills/test_status_runtime.json` — single
  ability, `target.kind=actor range=4`, area `chain area_max_chain_length=1
  area_radius=1`, effects `[{"status": "poisoned(3, 10, 2)"}]`. Для AC-X3.
- [ ] **J5.** Балансные числа `burning(2,3,1)` / `burning(1,2,1)` — в
  spec'е и в JSON помечены как placeholder. После плейтеста Стасян
  подкрутит. **НЕ блокирует merge.**

## K. Smoke / verification

- [ ] **K1.** Запустить проект → лог:
  - `StatusRegistry` грузит 9 статусов без warn'ов
  - `SkillDatabase` грузит все skill'ы без warn'ов
  - Никаких unknown-status / arity-mismatch / malformed warn'ов
- [ ] **K2.** Godmode → AC-X2 (burning через damage_status skill)
- [ ] **K3.** Godmode → AC-X3 (poisoned через test_status_runtime)
- [ ] **K4.** Godmode → AC-X4 (stun на manekin через debug-инструмент;
  если debug-self-cast недоступен — добавить временный hotkey в
  godmode_controller для self-cast'а тестового скилла со stunned)
- [ ] **K5.** Godmode → AC-X5 (stun на player → slot grey + auto-advance)
- [ ] **K6.** Godmode → AC-X6 (shielded блокирует часть урона)
- [ ] **K7.** Godmode → AC-X7 (re-apply burning замещает duration)
- [ ] **K8.** Godmode → AC-X8 (feared AI убегает от player'а;
  если player умирает — feared expire)

## L. Push & PR

- [ ] **L1.** `git add` всё; `git commit` поэтапно (A → B → C → ... → J)
  для читаемой истории. Один коммит = одна логическая единица.
- [ ] **L2.** `git push -u origin egor/spec-27-status-effects`
- [ ] **L3.** Скопировать PR-create URL из stderr push'а, открыть PR в
  браузере → `staging`.
- [ ] **L4.** Описание PR: ссылка на spec/plan/tasks, чек-лист пройденных
  AC-X, скриншот HUD'а с pill'ами над manekin'ом и player'ом.

## Зависимости между задачами

```
A1 → A2 → A3 (все 9) → A4 → A5
B1 (параллельно с A)
A* + B* → C → D → E → F + G + H + I (параллельно)
любая правка JSON → J (параллельно с кодом)
всё → K → L
```

## Out-of-task (deferred)

- Sprite-иконки Кати в pill'ах — placeholder unicode glyphs OK на джеме.
- Tooltip на pill'ах (через `status_pill_hovered`) — отдельная фича UI.
- Floating-text «Stunned!» — отдельная фича VFX/UI.
- Real `glitched` поведение — отдельный spec.
- Балансные числа в migrated burning skill'ах — Стасян после плейтеста.
- AudioDB hook на add_status / on_tick — отдельный spec audio-системы.
