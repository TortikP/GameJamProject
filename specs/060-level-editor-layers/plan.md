# 060 — Implementation Plan

**Спек:** [`spec.md`](spec.md). Этот документ — *как именно* делаем. Спек — *что и зачем*.

## 0. Структура плана

Sequencing'ом разбит на **12 фаз** (соответствуют группам §10 спека). Каждая фаза — атомарная единица работы; в идеале — один-два коммита, один логический smoke-проход на конце. Фазы строго последовательны кроме случаев где явно разрешено parallel (только Φ-1 framework patch — изолированно, может идти параллельно с Φ-2).

Внутри каждой фазы — конкретные технические решения (классы, сигналы, файлы), risk anchors (что может пойти не по плану, как ловить), и proof-of-life критерий (что должно работать к концу фазы).

После фаз — глобальные risks, рекомендации по smoke, и `tasks.md` ссылка.

---

## Φ-1. Framework patch: PanelTabBar.active_tab_changed

**Что:** Добавить `signal active_tab_changed(tab_id: StringName)` в `panel_tab_bar.gd` и re-emit в `tabbed_base_panel.gd`. Изолированная правка ui-panels framework (058).

**Файлы:**
- `scripts/presentation/ui_panels/internal/panel_tab_bar.gd`
- `scripts/presentation/ui_panels/tabbed_base_panel.gd`

**Решение:** добавить опциональный параметр `by_user: bool = false` в `_set_active(tab_id, by_user)`. Эмит сигнала только при `by_user=true`. Прохожу по всем 5 call sites (`panel_tab_bar.gd:89, 242, 329, 387, 457`):

| Line | Контекст | by_user |
|---|---|---|
| 89 | initial setup в `_ready` | `false` |
| 242 | после клика по табу в `_on_tab_button_gui_input` | `true` |
| 329 | после reattach detached tab | `true` |
| 387 | re-register flow | `false` |
| 457 | первый таб в `add_tab()` (programmatic) | `false` |

`TabbedBasePanel` объявляет одноимённый сигнал и подписывается на `_tab_bar.active_tab_changed` лямбдой re-emit'ящей в `_setup_tab_bar`.

**Risk anchor:** на подписке. `_tab_bar.setup(self)` (line 59 tabbed_base_panel.gd) уже стоит — connect ставится сразу после. Если по timing'у подписка проскочит раньше чем `_tab_bar` инициализируется внутри — сигнал теряется. **Mitigation:** связать после `_tab_bar.setup(self)`, не до. Smoke — открыть `tabbed_panel_demo.tscn` (058) и кликнуть по табам, проверить через print что сигнал летит.

**Proof of life:** в `tabbed_panel_demo.gd` времянно подписаться на `active_tab_changed` и логнуть в Output на каждое переключение. Должно срабатывать только на клик пользователя, не на initial render.

**Объём:** ~10 строк суммарно.

---

## Φ-2. EditorIO extract

**Что:** Вынести save/load/autosave/grid-sync из `EditorController` в `EditorIO`. Pure refactor — никакого новой функциональности, только перемещение кода.

**Файл:** `scripts/presentation/dev/editor/editor_io.gd` (новый).

**Класс:** `class_name EditorIO extends Node` — **не RefCounted**. Причина: autosave требует Timer (Node), restore prompt вызывает `ConfirmModal.ask` который требует scene tree access (`get_tree()`), `EditorIO` живёт как child `EditorController`. Lifecycle через стандартный Node free.

**API:**
```gdscript
class_name EditorIO
extends Node

const MAPS_DIR := "res://data/maps/"
const AUTOSAVE_PATH := "res://data/maps/__autosave__.json"
const PLAYTEST_PATH := "res://data/maps/__playtest__.json"
const AUTOSAVE_DEBOUNCE_SEC := 1.5
const AUTOSAVE_MAX_AGE_SEC := 86400

signal autosave_restored(level: LevelData)        # после prompt → Yes
signal load_completed(level: LevelData)           # после _on_load
signal save_completed(path: String)               # после _on_save success

var _grid: HexGrid                                # injected
var _objects_overlay: Node                        # injected, weak typing — overlay scripts not class_name'd
var _spawners_overlay: Node                       # same
var _autosave_timer: Timer                        # owned

func setup(grid: HexGrid, objects_overlay: Node, spawners_overlay: Node) -> void
func save(level: LevelData) -> bool                                 # explicit save action
func load_from(path: String) -> LevelData                           # null on failure
func write_playtest_snapshot(level: LevelData) -> bool              # __playtest__.json для playtest
func enqueue_autosave(level: LevelData) -> void                     # debounce Timer
func clear_autosave() -> void                                       # на explicit save success
func check_autosave_on_ready() -> Dictionary                        # {"prompt_needed": bool, "age_sec": int}
                                                                     # controller сам открывает ConfirmModal — IO не знает про modals
func refresh_grid_from_level(level: LevelData) -> void               # tile_map_layer + objects_overlay + spawners_overlay
```

**Решение про restore prompt:** `EditorIO` *не* открывает ConfirmModal сам. Возвращает {prompt_needed, age_sec}, `EditorController._ready` смотрит и сам вызывает modal. Reason: ConfirmModal — это HUD-узел сцены, его resolve'ит controller, а не IO. Иначе IO нужен NodePath к modal или поиск по дереву — лишняя зависимость.

**Объём:** ~150-180 строк ожидаемых, soft cap 200 (AC34).

**Risk anchor:** **Timer** в Godot 4 — `_autosave_timer = Timer.new(); add_child(_autosave_timer); _autosave_timer.one_shot = true; _autosave_timer.wait_time = 1.5; _autosave_timer.timeout.connect(_on_autosave_fire)`. Если забыть `add_child` — таймер не тикает (стандартная ловушка Godot).

**Proof of life:** EditorController после refactor работает 1:1 как 059. Smoke 059 (paint, erase, save, load, exit) проходит без регрессий.

**Sequencing внутри фазы:**
1. Создать `editor_io.gd` со всем API но stub-ами (return null/false/etc.).
2. Перенести `_on_save`/`_on_load`/`_on_exit` контроллера в IO один за одним. После каждого — controller проксирует через `_io.save(_level)` и т.п.
3. Перенести `_refresh_grid_from_level`. Здесь же добавляется передача `_objects_overlay`/`_spawners_overlay` — overlays ещё не подключены в Φ-2 (это Φ-6), но IO готов их принять.
4. Добавить `Timer` autosave + `enqueue_autosave`. Сейчас вызовов нет, в Φ-6 будут.
5. Добавить `check_autosave_on_ready()`. Сейчас controller не вызывает — в Φ-6 подключается.

**Контроллер после Φ-2:** ожидаемо ~200 строк. Public API без изменений (paint_floor / erase_floor — пока).

---

## Φ-3. LayersModel + LayersPanel migration

**Что:** Расширить LayersModel до 3 слоёв; мигрировать LayersPanel на TabbedBasePanel; добавить wiring `active_tab_changed` от Φ-1.

### Φ-3.a. LayersModel

**Файл:** `scripts/presentation/dev/editor/layers_model.gd`.

