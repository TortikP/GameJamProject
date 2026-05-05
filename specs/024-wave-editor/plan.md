# 024-wave-editor — plan

Имплементационная разнарядка. Файловые пути, API, порядок задач. Acceptance criteria — в `spec.md`.

## File map

### Новые файлы

| Путь | Назначение |
|---|---|
| `scripts/runtime/wave_controller.gd` | Runtime логика волн, авто-клир, переключение снапшотов |
| `scenes/runtime/wave_controller.tscn` | Scene-обёртка для WaveController |
| `scripts/infrastructure/run_score.gd` | Autoload `RunScore` |
| `scripts/presentation/ui/wave_timeline.gd` | Виджет таймлайна (EDIT + RUNTIME) |
| `scenes/ui/wave_timeline.tscn` | Сцена виджета |
| `scripts/presentation/ui/score_corner.gd` | HUD score widget |
| `scenes/ui/score_corner.tscn` | Сцена HUD score |
| `scripts/presentation/dev/wave_panel.gd` | Editor side-panel — wraps WaveTimeline (EDIT) + кнопки |
| `scripts/presentation/runtime/spawner_placeholder.gd` | Sprite2D + Label для cooldown визуала |
| `scenes/runtime/spawner_placeholder.tscn` | Scene |
| `data/maps/sample_waves.json` | 3-волновый демо-уровень |

### Модифицируемые файлы

| Путь | Изменение |
|---|---|
| `scripts/core/maps/level_data.gd` | + `waves` поле, миграция legacy, `get_wave_start_turn()`, расширенный `validate()` |
| `scripts/core/maps/level_serializer.gd` | Запись waves-формата всегда; чтение — backward-compat через `LevelData.from_dict` |
| `scripts/core/maps/level_loader.gd` | После `apply_to(grid, registry, level)` — `wave_controller.start_level(level)` |
| `scripts/core/arena/hex_grid.gd` | + `find_passable_for_displacement()`, + `displace_actor()` |
| `scripts/infrastructure/event_bus.gd` | + `wave_started`, `wave_cleared`, `level_completed`, проверить `actor_spawned` |
| `scripts/presentation/dev/map_editor_controller.gd` | `active_wave_index`, scoped placement, cumulative repaint, highlight overlay, spawner timer input |
| `scenes/dev/map_editor.tscn` | Mount WavePanel сверху |
| `scenes/dev/godmode.tscn` | Mount WaveController + WaveTimeline (RUNTIME) + ScoreCorner |
| `scripts/presentation/godmode/godmode_controller.gd` | Connect WaveController, не запускать procedural-paint после loader |
| `scripts/presentation/ui/ui_theme.gd` | + `WAVE_*` константы, + новые font sizes если нужны |
| `config/game_speed.cfg` | + `[battle] wave_transition_sec=0.15`, + `[ui] wave_tick_anim_sec=0.2`, `score_punch_sec=0.25` |
| `project.godot` | Регистрация autoload `RunScore` после `EventBus` |
| `data/maps/_schema.md` | Доппункт «waves» |
| `HANDOFF.md` | Update §work-in-progress + §модули после мержа |

### Не трогаем

- `scripts/core/actors/actor.gd` — никаких полей не добавляем (timer на спавнере, не на актёре).
- `scripts/core/skill/*.gd` — отдельный домен, к волнам не привязан.
- `scripts/presentation/dialogue_*.gd` — 025 туда заходит, не мы.

## API shapes

### `LevelData` extension

