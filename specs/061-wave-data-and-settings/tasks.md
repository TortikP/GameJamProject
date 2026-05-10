# 061 — Tasks

**Спек:** [`spec.md`](spec.md). **План:** [`plan.md`](plan.md). Этот документ — атомарные задачи в порядке исполнения. Каждая T-* — одна логическая операция, ровно одно изменение которое можно ревьюить отдельно. Мердж задач в один коммит — допустим если они образуют единый смысловой кусок (помечено в задаче).

Формат: `T-061-N. Описание [Φ-X] [LOC ≤ примерно] [risk]`.

---

## Φ-0. Recon (зависимости, перед стартом Φ-1)

- [ ] **T-061-1.** В `scripts/infrastructure/event_bus.gd` найти и зафиксировать сигналы: имя/сигнатуру `wave_cleared` (или ближайший аналог), `toast` (если EventBus роутер тостов). Если `wave_cleared` отсутствует — добавить как `signal wave_cleared(wave_index: int)` (1 строка), emit'ить из подходящего места (вероятно `wave_controller` после kill последнего enemy). Если `toast` нет — узнать как 060 шлёт тосты (проверить `editor_controller`/`editor_io`), использовать тот же путь. **[Φ-0] [≤10 строк, может ≤2] [R-061 OQ-IMPL-1, OQ-IMPL-2]**
- [ ] **T-061-2.** В `scripts/runtime/dialogue_db.gd` (или эквивалент) проверить наличие `get_all_ids() -> Array[StringName]`. Если нет — добавить (тривиальная итерация по внутреннему dict). **[Φ-0] [≤10 строк] [R-061 OQ-IMPL-3]**
- [ ] **T-061-3.** Grep на `is_special` по всему репо за пределами уже учтённых в plan.md Φ-2 (6 точек). Если новые — добавить в audit list для Φ-2. **[Φ-0] [recon, no LOC]**

→ Commit (если были правки): `chore(061): EventBus.wave_cleared / DialogueDB.get_all_ids — recon fixes`.

---

## Φ-1. LevelData v3 + migration + validate

- [ ] **T-061-4.** В `level_data.gd` поднять `SCHEMA_VERSION` 2→3, добавить новые `const`'ы (`DEFAULT_IS_SPECIAL`, `DEFAULT_ADVANCE_MODE`, `VALID_ADVANCE_MODES`, `DEFAULT_SPAWNER_AMOUNT`, `DEFAULT_SPAWNER_DELAY`). **[Φ-1] [≤15 строк]**
- [ ] **T-061-5.** Обновить `_make_empty_wave(idx)` — добавить дефолты `is_special: "normal"`, `respawn_player: false`, `advance_mode: "timer"`, `music_config: {}`. **[Φ-1] [≤10 строк]**
- [ ] **T-061-6.** Обновить `make_wave_copy_no_spawners(...)` — наследовать из source `is_special` (already string после миграции), `respawn_player` (можно false default чтобы не дублировать player-спаунер), `advance_mode`, `music_config`. **[Φ-1] [≤10 строк]**
- [ ] **T-061-8.** В `_wave_dict_from_arr` — читать `respawn_player`/`advance_mode`/`music_config` с дефолтами. **[Φ-1] [≤15 строк]**
- [ ] **T-061-10.** В `to_dict` (внутри per-wave entry build) — записать `respawn_player`/`advance_mode`/`music_config`. **[Φ-1] [≤8 строк]**
- [ ] **T-061-13.** Добавить публичный helper `func is_wave_special(idx: int) -> bool`. **[Φ-1] [≤8 строк]**
- [ ] **T-061-14.** Smoke: открыть `data/maps/1.json` в редакторе, save, проверить JSON: `version: 3`, новые поля присутствуют, `is_special: "normal"`. Diff `git diff data/maps/1.json` содержит только ожидаемые изменения. **[Φ-1] [smoke]**

→ Commit: `feat(061): LevelData v3 schema + migration + validate`.

---

## Φ-2. is_special readers audit + fix

