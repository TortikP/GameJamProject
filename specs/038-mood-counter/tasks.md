# 038-mood-counter — tasks

**Spec:** [`spec.md`](./spec.md) · **Plan:** [`plan.md`](./plan.md)

Легенда: `[P1]` критический · `[P2]` нужно для acceptance · `[P3]` nice-to-have
`[P]` parallel-safe внутри группы

---

## Группа A — JSON-миграция словаря

- [ ] **T010** [P1] `data/skills/*.json` — sed-проход (см. plan.md «JSON-миграция»). После: `git diff --stat data/skills/` для глазной проверки.
- [ ] **T011** [P1] Греп-валидация:
  - `grep -l '"friendly"\|"toxic"\|"apathetic"' data/skills/*.json` → пусто.
  - `grep -l '"mood"' data/skills/*.json | wc -l` → 52.
- [ ] **T012** [P2] Прогнать Godot редактор / пробный запуск godmode — все 52 скилла грузятся, в логах нет ошибок парсинга.

## Группа B — EventBus signal (parallel с A)

- [ ] **T020** [P1] [P] `scripts/infrastructure/event_bus.gd` — добавить `signal player_mood_changed(counts: Dictionary, dominant: StringName)` в конец файла, секция narrative-сигналов.

## Группа C — MoodTracker (после B)

- [ ] **T030** [P1] `scripts/core/narrative/mood_tracker.gd` — создать файл по коду из plan.md (≈50 LoC). depends T020.
- [ ] **T031** [P1] `project.godot` — добавить в `[autoload]`: `MoodTracker="*res://scripts/core/narrative/mood_tracker.gd"` после строки `SkillDatabase=...`. depends T030.

## Группа D — SkillDatabase валидация (parallel с A/B/C)

- [ ] **T040** [P2] [P] `scripts/core/skills/skill_database.gd` — в `_build_skill` после парсинга `mood` добавить локальный `const _VALID_MOODS` и warn-цикл (см. plan.md). depends T010 (иначе ворнинги забьют лог на старых именах).

## Группа E — Wiring (после C)

- [ ] **T050** [P1] `scripts/presentation/godmode/godmode_controller.gd` → `sync_player_skills_from_slots()` — после `player.set_skills(skills)` добавить `MoodTracker.recompute_from_skills(skills)`. depends T030, T031.

## Группа F — Smoke (после A,C,E)

- [ ] **T060** [P1] Запуск godmode сцены: на старте `MoodTracker.get_counts()` ненулевой (по 4 default-скиллам), `EventBus.player_mood_changed` отстрелил один раз с правильным dominant.
- [ ] **T061** [P1] RMB-замена скилла в слоте → recompute, новый emit. Старого warn'а нет.
- [ ] **T062** [P2] Очистить все 4 слота (RMB → null или эквивалент) → counts all-zero, dominant = `neutral`.
- [ ] **T063** [P2] Поставить два скилла с непересекающимся mood и одинаковыми вкладами в счётчик → dominant = `chimera`.
- [ ] **T064** [P3] В `_VALID_MOODS` временно поломать (убрать `tranquility`) → загрузка логает warn для всех скиллов с `tranquility`. Откатить.

## Группа G — Bookkeeping

- [ ] **T070** [P2] `CLAUDE.md` — таблица «Currently claimed»: добавить строку `| 038-mood-counter | Egor |`.
- [ ] **T071** [P3] `HANDOFF.md` — короткая запись в раздел про DialogueManager / нарратив (если есть) о том, что mood-tracker готов и ждёт consumer'а Никиты. Если раздела нет — пропустить, не плодить.

---

## Acceptance gate

Перед PR'ом `egor/mood-counter → staging`:

1. T011 грепы проходят.
2. T012 — Godot не выдаёт parse error в `--check-only` или при запуске.
3. T060–T063 smoke — глазами.
4. `git status` чистый кроме коммита фичи.
