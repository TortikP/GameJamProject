# 062 — Validation Pipeline · Plan

8 фаз. Целевой объём: ~700-900 GDScript LOC (новый код), ~25 loc keys,
2 новые сцены, 1 новый overlay node. Без новых autoload'ов.

| Φ | Что | Объём (LOC новых) | Зависит от |
|---|---|---|---|
| 0 | Recon (заметки в findings.md, без кода) | 0 | — |
| 1 | ValidationIssue class + EN/RU loc keys | ~80 + json | 0 |
| 2 | LevelData.validate() → Array[ValidationIssue]; миграция game_editor consumer | ~150 (refactor) | 1 |
| 3 | ValidationCoordinator (Node, debouncer) | ~120 | 2 |
| 4 | ProblemListPanel scene + script | ~180 | 3 |
| 5 | WaveSettingsPanel: tab badges + inline labels + UiTheme constants | ~140 | 3, 4 |
| 6 | HexValidationOverlay | ~100 | 3 |
| 7 | Save/load wiring в EditorController | ~50 | 3, 4, 5, 6 |
| 8 | Manual smoke + polish | 0 | All |

Цель: один PR, мерджу в staging как обычно. PR может разбиться на
2 коммит-блока (Φ-1..2 = backend; Φ-3..7 = UI обвязка) для удобства
ревью.

## Φ-0. Recon

**Что:** записать findings перед любым редактом.

**Артефакты:**
- `findings.md` в этой папке — пустой шаблон, заполняется по ходу.
- В spec.md уже есть инвентарь call-site'ов, не дублировать.

**Verify checklist (smoke перед началом):**
- [ ] `LevelData.validate()` есть, возвращает `Array[String]`, 25+
  `errors.append`-сайтов.
- [ ] `game_editor_controller.gd:260,334` — единственные внешние
  consumer'ы. Подтверждено grep'ом.
- [ ] `editor_io.gd::save()` validate НЕ вызывает.
- [ ] `editor_io.gd::enqueue_autosave()` validate НЕ вызывает (и не
  должен).
- [ ] `data/localization/{en,ru}.json` — keys `ui_dialogue_validate_*`
  есть (использует DialogueTrigger), `ui_trigger_validate_*` есть но не
  используется. Префикс `ui_validate_*` — свободен.
- [ ] `UiTheme` доступен из `scripts/presentation/dev/editor/`.
- [ ] WaveSettingsPanel использует tab UI (TabContainer или Buttons —
  уточнить в Φ-5).

## Φ-1. ValidationIssue + loc keys

**Файлы:**
- `scripts/core/validation/validation_issue.gd` (новый, `class_name
  ValidationIssue extends RefCounted`).
- `data/localization/en.json` — добавить ~25 ключей с префиксом
  `ui_validate_*` + 4 общих:
  - `ui_validate_save_blocked` — `«Cannot save: %d errors. See Problem List.»`
  - `ui_validate_save_with_warns` — `«Saved with %d warnings.»`
  - `ui_validate_panel_title` — `«Issues»`
  - `ui_validate_panel_empty` — `«No issues. Save unblocked.»`
- `data/localization/ru.json` — те же ключи RU.

**ValidationIssue API:**
```gdscript
class_name ValidationIssue
extends RefCounted

enum Severity { REJECT, WARN }

var severity: Severity
var path: String
var loc_key: StringName
var loc_args: Array
var message_fallback: String

static func reject(path_: String, loc_key_: StringName,
        args: Array = [], fallback: String = "") -> ValidationIssue:
    var i := ValidationIssue.new()
    i.severity = Severity.REJECT
    i.path = path_
    i.loc_key = loc_key_
    i.loc_args = args
    i.message_fallback = fallback if fallback != "" else String(loc_key_)
    return i

static func warn(path_: String, loc_key_: StringName,
        args: Array = [], fallback: String = "") -> ValidationIssue:
    # ... аналогично

func to_human() -> String:
    # Lazy resolver под Localization autoload — copy-paste из
    # DialogueTrigger._t/_tf (объясняется headless-safe нуждой
    # для GUT-тестов, см. dialogue_trigger.gd:63-84).
    var loop := Engine.get_main_loop()
    if loop is SceneTree:
        var loc: Node = (loop as SceneTree).root.get_node_or_null(^"Localization")
        if loc != null and loc.has_method(&"tf"):
            return loc.tf(String(loc_key), loc_args, message_fallback)
    return message_fallback % loc_args if loc_args.size() > 0 else message_fallback
```