- [ ] **T-061-15.** В `wave_timeline.gd` — заменить 4 точки прямого `bool(w.get("is_special", false))` на `_level.is_wave_special(i)` (если `_level` поле, что вероятно) или явное `str(...) != "normal"`. Lines 395, 397, 498. (Line 544 — `_on_wave_started(idx, _is_special: bool)` — НЕ менять, это EventBus signature.) **[Φ-2] [≤8 строк]**
- [ ] **T-061-16.** В `skill_offer_smoke_controller.gd` — заменить 3 hardcoded `"is_special": false` на `"is_special": "normal"`. Lines 153, 189, 244. **[Φ-2] [≤3 строки]**
- [ ] **T-061-17.** Если на T-061-3 нашлись новые точки — fix их тоже. **[Φ-2] [≤? зависит]**
- [ ] **T-061-18.** Smoke: загрузить `sample_skill_offer.json` (где `wave[2].is_special = true` в v2), запустить playtest, убедиться что wave 2 показывается как special визуально. **[Φ-2] [smoke]**

→ Commit: `fix(061): is_special readers — derive bool from string post-migration`.

---

## Φ-3. wave_controller advance_mode runtime

- [ ] **T-061-19.** В `wave_controller.gd` — добавить classfield `_waiting_for_clear: bool = false`. **[Φ-3] [≤3 строки]**
- [ ] **T-061-20.** В `wave_controller.gd._ready` (или где остальные subscriptions) — `EventBus.wave_cleared.connect(_on_wave_cleared)` (если сигнал существует после T-061-1). **[Φ-3] [≤3 строки]**
- [ ] **T-061-21.** В `wave_controller.gd._start_wave(idx)` (или эквивалент) — сбросить `_waiting_for_clear = false`. Если `advance_mode == "clear"` — установить `_waiting_for_clear = true` сразу. **[Φ-3] [≤8 строк]**
- [ ] **T-061-22.** Реализовать `_check_advance()` (см. plan §Φ-3.b) — match по `advance_mode`. Текущая логика advance переходит сюда. **[Φ-3] [≤25 строк net]**
- [ ] **T-061-23.** Реализовать `_on_wave_cleared(_idx)` — если `_waiting_for_clear` → advance. **[Φ-3] [≤8 строк]**
- [ ] **T-061-24.** Lines 142, 145 (emit `wave_started`) — заменить inline `bool(w.get("is_special", false))` на `_level.is_wave_special(_current_wave_index)`. **[Φ-3] [≤5 строк]**
- [ ] **T-061-25.** Pillar 1 visual: в runtime HUD (where wave counter лежит — найти на месте) — добавить условный label `«(waiting for clear)»` при `_waiting_for_clear == true`. Loc-key `ui_wave_waiting_for_clear`. **[Φ-3] [≤15 строк, может в отдельном файле]**
- [ ] **T-061-26.** Smoke (proof of life Φ-3): создать тестовую карту с 2 волнами, wave 0 `advance_mode: "timer_and_clear"`, `turns_to_next: 3`, 1 enemy spawner. Запустить playtest. Сценарий: ходы 1-3 → счётчик идёт, ход 3 → счётчик 0, wave не advance, виден label «waiting for clear». Убить enemy → advance в wave 1. **[Φ-3] [smoke critical]**

→ Commit: `feat(061): wave_controller advance_mode (timer/clear/timer_and_clear)`.

---

## Φ-4. WaveSettingsPanel skeleton + level/wave groups

