# Spec 055: UI Panels — Universal Interface Window Framework

**Статус:** Spec.
**Тип:** spec-L. Foundation для Specs 056-060 (level-editor rehaul) и долгосрочно для in-game UI миграции.
**Ветка:** `andrey/055-ui-panels` → integration `andrey/level-editor-rehaul` → staging (когда весь rehaul завершён).
**Обсуждали:** Андрей (идея, scope, UX-решения, can't-lose-UI правило, выбор Inherited Scenes), Никита (collapse-в-шапке, отверг bottom-dock концепт), Claude (раскладка, research-pass, развилки).
**Зависимости:** нет (это foundation).
**Используется:** Spec 056 (level-editor architecture) и далее.
**Дизайн:** [`docs/systems/ui-panels/design.md`](../../docs/systems/ui-panels/design.md) — авторитетный источник архитектурных решений. Этот спек — снимок «что мы строим в этом конкретном спеке», не вся система. Если конфликт — design.md выигрывает, спек обновляется.

---

## 1. Что строим (one-paragraph summary)

`BasePanel.tscn` + `BasePanel.gd` — Inherited Scene, которая инкапсулирует поведение универсального окна интерфейса: drag, resize (8 видимых handles), collapse-в-плашку (кнопка `−`/`+`), lock (замочек), persistence раскладки (per-screen/scene в `user://layouts.cfg`), 5 правил защиты от потери интерфейса. Все features конфигурируемы через экспорт-параметры (можно выключить resize, lock, collapse). Наследники добавляют контент через editable children в обозначенный body-контейнер. Standalone test-сцена с 4 наследниками-демо для acceptance/smoke. Старый `DraggablePanel.gd` удаляется в этом же спеке (зависимые панели сломаются — это известный trade-off, ремонт в Spec 057).

## 2. Цели

- Один тип `BasePanel`, переиспользуемый через Godot-идиоматический Inherited Scenes механизм.
- Все 5 features (drag/resize/collapse/lock/persistence) встроены и опциональны через экспорты.
- Все 5 can't-lose-UI правил (C1-C5 из design.md §6) работают.
- Интеграция с существующим `UiTheme` autoload — новый тип использует его палитру и шрифт, не свои.
- Forward hook для будущего Spec 060+ (UI Catalog): `panel_id`, `panel_description` экспорты, нода в группе `&"ui_panel"` для discoverability через `get_tree().get_nodes_in_group()`.
- Standalone test-сцена `scenes/dev/ui_panels_test.tscn` с 4 демо-наследниками — ручной smoke и будущий вход в UI Catalog.

## 3. Не-цели

- Миграция существующих 7 панелей редактора. Это работа Spec 056-057.
- UI Catalog screen в главном меню. Это работа Spec 060.
- Миграция in-game панелей (skill HUD, character info, popups). Долгосрочный chore, отдельные решения позже.
- Layout presets / save-load named layouts. Не нужно сейчас.
- Reset-кнопка / reset-хоткей. При выполненных C1-C5 потерять интерфейс нельзя.
- Bottom dock закрытых панелей. Закрытия нет.
- Tabs внутри панели как built-in feature. Если наследнику нужны табы — он сам кладёт `TabContainer` в body.
- Анимации drag/resize/collapse. Снэп без анимаций.
- Использование Godot встроенного `Window` нода. Решение принято в research-pass: `Window` спроектирован под subwindows / native OS windows, кастомизация под наши требования сильно ограничена. Берём `PanelContainer` как root.

## 4. Структура

### 4.1. Файлы

```
scenes/ui/panels/
  base_panel.tscn                       # Inherited-from база
  ui_catalog.tscn                       # Сцена «Каталог Интерфейсов» (5 демо-панелей)

scripts/presentation/ui_panels/
  base_panel.gd                         # class_name BasePanel
  ui_catalog.gd                         # script для сцены каталога

  internal/
    panel_drag_handler.gd               # внутренняя логика drag (composition)
    panel_resize_handler.gd             # внутренняя логика resize (8 handles)
    panel_collapse_handler.gd           # внутренняя логика collapse
    panel_lock_handler.gd               # внутренняя логика lock
    panel_persistence.gd                # save/load через ConfigFile
    panel_clamps.gd                     # C1-C5 utility функции

scenes/main_menu.tscn                   # +UiCatalogButton между Credits и Quit
scripts/presentation/main_menu.gd       # +_on_ui_catalog хендлер

user://layouts.cfg                      # создаётся в runtime, не в репо
```

**Решения по структуре:**
- Сцены в `scenes/ui/panels/`, скрипты в `scripts/presentation/ui_panels/` — convention из ответа на Q1.
- Internal handlers — composition, не наследование. `BasePanel.gd` создаёт их как child-узлы через `add_child(PanelDragHandler.new())` в `_ready()`. Это даёт single-responsibility файлы и возможность тестировать handler-логику изолированно. Это **не публичный API** — handlers — implementation detail.
- Никаких autoload'ов от этой системы. Persistence через прямой `ConfigFile` доступ из `panel_persistence.gd`.

### 4.2. `BasePanel.tscn` структура нод

```
PanelContainer (root, script: base_panel.gd, group: "ui_panel")
└─ VBoxContainer
   ├─ HeaderBar (HBoxContainer, name: "Header")
   │  ├─ LockButton (Button, name: "LockButton")
   │  ├─ TitleLabel (Label, name: "TitleLabel")
   │  └─ CollapseButton (Button, name: "CollapseButton")
   └─ BodyContainer (MarginContainer, name: "Body")
      └─ [пусто — наследники наполняют]

ResizeHandles (Control, name: "ResizeHandles", mouse_filter: PASS)
└─ 8 child-Control'ов (TopLeft, Top, TopRight, Right, BottomRight, Bottom, BottomLeft, Left)
```

`ResizeHandles` — sibling от `VBoxContainer` внутри `PanelContainer`, абсолютно позиционируется поверх границ панели (не часть layout flow). Mouse filter PASS чтобы не блокировать клики в body, но child handles имеют STOP в своих зонах.

### 4.3. `BasePanel.gd` публичный API

```gdscript
class_name BasePanel
extends PanelContainer

# ── Identity ───────────────────────────────────────────────────────
@export var panel_id: StringName = &""           # для persistence + UI Catalog
@export var panel_title_key: StringName = &""    # ключ Localization.t()
@export var panel_title_fallback: String = ""    # если ключ не найден / dev-режим
@export_multiline var panel_description: String = ""  # для будущего UI Catalog

# ── Feature toggles ────────────────────────────────────────────────
@export var header_visible: bool = true        # см. §5.4: false ⇒ auto-disable drag/resize/collapse/lock
@export var draggable: bool = true
@export var resizable: bool = true
@export var collapsible: bool = true
@export var lockable: bool = true
@export var persistable: bool = true

# ── Defaults (применяются если в layouts.cfg ещё нет записи) ───────
@export var default_locked: bool = false
@export var default_collapsed: bool = false

# ── Persistence scope (Q5: дефолт авто, опциональный override) ─────
@export var persistence_scope_override: StringName = &""

# ── Constraints ────────────────────────────────────────────────────
@export var min_panel_size: Vector2 = Vector2(120, 32)  # C1, см. §5

# ── Signals ────────────────────────────────────────────────────────
signal locked_changed(is_locked: bool)
signal collapsed_changed(is_collapsed: bool)
signal panel_moved(new_position: Vector2)
signal panel_resized(new_size: Vector2)

# ── Public methods ─────────────────────────────────────────────────
func get_body_container() -> MarginContainer  # для редких случаев программного доступа
func toggle_lock() -> void
func toggle_collapse() -> void
func reset_to_defaults() -> void              # сбрасывает к defaults (для будущего UI Catalog preview)
```

**Контракт для наследников:**
- В Inherited Scene открыть «Editable Children», положить контент в `Body` (MarginContainer).
- Указать `panel_id` (обязательно если `persistable = true`), `panel_title_key`/`panel_title_fallback`, `panel_description`.
- Не трогать ноды внутри HeaderBar или ResizeHandles. Если нужны кастомные кнопки в шапке — создать issue, расширим API. **Не стоит** напрямую добавлять child'ов в HeaderBar в наследнике — это сломает layout рассчёт min_size и persistence.

## 5. Behaviors (детально)

### 5.1. Drag

- Триггер: LMB-press на `HeaderBar` (на самой ноде или TitleLabel — кнопки `LockButton`/`CollapseButton` перехватывают свой `gui_input` и не пропускают).
- Если `draggable = false` ИЛИ `locked = true` → drag не стартует, курсор остаётся default.
- При первом старте drag: `set_anchors_preset(PRESET_TOP_LEFT)` сохраняя текущую `global_position`. Это критично — иначе layout-якоря (если панель в `VBoxContainer` родителе) перебивают позицию.
- В drag: `_input` (не `_gui_input`) ловит motion и release. Это позволяет drag survive выход курсора за пределы header'а.
- **C2 clamp:** в `_do_drag()` позиция корректируется так, чтобы вся `HeaderBar` rect целиком оставалась внутри `viewport_rect`. Тело может вылезать вниз/вбок, шапка — нет.
- На release: emit `panel_moved`, persistence debounce-таймер reset.

### 5.2. Resize

- 8 handles, абсолютно позиционированы по углам и серединам сторон `PanelContainer`. Размер каждого: `(10, 10)` для углов, `(W-20, 10)` для горизонтальных сторон, `(10, H-20)` для вертикальных. Зона захвата = размер handle = ≥10px (C-spec из design §7).
- `mouse_default_cursor_shape` per handle: `FDIAGSIZE` для TopLeft/BottomRight, `BDIAGSIZE` для TopRight/BottomLeft, `HSIZE` для Left/Right, `VSIZE` для Top/Bottom.
- Видимость handles: hover-only по умолчанию. При наведении на handle он становится видимым (`color = Color(1, 1, 1, 0.5)`), при уходе — невидимым (`color.a = 0`). UP-1 «перманентно видимые» — открытый вопрос на прототипе, по умолчанию **hover-only**.
- Если `resizable = false` ИЛИ `locked = true` ИЛИ `collapsed = true` → handles полностью скрыты (`visible = false` на корневом `ResizeHandles`), не реагируют.
- Resize update: новый size = max(min_panel_size, vector_from_handle_drag). Position обновляется при resize Top/Left handles (потому что точка отсчёта смещается).
- На release: emit `panel_resized`, persistence debounce.

### 5.3. Collapse

- Триггер: LMB-click на `CollapseButton`.
- В развёрнутом состоянии: текст кнопки `−`, видны header + body.
- В свёрнутом состоянии: текст кнопки `+`, body скрыт (`visible = false`), `min_size` = только header. ResizeHandles скрыты независимо от `resizable`.
- Запоминается размер до collapse в `_pre_collapse_size: Vector2`. При expand size восстанавливается из этого поля (не из persistence — это in-memory between toggles).
- Свёрнутую плашку можно драгать (если `draggable + !locked`), нельзя ресайзить.
- На toggle: emit `collapsed_changed`, persistence debounce.
- Если `collapsible = false` → CollapseButton скрыт.

### 5.4. Lock и header_visible

**Lock:**
- Триггер: LMB-click на `LockButton`.
- Иконка/текст кнопки: 🔓 unlocked, 🔒 locked. Точное представление — temp emoji-text, может стать TextureButton'ом позже (OI-2).
- При locked: drag и resize отключены. Collapse работает. LockButton — единственный способ разлочить (клик).
- На toggle: emit `locked_changed`, persistence debounce.
- Если `lockable = false` → LockButton скрыт.

**Header visibility (`header_visible: bool`):**
- Если `header_visible = false` → `HeaderBar` (HBoxContainer с lock/title/collapse) полностью скрыт (`visible = false`). Тело панели рендерится без верхней полосы.
- При `header_visible = false` следующие features **автоматически принудительно выключаются**, независимо от значения соответствующих экспортов:
  - `draggable` → false (нет handle для drag)
  - `resizable` → false (без header нет визуального anchor для resize handles, плюс по дизайну такие панели «прибиты гвоздями»)
  - `collapsible` → false (нечего сворачивать — header и есть свёрнутое состояние)
  - `lockable` → false (нечего лочить, всё уже неинтерактивно)
- Persistence продолжает работать если `persistable = true`: `position` и `size` сохраняются (разработчик может выставить их вручную в .tscn ИЛИ панель когда-то была интерактивной и юзер её передвинул, потом разработчик скрыл header).
- В runtime эти auto-disabled значения **read-only** наблюдаются через геттеры (логика в `BasePanel._ready()`: при `header_visible=false` устанавливаются `_effective_draggable=false` и т.д., публичные `draggable`/`resizable`/`...` методы отдают `_effective_*`). Это даёт предсказуемость: код не может «думать что drag работает» когда header скрыт.

**Конфигурация «гвоздями прибитой панели» (для in-game UI):**
- `header_visible = false` — это и есть основной механизм. Один экспорт-флаг даёт «полностью неинтерактивный фрейм для контента».
- Эквивалентная развёрнутая конфигурация: `header_visible = true, draggable = false, resizable = false, lockable = false, collapsible = false`. Доступна если хочется header (с заголовком) но без интерактива.

### 5.5. Persistence

- Файл: `user://layouts.cfg`. Формат — `ConfigFile`.
- Ключ секции: `<persistence_scope>::<panel_id>` где:
  - `persistence_scope` = `persistence_scope_override` если задан, иначе автоматически вычисляется как scene_file_path ближайшего ancestor с непустым `scene_file_path`.
  - `panel_id` = экспорт-параметр.
- Если `persistable = false` ИЛИ `panel_id` пуст → ничего не сохраняется/не загружается.
- Сохраняется: `position` (Vector2), `size` (Vector2), `collapsed` (bool), `locked` (bool).
- **Z-order не сохраняется в Spec 055.** Z-order требует координации между панелями — это правильнее делать когда у нас будет ≥2 панели на экране (т.е. в Spec 057). Эту строчку дизайна ([design.md §3](../../docs/systems/ui-panels/design.md#3-persistence-что-входит-в-snapshot)) нужно обновить — фиксирую как deferred-from-Spec-055 issue, см. §10.
- Когда сохраняется: debounced 0.5s после последнего изменения (drag-end, resize-end, collapse, lock).
- Когда загружается: в `_ready()`. Если ключа нет — используются defaults из экспортов (`default_locked`, `default_collapsed`) и position/size из .tscn.
- При загрузке: clamp C4 (см. §5.6).
- Версионирование: секция `[meta]` с `version = 1`. При несовпадении версии в Spec 055 — игнорируем существующий файл и пишем заново. (Миграция между версиями — будущий вопрос, сейчас единственная версия.)

### 5.6. Can't-lose-UI clamps

- **C1 (min size):** `custom_minimum_size = max(min_panel_size, header_min_size)`. Header min_size вычисляется в `_ready()` из реальных размеров кнопок и заголовка. Если `min_panel_size` экспорт меньше реального размера хедера — берётся header_min_size.
- **C2 (drag bounds):** см. §5.1.
- **C3 (viewport resize):** connect к `get_viewport().size_changed`. На signal — clamp каждой панели в группе `&"ui_panel"` (статический метод `BasePanel.clamp_all_panels(tree)`, или каждая панель сама на signal). Дебаунсим, чтобы не клампить во время dragging window's edge — clamp на `_process` next-frame, не сразу.
- **C4 (load-time clamp):** при загрузке layout — позиция и size валидируются против текущего `viewport_rect`. Если HeaderBar вне viewport → clamp position. Если size > viewport → clamp size. После clamp перезаписываем layouts.cfg валидной версией.
- **C5 (no mouse_filter=ignore):** `BasePanel._ready()` устанавливает `mouse_filter = MOUSE_FILTER_STOP` на root и проверяет в `_notification(NOTIFICATION_READY)` что не был переопределён. Если в наследнике кто-то поставил IGNORE → `push_warning("BasePanel: mouse_filter forced back to STOP — this is a UI safety rule")` и forced back. Hard rule, не negotiable.

## 6. Theming

- Используется существующий `UiTheme` autoload и его палитра (Win98-teal).
- `BasePanel` корень — `PanelContainer` с `theme_type_variation = &"UiPanel"` (новый variation в проектной theme или применяется через `UiTheme.make_panel_stylebox()` в `_ready()`).
- Header как отдельный StyleBox (немного темнее body — Win98-стиль) — добавим `theme_type_variation = &"UiPanelHeader"` для HeaderBar.
- LockButton/CollapseButton — стандартные `Button` с `UiTheme` стилями.
- Шрифт — Pixellari через global theme (наследуется автоматически).
- Подключиться к `EventBus.ui_theme_reloaded` — на signal перепримерить styleboxes (как делают существующие панели).

**Не делаем в Spec 055:**
- Не вводим новых StyleBox'ов в `UiTheme` без необходимости. Если variation `"UiPanel"` пустой → fallback на дефолтный PanelContainer стиль, который уже определён в global theme.
- Не делаем кастомную тему только для ui-panels.

## 7. UI Catalog screen (`scenes/ui/panels/ui_catalog.tscn`)

Standalone сцена-каталог. Доступна всем игрокам через главное меню. Это **placeholder для Spec 060** (полноценный UI Catalog с навигацией, описаниями, поиском) — но имя кнопки и точка входа выбираются финальными сейчас, чтобы потом не переименовывать.

**Состав:**
- Root: `Control` (full-rect), фон с `UiTheme` background color.
- Заголовок «Каталог Интерфейсов» сверху (через Localization key `ui_catalog_title`).
- Кнопка «← В меню» в углу — возвращает на главное меню.
- 5 наследников `BasePanel`, расположены равномерно на экране:
  1. **`FullPanel`** — все features включены (`header_visible=true`, all toggles=true), default unlocked, expanded. Body: несколько Label'ов с lorem-ipsum чтобы было видно min_size enforcement.
  2. **`NoResizePanel`** — `resizable=false`. Body: одна фиксированная Label. Демонстрирует «панель без ручек ресайза».
  3. **`AlwaysCollapsedPanel`** — `default_collapsed=true`. Демонстрирует initial state из persistence/defaults.
  4. **`PinnedPanel`** — `header_visible=false`. «Гвоздями прибитая, без верхней полосы». Body содержит inline message «In-game HUD style: no chrome, no interaction». Демонстрирует целевую конфигурацию для будущей миграции in-game панелей.
  5. **`LockedByDefaultPanel`** — `default_locked=true`. Все features включены, но стартует locked. Юзер должен явно разлочить.
- Минимальный controller-script `ui_catalog.gd` — обработка кнопки «В меню», debug-вывод в `_ready()` («Catalog loaded with N panels in group ui_panel»).

**Точка входа:**
- Кнопка `UiCatalogButton` в `scenes/main_menu.tscn`, между `CreditsButton` и `QuitButton`.
- Текст кнопки через Localization: `ui_main_menu_catalog`, fallback «Каталог Интерфейсов» / EN: «UI Catalog».
- Хендлер `_on_ui_catalog()` в `scripts/presentation/main_menu.gd` — `get_tree().change_scene_to_file("res://scenes/ui/panels/ui_catalog.tscn")`.
- Обратный путь: кнопка «← В меню» в каталоге → `change_scene_to_file("res://scenes/main_menu.tscn")`.
- Никаких debug-flag'ов. Доступно всем игрокам всегда.

**Долгосрочно (Spec 060):**
- Эта сцена эволюционирует в полноценный каталог: список panel-types в боковой панели, область preview справа, описания (`panel_description`), поиск. Сейчас — простая страница с 5 демо.
- Кнопка в главном меню не меняется. Меняется содержимое сцены `ui_catalog.tscn`.

## 8. Что удаляется

- `scripts/presentation/dev/draggable_panel.gd` — удалить в этом спеке. Это сломает 7 существующих панелей (`floor_palette_panel.gd`, `object_palette_panel.gd`, `wave_panel.gd`, `tool_panel.gd`, `level_meta_panel.gd`, `dialogue_trigger_panel.gd`, и не используется ли где ещё — проверить grep'ом в Plan).
- Map editor становится нерабочим. Это известный trade-off, согласован Андреем. Восстанавливается в Spec 056-057 (architecture from scratch + palette migration). До этого — редактор лежит. Файлы карт читать/писать остальная игра продолжает.
- Записать в DECISIONS дату «MM-YY: Map editor отключён на ~M спеков, вернётся в Spec 057». Не критичная информация, но полезная если кто-то откроет ветку через месяц.

## 9. Acceptance criteria (smoke checklist)

Манульный smoke на `scenes/ui/panels/ui_catalog.tscn` после имплементации:

| ID | Сценарий | Ожидание |
|---|---|---|
| S001 | Открыть главное меню → клик «Каталог Интерфейсов» | Сцена каталога открывается. 5 панелей на экране в дефолтных позициях. AlwaysCollapsedPanel свёрнута. LockedByDefaultPanel locked. |
| S002 | Drag FullPanel за header | Панель следует за курсором, header не выходит за границы viewport. |
| S003 | Drag FullPanel за body | Не двигается (только header — drag handle). |
| S004 | Resize FullPanel за нижне-правый угол | Размер меняется, видно курсор FDIAGSIZE при наведении на handle. |
| S005 | Resize FullPanel ниже min_panel_size | Размер не уменьшается ниже min. |
| S006 | Resize FullPanel за верхне-левый угол | Размер меняется, position сдвигается соответственно. |
| S007 | Click `−` на FullPanel | Панель сворачивается в плашку с header'ом. Иконка меняется на `+`. |
| S008 | Click `+` на свёрнутой FullPanel | Разворачивается обратно к pre-collapse размеру. |
| S009 | Click 🔓 на FullPanel | Иконка меняется на 🔒. Drag не работает. Resize handles не появляются на hover. Collapse работает. |
| S010 | NoResizePanel — попытка resize | Handles не появляются (`resizable=false`). Drag, collapse, lock работают. |
| S011 | PinnedPanel (header_visible=false) — визуально | Нет header'а вообще. Видно только body с message. |
| S012 | PinnedPanel — попытка drag за body | Не двигается. Курсор не меняется. |
| S013 | PinnedPanel — попытка resize | Handles не появляются (auto-disabled). |
| S014 | LockedByDefaultPanel — стартовое состояние | Locked при первом открытии каталога. Иконка 🔒. Drag/resize не работают. |
| S015 | Подвинуть FullPanel, вернуться в меню, снова открыть каталог | Позиция восстановлена. |
| S016 | Свернуть AlwaysCollapsedPanel-в-развёрнутую, вернуться в меню, снова открыть каталог | Запомнено как expanded (override default). |
| S017 | Драгать FullPanel в правый-нижний угол viewport | Header останавливается у края, не вылезает (C2). |
| S018 | Изменить размер окна Godot пока каталог открыт | Все панели clamp'ятся, остаются доступны (C3). |
| S019 | Удалить `user://layouts.cfg` вручную, открыть каталог | Все панели в дефолтных позициях из .tscn. AlwaysCollapsedPanel снова collapsed, LockedByDefaultPanel снова locked. |
| S020 | Кнопка «← В меню» в каталоге | Возврат на главное меню. |
| S021 | Проверить `get_tree().get_nodes_in_group("ui_panel").size() == 5` в `_ready` каталога | Все 5 панелей в группе (включая PinnedPanel — header нет, но в группе она). |

S001-S021 — все обязательны для merge Spec 055 в integration-ветку.

## 10. Open issues (на разрешение в Plan/Tasks или позже)

- **OI-1 (резолвится в Tasks):** конкретные иконки/текст для LockButton (🔓/🔒) и CollapseButton (`−`/`+`) — emoji-текст или TextureButton с asset'ами. Решение: в Spec 055 emoji-текст (proof-of-concept), TextureButton можно заменить позже без API-breakage.
- **OI-2 (deferred from Spec 055 → Spec 057):** Z-order persistence. Не сохраняется в Spec 055 (5 панелей в каталоге размещены без overlap). Будет реализовано в Spec 057, когда у нас 5+ панелей в редакторе на одном экране и они реально перекрываются. Обновить design.md §3 с пометкой.
- **OI-3 (после Spec 055):** UP-1 из design.md (видимые-всегда vs hover-only handles) — оценить на прототипе. Пока hover-only.
- **OI-4 (вне Spec 055):** UP-3 из design.md (lock persists через сессии) — реализовано как «да, persists» в этом спеке. Если по итогам плейтестов всплывёт раздражение — переоткрыть.

## 11. Размер

Оценка: **L** (несколько дней работы).

Прикидка по компонентам:
- `BasePanel.tscn` сборка + базовый скрипт + 6 internal handler'ов: 1-2 дня.
- Test-сцена + 4 наследника + smoke pass: 0.5 дня.
- Theme integration + EventBus signals: 0.5 дня.
- Удаление DraggablePanel + проверка что нигде больше не используется: 0.5 дня.
- Persistence implementation + clamps + debugging: 1 день.
- Polish, edge cases, документация в коде: 0.5 дня.

Итого: 4-5 дней реальной работы. Может растянуться если всплывёт что-то в clamps или persistence (особенно C3 viewport resize при разных DPI).

## 12. После merge

- Spec 056 (level-editor architecture from scratch) разблокирован.
- Map editor лежит до конца Spec 057.
- Сцена `ui_catalog.tscn` остаётся в репо как long-lived placeholder для Spec 060 (UI Catalog). 5 демо-панелей доступны игрокам через главное меню сразу.
- DECISIONS запись: ссылка на этот спек как foundation rehaul'а.
