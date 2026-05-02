# 024-wave-editor — tasks

Чек-лист имплементации. Зависимости — `spec.md` (acceptance) + `plan.md` (file paths, API). Cross-link: AC-W* ссылается на acceptance criteria из spec.md.

Минимальный играбельный scope, если время кончается: **P1 + P2 + P3 + P7**. Editor-полировку (P4, P5) и HUD (P6) можно cut'нуть.

## P0 — Setup (этот PR)

- [x] T1. `git mv specs/024-phase-timer-bar specs/024-wave-editor`.
- [x] T2. spec.md v2 написан (rewrite после clarify-round).
- [x] T3. plan.md написан.
- [x] T4. tasks.md написан (этот файл).

## P1 — Data + autoload + EventBus

- [x] T10. `LevelData.waves: Array[Dictionary]` поле, дефолт `[]`. (AC-W1)
- [x] T11. `LevelData.from_dict()` — миграция: если нет `waves` → пакуем root `floor/objects/spawners` в `waves[0]` с `is_special=false, turns_to_next=0`. Legacy spawner без `timer` → `timer=1`. (AC-W2)
- [x] T12. `LevelData.to_dict()` пишет всегда waves-формат, не корневые поля. (AC-W1)
- [x] T13. `LevelData.validate()` расширен: contiguous index, single player spawner across union, coord ∈ floor of own wave, `turns_to_next ≥ 1` (last = 0), `timer ≥ 1`. WARN if `timer > turns_to_next`. (AC-W3)
- [x] T14. `LevelData.get_wave_start_turn(idx)` — sum prev `turns_to_next`. (AC-W14, used by widget)
- [x] T15. `data/maps/_schema.md` — добавить раздел «waves» с примером.
- [x] T20. `EventBus`: добавить `wave_started(index: int, is_special: bool)`, `wave_cleared(index: int, unused_turns: int)`, `level_completed(total_score: int)`. (AC-W12, AC-W13)
- [x] T21. `EventBus`: проверить наличие `actor_spawned(actor)`. Добавить если нет.
- [x] T22. `EventBus.world_turn_ended(turn: int)` уже существует — verified line 53. Проверить, что эмитится после **полного** хода (player + AI), не после каждого actor'а. Если нет — fix in BattleController. (AC-W10)
- [x] T30. `scripts/infrastructure/run_score.gd` — autoload по plan.md. Подписан на `EventBus.run_started` для reset. (AC-W15)
- [x] T31. Регистрация `RunScore` в `[autoload]` `project.godot`, после `EventBus`.
- [x] T32. `config/game_speed.cfg`: `[battle] wave_transition_sec=0.15`, `[ui] wave_tick_anim_sec=0.2`, `score_punch_sec=0.25`. (AC-W16)

**P1 smoke:** загрузить `data/maps/sample.json` (legacy) → играется; save из редактора → JSON в waves-формате.

## P2 — Push-out в HexGrid

- [x] T40. `HexGrid.find_passable_for_displacement(from, exclude=[]) -> Vector2i`. BFS spiral, deterministic neighbour order, `MAX_DISPLACEMENT_RADIUS = 30`, sentinel `Vector2i.MAX`. (AC-W11)
- [x] T41. `HexGrid.displace_actor(actor, exclude=[]) -> bool` — chain-push рекурсивно. No-target → `actor.kill_with_reason("crushed")`. (AC-W11)
- [x] T42. `Actor.kill_with_reason(reason: String)` — добавить если нет (можно как алиас на existing `kill()` с logging).
- [x] T43. Verify: `move_actor` триггерит TileObjectResolver `on_actor_entered`. Если push-via-displace_actor использует `move_actor` напрямую — должно работать. Иначе — explicit call после displacement. (AC-W11, damage-on-land)
- [ ] T44. Dev-сцена `scenes/dev/displacement_smoke.tscn` — 3 актёра, кнопка «remove tile under selected» — для ручной верификации. *(deferred — manual smoke can use godmode + JSON edits; sample_waves.json in P7 covers the E2E case.)*

**P2 smoke:** см. plan.md → "P2 smoke".

## P3 — WaveController + spawner placeholder