```gdscript
# scripts/core/maps/level_data.gd

class_name LevelData
extends Resource

@export var name: String = ""
@export var version: int = 2     # bump from 1; loader handles v1 migration
@export var tileset_path: String = "res://scenes/dev/godmode_terrain.tres"
@export var waves: Array[Dictionary] = []   # [{index, is_special, turns_to_next, floor, objects, spawners}]

func get_wave_start_turn(idx: int) -> int:
    var t := 0
    for i in range(idx):
        t += int(waves[i].get("turns_to_next", 0))
    return t

func validate() -> Array[String]:
    var errs: Array[String] = []
    # ... contiguous index, single player spawner, coord ∈ floor of own wave,
    #     turns_to_next constraints, timer constraints, warn on timer > turns_to_next
    return errs

static func from_dict(d: Dictionary) -> LevelData:
    var lvl := LevelData.new()
    lvl.name = d.get("name", "")
    lvl.tileset_path = d.get("tileset_path", "res://scenes/dev/godmode_terrain.tres")
    if d.has("waves"):
        lvl.version = int(d.get("version", 2))
        lvl.waves = d["waves"]
    else:
        # legacy v1: pack root floor/objects/spawners into waves[0]
        lvl.version = 2
        lvl.waves = [{
            "index": 0,
            "is_special": false,
            "turns_to_next": 0,
            "floor": d.get("floor", []),
            "objects": d.get("objects", []),
            "spawners": _legacy_spawners_with_default_timer(d.get("spawners", [])),
        }]
    return lvl

static func _legacy_spawners_with_default_timer(arr: Array) -> Array:
    # backward compat: legacy spawners had no timer; default to 1 (spawn on turn 1).
    var out: Array = []
    for s in arr:
        var copy: Dictionary = s.duplicate()
        if not copy.has("timer"):
            copy["timer"] = 1
        out.append(copy)
    return out
```

### `WaveController`

```gdscript
# scripts/runtime/wave_controller.gd
class_name WaveController
extends Node

signal wave_changed(prev_index: int, new_index: int, is_special: bool)

var _level: LevelData = null
var _current_wave_index: int = -1
var _turns_into_wave: int = 0
var _pending_spawners: Array[Dictionary] = []  # active placeholders w/ countdown
var _placeholder_nodes: Dictionary = {}        # Vector2i -> SpawnerPlaceholder

@onready var _grid: HexGrid = get_node("../HexGrid")  # path from godmode.tscn structure

func _ready() -> void:
    EventBus.world_turn_ended.connect(_on_world_turn_ended)
    EventBus.actor_died.connect(_on_actor_died)

func start_level(level: LevelData) -> void:
    _level = level
    _current_wave_index = -1
    _advance_wave()

func _advance_wave() -> void:
    var prev := _current_wave_index
    _current_wave_index += 1
    if _current_wave_index >= _level.waves.size():
        EventBus.level_completed.emit(RunScore.total)
        _current_wave_index = prev   # park, do not rollover
        return
    _apply_wave_snapshot(_current_wave_index)
    var w: Dictionary = _level.waves[_current_wave_index]
    EventBus.wave_started.emit(_current_wave_index, bool(w.get("is_special", false)))
    wave_changed.emit(prev, _current_wave_index, bool(w.get("is_special", false)))

func _apply_wave_snapshot(idx: int) -> void:
    # 1. floor diff: erase missing → push residents → set new
    # 2. objects diff: remove gone → push residents if landed-on impassable → add new
    # 3. discard pending; instantiate placeholders for waves[idx].spawners (skip player on idx > 0)
    # 4. reset _turns_into_wave
    pass  # implementation in P3

func _on_world_turn_ended(turn: int) -> void:
    if _current_wave_index < 0: return
    _turns_into_wave += 1
    _decrement_pending_and_spawn()
    var w: Dictionary = _level.waves[_current_wave_index]
    if _turns_into_wave >= int(w.get("turns_to_next", 0)) and int(w.get("turns_to_next", 0)) > 0:
        _advance_wave()

func _decrement_pending_and_spawn() -> void:
    var still: Array[Dictionary] = []
    for sp in _pending_spawners:
        sp["timer"] = int(sp["timer"]) - 1
        if int(sp["timer"]) <= 0:
            _spawn_from_pending(sp)
        else:
            _update_placeholder_label(sp)
            still.append(sp)
    _pending_spawners = still

func _spawn_from_pending(sp: Dictionary) -> void:
    # call existing LevelLoader._spawn_enemy logic OR ActorRegistry directly
    # remove placeholder node from scene
    pass

func _on_actor_died(actor) -> void:
    call_deferred("_check_auto_clear")

func _check_auto_clear() -> void:
    if _current_wave_index < 0: return
    if _living_enemies_count() > 0: return
    if not _pending_spawners.is_empty(): return
    var w: Dictionary = _level.waves[_current_wave_index]
    var unused: int = max(0, int(w.get("turns_to_next", 0)) - _turns_into_wave)
    RunScore.add(unused)
    EventBus.wave_cleared.emit(_current_wave_index, unused)
    _advance_wave()

func _living_enemies_count() -> int:
    # query ActorRegistry for actors with kind=&"enemy" and is_alive
    return 0  # impl
```

