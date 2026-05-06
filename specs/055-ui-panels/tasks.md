# 055 — Tasks

Спек: [`spec.md`](./spec.md). Plan: [`plan.md`](./plan.md).

Нумерация по фазам Plan. Каждая фаза = `T<phase><nn>`. T1xx — Skeleton, T2xx — Drag, T3xx — Resize, T4xx — Collapse+Lock, T5xx — header_visible, T6xx — Persistence, T7xx — DraggablePanel removal, T8xx — каталог финал.

## Phase 1 — Skeleton

### Code (Claude)

- [ ] **T101.** Создать каталоги: `scenes/ui/panels/`, `scripts/presentation/ui_panels/`, `scripts/presentation/ui_panels/internal/`.
- [ ] **T102.** Создать `scripts/presentation/ui_panels/base_panel.gd`. `class_name BasePanel`, `extends PanelContainer`. Все экспорты из spec.md §4.3 (`panel_id`, `panel_title_key`, `panel_title_fallback`, `panel_description`, `header_visible`, `draggable`, `resizable`, `collapsible`, `lockable`, `persistable`, `default_locked`, `default_collapsed`, `persistence_scope_override`, `min_panel_size`). Все сигналы (`locked_changed`, `collapsed_changed`, `panel_moved`, `panel_resized`). Пустые методы-стабы (`get_body_container`, `toggle_lock`, `toggle_collapse`, `reset_to_defaults`). В `_ready()`: `add_to_group(&"ui_panel")`, `mouse_filter = MOUSE_FILTER_STOP` (C5), connect `EventBus.ui_theme_reloaded`, вызвать `_compute_effective_flags()` (метод-стаб пока). Никакой логики handler'ов в этой задаче.
- [ ] **T103.** Создать `scenes/ui/panels/base_panel.tscn`. Root `PanelContainer` с прикреплённым `base_panel.gd`. Иерархия per spec.md §4.2: `VBoxContainer` → `HeaderBar (HBoxContainer)` с `LockButton (Button)`, `TitleLabel (Label)`, `CollapseButton (Button)`. `BodyContainer (MarginContainer)` с пустым placeholder Label «inherit me». `ResizeHandles (Control, mouse_filter=PASS)` как sibling `VBoxContainer` внутри `PanelContainer`, с 8 child Control'ами (TopLeft, Top, TopRight, Right, BottomRight, Bottom, BottomLeft, Left), все скрыты (`modulate.a = 0`), пустые скрипты не вешать.
- [ ] **T104.** В `base_panel.gd._ready()` после group/mouse_filter: загрузить title через `Localization.t(panel_title_key, panel_title_fallback)`, проставить в `$VBoxContainer/HeaderBar/TitleLabel`. Если `panel_title_key.is_empty()` — использовать `panel_title_fallback` напрямую без вызова Localization.
- [ ] **T105.** Theme integration. В `_ready()` вызвать `_apply_theme()` (новый приватный метод). Метод применяет stylebox через `add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())`. Подключить к `EventBus.ui_theme_reloaded` чтобы перевызывать `_apply_theme()`. **Решение про `UiPanelHeader` variation отложено до визуального ревью в T112** — по умолчанию header использует тот же stylebox (или встроенную тему PanelContainer без override).
- [ ] **T106.** Создать `scripts/presentation/ui_panels/ui_catalog.gd`. `extends Control`. В `_ready()`: `print("[ui_catalog] loaded with %d panels in group" % get_tree().get_nodes_in_group(&"ui_panel").size())`. Метод `_on_back_pressed()` → `change_scene_to_file("res://scenes/main_menu.tscn")`.
- [ ] **T107.** Создать `scenes/ui/panels/ui_catalog.tscn`. Root `Control` с `anchors_preset=15` (full rect), background `ColorRect` с `UiTheme.bg_color`. Заголовок Label сверху-центру: text — placeholder «Каталог Интерфейсов», позже T805 сделает Localization. Кнопка `BackButton` в верхнем-левом углу: text «← В меню», `pressed` → `_on_back_pressed`. Прикрепить `ui_catalog.gd`. Один наследник `BasePanel.tscn` (Inherited Scene): name `FullPanel`, `panel_id = &"full_demo"`, `panel_title_fallback = "Full demo"`, position (200, 150), size (300, 200). В Body — открыть Editable Children, добавить VBoxContainer с тремя Label'ами «Lorem ipsum dolor sit amet» / «consectetur adipiscing elit» / «sed do eiusmod tempor».
- [ ] **T108.** Создать temporary main menu hook для тестирования каталога ДО Phase 8: добавить в `scripts/presentation/main_menu.gd._ready()` (закомментированный TODO, **не активировать пока**) — закладка чтобы не забыть в T801. Пока — открывать `ui_catalog.tscn` через Godot editor запуск конкретной сцены (F6).

