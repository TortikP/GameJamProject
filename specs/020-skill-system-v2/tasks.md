# 020-skill-system-v2 — tasks

**Spec:** [`spec.md`](./spec.md) · **Plan:** [`plan.md`](./plan.md)

Легенда: `[P1]` — критический путь · `[P2]` — нужно для acceptance · `[P3]` — nice-to-have
`[P]` — parallel-safe внутри группы

---

## Группа A — virtual `apply_level` на базовых классах

- [ ] **T001** [P1] [P] `scripts/core/abilities/ability_target.gd` — `func apply_level(_level: int) -> void: pass` + докстринг «default no-op; subclasses override per skill-level scaling».
- [ ] **T002** [P1] [P] `scripts/core/abilities/ability_area.gd` — то же.
- [ ] **T003** [P1] [P] `scripts/core/abilities/ability_effect.gd` — то же.

---

## Группа B — override `apply_level` на подклассах (parallel после A)

### Effects
- [ ] **T010** [P1] [P] `damage_effect.gd` — `if level > 0: damage = int(floor(damage * (1 + 0.2 * level)))`.
- [ ] **T011** [P1] [P] `heal_effect.gd` — `heal = int(floor(heal * (1 + 0.1 * level)))`.
- [ ] **T012** [P1] [P] `status_effect.gd` — `if duration > 1 and level > 0: duration += level`.
- [ ] **T013** [P1] [P] `move_effect.gd` — `if duration > 1 and level > 0: duration += level`. **`move_distance` НЕ скейлится.**
- [ ] **T014** [P3] [P] `create_effect.gd` — explicit no-op override (оставляет inheritance явным; можно опустить).

### Areas
- [ ] **T020** [P1] [P] `zone_circle_area.gd` — `if radius > 1 and level > 0: radius += level / 2` (целочисл. деление).
- [ ] **T021** [P1] [P] `chain_area.gd` — `if max_chain_length > 1 and level > 0: max_chain_length += level / 2`. (apply_level override, отдельно от radius-фичи в T030).
- [ ] **T022** [P3] [P] `self_area.gd` — explicit no-op (по желанию).

