# 058 — Tasks

Спек: [`spec.md`](./spec.md). Plan: [`plan.md`](./plan.md).

## Code (Claude в impl-команде)

### Pre-check

- [ ] **T000.** Подтвердить состояние перед началом. Все условия должны выполниться:
  - `git log --oneline -1 staging` показывает merge коммит спека 057 (panel migration to BasePanel).
  - `cat scenes/ui/panels/base_panel.tscn | grep -c "node name="` ≥ 5 — base_panel.tscn существует и непустой.
  - `wc -l scripts/presentation/ui_panels/internal/panel_drag_handler.gd` ≈ 89 строк (тот baseline, к которому применяем diff из плана).
  - `find scripts/presentation/ui_panels -name "panel_tab_bar.gd"` пусто (не пытаемся переписать существующий файл).
  - `find scripts/presentation/ui_panels -name "tabbed_base_panel.gd"` пусто.
  - `find scenes/ui/panels -name "tabbed_base_panel.tscn"` пусто.
  - `find scenes/ui/panels -name "tabbed_panel_demo*"` пусто.

### Framework extensions

- [ ] **T001.** `scripts/presentation/ui_panels/internal/panel_drag_handler.gd` — расширение. См. [plan.md §Step 1](./plan.md):
  - [ ] Добавить `signal drag_ended(release_pos: Vector2)` в начале файла после `extends Node`.
  - [ ] Добавить публичный метод `is_dragging() -> bool` возвращающий `_is_dragging`.
  - [ ] Добавить публичный метод `begin_drag_at(global_pos: Vector2) -> void` — idempotent: если уже drag — return. Если `not _base_panel.is_draggable() or _base_panel.is_locked()` — return. Иначе `_begin_drag(global_pos)`.
  - [ ] В `_input(event)` в ветке LMB-release добавить `drag_ended.emit(mb.global_position)` сразу после `_is_dragging = false`.
  - [ ] **Mitigation для R1** (см. plan.md §Risks): в `begin_drag_at` ПОСЛЕ `_begin_drag(global_pos)` — синхронно вызвать `_do_drag(global_pos)`, чтобы panel «снэплась» к курсору без ожидания первого motion event. Если на smoke (T010) это создаёт проблемы — surface как finding и убрать.
  - [ ] Проверка после правки: `grep -nE "signal drag_ended|begin_drag_at|is_dragging" scripts/presentation/ui_panels/internal/panel_drag_handler.gd` находит все три добавления. `wc -l` файла ~100-110 строк.

- [ ] **T002.** `scripts/presentation/ui_panels/base_panel.gd` — добавить proxy метод `start_drag_at`. См. [plan.md §Step 2](./plan.md):
  - [ ] Добавить публичный метод `start_drag_at(global_pos: Vector2) -> void`.
  - [ ] Тело: `if _drag_handler != null: _drag_handler.begin_drag_at(global_pos) else: push_warning("[BasePanel] start_drag_at called on '%s' with no drag handler" % String(panel_id))`.
  - [ ] Размещение: рядом с `toggle_lock`/`toggle_collapse` (другие публичные toggle-методы).
  - [ ] Docstring (`##`): «Proxy to PanelDragHandler.begin_drag_at — used by PanelTabBar for drag handoff during tab tear-off (no LMB-release event in between).»
  - [ ] Проверка после правки: `grep -n "start_drag_at" scripts/presentation/ui_panels/base_panel.gd` находит метод.

### Localization

- [ ] **T003.** Добавить loc key `ui_tabs_all_detached_hint` в данные локализации. См. [plan.md §Step 3](./plan.md):
  - [ ] Сначала проверить актуальный путь и формат: `find data/localization -name "*.json"` → ожидаем `en.json` и `ru.json` (или эквивалент). Если структура другая (вложенные секции, CSV, другой layout) — surface и адаптировать.
  - [ ] Добавить в en: `"ui_tabs_all_detached_hint": "(All tabs detached — drag a detached panel back here)"`.
  - [ ] Добавить в ru: `"ui_tabs_all_detached_hint": "(Все табы оторваны — перетащите detached-панель обратно сюда)"`.
  - [ ] Проверка после правки: `grep "ui_tabs_all_detached_hint" data/localization/*.json` находит обе записи.

