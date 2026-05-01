# 019-map-editor — plan

**Spec:** [`spec.md`](./spec.md)

## Файлы

| Путь | Что | Размер |
|---|---|---|
| `scripts/core/maps/level_data.gd` | NEW pure data class + validate | ~80 |
| `scripts/core/maps/level_serializer.gd` | NEW JSON in/out (FileAccess) | ~70 |
| `scripts/core/maps/level_loader.gd` | NEW apply LevelData → grid + spawn | ~110 |
| `scripts/infrastructure/active_level.gd` | NEW autoload, queued path slot | ~15 |
| `scripts/core/arena/hex_grid.gd` | +`set_tile_object(coord, object_id)` setter, +`apply_level_data` thin wrapper | +30 |
| `scripts/presentation/dev/map_editor_controller.gd` | NEW main editor scene controller | ~400 |
| `scripts/presentation/dev/object_palette_panel.gd` | NEW palette + tabs + filters | ~180 |
| `scripts/presentation/dev/floor_palette_panel.gd` | NEW floor tile picker + tileset dropdown | ~120 |
| `scripts/presentation/dev/level_meta_panel.gd` | NEW name/save/load/playtest UI | ~120 |
| `scripts/presentation/dev/objects_overlay.gd` | NEW Sprite2D-per-object renderer | ~80 |
| `scripts/presentation/dev/spawners_overlay.gd` | NEW Sprite2D-per-spawner renderer | ~80 |
| `scripts/presentation/dev/delete_highlight.gd` | NEW Node2D, draws red hex polygon | ~50 |
| `scripts/presentation/dev/hover_highlight.gd` | NEW Node2D, draws hex contour at cursor | ~50 |
| `scripts/presentation/godmode/godmode_controller.gd` | +ActiveLevel check в `_ready()` | +20 |
| `scripts/presentation/main_menu.gd` | +2 button handlers + hotkey input | +30 |
| `scenes/main_menu.tscn` | +Map Editor / Load Custom Level кнопки | +10 |
| `scenes/dev/map_editor.tscn` | NEW scene file | scene |
| `data/maps/_schema.md` | NEW schema doc для Стасяна | ~80 |
| `data/maps/sample.json` | NEW pre-made test map | ~50 |
| `config/game_speed.cfg` | +section `[editor]`: `spawner_swap=0.2`, `place_feedback=0.05` | +5 |
| `project.godot` | +autoload `ActiveLevel`, +input action `dev_open_editor` (Ctrl+E) | +10 |

Итого: 13 новых файлов кода / 3 новых ассета (sample, schema doc, scene) / 5 правок существующих. Чисто additive — никаких rename / delete / breaking-API.

## API: LevelData

```gdscript
class_name LevelData
## Pure data; serialized 1:1 to JSON.

const SCHEMA_VERSION: int = 1

var name: String = "Untitled"
var version: int = SCHEMA_VERSION
var tileset_path: String = "res://scenes/dev/godmode_terrain.tres"

# floor entries: {"coord": Vector2i, "source_id": int, "atlas_coord": Vector2i}
var floor_cells: Array[Dictionary] = []

# object entries: {"coord": Vector2i, "object_id": StringName}
var objects: Array[Dictionary] = []

# spawner entries: {"coord": Vector2i, "kind": StringName, "ref": StringName}
var spawners: Array[Dictionary] = []

## Validation. Returns array of error messages (empty = valid).
func validate() -> Array[String]:
    var errors: Array[String] = []
    var floor_set: Dictionary = {}
    for f in floor_cells:
        floor_set[f.coord] = true
    var player_count: int = 0
    var occupancy: Dictionary = {}  # coord -> kind ("object" | "spawner")
    for o in objects:
        if not floor_set.has(o.coord):
            errors.append("Object %s on unpainted tile %s" % [o.object_id, o.coord])
        if occupancy.has(o.coord):
            errors.append("Tile %s already occupied" % o.coord)
        occupancy[o.coord] = "object"
    for s in spawners:
        if not floor_set.has(s.coord):
            errors.append("Spawner %s on unpainted tile %s" % [s.kind, s.coord])
        if occupancy.has(s.coord):
            errors.append("Tile %s already occupied" % s.coord)
        occupancy[s.coord] = "spawner"
        if s.kind == &"player":
            player_count += 1
    if player_count == 0:
        errors.append("No player spawner — set Player Spawn before saving")
    elif player_count > 1:
        errors.append("Multiple player spawners (%d) — only one allowed" % player_count)
    return errors

func to_dict() -> Dictionary
static func from_dict(d: Dictionary) -> LevelData
```

