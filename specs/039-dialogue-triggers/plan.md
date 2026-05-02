# 039-dialogue-triggers — plan

См. `spec.md` для acceptance + scope. Этот документ — **HOW**: API, file paths, data flow, integration points.

## File map

| Path | Status | Purpose |
|---|---|---|
| `scripts/core/dialogue/dialogue_trigger.gd` | new | Pure data class (`class_name DialogueTrigger`) — поля + `from_dict` / `to_dict` / `validate`. |
| `scripts/core/maps/level_data.gd` | edit | Добавить `dialogue_triggers: Array[Dictionary]`, обновить `to_dict`/`from_dict`/`validate`. |
| `scripts/runtime/level_dialogue_director.gd` | new | Autoload. Lifecycle + signal connect/disconnect + condition resolve + DialogueManager dispatch. |
| `scripts/runtime/wave_controller.gd` | edit | +5 строк: emit `EventBus.wave_about_to_start(idx)` за фрейм до `_apply_wave_snapshot`. |
| `scripts/infrastructure/event_bus.gd` | edit | +1 signal: `wave_about_to_start(index: int)`. |
| `project.godot` | edit | +1 autoload: `LevelDialogueDirector` после `DialogueManager` и `MoodTracker` (если есть). |
| `scripts/presentation/dev/dialogue_trigger_panel.gd` | new | Editor panel. CRUD form + list. ≤ 300 строк (если упёрся — расщепляем form на отдельный `dialogue_trigger_form.gd`). |
| `scenes/dev/dialogue_trigger_panel.tscn` | new | Сцена панели. PanelContainer с VBox: header / list / form. |
| `scripts/presentation/ui/wave_timeline.gd` | edit | +метод `set_dialogue_trigger_markers(triggers, level)` — рисует маркеры в `Mode.EDIT`. ~30 строк. |
| `scenes/dev/map_editor.tscn` | edit | Инстанс DialogueTriggerPanel в HUD CanvasLayer. |
| `scripts/presentation/dev/map_editor_controller.gd` | edit | +`_wire_dialogue_trigger_panel`, +`_on_dialogue_trigger_*` handlers. **Целевой инкремент ≤ 60 строк** — без этого не подтверждаем, разбиваем. |
| `scripts/presentation/ui_theme.gd` | edit | +`DIALOGUE_TRIGGER_MARKER_COLOR`, +`DIALOGUE_TRIGGER_MARKER_RADIUS`. |
| `data/maps/sample_dialogues.json` | new | Sample-уровень для smoke. |
| `data/maps/_schema.md` | edit | +секция `dialogue_triggers[]` с полным описанием полей. |

## Data: `DialogueTrigger`

`scripts/core/dialogue/dialogue_trigger.gd` — value object, не extends Node.

```gdscript
class_name DialogueTrigger

const VALID_PLAY_MODES: Array[String] = ["request", "play"]

var id: StringName = &""
var event: StringName = &""
var dialogue_id: StringName = &""
var play_mode: String = "request"
var conditions: Dictionary = {}

static func from_dict(d: Dictionary) -> DialogueTrigger:
    var t := DialogueTrigger.new()
    t.id = StringName(str(d.get("id", "")))
    t.event = StringName(str(d.get("event", "")))
    t.dialogue_id = StringName(str(d.get("dialogue_id", "")))
    t.play_mode = str(d.get("play_mode", "request"))
    t.conditions = d.get("conditions", {}) as Dictionary
    return t

func to_dict() -> Dictionary: ...
func validate() -> Array[String]: ...   # см. AC-D3 в spec
```

В `LevelData` храним как `Array[Dictionary]` (а не `Array[DialogueTrigger]`) — чтобы `LevelSerializer` ел JSON напрямую без преобразования. Director конвертирует в `DialogueTrigger` при load уровня.

## Runtime: `LevelDialogueDirector`