- [ ] **T-061-27.** Создать `scripts/presentation/dev/wave_settings_panel.gd` — class skeleton, signals (см. plan §Φ-4.a), member vars, пустой `_ready` + `bind_level` + `set_active_wave` + `select_trigger`. **[Φ-4] [≤80 строк]**
- [ ] **T-061-28.** Создать `scenes/dev/wave_settings_panel.tscn` — Inherited Scene из `base_panel.tscn`, скрипт wave_settings_panel.gd, default size 360×600. **[Φ-4] [scene]**
- [ ] **T-061-29.** В `wave_settings_panel.gd` реализовать `_build_body()` — создаёт VBox с шестью subnode'ами (switcher, level, wave, spawner stub, skill_offer stub, wave_triggers stub). **[Φ-4] [≤25 строк]**
- [ ] **T-061-30.** Реализовать `_build_wave_switcher()` — `ItemList` + 3 кнопки `[+] [Copy] [Delete]`, сигналы emit'ят на user-action. **[Φ-4] [≤45 строк]**
- [ ] **T-061-31.** Реализовать `_build_wave_section()` — поля `is_special` (LineEdit), `turns_to_next` (SpinBox), `respawn_player` (CheckBox), `advance_mode` (OptionButton). Каждый control emit'ит `wave_field_changed` с активной волной. **[Φ-4] [≤70 строк]**
- [ ] **T-061-32.** Реализовать `_refresh_active_wave_fields()` с guard `_refreshing` — read поля из `_level.waves[_active_wave]`, set'ит controls, скрывает `respawn_player` для wave 0. **[Φ-4] [≤25 строк]**
- [ ] **T-061-33.** Реализовать `_refresh_switcher_list()` — clear + iterate `_level.waves`, формат строки `«Wave N · {is_special != "normal"} · ttn={value}»`. На `bind_level` и после mutation'ов. **[Φ-4] [≤20 строк]**
- [ ] **T-061-34.** `_build_level_section()` — пока заглушка с label «Level scope (triggers — Φ-7)». Наполнится в Φ-7. **[Φ-4] [≤8 строк]**
- [ ] **T-061-35.** Helper'ы `_make_label(loc_key, fallback)`, `_make_section_header(loc_key, fallback)` — reuse паттерна из удалённого `dialogue_trigger_panel.gd` (BasePanel children через UiTheme). **[Φ-4] [≤25 строк]**

→ Commit: `feat(061): WaveSettingsPanel skeleton — switcher + wave fields`.

---

## Φ-5. WaveSettingsPanel spawner section

- [ ] **T-061-36.** Реализовать `_build_spawner_section()` — header + `ItemList` + collapsible edit form (build пустой). **[Φ-5] [≤30 строк]**
- [ ] **T-061-37.** Реализовать `_refresh_spawner_list()` — итерация по `_level.waves[_active_wave].spawners`, формат строки. Trigger из `set_active_wave`. **[Φ-5] [≤20 строк]**
- [ ] **T-061-39.** Реализовать `_on_spawner_selected(idx)` — open form, populate с values из `_level.spawners[idx]`, set `_selected_spawner_coord`. **[Φ-5] [≤20 строк]**
- [ ] **T-061-40.** Реализовать emit'ы — каждый control в form'е на change → `spawner_field_changed(_selected_spawner_coord, {field: value})` с guard `_refreshing`. **[Φ-5] [≤15 строк]**
- [ ] **T-061-41.** Smoke (Φ-5): кликнуть на enemy spawner в списке, изменить timer 1→3, autosave, reload, значение сохранилось. **[Φ-5] [smoke]**

→ Commit: `feat(061): WaveSettingsPanel — per-spawner CRUD`.

---

## Φ-6. WaveSettingsPanel skill_offer port

- [ ] **T-061-42.** В `wave_settings_panel.gd` реализовать `_build_skill_offer_section()` — port из `673e377^:scripts/presentation/dev/wave_panel.gd`, секция `_build_skill_offer_section`. UiThemeScript→UiTheme. `_active_wave_index`→`_active_wave`. **[Φ-6] [≤80 строк]**
- [ ] **T-061-43.** Реализовать `_refresh_skill_offer_section()` — set state controls из `_level.waves[_active_wave].get("skill_offer")`. **[Φ-6] [≤25 строк]**
- [ ] **T-061-44.** Реализовать signa emits — `skill_offer_changed(idx, offer)`, `skill_offer_preview_requested(idx)`. С guard'ом `_so_refreshing`. **[Φ-6] [≤15 строк]**
- [ ] **T-061-45.** Smoke: открыть `sample_skill_offer.json`, переключить wave 0 → wave 1, секция отражает per-wave skill_offer; изменить count → autosave → reload → значение сохранилось. **[Φ-6] [smoke]**