- [x] T50. `scripts/runtime/wave_controller.gd` skeleton (extends Node, signals, fields per plan.md API).
- [x] T51. `start_level(level)` — set `_level`, current = -1, `_advance_wave()`.
- [x] T52. `_advance_wave()` — увеличить index, выход за бортик → `level_completed.emit`. Иначе → `_apply_wave_snapshot` + `wave_started.emit`.
- [x] T53. `_apply_wave_snapshot(idx)`:
  - [x] T53a. Diff old vs new floor: erase missing, push-out residents, set new cells через `FloorLayer.set_cell`.
  - [x] T53b. Diff old vs new objects: remove gone, add new, push-out если actor попал на newly-impassable.
  - [x] T53c. Discard `_pending_spawners`. Удалить старые placeholder ноды. Инстанциировать placeholder для каждого `waves[idx].spawners` (skip player kind на idx > 0). Скопировать в `_pending_spawners`.
  - [x] T53d. `_turns_into_wave = 0`.
  - [ ] T53e. Wait `GameSpeed.wait("battle", "wave_transition_sec")` для visual settle. Player input блокировать на этот период. *(deferred — `start_level.call_deferred` already gives a frame; the explicit input lock can be added in P5/P7 polish if visible glitching warrants it. config key already added in P1.)*
- [x] T54. `_on_world_turn_ended(turn)`:
  - [x] T54a. `_turns_into_wave++`.
  - [x] T54b. Decrement timer всех pending. timer→0 → `_spawn_from_pending` (создать actor через существующий spawn-helper, удалить placeholder, удалить из pending). Иначе → update placeholder label, оставить.
  - [x] T54c. Если `_turns_into_wave >= turns_to_next` → `_advance_wave`.
- [x] T55. `_on_actor_died(actor)` → `call_deferred("_check_auto_clear")`.
- [x] T56. `_check_auto_clear()`: enemy_count == 0 && pending empty → unused, `RunScore.add`, `wave_cleared.emit`, `_advance_wave`.
- [x] T57. `scripts/presentation/runtime/spawner_placeholder.gd` + `scenes/runtime/spawner_placeholder.tscn`. Sprite2D (placeholder spawner art) + Label child для timer'a. Punch tween на decrement.
- [x] T58. Label шрифт = `UiTheme.FS_NUM_OVERHEAD`, outline через `UiTheme.apply_world_text_outline`. (CLAUDE.md visibility doctrine) *(uses `apply_label_kind(label, "num_huge")` — UiTheme has FS_NUM_HUGE, not FS_NUM_OVERHEAD; matches plan.md "Шрифты для цифр на спавнере и score corner" via UiTheme.FS_NUM_*.)*
- [x] T59. Mount WaveController в `scenes/dev/godmode.tscn`. Wire `LevelLoader.apply_to(...)` → `wave_controller.start_level(level)`. *(Mounted via godmode_controller code, not .tscn export — the controller is conditionally created only when a LevelData is queued. Net behavior same.)*
- [x] T60. Если `ActiveLevel.has_queued()` is false (procedural godmode без custom level) → WaveController NO-OP, `start_level` не зовётся. Старый procedural путь работает побайтово как раньше.

**P3 smoke:** см. plan.md → "P3 smoke" (хардкод 2-волнового уровня).

## P4 — WaveTimeline widget

- [x] T70. `scripts/presentation/ui/wave_timeline.gd` skeleton — Mode enum, signals, `bind_level()`, `set_runtime_state()`.
- [x] T71. `_draw()`: горизонтальная линия + якоря (CircleShape) + цифры между. 1 turn = 1 px. Special → больший радиус (`UiTheme.WAVE_ANCHOR_SPECIAL_RADIUS_MULT`). (AC-W4, AC-W17)
- [x] T72. RUNTIME mode:
  - [x] T72a. Часы-курсор (Sprite2D или vector через _draw) на позиции `get_wave_start_turn(curr) + turns_into`. *(Drawn via `_draw` line + triangle pointer; no separate Sprite2D — simpler. Cursor uses `_runtime_current_wave` anchor x + `_runtime_turns_into_wave` × PIXELS_PER_TURN.)*
  - [x] T72b. Якоря пройденных волн — притушить (UiTheme `WAVE_ANCHOR_PASSED`).
  - [ ] T72c. Tick анимация на decrement турн-счётчика — `Tween` на scale Label'a, `GameSpeed.wait("ui", "wave_tick_anim_sec")`. *(Deferred — cursor moves smoothly; per-number pulse can be added in 029-feedback-polish if it reads as flat.)*
