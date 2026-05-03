# 045-intro-cutscene — tasks

## Чеклист

### Контент

- [ ] **T001** [P1] `data/maps/office_intro.json` — карта ~5×5 хексов, биом «office»
  (slot 7 атласа, `tile_kind=ice`). Декор: 1× `object_on_chair` (центр, спавн
  игрока на этом хексе), 1× `object_computer` рядом, 1× `object_cooler` сбоку.
  `waves: []`, `dialogue_triggers: []`. Player spawn → координата стула.
  _Файл:_ `data/maps/office_intro.json`

- [ ] **T002** [P1] `data/cutscenes/intro_office.json` — конфиг 2-кадра по
  схеме из plan.md.
  _Файл:_ `data/cutscenes/intro_office.json`

- [ ] **T003** [P1] `data/dialogues/intro_office_monologue.json` — placeholder:
  2–3 реплики игрока «офисный понедельник, мир вокруг кажется фарсом, надо
  что-то делать». Никита перепишет.
  _Файл:_ `data/dialogues/intro_office_monologue.json`

- [ ] **T004** [P1] `data/games/story_campaign.game.json` — prepend office_intro
  entry первым уровнем (`is_intro=true`, `cutscene_id="intro_office"`).
  Снять `is_intro` и `cutscene_id` со story_map_01.
  _Файл:_ `data/games/story_campaign.game.json`

### CutscenePlayer

- [ ] **T005** [P1] `scenes/meta/cutscene_player.tscn` — `CanvasLayer(layer=30)`
  → `Control` (fullscreen, чёрный ColorRect фон) → 2× `TextureRect` (Frame1, Frame2)
  c `expand_mode=1, stretch_mode=5, pivot_offset` в центре + `Label` (SkipLabel
  верх-правый угол). `process_mode = ALWAYS` на корневом Control.
  _Файл:_ `scenes/meta/cutscene_player.tscn`