**Изменения:**
```gdscript
const LAYER_HEXES := &"hexes"
const LAYER_SPAWNERS := &"spawners"
const LAYER_OBJECTS := &"objects"
const LAYER_ORDER: Array[StringName] = [LAYER_HEXES, LAYER_SPAWNERS, LAYER_OBJECTS]

func cycle_active_forward() -> StringName:
    var idx := LAYER_ORDER.find(active_layer)
    if idx < 0:
        active_layer = LAYER_HEXES
    else:
        active_layer = LAYER_ORDER[(idx + 1) % LAYER_ORDER.size()]
    return active_layer

func has_selection() -> bool:
    return get_active_selection() != null
```

`is_erase()` остаётся прежним (используется только для hexes, для других слоёв возвращает false — корректно).

**Объём:** ~80-100 строк, soft cap 120 (AC36).

### Φ-3.b. LayersPanel

**Файл:** `scripts/presentation/dev/editor/layers_panel.gd`.

**Решение:** `extends TabbedBasePanel`. В `_ready` после `super._ready()`:
1. Создать три палитры через `.new()`.
2. Подключить их сигналы `selection_changed` к одному handler через `bind(layer_id)`.
3. `add_tab(palette, layer_id, title_key, fallback)` для каждой.
4. Подписаться на `active_tab_changed` (наследованный от TabbedBasePanel после Φ-1) и re-emit как тот же сигнал — но его уже видно через наследование, не нужен ре-emit.

```gdscript
class_name LayersPanel
extends TabbedBasePanel

signal layer_selection_changed(layer_id: StringName, value: Variant)
# active_tab_changed naследован от TabbedBasePanel, не объявляем заново

var _hex_palette: HexTilePalette
var _spawner_palette: SpawnerPalette  # из Φ-4
var _object_palette: ObjectPalette    # из Φ-4

func _ready() -> void:
    super._ready()                                # CRITICAL — инициализирует tab_bar
    _hex_palette = HexTilePalette.new()
    _spawner_palette = SpawnerPalette.new()
    _object_palette = ObjectPalette.new()
    _hex_palette.selection_changed.connect(_on_palette.bind(LayersModel.LAYER_HEXES))
    _spawner_palette.selection_changed.connect(_on_palette.bind(LayersModel.LAYER_SPAWNERS))
    _object_palette.selection_changed.connect(_on_palette.bind(LayersModel.LAYER_OBJECTS))
    add_tab(_hex_palette, LayersModel.LAYER_HEXES,
            &"ui_layers_panel_tab_hexes", "Hexes")
    add_tab(_spawner_palette, LayersModel.LAYER_SPAWNERS,
            &"ui_layers_panel_tab_spawners", "Spawners")
    add_tab(_object_palette, LayersModel.LAYER_OBJECTS,
            &"ui_layers_panel_tab_objects", "Objects")

func _on_palette(value: Variant, layer_id: StringName) -> void:
    layer_selection_changed.emit(layer_id, value)

func get_palette_for_layer(layer_id: StringName) -> Node:
    match layer_id:
        LayersModel.LAYER_HEXES: return _hex_palette
        LayersModel.LAYER_SPAWNERS: return _spawner_palette
        LayersModel.LAYER_OBJECTS: return _object_palette
    return null
```

`get_palette_for_layer` понадобится в Φ-5 для `1-9` quick-select dispatch.

**Risk anchor:** `bind(layer_id)` в connect — порядок аргументов. Godot 4: `signal.connect(callable.bind(extras))` → handler вызывается с (signal_args..., bound_extras...). Hex palette emit'ит `selection_changed(value)`, после bind handler вызывается с `(value, layer_id)`. Это совпадает с сигнатурой `_on_palette(value, layer_id)`. **Если не совпадает** — runtime error «expected N args, got M». Smoke ловит.

**Risk anchor:** scene-файл `scenes/dev/editor/layers_panel.tscn` сейчас — composition вокруг `base_panel.tscn` через script-override. Меняем `script_path` в .tscn с `layers_panel.gd` на тот же файл (он сам поменяет extends на TabbedBasePanel). Если script-override не работает с TabbedBasePanel (наследник через несколько уровней) — fallback: создаём `tabbed_base_panel.tscn` и компонуем layers_panel.tscn вокруг него. Решается при имплементации.

**Proof of life:** Открыть level_editor.tscn — три таба видны, hexes (с палитрой как в 059), spawners (пустой пока — Φ-4), objects (пустой пока). Клик по табам переключает контент.

### Φ-3.c. Wire LayersPanel → EditorController

В `editor_controller.gd`:
- Заменить slot `_on_palette_selection(value)` на `_on_layer_selection_changed(layer_id, value)` — вызывает `_layers.set_selection(layer_id, value)`.
- Подключить `_layers_panel.active_tab_changed` (от Φ-1) → `_on_active_tab_changed(tab_id)` → `_layers.active_layer = tab_id`.
- Если 1-9 в Φ-5 будут менять active_layer — это пойдёт через тот же сигнал (controller вызывает `_layers_panel.set_active_tab(tab_id)` если такой API есть в TabbedBasePanel — нет, но добавим в Φ-5 если нужно).

---

## Φ-4. SpawnerPalette + ObjectPalette

**Что:** Две новые палитры по паттерну `HexTilePalette`. Без табов внутри (упрощение). Без иконок изначально (text-only) — иконки опциональны если останется время.

### Φ-4.a. SpawnerPalette

**Файл:** `scripts/presentation/dev/editor/spawner_palette.gd`.

```gdscript
class_name SpawnerPalette
extends VBoxContainer

const ENEMIES_DIR := "res://data/enemies/"

signal selection_changed(value: Dictionary)  # {"kind": StringName, "ref": StringName}

var _button_group: ButtonGroup
var _grid: HFlowContainer
var _quick_select_buttons: Array[Button] = []  # для 1-9 dispatch (Φ-5)

func _ready() -> void:
    _button_group = ButtonGroup.new()
    _grid = HFlowContainer.new()
    _grid.add_theme_constant_override("h_separation", 4)
    _grid.add_theme_constant_override("v_separation", 4)
    add_child(_grid)
    _build_buttons()

func _build_buttons() -> void:
    # Player первый
    _grid.add_child(_make_spawner_button(
        Localization.t("ui_spawner_palette_player", "Player"),
        &"player", &""))
    # Enemies из data/enemies/*.json
    var dir := DirAccess.open(ENEMIES_DIR)
    if dir == null:
        return
    dir.list_dir_begin()
    var fname := dir.get_next()
    while fname != "":
        if not dir.current_is_dir() and fname.ends_with(".json"):
            var enemy_id := fname.get_basename()
            var label := Localization.t("%s_name" % enemy_id, enemy_id.capitalize())
            _grid.add_child(_make_spawner_button(label, &"enemy", StringName(enemy_id)))
        fname = dir.get_next()
    dir.list_dir_end()

func _make_spawner_button(label: String, kind: StringName, ref: StringName) -> Button:
    var btn := Button.new()
    btn.text = label
    btn.toggle_mode = true
    btn.button_group = _button_group
    UiTheme.apply_button_styling(btn)
    btn.pressed.connect(_on_pressed.bind(kind, ref))
    _quick_select_buttons.append(btn)
    return btn

func _on_pressed(kind: StringName, ref: StringName) -> void:
    selection_changed.emit({"kind": kind, "ref": ref})

func quick_select(n: int) -> void:  # Φ-5 hook
    if n < 1 or n > _quick_select_buttons.size():
        return
    _quick_select_buttons[n - 1].button_pressed = true
    _quick_select_buttons[n - 1].pressed.emit()  # toggle_mode buttons не эмитят при программном set
```

