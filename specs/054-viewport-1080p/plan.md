# 054 — Plan: Viewport 1280×720 → 1920×1080

Спек: [`spec.md`](./spec.md). Все Q-054-1..4 резолвлены.

## Что дальше (TL;DR)

Три точечные правки:
1. `project.godot` — viewport_width/height bump.
2. `scenes/dev/map_editor.tscn` — убрать hardcoded position у HexGrid.
3. `scripts/presentation/dev/map_editor_controller.gd` — добавить `grid.position = viewport_rect * 0.5` в `_ready`.

Остальное — manual smoke в Godot (T004–T009 в [`tasks.md`](./tasks.md)).

## Архитектурное обоснование

- **Stretch mode остаётся `"viewport"`.** Godot рендерит сцену в логический canvas заданного размера и масштабирует на физическое окно. Меняем только размер canvas, режим масштабирования не трогаем — это сохраняет привычные координаты во всём UI/scene-коде, просто 16:9 пространство становится больше.
- **Anchored UI адаптируется автоматом.** `top_hud_bar`, `dialogue_panel`, `game_editor` (3-pane), `score_corner`, `combat_log`, `toast_layer` — все используют `anchor_right=1.0` / `anchor_bottom=1.0` с фиксированными offset'ами от краёв. После переезда anchor=1.0 продолжает означать «правый край viewport», просто это теперь 1920 а не 1280. Layout сохраняется визуально: панель с offset=-376 от правого края остаётся 376px шириной, прижатая к правому краю.
- **Sidebar'ы остаются той же физической ширины.** Это допустимо для editor'ов: sidebar шириной 376px на 1080p = 19.5% canvas (vs 29.4% на 720p) — меньше «давит» на центральный canvas. Ничего не ломается, читать содержимое не мешает.
- **Hardcoded `(640, 360)` уезжает на динамику.** Это единственный найденный hardcoded центр-720p в коде/сценах (см. F sweep в спеке). После Q-054-3.B он становится `viewport.size * 0.5`, и любое последующее изменение разрешения уже не потребует механической правки. Defensive default.

## Структура изменений

### Code & config

**1. `project.godot` — `[display]` блок.**

```ini
# до
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="viewport"

# после
window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="viewport"
```

Не добавляем `window_width_override` / `window_height_override` (Q-054-1.A: окно стартует size=viewport).
Не трогаем `stretch/aspect` (Q-054-2: остаётся неявно `"keep"`).

**2. `scenes/dev/map_editor.tscn:54` — HexGrid position.**

```
# до
[node name="HexGrid" parent="." instance=ExtResource("2_hexgrid")]
position = Vector2(640, 360)

# после
[node name="HexGrid" parent="." instance=ExtResource("2_hexgrid")]
```

(Просто удалить строку с `position`. По умолчанию Node2D position = Vector2.ZERO — потом перезаписывается контроллером.)

**3. `scripts/presentation/dev/map_editor_controller.gd._ready()`** — вставить ДО строки `grid.tile_map_layer.tile_set = HEX_TERRAIN` (сейчас line 156, после resolve и before initial canvas paint):

```gdscript
# Q-054-3 (spec 054): HexGrid position was hardcoded Vector2(640, 360) in
# map_editor.tscn -- the centre of the legacy 1280x720 viewport. Resolution
# bump moved the centre to (960, 540); anchor it to viewport size at runtime
# so future resolution changes don't drift the editor origin.
grid.position = get_viewport_rect().size * 0.5
```

Безопасность: вызывается до `grid.initialize()`. Position у Node2D — pure transform, не влияет на initialize logic. Camera затем встаёт на `tile_map_layer.map_to_local(Vector2i.ZERO)` = local (0,0) в hex_grid local space, что в world coords = `grid.position + (0,0)` = центр viewport. Поведение для пользователя идентично текущему (камера на hex (0,0) в центре экрана), но не привязано к 720p.

### Что НЕ трогаем

- Anchored UI scenes (game_editor, top_hud_bar, dialogue_panel, hex_tooltip, и т.д.) — anchors сделают работу.
- Sidebar widths (`offset_right = -376` и аналогичные) — оставляем, retune за scope.
- `UiTheme.FS_*` / `BAR_*_OVERHEAD` — оставляем (Q-054-2 контекста: текст станет визуально мельче, ОК).
- Camera2D zoom values в .tscn'ках — `godmode.tscn` `1.6`, `map_editor.tscn` `0.5` — оставляем (Q-054-4).
- FileDialog sizes 720×480 — F-054-1 в спеке, отдельный коммит.

## Risks & mitigations

- **R1.** Скрытый Camera2D / Control с hardcoded coords за пределами найденных трёх patterns (`Vector2(640|1280|720|...)`).
  Mitigation: T008 (visual review pass всех editor + runtime сцен из main_menu graph). Если что-то всплывёт — точечный фикс в этой же ветке.

- **R2.** GPU rendering load 1920×1080 vs 1280×720 (~2.25× больше пикселей).
  Mitigation: у всей команды Full HD моники → железо адекватное (Q-054-1). Если на чьей-то машине FPS просядет — понизить scaling в render settings, не отменять переезд.

- **R3.** FileDialog'и (F-054-1) станут визуально маленькими.
  Mitigation: не блокер AC; surface как finding, fix отдельным коммитом если раздражает.

## Smoke plan

См. [`tasks.md`](./tasks.md) T004–T009.
