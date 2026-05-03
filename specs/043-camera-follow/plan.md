# 043-camera-follow — plan

## Файлы

| Файл | Действие |
|---|---|
| `scripts/presentation/godmode/godmode_camera.gd` | edit — `_process` follow-loop + gate MMB и zoom-shift |
| `scenes/dev/godmode.tscn` | edit — `position_smoothing_enabled = true` на GodmodeCamera |

## Изменения в godmode_camera.gd

### 1. Хелпер `_is_following()`

```gdscript
func _is_following() -> bool:
    return _follow_target != null and is_instance_valid(_follow_target)
```

Используется во всех trёx ниже точках. Один источник истины,
без рассинхронов.

### 2. `_process(delta)` — новый

```gdscript
func _process(_delta: float) -> void:
    if _is_following():
        global_position = _follow_target.global_position
```

Snap к позиции target'а каждый кадр. `position_smoothing_enabled = true`
в .tscn — Camera2D сам интерполирует отрисовку. Telepor-эффекта нет.

### 3. Гард в MMB-блоке `_unhandled_input`

```gdscript
if event is InputEventMouseButton:
    var mb := event as InputEventMouseButton
    if mb.button_index == MOUSE_BUTTON_MIDDLE:
        if _is_following():
            return                           # ← новый ранний выход
        _panning = mb.pressed
        ...
```

Возврат **до** установки `_panning`. Drag не запускается.

Также проверка для `InputEventMouseMotion and _panning`: уже корректна
(если `_panning = false`, событие проходит мимо). Дополнительный гард
не нужен.

### 4. `_apply_zoom` — параллельный tween position

Существующий код:
```gdscript
var delta: Vector2 = mouse_world_before - mouse_world_after
_zoom_tween.parallel().tween_property(self, "position", position + delta, dur)
```

Новый:
```gdscript
if not _is_following():
    var delta: Vector2 = mouse_world_before - mouse_world_after
    _zoom_tween.parallel().tween_property(self, "position", position + delta, dur)
```

В follow-mode position-tween пропускается: `_process` всё равно перезапишет.

### 5. `_center_on_target` — без изменений

Метод вызывается из `_ready` и `set_follow_target`. В follow-mode он избыточен
(`_process` сам отработает на следующем кадре), но не вреден. Оставляем —
не лезем в touch-budget без причины.

## Изменение godmode.tscn

Один атрибут на ноде GodmodeCamera (между `enabled` и `zoom`):

```
position_smoothing_enabled = true
```

`position_smoothing_speed` не задаём — дефолт Godot (5.0) подходит для
шага гекса (~120 px) при `step_duration = 0.18 sec` (см. game_speed.cfg
[arena]).

## map_editor.tscn — не трогаем

Камера там уже имеет `position_smoothing_enabled = true` (в исходнике),
`set_follow_target` никогда не вызывается → `_follow_target == null` →
`_is_following() == false` → MMB-drag и zoom-to-cursor работают как раньше.

## Точки вызова `set_follow_target` (для контекста, не правим)

- `scripts/presentation/godmode/godmode_setup.gd:262-264` —
  при `_place_player` (старт godmode-сцены).
- `scripts/presentation/godmode/godmode_setup.gd:240-242` —
  при load custom level.

Обе точки уже работают, follow-mode включится автоматом.