**Risk anchor:** `button_pressed = true` для button в `ButtonGroup` НЕ эмитит `pressed` — Godot quirk. Поэтому в `quick_select` после set'а делаем `pressed.emit()` явно. Альтернатива — использовать `toggled.emit(true)`, но это сложнее.

### Φ-4.b. ObjectPalette

**Файл:** `scripts/presentation/dev/editor/object_palette.gd`.

Тот же паттерн, источник — `TileObjectRegistry`:

```gdscript
class_name ObjectPalette
extends VBoxContainer

const TILE_OBJECTS_DIR := "res://data/tile_objects/"

signal selection_changed(value: Dictionary)  # {"object_id": StringName}

var _button_group: ButtonGroup
var _grid: HFlowContainer
var _registry: TileObjectRegistry
var _quick_select_buttons: Array[Button] = []

func _ready() -> void:
    _registry = TileObjectRegistry.new()
    _registry.load_from_dir(TILE_OBJECTS_DIR)
    _button_group = ButtonGroup.new()
    _grid = HFlowContainer.new()
    _grid.add_theme_constant_override("h_separation", 4)
    _grid.add_theme_constant_override("v_separation", 4)
    add_child(_grid)
    _build_buttons()

func _build_buttons() -> void:
    for obj_id in _registry.get_all_ids():
        var obj: TileObject = _registry.get_object(obj_id)
        if obj == null or obj.id == &"":
            continue
        var label := Localization.t("%s_name" % String(obj_id), String(obj_id).capitalize())
        _grid.add_child(_make_button(label, obj_id))

func _make_button(label: String, object_id: StringName) -> Button:
    var btn := Button.new()
    btn.text = label
    btn.toggle_mode = true
    btn.button_group = _button_group
    UiTheme.apply_button_styling(btn)
    btn.pressed.connect(_on_pressed.bind(object_id))
    _quick_select_buttons.append(btn)
    return btn

func _on_pressed(object_id: StringName) -> void:
    selection_changed.emit({"object_id": object_id})

func quick_select(n: int) -> void:
    if n < 1 or n > _quick_select_buttons.size():
        return
    _quick_select_buttons[n - 1].button_pressed = true
    _quick_select_buttons[n - 1].pressed.emit()
```

**Quick-select labels (1-9 в углу первых 9 buttons):** реализую как Label child каждой кнопки в углу. Один Label в Φ-5, не сейчас.

**Иконки (sprite_path → AtlasTexture):** В hex_terrain.tres понятно (atlas region). Для enemies/objects — `load(sprite_path) as Texture2D` если файл валидный, fallback к text. Опциональный полишинг — **не блокер** для AC. Текстовых кнопок достаточно для 060 smoke. Если время есть — добавим в финале фазы.

**Proof of life:** spawners-таб показывает Player + N enemies (зависит от data/enemies). Objects-таб показывает все TileObjects. Клик меняет ButtonGroup-выделение. Сигналы летят в LayersPanel → controller.

**Объём:** SpawnerPalette ~70 строк, ObjectPalette ~70 строк.

### Φ-4.c. Quick-select label badges (1-9)

После того как палитры собирают buttons, на первых 9 рисуется подпись цифры в углу:

```gdscript
# Common helper в каждой палитре после _build_buttons():
func _decorate_quick_select_badges() -> void:
    for i in range(min(9, _quick_select_buttons.size())):
        var btn := _quick_select_buttons[i]
        var badge := Label.new()
        badge.text = str(i + 1)
        badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
        badge.add_theme_color_override("font_color", Color(1, 1, 0.4, 0.9))
        badge.position = Vector2(2, 2)
        btn.add_child(badge)
```

Можно вынести в shared `palette_helpers.gd` или дублировать (две точки = OK по «не абстрагируй для будущего»).

---

## Φ-5. InputDispatcher: per-layer + keyboard + cascade

**Что:** Расширить `input_dispatcher.gd` под три слоя, keyboard handling, cascade. Самая концентрированная фаза, риски всплывают тут.

**Файл:** `scripts/presentation/dev/editor/input_dispatcher.gd`.

### Φ-5.a. Per-layer dispatch

`_act_at` ветвится по `_layers.active_layer`:

```gdscript
func _act_at(coord: Vector2i, erase: bool) -> void:
    if coord == Vector2i(-1, -1):
        return
    match _layers.active_layer:
        LayersModel.LAYER_HEXES:    _act_hexes(coord, erase)
        LayersModel.LAYER_SPAWNERS: _act_spawners(coord, erase)
        LayersModel.LAYER_OBJECTS:  _act_objects(coord, erase)
    _last_painted_coord = coord

func _act_hexes(coord, erase) -> void:
    if erase or _layers.is_erase():
        if _controller.erase_floor(coord):
            _spawn_flash(coord)
        return
    var sel: Variant = _layers.get_active_selection()
    if typeof(sel) != TYPE_DICTIONARY:
        return
    _controller.paint_floor(coord, int(sel["source_id"]), sel["atlas_coord"])

func _act_spawners(coord, erase) -> void:
    if erase:
        if _controller.erase_spawner(coord):
            _spawn_flash(coord)
        return
    var sel: Variant = _layers.get_active_selection()
    if typeof(sel) != TYPE_DICTIONARY:
        return
    _controller.paint_spawner(coord, sel["kind"], sel["ref"])

func _act_objects(coord, erase) -> void:
    if erase:
        if _controller.erase_object(coord):
            _spawn_flash(coord)
        return
    var sel: Variant = _layers.get_active_selection()
    if typeof(sel) != TYPE_DICTIONARY:
        return
    _controller.paint_object(coord, sel["object_id"])
```

**Решение про flash:** dispatcher — *единственный* эмиттер flash. Controller `erase_*` методы возвращают `bool` (true если что-то стёрлось). Dispatcher решает spawn'ить flash или нет. Это держит flash policy в одном месте — например, для cascade flash будет один (см. Φ-5.c).

### Φ-5.b. Keyboard handling

Расширение `handle()`:

```gdscript
func handle(event: InputEvent) -> bool:
    if event is InputEventMouseButton:
        return _handle_mouse_button(event)
    if event is InputEventMouseMotion and _drag_state != DragState.NONE:
        return _handle_mouse_drag(event)
    if event is InputEventKey and event.pressed:
        return _handle_key(event as InputEventKey)
    return false

func _handle_key(ke: InputEventKey) -> bool:
    if _is_text_focus():
        return false  # let LineEdit/TextEdit/SpinBox eat it
    match ke.keycode:
        KEY_ESCAPE:
            _drag_state = DragState.NONE
            _last_painted_coord = NO_COORD
            return true
        KEY_Q: _set_layer(LayersModel.LAYER_HEXES); return true
        KEY_W: _set_layer(LayersModel.LAYER_SPAWNERS); return true
        KEY_E: _set_layer(LayersModel.LAYER_OBJECTS); return true
        KEY_TAB:
            _layers.cycle_active_forward()
            _controller.notify_active_layer_changed(_layers.active_layer)
            return true
        KEY_F1, KEY_QUESTION:
            _controller.show_help()
            return true
    if ke.keycode >= KEY_1 and ke.keycode <= KEY_9:
        var n := ke.keycode - KEY_0
        _controller.quick_select_in_active_palette(n)
        return true
    return false

func _set_layer(layer_id: StringName) -> void:
    _layers.active_layer = layer_id
    _controller.notify_active_layer_changed(layer_id)

func _is_text_focus() -> bool:
    var owner := Engine.get_main_loop().root.gui_get_focus_owner() if Engine.get_main_loop() != null else null
    if owner == null:
        return false
    return owner is LineEdit or owner is TextEdit or owner is SpinBox
```

**Risk anchor:** `gui_get_focus_owner()` — метод `Viewport`, не глобальный. Правильный путь: `controller.get_viewport().gui_get_focus_owner()`. Dispatcher не Node, нет `get_viewport`. **Решение:** controller передаёт self в dispatcher (уже передан как `_controller`), dispatcher вызывает `_controller.get_viewport().gui_get_focus_owner()`. Чище — controller имеет helper `is_text_focused()`, dispatcher вызывает его.

Чищу: в controller добавить:
```gdscript
func is_text_focused() -> bool:
    var owner := get_viewport().gui_get_focus_owner()
    return owner is LineEdit or owner is TextEdit or owner is SpinBox
```

Dispatcher: `if _controller.is_text_focused(): return false`.

### Φ-5.c. Cascade

Shift+RMB → controller.cascade_at(coord) → один flash.

```gdscript
func _handle_mouse_button(mb: InputEventMouseButton) -> bool:
    # ... LMB unchanged ...
    if mb.button_index == MOUSE_BUTTON_RIGHT:
        if mb.pressed:
            if mb.shift_pressed:
                var coord := _grid.coord_under_mouse_raw()
                if coord != Vector2i(-1, -1):
                    if _controller.cascade_at(coord):
                        _spawn_flash(coord)
                return true
            _drag_state = DragState.ERASING
            _act_at(_grid.coord_under_mouse_raw(), true)
        else:
            _drag_state = DragState.NONE
            _last_painted_coord = NO_COORD
        return true
    return false
```

`cascade_at` → bool: true если хоть что-то стёрлось.

**Risk anchor:** `mb.shift_pressed` свойство `InputEventMouseButton` есть в Godot 4 (унаследовано от InputEventWithModifiers). Если по какой-то причине не работает — fallback `Input.is_key_pressed(KEY_SHIFT)`.

### Φ-5.d. Спаун flash

```gdscript
func _spawn_flash(coord: Vector2i) -> void:
    DeleteFlash.spawn_at(_grid, coord, _grid)  # parent = HexGrid (Node2D)
```

`DeleteFlash` — из Φ-7.

**Объём:** ~190-210 строк, soft cap 220 (AC35).

**Proof of life:** Q/W/E переключают табы. Tab циклит. 1-9 выбирают buttons активной палитры. Esc сбрасывает drag. F1 открывает HELP (когда Φ-7 готов). Shift+RMB cascade'ит. Click в `LineEdit` (имя уровня) → Q НЕ переключает таб (LineEdit ест), вводится буква 'q'.

---

## Φ-6. EditorController: public API + overlay wiring + autosave

**Что:** Расширить `editor_controller.gd` всеми public методами для трёх слоёв + cascade + helpers + overlay wiring. Подключить autosave через EditorIO. Подключить Game Editor handoff в `_ready`.

**Файл:** `scripts/presentation/dev/editor/editor_controller.gd`.

### Φ-6.a. Resolve overlays

Добавить в @export:
```gdscript
@export var objects_overlay_path: NodePath
@export var spawners_overlay_path: NodePath
@export var help_modal_path: NodePath  # для Φ-7 hook
```

В `_resolve_nodes()`:
```gdscript
_objects_overlay = get_node_or_null(objects_overlay_path)
_spawners_overlay = get_node_or_null(spawners_overlay_path)
_help_modal = get_node_or_null(help_modal_path)
```

`scenes/dev/level_editor.tscn` обновляется (Φ-9): добавляются ObjectsOverlay и SpawnersOverlay как children HexGrid (паттерн map_editor.tscn).

### Φ-6.b. Public API расширение

```gdscript
# Mutations (called from InputDispatcher)
func paint_floor(coord, source_id, atlas_coord) -> void: ...     # already exists
func erase_floor(coord) -> bool: ...                              # CHANGED — now returns bool
func paint_spawner(coord, kind, ref) -> void: ...                 # NEW
func erase_spawner(coord) -> bool: ...                            # NEW
func paint_object(coord, object_id) -> void: ...                  # NEW
func erase_object(coord) -> bool: ...                             # NEW
func cascade_at(coord) -> bool: ...                               # NEW

# Layer state (called from InputDispatcher keyboard)
func notify_active_layer_changed(layer_id: StringName) -> void:
    # called when dispatcher Q/W/E/Tab — sync TabbedBasePanel UI
    if _layers_panel != null:
        _layers_panel.set_active_tab(layer_id)  # need to add this method to TabbedBasePanel
        # or pass through PanelTabBar API
func quick_select_in_active_palette(n: int) -> void:
    if _layers_panel == null: return
    var palette := _layers_panel.get_palette_for_layer(_layers.active_layer)
    if palette != null and palette.has_method("quick_select"):
        palette.quick_select(n)
func show_help() -> void:
    if _help_modal != null:
        _help_modal.show()
func is_text_focused() -> bool:
    var owner := get_viewport().gui_get_focus_owner()
    return owner is LineEdit or owner is TextEdit or owner is SpinBox
```

**Side issue:** `TabbedBasePanel.set_active_tab(tab_id)` API не существует (Φ-1 был только signal). Нужно добавить:

```gdscript
# tabbed_base_panel.gd:
func set_active_tab(tab_id: StringName) -> void:
    if _tab_bar != null:
        _tab_bar._set_active(tab_id, false)  # programmatic, no signal
```

Или — публичное API в PanelTabBar: `func set_active(tab_id, by_user=false)`. Чище.

**Решение:** добавить в PanelTabBar `func set_active(tab_id: StringName, by_user: bool = false) -> void` который делегирует в `_set_active`. TabbedBasePanel.set_active_tab(tab_id) → _tab_bar.set_active(tab_id, false). Эта правка естественно живёт в Φ-1, **передвигаю** её туда. Φ-1 объёмом был ~10 строк, станет ~15.

### Φ-6.c. Mutation методы реализация