→ Commit: `feat(061): WaveSettingsPanel — skill_offer section (port from wave_panel)`.

---

## Φ-7. WaveSettingsPanel dialogue triggers CRUD (level)

- [ ] **T-061-46.** В `_build_level_section()` (заглушка из T-061-34) — наполнить header + `ItemList` (`_triggers_list`) + button row (`Add/Edit/Duplicate/Delete`). **[Φ-7] [≤35 строк]**
- [ ] **T-061-47.** Реализовать `_refresh_triggers_list()` — итерация `_level.dialogue_triggers`, формат строки `«{id} · {event} · → {dialogue_id}»`. **[Φ-7] [≤15 строк]**
- [ ] **T-061-48.** Реализовать `_build_trigger_form()` — collapsible под списком. Поля: `id` LineEdit, `event` OptionButton (CURATED_EVENTS + Custom), `dialogue_id` OptionButton (из `DialogueDB.get_all_ids()`), `play_mode` OptionButton, conditions chip-list. **[Φ-7] [≤90 строк]**
- [ ] **T-061-49.** Реализовать chip-list conditions: на каждое condition — CheckBox+editor (SpinBox / LineEdit / float SpinBox). Resize/visibility editor'а на toggle CheckBox'а. **[Φ-7] [≤50 строк]**
- [ ] **T-061-50.** Реализовать handler'ы кнопок: `_on_btn_add` (`_open_form_blank`), `_on_btn_edit` (`_open_form_with(t)`), `_on_btn_dupe` (`_open_form_with(_dupe(t))` — id с суффиксом `_copy`), `_on_btn_delete` (confirm + emit `trigger_deleted`). Подписи через loc-keys. **[Φ-7] [≤35 строк]**
- [ ] **T-061-51.** Реализовать `_on_trigger_selected(idx)` (выбор row) → set `_selected_idx`, enable Edit/Dupe/Delete buttons. **[Φ-7] [≤15 строк]**
- [ ] **T-061-52.** Реализовать `_save_form()` — local validate, emit `trigger_created` или `trigger_updated`. **[Φ-7] [≤25 строк]**
- [ ] **T-061-53.** Реализовать `_close_form()` — visible=false, reset form fields. Cancel и после save. **[Φ-7] [≤8 строк]**
- [ ] **T-061-54.** Реализовать `select_trigger(id: StringName)` — find row, set `_selected_idx`, scroll to, open edit form. Используется в Φ-8. **[Φ-7] [≤20 строк]**
- [ ] **T-061-55.** Smoke: Add → форма → fill → Save → строка появилась в list. Edit → форма с values → modify → Save → list обновлён. Delete → confirm → row удалена. **[Φ-7] [smoke]**

→ Commit: `feat(061): WaveSettingsPanel — dialogue triggers CRUD (level scope)`.

---

## Φ-8. WaveSettingsPanel wave-section trigger mirror

- [ ] **T-061-56.** В `_build_body` (или `_build_wave_section`) добавить sub-секцию `_wave_triggers_section` — header + read-only `ItemList`. **[Φ-8] [≤15 строк]**
- [ ] **T-061-57.** Реализовать `_refresh_wave_triggers_mirror()` — фильтр по `t.conditions.wave_index == _active_wave`. Trigger из `set_active_wave` и `_refresh_triggers_list` (обе вызываются после CRUD). **[Φ-8] [≤20 строк]**
- [ ] **T-061-58.** Реализовать `_on_wave_mirror_selected(idx)` → resolve trigger id → `select_trigger(id)`. **[Φ-8] [≤10 строк]**
- [ ] **T-061-59.** Smoke: карта с триггером `wave_index=1`. Switch на wave 1 → mirror показывает trigger → click → level-section подсветил row и открыл edit form. **[Φ-8] [smoke]**

→ Commit: `feat(061): WaveSettingsPanel — wave-section trigger mirror`.

---

## Φ-9. EditorController public API + wiring