### New module: PanelTabBar

- [ ] **T004.** Создать `scripts/presentation/ui_panels/internal/panel_tab_bar.gd`. См. [plan.md §Step 4](./plan.md):
  - [ ] `class_name PanelTabBar`, `extends HBoxContainer`.
  - [ ] Константы: `META_ORIGIN_PANEL_ID := "__origin_panel_id"`, `META_ORIGIN_TAB_ID := "__origin_tab_id"`, `META_TAB_TITLE_KEY := "tab_title_key"`, `META_TAB_TITLE_FALLBACK := "tab_title_fallback"`, `VERTICAL_DRAG_THRESHOLD := 30.0`.
  - [ ] State fields: `_tabbed_panel: TabbedBasePanel`, `_tabs: Array[Dictionary]`, `_active_tab_id: StringName`, `_dragging_tab_id: StringName`, `_press_global_pos: Vector2`, `_floating_panels: Array[BasePanel]`, `_placeholder_label: Label`.
  - [ ] Public `setup(tabbed_panel: TabbedBasePanel) -> void` — единственная entry-point точка из TabbedBasePanel; вызывает в порядке: `_build_placeholder()` → `_discover_and_register_tabs()` → `_restore_detached_from_persistence()` → `_set_active(_first_attached_tab_id())` → `_refresh_placeholder_visibility()`.
  - [ ] Private `_build_placeholder()` — создаёт `Label`, текст из `tr(&"ui_tabs_all_detached_hint")`, изначально hidden.
  - [ ] Private `_discover_and_register_tabs()` — итерирует `_tabbed_panel.get_body_container().get_children()`, для каждого Control: tab_id = `StringName(child.name)`, title_key из meta или fallback на `child.name`, регистрирует в `_tabs` с button. Children без Control-типа игнорирует.
  - [ ] Private `_restore_detached_from_persistence()` — для каждой обнаруженной таб: вычисляет `synthetic_id = _synthetic_panel_id(tab_id)` и section_key, проверяет `ConfigFile.has_section(section_key)`. Если есть — `_detach_tab_silent(tab_id, true)` (spawn detached в saved позиции, без drag handoff).
  - [ ] Private `_make_tab_button(tab) -> Button` — создаёт Button с UiTheme styling (см. как стилизованы другие BasePanel header-кнопки), `mouse_filter = MOUSE_FILTER_STOP`. Connect `gui_input` к `_on_tab_button_input.bind(tab.tab_id)`.
  - [ ] Private `_on_tab_button_input(event, tab_id)` — обработка LMB-press: запоминает `_press_global_pos`, ставит `_dragging_tab_id = tab_id`. На LMB-release БЕЗ движения за порог — это click → `_set_active(tab_id)`, сбрасывает `_dragging_tab_id`.
  - [ ] Private `_input(event)` — глобальный listener пока `_dragging_tab_id != &""`. На motion: проверяет threshold (`>30px вертикально OR курсор вне `get_global_rect()` PanelTabBar'а`). Если перешли порог — вызывает `_detach_tab_active_drag(_dragging_tab_id, mouse_global)` и сбрасывает `_dragging_tab_id`. На LMB-release без detach — также сбрасывает `_dragging_tab_id` (это был не-click no-op).
  - [ ] Private `_detach_tab_active_drag(tab_id, mouse_global)` — full pipeline (см. plan.md §`_normalize_anchors_to_top_left для detached`):
    1. **R5/R6 guard**: `if _tabbed_panel.is_collapsed() or _tabbed_panel.is_locked(): return`.
    2. Загрузить `base_panel.tscn` через `preload(...)`.
    3. `var detached := scene.instantiate() as BasePanel`.
    4. Set exports: `panel_id = _synthetic_panel_id(tab_id)`, `panel_title_key = tab.title_key`, `panel_title_fallback = tab.title_fallback`, `min_panel_size` из родителя или фиксированное значение (например `Vector2(180, 100)`).
    5. `detached.set_meta(META_ORIGIN_PANEL_ID, _tabbed_panel.panel_id)`, `detached.set_meta(META_ORIGIN_TAB_ID, tab_id)`.
    6. `_tabbed_panel.get_parent().add_child(detached)` — `_ready` нормализует anchors, persistence читает synthetic_id (чисто, потому что synthetic section не существует на этой ветке кода).
    7. Reparent content: `body_source := _tabbed_panel.get_body_container()`, `body_source.remove_child(content_node)`, `detached.get_body_container().add_child(content_node)`.
    8. `detached.position = mouse_global - Vector2(40, BasePanel.CORNER_SIZE / 2)` (курсор над future header).
    9. `detached.start_drag_at(mouse_global)` — handoff (R1 mitigation в T001 даёт sync snap-to-cursor).
    10. Connect: `detached._drag_handler.drag_ended.connect(_on_floating_drag_ended.bind(detached))`.
    11. `_floating_panels.append(detached)`. Удалить tab из `_tabs`. Удалить tab-button из себя. `_set_active(_first_attached_tab_id())`. `_refresh_placeholder_visibility()`.
  - [ ] Private `_detach_tab_silent(tab_id, restore_layout)` — версия без drag handoff (используется при load из persistence). Шаги 1-7 + connect drag_ended (10) + add to _floating_panels (11) — но без steps 8-9 (position и handoff). Persistence сама уже выставила сохранённую position в шаге 6 (`_ready` triggers `_setup_persistence` → `load_layout`).
  - [ ] Private `_on_floating_drag_ended(panel: BasePanel, release_pos: Vector2)` — проверяет `if get_global_rect().has_point(release_pos)`: → `_reattach(panel)`. Иначе — no-op.
  - [ ] Private `_reattach(panel)` — обратный pipeline:
    1. Прочитать `tab_id := panel.get_meta(META_ORIGIN_TAB_ID, &"")`.
    2. Найти исходный tab record по tab_id (нужно держать sparse список даже для detached tabs, чтобы знать где их content-node «должен» жить — fallback: использовать `panel.get_body_container().get_child(0)` как content).
    3. Reparent content из `panel.get_body_container()` обратно в `_tabbed_panel.get_body_container()`.
    4. Восстановить tab record в `_tabs` + создать кнопку через `_make_tab_button` + `add_child` button (в правильную позицию — попытаться восстановить порядок; если сложно — append в конец, finding F-058-tab-order).
    5. **CRITICAL ORDER (R4)**: ДО `queue_free` — `_erase_layout_section(section_key)` для synthetic_id. Иначе `panel.tree_exiting` re-сохранит section через PanelPersistence._flush_save.
    6. `_floating_panels.erase(panel)`.
    7. `panel.queue_free()`.
    8. `_set_active(tab_id)`. `_refresh_placeholder_visibility()`.
  - [ ] Private `_set_active(tab_id)` — для каждого attached tab control в BodyContainer: `tab_control.visible = (tab_id == tab.tab_id)`. Highlight active tab-button (через `add_theme_stylebox_override` или toggle pressed state).
  - [ ] Private `_refresh_placeholder_visibility()` — `_placeholder_label.visible = (_count_attached_tabs() == 0)`.
  - [ ] Private `_synthetic_panel_id(tab_id) -> StringName` — `return StringName("%s__%s__detached" % [String(_tabbed_panel.panel_id), String(tab_id)])`.
  - [ ] Private `_layout_section_key(synthetic_id) -> String` — replicates PanelPersistence._compute_section_key: scope = `_tabbed_panel.persistence_scope_override` если задан, иначе walk up parent дерево пока не найдён ancestor с `scene_file_path`. Возвращает `"%s::%s" % [scope, synthetic_id]`.
  - [ ] Private `_erase_layout_section(section_key)` — `var cfg := ConfigFile.new(); cfg.load("user://layouts.cfg")` (ignore err — файла может не быть); `cfg.erase_section(section_key)`; `cfg.save("user://layouts.cfg")`.
  - [ ] Public `register_tab(content: Control)` — runtime API из TabbedBasePanel.add_tab. Регистрирует node как tab, создаёт button.
  - [ ] Public `unregister_tab(tab_id: StringName)` — runtime API из TabbedBasePanel.remove_tab. Удаляет tab, button, и detached panel если есть.
  - [ ] Public `get_active_tab_id() -> StringName` — getter.
  - [ ] Comment-block в начале файла: документирует convention `__origin_panel_id`/`__origin_tab_id` meta keys (per Q-058-7 решение в spec.md), и convention что `panel_id`/`tab_id` не должны содержать `__` (per R8 в plan.md).
  - [ ] Проверка после правки: `wc -l scripts/presentation/ui_panels/internal/panel_tab_bar.gd` — целевой ~250 строк (если сильно меньше — что-то пропущено; если сильно больше — surface). `grep -c "^func " scripts/presentation/ui_panels/internal/panel_tab_bar.gd` — должно быть около 17-19 функций.