```gdscript
func paint_floor(coord, source_id, atlas_coord) -> void:
    if _grid == null or _grid.tile_map_layer == null: return
    _grid.tile_map_layer.set_cell(coord, source_id, atlas_coord)
    _set_or_update_floor_cell(coord, source_id, atlas_coord)
    _io.enqueue_autosave(_level)

func erase_floor(coord) -> bool:
    if _grid == null or _grid.tile_map_layer == null: return false
    if _grid.tile_map_layer.get_cell_source_id(coord) < 0: return false
    _grid.tile_map_layer.set_cell(coord, -1)
    _remove_floor_cell(coord)
    _io.enqueue_autosave(_level)
    return true

func paint_spawner(coord, kind, ref) -> void:
    if kind == &"player":
        # Player uniqueness: remove ALL existing player spawners (any coord)
        for i in range(_level.spawners.size() - 1, -1, -1):
            if _level.spawners[i]["kind"] == &"player":
                _level.spawners.remove_at(i)
    else:
        # Replace any spawner at coord
        for i in range(_level.spawners.size() - 1, -1, -1):
            if _level.spawners[i]["coord"] == coord:
                _level.spawners.remove_at(i)
    _level.spawners.append({"coord": coord, "kind": kind, "ref": ref, "timer": 1})
    if _spawners_overlay != null and _spawners_overlay.has_method("refresh"):
        _spawners_overlay.refresh(_level.spawners)
    _io.enqueue_autosave(_level)

func erase_spawner(coord) -> bool:
    var changed := false
    for i in range(_level.spawners.size() - 1, -1, -1):
        if _level.spawners[i]["coord"] == coord:
            _level.spawners.remove_at(i)
            changed = true
    if changed and _spawners_overlay != null:
        _spawners_overlay.refresh(_level.spawners)
        _io.enqueue_autosave(_level)
    return changed

func paint_object(coord, object_id) -> void:
    for i in range(_level.objects.size() - 1, -1, -1):
        if _level.objects[i]["coord"] == coord:
            _level.objects.remove_at(i)
    _level.objects.append({"coord": coord, "object_id": object_id})
    if _objects_overlay != null:
        _objects_overlay.refresh(_level.objects)
    _io.enqueue_autosave(_level)

func erase_object(coord) -> bool:
    var changed := false
    for i in range(_level.objects.size() - 1, -1, -1):
        if _level.objects[i]["coord"] == coord:
            _level.objects.remove_at(i)
            changed = true
    if changed and _objects_overlay != null:
        _objects_overlay.refresh(_level.objects)
        _io.enqueue_autosave(_level)
    return changed

func cascade_at(coord) -> bool:
    var floor_changed := erase_floor(coord)
    var obj_changed := false
    for i in range(_level.objects.size() - 1, -1, -1):
        if _level.objects[i]["coord"] == coord:
            _level.objects.remove_at(i)
            obj_changed = true
    var sp_changed := false
    for i in range(_level.spawners.size() - 1, -1, -1):
        if _level.spawners[i]["coord"] == coord:
            _level.spawners.remove_at(i)
            sp_changed = true
    if obj_changed and _objects_overlay != null:
        _objects_overlay.refresh(_level.objects)
    if sp_changed and _spawners_overlay != null:
        _spawners_overlay.refresh(_level.spawners)
    if floor_changed or obj_changed or sp_changed:
        _io.enqueue_autosave(_level)
        return true
    return false
```

**Risk anchor:** `objects_overlay` и `spawners_overlay` в legacy имеют ли метод `refresh(...)` ровно с такой сигнатурой? Проверяю в Φ-6 sequencing'е первым делом. Если нет — придётся либо допилить overlay (мелкая правка), либо использовать другой метод (`set_objects()` / `update()`). Конкретный API смотрю при имплементации, документирую в коммит.

### Φ-6.d. Game Editor handoff в `_ready`

```gdscript
func _ready() -> void:
    _resolve_nodes()
    if _grid != null:
        _grid.initialize()                    # workaround удаляется в Φ-9
    _level = LevelData.new()
    _layers = LayersModel.new()
    _layers.set_selection(LayersModel.LAYER_HEXES, _default_hex_selection())
    _io = EditorIO.new()
    add_child(_io)
    _io.setup(_grid, _objects_overlay, _spawners_overlay)
    _dispatcher = InputDispatcher.new(self, _grid, _layers)
    _wire_panels()

    # Game Editor handoff OR autosave restore — but not both
    if ActiveLevel.has_queued():
        var path: String = ActiveLevel.consume()
        var loaded := _io.load_from(path)
        if loaded != null:
            _level = loaded
            _io.refresh_grid_from_level(_level)
            _meta_panel.set_level_name(_level.name)
            _check_multi_wave_warning()
    else:
        var info := _io.check_autosave_on_ready()
        if info["prompt_needed"]:
            await _prompt_autosave_restore(info["age_sec"])
        else:
            _io.refresh_grid_from_level(_level)  # empty grid

func _prompt_autosave_restore(age_sec: int) -> void:
    var modal := get_node_or_null(NodePath("HUD/ConfirmModal"))  # need to add to scene
    if modal == null:
        # No modal in scene — fail safe, just clear
        _io.clear_autosave()
        return
    var minutes := int(age_sec / 60.0)
    var confirmed: bool = await modal.ask(
        Localization.t("ui_level_editor_autosave_restore_title", "Restore unsaved work?"),
        Localization.tf("ui_level_editor_autosave_restore_body",
            [str(minutes)], "Found unsaved work from %s minutes ago. Restore?"),
        Localization.t("ui_level_editor_autosave_restore_yes", "Restore"),
        Localization.t("ui_level_editor_autosave_restore_no", "Discard"))
    if confirmed:
        var loaded := _io.load_from(_io.AUTOSAVE_PATH)
        if loaded != null:
            _level = loaded
            _io.refresh_grid_from_level(_level)
            _meta_panel.set_level_name(_level.name)
    else:
        _io.clear_autosave()

func _check_multi_wave_warning() -> void:
    if _level.waves.size() > 1:
        EventBus.ui_toast_requested.emit(
            Localization.tf("ui_level_editor_multi_wave_warning",
                [str(_level.waves.size())],
                "Multi-wave map (%s waves) loaded. Editing affects wave 0 only — full wave editor coming in 061."),
            4.0, &"warn")
```

**Risk anchor:** ConfirmModal — нужен в `scenes/dev/level_editor.tscn`. В Φ-9 добавлю.

### Φ-6.e. Playtest + exit

```gdscript
func _on_playtest() -> void:
    if not _io.write_playtest_snapshot(_level):
        EventBus.ui_toast_requested.emit(
            Localization.t("ui_map_editor_playtest_write_failed", "Failed to write playtest"),
            2.0, &"error")
        return
    ActiveLevel.mark_playtest(_io.PLAYTEST_PATH)
    ActiveLevel.queue(_io.PLAYTEST_PATH)
    get_tree().change_scene_to_file("res://scenes/dev/godmode.tscn")

func _on_exit() -> void:
    # 035: return to Game Editor if we came from there
    if ActiveGame.has_queued_for_editor():
        get_tree().change_scene_to_file("res://scenes/dev/game_editor.tscn")
        return
    get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
```

`_on_playtest_disabled` (toast «coming in 060») — удаляется. Сигнал переподключается на `_on_playtest`.

