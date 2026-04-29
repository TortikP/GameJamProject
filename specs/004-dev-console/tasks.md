# 004-dev-console — tasks

## Часть 1 — инфраструктура

- [ ] T001 [P1] `config/game_speed.cfg` — добавить секцию `[dev]` с `console_max_lines=80`.
- [ ] T002 [P1] `scripts/infrastructure/dev_console.gd` — Node-autoload. `_ready()`: инстанцирует `dev_console.tscn` в CanvasLayer(layer=20), добавляет в root. Toggle по F12. По умолчанию скрыт.
- [ ] T003 [P1] `scenes/dev/dev_console.tscn` — VBoxContainer full-rect: RichTextLabel#Log (bbcode, scroll_active=true, size_flags_vertical=expand) + LineEdit#Input (placeholder «enter command...»).
- [ ] T004 [P1] DevConsole: `push(level: int, tag: String, msg: String)` — форматирует строку с bbcode-цветом по level, timestamp, appends в RichTextLabel. Обрезает до `console_max_lines`. (depends T002, T003)
- [ ] T005 [P1] `scripts/infrastructure/game_logger.gd` — в конце `log()` добавить push в DevConsole если есть: кешировать ref в `_console_ref`, проверять `is_instance_valid`. (depends T004)
- [ ] T006 [P1] `project.godot` — добавить `DevConsole` последним в `[autoload]`. (depends T002)

## Часть 2 — команды

- [ ] T007 [P1] DevConsole: `_execute(raw)` — split, match по первому токену, dispatch. Вывод результата через `push` с уровнем INFO или WARN.
- [ ] T008 [P1] Команда `help` — вывести таблицу команд.
- [ ] T009 [P1] Команда `play <id>` — `DialogueManager.play(StringName(id), true)`. Warn если DialogueManager недоступен.
- [ ] T010 [P1] Команда `request <event>` — `DialogueManager.request(StringName(event), {}, true)`.
- [ ] T011 [P1] Команда `emit <signal>` — проверить против ALLOWED_SIGNALS, emit через EventBus. Warn если не в списке.
- [ ] T012 [P2] Команда `speed <section> <key> <value>` — `GameSpeed._cfg.set_value(section, key, float(value))`. Warn если GameSpeed недоступен.
- [ ] T013 [P1] Команда `clear` — `_log_rtl.clear()`.
- [ ] T014 [P1] Команда `db` — вывести все id из `DialogueDB._lines.keys()` отсортированные.

## Часть 3 — UX

- [ ] T015 [P1] LineEdit: Enter → `_execute` + append в `_history` (лимит 20) + очистить поле.
- [ ] T016 [P2] LineEdit: стрелка вверх/вниз → навигация по `_history`. (depends T015)
- [ ] T017 [P2] При открытии консоли (F12) — автофокус на LineEdit.
- [ ] T018 [P2] Полупрозрачный фон панели (alpha ~0.88) чтобы была видна игра позади.

## Часть 4 — merge

- [ ] T019 [P1] PR `andrey/dev-console → staging`. Ревью.
- [ ] T020 [P2] Обновить `Currently claimed` в CLAUDE.md (добавить 004-dev-console → Andrey).