- [x] T73. EDIT mode:
  - [x] T73a. Якоря — кликабельные `Control` ноды (не `_draw`). LMB → `anchor_clicked.emit(idx)`. RMB → `anchor_context_requested.emit(idx, screen_pos)`. *(Anchors hit-tested via `_gui_input` against the drawn discs — same end behaviour, less node bloat.)*
  - [x] T73b. Числа `turns_to_next` — `LineEdit` дети с numeric validation. Enter / focus_exit → `turns_to_next_changed.emit(idx, value)`. Esc → revert. *(Esc-revert deferred; commit on enter / focus_exit works.)*
  - [x] T73c. RMB на gap (между якорями) → `gap_context_requested.emit(after_idx, screen_pos)`.
  - [x] T73d. Кнопка «+ Wave» на правом конце бара → `add_wave_pressed.emit`.
  - [x] T73e. Подсветка active wave: контурное обведение якоря (active_wave_index пробрасывается в widget via setter).
- [x] T74. UiTheme константы: `WAVE_BAR_BG`, `WAVE_ANCHOR_FILL`, `WAVE_ANCHOR_PASSED`, `WAVE_ANCHOR_CURRENT`, `WAVE_ANCHOR_SPECIAL_RADIUS_MULT`, `WAVE_NUMBER_FONT_SIZE`, etc. Inline-цвета в скрипте — запрещены (CLAUDE.md).
- [ ] T75. Preview-сцена `scenes/dev/wave_timeline_preview.tscn` — мок LevelData, переключение mode, ручной trigger `set_runtime_state` через UI кнопки. *(Deferred — RUNTIME mode is exercised end-to-end via godmode + sample_waves.json; EDIT mode via P5 editor integration.)*

**P4 smoke:** см. plan.md → "P4 smoke".

## P5 — Editor integration (WavePanel + active wave routing)

- [x] T80. `MapEditorController._level.waves` поле обращений (вместо корневых). `_active_wave_index: int = 0`. *(LevelData root fields stay as the active-wave view; `set_active_wave_index` sync-swaps them around. No 30+ callsite refactor needed.)*
- [x] T81. Все placement-методы (`_place_floor`, `_place_object`, `_place_spawner`, `_erase_at`, replace-all, etc.) — пишут в `_level.waves[_active_wave_index]`. *(Achieved via the active-wave view; `to_dict` syncs root → waves[active] before serialize.)*
- [x] T82. `_repaint_canvas()`: рисует только `_level.waves[_active_wave_index]` — это полный снапшот этой волны. *(Existing `_apply_level` repaints from root fields → which mirror waves[active]. Active-wave switch calls `_apply_level(_level, false)`.)*
- [ ] T83. Highlight overlay для new-this-wave объектов. *(Deferred — pure visual aid; designer can A/B compare by clicking between waves. Land in 029-feedback-polish.)*
- [x] T84. `scripts/presentation/dev/wave_panel.gd` + соответствующий node в `scenes/dev/map_editor.tscn` сверху над канвой.
- [x] T85. WavePanel содержит:
  - [x] T85a. `WaveTimeline` instance в Mode.EDIT.
  - [x] T85b. Кнопка «Copy from previous wave (no spawners)». Disabled если active = 0. (AC-W7)
  - [x] T85c. Кнопка «Toggle special» для active wave (синхронизирована с RMB-context на якоре).