**Note about dirty/confirm-on-exit:** legacy MapEditor спрашивает «exit without saving» при unsaved changes. **В 060 это пока не делаем** — autosave спасает. Если Андрей хочет — это easy add позже. Decision: skip, surface как finding.

**Объём контроллера:** ожидаемо 280-300 строк. На грани. Если перевалит — extraction kandiдат — `_check_multi_wave_warning` + `_prompt_autosave_restore` в EditorIO (вместе со связанной логикой `check_autosave_on_ready`).

**Proof of life:** все 3 слоя paint/erase работают. Cascade работает. Q/W/E/Tab/1-9 переключают и выбирают. Save/Load/Autosave/Restore работает. Game Editor → Level Editor → Exit → Game Editor цикл работает. Playtest → ESC → Back to Editor цикл работает.

---

## Φ-7. Visual effects: DeleteFlash + EditorHelpModal

### Φ-7.a. DeleteFlash

**Файл:** `scripts/presentation/dev/editor/delete_flash.gd`.

```gdscript
class_name DeleteFlash
extends Node2D

const HexGeometry = preload("res://scripts/infrastructure/hex_geometry.gd")
const FLASH_DURATION_SEC := 0.15
const FLASH_COLOR := Color(1.0, 0.2, 0.2, 0.7)

var _polygon: PackedVector2Array = PackedVector2Array()

static func spawn_at(parent: Node, coord: Vector2i, grid: HexGrid) -> void:
    var flash := DeleteFlash.new()
    flash.position = grid.coord_to_world(coord) if grid.has_method("coord_to_world") \
        else grid.tile_map_layer.map_to_local(coord)
    parent.add_child(flash)
    var tile_size: Vector2i = grid.tile_map_layer.tile_set.tile_size if grid.tile_map_layer != null else Vector2i(128, 80)
    flash._init_polygon(tile_size)
    var tween := flash.create_tween()
    tween.tween_property(flash, "modulate:a", 0.0, FLASH_DURATION_SEC)
    tween.tween_callback(flash.queue_free)

func _init_polygon(tile_size: Vector2i) -> void:
    _polygon = HexGeometry.flat_top_polygon(tile_size)
    queue_redraw()

func _draw() -> void:
    if _polygon.size() > 0:
        draw_colored_polygon(_polygon, FLASH_COLOR)
```

**Risk anchor:** способ конвертации `coord` → world position. Проверяю в `hex_grid.gd` — есть `coord_to_world`? Если нет — `tile_map_layer.map_to_local(coord)`. В smoke вижу что нашёл правильный.

**Объём:** ~30 строк.

### Φ-7.b. EditorHelpModal

**Файл:** `scripts/presentation/dev/editor/editor_help_modal.gd`.

**Решение:** `extends BasePanel`. В `_ready` строит таблицу шорткатов. Open через `show()`, close через Esc (handled внутри modal через `_input` consume).

```gdscript
class_name EditorHelpModal
extends BasePanel

const SHORTCUTS: Array[Dictionary] = [
    {"key_text_key": &"ui_help_key_q", "key_fb": "Q",   "desc_key": &"ui_help_desc_layer_hexes"},
    {"key_text_key": &"ui_help_key_w", "key_fb": "W",   "desc_key": &"ui_help_desc_layer_spawners"},
    {"key_text_key": &"ui_help_key_e", "key_fb": "E",   "desc_key": &"ui_help_desc_layer_objects"},
    {"key_text_key": &"ui_help_key_tab", "key_fb": "Tab", "desc_key": &"ui_help_desc_cycle_layers"},
    {"key_text_key": &"ui_help_key_1_9", "key_fb": "1–9", "desc_key": &"ui_help_desc_quick_select"},
    {"key_text_key": &"ui_help_key_lmb", "key_fb": "LMB", "desc_key": &"ui_help_desc_paint"},
    {"key_text_key": &"ui_help_key_rmb", "key_fb": "RMB", "desc_key": &"ui_help_desc_erase"},
    {"key_text_key": &"ui_help_key_shift_rmb", "key_fb": "Shift+RMB", "desc_key": &"ui_help_desc_cascade"},
    {"key_text_key": &"ui_help_key_esc", "key_fb": "Esc", "desc_key": &"ui_help_desc_cancel_drag"},
    {"key_text_key": &"ui_help_key_f1", "key_fb": "F1 / ?", "desc_key": &"ui_help_desc_help"},
]

func _ready() -> void:
    super._ready()
    _build_body()
    visible = false  # start hidden

func _build_body() -> void:
    var grid := GridContainer.new()
    grid.columns = 2
    get_body_container().add_child(grid)
    for s in SHORTCUTS:
        var k := Label.new()
        k.text = Localization.t(s["key_text_key"], s["key_fb"])
        var d := Label.new()
        d.text = Localization.t(s["desc_key"], "")
        grid.add_child(k)
        grid.add_child(d)

func _input(event: InputEvent) -> void:
    if not visible: return
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_ESCAPE or event.keycode == KEY_F1 or event.keycode == KEY_QUESTION:
            visible = false
            get_viewport().set_input_as_handled()
```

**Решение про modal-overlay:** не делаем затемняющий ColorRect позади — BasePanel сам по себе достаточно чтобы юзер видел что фокус «на нём». Если будет UX-жалоба — добавим позже. **Не**-modal изначально проще.

**Объём:** ~50 строк + ~10 loc-keys.

**Proof of life:** F1 → видим список. Esc → закрыт. Loc-keys работают (en + ru).

### Φ-7.c. Wire help modal в level_editor.tscn

В Φ-9 добавляю инстанс `editor_help_modal.tscn` в HUD как child. Controller resolve'ит через `help_modal_path`.

---

## Φ-8. Game Editor / Playtest / pause-menu cycle integration

**Что:** Пересмотреть все cross-refs `map_editor.tscn` → `level_editor.tscn`. Тесная связь с Φ-10 (удаление legacy), но логически отдельное.

**Файлы:**
- `scripts/presentation/dev/game_editor_controller.gd:222`
- `scripts/presentation/pause_menu.gd:141`
- `scripts/presentation/godmode/godmode_input.gd:80`

Простая sed-замена `scenes/dev/map_editor.tscn` → `scenes/dev/level_editor.tscn` в каждом файле. После Φ-6.d/e EditorController уже знает как обработать `ActiveLevel.has_queued()` и `ActiveGame.has_queued_for_editor()` — handoff работает.

**Risk anchor:** Game Editor pre-060 ходит в map_editor.tscn для ВСЕХ уровней включая многоволновые. После 060 ходит в level_editor.tscn — многоволновые показывают warning toast (AC37) и работают на wave 0. Это **не регресс** для Никиты потому что он не работает с картами; для Андрея/Алексея это видно при тесте.

**Proof of life:** Game Editor → Edit → Level Editor открывается с правильной картой → Exit → Game Editor с тем же progress'ом. Playtest → ESC → Pause → Back to Editor → Level Editor с тем же `__playtest__.json` (rountdrip).

**Объём:** ~3 строки правок суммарно.

---

## Φ-9. hex_grid.tscn fix + level_editor.tscn updates

### Φ-9.a. hex_grid.tscn fix (F-059-IMPL-4)

**Решение:** убрать typed `@export TileMapLayer` поля, заменить на `@onready`.