### New module: TabbedBasePanel

- [ ] **T005.** Создать `scripts/presentation/ui_panels/tabbed_base_panel.gd`. См. [plan.md §Step 5](./plan.md):
  - [ ] `class_name TabbedBasePanel`, `extends BasePanel`.
  - [ ] `const PANEL_TAB_BAR_SCRIPT := preload("res://scripts/presentation/ui_panels/internal/panel_tab_bar.gd")`.
  - [ ] Field `var _tab_bar: PanelTabBar`.
  - [ ] `func _ready() -> void:` — **CRITICAL** сначала `super._ready()` (per CLAUDE.md trap row), потом `_setup_tab_bar()`.
  - [ ] Private `_setup_tab_bar()`:
    - `if _title_label != null: _title_label.visible = false`.
    - `_tab_bar = PanelTabBar.new()`.
    - `_tab_bar.name = "TabBar"`.
    - `_tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL`.
    - `_tab_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL`.
    - `_header_row.add_child(_tab_bar)`.
    - `_header_row.move_child(_tab_bar, 0)` (перед LockButton/CollapseButton/RightSpacer).
    - `_tab_bar.setup(self)`.
  - [ ] Public `add_tab(content: Control, tab_id: StringName, title_key: StringName = &"", title_fallback: String = "")`:
    - Если `not title_key.is_empty()`: `content.set_meta(PanelTabBar.META_TAB_TITLE_KEY, title_key)`.
    - Если `not title_fallback.is_empty()`: `content.set_meta(PanelTabBar.META_TAB_TITLE_FALLBACK, title_fallback)`.
    - `content.name = String(tab_id)`.
    - `_body_container.add_child(content)`.
    - `_tab_bar.register_tab(content)`.
  - [ ] Public `remove_tab(tab_id: StringName)` — `_tab_bar.unregister_tab(tab_id)`.
  - [ ] Public `get_active_tab_id() -> StringName` — `return _tab_bar.get_active_tab_id()`.
  - [ ] Проверка после правки: `wc -l scripts/presentation/ui_panels/tabbed_base_panel.gd` ~50-80 строк. `grep "super._ready" scripts/presentation/ui_panels/tabbed_base_panel.gd` находит вызов.

