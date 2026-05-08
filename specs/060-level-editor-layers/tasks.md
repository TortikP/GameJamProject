# 060 — Tasks

**Спек:** [`spec.md`](spec.md). **План:** [`plan.md`](plan.md). Этот документ — атомарные задачи в порядке исполнения. Каждая T-* — одна логическая операция, ровно одно изменение которое можно ревьюить отдельно. Мердж задач в один коммит — допустим если они образуют единый смысловой кусок (помечено в задаче).

Формат: `T-060-N. Описание [Φ-X] [LOC ≤ примерно] [risk]`.

---

## Φ-1. Framework patch (PanelTabBar + TabbedBasePanel)

- [x] **T-060-1.** В `panel_tab_bar.gd` добавить параметр `by_user: bool = false` к `_set_active(tab_id, by_user)`. Все 5 call sites обновить (см. plan §Φ-1 таблица): line 89/387/457 → `false`, line 242/329 → `true`. **[Φ-1] [≤15 строк] [R2: проверить tabbed_panel_demo не сломан]**
- [x] **T-060-2.** В `panel_tab_bar.gd` добавить `signal active_tab_changed(tab_id: StringName)` и emit в `_set_active` если `by_user == true`. **[Φ-1] [≤5 строк]**
- [x] **T-060-3.** В `panel_tab_bar.gd` добавить публичный `func set_active(tab_id: StringName, by_user: bool = false) -> void` — простой делегат в `_set_active`. **[Φ-1] [≤5 строк]**
- [x] **T-060-4.** В `tabbed_base_panel.gd` объявить `signal active_tab_changed(tab_id: StringName)`. В `_setup_tab_bar` подключить `_tab_bar.active_tab_changed` к лямбде, переэмитящей в собственный сигнал. Добавить `func set_active_tab(tab_id: StringName) -> void` делегирующий `_tab_bar.set_active(tab_id, false)`. **[Φ-1] [≤10 строк]**
- [ ] **T-060-5.** Smoke: открыть `tabbed_panel_demo.tscn`, добавить временный print в demo на `active_tab_changed`, кликать по табам, убедиться что сигнал летит ТОЛЬКО на user click (не initial). Удалить print после проверки. **[Φ-1] [smoke]**

→ Commit: `feat(ui-panels): active_tab_changed signal + set_active API` (отдельный логический коммит, framework-only).

---

## Φ-2. EditorIO extract

- [x] **T-060-6.** Создать `scripts/presentation/dev/editor/editor_io.gd` со стабовым API (см. plan §Φ-2). `class_name EditorIO extends Node`. Все методы возвращают defaults (null/false/empty). **[Φ-2] [≤80 строк]**
- [x] **T-060-7.** Перенести `_on_save` логику из `editor_controller.gd` в `EditorIO.save(level)`. Контроллер дёргает `_io.save(_level)`. **[Φ-2] [≤30 строк net]**
- [x] **T-060-8.** Перенести `_on_load` логику в `EditorIO.load_from(path)`. Контроллер дёргает `_io.load_from(path)`. **[Φ-2] [≤30 строк net]**
- [x] **T-060-9.** Перенести `_refresh_grid_from_level` в `EditorIO.refresh_grid_from_level(level)`. Расширить параметром overlays — controller передаёт null'ы пока (overlays подключаются в Φ-6). **[Φ-2] [≤25 строк net]**
- [x] **T-060-10.** Добавить `Timer` autosave в `EditorIO._ready` (one_shot, wait_time=1.5). Реализовать `enqueue_autosave(level)` (start таймер) и `_on_autosave_fire` (write `__autosave__.json`). **[Φ-2] [≤30 строк] [R5: max-debounce — finding если важно]**
- [x] **T-060-11.** Реализовать `clear_autosave()` (DirAccess.remove если файл есть) и `check_autosave_on_ready() -> Dictionary {prompt_needed, age_sec}`. **[Φ-2] [≤25 строк]**
- [x] **T-060-12.** Реализовать `write_playtest_snapshot(level) -> bool` (то же что save, но в `__playtest__.json`). **[Φ-2] [≤10 строк]**
- [ ] **T-060-13.** Smoke: проверить что 059'й цикл (paint floor → save → exit → load → paint visible) работает 1:1 как до refactor. **[Φ-2] [smoke] [R1: измерить размер controller'а — ожидаемо ≤200]**