- [ ] **T-061-60.** В `editor_controller.gd` добавить classfield `_wave_settings_panel: Node` + `@export var wave_settings_panel_path: NodePath`. **[Φ-9] [≤5 строк]**
- [ ] **T-061-61.** Реализовать `set_active_wave(idx)` — sync LevelData, refresh grid через `_io.refresh_grid_from_level(...)`, panel.set_active_wave, autosave. **[Φ-9] [≤15 строк]**
- [ ] **T-061-62.** Реализовать `add_wave(after_idx)` / `copy_wave_from_prev(after_idx)` / `delete_wave(idx)` + helper `_reindex_waves()`. **[Φ-9] [≤40 строк]**
- [ ] **T-061-63.** Реализовать `update_wave_field(idx, field, value)` — match по field, локальная валидация, toast WARN при invalid. **[Φ-9] [≤30 строк]**
- [ ] **T-061-64.** Реализовать `update_spawner(coord, fields)` — find spawner на активной волне, mutate. **[Φ-9] [≤15 строк]**
- [ ] **T-061-65.** Реализовать `add_dialogue_trigger(t)` / `update_dialogue_trigger(old_id, t)` / `delete_dialogue_trigger(id)` — CRUD на `_level.dialogue_triggers`, валидация, autosave, rebind panel. **[Φ-9] [≤50 строк]**
- [ ] **T-061-66.** Реализовать `_wire_wave_settings_panel()` — connect всех 11 сигналов панели. Вызвать из `_ready`. **[Φ-9] [≤25 строк]**
- [ ] **T-061-67.** В `_ready` или `bind_level` — `_wave_settings_panel.bind_level(_level)`. **[Φ-9] [≤3 строки]**
- [ ] **T-061-68.** Поднять hard cap controller'а 300 → 350 (комментарий в файле + AC33 спека). Если превышает 350 — finding. **[Φ-9] [no-op LOC, soft requirement]**
- [ ] **T-061-69.** Smoke (proof of life Φ-9): «+ Wave» → новая в switcher → click → grid пустой → save → reload → wave 1 на месте. Delete → удалена. Edit `is_special: "normal"` → `"boss"` → save → JSON content. **[Φ-9] [smoke critical]**

→ Commit: `feat(061): EditorController wave-nav + dialogue-triggers CRUD + wiring`.

---

## Φ-10. level_editor.tscn integration

- [ ] **T-061-70.** В `scenes/dev/level_editor.tscn` — добавить ext_resource на `wave_settings_panel.tscn` + node instance в HUD. Default position right edge offset by LayersPanel height. **[Φ-10] [scene, ≤10 строк tscn]**
- [ ] **T-061-71.** Smoke: запустить редактор, обе панели (LayersPanel + WaveSettingsPanel) видны без overlap. Drag WaveSettingsPanel → persistence сохранил new position через `BasePanel` (058). **[Φ-10] [smoke]**

→ Commit: `feat(061): mount WaveSettingsPanel in level_editor.tscn`.

---

## Φ-11. Loc-keys batch

- [ ] **T-061-72.** Добавить ~45 ключей из plan §Φ-11 в `data/localization/en.json` + `data/localization/ru.json`. EN — формальные термины. RU — естественный язык. **[Φ-11] [json, ~90 entries]**
- [ ] **T-061-73.** Smoke: переключить язык → все label'ы в WaveSettingsPanel + советующие тосты — корректные. Никаких raw loc-key strings вместо текста. **[Φ-11] [smoke]**

→ Commit: `feat(061): localization keys for WaveSettingsPanel + advance_mode UI`.

---

## Φ-12. Backward-compat smoke (AC34-36)

- [ ] **T-061-74.** Smoke `data/maps/1.json`: load → no errors → switcher показывает 1 wave → save → JSON v3 + new fields. Reload — diff после нормализации = 0 в floor/objects/spawners. **[Φ-12] [smoke critical]**
- [ ] **T-061-75.** Smoke `data/maps/sample_skill_offer.json`: load → 3 waves → wave 2 has `is_special` → wave-section показывает поле как `"boss"` (после миграции из bool). Save → JSON has `"is_special": "boss"`. Skill_offer per-wave работает. **[Φ-12] [smoke critical]**
- [ ] **T-061-76.** Smoke `data/maps/story_map_03.json`: load → много волн → переключаться между ними, поля корректны. Триггеры (если есть) — в level-секции. Save → idempotent. **[Φ-12] [smoke critical]**
- [ ] **T-061-77.** Smoke playtest каждой v2 карты после save'а как v3: загрузка через campaign / Game Editor playtest → одинаковое поведение что до миграции (один и тот же seed → один ход событий). **[Φ-12] [smoke critical]**
- [ ] **T-061-78.** Если на T-061-74..77 нашли регрессию — открыть finding `findings.md` с описанием + плагином (или git revert и discussion с Андреем). **[Φ-12] [contingent]**