- [x] T86. Wire WaveTimeline сигналы в WavePanel/EditorController:
  - [x] T86a. `anchor_clicked(idx)` → `_active_wave_index = idx`, repaint, autosave.
  - [x] T86b. `anchor_context_requested(idx, pos)` → ConfirmModal-gated delete (Wave 0 — info-toast). *(Full PopupMenu deferred — Toggle Special is on a dedicated WavePanel button; Delete is the only destructive RMB-anchor op.)*
  - [x] T86c. `gap_context_requested(after_idx, pos)` → новая волна с copy-from-prev, индексы +1.
  - [x] T86d. `turns_to_next_changed(idx, value)` → `_level.waves[idx].turns_to_next = max(1, value)`, autosave.
  - [x] T86e. `add_wave_pressed` → append с copy-from-prev defaults, switch active. *(Previous-last-wave's ttn=0 promoted to DEFAULT_TURNS_TO_NEXT before append; new last gets ttn=0 to preserve invariant.)*
- [ ] T87. Spawner placement / selection inline LineEdit для timer'a. *(Deferred — designers can hand-edit JSON or land in 029. Default timer=1 on placement; sample_waves.json shows non-default values.)*
- [ ] T88. Visual: цифра timer'a рисуется на спавнере на канве. *(Deferred with T87.)*
- [x] T89. Validation: при save — extended `LevelData.validate()` уже учитывает waves-инварианты.
- [x] T90. Autosave: любая wave-операция → debounce 1.5s → autosave. *(All wave handlers call `_mark_dirty()`.)*

**P5 smoke:** см. plan.md → "P5 smoke".

## P6 — Score corner HUD widget

- [x] T100. `scripts/presentation/ui/score_corner.gd` + `scenes/ui/score_corner.tscn`. Label child + AnchorPreset top-right.
- [x] T101. Подписан на `RunScore.score_changed`. Текст = `str(total)`.
- [x] T102. Punch tween: `scale 1.0 → 1.2 → 1.0` за `GameSpeed.get_value("ui", "score_punch_sec")` (дефолт 0.25).
- [x] T103. Mount в HUD `scenes/dev/godmode.tscn` (CanvasLayer top-right).
- [x] T104. Шрифт: `UiTheme.FS_NUM_HUGE`. Outline через `UiTheme.apply_world_text_outline`.

**P6 smoke:** консоль/dev-кнопка → `RunScore.add(5)` → label обновляется с пульсом.

## P7 — Sample + E2E smoke

- [x] T110. `data/maps/sample_waves.json` — 3-волновая демо-карта (per AC-W18):
  - Wave 0: player at (1,2) + 1 manekin at (6,3) (timer=2), `turns_to_next=5`. 8×6 grass floor, mountain at (4,3).
  - Wave 1: 1 manekin at (5,5) (timer=3), mountain удалён (object diff), `turns_to_next=6`. is_special=true.
  - Wave 2: пропасть из (3,2) и (3,3) — push-out demo если player стоит/отступил туда. `turns_to_next=0` (последняя).
- [ ] T111. Смок: главное меню → Load Custom Level → sample_waves.json → бой запускается → весь сценарий из AC-W19 проходит. *(Manual playtest deferred — needs Godot engine; static review in this PR.)*
- [ ] T112. Manual edge: убить врага волны 0 на ходу 1 → `score = 4` → wave 1 стартует мгновенно. Manual edge: не убить → wave 0 заканчивается на ходу 5 без auto-clear. *(Manual playtest.)*
- [ ] T113. Manual edge: на волне 2, если push-out выкидывает на damaging-tile (если на карте есть лава) → damage применяется immediately. *(Manual playtest; sample has no lava — push-out lands on plain grass, no damage expected.)*

**P7 smoke == AC-W19.**

## P-cleanup

- [ ] T120. `data/maps/_schema.md` — полный раздел про waves, пример sample_waves.json.
- [ ] T121. `HANDOFF.md`:
  - [ ] T121a. §work-in-progress: «024-wave-editor смержена в staging».
  - [ ] T121b. §EventBus signals — добавить `wave_started`, `wave_cleared`, `level_completed`.
  - [ ] T121c. §модули — `WaveController`, `RunScore`.
- [ ] T122. `CLAUDE.md` — claimed table: `024-wave-editor` → Andrey.
- [ ] T123. `specs/024-wave-editor/spec.md` — обновить «История правок» с финальной отметкой merge.

## Открытые на post-merge (не блокеры)

- OQ-12 (chain damage order) — обсудить на плейтесте.
- OQ-13 (multi-atlas cleanup) — отдельная спека, обсудить с Andrey.

## Если упёрлись

- Push-out не работает на конкретном кейсе → читаем CLAUDE.md «Known Godot 4.6 traps» (особенно про Array[CustomClass]); fallback на Dictionary store если HexGrid внутренние структуры жалуются.
- WaveTimeline не получает кликов в EDIT mode → проверить `mouse_filter = MOUSE_FILTER_PASS / STOP` у parent контейнеров; CanvasLayer в редакторе может перекрывать.
- Auto-clear триггерится дважды → `_check_auto_clear` идемпотентен (early return если `_current_wave_index` уже сменился). Гард: `_advance_wave` фиксирует index до emit'a.
- Anything else → re-read spec.md + plan.md «Risk register».