## API: LevelSerializer

```gdscript
class_name LevelSerializer

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

## Returns true on success, false on any IO/parse error (logs the reason).
static func save(level: LevelData, path: String) -> bool:
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        GameLogger.error("LevelSerializer", "Cannot write %s: %s" % [path, FileAccess.get_open_error()])
        return false
    f.store_string(JSON.stringify(level.to_dict(), "\t"))
    f.close()
    return true

## Returns null on read/parse failure; message via GameLogger.
static func load(path: String) -> LevelData
```

JSON format:
```json
{
  "name": "Tutorial 1",
  "version": 1,
  "tileset_path": "res://scenes/dev/godmode_terrain.tres",
  "floor": [
    {"coord": [0, 0], "source_id": 0, "atlas_coord": [0, 0]},
    {"coord": [1, 0], "source_id": 0, "atlas_coord": [0, 0]}
  ],
  "objects": [
    {"coord": [3, 2], "object_id": "lava_pool"}
  ],
  "spawners": [
    {"coord": [4, 4], "kind": "player", "ref": ""},
    {"coord": [6, 4], "kind": "enemy",  "ref": "manekin"}
  ]
}
```

`Vector2i` сериализуется как `[x, y]` массив (стандартный JSON). При парсинге — `Vector2i(arr[0], arr[1])`.

## API: LevelLoader

```gdscript
class_name LevelLoader

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const PLAYER_SCENE := preload("res://scenes/dev/player.tscn")
const MANEKIN_SCENE := preload("res://scenes/dev/manekin.tscn")

## Applies LevelData to an already-instantiated HexGrid + ActorRegistry.
## Caller responsibilities:
##   - grid.tile_map_layer assigned (the controller paints/clears as it sees fit)
##   - grid.initialize() will be called AFTER apply_to (or apply_to itself
##     depending on caller; godmode-controller calls grid.initialize() once,
##     after both _build_floor and any pre-spawn setup)
## Order of operations inside apply_to:
##   1. set tile_set on tile_map_layer to level.tileset_path
##   2. clear tile_map_layer cells, then set_cell per floor entry
##   3. caller calls grid.initialize() — _build_tile_map reads custom data
##   4. apply_to writes objects via grid.set_tile_object(coord, object_id)
##   5. spawn player + enemies at spawner coords
static func apply_to(grid: HexGrid, registry: ActorRegistry, level: LevelData) -> void
```

Особенность: спавнеры не имеют per-actor overrides в v1 (см. spec out_of_scope). Loader инстанциирует prefab из preload-таблицы (manekin → MANEKIN_SCENE). Если `enemy_id` не в таблице — warn и пропуск.

## API: HexGrid additions (additive)

```gdscript
## Set/clear an object on a coord at runtime. Updates HexTile.object_id and
## rebuilds pathfinder. Does NOT mutate TileSet custom data — runtime overlay.
func set_tile_object(coord: Vector2i, object_id: StringName) -> void:
    if not _tiles.has(coord):
        GameLogger.warn("HexGrid", "set_tile_object on unknown coord %s" % coord)
        return
    var tile: HexTile = _tiles[coord]
    tile.object_id = object_id
    _build_pathfinder()  # cheap (~hundreds of cells), straightforward

## Convenience for callers that already have a LevelData object — calls into LevelLoader.
## Optional helper, exists for symmetry with set_tile_object; can be skipped if all
## callers route through LevelLoader directly.
func apply_level_data(level: LevelData, registry: ActorRegistry) -> void:
    LevelLoader.apply_to(self, registry, level)
```

