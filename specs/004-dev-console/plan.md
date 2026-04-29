# 004-dev-console — plan

## Файлы

- `scripts/infrastructure/dev_console.gd` — Node-autoload `DevConsole`. Вся логика: лог, парсер команд, фильтр, history, EventBus auto-trace, overlay-данные.
- `scenes/dev/dev_console.tscn` — UI (CanvasLayer + Panel + VBox + RichTextLabel + LineEdit + overlay Control).
- `scripts/infrastructure/game_logger.gd` — добавить кеш-ref на DevConsole и push после `print`.
- `project.godot` — добавить `DevConsole` последним в `[autoload]`.
- `config/game_speed.cfg` — добавить секцию `[dev]` с `console_max_lines=80` и `debug_enabled=true`.

Всё. Никаких новых директорий, никаких отдельных файлов под фильтр / overlay / парсер. Один скрипт ~250 строк — компактно для джема.

## Архитектура сцены

```
DevConsole (Node, autoload)
└─ инстанцирует scenes/dev/dev_console.tscn в _ready()
   └─ CanvasLayer (layer=20)
      ├─ Panel#Root (full-rect, mouse_filter=stop, modulate.a=0.88, visible=false)
      │  └─ VBoxContainer (margin=8)
      │     ├─ RichTextLabel#Log (size_flags_v=expand_fill, scroll_active, bbcode_enabled, fit_content=false)
      │     └─ LineEdit#Input
      └─ Control#Overlay (anchor top_right, margin=8, visible=false)
         └─ Label#OverlayText (theme_override font_size=12, modulate.a=0.9)
```

Toggle консоли — `Panel#Root.visible = !visible`.
Toggle overlay — `Control#Overlay.visible = !visible`.

## Базовая структура `dev_console.gd`

```gdscript
extends Node

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const SCENE := preload("res://scenes/dev/dev_console.tscn")

const ALLOWED_SIGNALS := [
    "run_started", "wave_spawned", "portal_opened",
    "run_ended", "battle_started", "battle_ended"
]
const COLOR := {
    "DEBUG": "#888888", "INFO": "#ffffff", "WARN": "#ffcc00",
    "ERROR": "#ff4444", "CMD": "#88ffcc", "TRACE": "#66aaff"
}
const LEVEL_ORDER := {"DEBUG": 0, "INFO": 1, "WARN": 2, "ERROR": 3}

var _ui: Control
var _log_rtl: RichTextLabel
var _input: LineEdit
var _overlay: Control
var _overlay_label: Label
var _max_lines: int = 80

# Filter
var _min_level: int = 0   # 0=DEBUG (everything), 3=ERROR only
var _tag_filter: String = ""

# History
var _history: Array[String] = []
var _history_idx: int = -1

# EventBus trace
var _trace_enabled: bool = false
var _trace_connections: Array = []   # {signal: String, callable: Callable}
var _last_signal_name: String = ""
var _last_signal_time_ms: int = 0

# Stats
var _speed_overrides: int = 0
```

## `_ready` последовательность

```gdscript
func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS   # работаем при pause
    _ui = SCENE.instantiate()
    add_child(_ui)
    _log_rtl = _ui.get_node("CanvasLayer/Panel/VBox/Log")
    _input = _ui.get_node("CanvasLayer/Panel/VBox/Input")
    _overlay = _ui.get_node("CanvasLayer/Overlay")
    _overlay_label = _overlay.get_node("OverlayText")
    _input.text_submitted.connect(_on_submitted)
    _input.gui_input.connect(_on_input_gui)

    var max_lines: int = int(GameSpeed.get_value("dev", "console_max_lines", 80))
    _max_lines = max_lines
    var debug: bool = bool(GameSpeed.get_value("dev", "debug_enabled", true))

    if debug:
        _trace_on()
        _min_level = LEVEL_ORDER["DEBUG"]
    else:
        _min_level = LEVEL_ORDER["INFO"]

    var t := Timer.new()
    t.wait_time = 0.5
    t.autostart = true
    t.timeout.connect(_refresh_overlay)
    add_child(t)
```

## Вход / hotkeys

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_F12:
            _toggle_panel()
            get_viewport().set_input_as_handled()
        elif event.keycode == KEY_F12 and event.shift_pressed:
            _toggle_overlay()
            get_viewport().set_input_as_handled()
