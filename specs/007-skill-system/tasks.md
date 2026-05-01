# 007-skill-system — tasks

**Spec:** [`spec.md`](./spec.md) · **Plan:** [`plan.md`](./plan.md)

Легенда: `[P1]` критический путь · `[P2]` нужно для полноты · `[P3]` nice-to-have / можно дропнуть в субботу
`[P]` = parallel-safe (можно делать одновременно с другими `[P]` той же группы)

---

## Группа A — базовые контракты (открывают всё остальное)

- [x] **T001** [P1] `scripts/core/abilities/ability_effect.gd` — расширить базу: добавить `@export var id: StringName`, `@export var type: StringName`, `@export var duration: int = 0`, `@export var requires_alive_target: bool = true`. Оставить `apply(caster, target: Variant, ctx)`. Сменить тип `target` с `Actor` на `Variant`.
- [x] **T002** [P1] `scripts/core/abilities/ability_target.gd` — упростить: `resolve()` возвращает `Variant` (не `Array`). Оставить `can_apply` и `get_range_hexes`. Документировать в комментарии: «target = категория, area даёт список жертв».
- [x] **T003** [P1] `scripts/core/abilities/ability_area.gd` — новый абстрактный класс. Методы: `resolve(caster, primary_target: Variant, ctx) -> Array`, `get_affected_hexes(caster_coord, primary, grid) -> Array[Vector2i]`. (depends T002)
- [x] **T004** [P1] `scripts/core/abilities/parameter_modifier.gd` — новый класс с полями `id`, `target_param`, `op` (`add`/`mul`), `value: float`, метод `applies_to(obj) -> bool` (через `target_param in obj`).
- [x] **T005** [P1] Удалить `scripts/core/abilities/ability_modifier.gd` и `scripts/core/abilities/modifiers/knockback_modifier.gd`. Перед удалением grep по проекту — убедиться что нигде не импортируется кроме `ability.gd` и `ability_database.gd` (там обновим в Группе D).

---

## Группа B — конкретные подклассы (parallel после Группы A)

### Targets

- [x] **T010** [P1] [P] `scripts/core/abilities/targets/entity_target.gd` — `@export var range: int = -1` (–1 = unrestricted, 0 = self, 1 = adjacent). `resolve` берёт `ctx.target_id` → Actor через registry. `can_apply` проверяет дистанцию. (depends T002)
- [x] **T011** [P1] [P] `scripts/core/abilities/targets/hex_target.gd` — `resolve` возвращает `ctx.target_coord: Vector2i`. (depends T002)
- [x] **T012** [P2] [P] `scripts/core/abilities/targets/direction_target.gd` — вектор от caster к `ctx.target_coord`, нормализованный до hex-направления. (depends T002)
- [x] **T013** [P3] [P] `scripts/core/abilities/targets/object_target.gd` — stub: `resolve` возвращает `null`, `can_apply` возвращает `false`. Реальная object-сущность не нужна для этой фичи. (depends T002)
- [x] **T014** [P1] Удалить `targets/single_enemy_target.gd` и `targets/single_enemy_adjacent_target.gd` после миграции JSON (depends T060).

### Areas

- [x] **T020** [P1] [P] `scripts/core/abilities/areas/self_area.gd` — `resolve` возвращает `[caster]`. (depends T003)
- [x] **T021** [P1] [P] `scripts/core/abilities/areas/chain_area.gd` — `@export var max_chain_length: int = 1`. BFS по `hex_grid.get_walkable_neighbours`, стартуя с primary. Без повторов. Стоп на N или когда нет соседей. (depends T003)
- [x] **T022** [P1] [P] `scripts/core/abilities/areas/zone_circle_area.gd` — `@export var radius: int = 1`. Использует `hex_grid.reachable_within(target_coord, radius, [])`. Сортировка жертв по гекс-дистанции от primary. (depends T003)
- [x] **T023** [P2] [P] `scripts/core/abilities/areas/zone_line_area.gd` — `@export var length: int = 3`. Прямая в hex-направлении от caster через primary. Может потребовать новый хелпер в `hex_grid.gd` (`line(from, dir, length)` — обсудить с Egor как owner). (depends T003)
- [x] **T024** [P2] [P] `scripts/core/abilities/areas/zone_cone_area.gd` — `@export var range: int`, `@export var width: int` (в гексах). (depends T003)
- [x] **T025** [P3] [P] `scripts/core/abilities/areas/zone_arc_area.gd` — кольцо с углом. (depends T003)

### Effects