## API: ActiveLevel autoload

```gdscript
extends Node
## Single-slot queue for "the next scene-change should load this level".
## Set by editor (Playtest, Load Custom) or main menu (Load Custom Level).
## Read by godmode_controller in _ready() — consume() clears it.

var queued_path: String = ""

func queue(path: String) -> void: queued_path = path
func consume() -> String: var p := queued_path; queued_path = ""; return p
func has_queued() -> bool: return queued_path != ""
func clear() -> void: queued_path = ""
```

Регистрация в `project.godot`:
```
ActiveLevel="*res://scripts/infrastructure/active_level.gd"
```

## State machine редактора

```gdscript
enum Mode { IDLE, PLACING_FLOOR, ERASING_FLOOR, PLACING_OBJECT, PLACING_SPAWNER }

var _mode: Mode = Mode.IDLE
var _placing_atlas_coord: Vector2i           # for PLACING_FLOOR
var _placing_atlas_source: int               # for PLACING_FLOOR
var _placing_object_id: StringName           # for PLACING_OBJECT
var _placing_spawner_kind: StringName        # for PLACING_SPAWNER ("player" | "enemy")
var _placing_spawner_ref: StringName         # for PLACING_SPAWNER (enemy_id, "" for player)
var _pending_delete_coord: Vector2i = Vector2i(-1, -1)
var _drag_object_from_coord: Vector2i = Vector2i(-1, -1)  # P2: drag-existing
```

LMB handler — псевдо-таблица:

| _mode | hover empty floor | hover painted floor | hover floor with object | hover floor with spawner |
|---|---|---|---|---|
| IDLE | no-op | no-op | start drag (P2) | no-op |
| PLACING_FLOOR | set_cell + add to LevelData.floor | replace tile (overwrite atlas) | replace tile, keep object | replace tile, keep spawner |
| ERASING_FLOOR | no-op | erase_cell + remove any object/spawner here | erase + remove obj | erase + remove spawner |
| PLACING_OBJECT | toast «Сначала пол» | place + add to LevelData.objects | popup «Тайл занят» | popup «Тайл занят» |
| PLACING_SPAWNER (enemy) | toast «Сначала пол» | place + add to LevelData.spawners | popup | popup |
| PLACING_SPAWNER (player) | toast «Сначала пол» | place; if existed elsewhere → fade-out old | popup | popup (даже если это сам player — нельзя на себя) |

LMB также снимает pending_delete (без отмены LMB-действия).

RMB handler:

| _pending_delete_coord | hover coord |  result |
|---|---|---|
| `(-1,-1)` | C | mark C as pending; render red |
| C | C | execute delete (priority: spawner > object > floor); clear pending |
| C | D (≠ C) | re-mark D; clear C |

## Editor scene wiring

`scenes/dev/map_editor.tscn`:
- Root `MapEditor` (Node2D) — script `map_editor_controller.gd`
- Camera `EditorCamera` — переиспользуем `godmode_camera.gd` (pan + zoom; сам player-follow не активируется в редакторе, target = null)
- HexGrid инстанс из `scenes/arena/hex_grid.tscn` — использует тот же floor `tile_map_layer` (без VFXOverlay в редакторе — пустой, но узел оставляется чтобы `grid.initialize()` не упал)
- Overlays — детьми HexGrid, чтобы координатно совпадали с тайлами
- HUD CanvasLayer с панелями + ToastLayer + ConfirmModal

`map_editor.tscn` стартует с пустой картой:
- `_initial_paint()` рисует 5×5 квадрат грассы (`source_id=0, atlas=(0,0)` из godmode_terrain) — чтобы было куда сразу класть объекты.
- `dirty = false` после initial paint (initial paint не считается изменением).
- `LevelData` собирается синхронно — каждое placement-действие апдейтит `_level: LevelData`. Save = `LevelSerializer.save(_level, ...)`.

