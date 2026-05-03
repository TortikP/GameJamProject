# 040-wave-skill-choice — tasks

См. `spec.md` (acceptance) и `plan.md` (HOW).

## Phase 1 — Schema + pool data

- [x] T001 [P1] `scripts/core/maps/level_data.gd` — `validate()` нормализует `waves[i].skill_offer` если присутствует. Per AC-S3 правила. Серилизация — поле уже сохраняется автоматически (waves — Dictionary).
- [x] T002 [P1] `data/maps/_schema.md` — секция `waves[i].skill_offer` с полями + curated pool list.
- [x] T003 [P1] `data/skill_offer_pools/_schema.md` — формат pool JSON.
- [x] T004 [P1] `data/skill_offer_pools/basic.json` — sample-пул из 6-8 скиллов из `data/skills/`. Verify ids существуют.
- [x] T005 [P1] `scripts/infrastructure/event_bus.gd` — `signal skill_offer_about_to_open(wave_index: int, count: int, pool_id: StringName)`, `signal skill_offer_closed(wave_index: int, picked_skill_id: StringName, mode: StringName)`.

## Phase 2 — Player skill adapter (preview / unblock)

- [x] T006 [P1] Найти и прочитать **существующий** API игрока для add/upgrade/replace skills. Возможные точки: `Actor.set_skills`, `godmode_controller.sync_player_skills_from_slots`, `PlayerSkillSet` (если есть). Документировать что найдено в `andrey/HANDOFF.md` (если папки нет — в спеке).

  **Found:** SlotBar (`scripts/presentation/slot_bar.gd`) holds canonical skills via `set_slot(i, skill)` / `get_slot(i)`; mirror to Actor via `GodmodeController.sync_player_skills_from_slots()` (which also drives MoodTracker). No `PlayerSkillSet` class exists. Adapter wraps these — see T008.
- [x] T007 [P1] Если public API покрывает всё — **отказываемся** от adapter, используем напрямую (mark T008-T009 [P3] N/A). Иначе → T008-T009. **Decision:** adapter required — SlotBar lookup needs scene-tree walk, plus dedup logic for owned-skills query. `scripts/runtime/player_skill_adapter.gd` written.
- [x] T008 [P2] `scripts/runtime/player_skill_adapter.gd` — wrapper per plan.md. `owned_skills_array/dict`, `add_skill`, `can_upgrade`, `upgrade_skill`, `replace_slot`, plus `first_empty_slot`, `filled_slot_indices`, `has_skill`. Lazy GodmodeController lookup; warn-once on absence.
- [ ] T009 [P2] Smoke: запустить godmode, через console (или пред-test-кнопку) дёрнуть `PlayerSkillAdapter.add_skill(&"ball_throw")` → убедиться что слот изменился. Verify upgrade/replace тем же путём. (depends T008) — **manual, deferred to T030 batch smoke.**

## Phase 3 — Controller + modal scaffolding

- [x] T010 [P1] `scripts/runtime/skill_offer_controller.gd` — autoload skeleton: `_ready` подписки, `_scan_pools`, `_on_level_loaded`, `_on_wave_cleared`, `_on_battle_ended`. Modal stub auto-picks first card until T015-T018 ship the real scene. (depends T005)
- [x] T011 [P1] `project.godot` — autoload `SkillOfferController` после `SkillDatabase`. + WaveController gate: `_check_auto_clear` awaits `EventBus.skill_offer_closed` between `wave_cleared.emit` and `_advance_wave()` when the cleared wave has `skill_offer`. (depends T010)
- [ ] T012 [P1] Smoke: создать тестовый уровень с `skill_offer` в волне 0 → playtest → должны увидеть `skill_offer_about_to_open` лог + сразу `skill_offer_closed(_, &"", &"skipped")` (заглушка). (depends T011) — **manual, batch with T030.**
- [x] T013 [P1] `_build_cards` — sampling, mode-resolution per plan.md. Без UI. Built into SkillOfferController.
- [x] T014 [P1] `_apply_pick` — диспатч в adapter / напрямую. Built into SkillOfferController.
- [x] T015 [P1] `scenes/ui/skill_offer_card.tscn` + `skill_offer_card.gd` — bind `(skill, mode, slot_index?)`, рендер icon/name/mode-badge/desc, click emit. Стилинг через UiTheme.
- [x] T016 [P1] `scenes/ui/skill_offer_modal.tscn` + `skill_offer_modal.gd` — открытие, слот для cards, Skip button, await `player_picked`. CanvasLayer=25. Pause через `get_tree().paused = true` в `open()`, false в `close()`. (depends T015)
- [x] T017 [P1] Replace-slot submenu — после клика по replace-карточке показываем second screen «выберите слот Q/W/E/R» → emit `player_picked` с slot_index. (depends T016)
- [x] T018 [P1] `_open_modal` в Controller'e — instantiate scene, передать cards, await modal'a, free scene. Заменить заглушку из T010. (depends T013, T016)