### New scene: tabbed_base_panel.tscn

- [ ] **T006.** Создать `scenes/ui/panels/tabbed_base_panel.tscn`. См. [plan.md §Step 6](./plan.md):
  - [ ] **Подход по умолчанию (берём «пустой inherited»)**: Inherited Scene from `base_panel.tscn` БЕЗ override на TitleLabel.visible. Все runtime-правки делает `_setup_tab_bar()`. Минимизирует риск Inherited Scene quirks (R7).
  - [ ] Способ создания: либо в Godot UI (Scene → New Inherited Scene → выбрать `base_panel.tscn` → attach `tabbed_base_panel.gd` script на корневой ноде → save). Либо вручную:
    ```
    [gd_scene format=3 load_steps=2 inherits="res://scenes/ui/panels/base_panel.tscn"]
    [ext_resource type="Script" path="res://scripts/presentation/ui_panels/tabbed_base_panel.gd" id="1_tbp"]
    [node name="BasePanel" parent="." instance=...]
    script = ExtResource("1_tbp")
    ```
    Проверить точный синтаксис на работающей Inherited Scene в проекте (например, `dialogue_trigger_panel.tscn` после спека 057).
  - [ ] **Fallback (R7 материализуется)**: если Inherited Scene не работает с runtime script attach в Godot 4.6 — pure-script approach: создать обычный (не-inherited) `tabbed_base_panel.tscn` с `[node name="BasePanel" instance=ExtResource("base_panel.tscn") script=ExtResource("tabbed_base_panel.gd")]`. Surface при имплементации.
  - [ ] Проверка после правки: открыть `tabbed_base_panel.tscn` в Godot — нет parser errors, root node имеет script `tabbed_base_panel.gd`, при run сцены `_setup_tab_bar` отрабатывает.