```gdscript
# scripts/runtime/level_dialogue_director.gd, autoload "LevelDialogueDirector"
extends Node

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

# Active level state
var _level: LevelData = null
var _triggers: Array = []                    # Array[DialogueTrigger]
var _connected_signals: Array[Dictionary] = [] # [{event: StringName, callable: Callable}]
var _fired_per_run: Dictionary = {}           # StringName(trigger_id) -> bool
var _fired_per_session: Dictionary = {}       # StringName(trigger_id) -> bool

# Pending sequential play queue when multiple play-mode triggers match same event.
var _pending_plays: Array[StringName] = []
var _is_chaining: bool = false


func _ready() -> void:
    EventBus.run_started.connect(_on_run_started)
    EventBus.battle_started.connect(_on_battle_started)
    EventBus.battle_ended.connect(_on_battle_ended)
    EventBus.dialogue_finished.connect(_on_dialogue_finished)


func _on_run_started() -> void:
    _fired_per_run.clear()


func _on_battle_started(_arena_id: StringName) -> void:
    _disconnect_all()
    _level = ActiveLevel.current_level()  # см. ниже о ActiveLevel API
    if _level == null:
        return
    _triggers = _build_triggers(_level.dialogue_triggers)
    _connect_for_events()


func _on_battle_ended(_victory: bool) -> void:
    _disconnect_all()
    _level = null
    _triggers.clear()


func _build_triggers(raw: Array) -> Array:
    var out: Array = []
    for d in raw:
        var t = DialogueTrigger.from_dict(d)
        var errs = t.validate()
        if not errs.is_empty():
            for e in errs:
                GameLogger.warn("LevelDialogueDirector",
                    "trigger '%s' validation: %s" % [t.id, e])
        out.append(t)
    return out


func _connect_for_events() -> void:
    var unique_events: Dictionary = {}
    for t in _triggers:
        unique_events[t.event] = true

    for ev_sn in unique_events.keys():
        var ev_name: String = str(ev_sn)
        if not EventBus.has_signal(ev_name):
            GameLogger.warn("LevelDialogueDirector",
                "EventBus has no signal '%s' — triggers using it are dead" % ev_name)
            continue
        var cb: Callable = _make_handler(ev_sn)
        EventBus.connect(ev_name, cb)
        _connected_signals.append({"event": ev_sn, "callable": cb})


func _make_handler(event_name: StringName) -> Callable:
    # Variadic-args handler — Godot connect resolves args at emit-time.
    return func(arg0=null, arg1=null, arg2=null) -> void:
        _on_event_fired(event_name, [arg0, arg1, arg2])


func _on_event_fired(event_name: StringName, args: Array) -> void:
    for t in _triggers:
        if t.event != event_name:
            continue
        if _fired_per_run.has(t.id):
            continue
        if _fired_per_session.has(t.id):
            continue
        if not _conditions_pass(t, event_name, args):
            continue
        _try_fire(t)


func _conditions_pass(t: DialogueTrigger, event_name: StringName, args: Array) -> bool:
    var c: Dictionary = t.conditions
    # ── 1. Event-arg-bound conditions ──
    if c.has("wave_index"):
        var want: int = int(c["wave_index"])
        var got: int = -1
        # wave_started(idx, is_special), wave_cleared(idx, unused_turns),
        # wave_about_to_start(idx) — все имеют idx как arg0.
        if event_name in [&"wave_started", &"wave_cleared", &"wave_about_to_start",
                          &"skill_offer_about_to_open", &"skill_offer_closed"]:
            got = int(args[0]) if args[0] != null else -1
        if got != want:
            return false

    if c.has("absolute_turn"):
        if event_name != &"world_turn_ended":
            return false  # condition не применима к этому event
        var want_t: int = int(c["absolute_turn"])
        var got_t: int = int(args[0]) if args[0] != null else -1
        if got_t != want_t:
            return false

    if c.has("cleared_in_turns_lt"):
        if event_name != &"wave_cleared":
            return false
        var idx: int = int(args[0]) if args[0] != null else -1
        var unused: int = int(args[1]) if args[1] != null else 0
        if _level == null or idx < 0 or idx >= _level.waves.size():
            return false
        var ttn: int = int(_level.waves[idx].get("turns_to_next", 0))
        # «cleared faster than N turns» = unused >= ttn - N
        if unused < ttn - int(c["cleared_in_turns_lt"]):
            return false

    # ── 2. Global state conditions ──
    if c.has("mood_required"):
        var moods: Array = c["mood_required"]
        if not Engine.has_singleton("MoodTracker") and not _has_autoload("MoodTracker"):
            GameLogger.warn_once("LevelDialogueDirector",
                "MoodTracker absent — mood_required ignored on '%s'" % t.id)
        else:
            var dominant: StringName = MoodTracker.get_dominant()
            if dominant not in moods:
                return false

    if c.has("chance"):
        if randf() >= float(c["chance"]):
            return false

    return true


func _try_fire(t: DialogueTrigger) -> void:
    var dialogue_id: StringName = t.dialogue_id
    var ok: bool = false
    if t.play_mode == "play":
        if _is_chaining:
            _pending_plays.append(dialogue_id)
            ok = true
        else:
            ok = DialogueManager.play(dialogue_id)
            _is_chaining = ok
    else:  # "request"
        var resolved: StringName = DialogueManager.request(t.event, _make_context())
        ok = (resolved != &"")

    if not ok:
        return

    var c: Dictionary = t.conditions
    if c.get("once_per_run", false):
        _fired_per_run[t.id] = true
    if c.get("once_per_session", false):
        _fired_per_session[t.id] = true


func _on_dialogue_finished(_id: StringName) -> void:
    if _pending_plays.is_empty():
        _is_chaining = false
        return
    var next_id: StringName = _pending_plays.pop_front()
    _is_chaining = DialogueManager.play(next_id)


func _make_context() -> Dictionary:
    # Provided to DialogueManager.request for select-time conditions.
    var ctx: Dictionary = {"flags": []}
    # run_count placeholder — when meta-loop ships, fill it.
    ctx["run_count"] = 0
    return ctx


func _disconnect_all() -> void:
    for entry in _connected_signals:
        var cb: Callable = entry["callable"]
        var ev: String = str(entry["event"])
        if EventBus.is_connected(ev, cb):
            EventBus.disconnect(ev, cb)
    _connected_signals.clear()


func _has_autoload(name: String) -> bool:
    return get_node_or_null("/root/" + name) != null
```