```

Shift+F12 — Godot фильтрует Shift отдельно: проверять `event.shift_pressed` **раньше** чем `keycode == KEY_F12` без shift, иначе один блок съест оба. Правильный порядок:

```gdscript
if event.keycode == KEY_F12:
    if event.shift_pressed:
        _toggle_overlay()
    else:
        _toggle_panel()
    get_viewport().set_input_as_handled()
```

Esc внутри LineEdit — отдельно через `_on_input_gui`.

## `push(level, tag, msg)` — публичный API

```gdscript
func push(level: int, tag: String, msg: String) -> void:
    var lvl_name: String = ["DEBUG", "INFO", "WARN", "ERROR"][level]
    _push_colored(lvl_name, tag, msg)


func _push_colored(lvl_name: String, tag: String, msg: String) -> void:
    # Filter
    if lvl_name in LEVEL_ORDER and LEVEL_ORDER[lvl_name] < _min_level:
        return
    if _tag_filter != "" and tag != _tag_filter:
        return
    var t := Time.get_time_string_from_system()
    var color: String = COLOR.get(lvl_name, "#ffffff")
    var line := "[color=%s]%s [%s][%s][/color] %s" % [color, t, lvl_name, tag, msg]
    _log_rtl.append_text(line + "\n")
    _trim_log()


func _trim_log() -> void:
    # RichTextLabel доступ к строкам — through get_paragraph_count + remove_paragraph
    while _log_rtl.get_paragraph_count() > _max_lines:
        _log_rtl.remove_paragraph(0)
```

## Командный парсер

```gdscript
func _on_submitted(raw: String) -> void:
    var line := raw.strip_edges()
    if line == "":
        _input.clear()
        return
    _push_colored("CMD", "console", "> " + line)
    if _history.is_empty() or _history.back() != line:
        _history.append(line)
        if _history.size() > 20:
            _history.pop_front()
    _history_idx = _history.size()
    _input.clear()
    _execute(line)


func _execute(raw: String) -> void:
    var parts := raw.split(" ", false)
    if parts.is_empty():
        return
    match parts[0]:
        "help":    _cmd_help()
        "play":    _cmd_play(parts)
        "request": _cmd_request(parts)
        "emit":    _cmd_emit(parts)
        "speed":   _cmd_speed(parts)
        "clear":   _log_rtl.clear()
        "db":      _cmd_db()
        "inspect": _cmd_inspect(parts)
        "pause":   get_tree().paused = true
        "resume":  get_tree().paused = false
        "filter":  _cmd_filter(parts)
        "trace":   _cmd_trace(parts)
        "overlay": _cmd_overlay(parts)
        _:         push(2, "console", "unknown command '%s'" % parts[0])  # WARN
```

## EventBus auto-trace — техническая часть

Variadic Callable в Godot 4.6 нет. Решение: использовать `Callable` с одним аргументом-массивом не получится — сигнал передаёт распакованные аргументы. Способ — `signal.connect(target, flags)` через создание lambda **на лету** не позволяет захватить имя.

Рабочий вариант: использовать `Object.connect(signal_name, callable, flags)` где `callable` создаётся через **`Callable(self, "_on_traced_signal").bindv([signal_name])`**. `bindv` префиксует аргументы — обработчик получает `(signal_name_bound, ...emitted_args)`.

```gdscript
func _trace_on() -> void:
    if _trace_enabled:
        return
    if not _has_eventbus():
        push(2, "DevConsole", "trace: EventBus autoload not found")
        return
    var eb: Node = get_node("/root/EventBus")
    for sig in eb.get_signal_list():
        var name: String = sig["name"]
        if name.begins_with("_"):
            continue
        var cb := Callable(self, "_on_traced_signal").bindv([name])
        var err := eb.connect(name, cb)
        if err == OK:
            _trace_connections.append({"signal": name, "callable": cb})
    _trace_enabled = true
    push(1, "DevConsole", "trace: connected to %d signals" % _trace_connections.size())


func _trace_off() -> void:
    if not _trace_enabled:
        return
    var eb: Node = get_node_or_null("/root/EventBus")
    if eb:
        for c in _trace_connections:
            if eb.is_connected(c.signal, c.callable):
                eb.disconnect(c.signal, c.callable)
    _trace_connections.clear()
    _trace_enabled = false
    push(1, "DevConsole", "trace: off")


func _on_traced_signal(signal_name: String, arg0 = null, arg1 = null, arg2 = null, arg3 = null) -> void:
    var args := []
    for a in [arg0, arg1, arg2, arg3]:
        if a == null:
            break
        args.append(str(a))
    var s := signal_name + "(" + ", ".join(args) + ")"
    _last_signal_name = signal_name
    _last_signal_time_ms = Time.get_ticks_msec()
    _push_colored("TRACE", "EventBus", s)
