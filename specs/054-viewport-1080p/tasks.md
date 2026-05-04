# 054 — Tasks

Спек: [`spec.md`](./spec.md). Plan: [`plan.md`](./plan.md).

## Code (Claude в impl-команде)

- [ ] **T001.** `project.godot` `[display]` блок: `viewport_width` 1280 → 1920, `viewport_height` 720 → 1080. `stretch/mode="viewport"` оставить. Никаких новых `window_*_override`. (AC1)
- [ ] **T002.** `scenes/dev/map_editor.tscn:54` — удалить строку `position = Vector2(640, 360)` у HexGrid node. Сохранить остальное в node block без изменений.
- [ ] **T003.** `scripts/presentation/dev/map_editor_controller.gd._ready()` — после resolve блока (после `_dialogue_trigger_panel = _resolve(...)` на line 148, перед `grid.tile_map_layer.tile_set = HEX_TERRAIN` на line 156) добавить:

  ```gdscript
  # Q-054-3 (spec 054): HexGrid position was hardcoded Vector2(640, 360) in
  # map_editor.tscn — the centre of the legacy 1280×720 viewport. Resolution
  # bump moved the centre to (960, 540); anchor it to viewport size at runtime
  # so future resolution changes don't drift the editor origin.
  grid.position = get_viewport_rect().size * 0.5
  ```

  Проверить что `_ready` вызывается ДО `grid.initialize()` (line 164) и до camera.position установки (line 180) — да, вставка идёт между resolve и initialize.

## Smoke (Andrey, manual в Godot после impl)

- [ ] **T004 (AC2).** Запуск из `scenes/main_menu.tscn`. Окно открывается windowed на 1920×1080. Главное меню рендерится без обрезки и сдвига. Кнопки на местах (по центру). Console clean — никаких новых warn/error.
- [ ] **T005 (AC3).** Все три editor-сцены, по одной:
  - Main menu → Map Editor (`scenes/dev/map_editor.tscn`): открывается, sidebar справа (~376px) виден, tool panel слева виден, центральный canvas не перекрыт.
  - Main menu → Game Editor (`scenes/dev/game_editor.tscn`): 3-pane layout не overlapping, autosave restore modal (если есть) на месте.
  - Main menu → Godmode standalone (если запускается из меню) или прямой run сцены `scenes/dev/godmode.tscn`: F1 spawn маникена → обычный flow.
- [ ] **T006 (AC4).** Main menu → "Начать забег" (story_campaign): cutscene → диалог → шаг героини на юг → transition shader → story_map_01 с HUD.
  Визуальная проверка по пути:
  - dialogue panel целиком в кадре, текст не обрезан;
  - hex tooltip (если показывается) не уезжает за viewport;
  - top_hud_bar / score_corner / combat_log на своих углах, не overlapping.
- [ ] **T007 (AC5).** Map Editor: новый holst при первом открытии. HexGrid визуально центрирован относительно viewport (приблизительно центр свободной зоны canvas; небольшой шифт вправо из-за sidebar — допустим, это сохранение текущего поведения). Pan камерой (MMB drag), zoom (wheel) — работают.
- [ ] **T008 (AC6 + R1).** Visual review pass — пройтись по основным сценам и собрать список «что выглядит криво на 1080p». Категории для записи:
  - sidebar'ы стали узкими / непропорциональными → если да: какой именно;
  - padding между элементами странный → где;
  - текст где-то нечитаем (UiTheme constant остался 720p-tuned) → какой label;
  - камера показывает «слишком много / слишком мало» → в какой сцене.
  Если ничего критичного — записать «список пуст, переезд чистый». Этот список — input для следующего спека «UI re-tune for 1080p» (если понадобится).
- [ ] **T009.** Regression sanity (никаких core gameplay регрессий):
  - Mob spawn (godmode F1) → они движутся, кастуют, дамаг считается;
  - Wave end → upgrade screen открывается;
  - Dialogue trigger в level → диалог играется;
  - F5 reload `game_speed.cfg` → не падает.
  Если что-то регрессило — баг, чинится в этой же ветке отдельным коммитом.

## Acceptance gate

Все T001–T003 закоммичены, T004–T009 пройдены без блокирующих регрессий → ветка готова к PR в staging.