## Категоризация объектов в палитре

```gdscript
static func categorize(obj: TileObject) -> StringName:
    # Spawners ходят отдельным путём (не из TileObjectRegistry)
    if obj.breakable or obj.behavior_effect_id != &"":
        return &"interactive"
    return &"obstacle"
```

Применяется к каждому объекту при сборке палитры. Текущие 6 sample-объектов разложатся:
- **Obstacles**: `mountain` (ELEVATION, not breakable, no effect), `boulder` (LARGE, breakable=true → пойдёт в Interactive!).

Поправка: `boulder` имеет `breakable=true, hp=10` (см. 018 spec AC-O5). По правилу выше → Interactive. Это нормально — рушащийся валун *всё-таки* интерактивен, игрок может с ним взаимодействовать (бить).

Реальная категоризация sample-набора:
- **Obstacles** (no breakable, no effect): `mountain`, `wooden_table` ⚠️ (но `wooden_table` `breakable=true` → Interactive). Только `mountain` остаётся в Obstacle.
- **Interactive** (breakable OR effect): `lava_pool`, `heal_fountain`, `wooden_barrel`, `wooden_table`, `boulder`.

Получается перекос — почти все в Interactive. Это OK для v1 — категоризация детерминированная и понятная. Если Стасян добавит больше «чистой статики» (стены, кусты без HP), Obstacles наполнится.

Альтернатива (rejected для v1): добавить новое поле `category: StringName` в TileObject — трогает 018, требует Сергея, не критично сейчас.

## Filters

```gdscript
func _passes_filter(obj: TileObject) -> bool:
    var type_match: bool = (
        (_filter_large and obj.level == TileObject.Level.LARGE) or
        (_filter_small and obj.level == TileObject.Level.SMALL) or
        (_filter_elev  and obj.level == TileObject.Level.ELEVATION)
    )
    if not type_match:
        return false
    if _filter_has_effect_only and obj.behavior_effect_id == &"":
        return false
    return true
```

## Spawners — список из `data/enemies/`

```gdscript
func _build_spawner_list() -> Array[Dictionary]:
    var result: Array[Dictionary] = [{"kind": &"player", "ref": &"", "label": "Player Spawn"}]
    var dir := DirAccess.open("res://data/enemies/")
    if dir == null:
        return result
    for fn in dir.get_files():
        if not fn.ends_with(".json"): continue
        var enemy_id := fn.get_basename()
        result.append({"kind": &"enemy", "ref": StringName(enemy_id), "label": "Spawn: %s" % enemy_id})
    return result
```

Иконки спавнеров — placeholder Unicode-глиф для v1 (▲ player, ◆ enemy + цвет тинт по hash(enemy_id)). Когда придут спрайты от Кати — поменяем `sprite_path`-таблицу.

## Hotkey wiring

`project.godot` — добавить:
```
dev_open_editor={
"deadzone": 0.5,
"events": [Object(InputEventKey, ..., "ctrl_pressed":true, "keycode":69, ...)]
}
```
(Ctrl+E)

`MainMenu._unhandled_input`, `MapEditorController._unhandled_input`, `GodmodeController._unhandled_input` — на `Input.is_action_just_pressed("dev_open_editor")` → `change_scene_to_file("res://scenes/dev/map_editor.tscn")`. Если уже в редакторе — no-op.

Лейбл хоткея на кнопке: текст `"Map Editor [Ctrl+E]"` — без отдельного виджета (в стиле existing godmode-button). Простой, читаемый.

## Save flow подробно

```
1. user → Save click
2. read name from input field, sanitize → filename
3. validate level. errors → toast warn, exit
4. path := "res://data/maps/" + filename + ".json"
5. file exists? → ConfirmModal "Перезаписать %s?" (danger=true). cancel → exit
6. LevelSerializer.save(level, path). ok → toast success "Saved: %s". fail → toast error "Save failed: %s"
7. dirty = false
```

