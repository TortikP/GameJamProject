# 054 — Viewport 1280×720 → 1920×1080

**Обсуждали:** Andrey (идея)
**Статус:** ready (open questions резолвлены, идём в plan + tasks)

## Что дальше

1. ✅ Спек одобрен Andrey, open questions резолвлены.
2. Plan + tasks (этот же коммит).
3. Имплементация (отдельная команда).

## Resolved decisions

- **Q-054-1 → A → revised B (after smoke).** Изначально решили без override (окно 1920×1080 = весь монитор). На первом смоке выяснилось: при viewport == native монитор не остаётся места под Godot editor / console во время теста. Изменено на `window_width_override=1600`, `window_height_override=900`. Plus F11 toggle на native fullscreen для crispness checks (см. Q-054-5).
- **Q-054-2 → отложено.** `stretch/aspect` остаётся неявно `"keep"`. Отдельным спеком после того как 1080p устаканится.
- **Q-054-3 → B.** Убираем `position` у HexGrid в `map_editor.tscn`, центрирование через `viewport.size * 0.5` в `_ready` контроллера.
- **Q-054-4 → как есть.** `zoom = Vector2(1.6, 1.6)` в `godmode.tscn` остаётся. После смока Andrey решает корректировать или нет — отдельным точечным коммитом, не блокер AC.
- **Q-054-5 (новое, post-smoke) → F11 toggle через autoload.** Добавлен `WindowMode` autoload + input action `toggle_fullscreen`. F11 переключает между windowed (override 1600×900) и `WINDOW_MODE_FULLSCREEN` (borderless windowed fullscreen, native res). Borderless > exclusive — alt-tab мгновенный, нет переключения display mode.

## Проблема

Текущий `[display]` блок в `project.godot`:

```
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="viewport"
```

`viewport` stretch — Godot рендерит сцену в логический 1280×720 буфер и масштабирует на реальное окно. Для пользователя на 1080p мониторе:

- Картинка апскейлится 720p → 1080p → визуально мыло, особенно на тексте.
- Координатное пространство сцен живёт в 1280×720, любые «center of screen» хардкоды привязаны к 640×360 (нашёлся один — см. Q-054-3).
- Editor sidebar'ы (`offset_right = -376` в `map_editor.tscn`) уже сейчас занимают заметную долю canvas — на 1080p станет посвободнее.

Цель: рендерить нативно в 1920×1080 без апскейла, координатное пространство расширяется пропорционально.

## Цель

1. **Поднять виртуальный canvas до 1920×1080.** `window/size/viewport_*` в `project.godot`.
2. **Не реверстать UI в этом же спеке.** Anchored UI (game_editor, top_hud_bar, dialogue_panel и пр.) адаптируется автоматом. Фрагменты с фиксированной шириной (sidebar'ы редакторов, toast layer, score corner) остаются того же физического размера в пикселях — визуально станут уже относительно нового canvas. Если что-то выглядит странно — собираем список, чиним отдельным спеком после визуального ревью.
3. **Не бампить `FS_*` / `BAR_*_OVERHEAD` константы в UiTheme.** Текст станет визуально мельче на 1080p — приемлемо. Если конкретный лейбл станет нечитаем — поднимаем точечно отдельным PR через UiTheme.
4. **Починить точечные хардкоды**, которые ломаются при переезде. Найден один: `Vector2(640, 360)` в `map_editor.tscn` (см. Q-054-3).

## Acceptance criteria

- **AC1.** `project.godot`: `viewport_width=1920`, `viewport_height=1080`. `stretch/mode="viewport"` остаётся. `window_*_override` = 1600×900 (Q-054-1.B revised).
- **AC2.** Запуск игры: окно открывается windowed 1600×900 (на 1080p мониторе остаётся «воздух» под IDE/console). Главное меню рендерится без обрезки/сдвига. Картинка чуть downscale'ится (1920→1600 = 0.83×) — приемлемо для dev.
- **AC3.** Все три editor-сцены (`map_editor.tscn`, `game_editor.tscn`, `godmode.tscn` в standalone playtest) — открываются, sidebar'ы видимы, центральный canvas не перекрыт. Никаких overlapping панелей по сравнению со staging.
- **AC4.** Прохождение story_campaign до первого диалога: cutscene → диалог → шаг героини → transition. Никаких визуальных артефактов: dialogue panel не обрезается, hex tooltip не уезжает за экран, top_hud_bar / score_corner / combat_log на своих местах.
- **AC5.** Map editor: при открытии HexGrid центрирован относительно нового viewport (фикс по Q-054-3). Pan/zoom работают.
- **AC6.** Никаких новых runtime warn'ов в консоли при стандартных smoke-сценариях (запуск, главное меню, godmode F1, editor open, начало story_campaign).
- **AC7.** На laptop с экраном меньше 1920×1080 — игра запускается без краша. (Не актуально по Q-054-1: у всех Full HD, оставлено для записи.)
- **AC8 (Q-054-5).** F11 в любой сцене переключает между windowed (1600×900) и borderless fullscreen (native 1920×1080). На fullscreen pixel art crisp 1:1, alt-tab возвращает мгновенно. Работает в том числе на pause.

## Out of scope

- Реверстать UI panels под широкий 1080p canvas (sidebar'ы, padding, layout). Делается отдельным спеком после визуального ревью результата.
- Бампить `UiTheme.FS_*` / `BAR_*_OVERHEAD`. Если конкретный лейбл стал нечитаем — точечный PR через UiTheme, не в этом спеке.
- Менять `stretch/aspect` (default `"keep"` → `"expand"`). См. Q-054-2.
- Менять `window_mode` (windowed / borderless / fullscreen) или добавлять in-game options screen для разрешения.
- Sprite/asset re-export. Все спрайты остаются те же, рендерятся в нативных пикселях.
- Готовить под Steam launch (Mark): аспекты разрешения для Steam (settings menu, launch options, fullscreen toggle) — отдельная задача после того, как 1080p устаканится.

## Findings (для других)

- **F-054-1** (Andrey/Stasyan): три FileDialog'а имеют hardcoded `size = Vector2i(720, 480)` — `level_meta_panel.gd:117`, `main_menu.tscn:96` (LoadFileDialog), `main_menu.tscn:103` (LoadGameFileDialog). На 720p заполняли почти весь экран, на 1080p станут визуально маленькими (~37% × 44% от screen). Не критично, но заметно по UX. Можно поднять до Vector2i(960, 640) — отдельный точечный коммит, не в этом спеке.