**Loc keys (полный список):** см. `loc_keys.md` в этой папке (создаётся
вместе с .gd). Массив для копи-пасты в обе локали + 1:1 мэппинг на
существующие `errors.append` сайты.

**Verify:**
- [ ] `ValidationIssue.reject(...)` строит объект, `to_human()` отдаёт
  локализованную строку.
- [ ] При отсутствии Localization (headless) — fallback с %d/%s
  работает.

## Φ-2. LevelData.validate() refactor

**Файл:** `scripts/core/maps/level_data.gd` строки 144-283.

**Изменение signature:**
```gdscript
func validate() -> Array[ValidationIssue]:  # was Array[String]
```

**Замена паттерна для каждого `errors.append(string)`:**

Старое:
```gdscript
errors.append("Wave %d turns_to_next must be >= 1 (got %d)" % [i, ttn])
```

Новое:
```gdscript
errors.append(ValidationIssue.reject(
    "waves[%d].turns_to_next" % i,
    &"ui_validate_wave_ttn_too_low",
    [i, ttn],
    "Wave %d: turns_to_next must be >= 1 (got %d)"
))
```

WARN-prefixed → `ValidationIssue.warn(...)` без префикса в тексте
(severity несёт это).

**DialogueTrigger.validate() interop:** в цикле `for raw in
dialogue_triggers` (строки 253-275 текущего level_data.gd):

```gdscript
var t: DialogueTrigger = DialogueTrigger.from_dict(raw)
var t_errs: Array[String] = t.validate()
for e in t_errs:
    var sev := ValidationIssue.Severity.REJECT
    var msg := e
    if msg.begins_with("WARN: "):
        sev = ValidationIssue.Severity.WARN
        msg = msg.substr(6)
    var issue := ValidationIssue.new()
    issue.severity = sev
    issue.path = "level.dialogue_triggers[id=%s].*" % str(t.id)
    issue.loc_key = &""  # already-localized text
    issue.message_fallback = msg
    errors.append(issue)
```

То есть DialogueTrigger строки попадают в issue без `loc_key` — сам
текст уже локализован на месте (см. dialogue_trigger.gd). UI зовёт
`to_human()` который при пустом loc_key возвращает `message_fallback`
напрямую.

**Consumer миграция:** `scripts/presentation/dev/game_editor_controller.gd:260,334`.

Старое:
```gdscript
var msgs: Array[String] = _game.validate()
for m in msgs:
    GameLogger.warn("[GameEditor] " + m)
```

Новое:
```gdscript
var issues: Array[ValidationIssue] = _game.validate()
for issue in issues:
    var prefix := "[ERROR]" if issue.severity == ValidationIssue.Severity.REJECT else "[WARN]"
    GameLogger.warn("[GameEditor] %s %s" % [prefix, issue.to_human()])
```

