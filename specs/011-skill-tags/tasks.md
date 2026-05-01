# 011-skill-tags — tasks

**Spec:** [`spec.md`](./spec.md) · **Plan:** [`plan.md`](./plan.md)

Легенда: `[P1]` критический путь · `[P2]` doc-fix · `[P3]` post-merge коммуникация
`[P]` = parallel-safe

---

## Группа A — код

- [ ] **T001** [P1] `scripts/core/skills/skill.gd` — добавить `@export var tags: Array[StringName] = []` после строки `@export var abilities: Array[Ability] = []` (строка 15). Skill API ничего больше не трогать.
- [ ] **T002** [P1] `scripts/core/skills/skill_database.gd` — в `_build_skill` после `skill.cooldown = int(...)` (строка 71) вставить блок парсинга `tags` из plan.md §"Парсер snippet". (depends T001)

## Группа B — content (parallel после T002)

- [ ] **T003** [P1] [P] `data/skills/skill_debug_punch.json` — добавить `"tags": ["damage"],` после `"cooldown": 0,`. (depends T002)
- [ ] **T004** [P1] [P] `data/skills/skill_melee_punch.json` — `"tags": ["damage"],`. (depends T002)
- [ ] **T005** [P1] [P] `data/skills/skill_manekin_attack.json` — `"tags": ["damage"],`. (depends T002)
- [ ] **T006** [P1] [P] `data/skills/skill_knockback_punch.json` — `"tags": ["damage", "knockback"],`. (depends T002)
- [ ] **T007** [P1] **NOT-task:** убедиться что `data/skills/test_*.json` (4 файла) — НЕ изменены. AC-T4. (depends T006)

## Группа C — docs

- [ ] **T008** [P2] [P] `specs/007-skill-system/plan.md` — в JSON schema example (строки ~237-261) добавить `"tags": ["damage"],` после `"cooldown": 2,`. Doc-fix только. (depends T001 — концептуально)

## Группа D — verify

- [ ] **T009** [P1] Открыть проект в Godot 4.6.2, F5. Проверить лог: `[INFO][SkillDatabase] loaded N skills` (N = до-PR значение, ничего не отвалилось). Никаких WARN от парсера tags. (depends T002-T007)
- [ ] **T010** [P1] Smoke-тест каста: F1/F2/F3/F4 в godmode → debug skills работают. Manekin → атакует игрока через `skill_manekin_attack` как до PR. AC-T6. (depends T009)
- [ ] **T011** [P1] `git diff staging --stat` — проверить что diff = ровно 7 файлов из plan.md, ничего лишнего. (depends T010)

## Группа E — push

- [ ] **T012** [P1] Commit message: `feat(011): add Skill.tags additive field — carve-out from 008/AC-S5`. Push `egor/spec-011-skill-tags` → origin. (depends T011)
- [ ] **T013** [P1] Открыть PR `egor/spec-011-skill-tags → staging` в браузере по URL из push output. В описании сослаться на 008/AC-S5, упомянуть Сергея как primary reviewer. (depends T012, manual via browser — Claude не может через api.github.com)

## Группа F — post-merge

- [ ] **T014** [P3] После мержа в staging — пинг Сергея в чате: «011 в staging, `Skill.tags` доступен — апдейти 008/AC-S5 в plan.md». (depends T013 + merge)

---

## Заметки для Клода если возьмёт implement

- Коммит — **один** на всю фичу (не разбивать по таскам). 011 — это сам по себе single atomic change. Multiple коммиты только если что-то серьёзно сломается на T009/T010 и придётся фиксить — тогда отдельный fix-коммит.
- Перед T001: убедиться что `git status` чистый и ветка `egor/spec-011-skill-tags` (не staging).
- T002 snippet — копипаст из plan.md как есть, не перерисовывать.
- T003-T006: JSON-формат уже задан — ставить `tags` ПОСЛЕ `cooldown` и ДО `abilities`, вкладывая на тот же отступ что `cooldown` в каждом конкретном файле (debug_punch — табы, остальные — пробелы; не унифицировать в этом PR — не наш скоуп).
- T009/T010 — Godot из container запустить нельзя (no GUI). Этот блок делает Egor локально перед пушем. Если Клод имплементил — отметь T001-T008 как `[x]`, T009-T010 оставь `[ ]` с пометкой «manual: Egor».
- T013 — URL вернётся в stderr `git push` первой строкой `Create a pull request for ... by visiting: ...`. Из container PR не открывается (api.github.com заблокирован).