→ Commit: `refactor(060): extract EditorIO from EditorController` (functional pure refactor, без новой UX).

---

## Φ-3. LayersModel + LayersPanel migration

- [x] **T-060-14.** Расширить `layers_model.gd`: константы `LAYER_SPAWNERS`, `LAYER_OBJECTS`, `LAYER_ORDER`. Метод `cycle_active_forward() -> StringName`. Метод `has_selection() -> bool`. Default selection для всех трёх слоёв в инициализации (controller сам set'ит после конструктора). **[Φ-3] [≤30 строк net]**
- [x] **T-060-15.** В `layers_panel.gd`: сменить `extends BasePanel` → `extends TabbedBasePanel`. Удалить старое поле `_palette: HexTilePalette` и сигнал `hex_palette_selection_changed`. Объявить `signal layer_selection_changed(layer_id: StringName, value: Variant)`. **[Φ-3] [≤10 строк]**
- [x] **T-060-16.** В `layers_panel.gd._ready`: после `super._ready()` создать три палитры (HexTilePalette + stub'ы SpawnerPalette/ObjectPalette — реализация в Φ-4). Подключить их `selection_changed` через `bind(layer_id)` в `_on_palette` re-emitter. Вызвать `add_tab` для каждой. **[Φ-3] [≤25 строк] [R3: ButtonGroup state на смене таба]**
- [x] **T-060-17.** Добавить в `layers_panel.gd` метод `get_palette_for_layer(layer_id: StringName) -> Node` (для Φ-5 quick-select dispatch). **[Φ-3] [≤10 строк]**
- [x] **T-060-18.** Создать stub'ы `spawner_palette.gd` и `object_palette.gd` с минимальным `class_name X extends VBoxContainer`, `signal selection_changed(value: Dictionary)`, `_ready()` пустой. Реализация — Φ-4. **[Φ-3] [≤15 строк × 2]**
- [x] **T-060-19.** В `editor_controller.gd`: заменить slot `_on_palette_selection(value)` → `_on_layer_selection_changed(layer_id, value)`. Подписаться на `_layers_panel.layer_selection_changed` и `_layers_panel.active_tab_changed`. Slot последнего → `_layers.active_layer = tab_id`. **[Φ-3] [≤20 строк net]**
- [x] **T-060-20.** Обновить `scenes/dev/editor/layers_panel.tscn` — script сменился на TabbedBasePanel-наследника. Если script-override не подхватывается — пересохранить или поправить вручную. **[Φ-3] [.tscn правка] [risk]** *(.tscn instance=base_panel.tscn + script=layers_panel.gd; script chain `LayersPanel→TabbedBasePanel→BasePanel` works on base_panel root — no .tscn edits needed.)*
- [ ] **T-060-21.** Smoke: level_editor.tscn открывается, видны три таба. Hexes — палитра как в 059, рисует. Spawners/Objects — пустые табы. Клик по табам переключает контент. Active tab — синхронизирован с `LayersModel.active_layer` (проверить через debug print). **[Φ-3] [smoke]**

→ Commit: `feat(060): migrate LayersPanel to TabbedBasePanel + extend LayersModel`.

---

## Φ-4. Palettes (SpawnerPalette + ObjectPalette)

- [x] **T-060-22.** Реализовать `spawner_palette.gd` полностью (см. plan §Φ-4.a code). Player + N enemies из `data/enemies/*.json`. Text-only buttons. Метод `quick_select(n)`. Сбор `_quick_select_buttons` для Φ-5. **[Φ-4] [≤80 строк]**
- [x] **T-060-23.** Реализовать `object_palette.gd` полностью (см. plan §Φ-4.b code). `TileObjectRegistry` итерация. Без табов obstacles/interactive. Text-only buttons. **[Φ-4] [≤80 строк]**
- [x] **T-060-24.** Реализовать `_decorate_quick_select_badges()` — Label child каждой из первых 9 кнопок с цифрой. Дублировать в обеих палитрах (или вытащить в shared `palette_helpers.gd` — на усмотрение имплементера, **не** лезть в abstraction over одного use case без необходимости). Также добавить badges в `HexTilePalette` для consistency. **[Φ-4] [≤20 строк × 3 palette = ≤60]** *(extracted to PaletteHelpers — 3 use cases justifies it)*
- [ ] **T-060-25.** Smoke: spawners-таб видит Player + список enemy. Objects-таб видит N tile objects. Click меняет ButtonGroup. На первых 9 кнопках в каждой палитре — цифры в углу. **[Φ-4] [smoke]**

→ Commit: `feat(060): SpawnerPalette + ObjectPalette + 1-9 quick-select badges`.

---

## Φ-5. InputDispatcher: per-layer + keyboard + cascade

- [x] **T-060-26.** Расширить `input_dispatcher.gd._act_at`: `match _layers.active_layer:` → ветви на три helper'а `_act_hexes`, `_act_spawners`, `_act_objects` (см. plan §Φ-5.a code). Hexes — поведение 059, как было. Spawners/objects — вызывают новый controller API (`paint_spawner`, `erase_spawner`, etc., будут реализованы в Φ-6). **[Φ-5] [≤50 строк net]**
- [x] **T-060-27.** Изменить `_act_hexes` так, чтобы flash спавнился из dispatcher а не controller. Controller `erase_floor` теперь возвращает `bool`. Dispatcher на success делает `_spawn_flash(coord)`. **[Φ-5] [≤10 строк]** *(dispatcher ready; controller erase_floor → bool change in Φ-6)*
- [x] **T-060-28.** Реализовать `_handle_key(ke)` (см. plan §Φ-5.b code): Esc/Q/W/E/Tab/F1/?/1-9. Focus check через `_controller.is_text_focused()`. **[Φ-5] [≤50 строк]**
- [x] **T-060-29.** Расширить `_handle_mouse_button` для Shift+RMB cascade (см. plan §Φ-5.c). Один flash после успешного cascade. **[Φ-5] [≤15 строк net]**
- [x] **T-060-30.** Добавить helper `_spawn_flash(coord)` — обёртка `DeleteFlash.spawn_at`. **[Φ-5] [≤5 строк] (требует Φ-7.a)** *(stub no-op; body filled in Φ-7.a)*
- [x] **T-060-31.** В `editor_controller.gd` добавить `is_text_focused() -> bool` (см. plan §Φ-5.b risk anchor). **[Φ-5] [≤5 строк]**
- [ ] **T-060-32.** Smoke: Q/W/E переключают табы. Tab циклит. 1-9 выбирают первые 9 buttons активной палитры. F1 → controller вызывает `show_help()` (пока stub). Esc сбрасывает drag. Shift+RMB — cascade. Click в LineEdit (имя уровня) → Q НЕ переключает таб, вводится 'q'. **[Φ-5] [smoke]**

→ Commit: `feat(060): InputDispatcher per-layer + keyboard + cascade`.

---

## Φ-6. EditorController: public API + overlay wiring + autosave + handoff

- [x] **T-060-33.** Добавить @export'ы `objects_overlay_path`, `spawners_overlay_path`, `help_modal_path`. Резолвнуть в `_resolve_nodes`. **[Φ-6] [≤10 строк]** *(also added `confirm_modal_path` since prompt needs the modal)*
- [x] **T-060-34.** Реализовать mutation методы `paint_spawner`, `erase_spawner`, `paint_object`, `erase_object` (см. plan §Φ-6.c code). Каждый дёргает `_io.enqueue_autosave(_level)` после успеха. Overlays получают `refresh(...)` если их has_method. **[Φ-6] [≤100 строк]**
- [x] **T-060-35.** Реализовать `cascade_at(coord) -> bool` — комбинация всех трёх erase'ов (см. plan §Φ-6.c). Один enqueue_autosave. **[Φ-6] [≤25 строк]**
- [x] **T-060-36.** Реализовать helpers `notify_active_layer_changed(layer_id)`, `quick_select_in_active_palette(n)`, `show_help()`. **[Φ-6] [≤20 строк]**
- [x] **T-060-37.** Game Editor handoff: в `_ready` после `_wire_panels()` — `if ActiveLevel.has_queued()`: consume + `_io.load_from` + `_io.refresh_grid_from_level` + `_meta_panel.set_level_name` + `_check_multi_wave_warning`. **[Φ-6] [≤25 строк]** *(extracted to EditorStartup — F-060-IMPL-2)*
- [x] **T-060-38.** Autosave restore prompt: `_prompt_autosave_restore(age_sec)` через ConfirmModal child HUD (modal добавится в Φ-9.b). Если modal == null — silent clear_autosave. **[Φ-6] [≤30 строк] [R6: await process_frame перед .ask]** *(extracted to EditorStartup — F-060-IMPL-2)*
- [x] **T-060-39.** Multi-wave warning toast: `_check_multi_wave_warning` (см. plan §Φ-6.d). 4-секундный warn-toast если waves.size() > 1. **[Φ-6] [≤10 строк]** *(extracted to EditorStartup — F-060-IMPL-2)*
- [x] **T-060-40.** Заменить `_on_playtest_disabled` (toast «coming in 060») → `_on_playtest` (functional). Подключить через `_meta_panel.playtest_requested.connect(_on_playtest)`. **[Φ-6] [≤15 строк]**
- [x] **T-060-41.** Расширить `_on_exit` — если `ActiveGame.has_queued_for_editor()`: → `game_editor.tscn`, иначе `main_menu.tscn`. **[Φ-6] [≤10 строк]**
- [x] **T-060-42.** Подписаться `_meta_panel.playtest_requested` на `_on_playtest`. Удалить старый stub `_on_playtest_disabled`. Удалить loc-key `ui_level_editor_playtest_disabled_toast` (orphan, идёт в Φ-11). **[Φ-6] [≤5 строк]**
- [x] **T-060-43.** **Если controller > 300 строк** — extract `_prompt_autosave_restore` + `_check_multi_wave_warning` в EditorIO с callback'ами. Запасной план R1. **[Φ-6] [≤30 строк net, condicional]** *(extracted to NEW files level_mutations.gd + editor_startup.gd instead of EditorIO — F-060-IMPL-2 explains divergence from plan's EditorIO target. Controller fits at 269 / 300.)*
- [ ] **T-060-44.** Smoke: все 3 слоя paint/erase. Cascade. Save/Load. Game Editor → Edit → Exit → Game Editor. Playtest cycle. Autosave (закрыть без save → reopen → modal → restore работает). **[Φ-6] [smoke big]**

→ Commit: `feat(060): EditorController full API + overlay wiring + handoff cycles`.

---

## Φ-7. Visual effects

- [x] **T-060-45.** Создать `delete_flash.gd` (см. plan §Φ-7.a code). Static `spawn_at(parent, coord, grid)`. Tween fade-out 150ms. **[Φ-7] [≤40 строк]**
- [x] **T-060-46.** Создать `editor_help_modal.gd` + `editor_help_modal.tscn` (см. plan §Φ-7.b code). 10 строк шорткатов hard-coded с loc-keys (loc-keys в Φ-11). Esc/F1 закрывают. **[Φ-7] [≤80 строк]**
- [ ] **T-060-47.** Smoke: erase любого слоя → красный flash на 150ms. F1 → modal с таблицей. Esc/F1 закрывают. **[Φ-7] [smoke]**

→ Commit: `feat(060): DeleteFlash + EditorHelpModal`.

---

## Φ-8. Cross-refs to level_editor.tscn

- [x] **T-060-48.** В `game_editor_controller.gd:222` заменить `map_editor.tscn` → `level_editor.tscn`. **[Φ-8] [1 строка]**
- [x] **T-060-49.** В `pause_menu.gd:141` (`_on_back_to_editor`) заменить путь. **[Φ-8] [1 строка]**
- [x] **T-060-50.** В `godmode/godmode_input.gd:80` (back-to-editor branch) заменить путь. **[Φ-8] [1 строка]**
- [ ] **T-060-51.** Smoke: Game Editor → Edit (любая карта) → новый level editor с правильно загруженной картой. Playtest → ESC → Pause → Back to Editor → новый level editor с теми же изменениями. **[Φ-8] [smoke]**

→ Commit: `refactor(060): cross-refs map_editor.tscn → level_editor.tscn` (можно слить с Φ-10 в один коммит).

---

## Φ-9. hex_grid.tscn fix + level_editor.tscn updates

### Φ-9.a. hex_grid.tscn fix

- [ ] **T-060-52.** В `hex_grid.gd` заменить `@export var tile_map_layer/vfx_overlay: TileMapLayer` на `@onready var ... = $Terrain/$VFXOverlay`. **[Φ-9] [≤5 строк]**
- [ ] **T-060-53.** В `hex_grid.tscn` удалить строки 8-9 (`tile_map_layer = NodePath("Terrain")`, `vfx_overlay = NodePath("VFXOverlay")`). **[Φ-9] [≤2 строки]**
- [ ] **T-060-54.** В `editor_controller.gd._ready` удалить workaround (6 строк, см. plan §Φ-9.a). Оставить только `_grid.initialize()`. **[Φ-9] [≤5 строк net]**
- [ ] **T-060-55.** Smoke: открыть `level_editor.tscn` — нет error логов про `tile_map_layer is null`. Открыть `godmode.tscn` — то же самое. **[Φ-9] [smoke]**

### Φ-9.b. level_editor.tscn updates

- [x] **T-060-56.** В `level_editor.tscn` добавить:
  - `ObjectsOverlay` (Node2D, script `objects_overlay.gd`) — child HexGrid.
  - `SpawnersOverlay` (Node2D, script `spawners_overlay.gd`) — child HexGrid.
  - `ConfirmModal` (instance `scenes/ui/confirm_modal.tscn`) — child HUD.
  - `EditorHelpModal` (instance `editor_help_modal.tscn`) — child HUD.
  - Обновить @export пути LevelEditor: `objects_overlay_path`, `spawners_overlay_path`, `help_modal_path`. **[Φ-9] [.tscn правки]**
- [ ] **T-060-57.** Smoke: запустить level_editor.tscn — overlays резолвятся (если paint object → виден на сетке), modal'ы доступны. **[Φ-9] [smoke]**

→ Commit: `fix(060): hex_grid.tscn binding + level_editor.tscn overlays/modals`.

---

## Φ-10. Удаление legacy + main_menu cross-refs

- [ ] **T-060-58.** Pre-flight grep: для каждого из 12 файлов на удаление сделать grep по `*.gd` и `*.tscn`. Все matches должны быть либо в файлах которые тоже удаляются, либо в `.git/`. Спорные — обсудить перед удалением. **[Φ-10] [check]**
- [ ] **T-060-59.** `git rm` 12 файлов:
  - `scenes/dev/map_editor.tscn`
  - `scripts/presentation/dev/map_editor_controller.gd`
  - `scripts/presentation/dev/floor_palette_panel.gd`
  - `scripts/presentation/dev/object_palette_panel.gd`
  - `scripts/presentation/dev/tool_panel.gd`
  - `scripts/presentation/dev/paint_preview.gd`
  - `scripts/presentation/dev/wave_panel.gd`
  - `scripts/presentation/dev/wave_diff_overlay.gd`
  - `scripts/presentation/dev/dialogue_trigger_panel.gd`
  - `scripts/presentation/dev/hotkey_overlay.gd`
  - `scripts/presentation/dev/delete_highlight.gd`
  - `scripts/presentation/dev/level_history.gd`. **[Φ-10] [git rm]**
- [ ] **T-060-60.** В `main_menu.gd` удалить `_map_editor_btn` field, `_on_map_editor` handler, и .connect(). Переименовать `_level_editor_new_btn` → `_level_editor_btn` (3 места). Переименовать `_on_level_editor_new` → `_on_level_editor`. Убрать упоминания `_map_editor_btn` в array reference на line 114-115. **[Φ-10] [≤15 строк net]**
- [ ] **T-060-61.** В `main_menu.tscn` удалить node `MapEditorButton`. Переименовать `LevelEditorNewButton` → `LevelEditorButton`. Обновить text key на `ui_main_menu_level_editor_button_text`. **[Φ-10] [.tscn правки]**
- [ ] **T-060-62.** Smoke: `grep -rln "map_editor" --include="*.gd" --include="*.tscn" .` — должно вернуть пусто (вне docs/specs/). Открыть main_menu — единственная кнопка «Level Editor». Проект компилируется. **[Φ-10] [smoke]**

→ Commit: `chore(060): delete legacy MapEditor + cross-refs cleanup` (atomically, single commit per AC25).

---

## Φ-11. Loc-keys cleanup + new keys

- [ ] **T-060-63.** Сгенерировать suspect orphan list через grep (см. plan §Φ-11). Verify each — действительно ли в живом коде нет references. Сохранить итоговый ORPHAN-список. **[Φ-11] [check]**
- [ ] **T-060-64.** Удалить orphan ключи из `data/localization/en.json` и `ru.json`. Убедиться что JSON остаётся валидным (json validate). Не трогать `_sources.json` если оно автоген. **[Φ-11] [bulk delete]**
- [ ] **T-060-65.** Добавить новые ключи в en.json и ru.json (parallel update — paired diff): tabs, palette labels, multi-wave warning, autosave restore prompt, help modal shortcuts. См. plan §Φ-11 таблица. **[Φ-11] [~25 ключей × 2]**
- [ ] **T-060-66.** Переименовать `ui_main_menu_level_editor_new_button_text` → `ui_main_menu_level_editor_button_text` в обоих файлах. **[Φ-11] [2 строки]**
- [ ] **T-060-67.** Smoke: переключить язык Ru/En в редакторе, все labels читаются (не сырые ключи в UI). Help modal обоих языков. Multi-wave warning toast обоих языков. **[Φ-11] [smoke]**

→ Commit: `chore(060): localization keys — orphan cleanup + new keys`.

---

## Φ-12. Smoke prelude + PR

- [ ] **T-060-68.** Полный manual smoke по checklist'у F-060-9 (см. spec.md §7). Каждый пункт — pass/fail. Если fail — back-fix в той же ветке (новые коммиты). **[Φ-12] [big smoke]**
- [ ] **T-060-69.** Final size check: `wc -l` всех новых/изменённых файлов. Hard cap: editor_controller ≤300 (AC33). Soft caps: editor_io ≤200 (AC34), input_dispatcher ≤220 (AC35), layers_model ≤120 (AC36). Если cap нарушен — finding или extract. **[Φ-12] [check]**
- [ ] **T-060-70.** Push, открыть PR на staging. PR description: ссылка на spec.md / plan.md, summary изменений, F-060-* список, manual smoke checklist для ревьюера. PR URL: https://github.com/TortikP/GameJamProject/pull/new/andrey/060-level-editor-layers (если spec/plan/tasks уже запушены — иначе compare URL). **[Φ-12] [PR]**

---

## Sequencing visualization

```
[Φ-1: framework] ──┐
                   ├─→ [Φ-3: layers/panel migration] ─→ [Φ-4: palettes] ─→ [Φ-5: dispatcher]
[Φ-2: io extract] ─┘                                                              │
                                                                                   ▼
                                          [Φ-7: VFX] ←─ [Φ-6: controller full API]
                                                │
                                                ▼
[Φ-8: cross-refs] ─→ [Φ-9: hex_grid + scene] ─→ [Φ-10: delete legacy] ─→ [Φ-11: loc] ─→ [Φ-12: smoke + PR]
```

Φ-1 и Φ-2 параллельны. Остальные строго по порядку.

**Estimated:** 70 атомарных задач, ~10-12 коммитов, 2-4 дня одного человека плотно. Может растянуться если Φ-5/Φ-6 ловят неожиданные баги (overlay refresh API, ButtonGroup quirks).

---

# 🎯 HANDOFF в следующий чат (имплементация)

**Спек/план/таски лежат в репо** (ветка `andrey/060-level-editor-layers`):
- `specs/060-level-editor-layers/spec.md` — что и зачем (37 AC, 13 Q-резолвов, 9 findings).
- `specs/060-level-editor-layers/plan.md` — как именно (12 фаз, код-snippet'ы, 8 risk anchors R1-R8).
- `specs/060-level-editor-layers/tasks.md` — этот файл, 70 T-060-* задач в порядке исполнения.

**Старт:** `git checkout andrey/060-level-editor-layers && git pull`. Затем читать `spec.md` → `plan.md` → начинать с T-060-1 (Φ-1, framework patch — изолированно). Иди по T-задачам в порядке, отмечай галочками, коммить пер-Φ.

**Главные ловушки** (которые стоят отдельного внимания):
- **R1.** EditorController не должен превышать 300 строк после Φ-6. T-060-43 — fallback extraction если упёрлось.
- **R3.** ButtonGroup state при switch'е таба может потеряться (AC6 smoke в T-060-21).
- **R5.** Autosave debounce не fires во время длинного drag — surface как finding если важно.
- **F-059-IMPL-4** (hex_grid.tscn): фикс через `@onready` (Φ-9.a), убирать workaround в editor_controller.

**Ничего не делать без спека.** Если на имплементации всплывает unknown — surface как finding в `findings.md` рядом со spec.md. Не править спек на ходу.
