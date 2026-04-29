# 004-dev-console — spec

**Owner:** Andrey
**Status:** planned

## Цель

In-game dev консоль: лог игровых событий прямо на экране + командная строка для вызова тестовых действий (воспроизвести диалог, эмитить EventBus-сигнал, менять GameSpeed). Заменяет постоянное переключение в Godot Output и сцену `dialogue_preview`.

## Acceptance criteria

### Отображение

- По `F12` — консоль toggle (show/hide). Поверх всего (CanvasLayer layer=20).
- Верхняя часть — скроллируемый лог последних N строк (N из `game_speed.cfg`, дефолт 80).
- Лог пишет все `GameLogger` вызовы в реальном времени: `[LEVEL][TAG] msg` с временной меткой.
- Каждый уровень своим цветом: DEBUG=серый, INFO=белый, WARN=жёлтый, ERROR=красный. RichTextLabel + bbcode.
- Нижняя часть — однострочный LineEdit для команд. Enter — выполнить, история команд по стрелкам вверх/вниз (последние 20).

### Команды (MVP)

| Команда | Действие |
|---|---|
| `help` | список команд |
| `play <id>` | `DialogueManager.play(id, true)` |
| `request <event>` | `DialogueManager.request(event, {}, true)` |
| `emit <signal>` | `EventBus.<signal>.emit()` — только из заранее разрешённого списка (run_started, wave_spawned, portal_opened) |
| `speed <section> <key> <value>` | перезаписать значение GameSpeed в памяти (не в файле) |
| `clear` | очистить лог в консоли |
| `db` | вывести все id из DialogueDB |

### Интеграция с GameLogger

- `GameLogger` при каждом вызове дополнительно пушит строку в консоль (если та существует).
- Консоль **не обязательна** — GameLogger проверяет `has_node("/root/DevConsole")`, если нет — только `print`. Игра без консоли не ломается.

### Dev-only

- Консоль присутствует только при наличии autoload `DevConsole` в `project.godot`.
- На релизе — просто убрать autoload из project.godot. Код трогать не надо.

## Out of scope

- GDScript REPL (eval произвольного кода).
- Сохранение лога в файл.
- Сетевые команды.
- Консоль в релизной сборке (только debug).

## Зависимости

- 001-bootstrap (GameLogger, autoloads).
- 003-dialogue-manager (команды `play`, `request`, `db`).
