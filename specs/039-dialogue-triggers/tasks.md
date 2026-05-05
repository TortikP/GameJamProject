# 039-dialogue-triggers — tasks

См. `spec.md` (acceptance) и `plan.md` (HOW). Tasks — что делать в порядке зависимостей. `[P1]` = блокирующее, `[P2]` = желательно, `[P3]` = nice-to-have. `[P]` = можно параллельно с предыдущим. `(depends T0XX)` = блокирующая зависимость.

## Phase 1 — Schema + data layer

- [ ] T001 [P1] `scripts/core/dialogue/dialogue_trigger.gd` — value class. Поля + `from_dict` / `to_dict` / `validate`. Без autoload.
- [ ] T002 [P1] `scripts/core/maps/level_data.gd` — поле `dialogue_triggers: Array[Dictionary] = []`. Обновить `to_dict` / `from_dict` (default empty при отсутствии). `validate()` — пройтись по массиву через `DialogueTrigger.validate`, агрегировать ошибки. (depends T001)
- [ ] T003 [P1] `scripts/core/maps/level_serializer.gd` (или эквивалент в проекте — найти при имплементации) — убедиться что новое поле сериализуется-десериализуется. Smoke: round-trip в JSON. (depends T002)
- [ ] T004 [P2] [P] `data/maps/_schema.md` — секция `dialogue_triggers[]` с полным описанием полей и curated events. (depends T002)

## Phase 2 — EventBus + WaveController синтез

- [ ] T005 [P1] `scripts/infrastructure/event_bus.gd` — добавить `signal wave_about_to_start(index: int)` и `signal level_loaded(level: LevelData)`. Документ-коммент со ссылкой на 039.
- [ ] T006 [P1] `scripts/runtime/wave_controller.gd` — найти точку перед `_apply_wave_snapshot(new_idx)` (между `wave_cleared` старой волны и snapshot apply) → emit `EventBus.wave_about_to_start(new_idx)`. Smoke: лог-печать порядка. (depends T005)
- [ ] T007 [P1] `LevelLoader.load_into(...)` (найти модуль) — после применения wave 0 emit `EventBus.level_loaded(level)`. Только additive, никаких правок load-логики. (depends T005)

## Phase 3 — Director runtime

- [ ] T008 [P1] `scripts/runtime/level_dialogue_director.gd` — autoload skeleton: `_ready` подписки, `_on_run_started` / `_on_battle_started` / `_on_battle_ended` / `_on_dialogue_finished` callbacks. Логика build/connect/disconnect. (depends T001, T005, T007)
- [ ] T009 [P1] `_make_handler` + `_on_event_fired` — variadic-args lambda + dispatch по event name. (depends T008)
- [ ] T010 [P1] `_conditions_pass` — все 7 conditions из spec §3. Mood — soft через `_has_autoload("MoodTracker")`. (depends T008)
- [ ] T011 [P1] `_try_fire` — play vs request, once-tracking, _pending_plays chain. (depends T008)
- [ ] T012 [P1] `project.godot` — зарегистрировать LevelDialogueDirector autoload **после** DialogueDB, DialogueManager, MoodTracker (если есть), но до боевых сцен. (depends T008)
- [ ] T013 [P1] Smoke без editor: написать sample JSON руками в `data/maps/sample_dialogues.json` (см. T020), запустить через Load Custom Level, убедиться что 5 триггеров стреляют корректно. (depends T012, T020)

## Phase 4 — Editor: timeline markers

- [ ] T014 [P1] `scripts/presentation/ui_theme.gd` — добавить `DIALOGUE_TRIGGER_MARKER_COLOR` + `DIALOGUE_TRIGGER_MARKER_RADIUS` константы.
- [ ] T015 [P1] `scripts/presentation/ui/wave_timeline.gd` — добавить `set_dialogue_trigger_markers(triggers, level)` + `_layout_markers` + draw в `_draw`. **Только** для `Mode.EDIT`. (depends T014)
- [ ] T016 [P1] WaveTimeline — `_gui_input` обработка hover/click на маркер: hover → tooltip из summary, click → emit `dialogue_trigger_marker_clicked(trigger_id)`. (depends T015)

## Phase 5 — Editor: trigger panel

- [ ] T017 [P1] `scenes/dev/dialogue_trigger_panel.tscn` — сцена с PanelContainer/VBox/header/list/buttons/form. Стили через UiTheme. См. plan.md §«Editor: DialogueTriggerPanel».
- [ ] T018 [P1] `scripts/presentation/dev/dialogue_trigger_panel.gd` — список + CRUD form + сигналы (`trigger_created`/`trigger_updated`/`trigger_deleted`/`trigger_marker_clicked_request`). DialogueDB.get_all_ids() для picker'а. (depends T017)
- [ ] T019 [P1] `scenes/dev/map_editor.tscn` — инстансим DialogueTriggerPanel в HUD/CanvasLayer. Раскладка: левая нижняя зона рядом с FloorPalette. (depends T017)
- [ ] T020 [P1] `scripts/presentation/dev/map_editor_controller.gd` — `+@export var dialogue_trigger_panel_path: NodePath`, `_resolve` в `_ready`, `_wire_dialogue_trigger_panel`, `_on_dlg_trigger_*` handlers. **Не более +60 строк.** (depends T015, T018)
- [ ] T021 [P1] Editor controller — `_refresh_timeline_dialogue_markers()` вызывается при bind_level / любой CRUD триггеров. Передаёт `_level.dialogue_triggers` в WaveTimeline через `set_dialogue_trigger_markers`. (depends T015, T020)
- [ ] T022 [P1] Editor controller — `dialogue_trigger_marker_clicked` (signal с timeline) → панель выделяет соответствующую строку через метод `select_trigger(id)`. (depends T016, T020)

## Phase 6 — Sample + smoke

- [ ] T023 [P1] `data/maps/sample_dialogues.json` — 2-волновый уровень с 5 триггерами из spec §6. (depends T002, T013)
- [ ] T024 [P1] Manual smoke (см. plan.md §«Test plan» полный сценарий). Все 7 шагов проходят. (depends T013, T020, T023)
- [ ] T025 [P2] Smoke: добавить в редакторе trigger с `event="totally_unknown_signal"` → save → playtest → лог: «EventBus has no signal totally_unknown_signal — triggers using it are dead», остальные триггеры работают. (depends T024)

## Phase 7 — Docs + handoff

- [ ] T026 [P2] `HANDOFF.md` §18 — short note о наличии 039 и точке интеграции с 040.
- [ ] T027 [P2] `CLAUDE.md` — таблица «Currently claimed»: добавить строку «039-dialogue-triggers — Andrey».
- [ ] T028 [P3] [P] Заметка в `andrey/HANDOFF.md` (если папка `andrey/` к моменту имплементации создана) — реальные траблы и решения.

## Cut list (если время поджимает)

- **Cut T015-T016 timeline markers.** Тогда editor — только sidebar без визуализации на таймлайне. Триггеры всё равно создаются и работают runtime. Reduces scope ~25%.
- **Cut T018 hard form.** Заменить на «edit raw JSON в TextEdit» — designer пишет dict руками, мы валидируем через `DialogueTrigger.validate`. Reduces scope ~40%.
- **Cut T025 unknown-signal smoke.** Это документирует поведение, не блокирует.

## Out-of-tasks notes

- Localization text-fields — не наша задача, Никита параллельно.
- Mood condition — soft зависимость, работает без 038.
- skill_offer_* events — JSON принимает их с момента T002, runtime warn'ит до мержа 040.
