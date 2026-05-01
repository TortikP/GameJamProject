# 005-camera-and-arena — plan

См. `spec.md` (что/зачем). Здесь — как.

## 1. Архитектура и слои

```
scripts/presentation/godmode/
  godmode_camera.gd          # extends Camera2D. Зум колесом, clamp, lerp, zoom-к-курсору.

scenes/dev/
  godmode.tscn               # добавить Camera2D с этим скриптом, current=true.

config/
  game_speed.cfg             # добавить ключи в [godmode].

scripts/presentation/godmode/
  godmode_controller.gd      # GRID_W=14, GRID_H=9. Без других изменений.
```

Зависимости:
- `godmode_camera.gd` зависит только от `GameSpeed` autoload и Godot Camera2D API. Ничего в `core/` не трогается.
- `godmode_controller.gd` — единственное изменение: две константы.

## 2. Camera2D config в сцене

```
[node name="GodmodeCamera" type="Camera2D" parent="."]
script = ExtResource("godmode_camera.gd")
current = true
enabled = true
position_smoothing_enabled = false
zoom = Vector2(1, 1)
```

Position камеры — на старте (0,0) в координатах Godmode Node2D. Игрок спавнится по `grid.tile_map_layer.map_to_local(Vector2i(7,4))` + offset HexGrid (`position = (160, 90)` в сцене). Камера в `_ready` берёт стартовую позицию игрока и ставит туда себя один раз. Никакого автоследования (это OOS).

## 3. godmode_camera.gd — реализация

```gdscript
extends Camera2D

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

var _zoom_target: Vector2 = Vector2.ONE
var _zoom_tween: Tween

func _ready() -> void:
    _zoom_target = zoom
    # Стартовое позиционирование на игрока: deferred, ждём пока player встанет.
    _center_on_player.call_deferred()

func _center_on_player() -> void:
    var player := get_tree().root.find_child("Player", true, false) as Node2D
    if player != null:
        global_position = player.global_position

func _unhandled_input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton):
        return
    var mb := event as InputEventMouseButton
    if not mb.pressed:
        return
    var step := GameSpeed.get_value("godmode", "zoom_step", 0.1)
    var zoom_min := GameSpeed.get_value("godmode", "zoom_min", 0.5)
    var zoom_max := GameSpeed.get_value("godmode", "zoom_max", 3.0)
    if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
        _apply_zoom(_zoom_target.x + step, mb.position, zoom_min, zoom_max)
        get_viewport().set_input_as_handled()
    elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
        _apply_zoom(_zoom_target.x - step, mb.position, zoom_min, zoom_max)
        get_viewport().set_input_as_handled()

func _apply_zoom(new_z: float, mouse_screen: Vector2, zmin: float, zmax: float) -> void:
    new_z = clampf(new_z, zmin, zmax)
    if is_equal_approx(new_z, _zoom_target.x):
        return
    # Zoom-к-курсору: точка под курсором должна остаться на месте.
    # Camera2D.zoom > 1 = увеличение. Перевод: world_pos под курсором не меняется.
    var mouse_world_before := get_global_mouse_position()
    _zoom_target = Vector2(new_z, new_z)
    if _zoom_tween != null and _zoom_tween.is_valid():
        _zoom_tween.kill()
    var dur := GameSpeed.get_value("godmode", "zoom_lerp_duration", 0.12)
    _zoom_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    _zoom_tween.tween_property(self, "zoom", _zoom_target, dur)
    # Сдвиг камеры — синхронно с зумом, чтобы курсор-якорь работал.
    # Точная формула после tween: camera.position += (mouse_world_before - mouse_world_after).
    # Пока tween в процессе, get_global_mouse_position обновляется автоматически
    # каждый кадр в Camera2D — но проще зафиксировать сдвиг разом, иначе будет
    # «дребезг». Поэтому:
    #   delta = mouse_world_before - mouse_world_after_at_target_zoom
    # Где mouse_world_after_at_target_zoom = global_position + (mouse_screen - vp_center) / new_z
    var vp_size := get_viewport_rect().size
    var vp_center := vp_size * 0.5
    var mouse_world_after := global_position + (mouse_screen - vp_center) / new_z
    var delta := mouse_world_before - mouse_world_after
    _zoom_tween.parallel().tween_property(self, "position", position + delta, dur)
```

Заметка по zoom-к-курсору: формула рассчитана на дефолтный `anchor_mode = ANCHOR_MODE_DRAG_CENTER` и без вращения камеры. Если позже `rotation != 0` или `anchor_mode` сменится — пересмотреть. На текущей сцене это безопасно.

## 4. game_speed.cfg — новые ключи

Добавить в существующую секцию `[godmode]`:

```ini
[godmode]
ability_cast_delay=0.05
zoom_step=0.1
zoom_min=0.5
zoom_max=3.0
zoom_lerp_duration=0.12
```

Все 4 ключа — float, читаются на каждое тиканье колеса (без кэширования) → F5 hot-reload работает автоматически.

## 5. godmode_controller.gd — изменения

```gdscript
const GRID_W := 14   # было 8
const GRID_H := 9    # было 5
```

`_place_player()` уже использует `Vector2i(GRID_W / 2, GRID_H / 2)` → автоматически (7, 4). Ничего больше менять не нужно.

## 6. Тестирование

Manual smoke (см. spec.md "Acceptance verification"). Нет unit-тестов — это presentation-полировка, проверяется глазами.

## 7. Риски и заметки

- **Zoom-к-курсору формула** — самое хрупкое место. Если на ревью «угол съезжает на 1-2 пикселя» — это субпиксельная погрешность интеграции tween, не баг логики. Если съезжает заметно — возможно `Camera2D.anchor_mode` не дефолтный, или `Camera2D` не direct child Node2D с identity-трансформацией. Проверить иерархию.
- **Виртуальный размер viewport.** Если в `project.godot` стоит `stretch_mode = canvas_items` или есть HiDPI-режим — `mb.position` может быть в логических пикселях, а `get_viewport_rect()` в физических. Тестить на актуальном `project.godot`. Если расходится — использовать `get_canvas_transform().affine_inverse() * mb.position` вместо ручного пересчёта.
- **HexCursor** (`scripts/presentation/hex_cursor.gd`) использует `grid.coord_under_mouse()`, который под капотом делает `tile_map_layer.local_to_map(tile_map_layer.get_local_mouse_position())`. Это viewport-aware, под капотом учитывает камеру. Тестить — но менять там ничего не должно понадобиться.

## 8. Что НЕ делаем (явно)

- Не трогаем `arena_demo_controller.gd`. У него своя камера-логика (или её отсутствие) — не наша забота на этом PR.
- Не выносим `godmode_camera.gd` в `presentation/common/` или ещё куда «для переиспользования». Если завтра нужен зум в другой сцене — скопировать или вынести **тогда**, не сейчас. (CLAUDE.md don'ts: «no abstractions for the future».)

## 9. Ссылки на Godot docs

- [Camera2D class](https://docs.godotengine.org/en/4.6/classes/class_camera2d.html)
- [InputEventMouseButton](https://docs.godotengine.org/en/4.6/classes/class_inputeventmousebutton.html)
- [Tween](https://docs.godotengine.org/en/4.6/classes/class_tween.html)