```

Слабое место: 4 «слота» для аргументов. Если сигнал имеет >4 — обрежется. Проверить — в EventBus текущие сигналы имеют максимум 3 (`spell_cast(actor_id, spell_id, targets)`). Добавим 4 для запаса, при добавлении нового сигнала с >4 args — расширим.

Альтернатива на потом: GDScript lambda через `func(): ...` с захватом имени — но в 4.6 lambda не передаёт переменное число аргументов, ровно та же проблема.

Документация: https://docs.godotengine.org/en/4.6/classes/class_callable.html#class-callable-method-bindv

## Filter — реализация

```gdscript
func _cmd_filter(parts: PackedStringArray) -> void:
    if parts.size() < 3:
        push(2, "console", "usage: filter level <DEBUG|INFO|WARN|ERROR|all>  |  filter tag <name|clear>")
        return
    match parts[1]:
        "level":
            var v: String = parts[2].to_upper()
            if v == "ALL":
                _min_level = -1
            elif v in LEVEL_ORDER:
                _min_level = LEVEL_ORDER[v]
            else:
                push(2, "console", "unknown level '%s'" % parts[2])
                return
            push(1, "console", "filter level = %s" % v)
        "tag":
            if parts[2] == "clear":
                _tag_filter = ""
                push(1, "console", "filter tag cleared")
            else:
                _tag_filter = parts[2]
                push(1, "console", "filter tag = '%s'" % _tag_filter)
        _:
            push(2, "console", "unknown filter '%s'" % parts[1])
```

TRACE не в LEVEL_ORDER → проходит фильтр всегда **если** `_min_level <= 0`. Уточнение: добавить TRACE в LEVEL_ORDER со значением `-1`, чтобы `level INFO` (1) скрывал TRACE и DEBUG. Поправим в `LEVEL_ORDER`:

```gdscript
const LEVEL_ORDER := {"TRACE": -1, "DEBUG": 0, "INFO": 1, "WARN": 2, "ERROR": 3}
```

И в `_push_colored` сравнение `< _min_level` теперь корректно отфильтрует TRACE при `_min_level >= 0`.

## Overlay refresh

```gdscript
func _refresh_overlay() -> void:
    if not _overlay.visible:
        return
    var fps: int = int(Engine.get_frames_per_second())
    var sig := "—"
    if _last_signal_name != "":
        var ago_s: float = (Time.get_ticks_msec() - _last_signal_time_ms) / 1000.0
        sig = "%s (%.1fs ago)" % [_last_signal_name, ago_s]
    var dq := "n/a"
    var dp := "-"
    var dm: Node = get_node_or_null("/root/DialogueManager")
    if dm and "_queue" in dm and "_current" in dm:
        dq = str(dm._queue.size())
        dp = str(dm._current.id) if dm._current else "-"
    _overlay_label.text = "FPS: %d\nlast signal: %s\ndialogue queue: %s   playing: %s\nspeed overrides: %d" % [fps, sig, dq, dp, _speed_overrides]
```

`dm._queue` / `dm._current` — приватные поля DialogueManager. Использование `in` проверяет наличие property → не упадём если рефакторят. Если упадёт — заменим на тонкий публичный accessor, но не сейчас (не хочется трогать чужой autoload в этой ветке).

## GameLogger интеграция

`scripts/infrastructure/game_logger.gd`:

```gdscript
extends RefCounted

const Level = ...   # как сейчас

static var _console_ref: Node = null

static func _write(level: int, tag: String, msg: String) -> void:
    var prefix: String = "[%s][%s]" % [Level.keys()[level], tag]
    print("%s %s" % [prefix, msg])
    _push_to_console(level, tag, msg)


static func _push_to_console(level: int, tag: String, msg: String) -> void:
    if not is_instance_valid(_console_ref):
        var loop := Engine.get_main_loop()
        if loop == null:
            return
        var root: Node = loop.root if "root" in loop else null
        if root == null or not root.has_node("DevConsole"):
            return
        _console_ref = root.get_node("DevConsole")
    _console_ref.push(level, tag, msg)
