# 062 — Validation Pipeline · Tasks

## Φ-0. Recon

- [ ] **T-062-1.** `findings.md` создать (пустой шаблон, заполняется в
  Φ-1..7 по ходу странностей).
- [ ] **T-062-2.** `grep -n "errors.append" scripts/core/maps/level_data.gd`
  — посчитать call-сайты, записать в findings.md (sanity-check для Φ-1
  loc-keys count).
- [ ] **T-062-3.** Проверить grep'ом всех consumer'ов
  `LevelData.validate(`. Текущая гипотеза — только game_editor_controller.

## Φ-1. ValidationIssue + loc keys

- [ ] **T-062-4.** Создать `scripts/core/validation/validation_issue.gd`
  (`class_name ValidationIssue extends RefCounted`). Severity enum,
  fields, `reject()` / `warn()` factory методы, `to_human()` с lazy
  Localization резолвером (паттерн из dialogue_trigger.gd:63-84).
- [ ] **T-062-5.** Создать `loc_keys.md` в этой папке — 1:1 список
  старых `errors.append` строк → новых `ui_validate_*` ключей с
  args-сигнатурой. Готовый `loc_keys.md` облегчает Φ-2.
- [ ] **T-062-6.** Добавить ~25 `ui_validate_*` ключей в
  `data/localization/en.json` (английские fallback'и из существующих
  строк в level_data.gd).
- [ ] **T-062-7.** Те же ключи в `data/localization/ru.json` (перевод).
- [ ] **T-062-8.** Добавить 4 общих ключа: `ui_validate_save_blocked`,
  `ui_validate_save_with_warns`, `ui_validate_panel_title_count`,
  `ui_validate_panel_empty` в обе локали.

**Smoke Φ-1:**
- [ ] T-062-S1. Открыть редактор после T-062-4..8, парсе нет ошибок,
  редактор открывается. `ValidationIssue.reject(...)` callable из любого
  места (нет циклической зависимости с LevelData).

## Φ-2. LevelData.validate() refactor

- [ ] **T-062-9.** В `scripts/core/maps/level_data.gd`: change return
  type `validate() -> Array[ValidationIssue]`.
- [ ] **T-062-10.** Каждый `errors.append("...")` → `errors.append(
  ValidationIssue.reject(path, key, args, fallback))`. WARN-prefixed →
  `.warn(...)`. По loc_keys.md из T-062-5.
- [ ] **T-062-11.** DialogueTrigger interop — обернуть `t.validate()`
  strings в `ValidationIssue` (см. plan.md Φ-2). Path
  = `level.dialogue_triggers[id=X].*`, severity по `WARN: ` префиксу,
  loc_key пустой (текст уже локализован).
- [ ] **T-062-12.** `scripts/presentation/dev/game_editor_controller.gd:260,334`
  — мигрировать. **NB:** перед этим — grep `_game.validate` в файле, и
  убедиться что это LevelData.validate() (а не у GameData свой). Если
  GameData свой — оставить как есть, скоупом 062 не трогаем.

**Smoke Φ-2:**
- [ ] T-062-S2. `data/maps/sample_2.json` (валидный) загрузить — 0
  issues. `data/maps/__autosave_*` (если есть невалидный) — список
  issues с правильными path'ами и severity.
- [ ] T-062-S3. Запустить `--headless --quit` в Godot, парсе нет ошибок.

## Φ-3. ValidationCoordinator

- [ ] **T-062-13.** Создать
  `scripts/presentation/dev/editor/validation_coordinator.gd` по plan.md Φ-3.
- [ ] **T-062-14.** В `editor_controller.gd::_resolve_nodes` или
  `_ready` — создать ValidationCoordinator child node, вызвать
  `setup(func(): return _level)`.
- [ ] **T-062-15.** Mutation hooks: добавить `_validation.request_revalidate()`
  в paint/erase/cascade/add_wave/copy_wave/delete_wave/update_wave_field/
  _on_skill_offer_changed (10 точек).
- [ ] **T-062-16.** Dialogue trigger CRUD ops от 061 — `request_revalidate()`
  в add/update/delete trigger методах editor_controller'а / wave_editor_ops.
- [ ] **T-062-17.** В `_on_load` и `_on_new` вызвать `revalidate_now()`
  в конце.

**Smoke Φ-3:**
- [ ] T-062-S4. Paint 5 спавнеров подряд — debounce fire'ит ровно 1 раз
  через ~200ms после последнего paint'а (проверка через `print` в
  `_on_debounce_fire` или GameLogger.info). Удалить `print` после
  smoke'а.
- [ ] T-062-S5. `revalidate_now()` после load — issues_changed signal
  fire'ится синхронно.

## Φ-4. ProblemListPanel