## Load flow (editor)

```
1. user → Load click
2. dirty? → ConfirmModal "Сохранить текущую карту?" (yes/no/cancel)
   - yes → run save flow first; on success continue; on fail abort
   - no → continue
   - cancel → exit
3. FileDialog FILE_MODE_OPEN_FILE, root_subfolder = "res://data/maps/", filter "*.json"
4. user picks file → LevelSerializer.load(path)
5. apply level to editor (clear ObjectsOverlay, repaint floor, restore objects, restore spawners)
6. dirty = false
```

## Playtest flow

```
1. user → Playtest click
2. validate level. errors → toast warn, exit
3. LevelSerializer.save(level, "res://data/maps/__playtest__.json")
4. ActiveLevel.queue("res://data/maps/__playtest__.json")
5. change_scene_to_file("res://scenes/dev/godmode.tscn")
```

`__playtest__.json` — leading double-underscore чтобы файл не путали с пользовательскими картами. Не в gitignore — в gitignore добавляется.

## godmode_controller.gd patches

Добавляется в начало `_ready()` после resolve nodes:

```gdscript
# 019: load custom level if queued. Falls through to procedural paint when not.
if ActiveLevel.has_queued():
    var path: String = ActiveLevel.consume()
    var level: LevelData = LevelSerializer.load(path)
    if level == null:
        GameLogger.error("Godmode", "Failed to load %s — falling back to procedural" % path)
        # fall through to existing paint path
    else:
        grid.tile_map_layer.tile_set = load(level.tileset_path)
        if grid.vfx_overlay != null:
            grid.vfx_overlay.tile_set = grid.tile_map_layer.tile_set
        # Skip _paint_grid; LevelLoader does it. _place_player also handled there.
        grid.actor_step_started.connect(_on_step_started)
        grid.tile_map_layer.clear()
        for cell in level.floor_cells:
            grid.tile_map_layer.set_cell(cell.coord, cell.source_id, cell.atlas_coord)
        grid.initialize()
        LevelLoader.apply_to(grid, registry, level)
        # player ref now lives wherever LevelLoader put it; resolve it
        player = grid.get_node_or_null("Actors/Player") as Actor
        if player == null:
            GameLogger.error("Godmode", "Loaded level produced no player — fallback to default spawn")
            _place_player()
        # _seed_slots, EventBus connects, etc — same as before
        _seed_slots.call_deferred()
        ...
        return  # skip default paint+place
# existing path (no queued level)
grid.tile_map_layer.tile_set = GODMODE_TERRAIN
...
```

Тонкость: LevelLoader должен использовать тот же `PLAYER_SCENE`, что и godmode (`scenes/dev/player.tscn`), и тот же ActorRegistry. Контроллер передаёт `registry` в loader.

## Тестовый sample.json

`data/maps/sample.json` — минимальная играбельная карта для smoke:
- 8×6 пол (godmode_terrain.tres)
- 1 player spawner @ (1, 3)
- 2 manekin spawners @ (5, 2), (6, 4)
- 1 lava_pool @ (3, 3)
- 1 wooden_barrel @ (4, 5)

Грузится через main-menu → Load Custom Level → sample.json. Запускается бой, player ставится в (1,3), на хексе (3,3) лавалуж, etc.

## game_speed.cfg + section

```ini
[editor]
spawner_swap=0.2
place_feedback=0.05
hover_pulse=0.6
```

Не критичные значения — visual feedback timings. Ключи — для предсказуемости / hot-reload.

## Out-of-tasks notes

- **Не делаем undo.** Если время останется — рассмотрим как P3 follow-up.
- **Не делаем свой FileDialog**, используем встроенный Godot `FileDialog`. Стилизация через UiTheme (`apply_button_styling` где это возможно — Godot не всё даёт стилизовать, но базовое окно ОК).
- **Не делаем preview-thumbnail карт** в загрузочном диалоге. Файлдиалог — без превью. Future polish.
