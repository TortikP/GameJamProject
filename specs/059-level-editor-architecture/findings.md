# 059 — Findings (impl-time)

Surfacing для ревью.

## F-059-IMPL-1 — InputDispatcher использовал `coord_under_mouse()` вместо `coord_under_mouse_raw()`

**Симптом:** При тестировании сцены LMB-клики по пустому пространству (вне любых нарисованных тайлов) не давали никакого результата. На сетке без single тайла редактор был полностью неработоспособен — невозможно начать рисовать.

**Корневая причина:** `HexGrid.coord_under_mouse()` (line 355 в `hex_grid.gd`) проверяет `_tiles.has(coord)` и возвращает `Vector2i(-1, -1)` если тайла под курсором ещё нет. Это runtime-метод для геймплея (например, чтобы actor не мог двинуться на несуществующую клетку). На пустом editor-канвасе он всегда возвращает sentinel.

Старый `MapEditorController` для editor-режима использует `coord_under_mouse_raw()` (line 372) — без проверки registry, hard-cap'ом на ±250 hex-coord для безопасности. Я в InputDispatcher выбрал не тот метод, не сверился со старой имплементацией.

**Fix:** В `input_dispatcher.gd` 3 вызова `coord_under_mouse()` → `coord_under_mouse_raw()`. Плюс добавлен guard в `_act_at(coord, ...)` против sentinel `Vector2i(-1, -1)` — на случай курсора over HUD canvas layer или beyond MAP_HALF_LIMIT.

**Lessons learned:** 
- В spec/plan надо было явно указать «paint-anywhere mode → use coord_under_mouse_raw». Сейчас в plan.md §Step 4 написано просто `_grid.coord_under_mouse()` без объяснения какой метод выбран и почему.
- При имплементации второго потребителя API стоило прочитать как использует первый. Я этого не сделал.
- R3 в plan.md упоминал «coord_under_mouse за пределами сетки может вернуть невалидный Vector2i» — но фокус был не туда. Реальный риск был «на пустой сетке вообще ничего не painting'уется».

## F-059-IMPL-2 — HoverHighlight добавлен в 059 (ранее был non-goal)

**Контекст:** spec.md §4 явно объявляет «no HoverHighlight» в скоупе 059. После того как F-059-IMPL-1 был зафикшен и редактор стал технически работать, обнаружилось что без visual indicator юзабельность нулевая: невидимые гексы рендерятся при кликах, но пользователь не видит куда курсор показывает на пустой сетке.

**Что сделано:** Добавлен existing `scripts/presentation/dev/hover_highlight.gd` (44 строки, был написан давно для map_editor) как Node2D-child HexGrid в `level_editor.tscn`. Никаких правок в EditorController — HoverHighlight self-attaches к parent HexGrid в собственном `_ready()`. Это +2 строки в .tscn (+1 ext_resource +1 node) — минимальное расширение скоупа.

**Почему scope creep оправдан:** AC4-AC8 (paint, erase, drag) формально проходят без HoverHighlight (если знать что метод правильный — F-059-IMPL-1), но **проверить smoke вручную невозможно** — не на что смотреть. Это был fundamental misjudgement в spec'е (моё), а не legitimate non-goal. Стоимость добавления — 2 строки в .tscn.

**Что НЕ сделано:** Связанный `DeleteHighlight` (показывает красную обводку на гексе под RMB-курсором при Erase mode) — оставлен на 060. AC5/AC7 проходят без него, есть Erase highlight через ButtonGroup в палитре.

## F-059-IMPL-3 — Все 4 loc-key пришлось добавить заново (план переоценил переиспользование)

Plan.md §Step 8 упоминал что `ui_level_meta_panel_title` может уже существовать. По факту в проекте были `ui_level_meta_title`, `ui_level_meta_name_label`, `ui_level_meta_playtest`, `ui_level_meta_untitled` — но не `_panel_title`. Все 4 ключа нужно было добавлять как новые, что и сделано.

Не блокер — мелкая переоценка в плане, surfaceю для будущих спеков чтобы не опираться на «может быть уже есть».
