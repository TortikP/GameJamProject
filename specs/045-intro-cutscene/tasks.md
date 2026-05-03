# 045-intro-cutscene — tasks

## Чеклист

- [ ] **T001** [P1] `config/game_speed.cfg` — поднять `cutscene_request_timeout_sec` до `15.0`
  (секция `[meta]`). Без этого CampaignController тушит flow через 0.5 сек до завершения кутсцена.
  _Файл:_ `config/game_speed.cfg`

- [ ] **T002** [P1] Создать `data/cutscenes/intro_awakening.json` — 2 слайда, суммарно ≤ 8 сек.
  Слайд 1: `image=""`, `text="Before the arena... there was silence."`, `duration=4.0`.
  Слайд 2: `image=""`, `text="Now it calls you."`, `duration=3.0`.
  _Файл:_ `data/cutscenes/intro_awakening.json`

- [ ] **T003** [P1] Создать `scenes/meta/cutscene_player.tscn` — `CanvasLayer(layer=30)` → `Control`
  (fullscreen, черный фон) → `TextureRect` (ImageRect) + `PanelContainer`/`Label` (TextBox/PanelText)
  + `Label` (SkipLabel top-right). `process_mode = PROCESS_MODE_ALWAYS` на корневом Control.
  Применить `UiTheme.apply_label_kind` в скрипте на PanelText и SkipLabel.
  _Файл:_ `scenes/meta/cutscene_player.tscn`

- [ ] **T004** [P1] Написать `scripts/presentation/meta/cutscene_player.gd`.
  - `class_name CutscenePlayer`, `extends Node`.
  - `_ready`: `EventBus.campaign_cutscene_requested.connect(_on_cutscene_requested)`.
  - `_on_cutscene_requested(cutscene_id, on_done)`: load JSON из `data/cutscenes/<id>.json`,
    warn+on_done если нет файла, иначе пауза + spawn overlay + `_play_panels`.
  - `_play_panels(panels, on_done)`: loop по слайдам, `_show_slide`, await duration/input.
  - `_show_slide(panel)`: set image (если есть), typewriter текст.
  - `_typewriter(label, text)`: символ за символом, `process_mode=ALWAYS` таймеры.
  - `_skip_or_advance()` через `_unhandled_input`: force-complete typewriter или advance/skip_all.
  - Завершение: free overlay, `get_tree().paused = false`, `on_done.call()`.
  _Файл:_ `scripts/presentation/meta/cutscene_player.gd`

- [ ] **T005** [P1] Зарегистрировать autoload `CutscenePlayer` в `project.godot`
  после `CampaignController`.
  _Файл:_ `project.godot`

- [ ] **T006** [P1] Smoke-тест: Load Game `data/games/sample.game.json` → Start →
  кутсцен `intro_awakening` показывается → auto-advance 7 сек → `on_done` → уровень стартует.
  Проверить что `get_tree().paused` снимается корректно.

- [ ] **T007** [P2] Smoke-тест skip: то же что T006, но нажать Space/Click на первом слайде →
  кутсцен закрывается мгновенно → уровень стартует.

- [ ] **T008** [P2] Smoke-тест без ActiveGame: Godmode → уровень грузится → `CutscenePlayer`
  молчит (signal не эмитился CampaignController без активной игры).

- [ ] **T009** [P2] Добавить запись в таблицу `CLAUDE.md` «Currently claimed»:
  `| 045-intro-cutscene (CutscenePlayer autoload, data/cutscenes/) | Andrey |`
  _Файл:_ `CLAUDE.md`

- [ ] **T010** [P3] Добавить секцию 21 в `HANDOFF.md`:
  `CutscenePlayer autoload — слушает campaign_cutscene_requested, грузит data/cutscenes/<id>.json,
  слайд-шоу ≤ 10 сек, on_done по skip или last slide. Таймаут в GameSpeed
  meta/cutscene_request_timeout_sec=15.0.`
  _Файл:_ `HANDOFF.md`

## Зависимости

T003 → T004 → T005 (в этом порядке, остальное параллельно)
T001 критично делать до smoke-теста T006.
