# Spec 058 — ui-panels: tabs + tear-off

**Статус:** Spec.
**Тип:** spec-M (1.5–2 дня имплементации).
**Ветка:** `andrey/058-ui-panels-tabs-teardown` → `staging`.
**Обсуждали:** Андрей (идея extract как отдельный спек, резолв OQ-7→B, T1..T5 решения), мозг (раскладка фреймворка, выбор tabbed-subclass vs flag, drag-handoff механика).
**Зависимости:** Spec 055 (`ui-panels` framework, merged как PR #145), Spec 057 (panel migration, merged как PR #147 — гарантирует что 5 dev-панелей уже на BasePanel и `_normalize_anchors_to_top_left` работает в consuming-сценах).
**Используется:** Spec 059 (`level-editor`: architecture from scratch) — `LayersPanel` будет 3-tab (hexes / spawners / objects) с tear-off; см. [`docs/systems/level-editor/design.md`](../../docs/systems/level-editor/design.md) §8 Spec 2.
**Дизайн:** [`docs/systems/ui-panels/design.md`](../../docs/systems/ui-panels/design.md) (фреймворк base; этот спек НЕ дописывает в design.md, но extends его — будущая правка design.md дозреет когда соберётся), [`docs/systems/level-editor/design.md`](../../docs/systems/level-editor/design.md) §8 (контекст потребления + резолв OQ-7).

---

## 1. Что строим (one-paragraph summary)

Расширение `ui-panels` фреймворка табами в шапке `BasePanel` + tear-off / re-attach. Заводим новый подкласс `TabbedBasePanel extends BasePanel` (отдельный класс, не флаг на базе) с собственной сценой `tabbed_base_panel.tscn` (Inherited Scene from `base_panel.tscn`). В шапке вместо `TitleLabel` появляется `PanelTabBar` (новый internal класс, аналогичен `PanelDragHandler`/`PanelResizeHandler` по статусу). Tabs объявляются как Control-дети `BodyContainer` (.tscn-driven default) либо через runtime API `add_tab(content, tab_id, title_key, title_fallback)` / `remove_tab(tab_id)`. Drag за tab-button за порог (>30px вертикали ИЛИ за пределы tab-bar rect) запускает tear-off: создаётся standalone `BasePanel` (обычный, не Tabbed), Control содержимого реpaentится в его `BodyContainer`, drag handoff'ится без релиза LMB через новый публичный метод `PanelDragHandler.begin_drag_at(global_pos)`. Detached panel — обычная BasePanel с synthetic `panel_id = <parent_id>__<tab_id>__detached` для persistence (стандартный path, без правок persistence framework). Re-attach **только к origin** tab-bar; drop на чужой — отвергается. Empty tab-bar (все табы оторваны) показывает локализованный placeholder. Tab reorder — вне scope.

## 2. Проблема

`docs/systems/level-editor/design.md` §4 фиксирует: «Переключение слоя: …клик по табу `LayersPanel` (ui-panels: tab-bar в шапке)». Spec 059 (architecture from scratch) собирается строить `LayersPanel` с 3 табами и tear-off — но `BasePanel` сейчас не имеет концепта табов. Пока tabs+tear-off не реализован, либо Spec 059 прячет сразу 3 палитры в один свой ad-hoc TabContainer (теряем generic фреймворк, дублируем подходом 055-эпохи), либо ждёт. OQ-7 (закрыто как B) вытащил эту работу в собственный спек, чтобы:

- Persistence detached-панелей через synthetic `panel_id` + handoff drag без релиза кнопки + cleanup synthetic sections на reattach имели собственный review-цикл и собственный smoke без editor-specific shума.
- Будущие редакторы (диалогов, скиллов, аспектов) могли использовать готовую generic фичу.
- Spec 059 не смешивал editor-specific shortcuts с framework API.

## 3. Цель

1. **Подкласс `TabbedBasePanel extends BasePanel`** существует. Имеет собственную сцену `scenes/ui/panels/tabbed_base_panel.tscn` (Inherited Scene от `base_panel.tscn`), с `TitleLabel.visible = false` и встроенным `PanelTabBar` в HeaderRow между Lock-блоком и Collapse-блоком (точнее — туда, где раньше был TitleLabel: в начале HeaderRow с size_flags_horizontal=EXPAND).
2. **Hybrid declaration API (T-058-1=C):** Tabs объявляются:
   - **.tscn-driven (дефолт):** Control-дети `BodyContainer` автоматически становятся табами. `tab_id = node.name`. Title — duck-typed: если у ноды есть property `tab_title_key: StringName` — берётся оно (через `Localization.t(...)`); иначе если есть meta `tab_title_key` — оно; иначе `node.name` как fallback. Аналогично `tab_title_fallback`.
   - **Runtime:** `TabbedBasePanel.add_tab(content: Control, tab_id: StringName, title_key: StringName = &"", title_fallback: String = "") -> void`, `remove_tab(tab_id: StringName) -> void`. Параметры write metadata на ноду; ребёнок добавляется в `BodyContainer` и регистрируется в TabBar. `remove_tab` снимает с TabBar и удаляет из `BodyContainer` (caller отвечает за queue_free контента если нужно).
3. **Tear-off (T-058-3=A):** На press LMB на tab-button TabBar начинает tracking. На motion: если суммарное вертикальное смещение |dy| > 30px ИЛИ текущая позиция мыши вне rect самого TabBar — запускается detach. Detach создаёт новый `BasePanel` (обычный, не Tabbed; instance from `base_panel.tscn`), реpaentит Control контента из `BodyContainer` источника в `BodyContainer` нового панели, ставит `panel_id = <parent_id>__<tab_id>__detached`, `panel_title_key/fallback` = (tab title), добавляет panel в один parent с источником (sibling). Drag handoff: вызывается `new_panel.start_drag_at(global_mouse_pos)` (новый публичный метод BasePanel который проксирует в drag handler) — пользователь не отпускает LMB, drag продолжается на новой panel плавно.
4. **Re-attach к origin (T-058-2=A):** Когда detached panel заканчивает drag (LMB release), TabBar (origin) проверяет: если release-position внутри его global_rect — реprepaent контент назад в `BodyContainer`, активирует таб, удаляет detached panel (queue_free). Сheck identity через `_origin_panel_id` + `_origin_tab_id` сохранённые в meta detached panel'а. Drop **на чужой** TabBar (panel_id не совпадает) — отвергается, detached panel остаётся detached. (Проще: каждый PanelTabBar listens на drag_ended только своих tracked floating-tab панелей; drop на чужую территорию = drop на пол = no-op.)
5. **Persistence через synthetic id (T-058-4=C):** Detached panel имеет `panel_id = <parent_id>__<tab_id>__detached` и `persistable = true`. Стандартный `PanelPersistence` flow сохраняет position/size/locked/collapsed под секцией `<scene_path>::<parent_id>__<tab_id>__detached`. На scene reload: TabBar в `_ready` (после super) проверяет для каждого declared tab — есть ли в `user://layouts.cfg` секция с synthetic key. Если да — спавнит detached panel заранее, реparentит контент. Без changes в `panel_persistence.gd`.
6. **Cleanup synthetic section на reattach.** Когда detached panel реattach'ится — TabBar **до** queue_free detached panel читает `user://layouts.cfg`, `cfg.erase_section(...)`, `cfg.save(...)`. Иначе следующий load увидит старую synthetic запись и снова detach'нет. Этот cleanup — в логике `PanelTabBar`, не в `PanelPersistence`. (Реализуется через статический helper `PanelTabBar._erase_layout_section(scope, panel_id)` или через прямую работу с ConfigFile в TabBar.)
7. **Empty placeholder (T-058-5=D):** Если все declared tabs detached — TabBar показывает локализованный Label «(All tabs detached — drag a detached panel back here)» / «(Все табы оторваны — перетащите detached-панель обратно сюда)» вместо tab-buttons. Кеи: `ui_tabs_all_detached_hint` в `data/localization/{en,ru}.json`. BodyContainer пуст; TabbedBasePanel визуально остаётся фреймом + шапкой + пустым телом.
8. **Detached panel прогоняется через `_normalize_anchors_to_top_left()`.** Поскольку detached panel — обычная BasePanel, добавляется в дерево через `add_child(...)` ДО установки position и handoff drag'а. `_ready()` нормализует anchors как в любой консьюмер-сцене. См. spec 057 fix F-057-IMPL-4.
9. **Tab reorder — вне scope.** Drag tab-button горизонтально внутри tab-bar (без выхода за rect и без |dy|>30px) — игнорируется (не происходит ничего). Future feature.
10. **Acceptance smoke** (см. §6) проходит на пустой `user://layouts.cfg` (свежий запуск) и на сохранённом layouts.cfg (re-открытие сцены).

## 4. Не-цели

- **Drag tab-button внутри tab-bar для reorder.** Не делаем. Если жест не достиг порога — просто click → switch active tab.
- **Drop detached panel на ЧУЖОЙ TabBar (T-058-2=A).** Отвергается явно: даже если визуально совпадает hover.
- **RMB context menu на tab-button** («detach», «close», «duplicate»). Не в скоупе. Если drag окажется неинтуитивным на smoke — finding в `findings.md` для будущего follow-up. (Андрей в Q-058-3 explicitly: «RMB-меню НЕ в скоупе 058».)
- **Detached panel как новый origin.** Detached panel — обычная BasePanel (не Tabbed), не может принимать новые табы. Это упрощает T-058-2=A: re-attach только origin → origin.
- **Migration in-game UI на TabbedBasePanel.** Skill HUD, character info — не трогаем.
- **Меняние существующего `PanelPersistence`.** Только добавление одного нового signal в `PanelDragHandler` (`drag_ended(release_pos)`) — это не persistence framework и не базовая семантика drag, а добавочный signal для observers. См. §5.4.
- **Tab close-кнопка (X) на tab-button.** Закрытия таба нет, как и закрытия панели (consistent с design.md §10 ui-panels). Только detach+reattach.
- **Custom стили tab-button** (highlights, hover state кастомные). Используем стандартный `UiTheme.apply_button_styling` + active-state выделение через простую разницу stylebox (active vs inactive).
- **Animation на detach/reattach.** Снэпы без анимации, consistent с design.md §10 ui-panels.
- **TabBar scroll** при overflow (когда табов больше, чем влазит горизонтально). Если контент шире — клиппинг. Юзер делает панель шире через resize. Future feature если попросят.

## 5. Структура изменений (high-level shape)

### 5.1. Новые файлы

```
scripts/presentation/ui_panels/tabbed_base_panel.gd      # class_name TabbedBasePanel extends BasePanel (~150 строк)
scripts/presentation/ui_panels/internal/panel_tab_bar.gd # class_name PanelTabBar extends HBoxContainer (~250 строк)
scenes/ui/panels/tabbed_base_panel.tscn                  # Inherited Scene from base_panel.tscn
scenes/ui/panels/tabbed_panel_demo.tscn                  # тестовая 3-tab сцена для smoke (НЕ для прода)
scripts/presentation/ui_panels/tabbed_panel_demo.gd      # демо-controller с 3 dummy-tabs
```

### 5.2. Минимальные правки в существующих файлах

- `scripts/presentation/ui_panels/internal/panel_drag_handler.gd` — добавить:
  - **signal `drag_ended(release_pos: Vector2)`** — emit в `_input(...)` ветка LMB-release.
  - **public method `begin_drag_at(global_pos: Vector2) -> void`** — выставляет `_is_dragging = true`, `_drag_offset = base_panel.global_position - global_pos`. Вызывается извне (PanelTabBar) для drag handoff без LMB-press события. Идемпотентен (двойной вызов в одной gesture — no-op после первого).
  - **public method `is_dragging() -> bool`** — простой геттер. Может потребоваться для тестов / диагностики.
- `scripts/presentation/ui_panels/base_panel.gd` — добавить:
  - **public method `start_drag_at(global_pos: Vector2) -> void`** — проксирует в `_drag_handler.begin_drag_at(global_pos)` если `_drag_handler != null`. Иначе no-op + push_warning.
- `data/localization/en.json` + `data/localization/ru.json` — добавить ключ:
  - `ui_tabs_all_detached_hint` — fallback en `(All tabs detached — drag a detached panel back here)`, ru `(Все табы оторваны — перетащите detached-панель обратно сюда)`.

### 5.3. PanelTabBar внутреннее устройство

Состояние:
```
_tabbed_panel: TabbedBasePanel        # parent panel reference
_tabs: Array[Dictionary]              # [{tab_id: StringName, content: Control, title_key, title_fallback, button: Button, detached_panel: BasePanel|null}]
_active_tab_id: StringName            # текущий активный таб (только среди attached)
_dragging_tab_id: StringName          # таб, чья кнопка сейчас зажата (для threshold check)
_press_global_pos: Vector2            # позиция нажатия LMB на tab-button
_floating_panels: Array[BasePanel]    # detached панели, источник которых — этот TabBar
```

Lifecycle:
- `_ready()` after super: разбирает Control-дети `BodyContainer` parent panel'а (`_tabbed_panel.get_body_container()`), заводит на каждый запись в `_tabs` с дефолтным `tab_id = node.name`. Создаёт tab-button для каждого. Активным делает первый таб (или первый attached, если первый окажется detached на load).
- На load, для каждого таба: проверка `<scope>::<parent_id>__<tab_id>__detached` в `user://layouts.cfg`. Если секция есть — `_detach_tab_silent(tab_id, restore_layout=true)`: реparentит контент в новый detached panel, добавляет в дерево как sibling parent'а, kicks off persistence load (стандартный path заберёт position/size).
- Обновляет button label через `Localization.t(tab.title_key, tab.title_fallback)` либо `node.name`.

Press → motion → detach pipeline:
- На tab-button gui_input LMB-press: `_dragging_tab_id = tab_id; _press_global_pos = mouse_global; accept_event()`.
- На `_input` LMB motion (пока `_dragging_tab_id != &""`):
  - Compute `dy = abs(mouse_global.y - _press_global_pos.y)`.
  - Compute `outside_bar = not get_global_rect().has_point(mouse_global)`.
  - Если `dy > 30 OR outside_bar` → `_detach_tab_active_drag(_dragging_tab_id, mouse_global); _dragging_tab_id = &""`.
- На `_input` LMB-release: `_dragging_tab_id = &""` (и если threshold не достигнут — это был обычный click → `_set_active(tab_id)`).

`_detach_tab_active_drag`:
- Instantiate `base_panel.tscn` (PackedScene).
- Set `panel_id = StringName("%s__%s__detached" % [parent_id, tab_id])`, `panel_title_key`, `panel_title_fallback`, `min_panel_size` из tab metadata (или default).
- Set `_origin_panel_id`/`_origin_tab_id` через meta на detached panel: `set_meta("__origin_panel_id", parent_id); set_meta("__origin_tab_id", tab_id)`.
- Reparent tab content: `body.remove_child(content); detached_panel.get_body_container().add_child(content)`. **Важно:** добавить detached panel в дерево ДО reparent контента, чтобы `_ready` сработал и BodyContainer был resolved. Идиома: `parent_of_tabbed.add_child(detached_panel)` сначала, затем reparent.
- Set `position = mouse_global - Vector2(some_offset, header_h/2)` (чтобы курсор был над headerом).
- Call `detached_panel.start_drag_at(mouse_global)` — handoff drag.
- Connect `detached_panel._drag_handler.drag_ended` → `_on_floating_drag_ended(detached_panel, release_pos)`.
- Push `detached_panel` в `_floating_panels`.
- Update tab record: `tab.detached_panel = detached_panel`.
- Switch active to next attached tab (или показать empty placeholder).

`_on_floating_drag_ended(panel, release_pos)`:
- Если `get_global_rect().has_point(release_pos)` (release внутри MY tab-bar) → `_reattach(panel)`.
- Иначе panel остаётся detached (no-op).

`_reattach(panel)`:
- Read meta `__origin_tab_id` from panel; найти запись в `_tabs`.
- Reparent content из panel.get_body_container() обратно в `_tabbed_panel.get_body_container()`. Set visible=true if not already.
- Cleanup synthetic section: загрузить `user://layouts.cfg`, `cfg.erase_section(scope::synthetic_id)`, save.
- Remove panel from `_floating_panels`, `panel.queue_free()`.
- Set tab.detached_panel = null.
- `_set_active(tab_id)` — show reattached tab.

`_set_active(tab_id)`:
- Hide all attached tab contents in BodyContainer (visible=false).
- Show selected tab content (visible=true).
- Update active visual state на tab-buttons (stylebox/highlight).
- Update placeholder visibility (if any tab attached → hide placeholder; if none → show).

### 5.4. Drag handoff signal — почему добавляем в PanelDragHandler

T-058-4=C говорит «никаких изменений в persistence framework». Эта добавка — в `PanelDragHandler`, не в persistence. Это маленький параллельный signal к существующим (`panel_moved`, `panel_resized`), позволяющий observerам реагировать на конец drag. Persistence sync уже не зависит от него (persistence сохраняет каждые 1.0s debounce от `panel_moved`/`panel_resized`/`locked_changed`/`collapsed_changed` — drag_ended не требуется ему). Поэтому добавление signal безопасно для существующих consumerов (ничего не сломается, новые consumers могут подписаться).

`begin_drag_at(global_pos)` — публичный метод. Используется PanelTabBar для handoff. Идемпотентен в одной gesture: если `_is_dragging` уже true → ранний return + no-op. Это защита от double-handoff.

### 5.5. Detached panel layout

После handoff и до user-resize:
- `position` ставится в `mouse_global - Vector2(40, BasePanel.CORNER_SIZE / 2)` — чтобы курсор оказался посередине будущего header. Точные оффсеты подберутся при имплементации, но цель — чтобы юзер не чувствовал «телепорта».
- `size` дефолтно из `base_panel.tscn` (300×200) ИЛИ из persistence (если synthetic key уже был).
- `min_panel_size` берётся из tab content's `custom_minimum_size`, ограниченный снизу `Vector2(120, 88)` (BasePanel default).

После первого user-drag/resize — стандартный persistence flow сохраняет под synthetic id, дальше всё штатно.

### 5.6. Demo сцена для smoke

`tabbed_panel_demo.tscn` — самостоятельная сцена для T010-T012 (см. tasks.md). Содержит один `TabbedBasePanel` с 3 dummy-табами (`Tab A`, `Tab B`, `Tab C`), каждый — Control с Label внутри. Используется для smoke без зависимости от editor scenes. Удалится в Spec 059 если не нужна, либо живёт как UI Catalog entry.

## 6. Acceptance criteria

- **AC1.** Открытие `scenes/ui/panels/tabbed_panel_demo.tscn` (или эквивалент) — TabbedBasePanel показывает 3 tab-buttons в шапке (вместо TitleLabel). Lock + Collapse + RightSpacer присутствуют справа как в обычной BasePanel. Активным показан первый tab. Body виден с содержимым первого tab'а.
- **AC2.** Click по tab-button (без drag) переключает активный tab: prev hidden, current visible. Кнопка активного tab'а визуально выделена (отличается stylebox от inactive).
- **AC3 (tear-off threshold A).** Press LMB на tab-button + motion вертикально вниз более чем 30px (с курсором всё ещё над tab-bar) → создаётся standalone BasePanel. Содержимое таба переехало в новую панель. Tab-button исчез из tab-bar. Drag не прерывается (LMB не отпускался) — пользователь продолжает таскать новую панель курсором.
- **AC4 (tear-off threshold B).** Press LMB на tab-button + motion в сторону, выходя за пределы tab-bar rect (например, вниз-влево за header) → tear-off triggers. Поведение идентично AC3.
- **AC5 (re-attach к origin).** Detached panel перетаскивается обратно так, чтобы LMB-release произошёл с курсором над tab-bar источника → контент возвращается в исходный tab, tab-button появляется обратно в tab-bar, detached panel удаляется (`queue_free`). На активный tab автоматически переключается реprepaент'нутый.
- **AC6 (rejection of foreign tab-bar).** Если в сцене **два** TabbedBasePanel'а (А и Б), detached panel из A на release над tab-bar Б — НЕ реattach'ится в Б. Остаётся detached. (Эта проверка — отдельный smoke с двумя демо-панелями; см. T012.)
- **AC7 (persistence freshness).** Чистый `user://layouts.cfg` (delete or never-existed). Открыть демо-сцену → 3 tab'а в attached state. Detach один (drag ниже порога) → отпустить вне tab-bar → detached panel виден в новой позиции. Закрыть сцену / выйти. `cat user://layouts.cfg` показывает секцию `<scene_path>::<parent_id>__<tab_id>__detached` с position/size. Открыть сцену снова → detached panel materialized в той же позиции, в tab-bar 2 attached + tab-button одного отсутствует.
- **AC8 (re-attach cleanup).** Сценарий AC5 + перед reattach `cat user://layouts.cfg` показывает synthetic section. После reattach — `cat user://layouts.cfg` synthetic section ОТСУТСТВУЕТ (`grep` пусто). Открытие сцены заново → все 3 tab'а в attached state, detached panel НЕ всплывает (потому что synthetic section не было в файле).
- **AC9 (empty placeholder).** Detach все 3 tab'а последовательно → tab-bar показывает локализованный текст «(All tabs detached — …)» (en) / «(Все табы оторваны — …)» (ru). Body пустой. Reattach один → placeholder исчезает, tab-button возвращается, контент виден.
- **AC10 (anchors normalization).** Detached panel'ом можно нормально драгать (header стопится у viewport edges по C2), resize'ить за углы и края, collapse, lock. Никаких jump'ов «панель прыгает на первый клик» — `_normalize_anchors_to_top_left` отрабатывает в `_ready`. Для проверки: в demo сцене разместить TabbedBasePanel с не-default anchors (например anchor=center via grow=2,2) и убедиться, что detached panel из неё ведёт себя корректно после первого drag.
- **AC11 (no regressions in BasePanel).** Существующая `scenes/dev/map_editor.tscn` (5 панелей на BasePanel из spec 057) — открывается, drag/resize/collapse/lock/persistence работают без regress. `tests/manual/058-no-base-regression.md` — checklist; smoke через прохождение spec 057 acceptance заново.
- **AC12 (no regressions in `BasePanel` API).** Существующий `scenes/ui/panels/ui_catalog.tscn` (если используется) — продолжает рендерить BasePanel'ы корректно. `extends BasePanel`-наследники без override на tab-логику — никак не аффектятся.

## 7. Findings (для других)

- **F-058-1 (для Никиты, Стасяна):** После 058 в репе появляется 2 типа panel-сцен: `base_panel.tscn` и `tabbed_base_panel.tscn`. Использовать tabbed только когда нужны табы (consumer specifies multi-section content). Для одиночных панелей — обычная BasePanel.
- **F-058-2 (для Алексея):** Если потребуется в будущем мигрировать `WavePanel` или другие панели на табы — паттерн уже готов. Public API: `add_tab()` / `remove_tab()` / `get_active_tab_id()`. Существующие BasePanel'и — без изменений.
- **F-058-3 (для Андрея, Егора):** Tab content scripts сейчас ничего не наследуют, кроме своего собственного предка (Control / Container / etc.). Для localized titles они могут (опционально) экспортировать `tab_title_key: StringName` и `tab_title_fallback: String` — PanelTabBar их прочтёт duck-typed. Альтернатива — `set_meta("tab_title_key", &"...")` в editor. Если ни того ни того — fallback на `node.name`.
- **F-058-4 (для всех):** Drag-threshold `30px` (vertical) и пересечение rect tab-bar — оба эвристичны. Если на smoke юзер пытается switch tab быстрым кликом и accidentally получает detach (например при drift cursor вниз 31px) — finding для tuning. По умолчанию 30px должен быть достаточно «надо реально потащить» без false-positives.
- **F-058-5 (потенциальный для будущего spec):** Detached panel сейчас не tabbed (T-058-2=A не позволяет ему принимать другие табы). Если в будущем захочется «бросать табы между tabbed-панелями» — это другой спек, **не extend** этого. Архитектурно: detached panel хранит `_origin_panel_id`/`_origin_tab_id` в meta — этого достаточно для T-058-2 политики.

## 8. Resolved decisions (T-058-*)

Из чата с Андреем + резолв OQ-7:

- **T-058-1 → C (hybrid API).** .tscn-driven дефолт (children of BodyContainer = tabs, имя через `tab_title_key` экспорт ИЛИ node.name fallback); runtime `add_tab()`/`remove_tab()` тоже доступны. Альтернативы A (только runtime) и B (только .tscn) отвергнуты — оба слишком жёсткие.
- **T-058-2 → A (re-attach только origin).** Detached помнит origin (через meta `__origin_panel_id`/`__origin_tab_id`), drop на чужой tab-bar — отвергается. Альтернативы B (любой tabbed принимает) и C (запрос подтверждения у user'а) отвергнуты — A проще, безопаснее, поведение предсказуемое.
- **T-058-3 → A (drag-out за порог).** `>30px вертикально OR за пределы tab-bar rect`. RMB-меню НЕ в скоупе 058. Если drag окажется неинтуитивным на smoke — finding. Альтернативы B (RMB-only) и C (обе механики) отвергнуты — drag-only достаточно для MVP.
- **T-058-4 → C (synthetic panel_id).** `<parent_id>__<tab_id>__detached` — обычный BasePanel persistence path, никаких изменений в persistence framework. Cleanup synthetic секции на reattach делается в `PanelTabBar` логике (через прямую работу с ConfigFile), не в `PanelPersistence`. Альтернативы A (отдельный сторадж для detached) и B (расширение PanelPersistence новой схемой) отвергнуты — C минимально инвазивный.
- **T-058-5 → D (placeholder).** Пустой tab-bar показывает локализованный «(All tabs detached — …)». Альтернативы A (скрыть TabbedBasePanel целиком), B (показать первоначальный TitleLabel), C (тонкая полоска без текста) — отвергнуты в пользу D как самой явной коммуникации юзеру.
- **Q-058-6 → подкласс TabbedBasePanel (НЕ флаг на BasePanel).** Аргумент: tabs — opt-in feature, большинство панелей не tabbed. Раздувать BasePanel флагом и conditional logic — хуже для читаемости и тестов. Альтернатива (флаг `tabs_enabled` на BasePanel) — отвергнута. Резолвлено мозгом в пределах спека; Андрей может пересмотреть на ревью.
- **Q-058-7 → детaached panel — обычный BasePanel (НЕ TabbedBasePanel).** Аргумент: T-058-2=A не позволяет detached'у принимать другие табы, значит ему не нужна tab-логика. Простая BasePanel минимизирует сложность. Альтернатива (detached как TabbedBasePanel с одним табом) — отвергнута. Резолвлено мозгом; Андрей может пересмотреть.
- **Q-058-8 → drag handoff через add to PanelDragHandler `drag_ended` signal + `begin_drag_at` method.** Аргумент: альтернативы (handoff через PanelTabBar polling drag state, или через emit-on-frame signal в _process) — менее чистые. `drag_ended` signal — естественное расширение существующих signals (`panel_moved`, `panel_resized`); `begin_drag_at` — публичный API для handoff. Резолвлено; Андрей может пересмотреть.
- **Tab reorder — НЕ в скоупе.** Drag tab-button горизонтально (без перехода в detach) игнорируется. Опциональная фича на будущее.

## 9. Out of scope

- Любые правки `PanelPersistence` кроме нулевых (мы не трогаем этот файл).
- Любые правки `BasePanel.tscn` (мы создаём `tabbed_base_panel.tscn` как Inherited Scene, не трогая корневую).
- Изменения существующих 5 dev-панелей (они на обычной BasePanel — корректно, табы не нужны).
- Пробное использование TabbedBasePanel в `LayersPanel` — это работа Spec 059.
- Реальные палитры hexes/spawners/objects как content. Demo использует dummy-табы.
- Loc keys для tab titles конкретных будущих consumer'ов (только `ui_tabs_all_detached_hint` в этом спеке; остальные — когда понадобятся).

## 10. Dependency / sequencing

- Этот спек **разблокирует Spec 059** (`level-editor`: architecture from scratch). Spec 059 будет использовать TabbedBasePanel для LayersPanel. Если 058 не merge'нут — 059 пишет ad-hoc tab-логику, что мы explicitly решили не делать (см. design.md §8).
- После merge 058 в staging — review pause перед стартом 059 (стандартный workflow per `docs/workflow.md`). Если 058 откроет неприятные сюрпризы (например, drag handoff в Godot 4.6 ведёт себя нестабильно) — это окно чтобы доработать 058 до старта 059.
- 058 не зависит от других in-progress специаций (только от merged 055 и 057).
