# 004-dev-console — plan

## Файлы

- `scripts/infrastructure/dev_console.gd` — Node-autoload `DevConsole`. Лог + командный парсер.
- `scenes/dev/dev_console.tscn` — UI сцены (инстанцируется autoload'ом).
- `scripts/infrastructure/game_logger.gd` — добавить push в DevConsole (1 строка).
- `project.godot` — добавить `DevConsole` последним в `[autoload]`.
- `config/game_speed.cfg` — добавить `[dev] console_max_lines=80`.

## Архитектура

```
DevConsole (Node, autoload)
  └─ инстанцирует dev_console.tscn в CanvasLayer(layer=20)
       ├─ VBoxContainer
       │   ├─ RichTextLabel#Log   (scroll, bbcode, fit_content=false)
       │   └─ LineEdit#Input      (history вверх/вниз)
       └─ toggle по F12
```

DevConsole — autoload, значит `GameLogger` может делать `get_node("/root/DevConsole")` без preload.

## GameLogger интеграция

```gdscript
# В конце каждого метода log():
var console = Engine.get_singleton("DevConsole") if Engine.has_singleton("DevConsole") else null
# Нет — проще:
if Engine.get_main_loop().root.has_node("DevConsole"):
    Engine.get_main_loop().root.get_node("DevConsole").push(level, tag, msg)
```

Вызов одноразово кешируется в `_console_ref` чтобы не делать `has_node` каждый раз.

## Командный парсер

```gdscript
func _execute(raw: String) -> void:
    var parts := raw.strip_edges().split(" ", false)
    if parts.is_empty(): return
    match parts[0]:
        "help":   _cmd_help()
        "play":   _cmd_play(parts)
        "request": _cmd_request(parts)
        "emit":   _cmd_emit(parts)
        "speed":  _cmd_speed(parts)
        "clear":  _cmd_clear()
        "db":     _cmd_db()
        _:        _log_console(\"unknown command '%s'\" % parts[0])
```

## Цвета bbcode

```
DEBUG → [color=#888888]
INFO  → [color=#ffffff]
WARN  → [color=#ffcc00]
ERROR → [color=#ff4444]
CMD   → [color=#88ffcc]   # команды пользователя
```

## История команд

`_history: Array[String]`, `_history_idx: int`. Стрелка вверх — `_history_idx--`, стрелка вниз — `_history_idx++`. При Enter: append + reset idx. Лимит 20 записей.

## Allowed emit signals

```gdscript
const ALLOWED_SIGNALS := ["run_started", "wave_spawned", "portal_opened", "run_ended"]
```

Остальные — warn в консоль, не эмитим.