**Файл `scripts/core/arena/hex_grid.gd`:**
```gdscript
# BEFORE:
@export var tile_map_layer: TileMapLayer
@export var vfx_overlay: TileMapLayer

# AFTER:
@onready var tile_map_layer: TileMapLayer = $Terrain
@onready var vfx_overlay: TileMapLayer = $VFXOverlay
```

**Файл `scenes/arena/hex_grid.tscn`:**
```
# BEFORE (lines 7-9):
[node name="HexGrid" type="Node2D"]
script = ExtResource("1_hexgrid")
tile_map_layer = NodePath("Terrain")
vfx_overlay = NodePath("VFXOverlay")

# AFTER (lines 7-?):
[node name="HexGrid" type="Node2D"]
script = ExtResource("1_hexgrid")
```

**Файл `scripts/presentation/dev/editor/editor_controller.gd` — удалить workaround:**
```gdscript
# DELETE these 6 lines:
if _grid != null:
    if _grid.tile_map_layer == null:
        _grid.tile_map_layer = _grid.get_node_or_null("Terrain") as TileMapLayer
    if _grid.vfx_overlay == null:
        _grid.vfx_overlay = _grid.get_node_or_null("VFXOverlay") as TileMapLayer
    _grid.initialize()

# REPLACE with:
if _grid != null:
    _grid.initialize()
```

**Risk anchor — order of operations:** `@onready var tile_map_layer = $Terrain` инициализируется в `_ready()` HexGrid. EditorController в своём `_ready()` вызывает `_grid.initialize()`. **Children's `_ready` runs before parent's `_ready` в Godot 4** (bottom-up). Значит на момент EditorController._ready → _grid.initialize() — `_grid.tile_map_layer` уже инициализирован. ✓

**Risk anchor — godmode.tscn:** godmode тоже использует HexGrid. Если godmode controller тоже вызывает `_grid.initialize()` или читает `tile_map_layer` — изменение `@onready` не должно регрессить (тот же reasoning). Smoke: открыть godmode и убедиться что работает без error логов.

**Risk anchor — map_editor.tscn:** тоже использует HexGrid. Но мы его удаляем в Φ-10. Если Φ-9 идёт ДО Φ-10 — есть момент когда map_editor может не запускаться. **Это ОК** — мы всё равно удаляем; но на ревью это видно как «map_editor сломан в commit X, удалён в commit Y». Для clean PR — Φ-9 и Φ-10 в одном коммите, или Φ-9 после Φ-10.

**Решение про order:** Φ-10 (удаление legacy) **до** Φ-9 (hex_grid fix) внутри финального flow. То есть на момент когда чиним hex_grid.tscn — map_editor уже удалён, не нужно его проверять.

### Φ-9.b. level_editor.tscn updates

Добавить:
- `ObjectsOverlay` (Node2D, `scripts/presentation/dev/objects_overlay.gd`) — child HexGrid.
- `SpawnersOverlay` (Node2D, `scripts/presentation/dev/spawners_overlay.gd`) — child HexGrid.
- `ConfirmModal` (instance `scenes/ui/confirm_modal.tscn`) — child HUD. Для autosave restore prompt.
- `EditorHelpModal` (instance `scenes/dev/editor/editor_help_modal.tscn`) — child HUD.

Обновить:
- `EditorController` exports: `objects_overlay_path`, `spawners_overlay_path`, `help_modal_path`.

**Объём:** +4 узла в .tscn, +3 поля в @export.

---

## Φ-10. Удаление legacy + cross-refs полное пересмотрение

**Что:** Атомарно удалить 12 файлов + map_editor.tscn + cross-refs в main_menu (gd + tscn). Один коммит.

**Файлы для git rm:**
```
scenes/dev/map_editor.tscn
scripts/presentation/dev/map_editor_controller.gd
scripts/presentation/dev/floor_palette_panel.gd
scripts/presentation/dev/object_palette_panel.gd
scripts/presentation/dev/tool_panel.gd
scripts/presentation/dev/paint_preview.gd
scripts/presentation/dev/wave_panel.gd
scripts/presentation/dev/wave_diff_overlay.gd
scripts/presentation/dev/dialogue_trigger_panel.gd
scripts/presentation/dev/hotkey_overlay.gd
scripts/presentation/dev/delete_highlight.gd
scripts/presentation/dev/level_history.gd
```

**Risk anchor — orphan references:** перед `git rm` сделать grep по всему репо на каждый файл (особенно по `class_name` если он есть и по filename). Если что-то ссылается — это или другой удалён, или живой — нужно решить.

**Команды для проверки:**
```bash
for f in map_editor_controller floor_palette_panel object_palette_panel \
         tool_panel paint_preview wave_panel wave_diff_overlay \
         dialogue_trigger_panel hotkey_overlay delete_highlight level_history; do
    echo "=== $f ==="
    grep -rln "$f" --include="*.gd" --include="*.tscn" --include="*.tres" .
done
```

Все matches должны быть либо в файлах которые тоже удаляются, либо в `.git/`. Если есть в живом коде — приоритет: переписать чтобы не ссылалось, потом удалять.

**Cross-refs main_menu:**
- `scripts/presentation/main_menu.gd`:
  - line 46: `@onready var _map_editor_btn: Button = $VBox/MapEditorButton` — DELETE
  - line 47: переименовать `_level_editor_new_btn` → `_level_editor_btn`, NodePath → `$VBox/LevelEditorButton`
  - line 80: `_map_editor_btn.pressed.connect(_on_map_editor)` — DELETE
  - line 81: переименовать `_level_editor_new_btn.pressed.connect(_on_level_editor_new)` → `_level_editor_btn.pressed.connect(_on_level_editor)`
  - line 114-115: array references — обновить
  - line 143: `_on_map_editor()` — DELETE if it was the `start_in_map_editor` path; replace with `_on_level_editor()`
  - line 226-227: `_on_map_editor()` handler — DELETE
  - line 230-234: переименовать `_on_level_editor_new` → `_on_level_editor`

- `scenes/main_menu.tscn`:
  - DELETE node `MapEditorButton` (line ~64-67)
  - RENAME node `LevelEditorNewButton` → `LevelEditorButton`
  - UPDATE text key from `ui_main_menu_level_editor_new_button_text` to `ui_main_menu_level_editor_button_text`

**Локализация удаляемого map_editor button text key:**
- `ui_main_menu_map_editor_button_text` — orphan, удаляем в Φ-11.
- `ui_main_menu_level_editor_new_button_text` → переименовать в `ui_main_menu_level_editor_button_text` в Φ-11.

