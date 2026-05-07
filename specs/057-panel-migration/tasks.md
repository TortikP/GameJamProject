# 057 — Tasks

Спек: [`spec.md`](./spec.md). Plan: [`plan.md`](./plan.md).

## Code (Claude в impl-команде)

### Pre-check

- [ ] **T000.** Подтвердить состояние перед началом. Пустые ответы — go-signal:
  - `find scripts/ -name "draggable_panel*"` (должно быть пусто — DraggablePanel удалён в Phase 7).
  - `grep -rln "extends.*PanelContainer" scripts/presentation/dev/floor_palette_panel.gd scripts/presentation/dev/object_palette_panel.gd scripts/presentation/dev/tool_panel.gd scripts/presentation/dev/level_meta_panel.gd scripts/presentation/dev/dialogue_trigger_panel.gd` (5 file matches — все ещё на старом fundament'е).
  - `cat scenes/ui/panels/base_panel.tscn | grep -c "node name="` (≥ 5 — base_panel.tscn существует и непустой).

### Per-panel migration

- [ ] **T001.** `scripts/presentation/dev/floor_palette_panel.gd` — миграция на BasePanel. См. [plan.md §Pattern per panel](./plan.md):
  - [ ] Заменить `extends PanelContainer` → `extends BasePanel`.
  - [ ] Удалить `const DraggablePanel = preload(...)`.
  - [ ] В `_ready()` удалить `add_theme_stylebox_override("panel", ...)` и `_install_drag(_title_label)` вызов. Оставить вызов `_build_ui()` или переименовать в `_build_body()` (по вкусу, но консистентно).
  - [ ] В `_build_ui()` — все `add_child(x)` направлены в `var _body := get_body_container(); _body.add_child(x)`. Если в коде создаётся локальный `_title_label` для drag-handle — удалить (header BasePanel'а его уже показывает).
  - [ ] Удалить функцию `_install_drag()` целиком.
  - [ ] Удалить поле `var _title_label: Label`, если оно осталось без употребления.
  - [ ] Public API не трогать: signals `tile_picked`, `erase_picked`, `tileset_changed`, `replace_all_requested` остаются. Методы `setup`, `select_tile`, `select_nth` остаются. (AC4)
  - [ ] Если в body был добавлен явный header-row с кнопками — переедет в body как первая строка (см. F-057-3 в spec.md). Если по факту шапка чистая — finding не нужен.
  - [ ] Проверка после правки: `grep -nE "DraggablePanel|_install_drag|extends PanelContainer" scripts/presentation/dev/floor_palette_panel.gd` пусто.

- [ ] **T002.** `scripts/presentation/dev/object_palette_panel.gd` — миграция. Same pattern as T001:
  - [ ] `extends PanelContainer` → `extends BasePanel`, удалить DraggablePanel preload, `_install_drag()` функцию, theme override в `_ready()`.
  - [ ] body building через `get_body_container()`.
  - [ ] Public API сохранить: signals `object_picked`, `spawner_picked`. Методы `setup` (с `registry: TileObjectRegistry`), `select_spawner`, `select_object`, `select_nth`.
  - [ ] Surface: эта панель в коде объединяет objects и spawners в один TabContainer (по чтению spec'а). После миграции внутренний TabContainer остаётся в body, на header это никак не влияет — этот таб НЕ имеет отношения к будущему tear-off палитр (Spec 059), не путать.
  - [ ] Проверка после правки: тот же grep.

- [ ] **T003.** `scripts/presentation/dev/tool_panel.gd` — миграция. Same pattern:
  - [ ] `extends PanelContainer` → `extends BasePanel`, остальные удаления как в T001.
  - [ ] Public API сохранить: signals `tool_changed`, `brush_size_changed`. Метод `setup`.
  - [ ] Тут панель самая маленькая (153 строки) — миграция должна занять минут 15. Если занимает больше часа — что-то идёт не по плану, паузим и сообщаем Андрею.
  - [ ] Проверка после правки: тот же grep.

- [ ] **T004.** `scripts/presentation/dev/level_meta_panel.gd` — миграция. Same pattern:
  - [ ] `extends PanelContainer` → `extends BasePanel`, остальные удаления.
  - [ ] Public API сохранить: signals `save_requested`, `load_requested`, `playtest_requested`, `exit_requested`, `name_changed`. Методы `setup`, `set_level_name`, `set_dirty`.
  - [ ] У этой панели Save/Load/Playtest/Exit кнопки могли быть в header-row (по чтению кода — подтвердить при имплементации). Если да — переедут в body как первая строка `HBoxContainer`. Header BasePanel остаётся унифицированным (только title + lock + collapse).
  - [ ] FileDialog при load_requested — `level_meta_panel.gd:117` — НЕ ТРОГАЕМ. Это F-054-1 finding из спека 056, отдельная история.
  - [ ] Проверка после правки: тот же grep.

- [ ] **T005.** `scripts/presentation/dev/dialogue_trigger_panel.gd` + `scenes/dev/dialogue_trigger_panel.tscn` — миграция .gd + re-create .tscn:
  - [ ] **.gd:** `extends PanelContainer` → `extends BasePanel`, удалить `DraggablePanelScript = preload(...)` и `_ready()` `add_theme_stylebox_override` + `dragger.setup(self, _title_label)`. body building через `get_body_container()`.
  - [ ] Public API сохранить: signals `trigger_created`, `trigger_updated`, `trigger_deleted`, `trigger_selected`. Методы `bind_level`, `select_trigger`.
  - [ ] CRUD кнопки (Add/Delete/Edit) — переедут в body как первая строка. Header унифицированный.
  - [ ] **.tscn:** удалить `scenes/dev/dialogue_trigger_panel.tscn` целиком. Создать новый файл с тем же UID `uid://dialogue_trigger_panel`. Содержимое — см. [plan.md §dialogue_trigger_panel.tscn re-create](./plan.md). Способ создания: либо в Godot UI (Scene → New Inherited Scene → выбрать base_panel.tscn → attach script → set exports → save), либо вручную написать .tscn по target шаблону. Если ручной путь — `format=3 load_steps=3`, ext_resource на base_panel.tscn (id="1_bp") + script (id="2_dtp"), root node `instance=ExtResource("1_bp")`, экспорты `panel_id = &"dialogue_trigger"` / `panel_title_key = &"ui_dialogue_trigger_title"` / `panel_title_fallback = "Триггеры диалогов"` / `min_panel_size = Vector2(220, 200)`.
  - [ ] Проверка после правки: `grep DraggablePanel scenes/dev/dialogue_trigger_panel.tscn scripts/presentation/dev/dialogue_trigger_panel.gd` пусто. `wc -l scenes/dev/dialogue_trigger_panel.tscn` ≤ 12.

### Map editor scene rewire

- [ ] **T006.** `scenes/dev/map_editor.tscn` — конвертировать 5 panel nodes из `[type="PanelContainer"]` в `[instance=base_panel.tscn]`:
  - [ ] Добавить ext_resource на `res://scenes/ui/panels/base_panel.tscn` в начале файла (одно дополнение, переиспользуется для всех 5 instances).
  - [ ] Для каждой из `LevelMetaPanel`, `FloorPalettePanel`, `ObjectPalettePanel`, `ToolPanel`, `DialogueTriggerPanel`:
    - [ ] Изменить `[node name="X" type="PanelContainer" parent="HUD"]` → `[node name="X" parent="HUD" instance=ExtResource("<base_panel_id>")]`.
    - [ ] Сохранить `script = ExtResource(<panel_script_id>)` (script должен указывать на соответствующий .gd, теперь extends BasePanel).
    - [ ] Сохранить anchor_*, offset_*, grow_* строки 1:1 — см. таблицу [plan.md §Per-panel экспорты](./plan.md).
    - [ ] Добавить экспорты BasePanel'а: `panel_id`, `panel_title_key`, `panel_title_fallback`, `min_panel_size`. Конкретные значения — таблица [plan.md §Per-panel экспорты](./plan.md).
    - [ ] Если в исходной ноде были `theme_override_*` или `mouse_filter` overrides — оценить нужность; вероятно уносим (BasePanel сам красится через UiTheme). Surface при выполнении.
  - [ ] **DialogueTriggerPanel в map_editor.tscn** — этот node сейчас отдельная instance от старого `dialogue_trigger_panel.tscn`. После T005 этот файл — instance от base_panel.tscn с прикреплённым DTP script. Узел в map_editor.tscn остаётся `instance=` от `dialogue_trigger_panel.tscn` (НЕ от base_panel.tscn напрямую) — это композиция: map_editor → dialogue_trigger_panel.tscn → base_panel.tscn. Экспорты `panel_id` etc. уже выставлены в самом dialogue_trigger_panel.tscn, в map_editor.tscn их дублировать не нужно — только anchor/offset.
  - [ ] Проверка после правки: открыть `scenes/dev/map_editor.tscn` в Godot — нет parser errors, все 5 панелей видны в Inspector с экспортами BasePanel'а доступными.

### Smoke

- [ ] **T007.** Smoke: parse + visibility (AC1, AC2). Из главного меню — Map Editor → New Level → редактор открывается, все 5 панелей видны в текущих позициях, у каждой в шапке title + lock + collapse, body содержит ожидаемое.

- [ ] **T008.** Smoke: drag/resize/collapse/lock (AC3). Для каждой из 5 панелей:
  - [ ] Drag за header → панель двигается, не выходит за viewport (clamps работают).
  - [ ] Resize за угол/край → размер меняется до min_panel_size.
  - [ ] Collapse → body скрывается, остаётся только header.
  - [ ] Lock → drag и resize заблокированы, иконка замочка переключилась.

- [ ] **T009.** Smoke: persistence (AC6). Drag floor_palette в новое место, resize, collapse, exit редактор → main menu → re-enter. Floor palette на новом месте, в том же размере, collapsed. `cat user://layouts.cfg` (на macOS `~/Library/Application Support/Godot/app_userdata/<project>/layouts.cfg`, на Linux `~/.local/share/godot/app_userdata/<project>/layouts.cfg`) — секция `[scenes/dev/map_editor.tscn::floor_palette]` существует со значениями.

- [ ] **T010.** Smoke: save/load roundtrip (AC5). New level → выбрать tile → клик по гексу → object → клик → set name "smoke_057" → save (через level_meta panel) → файл записан в `user://maps/` или `data/maps/`. Закрыть редактор. Открыть тот же файл → tile и object на тех же координатах, name "smoke_057".

- [ ] **T011.** Smoke: dialogue_triggers CRUD (AC7). Загрузить существующий `data/maps/level_*.json` со существующими триггерами → triggers видны в DialogueTriggerPanel (если в этом уровне есть триггеры). Выбрать → отредактировать поле (например trigger_name) → save → JSON `before/after diff` совпадает с ожидаемой правкой, никаких побочных полей не изменилось.

- [ ] **T012.** Smoke: public API не сломан (AC4). Открыть Godot Output / Debug consol во время smoke T007-T011 → нет error'ов про missing signals/methods, нет warning'ов «property X not found on Y». `MapEditorController` не патчился — если runtime ругается на эту связку, смотреть какой именно сигнал/метод не подцепился.

### Cleanup verification

- [ ] **T013.** Dead code grep (AC8):
  - [ ] `grep -rn "DraggablePanel\|draggable_panel" scripts/ scenes/` возвращает пусто.
  - [ ] `grep -rnE "extends PanelContainer" scripts/presentation/dev/(floor_palette|object_palette|tool|level_meta|dialogue_trigger)_panel.gd` возвращает пусто.
  - [ ] `find scripts/ -name "draggable_panel*"` возвращает пусто.
  - [ ] Если что-то нашлось — finding в новом `findings.md` файле спека, разбираемся точечно.

### Non-code

- [ ] **T014.** Если по ходу T001-T012 всплыли неожиданности (BasePanel не покрывает какой-то use case, F-057-3 нашло реальный visual loss, R1-R4 выстрелил) — `specs/057-panel-migration/findings.md` создаётся, в нём фиксируются проблемы с конкретикой. Если ничего не всплыло — finding файл не создаётся.

- [ ] **T015.** Push ветки + PR. После всех T001-T014 done и smoke зелёный:
  - [ ] `git push -u origin andrey/057-panel-migration`.
  - [ ] PR-creation URL из stderr — отдать Андрею.
  - [ ] PR title: `057 — Panel migration to BasePanel`.
  - [ ] PR body: чек-лист AC1-AC8 с подтверждениями + ссылки на spec/plan/tasks.

## Open questions during impl

Если возникают новые вопросы по ходу T001-T013 — фиксируются как Q-057-N+ в `spec.md` §Resolved decisions с пометкой `OPEN`, спек паузится до резолва Андреем. Текущие закрытые вопросы Q-057-1..7 не пересматриваются без явного повода.
