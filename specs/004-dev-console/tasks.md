# 004-dev-console — tasks

Branch: `andrey/dev-console`. PR target: `staging`.

## Часть 1 — конфиг и инфраструктура

- [ ] T001 [P1] `config/game_speed.cfg` — добавить секцию `[dev]` с `console_max_lines=80` и `debug_enabled=true`.
- [ ] T002 [P1] `scenes/dev/dev_console.tscn` — построить дерево по plan.md §"Архитектура сцены": CanvasLayer(layer=20) → Panel#Root (full-rect, modulate.a=0.88, visible=false) → VBoxContainer → RichTextLabel#Log (bbcode, scroll, fit_content=false) + LineEdit#Input. Плюс Control#Overlay (anchor top_right, margin=8, visible=false) → Label#OverlayText.
- [ ] T003 [P1] `scripts/infrastructure/dev_console.gd` — каркас: `extends Node`, константы (`SCENE`, `ALLOWED_SIGNALS`, `COLOR`, `LEVEL_ORDER`), state-переменные, пустой `_ready` инстанцирующий сцену + находящий узлы.
- [ ] T004 [P1] DevConsole `_ready`: process_mode=ALWAYS, чтение `[dev]` из GameSpeed, применение дефолтов по `debug_enabled` (см. spec §E), запуск 0.5с Timer для overlay refresh, коннект `text_submitted` и `gui_input` LineEdit. (depends T002, T003)
- [ ] T005 [P1] `project.godot` — добавить `DevConsole="*res://scripts/infrastructure/dev_console.gd"` последним в `[autoload]`. (depends T003)

## Часть 2 — лог и фильтры

- [ ] T006 [P1] DevConsole `push(level, tag, msg)` + `_push_colored(lvl_name, tag, msg)`: timestamp через `Time.get_time_string_from_system()`, цвет из `COLOR`, bbcode-строка, `RichTextLabel.append_text`. (depends T004)
- [ ] T007 [P1] DevConsole `_trim_log()`: пока `get_paragraph_count() > _max_lines` — `remove_paragraph(0)`. Вызывается в конце `_push_colored`. (depends T006)
- [ ] T008 [P1] DevConsole filter: `_min_level: int`, `_tag_filter: String`. `_push_colored` применяет оба фильтра до append. TRACE=-1 в LEVEL_ORDER чтобы `level INFO` скрывал и DEBUG и TRACE. (depends T006)
- [ ] T009 [P1] DevConsole `_cmd_filter(parts)`: подкоманды `level <name|all>` и `tag <name|clear>`. Валидация против LEVEL_ORDER. (depends T008)

## Часть 3 — GameLogger интеграция

- [ ] T010 [P1] `scripts/infrastructure/game_logger.gd`: добавить `static var _console_ref: Node = null`, метод `_push_to_console(level, tag, msg)` с lazy lookup через `Engine.get_main_loop().root.has_node("DevConsole")` и `is_instance_valid` проверкой кеша. Вызвать из `_write` после `print`. (depends T004)
- [ ] T011 [P1] Smoke-test: запустить игру без autoload DevConsole — убедиться что `print` работает, нет крашей в `_push_to_console`. (depends T010)

## Часть 4 — toggle и input

- [ ] T012 [P1] DevConsole `_unhandled_input`: F12 → `_toggle_panel`, Shift+F12 → `_toggle_overlay`. `set_input_as_handled` после обоих. Учитывать `event.shift_pressed` ДО ветки без shift (см. plan.md). (depends T004)
- [ ] T013 [P1] DevConsole `_toggle_panel()`: переключает `Panel#Root.visible`, при show — `_input.grab_focus()`. (depends T012)
- [ ] T014 [P2] DevConsole `_toggle_overlay()`: переключает `Control#Overlay.visible`. (depends T012)
- [ ] T015 [P1] DevConsole `_on_input_gui(event)`: KEY_UP/DOWN — навигация по `_history`, KEY_ESCAPE — `_toggle_panel`. `set_input_as_handled` в каждой ветке. (depends T013)
- [ ] T016 [P1] DevConsole `_on_submitted(raw)`: эхо в лог как CMD, push в `_history` (лимит 20, dedupe с предыдущим), reset `_history_idx`, clear LineEdit, вызов `_execute(raw)`. (depends T015)

## Часть 5 — команды

