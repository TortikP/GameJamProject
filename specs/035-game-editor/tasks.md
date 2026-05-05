# 035-game-editor — tasks

P1 = блокер релиза, P2 = важное, P3 = polish. `[P]` = можно параллельно с другими `[P]` той же приоритетности.

## Phase 1 — Data layer

- [x] **T001 [P1]** Создать `GameData` pure-data class. (`scripts/core/maps/game_data.gd`)
  - поля из spec §1, `validate() -> Array[String]`.
- [x] **T002 [P1]** Создать `GameSerializer` (static save/load). (`scripts/core/maps/game_serializer.gd`)
  - использует `FileAccess`, `JSON.stringify(d, "\t")`, sanitize имени по 020-паттерну.
- [x] **T003 [P1]** Расширить `EventBus` 5 новыми сигналами из spec §7. (`scripts/infrastructure/event_bus.gd`)
- [x] **T004 [P1]** Добавить 6 ключей в `[meta]` секцию `config/game_speed.cfg`. (`config/game_speed.cfg`)

## Phase 2 — Autoloads

- [x] **T005 [P1]** Создать `ActiveGame` autoload. (`scripts/infrastructure/active_game.gd`)
  - API из spec §3. Регистрация в `project.godot` после `ActiveLevel`.
- [x] **T006 [P1]** Создать `CampaignController` autoload. (`scripts/runtime/campaign_controller.gd`)
  - подписки на `level_completed` и `scene_ready`, callback timeouts через `await get_tree().create_timer(...)` с дефолтами из cfg.
  - регистрация в `project.godot` после `ActiveGame`.
- [x] **T007 [P1]** Создать `_DummyUpgradeStub` autoload. (`scripts/runtime/_dummy_upgrade_stub.gd`)
  - подписка на `upgrade_choice_requested`, await `upgrade_screen_min_display`, toast, callback.
  - регистрация в `project.godot` после `CampaignController`.
- [x] **T008 [P1]** В `godmode_controller._ready()` финальной строкой добавить `EventBus.scene_ready.emit(&"godmode")`. (`scripts/presentation/godmode/godmode_controller.gd`)

## Phase 3 — Transition VFX

- [x] **T009 [P2]** Создать `level_transition.tscn` + контроллер. (`scenes/meta/level_transition.tscn`, `scripts/presentation/meta/level_transition.gd`)
  - 4 фазы из spec §5. Reuse distort шейдера из `010-crt-postfx`. API: `play_out() -> Signal`, `play_in() -> Signal`.
- [x] **T010 [P2]** Подключить `play_out()` в `CampaignController` перед change_scene. После change_scene в новой сцене инстанциировать transition с `play_in()` (CampaignController сам делает это в reaction на `scene_ready` если `_just_advanced` флаг). (`scripts/runtime/campaign_controller.gd`)

## Phase 4 — Game Editor UI

- [x] **T011 [P2]** Создать `game_editor_level_row.tscn` + script. (`scenes/dev/game_editor_level_row.tscn`, `scripts/presentation/dev/game_editor_level_row.gd`)
  - сигналы наверх: `removed`, `moved_up`, `moved_down`, `changed`. Поля в строке: index label, OptionButton (карты), display_name LineEdit, cutscene_id LineEdit, is_intro CheckBox, ↑/↓/✕ кнопки.
- [x] **T012 [P2]** Создать `game_editor.tscn` + контроллер. (`scenes/dev/game_editor.tscn`, `scripts/presentation/dev/game_editor_controller.gd`)
  - дерево из spec §2. State, диспатч сигналов от rows, autosave debounce.
- [x] **T013 [P2]** Save / Load / Playtest / Exit. (`scripts/presentation/dev/game_editor_controller.gd`)
  - Save → FileDialog SAVE mode → `data/games/<sanitized>.game.json`. Confirm-overwrite через ConfirmModal.
  - Load → FileDialog OPEN, фильтр `*.game.json`. Dirty-check confirm перед сменой.
  - Playtest → write `__playtest_game__.json`, `ActiveGame.load_game(path)`, change_scene godmode.
  - Exit → dirty-check confirm → main_menu.
- [x] **T014 [P3]** Autosave debounce 1.5 сек → `__autosave_game__.json`. На входе — Confirm «Восстановить?» если mtime ≤ 24h. (`scripts/presentation/dev/game_editor_controller.gd`)

## Phase 5 — Main menu integration

- [x] **T015 [P1]** В `main_menu.tscn` добавить **GameEditorButton** + **LoadGameButton** + **LoadGameFileDialog**. (`scenes/main_menu.tscn`)
- [x] **T016 [P1]** В `main_menu.gd` — обработчики, apply_theme, `ActiveGame.clear()` в `_ready`. (`scripts/presentation/main_menu.gd`)

## Phase 6 — Endgame

- [x] **T017 [P2]** Создать `campaign_end.tscn` + script. (`scenes/meta/campaign_end.tscn`, `scripts/presentation/meta/campaign_end.gd`)
  - Заголовок, score label, кнопка Main Menu.
- [x] **T018 [P2]** В `CampaignController` — branch на `is_last_level()` → change_scene на `campaign_end.tscn` после play_out. emit `campaign_finished`. (`scripts/runtime/campaign_controller.gd`)

## Phase 7 — Sample content + docs

- [x] **T019 [P1]** Создать `data/games/sample.game.json`. (`data/games/sample.game.json`)
  - 2 уровня ссылающихся на `data/maps/sample.json` дважды, первый `is_intro=true`, `cutscene_id=&""`.
- [x] **T020 [P3]** Создать `data/games/_schema.md`. (`data/games/_schema.md`)
  - 1:1 с GameData. Пример JSON.

## Phase 8 — Validation pass

- [ ] **T021 [P1]** Smoke-test: Load Game → sample → бой → win → transition → 2-й уровень → win → campaign_end → Main Menu. Без падений в логе.
- [ ] **T022 [P2]** Edge: Save без уровней / с битым map_path → отказ + toast. (Проверить вручную в редакторе.)
- [ ] **T023 [P3]** Edge: F5 во время transition / в campaign_end — game_speed.cfg перечитывается, новый transition работает с новыми длительностями.

## Зависимости задач

```
T001 ─┐
T002 ─┼→ T005 → T006 ──┬→ T010 → T021
T003 ─┤                ├→ T018
T004 ─┘                ├→ T015 → T016
                       └→ T007

T008 → (T006 готов) → T021

T009 → T010
T011 → T012 → T013 → T014
T012 → T015 (для Game Editor button → change_scene)

T017 → T018
T019 → T021
T020 — independent
T022, T023 — после всего
```

## Сейфти-нет

После каждой Phase'ы — git commit с понятным prefix'ом (`feat(035): T001-T004 data layer + signals + cfg keys`). Если что-то ломается на Phase 5 (UI) — rollback до конца Phase 4 не теряет ядро.

Не пушить branch на staging до прохождения T021 (smoke test проходит сквозь весь flow). T022/T023 — желательны, но не блокеры PR'а.