### `HexGrid` push-out

```gdscript
# scripts/core/arena/hex_grid.gd

const MAX_DISPLACEMENT_RADIUS: int = 30

func find_passable_for_displacement(from: Vector2i, exclude: Array[Vector2i] = []) -> Vector2i:
    var visited: Dictionary = {}
    visited[from] = true
    for c in exclude:
        visited[c] = true
    var frontier: Array[Vector2i] = [from]
    var radius := 0
    while not frontier.is_empty() and radius <= MAX_DISPLACEMENT_RADIUS:
        var next_frontier: Array[Vector2i] = []
        for cur in frontier:
            for nbr in _hex_neighbours_clockwise_from_north(cur):
                if visited.has(nbr): continue
                visited[nbr] = true
                if _is_passable(nbr):
                    return nbr
                next_frontier.append(nbr)
        frontier = next_frontier
        radius += 1
    return Vector2i.MAX

func displace_actor(actor: Actor, exclude: Array[Vector2i] = []) -> bool:
    var from: Vector2i = actor.coord
    var target: Vector2i = find_passable_for_displacement(from, exclude)
    if target == Vector2i.MAX:
        actor.kill_with_reason("crushed")  # add this method to Actor if missing
        return true
    var occupant: Actor = _actor_at(target)
    if occupant != null:
        var ok: bool = displace_actor(occupant, exclude + [from, target])
        if not ok:
            return false
    move_actor(actor, target)  # existing method; assumed to fire on_entered hooks
    return true

func _is_passable(coord: Vector2i) -> bool:
    if not has_cell(coord): return false                # outside floor
    var obj_id: StringName = get_tile_object_id(coord)  # 018 method
    if obj_id != &"":
        var obj := TileObjectRegistry.get_object(obj_id)
        if obj != null and not obj.walkable: return false
    return _actor_at(coord) == null  # checked separately in chain logic
```

Note: `_actor_at`, `move_actor`, `has_cell`, `get_tile_object_id` — assumed-existing or trivially adaptable (verified at imp time, not now).

### `RunScore`

```gdscript
# scripts/infrastructure/run_score.gd
extends Node

signal score_changed(total: int, delta: int)

var total: int = 0

func _ready() -> void:
    if EventBus.has_signal("run_started"):
        EventBus.run_started.connect(reset)

func add(delta: int) -> void:
    if delta == 0: return
    total += delta
    score_changed.emit(total, delta)

func reset() -> void:
    total = 0
    score_changed.emit(total, 0)
```

### `WaveTimeline`

```gdscript
# scripts/presentation/ui/wave_timeline.gd
class_name WaveTimeline
extends Control

enum Mode { EDIT, RUNTIME }

@export var mode: Mode = Mode.EDIT

signal anchor_clicked(wave_index: int)               # EDIT
signal anchor_context_requested(wave_index: int, screen_pos: Vector2)  # EDIT
signal gap_context_requested(after_idx: int, screen_pos: Vector2)      # EDIT
signal turns_to_next_changed(wave_index: int, new_value: int)          # EDIT
signal add_wave_pressed                              # EDIT
signal special_toggled(wave_index: int)              # EDIT (proxy via context)

var _level: LevelData = null
var _current_wave_runtime: int = 0
var _turns_into_wave_runtime: int = 0

func bind_level(level: LevelData) -> void: ...
func set_runtime_state(current_wave: int, turns_into: int) -> void: ...

# Internals: renders via _draw + dynamically-sized child Controls (anchors, LineEdits, "+ Wave" button)
# 1 turn = 1 px; bar length = sum of turns_to_next + paddings
```

## Sequencing (P0..P7)

Каждая P-фаза — отдельный коммит, отдельно тестируется (smoke-проверки в spec).