### Demo scene

- [ ] **T007.** Создать `scenes/ui/panels/tabbed_panel_demo.tscn` + `scripts/presentation/ui_panels/tabbed_panel_demo.gd`. См. [plan.md §Step 7](./plan.md):
  - [ ] `tabbed_panel_demo.gd` — `extends Control`, пустой (только `func _ready() -> void:` no-op или placeholder log).
  - [ ] `tabbed_panel_demo.tscn` — Control root с background-цветом для контраста. В нём:
    - **TabbedBasePanel #1** в центре, exports: `panel_id = &"demo_tabbed_main"`, `panel_title_key = &""` (не используется), `min_panel_size = Vector2(280, 200)`. В body 3 children:
      - `TabA` — Label с text "I am tab A", `set_meta("tab_title_fallback", "Tab A")`.
      - `TabB` — VBoxContainer с парой Buttons (например "Action 1", "Action 2"), `set_meta("tab_title_fallback", "Tab B")`.
      - `TabC` — Label с text "Empty tab C", `set_meta("tab_title_fallback", "Tab C")`.
    - **TabbedBasePanel #2** (для AC6 smoke), смещённая в сторону. exports: `panel_id = &"demo_tabbed_other"`. 1-2 dummy таба чтобы был tab-bar для drop-теста.
    - **TabbedBasePanel #3** (для AC10 smoke) с не-default anchors (например anchor_top=0.5, anchor_left=0.5, grow_direction=GROW_DIRECTION_BOTH = 2 = BOTH) — для проверки `_normalize_anchors_to_top_left` через детач из неё.
  - [ ] Проверка после правки: открыть сцену — рендерится 3 TabbedBasePanel'а, все 3 показывают tab-bar в шапке вместо TitleLabel.

### Smoke

- [ ] **T008.** Smoke: visibility + click switching (AC1, AC2). Открыть `tabbed_panel_demo.tscn`. Для главной TabbedBasePanel:
  - [ ] В шапке видны 3 tab-button'а (Tab A, Tab B, Tab C). TitleLabel невидим. Lock + Collapse + RightSpacer присутствуют справа.
  - [ ] Активным выделен Tab A (визуально отличается от inactive). Body показывает "I am tab A".
  - [ ] Click по Tab B (без drag) — Tab B выделяется, body показывает VBoxContainer с двумя Buttons. Tab A контент скрыт.
  - [ ] Click по Tab C — Tab C выделяется, body показывает "Empty tab C".