```

Без autoload DevConsole `has_node` возвращает false → `_console_ref` остаётся null → следующий вызов снова try-fetch. Дёшево.

## inspect — реализация

```gdscript
func _cmd_inspect(parts: PackedStringArray) -> void:
    if parts.size() < 2:
        push(2, "console", "usage: inspect <dm|gs|eb>")
        return
    match parts[1]:
        "dm":
            var dm: Node = get_node_or_null("/root/DialogueManager")
            if not dm:
                push(2, "console", "DialogueManager not found")
                return
            var qs: int = dm._queue.size() if "_queue" in dm else -1
            var cur: String = str(dm._current.id) if dm._current else "-"
            push(1, "inspect", "DM: queue=%d, current=%s" % [qs, cur])
        "gs":
            var gs: Node = get_node_or_null("/root/GameSpeed")
            if not gs:
                push(2, "console", "GameSpeed not found")
                return
            push(1, "inspect", "GS: cfg loaded=%s" % str(gs._cfg != null))
        "eb":
            var eb: Node = get_node_or_null("/root/EventBus")
            if not eb:
                push(2, "console", "EventBus not found")
                return
            var sigs := []
            for s in eb.get_signal_list():
                if not s.name.begins_with("_"):
                    sigs.append(s.name)
            push(1, "inspect", "EB signals: " + ", ".join(sigs))
        _:
            push(2, "console", "unknown target '%s'" % parts[1])
```

## История команд

```gdscript
func _on_input_gui(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_UP:
                if _history.is_empty():
                    return
                _history_idx = max(0, _history_idx - 1)
                _input.text = _history[_history_idx]
                _input.caret_column = _input.text.length()
                get_viewport().set_input_as_handled()
            KEY_DOWN:
                if _history.is_empty():
                    return
                _history_idx = min(_history.size(), _history_idx + 1)
                if _history_idx >= _history.size():
                    _input.text = ""
                else:
                    _input.text = _history[_history_idx]
                _input.caret_column = _input.text.length()
                get_viewport().set_input_as_handled()
            KEY_ESCAPE:
                _toggle_panel()
                get_viewport().set_input_as_handled()
```

## ALLOWED_SIGNALS — `emit`

```gdscript
func _cmd_emit(parts: PackedStringArray) -> void:
    if parts.size() < 2:
        push(2, "console", "usage: emit <signal>")
        return
    var name: String = parts[1]
    if not (name in ALLOWED_SIGNALS):
        push(2, "console", "signal '%s' not in allowlist" % name)
        return
    var eb := get_node_or_null("/root/EventBus")
    if not eb:
        push(2, "console", "EventBus not found")
        return
    eb.emit_signal(name)
    push(1, "console", "emitted %s" % name)
```

Bare emit без аргументов — для большинства сигналов в EventBus подойдёт (`run_started`, `portal_opened`, `wave_spawned` упадёт на проверке аргументов). Намеренная скромная фича: если нужно эмитить с args — добавим парсинг типов в v2.

## `help` — пример вывода

```
play <id>           — play dialogue by id
request <event>     — request dialogue by event
emit <signal>       — emit one of: run_started, wave_spawned, portal_opened, run_ended, battle_started, battle_ended
speed <s> <k> <v>   — override GameSpeed value (in-memory)
clear               — clear console log
db                  — list dialogue ids
inspect <dm|gs|eb>  — autoload state
pause / resume      — toggle scene tree pause
filter level <L>    — DEBUG | INFO | WARN | ERROR | all
filter tag <name|clear>
trace on/off        — EventBus auto-trace
overlay on/off      — debug HUD overlay
help                — this list

current: filter=INFO, trace=off, overlay=off
```

## Проверка: Godot 4.6 API

- `RichTextLabel.append_text` — да, доступен. https://docs.godotengine.org/en/4.6/classes/class_richtextlabel.html#class-richtextlabel-method-append-text
- `RichTextLabel.get_paragraph_count` / `remove_paragraph` — оба есть.
- `Object.get_signal_list` — `Array[Dictionary]`, ключ `name`.
- `Callable.bindv` — да. Возвращает новый Callable с префиксованными аргументами.
- `Engine.get_frames_per_second` — есть.
- `Time.get_time_string_from_system` — есть. Формат `HH:MM:SS`.

## Что НЕ в plan'е (избегаем scope creep)

- Подсветка синтаксиса для команд.
- Tab-автокомплит.
- Команда `record` для записи макроса.
- Ремоут-консоль через TCP.
- Сохранение настроек фильтра между запусками.
- Парсинг типизированных аргументов для `emit`.

Если кто-то хочет — отдельный спек, не сюда.