- **P0 setup:** этот коммит — папка переименована, spec/plan/tasks написаны.
- **P1 data + autoload + EventBus:** `LevelData.waves`, миграция, validate, RunScore autoload, EventBus signals. **Smoke:** загрузить старую sample.json в редакторе — открывается, играется как до.
- **P2 push-out:** HexGrid методы + dev-сцена `scenes/dev/displacement_smoke.tscn` с кнопкой «убрать пол под актёром» — actor должен прыгнуть на ближайший проходимый, цепочка работает. **Smoke:** ручной кейс с тремя актёрами в ряд, удалить пол под средним.
- **P3 WaveController + spawner placeholder:** runtime логика + плейсхолдер с цифрой. Wave_started/cleared/level_completed эмитятся. Sample карту добавим в P7. **Smoke:** ручная инстанциация `LevelData` с 2 волнами в коде, godmode_controller подаёт в WaveController, плейсхолдеры считают, авто-клир переходит дальше.
- **P4 WaveTimeline widget:** оба mode. Сначала RUNTIME (легче), потом EDIT. **Smoke:** preview-сцена `scenes/dev/wave_timeline_preview.tscn` с моком LevelData.
- **P5 editor integration:** WavePanel сверху, active wave routing, cumulative repaint, highlight, spawner timer input, wave operations (+/insert/delete/special/edit turns). **Smoke:** ручное создание 3-волнового уровня в редакторе, save, reload — структура сохраняется.
- **P6 score corner:** HUD widget + tween. **Smoke:** в дев-сцене дёрнуть `RunScore.add(5)` — цифра обновилась с пульсом.
- **P7 sample + smoke:** `data/maps/sample_waves.json`, full E2E playthrough. **Smoke:** AC-W18 + AC-W19.
- **P-cleanup:** `_schema.md` доку, HANDOFF.md update.

Минимальный играбельный scope если время кончается: **P1 + P2 + P3 + P7** (без EDIT-mode таймлайна и редактора волн). Sample.json правится руками. Score и HUD timeline RUNTIME — желательно, но cut'абельны.

## Risk register

| ID | Риск | Вероятность × Серьёзность | Митигация |
|---|---|---|---|
| R1 | Push-out oscillation (A→B→A) | Низкая × Высокая | `exclude` в рекурсии аккумулирует исходную клетку + промежуточные target'ы. Тест в P2 dev-сцене. |
| R2 | `actor_died` ranges mid-animation, auto-clear ловит momentum | Средняя × Средняя | `call_deferred` для `_check_auto_clear`. Тест: убить двух врагов одной AOE — клир срабатывает один раз. |
| R3 | Snapshot JSON раздувается на 10+ волн | Низкая × Низкая | 30 КБ оценка приемлема. Если станет проблемой — pre-compress whitespace в `JSON.stringify` (`""` separator), снимет 30-40%. Schema not affected. |
| R4 | Cumulative-state redraw в редакторе тормозит при больших картах | Средняя × Низкая | Cache last-rendered wave index. Rebuild только на `active_wave_index` change или edit current wave. |
| R5 | Highlight (новых-в-этой-волне) визуально шумит | Средняя × Низкая | Низкая интенсивность по умолчанию (alpha 0.3 outline). Toggle в WavePanel «Show diff highlight» если шум. |
| R6 | `world_turn_ended` сигнал ещё не подключён в боевой сцене для всех тиков | Низкая × Высокая | Verified: signal в EventBus уже есть (line 53). Найти, кто emit'ит, убедиться что emit'ится после полного хода (player + AI), а не после каждого actor'а. Если нет — добавить emit в BattleController в P3. |
| R7 | `spawner.kind = player` со spawn-таймером ≠ 1 → game ломается (player должен быть на сцене с т=0) | Низкая × Средняя | Validate: player spawner timer всегда 1, force на load. WARN если author поставил другое. |
| R8 | Деструктивные операции в редакторе (Delete wave) теряют контент без undo | Высокая × Средняя | Confirm-modal с danger-стилем (per AC-W6). Autosave перед delete (autosave 020 уже работает на любое изменение). Undo — out_of_scope. |
| R9 | Inline LineEdit для turns_to_next и spawner timer ловит фокус и блокирует другие inputs редактора | Средняя × Низкая | На `focus_exited` коммитим и снимаем фокус. Esc → cancel + restore prev value. |
| R10 | Push-out выкидывает actor в гекс с другим objection (lava + spike) → одновременные эффекты | Низкая × Средняя | Damage-on-land — последовательно через TileObjectResolver, существующий механизм. OQ-12 на пост-плейтест. |