- [x] **T030** [P1] [P] Refactor `scripts/core/abilities/effects/damage_effect.gd` — переименовать поле `amount` → `damage`. Внутри `apply` использовать `target as Actor` с тихим no-op если каст не удался. Сохранить `damage_bonus` от caster (KEEP IN SYNC с `Ability.predicted_damage_to`). DoT (duration > 0) — пометить `# TODO 007 DoT scaffold`, не реализовывать в этой фиче, эффект работает как мгновенный. (depends T001)
- [x] **T031** [P1] [P] `scripts/core/abilities/effects/heal_effect.gd` — `@export var heal: int = 0`. `apply` дёргает `Actor.heal(amount)` (или `take_damage(-amount)` если метода нет — проверить и добавить `Actor.heal` если нужно). (depends T001)
- [x] **T032** [P1] [P] `scripts/core/abilities/effects/status_effect.gd` — `@export var status: StringName`. `apply` вызывает `target.add_status(status, duration)` если метод существует, иначе лог и no-op. Реальная статус-система — отдельная фича. (depends T001)
- [x] **T033** [P1] [P] `scripts/core/abilities/effects/move_effect.gd` — `@export var move_type: StringName = &"push"`, `@export var move_distance: int = 1`. Реализация: для `push` — направление от caster к target, на N гексов; для `pull` — обратное; для `teleport` — на coord из ctx (или пропуск если нет). Использует `hex_grid.move_actor` или новый `shove_actor`. (depends T001)
- [x] **T034** [P2] [P] `scripts/core/abilities/effects/create_effect.gd` — `@export var game_object_id: StringName`. `apply`: проверить что `target` — `Vector2i` (иначе skip), проверить что гекс не занят (иначе skip), заспавнить через будущий object-spawner или stub-лог. `requires_alive_target` дефолт `false`. (depends T001)

---

## Группа C — Skill и БД (parallel после A; зависит от B по runtime, но компилируется без B)

- [x] **T040** [P1] `scripts/core/skills/skill.gd` — `class_name Skill extends Resource`. Поля `id`, `cooldown`, `abilities: Array[Ability]`, `_cd_remaining`. Методы `is_ready()`, `cast(caster, ctx) -> bool`, `tick_cooldown(by: int = 1)`. (depends T050)
- [x] **T041** [P1] `scripts/core/skills/skill_database.gd` — autoload по образцу `ability_database.gd`. Загружает `data/skills/*.json`. Метод `get_skill(id) -> Skill`. (depends T040, T070)
- [x] **T042** [P1] `project.godot` — добавить autoload `SkillDatabase=*res://scripts/core/skills/skill_database.gd`. (depends T041)

---

## Группа D — Ability refactor (центральный merge-point)

- [x] **T050** [P1] `scripts/core/abilities/ability.gd` — переписать:
  - Поля: `target: AbilityTarget`, `area: AbilityArea`, `effects: Array[AbilityEffect]`, `modifiers: Array[ParameterModifier]`.
  - Метод `cast`: lifecycle из plan.md §Lifecycle (resolve target → resolve area → for victim, for effect: duplicate, apply mods, alive-check, apply).
  - Метод `_apply_param_modifiers(obj, mods)`: группировка по `target_param`, формула `(base + Σadds) × Π muls`, set обратно с coercion (int → floor).
  - Метод `predicted_damage_to`: суммирует все Damage-эффекты с применением мод-формулы. KEEP IN SYNC комментарий.
  - `EventBus.ability_cast.emit(...)` сохраняется.
  (depends T001, T002, T003, T004)

---

## Группа E — Database и JSON (после D)

- [x] **T060** [P1] `scripts/core/abilities/ability_database.gd` — обновить registry (`TARGET_KINDS`, `AREA_KINDS`, `EFFECT_KINDS`, `MODIFIER_KINDS` per plan.md). Парсер JSON: новые поля `area`, `effects` (массив), `modifiers` с `kind: parameter`. Удалить ссылки на старые `single_enemy*` и `knockback`. (depends T010-T013, T020-T022, T030-T033, T050)
- [x] **T061** [P1] Migrate `data/abilities/melee_punch.json` → новая схема (target=entity range=1, area=chain(1), effects=[damage(8)]). (depends T060)
- [x] **T062** [P1] Migrate `data/abilities/debug_punch.json` → (target=entity, area=chain(1), effects=[damage(5)]). (depends T060)
- [x] **T063** [P1] Migrate `data/abilities/manekin_attack.json` → (target=entity range=1, area=chain(1), effects=[damage(4)]). (depends T060)
- [x] **T064** [P1] Migrate `data/abilities/knockback_punch.json` → (target=entity range=1, area=chain(1), effects=[damage(4), move(push, 2)]). (depends T060, T033)
- [ ] **T065** [P1] Запустить проект, godmode-сцена, кликнуть всеми 4 абилками — все работают как до миграции (acceptance gate этой группы). (depends T061-T064)

