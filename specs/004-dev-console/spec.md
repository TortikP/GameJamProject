# 004-dev-console — spec

**Owner:** Andrey
**Status:** planned

## Цель

In-game dev-консоль: лог игровых событий + командная строка для тестовых действий + debug-overlay (FPS / last signal / dialogue queue). Заменяет постоянное переключение в Godot Output, сцену `dialogue_preview` и ручные `print()` для трассировки EventBus.

Полностью отключается удалением одной строки из `[autoload]` в `project.godot`. Игра без консоли не ломается — `GameLogger` продолжает писать только в `print()`.

## Acceptance criteria

### A. Отображение лога

- `F12` — toggle консоли. Сцена поверх всего (CanvasLayer layer=20). По умолчанию скрыта.
- Верхняя часть — RichTextLabel#Log (bbcode_enabled=true, scroll_active=true, fit_content=false). Хранит последние N строк (N из `[dev] console_max_lines`, дефолт 80).
- Лог пишет все `GameLogger.*` вызовы в реальном времени: `HH:MM:SS [LEVEL][TAG] msg`.
- Цвета (bbcode `[color=...]`):
  - DEBUG → `#888888` серый
  - INFO → `#ffffff` белый
  - WARN → `#ffcc00` жёлтый
  - ERROR → `#ff4444` красный
  - CMD → `#88ffcc` бирюзовый (эхо команд пользователя)
  - TRACE → `#66aaff` синий (EventBus auto-trace)
- Нижняя часть — LineEdit#Input (placeholder «enter command…»). Автофокус при открытии консоли.
- Полупрозрачный фон панели (~88% alpha) — игра видна позади.

### B. Команды (MVP)

| Команда | Действие |
|---|---|
| `help` | список команд + текущие настройки фильтра/trace/overlay |
| `play <id>` | `DialogueManager.play(StringName(id), true)` |
| `request <event>` | `DialogueManager.request(StringName(event), {}, true)` |
| `emit <signal>` | `EventBus.<signal>.emit()` — только из ALLOWED_SIGNALS, без аргументов в MVP |
| `speed <section> <key> <value>` | перезаписать значение GameSpeed в памяти (не пишется в файл) |
| `clear` | очистить лог консоли |
| `db` | вывести все id из `DialogueDB.get_all_ids()` отсортированные |
| `inspect <name>` | краткое состояние autoload'а: `dm` (DialogueManager), `gs` (GameSpeed), `eb` (EventBus) |
| `pause` / `resume` | `get_tree().paused = true/false` |
| `filter level <DEBUG\|INFO\|WARN\|ERROR\|all>` | минимальный уровень для отображения. all = показывать всё включая TRACE. Дефолт зависит от `debug_enabled`. |
| `filter tag <name>` | показывать только указанный tag |
| `filter tag clear` | сбросить tag-фильтр |
| `trace on` / `trace off` | EventBus auto-trace вкл/выкл (см. C) |
| `overlay on` / `overlay off` | debug HUD-оверлей вкл/выкл (см. D) |

Неизвестная команда → WARN в консоль.
ALLOWED_SIGNALS (MVP): `run_started`, `wave_spawned`, `portal_opened`, `run_ended`, `battle_started`, `battle_ended`. Остальные требуют расширения списка в коде — намеренно, чтобы случайным `emit` не сломать рантайм.

### C. EventBus auto-trace

- При `trace on` DevConsole перебирает `EventBus.get_signal_list()`, и для каждого сигнала чьё имя не начинается с `_` коннектится через `Callable` с захватом имени. Каждый emit пишет в лог `[TRACE][EventBus] <signal_name>(<args>)`. Аргументы конвертируются через `var_to_str` или `str(arg)`.
- При `trace off` — отключает все коннекты (хранит массив `_trace_connections: Array[Dictionary]` с `{signal, callable}`). Идемпотентно: повторный on/off безопасен.
- Стартовое состояние определяется `debug_enabled` (см. E).

### D. Debug HUD overlay

Control в правом верхнем углу основной CanvasLayer консоли (anchor top_right, margin 8px). Показывается **независимо от toggle консоли** — то есть консоль может быть скрыта, а overlay видим.