### Targets
- [ ] **T030** [P1] [P] `actor_target.gd` (после rename T040) — `if range > 1 and level > 0: range += level`.
- [ ] **T031** [P1] [P] `hex_target.gd` — то же.
- [ ] **T032** [P1] [P] `object_target.gd` — то же (на stub'е, но руки не доходить второй раз).
- [ ] **T033** [P3] [P] `self_target.gd` — explicit no-op.

---

## Группа C — Rename entity → actor

- [ ] **T040** [P1] `git mv scripts/core/abilities/targets/entity_target.gd scripts/core/abilities/targets/actor_target.gd`. Внутри: `class_name EntityTarget` → `ActorTarget`. Update file-level docstring (entity → actor).
- [ ] **T041** [P1] `scripts/core/abilities/ability_database.gd` — `TARGET_KINDS["entity"]` → `TARGET_KINDS["actor"]`, preload путь `actor_target.gd`. Удалить ключ `"entity"`. (depends T040)
- [ ] **T042** [P1] grep `EntityTarget` по проекту, убедиться что нет других потребителей кроме переименованного файла. Update `specs/007-skill-system/plan.md` если упоминается (документация, не код).

---

## Группа D — ChainArea radius

- [ ] **T050** [P1] `chain_area.gd` — `@export var radius: int = 1`. BFS-step: на каждом звене, вместо `get_walkable_neighbours(current)`, делать BFS до `radius` шагов и фильтровать Actor'ы. Visited-tracking сохраняется. При `radius=1` поведение идентично pre-020 (regression-safe).
- [ ] **T051** [P2] `chain_area.get_affected_hexes` — если требуется обновление под radius для preview-overlay (проверить cast_range_overlay): пока не требуется (overlay рисует только primary hex).

---

## Группа E — Skill / Ability расширение

- [ ] **T060** [P1] `scripts/core/abilities/ability.gd` — добавить `@export var sound: StringName = &""`, `@export var animation: StringName = &""`. Сигнатура `cast(caster, ctx, level: int = 0)`, `predicted_damage_to(caster, t, ctx, level: int = 0)`. В cast: target.duplicate + apply_level (новое), area.duplicate + apply_level + _apply_param_modifiers (apply_level до modifiers), effect.duplicate + apply_level + _apply_param_modifiers. Базовый ресурс не мутируется.
- [ ] **T061** [P1] `scripts/core/skills/skill.gd` — добавить `name: String`, `tooltip: String`, `desc: String`, `mood: Array[StringName]`, `level: int`. Rename `tags` → `behaviour_tags`. `cast(caster, ctx)`: пробрасывает `self.level` в `ab.cast(caster, ctx, self.level)`. `predicted_damage_to`: то же.
- [ ] **T062** [P2] `scripts/core/abilities/effects/create_effect.gd` — rename `@export var game_object_id` → `entity_id`. Update лог-строки и TODO-коммент. (depends ничего; делать рядом с T060)

---

## Группа F — Парсеры базы данных

- [ ] **T070** [P1] `scripts/core/skills/skill_database.gd` — парсинг новых полей: `name`/`tooltip`/`desc` (String, default ""), `mood` (Array[StringName] аналогично tags), `level` (int default 0), `behaviour_tags` (вместо `tags`). Удалить парсинг `tags`. (depends T061)
- [ ] **T071** [P1] `scripts/core/abilities/ability_database.gd` — `_apply_params` уже общий, новые поля Ability (`sound`, `animation`) подхватятся автоматически. Только убедиться, что rename `entity`→`actor` в TARGET_KINDS done (T041).

---

## Группа G — JSON миграция (in-place)

- [ ] **T080** [P1] [P] `data/skills/skill_debug_punch.json` — `"tags"` → `"behaviour_tags"`, `"kind": "entity"` → `"kind": "actor"`.
- [ ] **T081** [P1] [P] `data/skills/skill_melee_punch.json` — то же.
- [ ] **T082** [P1] [P] `data/skills/skill_manekin_attack.json` — то же.
- [ ] **T083** [P1] [P] `data/skills/skill_knockback_punch.json` — то же.
- [ ] **T084** [P1] [P] `data/skills/test_area_strike.json` — `entity`→`actor` (если есть). Проверить — там `self`, миграция тривиальна.
- [ ] **T085** [P1] [P] `data/skills/test_chain_lightning.json` — `entity`→`actor`.
- [ ] **T086** [P1] [P] `data/skills/test_target_area_strike.json` — hex, без изменений (но проверить).
- [ ] **T087** [P1] [P] `data/skills/test_vamp_strike.json` — `entity`→`actor`.

---

## Группа H — потребители tags rename

- [ ] **T090** [P1] `scripts/core/ai/enemy_ai_planner.gd` строки 82, 85 — `s.tags` → `s.behaviour_tags`. (depends T061)
- [ ] **T091** [P1] `scripts/presentation/godmode/godmode_controller.gd` строки 741, 743 — `skill.tags` → `skill.behaviour_tags`. (depends T061)

---

## Группа I — Test fixtures (новые JSON)

- [ ] **T100** [P2] [P] `data/skills/test_combo_actor_chain_damage.json` — actor (range=–1) + chain(2, radius=1) + damage(10).
- [ ] **T101** [P2] [P] `data/skills/test_combo_hex_circle_damage_status.json` — hex (range=4) + zone_circle(2) + damage(8) + status(burning, dur=2).
- [ ] **T102** [P2] [P] `data/skills/test_combo_self_self_heal.json` — self + self + heal(20).
- [ ] **T103** [P2] [P] `data/skills/test_combo_actor_chain_move.json` — actor (range=1) + chain(1) + damage(4) + move(push, 2).
- [ ] **T104** [P2] [P] `data/skills/test_combo_hex_circle_create.json` — hex (range=3) + zone_circle(1) + create(swarm).
- [ ] **T105** [P2] `data/skills/test_level_scaling.json` — копия vamp_strike с `level: 2`. Через debug-каст ожидать damage=140, heal=60 в логе.

---

## Группа J — Smoke / acceptance (выполняется Egor'ом, Claude не запускает Godot)

- [ ] **T110** [P1] Открыть проект, godmode-сцена. `SkillDatabase` и `AbilityDatabase` логируют без warn'ов. Все 8 мигрированных + 6 новых JSON загрузились.
- [ ] **T111** [P1] Каст 4 production-абилок (`debug_punch`, `melee_punch`, `manekin_attack`, `knockback_punch`) — поведение идентично pre-020. (AC-X2)
- [ ] **T112** [P1] AI манекена выбирает skill_manekin_attack через `behaviour_tags ∋ "damage"`. (AC-X3)
- [ ] **T113** [P1] Каст `test_level_scaling`: лог DamageEffect.apply показывает 140 урона, HealEffect.apply показывает 60 хила. (AC-X4)
- [ ] **T114** [P2] Каст всех 5 test_combo_*: не падает, ожидаемое поведение в логе.

---

## Группа K — Документация (после остального)

- [ ] **T120** [P2] `CLAUDE.md` — в таблице «Currently claimed» добавить `020-skill-system-v2 | Egor`. Если попадутся новые traps — append в табл.
- [ ] **T121** [P3] `HANDOFF.md` §18 (текущее состояние) — кратко упомянуть 020 как next-up или in-progress.
- [ ] **T122** [P3] `specs/007-skill-system/spec.md` — пометить «Status: superseded by 020-skill-system-v2» в шапке (история сохраняется, не удаляем).

---

## Acceptance gate всего PR

- [ ] Godmode запускается, `SkillDatabase` лог: «loaded 14 skills» (8 мигр + 6 новых) без warn'ов.
- [ ] T111 — 4 production-абилки работают идентично pre-020.
- [ ] T113 — level-2 даёт damage 140 / heal 60 (floor).
- [ ] AI выбирает skill через `behaviour_tags`.
- [ ] grep по проекту: нет упоминаний `Skill.tags`, `EntityTarget`, `game_object_id`, `"kind": "entity"`.
- [ ] PR review: координация с Sergey (008 потребитель `Skill.tags`) — фикс в этом же PR, ack в чате.

---

## Заметки на /implement

- Группа A открывает Группу B — параллельно после A.
- C (rename) и D (chain.radius) — независимы, можно параллелить.
- E зависит от A (контракт apply_level используется в Ability.cast).
- F зависит от E (поля Skill/Ability должны существовать).
- G/H — независимы, но требуют F (парсинг новых полей перед запуском Godot для проверки).
- J (smoke) — Egor запускает локально, Claude не имеет Godot в контейнере.
- Шаги внутри одной группы Claude может пробежать без остановок (mechanical edits). Stop-points: между группами для самопроверки grep'ом.
- `Resource.duplicate()` — shallow по default. У наших ресурсов вложенных Resource'ов нет на уровне Effect/Area/Target → проблем не будет. Если внутри Effect появится вложенный Resource — `duplicate(true)` (deep) или append в CLAUDE.md traps.