- [ ] **T-062-18.** Сцена `scenes/dev/editor/problem_list_panel.tscn`:
  Panel → VBox → Header HBox (Title, spacer, 3 filter Button'а) +
  ItemList. UiTheme.apply_panel_kind на root.
- [ ] **T-062-19.** Скрипт
  `scripts/presentation/dev/editor/problem_list_panel.gd` по plan.md Φ-4.
- [ ] **T-062-20.** Severity иконки: текстовые «●» (REJECT, красный) и
  «⚠» (WARN, жёлтый) — простые Label-icons через ItemList.add_icon_item.
  Если будет уродливо — заменить на shape_circle_create_imagetexture в
  Φ-8 polish.
- [ ] **T-062-21.** Добавить ProblemListPanel в `level_editor.tscn` —
  нижний край existing layout, instance .tscn'а.
- [ ] **T-062-22.** EditorController подписка
  `problem_list.jump_requested → _on_validation_jump(path)`.
- [ ] **T-062-23.** `_on_validation_jump`: парсе path:
  - `^waves\[(\d+)\]` → `set_active_wave(N)`.
  - `^level\.dialogue_triggers\[id=(\w+)\]` → `_meta_panel.select_trigger(id)`
    через WaveSettingsPanel.
  - Coord match → no-op (highlight уже виден; nice-to-have center
    camera).
  - `^level` → no-op.

**Smoke Φ-4:**
- [ ] T-062-S6. На невалидной карте — ProblemList показывает все issues
  с правильным текстом.
- [ ] T-062-S7. Filter All / REJECT / WARN — переключение видимости
  работает.
- [ ] T-062-S8. Двойной клик на issue с `waves[3].turns_to_next` →
  active wave становится 3, табы рисуются корректно.

## Φ-5. WaveSettingsPanel: badges + inline labels

- [ ] **T-062-24.** Добавить константы цветов в `ui_theme.gd` (см.
  plan.md Φ-5).
- [ ] **T-062-25.** Создать
  `scripts/presentation/dev/editor/validation_decorators.gd` (helpers
  decorate_field_inline / clear_field_inline / decorate_tab_badge /
  clear_tab_badge).
- [ ] **T-062-26.** В `wave_settings_panel.gd` — `subscribe_validation(coord)`
  и `_on_issues_changed`.
- [ ] **T-062-27.** `_refresh_tab_badges`: per-tab path filter,
  derivation worst severity, decorate.
- [ ] **T-062-28.** `_refresh_inline_labels` для полей turns_to_next,
  advance_mode, skill_offer.{pool,source,count}, music_config.bpm.
  Идемпотентный — clear затем decorate.
- [ ] **T-062-29.** EditorController вызывает `_wave_settings_panel.subscribe_validation(_validation)`
  в `_wire_panels` или `_resolve_nodes`.

**Smoke Φ-5:**
- [ ] T-062-S9. На валидной карте все табы без badges.
- [ ] T-062-S10. turns_to_next=0 в волне 2 → после 200ms таб «Wave»
  получает красный badge, под полем красный label с loc-текстом.
- [ ] T-062-S11. Замена → 5 → label/badge пропадают.
- [ ] T-062-S12. WARN-only (skill_offer.pool с несуществующим файлом) →
  жёлтый badge на табе Skill Offer + жёлтый label под полем pool.

## Φ-6. HexValidationOverlay

- [ ] **T-062-30.** Создать
  `scripts/presentation/dev/editor/hex_validation_overlay.gd` по plan.md
  Φ-6.
- [ ] **T-062-31.** Добавить ноду в `level_editor.tscn` — child
  HexGrid'а или sibling, z-order между objects_overlay и UI.
- [ ] **T-062-32.** Экспортнуть NodePath'ы grid_path и
  coordinator_path; настроить в .tscn.

**Smoke Φ-6:**
- [ ] T-062-S13. Положить spawner на (0,0) которого нет в floor —
  hex (0,0) подсвечен красным полупрозрачно.
- [ ] T-062-S14. После paint'а floor на (0,0) — после 200ms highlight
  пропадает.

## Φ-7. Save/load wiring

- [ ] **T-062-33.** `_on_save()` в editor_controller.gd по plan.md Φ-7.
- [ ] **T-062-34.** `_on_new()` — добавить `revalidate_now()` в конце.
- [ ] **T-062-35.** `_on_load()` — добавить `revalidate_now()` после
  `_push_level_to_panels()`.

**Smoke Φ-7:**
- [ ] T-062-S15. Save на пустом уровне (нет волн) → toast «Cannot save:
  1 errors». Файл не записан (проверить mtime).
- [ ] T-062-S16. Save на валидной карте → toast «Saved: path». Файл
  обновился.
- [ ] T-062-S17. Save на карте с WARN-only (e.g. невалидный pool) →
  файл записан, toast «Saved with N warnings».
- [ ] T-062-S18. Autosave продолжает писать **на любых** issue'ях —
  paint 1 spawner на пустом уровне (REJECT-state), подождать 1.5s →
  `__autosave_*.json` создан.

## Φ-8. Polish + smoke

- [ ] **T-062-36.** Полный smoke по AC1-AC13 (см. spec.md). Каждое AC —
  чекмарк, неудача → fix или findings-запись.
- [ ] **T-062-37.** Удалить debug `print`/`prints` из validation
  coordinator и др. кода.
- [ ] **T-062-38.** Перепроверить что нет inline `Color(...)` в UI коде
  062 — всё через UiTheme константы.
- [ ] **T-062-39.** Обновить `docs/FEATURES.md`: добавить запись
  `validation-pipeline` (status: working, спек 062, код points).
- [ ] **T-062-40.** Записать в `docs/tech-debt.md`: «set_dirty wiring
  ещё не подключён в level editor (`editor_controller.gd:355` коммент
  с 061)» — отдельный TODO.
- [ ] **T-062-41.** Если по ходу обнаружили что-то странное — finalize
  `findings.md` (R1-R5 из spec.md ↔ что реально вылезло).

## Готово

После всех T и smoke S — push, открыть PR `andrey/062-validation-pipeline
→ staging`. Запросить ревью у Андрея + минимум одного программиста (Алексей
если он уже работал с editor'ом ранее, иначе Сергей).