**Notes:**
- `Engine.has_singleton` не работает для script-autoload'ов в Godot 4 — использует `_has_autoload` через path-lookup.
- `_make_handler` лямбда принимает до 3 опциональных аргументов — покрывает все наши signal arities (max — `wave_started(idx, is_special)` = 2, `damage_dealt` = 3 если когда-нибудь подвяжемся). Если потребуется больше — переделаем на `Callable.bindv` с явной arity.
- `_pending_plays` — простая FIFO-цепь для случая «два `play`-trigger'а на одном event». Между ними `await dialogue_finished`. Если play-mode trigger срабатывает пока непустая очередь — додобавляется в хвост.

## ActiveLevel API — нужен метод `current_level()`

Сейчас `ActiveLevel` (autoload, см. `scripts/runtime/active_level.gd`) держит `queued_path` и `playtest_origin`. Director'у нужно получить **актуальный загруженный** `LevelData`. Возможные пути:

1. **Расширить `ActiveLevel`** методом `current_level() -> LevelData` — после `LevelLoader` отдал результат, кладём туда же.
2. **EventBus сигнал** `level_loaded(level: LevelData)` — Director слушает, держит ref у себя.
3. **Tap on LevelLoader** — Director может найти WaveController-сцену и спросить у неё.

**Решение**: путь 2. `EventBus.level_loaded(level: LevelData)` — emit'ится из `LevelLoader.load_into(...)` в момент когда уровень полностью применён. Director слушает, держит ref. Это гасит race с `battle_started` (который может прийти раньше level_loaded, или одновременно).

В `event_bus.gd`:
```gdscript
signal level_loaded(level: LevelData)  # 039 — fired by LevelLoader after waves[0] applied
```

В `LevelLoader` — найти точку где `_apply_wave_snapshot(0)` отработал и эмитить. **Owner: Andrey (этой спекой) — additive emit, никаких правок логики.**

В Director'е `_on_battle_started` → ждём level_loaded; если он уже пришёл — берём ref сразу. Реализуем через простой бул-flag «loaded» + ленивая инициализация на первом event.