### Smoke (Andrey)

- [ ] **T112 (визуальный ревью).** Открыть `scenes/ui/panels/ui_catalog.tscn` в Godot editor, F6 (run current scene). Ожидание:
  - Каталог открывается, видно заголовок «Каталог Интерфейсов» и кнопку «← В меню» в углу.
  - `FullPanel` рендерится в позиции (200, 150) размером ~(300, 200). Видна шапка с пустыми кнопками-плейсхолдерами и заголовком «Full demo». Body показывает три строки lorem ipsum.
  - Visually distinguishable header from body? **Если нет — заводим R3 и решаем `UiPanelHeader` variation сейчас, до Phase 2.** Если да — продолжаем без variation.
  - В консоли: `[ui_catalog] loaded with 1 panels in group`.
  - Кнопка «← В меню» возвращает на главное меню.
  - Theme matches остальной игры (Win98-teal, Pixellari font).

---

## Phase 2 — Drag

### Code (Claude)

- [ ] **T201.** Создать `scripts/presentation/ui_panels/internal/panel_drag_handler.gd`. `class_name PanelDragHandler`, `extends Node`. Метод `setup(base_panel: BasePanel, header: HBoxContainer) -> void` принимает root и header. Хранит ссылки. Подключает `header.gui_input` к internal `_on_handle_input`. Логика: LMB-press на header → `_begin_drag()`, далее `_input(event)` (global) ловит motion/release. Учитывать `_effective_draggable` через `base_panel.is_draggable()` (новый метод-геттер из BasePanel). На начале drag — `set_anchors_preset(PRESET_TOP_LEFT)` сохраняя текущую `global_position`. Эмитит `base_panel.panel_moved.emit(new_position)` на release.
- [ ] **T202.** Добавить C2 clamp в `_do_drag()` `panel_drag_handler.gd`. Метод `_clamp_position_to_viewport(pos: Vector2) -> Vector2`: вычислить header rect (header.global_position + header.size), убедиться что header целиком внутри `get_viewport_rect()`. Тело может вылезать за низ/право/лево, header — нет.
- [ ] **T203.** В `base_panel.gd._ready()` после theme integration: создать `PanelDragHandler.new()`, `add_child()`, вызвать `setup(self, $VBoxContainer/HeaderBar)`. Сохранить ссылку в private `_drag_handler` (для тестов / введения public API позже если нужно).
- [ ] **T204.** Добавить геттер `func is_draggable() -> bool: return _effective_draggable` в `base_panel.gd`. Реализовать `_compute_effective_flags()`: для phase 2 пока только `_effective_draggable = draggable and header_visible` (остальные флаги — true заглушками, доделаем в Phase 5).

### Smoke (Andrey)