Toggle: `overlay on/off` (через консоль) или горячая клавиша `Shift+F12`.

Содержимое — Label#OverlayText (моноширинный шрифт, фон полупрозрачный):

```
FPS: 60
last signal: wave_spawned (1.2s ago)
dialogue queue: 0   playing: -
speed overrides: 0
```

Обновление раз в 0.5с (Timer внутри overlay):
- `FPS` — `Engine.get_frames_per_second()`.
- `last signal` — последний EventBus emit (имя + секунды назад). Заполняется из auto-trace; если trace=off, поле `—`.
- `dialogue queue` / `playing` — `DialogueManager._queue.size()` и `_current.id` (или `-`). Если `DialogueManager` нет в дереве — `n/a`.
- `speed overrides` — счётчик успешных команд `speed` с момента старта.

Все обращения к autoload'ам идут через `has_node` + `is_instance_valid`. Никаких null-крашей.

### E. Debug mode runtime flag

В `config/game_speed.cfg` секция `[dev]`:

```ini
[dev]
console_max_lines=80
debug_enabled=true
```

При старте DevConsole читает `debug_enabled` и применяет дефолты:

| `debug_enabled` | trace | filter level | overlay |
|---|---|---|---|
| `true` | on | DEBUG (всё) | off |
| `false` | off | INFO (DEBUG скрыт) | off |

Команды `trace` / `filter` / `overlay` всегда переопределяют независимо от cfg.

`GameLogger.debug(...)` всегда пишется в `print()` (Godot Output) — фильтр уровня действует только на отображение в **консоли**.

### F. История команд

- Стрелки ↑/↓ — навигация по `_history` (последние 20 уникальных записей).
- Enter — выполнить + push в history (если не дубликат предыдущей) + сбросить `_history_idx` + очистить поле.
- Esc внутри LineEdit — закрыть консоль (то же что F12).

### G. Интеграция с GameLogger

- `GameLogger._write` после `print(...)` дополнительно зовёт `DevConsole.push(level, tag, msg)` если `Engine.get_main_loop().root.has_node("DevConsole")`.
- Ref кешируется в `static var _console_ref: Node` модуля `game_logger.gd`. Проверка `is_instance_valid(_console_ref)` на каждом вызове, при первом null — повторный `has_node`.
- Без autoload DevConsole `has_node` возвращает false → ветка пропускается. Игра идентична текущему состоянию.

## Out of scope

- GDScript REPL (eval произвольного кода) — только заранее определённые команды.
- Сохранение лога в файл, экспорт буфера.
- Сетевые / мультиплеерные команды.
- Кастомные виджеты: графики, таймлайны, профайлер.
- Консоль в релизной сборке — release config убирает autoload.
- Мультистрочный ввод.
- Автодополнение по Tab.
- Аргументы для команды `emit` (только bare emit без параметров).

## Зависимости

- 001-bootstrap — GameLogger, GameSpeed, EventBus, AudioDirector autoloads.
- 003-dialogue-manager — команды `play`, `request`, `db`, `inspect dm`.

## Риски

- **EventBus auto-trace перегрузка**: если добавят high-frequency сигнал (например `turn_started` каждый кадр), лог зальётся. Митигация: `filter level INFO` выкидывает TRACE; либо `trace off`. Документируем в `help`.
- **`get_signal_list()` 4.6**: метод на `Object`, возвращает `Array[Dictionary]` с ключом `name`. Проверить: https://docs.godotengine.org/en/4.6/classes/class_object.html#class-object-method-get-signal-list.
- **CanvasLayer layer=20 коллизия**: если другие сцены UI используют layer ≥20 — наложатся. На текущий момент таких нет; проверка при интеграции.
- **Передача переменного количества аргументов в Callable для auto-trace**: Godot 4.6 не поддерживает variadic `Callable`. Решение: коннектить отдельный метод-обработчик на каждый сигнал по типу `_on_signal_<arity>`, или генерировать lambda через `Callable.create` — выбор делается в plan.md.