→ Commit: `chore(061): backward-compat smoke — все existing maps мигрируют чисто` (если smoke прошёл; иначе fix-коммиты с findings'ами по ходу).

---

## Φ-13. Docs

- [ ] **T-061-79.** Создать `docs/systems/level-editor/dialogue-triggers.md` (см. plan §Φ-13). Включает: концепт, CURATED_EVENTS таблица с семантикой, `id` vs `dialogue_id` пример, conditions cookbook, ссылки на спеки 003/039/061. **[Φ-13] [≤120 строк markdown]**
- [ ] **T-061-80.** Обновить (или создать) `data/maps/_schema.md`: top-level fields, wave entry v3, spawner v3, migration notes. **[Φ-13] [≤60 строк markdown]**
- [ ] **T-061-81.** В `docs/FEATURES.md` обновить запись `level-editor` и/или добавить `wave-settings-panel`, `dialogue-triggers-editor` (lazy backfill). **[Φ-13] [≤30 строк markdown]**
- [ ] **T-061-82.** В `docs/tech-debt.md` — если за время имплементации возникли findings (R-061-13 monolith, R-061-14 missed audit, etc.) — занести с id'ом `F-061-IMPL-K`. **[Φ-13] [contingent]**

→ Commit: `docs(061): dialogue-triggers UX, schema v3, FEATURES backfill`.

---

## Φ-14. PR finalization

- [ ] **T-061-83.** Финальный rebase ветки на `staging` (если staging уехал во время имплементации). `git checkout staging && git pull && git checkout andrey/061-wave-data-and-settings && git rebase staging`. **[Φ-14] [git]**
- [ ] **T-061-84.** PR description в `specs/061-wave-data-and-settings/PR.md` (как 060). Включает: scope summary (что сделано), AC checklist (✅ / ❌), smoke checklist with results, findings ссылки, breaking notes (миграция v2→v3). **[Φ-14] [≤80 строк markdown]**
- [ ] **T-061-85.** Push, открыть PR через https://github.com/TortikP/GameJamProject/pull/new/andrey/061-wave-data-and-settings, поставить ассайнером Андрея. **[Φ-14] [git + browser]**

→ Commit (последний перед PR): `docs(061): PR description + final smoke checklist`.

---

## Sequencing visualization

```
Φ-0 recon ───────┐
                 ├──→ Φ-1 LevelData v3
                 │       │
                 │       ├──→ Φ-2 is_special audit (||)
                 │       │
                 │       └──→ Φ-3 advance_mode runtime
                 │              │
                 │              └──→ Φ-4 panel skeleton
                 │                     │
                 │                     ├──→ Φ-5 spawner section
                 │                     ├──→ Φ-6 skill_offer port
                 │                     ├──→ Φ-7 dialogue triggers CRUD
                 │                     │      │
                 │                     │      └──→ Φ-8 wave-mirror
                 │                     │
                 │                     └──→ Φ-9 EditorController wiring
                 │                            │
                 │                            └──→ Φ-10 tscn integration
                 │                                   │
                 │                                   └──→ Φ-11 loc-keys
                 │                                          │
                 │                                          └──→ Φ-12 smoke
                 │                                                 │
                 │                                                 └──→ Φ-13 docs
                 │                                                        │
                 │                                                        └──→ Φ-14 PR
```

Φ-2 параллелится с Φ-3 (обе зависят только от Φ-1's helper). Остальные строго последовательно.

**Оценка длительности:** 2-3 сессии до merge при текущем темпе.