- [x] **T070** [P1] `scripts/core/skills/skill_database.gd` — поддержка JSON-схемы для skills (вложенные abilities). Использует тот же парсер ability'ев из `ability_database` (вынести парс-функцию в общий хелпер если копипаста). (depends T060)

---

## Группа F — EventBus и интеграция

- [x] **T080** [P1] `scripts/infrastructure/event_bus.gd` — добавить `signal skill_cast(caster_id: StringName, skill_id: StringName, target_ids: Array)` рядом с `ability_cast`.
- [x] **T081** [P2] `Skill.cast` — эмитит `EventBus.skill_cast` после прохода всех способностей. `target_ids` — объединённый dedup'нутый список actor_id из всех `ability_cast` этого навыка. (depends T040, T080)
- [x] **T082** [P2] `TurnManager` (`scripts/core/turn/turn_manager.gd`) — на старте хода исполнителя вызывать `Skill.tick_cooldown(1)` для всех его навыков. Проверить что `Actor` хранит ссылки на свои Skill'ы (или Skill хранит их сам). Контракт хранения уточняется в /implement. (depends T040)

---

## Группа G — Smoke / godmode test (после F)

- [x] **T090** [P1] `data/skills/test_vamp_strike.json` — навык вампиризма из spec scenario 3 (damage→heal_caster). (depends T070)
- [x] **T091** [P2] `data/skills/test_chain_lightning.json` — chain area, max=3, damage 10 + status(stun) duration 1. (depends T070)
- [x] **T092** [P2] Godmode: добавить debug-кнопку «Cast test skill» в `scripts/presentation/godmode/godmode_controller.gd` или новый dev-инспектор, дёргает `SkillDatabase.get_skill(...).cast(player, {target_id: selected_actor_id})`. (depends T040, T090)
- [ ] **T093** [P2] Прогнать вручную spec-scenarios 1, 3, 6, 8: одиночный damage на self, вампиризм с добиванием, модификатор `+5 damage`, Create в занятый гекс. Лог через `GameLogger.info("SkillTest", ...)`. (depends T092)

---

## Группа H — документы (после H)

- [x] **T100** [P2] `THEME_PLAN.md` §4 — переписать под новый контракт. Псевдокод lifecycle обновить под Skill→Ability→Effect[]. (depends T050)
- [x] **T101** [P3] `CLAUDE.md` — добавить в «Currently claimed»: `007-skill-system | Egor`. Если попадутся новые Godot-trap'ы (`Resource.duplicate()` поведение, типизация Variant и т. д.) — append в таблицу traps в том же PR. (depends nothing)
- [x] **T102** [P3] `HANDOFF.md` §19 — добавить в «Дальнейшие фичи (заготовки)»: `007-skill-system — owner Egor`. (depends nothing)

---

## Acceptance gate всего PR

- [ ] Godmode запускается без ошибок в консоли.
- [ ] Все 4 мигрированных ability работают как до фичи (T065).
- [ ] `test_vamp_strike` — урон + хил исполнителя на одной целе с 10 HP → цель мертва, исполнитель healed (T093).
- [ ] Стек `+5 add` и `×1.5 mul` на damage(10) → 22 урона (floor от 22.5) (T093).
- [ ] Никаких `push_warning` / `push_error` от наших классов в логе на чистом запуске.
- [ ] PR review: координация с Sergey по «modifier engine» проведена в чате; Andrey ack по EventBus-расширению (новый сигнал).

---

## Заметки на /implement

- **Не лупиться через все 30 тасков одним рывком** (HANDOFF §19, правило 2). Один таск, отметка `[x]`, верификация, следующий.
- Группы A → D — критический последовательный путь. Группы B (target/area/effect подклассы) внутри parallel-safe.
- Если на T060 (ability_database refactor) обнаружится, что старая `MODIFIER_KINDS` загрузка ломает существующие тесты — таск делится: сперва добавить новые kinds рядом со старыми, мигрировать JSON, потом удалить старые.
- `Resource.duplicate()` в Godot 4.6 — проверить поведение для вложенных Resource-полей (deep vs shallow). Если shallow — модификатор может зацепить общую копию между cast'ами. Если попадётся — append в CLAUDE.md traps.