(Nota bene: `_game` в game_editor_controller — это `GameData`, не
`LevelData`. Уточнить в Φ-2 что у GameData есть свой `validate()` или
этот call ссылается на LevelData. Проверить grep'ом перед редактом.)

**Verify:**
- [ ] Все 25+ `errors.append`-сайтов переписаны.
- [ ] Каждому issue соответствует loc_key из Φ-1.
- [ ] `game_editor_controller.gd` компилируется с новой signature.
- [ ] Запустить existing GUT тесты на LevelData (если есть) — все
  проходят.
- [ ] Headless smoke: `godot --headless --script scripts/scene_to_run.gd`
  не падает на parse'е новой сигнатуры.

## Φ-3. ValidationCoordinator

**Файл:** `scripts/presentation/dev/editor/validation_coordinator.gd`
(новый).

```gdscript
class_name ValidationCoordinator
extends Node

signal issues_changed(issues: Array[ValidationIssue])

const _DEBOUNCE_SEC: float = 0.2

var _level_provider: Callable
var _current: Array[ValidationIssue] = []
var _timer: Timer

func _ready() -> void:
    _timer = Timer.new()
    _timer.one_shot = true
    _timer.wait_time = _DEBOUNCE_SEC
    _timer.timeout.connect(_on_debounce_fire)
    add_child(_timer)

## level_provider: Callable returning the current LevelData. Stored as
## getter (not value) so the coordinator always sees the latest level
## reference — including after _on_new / _on_load swaps.
func setup(level_provider: Callable) -> void:
    _level_provider = level_provider

func request_revalidate() -> void:
    _timer.stop()
    _timer.start()

func revalidate_now() -> Array[ValidationIssue]:
    _timer.stop()
    _do_revalidate()
    return _current

func get_current_issues() -> Array[ValidationIssue]:
    return _current

func has_blocking_issues() -> bool:
    for i in _current:
        if i.severity == ValidationIssue.Severity.REJECT:
            return true
    return false

func issues_for_path_prefix(prefix: String) -> Array[ValidationIssue]:
    var out: Array[ValidationIssue] = []
    for i in _current:
        if i.path.begins_with(prefix):
            out.append(i)
    return out

func _on_debounce_fire() -> void:
    _do_revalidate()

func _do_revalidate() -> void:
    var lvl: LevelData = _level_provider.call()
    if lvl == null:
        _current = []
    else:
        _current = lvl.validate()
    issues_changed.emit(_current)
```

**EditorController integration:**
- В `_resolve_nodes` создать `ValidationCoordinator` и вызвать
  `setup(func(): return _level)`.
- После каждой мутации (paint/erase/cascade/add_wave/copy_wave/delete_wave/
  update_wave_field/_on_skill_offer_changed) — `_validation.request_revalidate()`.
- Dialogue trigger CRUD методы (от 061) — тоже `request_revalidate()`.
- В `_on_save()` — `revalidate_now()` (см. Φ-7).
- В `_on_load()`/`_on_new()` — `revalidate_now()` (см. Φ-7).

**Verify:**
- [ ] `request_revalidate()` 5 раз за 100ms = 1 fire через 200ms после
  последнего вызова.
- [ ] `revalidate_now()` мгновенный.
- [ ] `has_blocking_issues()` корректно различает REJECT и WARN.

## Φ-4. ProblemListPanel

**Файлы:**
- `scenes/dev/editor/problem_list_panel.tscn` (новая)
- `scripts/presentation/dev/editor/problem_list_panel.gd` (новый, ~180 LOC)

**Layout:**
- Panel root (UiTheme styling)
- VBoxContainer:
  - HBoxContainer (header):
    - Title Label («Issues: 3 errors, 2 warnings»)
    - Spacer
    - Filter Buttons (All / REJECT / WARN) — checkable, group
  - ItemList (списков issues, scrollable)

**Скрипт:**
```gdscript
class_name ProblemListPanel
extends Panel

signal jump_requested(path: String)

@export var coordinator_path: NodePath
@onready var _title: Label = $"%Title"
@onready var _list: ItemList = $"%List"
@onready var _filter_all: Button = $"%FilterAll"
@onready var _filter_reject: Button = $"%FilterReject"
@onready var _filter_warn: Button = $"%FilterWarn"

enum FilterMode { ALL, REJECT_ONLY, WARN_ONLY }
var _filter: FilterMode = FilterMode.ALL
var _current: Array[ValidationIssue] = []

func _ready() -> void:
    var coord := get_node_or_null(coordinator_path)
    if coord != null:
        coord.issues_changed.connect(_on_issues_changed)
    _list.item_activated.connect(_on_item_activated)
    _filter_all.pressed.connect(func(): _filter = FilterMode.ALL; _refresh())
    # ...
    UiTheme.apply_panel_kind(self, &"editor_dock")  # or similar

func _on_issues_changed(issues: Array[ValidationIssue]) -> void:
    _current = issues
    _refresh()

func _refresh() -> void:
    _list.clear()
    var rejects := 0
    var warns := 0
    for issue in _current:
        if issue.severity == ValidationIssue.Severity.REJECT: rejects += 1
        else: warns += 1
        if not _passes_filter(issue): continue
        var idx := _list.add_item(issue.to_human())
        _list.set_item_icon(idx, _icon_for(issue.severity))
        _list.set_item_metadata(idx, issue.path)
    _title.text = Localization.tf("ui_validate_panel_title_count",
        [_current.size(), rejects, warns],
        "Issues: %d (%d errors, %d warnings)")

func _on_item_activated(idx: int) -> void:
    var path: String = _list.get_item_metadata(idx)
    jump_requested.emit(path)
```

**EditorController wiring:**
- Подключить `problem_list_panel.jump_requested → _on_validation_jump(path)`.
- `_on_validation_jump` парсит path:
  - `waves[N].*` → `set_active_wave(N)` + если есть subfield, ProblemList
    UI достаточен для дизайнера, без auto-focus на конкретный SpinBox.
    (Auto-focus — nice-to-have в Φ-5 если будет дёшево.)
  - `level.dialogue_triggers[id=X].*` → `_meta_panel.select_trigger(X)` (signal
    уже есть в WaveSettingsPanel).
  - Coord-based path → emit signal `_grid.center_on_coord(c)` если
    grid поддерживает (если нет — toast'нуть coord).
  - `level.*` → no-op (LevelMetaPanel и так видна).

**Размещение в level_editor.tscn:** добавить ProblemListPanel в
существующий VBoxContainer на нижнем краю. Высота ~120px. Hidden если
issues пусто (collapse-toggle button). Точное место уточняем в Φ-4.

**Verify:**
- [ ] Панель показывает все issues после revalidate.
- [ ] Filter переключает видимость без ремаунта list.
- [ ] Click → jump_requested сигнал с правильным path.

## Φ-5. WaveSettingsPanel: tab badges + inline labels

**Файлы (правка):**
- `scripts/presentation/dev/wave_settings_panel.gd` (~+100 LOC).
- `scripts/presentation/dev/editor/validation_decorators.gd` (новый, ~40 LOC, helpers).
- `scripts/infrastructure/ui_theme.gd` (~+10 LOC: цветовые константы).

**ValidationDecorators (helpers):**
```gdscript
class_name ValidationDecorators
extends RefCounted

static func decorate_field_inline(host_container: Control,
        issue: ValidationIssue) -> Label:
    # Создаёт Label под host_container'ом с issue.to_human(),
    # цвет по severity, mouse_filter = IGNORE, autowrap = WORD,
    # имя "ValidationLabel" — для последующего clear'а. Возвращает
    # Label чтобы caller мог хранить ref.

static func clear_field_inline(host_container: Control) -> void:
    # Удаляет все child Label'ы с именем "ValidationLabel".

static func decorate_tab_badge(tab_button: Button,
        severity: ValidationIssue.Severity) -> void:
    # Добавляет/обновляет Label-child "ValidationBadge" в tab_button
    # с цветом по severity. REJECT перекрывает WARN.

static func clear_tab_badge(tab_button: Button) -> void:
    # Удаляет ValidationBadge child.
```

**WaveSettingsPanel.subscribe_validation:**
```gdscript
func subscribe_validation(coord: ValidationCoordinator) -> void:
    coord.issues_changed.connect(_on_issues_changed)

func _on_issues_changed(issues: Array[ValidationIssue]) -> void:
    _refresh_tab_badges(issues)
    _refresh_inline_labels(issues)

func _refresh_tab_badges(issues: Array[ValidationIssue]) -> void:
    # Per tab: filter issues by path, derive worst severity, decorate.
    # Tab «Level»: paths matching r"^level(\..*)?$"
    #   minus DialogueTriggers (что покрывается отдельным маркером).
    # Tab «Wave»: paths matching r"^waves\[N\]\..*$" где N == _active_wave
    #   minus Spawners / Skill Offer / Dialogue Triggers (свои табы).
    # ... и т.д.

func _refresh_inline_labels(issues: Array[ValidationIssue]) -> void:
    # Для каждого field-tracked path (turns_to_next, advance_mode,
    # skill_offer.pool/source/count) — decorate или clear.
```

**UiTheme константы:**
```gdscript
const VALIDATION_REJECT_FG: Color = Color("#e85d5d")
const VALIDATION_WARN_FG: Color = Color("#f0b550")
const VALIDATION_BADGE_REJECT: Color = Color("#d04040")
const VALIDATION_BADGE_WARN: Color = Color("#cc9920")
const VALIDATION_HEX_REJECT: Color = Color("#d04040", 0.35)
const VALIDATION_HEX_WARN: Color = Color("#cc9920", 0.30)
```

**Verify:**
- [ ] Невалидный turns_to_next (=0 в средней волне) → красный badge на
  табе Wave + inline label под полем.
- [ ] WARN-only skill_offer.pool (file not found) → жёлтый badge на
  табе Skill Offer.
- [ ] После фикса issue (turns_to_next=2) — после 200ms badge и label
  пропадают.

## Φ-6. HexValidationOverlay

**Файлы:**
- `scripts/presentation/dev/editor/hex_validation_overlay.gd` (новый, ~80 LOC).
- В `scenes/dev/level_editor.tscn` — добавить ноду между
  `objects_overlay` и UI слоем (поверх gridа, ниже UI).

**Скрипт:**
```gdscript
class_name HexValidationOverlay
extends Node2D

@export var grid_path: NodePath
@export var coordinator_path: NodePath

const _COORD_RX := RegEx.create_from_string(r"\[coord=\((-?\d+),(-?\d+)\)\]")

var _grid: HexGrid
var _highlights: Array = []  # [{coord, severity}]

func _ready() -> void:
    _grid = get_node_or_null(grid_path)
    var coord := get_node_or_null(coordinator_path)
    if coord != null:
        coord.issues_changed.connect(_on_issues_changed)

func _on_issues_changed(issues: Array[ValidationIssue]) -> void:
    _highlights.clear()
    for issue in issues:
        var c: Vector2i = _extract_coord(issue.path)
        if c == Vector2i.MAX: continue
        _highlights.append({"coord": c, "severity": issue.severity})
    queue_redraw()

func _draw() -> void:
    if _grid == null or _grid.tile_set == null: return
    var pts: PackedVector2Array = HexGeometry.flat_top_polygon(
        _grid.tile_set.tile_size)
    for h in _highlights:
        var center: Vector2 = _grid.map_to_local(h["coord"])
        var col: Color = (UiTheme.VALIDATION_HEX_REJECT
            if h["severity"] == ValidationIssue.Severity.REJECT
            else UiTheme.VALIDATION_HEX_WARN)
        var poly: PackedVector2Array = []
        for p in pts: poly.append(p + center)
        draw_colored_polygon(poly, col)

func _extract_coord(path: String) -> Vector2i:
    var m := _COORD_RX.search(path)
    if m == null: return Vector2i.MAX
    return Vector2i(int(m.get_string(1)), int(m.get_string(2))) 
```

**Verify:**
- [ ] Spawner на unpainted tile → красный hex highlight на этом
  тайле.
- [ ] WARN-issue с координатой → жёлтый highlight.
- [ ] После фикса issue — highlight пропадает.

## Φ-7. Save/load wiring

**Файл (правка):** `scripts/presentation/dev/editor/editor_controller.gd`
строки 347-390 (`_on_save`, `_on_new`, `_on_load`).

**`_on_save()` новый:**
```gdscript
func _on_save() -> void:
    var issues := _validation.revalidate_now()
    if _validation.has_blocking_issues():
        var rejects := 0
        for i in issues:
            if i.severity == ValidationIssue.Severity.REJECT:
                rejects += 1
        _toast(Localization.tf("ui_validate_save_blocked", [rejects],
            "Cannot save: %d errors. See Problem List."), &"error")
        return
    if _io.save(_level):
        var warns := issues.size()  # only WARNs left if we got past REJECT check
        if warns > 0:
            _toast(Localization.tf("ui_validate_save_with_warns", [warns],
                "Saved with %d warnings."), &"success")
        else:
            _toast("Saved: " + EditorIO.MAPS_DIR + _level.name + ".json",
                &"success")
    else:
        _toast("Save FAILED — see Output", &"error")
```

**`_on_new()` дополнить:** в конце — `_validation.revalidate_now()`.

**`_on_load()` дополнить:** после `_push_level_to_panels()` —
`_validation.revalidate_now()`.

**Mutation hook:** в каждый из методов
`paint_floor / erase_floor / paint_spawner / erase_spawner / paint_object
/ erase_object / cascade_at / add_wave / copy_wave_from_prev /
delete_wave / update_wave_field / _on_skill_offer_changed` добавить
строку `_validation.request_revalidate()` после `_io.enqueue_autosave(_level)`.

Также для Dialogue Triggers (методы пришли с 061) — те же
`request_revalidate()`.

**Verify:**
- [ ] Save с REJECT → toast «Cannot save…», файл не пишется.
- [ ] Save с WARN-only → файл пишется, toast «Saved with N warnings».
- [ ] Save без issues → toast «Saved: path».
- [ ] Load файла с REJECT → файл загружается, ProblemList показывает
  ошибки сразу.

## Φ-8. Manual smoke + polish

**Smoke checklist:** в `tasks.md`, не в чате.

Покрывает: AC1-AC13, plus edge cases:
- Пустой уровень (`_on_new` → REJECT «нет волн» → save blocked).
- Sample valid map (validate → 0 issues → save без warning).
- `data/maps/sample_*.json` или story_map с placeholder'ами (несколько
  WARN, save проходит, badges/highlights видны).
- Ввод поля с типом-валидацией (turns_to_next=0 → 200ms → red badge).
- Toggle между табами с активной валидацией — badges не теряются.
- Filter в ProblemListPanel — все три режима.
- F5 reload `game_speed.cfg` — debounce time не должна быть hot-reloadable
  (200ms hardcoded в `validation_coordinator.gd`).

**Полиш:** убрать debug print'ы, перепроверить что нет hardcoded color
inline в UI, обновить `docs/FEATURES.md` записью `validation-pipeline`.

## Не делаем (явно)

- Не выносим debounce в `config/game_speed.cfg` — UI affordance, не
  игровой timing.
- Не делаем undo/redo (064).
- Не трогаем `set_dirty` — отдельный TODO.
- Не делаем live valitate в game_editor.tscn — wire-only миграция
  consumer'а.
- Не локализуем DialogueTrigger.validate() второй раз (уже сделано).