- [ ] **T006** [P1] `scripts/presentation/meta/cutscene_player.gd` — `class_name
  CutscenePlayer extends Node`. Сигнал `cutscene_finished(id)`. `_ready` коннект
  `EventBus.campaign_cutscene_requested`. `_on_cutscene_requested(id, on_done)`:
  load JSON, paused=true, spawn overlay, `_play_frames`, free, paused=false,
  on_done.call(), emit `cutscene_finished`.
  - `_play_frames(overlay, frames)`: для каждого кадра — set texture, scale tween
    (`scale_from`→`scale_to` за `duration`), параллельно alpha-tween для cross-fade.
    Skip-флаг прерывает все tweens, сразу advance.
  - `_unhandled_input` (внутри overlay'а) — на ui_accept/MouseButton.pressed
    устанавливает skip-флаг.
  _Файл:_ `scripts/presentation/meta/cutscene_player.gd`

- [ ] **T007** [P1] Зарегистрировать autoload `CutscenePlayer` в `project.godot`
  — *после* `CampaignController` (порядок важен: cutscene-coupling).
  _Файл:_ `project.godot`

- [ ] **T008** [P1] `config/game_speed.cfg` — `[meta]` секция, поднять
  `cutscene_request_timeout_sec` до `4.0`.
  _Файл:_ `config/game_speed.cfg`

### IntroDirector

- [ ] **T009** [P1] `scripts/runtime/intro_director.gd` — `class_name IntroDirector
  extends Node`. `_ready` коннект `EventBus.scene_ready`. `_on_scene_ready`
  фильтрует godmode + active_game + is_intro, запускает `_run_sequence` через
  `call_deferred`. `_run_sequence` async sequence по plan.md:
    1. await `CutscenePlayer.cutscene_finished` (с 5s таймаутом-race через
       `create_timer` чтобы не зависнуть)
    2. `DialogueManager.play_dialogue(...)` + await `EventBus.dialogue_finished`
    3. find grid + player → `grid.move_actor(player.id, south_coord)` +
       await `EventBus.actor_moved` с таймаутом
    4. `await timer(0.3)`
    5. `EventBus.level_completed.emit(0)`
  _Файл:_ `scripts/runtime/intro_director.gd`

- [ ] **T010** [P1] Зарегистрировать autoload `IntroDirector` в `project.godot`
  — *после* `CutscenePlayer` и `CampaignController`.
  _Файл:_ `project.godot`

### Locks (HUD/zoom/input)

- [ ] **T011** [P1] `scripts/presentation/godmode/godmode_setup.gd` — после
  resolve'а HUD-нода, добавить:
  ```gdscript
  if ActiveGame.has_active_game() and ActiveGame.current_is_intro():
      hud.visible = false
  ```
  Точное место — рядом со сборкой ссылок на UI-узлы. Восстанавливать не нужно.
  _Файл:_ `scripts/presentation/godmode/godmode_setup.gd`

- [ ] **T012** [P1] `scripts/presentation/godmode/godmode_camera.gd._unhandled_input`
  — first-line guard:
  ```gdscript
  if ActiveGame.has_active_game() and ActiveGame.current_is_intro():
      return
  ```
  _Файл:_ `scripts/presentation/godmode/godmode_camera.gd`

- [ ] **T013** [P1] `scripts/presentation/godmode/godmode_input.gd._unhandled_input`
  — после существующего `is_alive` guard:
  ```gdscript
  if ActiveGame.current_is_intro():
      # ESC всё ещё нужен (pause menu) — пускаем только его
      if event is InputEventKey and (event as InputEventKey).pressed and \
         (event as InputEventKey).keycode == KEY_ESCAPE:
          return  # дать ESC handler'у сработать через стандартный chain
      get_viewport().set_input_as_handled()
      return
  ```
  _Файл:_ `scripts/presentation/godmode/godmode_input.gd`

### Smoke-тесты

- [ ] **T014** [P1] **Happy path.** Main menu → "Начать забег" → office_intro
  загружается → cutscene-art (cutscene_2 → cutscene_1, scale + cross-fade,
  ≤3s) → диалог → шаг на юг с центровкой камеры → transition shader →
  story_map_01 загружается с HUD виден, зум работает, игрок управляется.

- [ ] **T015** [P1] **Skip path.** Тот же flow, но Space на cutscene-art →
  немедленный переход к диалогу. Затем Space по диалогу → шаг → transition.

- [ ] **T016** [P2] **Godmode regression.** Главное меню → Godmode →
  intro НЕ играется (нет ActiveGame), HUD виден, всё как было.

- [ ] **T017** [P2] **Load Custom Level regression.** Аналогично T016 для
  Load Custom Level.

- [ ] **T018** [P2] **Load Game (story_campaign.game.json).** Через Load Game
  intro проигрывается так же, как через "Начать забег".

- [ ] **T019** [P2] **Pause во время cutscene-art.** ESC во время overlay'а
  открывает pause menu. Resume → cutscene продолжается с того же места.
  *Если ломается* — просто заблокировать ESC во время cutscene'а через
  early-return в `_unhandled_input` overlay'а (acceptable cut).

- [ ] **T020** [P2] **Quit-to-menu во время intro.** Pause → Quit to Main Menu
  → ActiveGame.clear() очищает is_intro. "Начать забег" заново → intro работает.

### Документация

- [ ] **T021** [P3] `CLAUDE.md` — таблица «Currently claimed»:
  `| 045-intro-cutscene (CutscenePlayer + IntroDirector autoloads, intro flow) | Andrey |`
  _Файл:_ `CLAUDE.md`

- [ ] **T022** [P3] `HANDOFF.md` секция 21 — короткое описание intro-flow,
  где сидят локи, как добавить ещё intro-уровень в будущем (no-go без копи-пейста
  IntroDirector — фича не generic).
  _Файл:_ `HANDOFF.md`

## Зависимости

- T001–T004 (контент) — параллельно, до smoke-тестов.
- T005 → T006 → T007 (CutscenePlayer scene → script → autoload reg).
- T009 → T010 (IntroDirector script → autoload reg).
- T008 — независимо, до T014.
- T011–T013 (locks) — параллельно после T010.
- T014–T020 — после всего кода.
- T021–T022 — в конце, перед PR.

## Порядок реализации (один проход)

1. Контент (T001–T004) — быстро, проверяем JSON-валидность parse'ом в Godot.
2. CutscenePlayer (T005–T008) — visual smoke-тест: temporarily вызвать
   `EventBus.campaign_cutscene_requested.emit("intro_office", func(): print("done"))`
   из главного меню godmode-кнопки, убедиться что overlay показывается.
3. Locks (T011–T013) — проверка через временный override `current_is_intro` → true.
4. IntroDirector (T009–T010) — собирает всё вместе.
5. Smoke (T014–T020).
6. Docs (T021–T022).