- [ ] **T009.** Smoke: tear-off thresholds (AC3, AC4).
  - [ ] **AC3 (vertical >30px).** LMB-press на Tab B + drag вниз ~50px без выхода за tab-bar по горизонтали → создаётся standalone panel. Tab B исчез из tab-bar главной. Содержимое Tab B (VBox с кнопками) переехало в новую панель. Drag не прервался — продолжаем тащить курсором (LMB не отпускался). Отпустить LMB где угодно (не над tab-bar). Detached panel остался в финальной позиции.
  - [ ] **AC4 (out of rect).** LMB-press на Tab C + drag вниз-влево, выходя за пределы tab-bar по горизонтали (например, ниже уровня header'а в зону body) → tear-off triggers identically. Detached panel создаётся.

- [ ] **T010.** Smoke: re-attach + foreign rejection (AC5, AC6).
  - [ ] **AC5 (re-attach к origin).** Detached panel из AC3 теста (Tab B) — drag за header обратно к главной TabbedBasePanel так, чтобы LMB-release произошёл с курсором над её tab-bar → контент Tab B вернулся в исходный таб, tab-button "Tab B" снова в tab-bar главной, detached panel удалён. Активный таб переключился на B.
  - [ ] **AC6 (rejection of foreign).** Снова detach Tab A из главной. Drag detached → отпустить с курсором над tab-bar **второй** TabbedBasePanel (#2). Detached НЕ реattach'ится во вторую. Остаётся detached в air. Tab A остаётся отсутствующим в главной tab-bar. Reattach к главной всё ещё работает (из той же detached панели).

- [ ] **T011.** Smoke: persistence freshness + cleanup (AC7, AC8).
  - [ ] **AC7 (freshness).** Закрыть Godot. Удалить `user://layouts.cfg` (`rm` или эквивалент по платформе — на Linux `~/.local/share/godot/app_userdata/<project>/layouts.cfg`). Запустить `tabbed_panel_demo.tscn`. В начале — все 3 таба attached. Detach Tab A, отпустить вне tab-bar. Закрыть сцену (выйти из Godot). `cat user://layouts.cfg` показывает секцию `[<scene_path>::demo_tabbed_main__TabA__detached]` с position/size. Открыть сцену снова → detached panel materialized в той же позиции, в tab-bar главной 2 attached (Tab B, Tab C), Tab A отсутствует.
  - [ ] **AC8 (cleanup на reattach).** Из состояния после AC7 — `cat user://layouts.cfg` подтверждает synthetic section. Drag detached к главной tab-bar и отпустить → reattach. `cat user://layouts.cfg` — synthetic section `demo_tabbed_main__TabA__detached` ОТСУТСТВУЕТ (`grep "TabA__detached"` пусто). Закрыть и заново открыть сцену → все 3 tab'а attached, detached panel НЕ всплывает.

- [ ] **T012.** Smoke: empty placeholder + anchors normalization (AC9, AC10).
  - [ ] **AC9 (placeholder).** Detach все 3 таба последовательно. После третьего detach — tab-bar главной TabbedBasePanel показывает локализованный текст "(All tabs detached — drag a detached panel back here)" (или ru-вариант если language=ru). Body главной пустой. Reattach один (любой) → placeholder исчезает, tab-button возвращается, контент виден.
  - [ ] **AC10 (anchors normalization).** Использовать TabbedBasePanel #3 (с не-default anchors). Detach один из её табов. Detached panel — drag за header → не «прыгает на первый клик». Resize за углы работает. Collapse/lock работают. Это смоук spec 057 fix `_normalize_anchors_to_top_left` для нового detached path.

- [ ] **T013.** Smoke: no regressions (AC11, AC12).
  - [ ] **AC11.** Запустить старый smoke spec 057: открыть `scenes/dev/map_editor.tscn` через main menu → редактор открывается, все 5 панелей видны, drag/resize/collapse/lock/persistence — работают как до 058. Никаких новых warning'ов в Godot Output.
  - [ ] **AC12.** Если в проекте есть `ui_catalog.tscn` или эквивалентная preview-сцена — открыть, убедиться что обычные BasePanel'ы рендерятся. Существующие `extends BasePanel` без tab-логики — не аффектятся (миграцию не делали). Если ui_catalog нет — finding F-058-no-catalog в `findings.md`, smoke сводится к точечной проверке любой одной BasePanel сцены через main menu.

### Cleanup verification

- [ ] **T014.** Dead code grep + sanity:
  - [ ] `grep -rnE "extends PanelContainer" scripts/presentation/ui_panels/` пусто (мы не должны были вернуть старый паттерн ни в одном новом файле).
  - [ ] `grep -nE "TabbedBasePanel|PanelTabBar|panel_tab_bar" scripts/presentation/ui_panels/base_panel.gd` пусто (BasePanel не должен знать про tabs — это violation Q-058-6 решения).
  - [ ] `grep -nE "TabbedBasePanel|PanelTabBar" scripts/presentation/ui_panels/internal/panel_persistence.gd` пусто (persistence framework не трогается per T-058-4=C).
  - [ ] `grep -n "panel_persistence\|PanelPersistence" scripts/presentation/ui_panels/internal/panel_tab_bar.gd` находит ТОЛЬКО строки с упоминанием класса в комментариях/docstrings (НЕ import/preload — TabBar делает прямую ConfigFile работу).
  - [ ] Если что-то нашлось — finding в `findings.md`, разбираемся.

### Findings

- [ ] **T015.** Если по ходу T001-T014 всплыли неожиданности (R1 материализовался, Inherited Scene не работает per R7, drag handoff нестабилен, persistence read order путается с anchor normalize, tab-button styling не подхватывает UiTheme) — `specs/058-ui-panels-tabs-teardown/findings.md` создаётся, в нём фиксируются проблемы с конкретикой и текущим work-around. Если ничего не всплыло — finding файл не создаётся.

### Push + PR

- [ ] **T016.** Push ветки + PR. После всех T001-T015 done и smoke зелёный:
  - [ ] `git push -u origin andrey/058-ui-panels-tabs-teardown`.
  - [ ] PR-creation URL из stderr push'а — отдать Андрею. Fallback: `https://github.com/TortikP/GameJamProject/compare/staging...andrey/058-ui-panels-tabs-teardown?expand=1`.
  - [ ] PR title: `058 — ui-panels: tabs + tear-off`.
  - [ ] PR body: чек-лист AC1-AC12 с подтверждениями + ссылки на spec/plan/tasks + список новых файлов (+5 / -0 файлов: panel_tab_bar.gd, tabbed_base_panel.gd, tabbed_base_panel.tscn, tabbed_panel_demo.tscn, tabbed_panel_demo.gd) + список расширенных файлов (+2 файла: panel_drag_handler.gd, base_panel.gd) + список loc-правок (en.json, ru.json).

## Open questions during impl

Если возникают новые вопросы по ходу T001-T014 — фиксируются как Q-058-N+ в `spec.md` §Resolved decisions с пометкой `OPEN`, спек паузится до резолва Андреем. Текущие закрытые вопросы T-058-1..5 + Q-058-6..8 не пересматриваются без явного повода.

Особое внимание Q-058-6/7/8 — резолвлены мозгом в пределах подготовки спека. Андрей может пересмотреть на ревью PR (до старта T-задач или после smoke). Если Андрей резолвит иначе — план перерабатывается до T001.