- [ ] T017 [P1] DevConsole `_execute(raw)`: split, match по первому токену, диспатч на `_cmd_*`. Unknown → WARN. (depends T016)
- [ ] T018 [P1] `_cmd_help()`: вывести список команд + текущие настройки фильтра/trace/overlay (по образцу из plan.md §help).
- [ ] T019 [P1] `_cmd_play(parts)`: `DialogueManager.play(StringName(parts[1]), true)`. Если autoload нет — WARN.
- [ ] T020 [P1] `_cmd_request(parts)`: `DialogueManager.request(StringName(parts[1]), {}, true)`. WARN если нет.
- [ ] T021 [P1] `_cmd_emit(parts)`: проверка против `ALLOWED_SIGNALS`, `EventBus.emit_signal(name)`. WARN если не в списке или EventBus нет.
- [ ] T022 [P2] `_cmd_speed(parts)`: `GameSpeed._cfg.set_value(section, key, float(value))`, инкремент `_speed_overrides`. WARN если GameSpeed нет.
- [ ] T023 [P1] `_cmd_db()`: вывести `DialogueDB.get_all_ids()` отсортированные через `, `.
- [ ] T024 [P2] `_cmd_inspect(parts)`: подкоманды `dm`/`gs`/`eb` по plan.md §inspect.
- [ ] T025 [P1] `pause` / `resume` — `get_tree().paused = true/false`. Однострочные, прямо в `_execute` match.
- [ ] T026 [P1] `clear` — `_log_rtl.clear()`. Однострочно в `_execute`.

## Часть 6 — EventBus auto-trace

- [ ] T027 [P1] DevConsole `_trace_on()`: перебор `EventBus.get_signal_list()`, фильтр `_`-префикса, `Callable(self, "_on_traced_signal").bindv([name])`, `eb.connect(name, cb)`. Сохранить в `_trace_connections`. Установить `_trace_enabled=true`. Идемпотентно. (depends T006)
- [ ] T028 [P1] DevConsole `_trace_off()`: проход по `_trace_connections`, `eb.disconnect`, очистка массива, `_trace_enabled=false`. Идемпотентно. (depends T027)
- [ ] T029 [P1] DevConsole `_on_traced_signal(name, arg0=null, arg1=null, arg2=null, arg3=null)`: собрать non-null args, запушить TRACE-строку, обновить `_last_signal_name` и `_last_signal_time_ms`. (depends T027)
- [ ] T030 [P1] `_cmd_trace(parts)`: `on` → `_trace_on()`, `off` → `_trace_off()`. (depends T028)

## Часть 7 — overlay

- [ ] T031 [P1] DevConsole `_refresh_overlay()` (вызывается Timer'ом 0.5с): early return если `_overlay.visible == false`. Заполняет Label по plan.md §overlay refresh. Проверки `get_node_or_null` + `is_instance_valid` для DialogueManager. (depends T014, T029)
- [ ] T032 [P2] `_cmd_overlay(parts)`: `on`/`off` → `_overlay.visible`. (depends T014)

## Часть 8 — финиш

- [ ] T033 [P1] Manual test pass:
  - F12 открывает/закрывает.
  - Все DialogueManager-логи появляются автоматом.
  - `play <id>` запускает диалог.
  - `trace on` ловит `run_started` если эмитнуть руками.
  - `filter level WARN` убирает DEBUG/INFO/TRACE.
  - `filter tag DialogueDB` оставляет только их.
  - `pause` останавливает игру, `resume` снимает.
  - Shift+F12 показывает overlay, FPS обновляется.
  - Удаление autoload DevConsole из project.godot — игра запускается без ошибок.
- [ ] T034 [P1] Удалить `scenes/dev/dialogue_preview.tscn` если его функции (запуск диалога вручную) полностью покрылись `play`/`request` (см. spec 003 — preview жил для тестирования; теперь живёт console). Решение по результату T033. **Default — оставить**, удаляется отдельным PR при подтверждении ненужности.
- [ ] T035 [P1] PR `andrey/dev-console → staging`. Описание: ссылка на 004-spec, скриншот окна с trace+overlay, чек-лист T033.
- [ ] T036 [P2] Обновить `Currently claimed` в `CLAUDE.md`: добавить `004-dev-console → Andrey`.

## Замечания

- Не добавлять зависимостей на конкретные сцены — DevConsole должен жить независимо.
- Все `get_node_or_null` + проверка `is_instance_valid` перед dereference чужих autoload'ов. DialogueManager / GameSpeed / EventBus могут быть выгружены в тестах.
- При расширении ALLOWED_SIGNALS — обновить и `_cmd_help` тоже (или сгенерить help из константы).
- Если `_on_traced_signal` 4-аргументного оказывается мало — расширить до 6, не менять подход.