- [ ] **T211 (S002).** F6 на `ui_catalog.tscn`. Drag FullPanel за header (заголовок или пустую область HBoxContainer'а): панель следует за курсором плавно.
- [ ] **T212 (S003).** Drag за body (по lorem ipsum Label'ам): панель НЕ двигается. Курсор остаётся default над body, drag-cursor только над header.
- [ ] **T213 (S017, C2).** Драгать FullPanel в правый-нижний угол viewport: header останавливается у края, не вылезает. Тело может частично уйти за край (это допустимо). Протащить в каждый из 4 углов — ни в одном header не теряется.

---

## Phase 3 — Resize

### Code (Claude)

- [ ] **T301.** Создать `scripts/presentation/ui_panels/internal/panel_resize_handler.gd`. `class_name PanelResizeHandler`, `extends Node`. Метод `setup(base_panel: BasePanel, handles_root: Control) -> void`. Хранит 8 ссылок на child handles по именам (TopLeft, Top, TopRight, Right, BottomRight, Bottom, BottomLeft, Left). Для каждого ставит `mouse_filter = MOUSE_FILTER_STOP`, `mouse_default_cursor_shape` per handle (FDIAGSIZE/BDIAGSIZE/HSIZE/VSIZE), connect `gui_input` и `mouse_entered`/`mouse_exited` для visibility tween (modulate.a 0 → 0.5 в hover, обратно при exit).
- [ ] **T302.** Layout handles. Метод `_layout_handles()` в `panel_resize_handler.gd`. Вызывается на `base_panel.resized` сигнал. Размеры: углы — `(10, 10)`, горизонтальные стороны — `(W-20, 10)`, вертикальные — `(10, H-20)`. Position: TopLeft (0, 0), Top (10, 0), TopRight (W-10, 0), Right (W-10, 10), BottomRight (W-10, H-10), Bottom (10, H-10), BottomLeft (0, H-10), Left (0, 10). Где W=base_panel.size.x, H=base_panel.size.y.
- [ ] **T303.** Resize logic. Метод `_on_handle_input(event, handle_name)` ловит LMB-press → старт resize state с запоминанием стартовой `position`, `size` и `mouse_position`. На motion в `_input` — пересчёт нового `size`/`position` в зависимости от какого handle тащится. Min size enforce: `new_size = new_size.max(base_panel.min_panel_size)`. Position обновляется при resize Top/Left handles (anchor смещается). На release — `panel_resized.emit(new_size)`.
- [ ] **T304.** В `base_panel.gd._ready()` после `_drag_handler`: создать `PanelResizeHandler.new()`, `add_child()`, `setup(self, $ResizeHandles)`. Только если `_effective_resizable` (phase 3 пока считает = `resizable and header_visible`).
- [ ] **T305.** В `_compute_effective_flags()` добавить `_effective_resizable = resizable and header_visible`. Геттер `is_resizable()`.
- [ ] **T306.** Hide handles когда `is_resizable() == false`: в setup проверить флаг, если false — `handles_root.visible = false` и не connect'ить input. (Locked state будет добавлен в Phase 4 — пока handles управляются только статическим флагом.)
- [ ] **T307.** Виртуальный visual gap между handle hover-areas. Если на smoke T311 окажется что курсор «прыгает» между HSIZE и FDIAGSIZE на границе угла-стороны, добавить 2px gap (handle Top начинается с x=12, не x=10). Не делать на этом этапе, только если воспроизводится bug.

### Smoke (Andrey)

- [ ] **T311 (S004).** F6, hover мышью по нижне-правому углу FullPanel (визуально зона 10x10 пикселей). Курсор меняется на FDIAGSIZE, появляется полупрозрачный квадратик handle. Drag — размер панели меняется.
- [ ] **T312 (S005, C1).** Resize FullPanel ниже `min_panel_size` (defaults 120x32): размер не уменьшается ниже min. Min size при необходимости = max от экспорта и реального размера header (LockButton + TitleLabel + CollapseButton).
- [ ] **T313 (S006).** Resize FullPanel за верхне-левый угол: размер меняется И position сдвигается соответственно (правый-нижний угол остаётся на месте).
- [ ] **T314 (R2 check).** Hover по краям FullPanel НЕ над handle (например центр верхней стороны на 2px ниже handle): курсор остаётся default. Курсор меняется на VSIZE/HSIZE/etc только когда мышь действительно над handle. Никаких «cursor surprises» — это была причина дропа resize в spec 055-old.
- [ ] **T315.** Resize-handles исчезают плавно при mouse_exit, появляются плавно при mouse_enter (alpha tween, не instant snap). Если визуально слишком медленно/быстро — отметить в комментарий, скорректируем в Polish.

---

## Phase 4 — Collapse + Lock

### Code (Claude)

- [ ] **T401.** Создать `scripts/presentation/ui_panels/internal/panel_collapse_handler.gd`. `setup(base_panel, collapse_button, body_container, resize_handles)`. На `collapse_button.pressed`: toggle `_is_collapsed`, скрыть/показать `body_container.visible`, скрыть `resize_handles.visible` (collapse обнуляет resize), обновить text кнопки `−`/`+`, запомнить `_pre_collapse_size = base_panel.size` перед collapse, восстановить при expand. Эмитит `base_panel.collapsed_changed.emit(_is_collapsed)`.
- [ ] **T402.** Создать `scripts/presentation/ui_panels/internal/panel_lock_handler.gd`. `setup(base_panel, lock_button)`. На `lock_button.pressed`: toggle `_is_locked`, обновить text 🔓/🔒. Эмитит `base_panel.locked_changed.emit(_is_locked)`. Публичный геттер `is_locked() -> bool` на уровне base_panel.
- [ ] **T403.** Drag/Resize handlers reагируют на lock state. В `panel_drag_handler._begin_drag()` и `panel_resize_handler._on_handle_input()` — early return если `base_panel.is_locked()`. В resize_handler также скрывать handles когда locked (`handles_root.visible = not is_locked()` на signal `locked_changed`).
- [ ] **T404.** В `base_panel.gd._ready()` после resize handler: создать `PanelCollapseHandler.new()` если `_effective_collapsible`, `setup(self, $VBoxContainer/HeaderBar/CollapseButton, $VBoxContainer/BodyContainer, $ResizeHandles)`. Аналогично `PanelLockHandler` если `_effective_lockable`. Спрятать `CollapseButton.visible = false` если `_effective_collapsible == false`. Аналогично `LockButton`.
- [ ] **T405.** В `_compute_effective_flags()` добавить collapsible/lockable. `_effective_collapsible = collapsible and header_visible`, аналогично lockable. Геттеры `is_collapsible()`, `is_lockable()`.
- [ ] **T406.** Apply `default_locked` и `default_collapsed` на старте: после создания handlers в `_ready()`, если `default_locked && _effective_lockable` — вызвать `lock_handler._set_locked(true)` (приватный метод который выставит state без эмита signal). Аналогично collapse. **NB:** в Phase 6 это будет переопределено persistence-loaded values если они есть в `layouts.cfg`.
- [ ] **T407.** Добавить `LockedByDefaultPanel` наследник в `ui_catalog.tscn`. Inherited scene from `base_panel.tscn`, `panel_id = &"locked_default_demo"`, `panel_title_fallback = "Locked by default"`, `default_locked = true`, position (550, 150), size (300, 200). Body — Label «I start locked. Click 🔒 to unlock.». Update `ui_catalog.gd._ready()` debug to show 2 panels in group.
- [ ] **T408.** Добавить `AlwaysCollapsedPanel` наследник в `ui_catalog.tscn`. `panel_id = &"collapsed_default_demo"`, `panel_title_fallback = "Starts collapsed"`, `default_collapsed = true`, position (200, 400), size (300, 200). Body — Label «Click + to expand me.». 3 panels in group.
- [ ] **T409.** Добавить `NoResizePanel` наследник в `ui_catalog.tscn`. `panel_id = &"no_resize_demo"`, `panel_title_fallback = "No resize"`, `resizable = false`, position (550, 400), size (300, 200). Body — Label «I can be dragged, collapsed, locked — but not resized.». 4 panels in group.

### Smoke (Andrey)

- [ ] **T411 (S007).** F6, click `−` на FullPanel: панель сворачивается до header'а, body скрыт, иконка меняется на `+`. Resize handles не появляются на hover в свёрнутом состоянии.
- [ ] **T412 (S008).** Click `+` на свёрнутой FullPanel: разворачивается обратно до прежнего размера (size до collapse).
- [ ] **T413 (S009).** Click 🔓 на FullPanel: иконка меняется на 🔒, drag не работает (попытка drag за header не двигает панель), resize handles не появляются на hover. Click `−` ВСЁ ЕЩЁ работает (collapse не блокируется lock'ом). Click 🔒 разлочивает.
- [ ] **T414 (S001 partial).** Открытие каталога: 4 панели на экране. AlwaysCollapsedPanel свёрнута сразу. LockedByDefaultPanel locked сразу (иконка 🔒). FullPanel и NoResizePanel в дефолтных состояниях (unlocked, expanded).
- [ ] **T415 (S010).** NoResizePanel — попытка resize: handles не появляются на hover вообще. Drag, collapse, lock работают.
- [ ] **T416 (S014).** LockedByDefaultPanel при первом открытии каталога — locked. Drag/resize не работают. Click 🔒 разлочивает, drag/resize начинают работать.

---

## Phase 5 — header_visible cascade

### Code (Claude)

- [ ] **T501.** В `base_panel.gd._ready()` рано в начале: если `header_visible == false` — `$VBoxContainer/HeaderBar.visible = false`. Это первое что происходит, до создания handler'ов.
- [ ] **T502.** `_compute_effective_flags()` уже содержит `and header_visible` для всех 4 флагов из Phase 1-4. Verify, что cascade работает: `header_visible=false` → все 4 effective false. Logging при первом запуске: если `header_visible=false`, `print` в Output чтобы было видно при дебаге.
- [ ] **T503.** В `_ready()` создание handlers — обернуть в проверки `_effective_*`. Если все 4 false — handler'ы вообще не создаются (нет `_drag_handler` etc.). Это защита от того что кто-то их вызовет ради сайд-эффекта.
- [ ] **T504.** Добавить `PinnedPanel` наследник в `ui_catalog.tscn`. `panel_id = &"pinned_demo"`, `panel_title_fallback = ""` (не показывается всё равно), `header_visible = false`, position (900, 150), size (250, 150). Body — Label «In-game HUD style: no chrome, no interaction.». 5 panels in group.

### Smoke (Andrey)

- [ ] **T511 (S011).** F6 каталог: PinnedPanel визуально без header'а. Видно только body с message. Никаких кнопок 🔒, `−`, заголовка.
- [ ] **T512 (S012).** Попытка drag PinnedPanel — клик и таскать body: не двигается, курсор не меняется на drag.
- [ ] **T513 (S013).** Попытка resize PinnedPanel — hover по краям: handles не появляются. Курсор остаётся default.
- [ ] **T514 (S021 prep).** Debug output в `ui_catalog._ready()`: 5 panels in group ui_panel. Все 5 включая PinnedPanel.

---

## Phase 6 — Persistence

### Code (Claude)

- [ ] **T601.** Создать `scripts/presentation/ui_panels/internal/panel_persistence.gd`. `class_name PanelPersistence`, `extends Node`. Методы:
  - `setup(base_panel: BasePanel) -> void`
  - `compute_section_key() -> String` — возвращает `"<scope>::<panel_id>"`. Scope = `base_panel.persistence_scope_override` если непустое, иначе `_find_ancestor_scene_path()`.
  - `_find_ancestor_scene_path() -> String` — обход вверх от base_panel до первого ancestor с непустым `scene_file_path`. Если ничего нет — return `"unknown"` + `push_warning`.
  - `load_layout() -> void` — open `user://layouts.cfg`, прочитать секцию по compute_section_key(), apply position/size/locked/collapsed. Если ключа нет — ничего не делать (defaults применятся).
  - `save_layout() -> void` — сохранить текущее state в секцию ConfigFile, `save("user://layouts.cfg")`.
  - `_on_changed_debounced()` — рестарт internal `Timer` (0.5s), на timeout вызвать `save_layout()`.
- [ ] **T602.** В `base_panel.gd._ready()` после всех handlers: если `persistable && not panel_id.is_empty()` — создать `PanelPersistence.new()`, `add_child()`, `setup(self)`. Connect signals от base_panel (`panel_moved`, `panel_resized`, `locked_changed`, `collapsed_changed`) к `_on_changed_debounced`.
- [ ] **T603.** Load order: persistence load **после** apply defaults. В `_ready()` порядок:
  1. `_compute_effective_flags()`.
  2. `header_visible == false` → hide HeaderBar.
  3. Создание handlers (если effective флаги позволяют).
  4. Apply defaults (`default_locked`, `default_collapsed`).
  5. Создание `_persistence_handler` если `persistable && !panel_id.is_empty()`.
  6. Если `_persistence_handler` есть — `load_layout()`. Это перезатирает defaults значениями из `layouts.cfg`, если ключ есть.
- [ ] **T604.** Создать `scripts/presentation/ui_panels/internal/panel_clamps.gd`. Static utility methods:
  - `static func clamp_to_viewport(pos: Vector2, size: Vector2, header_size: Vector2, viewport: Rect2) -> Vector2`
  - `static func clamp_size_to_viewport(size: Vector2, viewport: Rect2, min_size: Vector2) -> Vector2`
  - Чистые функции, никакого state.
- [ ] **T605.** В `panel_persistence.load_layout()` после применения position/size — вызвать `PanelClamps.clamp_to_viewport()` (C4) и `clamp_size_to_viewport()`. Если значения изменились после clamp — сразу `save_layout()` чтобы перезаписать valid values в файле.
- [ ] **T606.** C3 (viewport resize). В `base_panel.gd._ready()` (если `persistable`): connect к `get_viewport().size_changed` сигналу. Handler `_on_viewport_size_changed`: `await get_tree().process_frame` (settling), затем clamp position/size через `PanelClamps`, если изменилось — apply + persist.
- [ ] **T607.** Flush на exit (R4). В `base_panel.gd._notification(NOTIFICATION_PREDELETE)` или `tree_exiting` signal: если `_persistence_handler` есть — `flush_save()` (новый метод, синхронный save без debounce).
- [ ] **T608.** Version meta. В `panel_persistence` при первой записи в `layouts.cfg` — также пишет `[meta] version = 1`. На load — читает version, если != 1 — `push_warning` и игнорирует файл (defaults применятся).
- [ ] **T609.** Robustness: `load_layout` оборачивает `cfg.load()` в try-style проверку (`var err := cfg.load(...); if err != OK: return`). Никаких crash'ей если файл corrupted/missing/permission-denied.

### Smoke (Andrey)

- [ ] **T611 (S015 part 1).** F6 каталог. Подвинуть FullPanel в новую позицию. Click «← В меню». Вернуться в каталог (главное меню → когда T801 готов; пока — F6 заново). Position FullPanel восстановлен.
- [ ] **T612 (S015 part 2).** Поменять размер NoResizePanel — да нельзя. Поменять размер FullPanel вместо. Назад → каталог. Размер восстановлен.
- [ ] **T613 (S016).** Развернуть AlwaysCollapsedPanel (она стартует свёрнутой по default). Назад → каталог. Запомнено как expanded — открывается развёрнутой, переопределяя `default_collapsed=true`.
- [ ] **T614 (S018, C3).** Открыть каталог. Изменить размер окна Godot (ужать значительно). Все 5 панелей clamp'ятся внутрь — header'ы видны, ни одна не «потерялась» за краем. Debug: проверить `user://layouts.cfg` — clamp'нутые значения сохранены.
- [ ] **T615 (S019).** Открыть `user://layouts.cfg` в OS file manager (`%APPDATA%/Godot/app_userdata/<project>/layouts.cfg` на Win), удалить файл. Открыть каталог. Все 5 панелей в дефолтных позициях из .tscn. AlwaysCollapsedPanel снова свёрнута, LockedByDefaultPanel снова locked.
- [ ] **T616 (R5 verify).** Найти путь `user://layouts.cfg` через OS — путь существует, файл валидный ConfigFile с секциями `<scene_path>::<panel_id>`, секция `[meta] version=1`.

---

## Phase 7 — DraggablePanel.gd removal

### Code (Claude)

- [ ] **T701.** `git rm scripts/presentation/dev/draggable_panel.gd`. Один коммит, отдельно от других правок.
- [ ] **T702.** Verify: `grep -r "draggable_panel" scripts/ scenes/` — должен показать 7 потребителей (per spec.md §8): floor_palette_panel, object_palette_panel, wave_panel, tool_panel, level_meta_panel, dialogue_trigger_panel, и проверить что нет 7-го. Если найден какой-то, не упомянутый в spec — добавить в список fallout.
- [ ] **T703.** Документировать fallout в commit message: список 7 файлов, которые перестают компилироваться. Это known and intended.

### Smoke (Andrey)

- [ ] **T711.** Запустить Godot: проект открывается, parse errors на 7 файлах ожидаемы (preload не находит draggable_panel.gd). Главное меню запускается. Каталог запускается. Pause menu, gameplay сцены — запускаются (если они не используют draggable_panel — они не должны). Map editor — НЕ запускается, parse fail. Это OK, ожидаемо.
- [ ] **T712.** Verify что все 21 smoke сценария Phase 1-6 продолжают работать после удаления (regression check).

---

## Phase 8 — Каталог финал

### Code (Claude)

- [ ] **T801.** В `scenes/main_menu.tscn`: добавить `UiCatalogButton` (Button) в `VBox` между `CreditsButton` и `QuitButton`. Использовать тот же стиль.
- [ ] **T802.** В `scripts/presentation/main_menu.gd`:
  - `@onready var _ui_catalog_btn: Button = $VBox/UiCatalogButton` после `_credits_btn`.
  - В `_ready()` после `_credits_btn.pressed.connect(_on_credits)`: `_ui_catalog_btn.pressed.connect(_on_ui_catalog)`.
  - Новый метод `_on_ui_catalog() -> void: get_tree().change_scene_to_file("res://scenes/ui/panels/ui_catalog.tscn")`.
- [ ] **T803.** Удалить TODO-comment из T108 в main_menu.gd (если остался).
- [ ] **T804.** Localization keys. Добавить в `data/localization/ru.json`:
  - `"ui_main_menu_catalog": "Каталог Интерфейсов"`
  - `"ui_catalog_title": "Каталог Интерфейсов"`
  - `"ui_catalog_back": "← В меню"`

  В `data/localization/en.json`:
  - `"ui_main_menu_catalog": "UI Catalog"`
  - `"ui_catalog_title": "UI Catalog"`
  - `"ui_catalog_back": "← Back to menu"`
- [ ] **T805.** Apply Localization в существующих строках:
  - `main_menu.gd._ready()` после connect: `_ui_catalog_btn.text = Localization.t("ui_main_menu_catalog", "Каталог Интерфейсов")`.
  - `ui_catalog.gd._ready()`: проставить заголовок Label через `Localization.t("ui_catalog_title", "Каталог Интерфейсов")`, BackButton.text через `Localization.t("ui_catalog_back", "← В меню")`.
  - В `ui_catalog.tscn` оставить fallback'и в .tscn (на случай если Localization недоступен в editor preview).

### Smoke (Andrey)

- [ ] **T811 (S001 full).** Открыть главное меню. Видна новая кнопка «Каталог Интерфейсов» между Credits и Quit. Click → каталог открывается с 5 панелями. Debug output: 5 panels in group.
- [ ] **T812 (S020).** В каталоге click «← В меню» → возврат на главное меню.
- [ ] **T813 (Localization).** Сменить язык на English (если поддерживается через настройки). Кнопка в меню → «UI Catalog». Заголовок каталога → «UI Catalog». BackButton → «← Back to menu». Сменить обратно на русский — все строки на месте.
- [ ] **T814 (S021).** В debug консоли: `[ui_catalog] loaded with 5 panels in group`. Все 5 панелей в группе ui_panel.
- [ ] **T815 (full regression).** Пройти S001-S021 ещё раз целиком, по списку из spec.md §9. Это финальная приёмка Spec 055. Если хоть один сценарий fail — фикс и retest всего списка.

---

## Post-merge tasks (после S001-S021 PASS)

### Docs (Claude)

- [ ] **T901.** Update `docs/systems/ui-panels/design.md` §3: убрать z-order persistence из «что входит в snapshot», добавить пометку «z-order перенесён в Spec 057 (см. OI-2)».
- [ ] **T902.** Update `docs/systems/ui-panels/design.md` §10: добавить контракт «структура HeaderBar и Body — стабильная, breaking changes требуют отдельного mini-spec'а».
- [ ] **T903.** Add entry to `docs/design/DECISIONS.md`: «Spec 055 — UI Panels foundation merged. Map editor лежит до Spec 057.».
- [ ] **T904.** Add `ui-panels` block to `docs/FEATURES.md`:
  - Статус: stable.
  - Спек: 055-ui-panels.
  - Код: `scripts/presentation/ui_panels/`, `scenes/ui/panels/`.
  - Как проверить: главное меню → Каталог Интерфейсов → пройти S001-S021.
  - Дизайн: `docs/systems/ui-panels/design.md`.
  - Заметки: foundation для level-editor rehaul (Spec 056-060) и in-game UI миграции (TBD).
- [ ] **T905.** Update `docs/FEATURES.md` запись `level-editor`: добавить заметку «editor лежит, восстанавливается в Spec 057».
- [ ] **T906.** Открыть PR `andrey/055-ui-panels` → `andrey/level-editor-rehaul`. Сводка: spec.md, plan.md, tasks.md как контекст. Smoke S001-S021 пройден. Map editor сломан intentionally. Review pause до merge в integration-ветку.