Уточнить детали загрузки и точный момент emit'а — на T002 (см. tasks.md).

## Editor: `DialogueTriggerPanel`

Сцена `scenes/dev/dialogue_trigger_panel.tscn`:

```
PanelContainer (DialogueTriggerPanel script)
└── VBox
    ├── Header: HBox [Label "Dialogue triggers"  ·  CountLabel "5 triggers"  ·  ToggleCollapseBtn]
    ├── List: ItemList (selectable, не reorderable v1)
    ├── ButtonsRow: HBox [Add  ·  Edit  ·  Duplicate  ·  Delete]
    └── EditForm: CollapsibleVBox  (visible только в Add/Edit режиме)
        ├── IdRow:        Label + LineEdit
        ├── EventRow:     Label + OptionButton + LineEdit (custom mode)
        ├── DialogueRow:  Label + LineEdit (filter) + OptionButton (popup with filtered list)
        ├── PlayModeRow:  Radio [request/play]
        ├── ConditionsSection:
        │   ├── CheckBox + Label + ValueEditor для каждого condition kind
        │   └── ...
        └── FormButtonsRow: [Save  ·  Cancel]
```

Скрипт `dialogue_trigger_panel.gd` — экспонирует сигналы:

```gdscript
signal trigger_created(trigger_dict: Dictionary)
signal trigger_updated(old_id: StringName, trigger_dict: Dictionary)
signal trigger_deleted(trigger_id: StringName)
signal trigger_marker_clicked_request(trigger_id: StringName)  # для подсветки на timeline
```

Editor controller подписывается, обновляет `_level.dialogue_triggers`, дёргает `_mark_dirty()`, `_refresh_dialogue_trigger_panel()`, `_refresh_timeline_markers()`.

**Не лезем в ServiceLayer**: panel читает `DialogueDB.get_all_ids()` напрямую (как `dialogue_preview` уже делает).

## Editor: timeline markers

Расширение `scripts/presentation/ui/wave_timeline.gd`:

```gdscript
# В Mode.EDIT — после _rebuild() добавить marker pass.
# Приватный _trigger_markers: Array[Dictionary] — установлен извне.
# Каждый element: {trigger_id, event, dialogue_id, x, y, summary}.

func set_dialogue_trigger_markers(triggers: Array, level: LevelData) -> void:
    if mode != Mode.EDIT:
        _trigger_markers.clear()
        return
    _trigger_markers = _layout_markers(triggers, level)
    queue_redraw()  # for _draw to pick up

func _layout_markers(triggers: Array, level: LevelData) -> Array:
    # Map (event, conditions) → x position on bar.
    # wave_*: anchor x of waves[wave_index]
    # world_turn: PADDING_LEFT + absolute_turn * PIXELS_PER_TURN
    # level_started: anchor of wave 0
    # level_completed: last anchor
    # без index/turn → fallback `Misc` slot at far right
    # vertical stack — count markers at same x, offset Y by row.
    ...

func _draw() -> void:
    # ... existing bar/anchor/number draw ...
    for m in _trigger_markers:
        var c: Color = UiThemeScript.DIALOGUE_TRIGGER_MARKER_COLOR
        draw_circle(Vector2(m.x, m.y), UiThemeScript.DIALOGUE_TRIGGER_MARKER_RADIUS, c)
```

Hover/click обработка — через transparent ButtonControl поверх кружка (стандартный паттерн в Godot 4 для clickable shapes), либо `_gui_input` + ручной hit-test. Выберу хит-тест на `_gui_input` — меньше нод.

## Wiring в `map_editor_controller.gd`

Цель ≤60 строк добавлений. Паттерн — копия `_wire_wave_panel`.