## Phase 4 — Dialog interplay

- [x] T019 [P1] В `_on_wave_cleared` — `await EventBus.dialogue_finished` если `DialogueManager.is_playing()` ПЕРЕД `paused=true`. AC-S15. (depends T018)
- [ ] T020 [P2] Smoke с 039 (если 039 уже смержен или в той же ветке): trigger `event=skill_offer_about_to_open`, `play_mode=play` → playtest → диалог играется → потом модалка. (depends T019) — **manual, batch with T030.**

## Phase 5 — Editor: WavePanel section

- [x] T021 [P1] `scripts/presentation/ui_theme.gd` — `SKILL_OFFER_MARKER_COLOR` + `SKILL_OFFER_MARKER_RADIUS` (+ `SKILL_OFFER_MARKER_GLYPH`).
- [x] T022 [P1] `scenes/dev/wave_panel.tscn` — добавить SkillOfferSection. **Decision:** built programmatically in `_build_skill_offer_section()` rather than .tscn nodes — keeps the .tscn diff zero, matches `slot_bar.gd` pattern. EnableCheckbox / PoolDropdown / CountSpinbox / Allow* CheckBoxes / PreviewBtn. Стили — UiTheme.
- [x] T023 [P1] `scripts/presentation/dev/wave_panel.gd` — `_refresh_skill_offer_section`, listeners на UI nodes, emit `skill_offer_changed(wave_idx, offer | null)`. Pool dropdown — собран из `SkillOfferController.get_pool_ids()`. (depends T022)
- [x] T024 [P1] `scripts/presentation/dev/map_editor_controller.gd` — connect `skill_offer_changed`, `_on_skill_offer_changed` handler, history push, mark dirty. **27 строк инкремент** (≤30 budget). (depends T023)
- [x] T025 [P2] PreviewBtn — открыть модалку с current config. **Decision:** preview spawn lives in WavePanel itself (keeps controller delta within AC-S22 budget). Modal builds via SkillOfferController._build_cards reaching, no _apply_pick on close. (depends T018, T023)

## Phase 6 — Editor: timeline marker

- [x] T026 [P1] `scripts/presentation/ui/wave_timeline.gd` — `_layout_skill_offer_markers` + `_draw`. Маркер в gap'е после волны с `skill_offer != null`. Работает в EDIT и RUNTIME. (depends T021)
- [x] T027 [P2] Hover на маркер → tooltip — **deferred (P3 cut, see HANDOFF §21)**. Click → emit `skill_offer_marker_clicked(wave_idx)` (только в EDIT) — done. (depends T026)
- [x] T028 [P2] Editor controller — `skill_offer_marker_clicked` → switch active wave. WavePanel auto-refreshes section. (depends T027, T024)

## Phase 7 — Sample + smoke

- [x] T029 [P1] `data/maps/sample_skill_offer.json` — 3 волны, offer на волне 1, content смокается с pool `basic`. (depends T004, T011)
- [ ] T030 [P1] Manual smoke per plan.md «Test plan» — 7 шагов, all pass. (depends T024, T026, T029) — **pending Andrey in Godot.**

## Phase 8 — Docs + handoff

- [x] T031 [P2] `HANDOFF.md` §21 — note о наличии 040 + точках интеграции с 039.
- [x] T032 [P2] `CLAUDE.md` Currently-claimed — добавить 040-wave-skill-choice — Andrey.

## Cut list (если время поджимает)

- **Hard cut: drop allow_replace** (-T017 + simplify T013-T015). Только add + upgrade.
- **Harder cut: drop allow_upgrade** (-PlayerSkillAdapter.upgrade_skill, -T008-T009 partial). Только add. Если slots full — auto-replace random / earliest.
- **Cut PreviewBtn** (-T025).
- **Cut RUNTIME timeline marker** (T026 condition только EDIT). Игрок узнаёт когда модалка открылась.
- **Cut weights** в pool — все равновероятны.

Default ship — без cut'ов. Cut'ы в порядке приоритета сверху вниз.

## Out-of-tasks notes

- Skill upgrade семантика (`level += 1`) — наследуем из 021/026, не правим.
- Mood recompute после apply — автоматом если godmode_controller `sync_player_skills_from_slots` дёргается на set_skills (он дёргается через сигнал/listener из `_on_ability_picker_selected`); если adapter путь это пропускает — добавляем явный `MoodTracker.recompute_from_skills` вызов в `_apply_pick`.
- Localization label/desc — Никитина параллельная работа, мы дёргаем `tr()`.