## Tests / smoke checklist

### P1 smoke
- Загрузить `data/maps/sample.json` (легаси v1) в редакторе → должна открыться без ошибок, валидация проходит, `_level.waves.size() == 1`.
- Save из редактора → JSON содержит `waves` поле, не `floor/objects/spawners` на корне.

### P2 smoke
- В `displacement_smoke.tscn` — 3 актёра в ряд (A, B, C). Удалить пол под B. B → толкнут на ближайший проходимый, **C не сдвинут** (их разделяет проходимая клетка). Положить пропасть и под A → A должен прыгнуть мимо/вокруг B.
- Стресс: окружить актёра пропастями со всех 6 сторон + второе кольцо тоже непроходимо → kill_with_reason.

### P3 smoke
- Хардкод-сценарий: уровень с двумя волнами. Wave 0: player + manekin timer=2, turns_to_next=4. Wave 1: 1 manekin timer=1.
- Запустить → manekin появляется на ходу 2 → если player убивает на ходу 3 → score += 1 → wave 1 стартует мгновенно → новый manekin появляется на ходу 1 wave-1.
- Если player не убивает manekin → wave 0 заканчивается на ходу 4 без auto-clear, score += 0, wave 1 стартует, manekin волны 0 живёт и блокирует auto-clear волны 1.

### P4 smoke
- `wave_timeline_preview.tscn` — мок LevelData с 4 волнами, 2 special. Бар рисуется корректно. EDIT mode: клик на якоре эмитит `anchor_clicked`, RMB → `anchor_context_requested`, числа editable.
- RUNTIME mode: дёргать `set_runtime_state(curr, into)` руками — часы-курсор движется, числа decrement'ятся, анимация tick видна.

### P5 smoke
- В редакторе: создать 3-волновый уровень (через + Wave x2), переключаться между волнами, ставить разные объекты в каждой, copy-from-prev, delete (с confirm), insert между, toggle special.
- Save → JSON корректен. Load → структура восстанавливается.

### P6 smoke
- В тест-сцене: `RunScore.add(5)` через консоль → label обновляется с punch.

### P7 smoke (E2E)
- AC-W18 / AC-W19. Полный playthrough sample_waves.json через main menu → Load Custom Level → бой → 3 волны проигрываются → push-out демо на волне 2 работает → score growing → `level_completed` fires.

## Open coordination questions

- **Egor.** `find_passable_for_displacement` + `displace_actor` — PR review просим. Метод аддитивный, не ломает существующий API. Проверим, что `move_actor` уже триггерит on_entered хуки; если нет — отдельный inline call.
- **Stasyan.** После мержа: правит `sample_waves.json`, добавляет 2-3 production-карт в `data/maps/`, балансит `turns_to_next` и `timer`'ы. Не нужно от него к моменту мержа.
- **Никита.** 025-level-dialogues потребляет наши сигналы. Никаких блокеров от нас.

## Notes for implementer

- **Не использовать `create_timer(...)` нигде.** Все таймауты — через `GameSpeed.wait(...)`. См. CLAUDE.md «Timing».
- **Все цвета и стили в WaveTimeline** — через `UiTheme.X`, не inline. Новые константы добавлять в `UiTheme` в том же PR (см. CLAUDE.md «UI colors»).
- **Шрифты для цифр на спавнере и score corner** — через `UiTheme.FS_NUM_*` константы. Outline через `UiTheme.apply_world_text_outline`. См. CLAUDE.md «Visibility doctrine».
- **Hex polygon в WaveTimeline?** Не используется — таймлайн линейный. Но если ремесленник захочет рисовать якоря-как-гексы — `HexGeometry.flat_top_polygon(tile_size)` (не hardcode).
- **Godot 4.6 traps в CLAUDE.md** — особенно про `Array[CustomClass]` и `:=` с `load(...).new()`. Spawner-записи — Dictionary, не custom class. ОК.
- **`class_name` для `WaveController`, `RunScore` (как класс-обёртка для autoload-singleton'a)** — проверить, что не коллидит с Godot internals (см. trap про `Logger`). `WaveController` и `RunScore` — оба safe.