```gdscript
@export var dialogue_trigger_panel_path: NodePath

var _dialogue_trigger_panel: Node

func _ready() -> void:
    # ... existing ...
    _dialogue_trigger_panel = _resolve(dialogue_trigger_panel_path, "HUD/DialogueTriggerPanel")
    # ... existing ...
    _wire_dialogue_trigger_panel()


func _wire_dialogue_trigger_panel() -> void:
    if _dialogue_trigger_panel == null: return
    _dialogue_trigger_panel.trigger_created.connect(_on_dlg_trigger_created)
    _dialogue_trigger_panel.trigger_updated.connect(_on_dlg_trigger_updated)
    _dialogue_trigger_panel.trigger_deleted.connect(_on_dlg_trigger_deleted)
    _dialogue_trigger_panel.trigger_marker_clicked_request.connect(_on_dlg_trigger_marker_request)
    # Initial bind
    if _dialogue_trigger_panel.has_method("bind_level"):
        _dialogue_trigger_panel.bind_level(_level)


func _on_dlg_trigger_created(d: Dictionary) -> void:
    _history.push(_level)
    _level.dialogue_triggers.append(d)
    _refresh_dialogue_trigger_panel()
    _refresh_timeline_dialogue_markers()
    _mark_dirty()

# updated/deleted/marker_request — аналогично
```

Не плодим helpers в контроллере, всё heavy в panel'е.

## Sample level

`data/maps/sample_dialogues.json` — основан на `sample_waves.json`, добавлено поле `dialogue_triggers`. Содержит 5 триггеров из §6 спеки. **Создаём отдельный файл, не правим sample_waves.json** — чтобы старые smoke runs не сломались.

## Schema doc

`data/maps/_schema.md` — дописать секцию:

```markdown
### dialogue_triggers (added in 039)

Optional. Array of trigger dictionaries.

```json
{
  "id": "lvl2_intro",         // unique within level
  "event": "level_started",   // EventBus signal name
  "dialogue_id": "boss_intro",
  "play_mode": "play",        // "request" | "play"
  "conditions": {
    "wave_index": 0,
    "absolute_turn": 40,
    "cleared_in_turns_lt": 4,
    "mood_required": ["burnout"],
    "chance": 1.0,
    "once_per_run": true,
    "once_per_session": false
  }
}
```

Conditions are AND. Curated events: `level_started`, `wave_about_to_start`,
`wave_started`, `wave_cleared`, `world_turn`, `skill_offer_about_to_open`,
`skill_offer_closed`, `level_completed`. Open vocabulary — any
`EventBus.<signal_name>` works at runtime.
```

## Test plan

Smoke order (manual, в Godot editor):

1. Open `map_editor.tscn` → создай новый уровень → добавь wave 1 (turns_to_next=5). DialogueTriggerPanel виден.
2. Add trigger: id="t1", event=`level_started`, dialogue_id=`boss_intro`, play_mode=`play`. Save → list показывает t1, marker на anchor волны 0.
3. Add trigger: id="t2", event=`wave_cleared`, wave_index=0, dialogue_id=`boss_tired`. Marker на той же точке, стек выше.
4. Save level as `test_triggers.json` → Playtest → t1 играется на старте уровня → проходим волну → t2 проигрывается.
5. Add trigger с event=`world_turn`, absolute_turn=3 → playtest → на 3-м ходу диалог стреляет.
6. Установить trigger c `cleared_in_turns_lt=2` → клир за 1 ход (`unused_turns=4`, ttn=5, 4 >= 5-2 → fire).
7. Удалить trigger через delete → confirm → list пусто, marker исчез.

## Risk register

- **R1 (Variadic Callable).** Godot 4.6 `Callable` принимает ограниченное число аргументов. Лямбда `func(arg0=null, arg1=null, arg2=null)` покроет все наши текущие signal arities; если потребуется > 3 — переходим на `Callable.bind` per-event.
- **R2 (battle_started vs level_loaded race).** Закрываем introducing `level_loaded` сигнал и ленивой инициализацией Director.
- **R3 (Editor controller bloat).** Hard ceiling +60 строк. Если не укладываемся — выносим вспомогательные методы в panel, или (в крайнем случае) добавляем sibling-node `DialogueTriggerEditorBridge` как 032/033 паттерн.
- **R4 (Once-tracking persistence).** `_fired_per_run/_session` живут только в памяти процесса. Save-system отсутствует, не наша задача. Одобрено в 003.
- **R5 (validate ergonomics).** Validate WARN на missing dialogue_id может затопить лог если у нас 30 триггеров и DB пустой. Throttle через warn-once per (level, dialogue_id) ключ.