**Proof of life:** Открыть main_menu — единственная кнопка «Level Editor». Проект компилируется. Поиск `map_editor` по репо возвращает только строки в HANDOFF.md / specs/* / docs/* / .git/.

---

## Φ-11. Loc-keys cleanup

**Что:** Удалить orphan-ключи и добавить новые. Mass operation через скрипт.

**Удаляемые ключи (orphan после Φ-10):**

Поиск pattern: всё что начинается с `ui_map_editor_` / `ui_object_palette_` / `ui_tool_panel_` / `ui_wave_panel_` / `ui_wave_diff_` / `ui_dialogue_trigger_panel_` / `ui_hotkey_overlay_` / `ui_main_menu_map_editor_*` — orphan'ы.

**Проверка перед удалением:** grep по живому коду каждого ключа.

```bash
# Generate suspect list
grep -oE '"ui_(map_editor|object_palette|tool_panel|wave_panel|wave_diff|dialogue_trigger_panel|hotkey_overlay)[^"]*"' \
    data/localization/en.json | sort -u > /tmp/suspect-keys.txt

# For each, check if used in live code
while read key; do
    key_clean=$(echo "$key" | tr -d '"')
    matches=$(grep -rln "$key_clean" --include="*.gd" --include="*.tscn" .)
    if [ -z "$matches" ]; then
        echo "ORPHAN: $key_clean"
    else
        echo "LIVE: $key_clean — $matches"
    fi
done < /tmp/suspect-keys.txt
```

ORPHAN'ы — удаляем. LIVE — оставляем (это ключи которые переезжают в новый код, например `ui_floor_palette_erase` который используется HexTilePalette).

**Оставляемые ключи (после проверки):**
- `ui_floor_palette_erase` — используется HexTilePalette.
- Любые `ui_object_palette_*` если случайно реюзаются — пока не вижу таких в новых палитрах, но grep покажет.

**Новые ключи (en + ru, parallel update):**
```
ui_main_menu_level_editor_button_text          | Level Editor                | Редактор уровней
ui_layers_panel_tab_hexes                      | Hexes                       | Гексы
ui_layers_panel_tab_spawners                   | Spawners                    | Спаунеры
ui_layers_panel_tab_objects                    | Objects                     | Объекты
ui_spawner_palette_player                      | Player                      | Игрок
ui_level_editor_multi_wave_warning             | Multi-wave map (%s waves)…  | Многоволновая карта…
ui_level_editor_autosave_restore_title         | Restore unsaved work?       | Восстановить?
ui_level_editor_autosave_restore_body          | Found unsaved…              | Найдены несохранённые…
ui_level_editor_autosave_restore_yes           | Restore                     | Восстановить
ui_level_editor_autosave_restore_no            | Discard                     | Отбросить
ui_help_key_q .. ui_help_desc_help (10×2)      | (см. SHORTCUTS в Φ-7.b)     | (RU перевод)
```

**Renamed key:**
- `ui_main_menu_level_editor_new_button_text` → `ui_main_menu_level_editor_button_text`. Старый удалить, добавить новый. Проверить что нигде ещё не используется старый (его читал главное меню, после Φ-10 — обновлённый текст).

**Risk anchor:** localization tooling (`data/localization/_sources.json`) — это автоматическое отображение ключ → исходник. Ну не совсем — посмотрел в репо, выглядит как автогенерация. Возможно автогенерится в CI. Если так — не трогаем `_sources.json`, оно сгенерится само.

**Objection:** F-059-IMPL-3 в 059 finding'е сказал «`ui_level_meta_panel_title` не было, пришлось добавлять как новый». Это уже добавлено в 059. Не переоцениваем что есть.

**Объём:** ~30 удалённых ключей × 2 файла (en + ru), ~25 новых ключей × 2 файла.

---

## Φ-12. Smoke prelude + PR readiness

**Что:** Финальный manual smoke по checklist'у F-060-9 (см. spec.md §7). Если что-то падает — back-fix в той же ветке.

**Сценарии:**
1. Пустой smoke (новая карта). Базовые AC1-AC18.
2. Save/Load roundtrip.
3. Game Editor handoff (открыть карту через Game Editor → редактировать → Exit → Game Editor показывает изменения).
4. Playtest cycle (Playtest → играть пару ходов → ESC → Pause → Back to Editor — все изменения сохранены).
5. Multi-wave map (если есть в data/maps/) — warning toast виден, save сохраняет все волны (проверить json roundtrip).
6. Autosave restore (paint, Ctrl+W close без save, reopen — modal предлагает restore).
7. Все шорткаты Q/W/E/Tab/1-9/Esc/F1/Shift+RMB.
8. hex_grid.tscn fix — никаких warn/error логов про tile_map_layer = null.
9. Cross-references — `grep -rln "map_editor" .` вне docs/specs/HANDOFF — пусто.
10. Compile — нет parse errors, нет warning'ов про unused.

**PR description:** ссылка на `specs/060-level-editor-layers/spec.md`, summary cмены, F-060-* пункты которые юзер должен проверить.

---

## Глобальные риски и митигации

**R1. EditorController снова вылезет за 300 строк после всех расширений.** Mitigation: измерять после каждой Φ. Если на Φ-6 уже >280 — отделять `_prompt_autosave_restore` + `_check_multi_wave_warning` в EditorIO.

**R2. PanelTabBar emit на `set_active` сломает что-то в существующих consumers (tabbed_panel_demo).** Mitigation: тест демо-сцены после Φ-1.

**R3. ButtonGroup при switch'е таба теряет state.** Если AC6 не пройдёт smoke — придётся явно сохранять/восстанавливать selection через LayersModel. Mitigation: фикс в Φ-3 если smoke ловит.

**R4. Overlay refresh после mass mutation тяжёлый.** Если paint каждого spawner вызывает full overlay rebuild — лагает на больших картах. Mitigation: smoke на 50+ объектах. Если тормозит — incremental update в overlay (но это спек 062+).

**R5. Autosave debounce на drag.** При drag-paint каждое движение сбрасывает таймер; если drag длится 30 секунд — autosave не fires до окончания. На крупных перестройках это плохо. Mitigation: max-debounce 5s (force-fire даже если drag активен). Surface как finding если важно.

**R6. Confirm modal в restore prompt пропускает event если вызван слишком рано.** В `_ready` модал может ещё не быть готов. Mitigation: `await get_tree().process_frame` перед `modal.ask(...)`.

**R7. Локализация: добавление 25+ ключей в en+ru может привести к опечаткам/несогласованности.** Mitigation: парный review en/ru side-by-side. Стасян/Никита могут пройтись по русскому.

**R8. После удаления `level_history.gd` (undo) — кто-то в репо может ссылаться на него через ad-hoc preload.** Mitigation: grep `level_history` перед удалением (Φ-10).

---

## Sequencing summary

```
Φ-1 (framework)  →  Φ-2 (io extract)  →  Φ-3 (layers/panel migration)
                                          ↓
Φ-12 ← Φ-11 ← Φ-10 ← Φ-9 ← Φ-8 ← Φ-7 ← Φ-6 (controller) ← Φ-5 (dispatcher) ← Φ-4 (palettes)
```

Φ-1 и Φ-2 могут идти параллельно (изолированы). Остальные строго последовательно. Φ-9 (hex_grid fix) и Φ-10 (delete legacy) логически связаны — делать в одном коммите.

**Estimated commits:** 8-12 (по одному на Φ кроме Φ-9+Φ-10 = один).

**Estimated размер PR:** +2500 / -3700 строк (новые палитры + расширение dispatcher + IO + delete легаси).

---

## Mini-handoff в следующий чат (для имплементации)

Лежит отдельно в `tasks.md` — там детальный T-список плюс компактный handoff.
