# 058 — Plan: ui-panels tabs + tear-off

Спек: [`spec.md`](./spec.md). Резолвлены T-058-1..5 + Q-058-6..8.

## Что дальше (TL;DR)

Восемь точечных шагов + smoke + 6 acceptance прогонов:

1. **2 минимальные правки** в `panel_drag_handler.gd` (signal `drag_ended` + public `begin_drag_at` + helper `is_dragging`) и `base_panel.gd` (proxy `start_drag_at`). ~30 строк суммарно.
2. **2 loc keys** в `data/localization/{en,ru}.json` для `ui_tabs_all_detached_hint`.
3. **`PanelTabBar` (новый)** — `scripts/presentation/ui_panels/internal/panel_tab_bar.gd`, `class_name PanelTabBar extends HBoxContainer`. Логика: разбор tabs из BodyContainer, button rendering, threshold detection, detach pipeline, reattach pipeline, synthetic-section cleanup, placeholder. ~250 строк.
4. **`TabbedBasePanel` (новый)** — `scripts/presentation/ui_panels/tabbed_base_panel.gd`, `class_name TabbedBasePanel extends BasePanel`. Тонкий subclass: оборачивает HeaderRow → инстанцирует PanelTabBar в место TitleLabel'а, hides TitleLabel.visible, exposes `add_tab()`/`remove_tab()`/`get_active_tab_id()` API проксирующее в PanelTabBar. ~150 строк.
5. **`tabbed_base_panel.tscn` (новый)** — Inherited Scene from `base_panel.tscn`. TitleLabel.visible=false. PanelTabBar добавлен в HeaderRow в позиции 0 (перед скрытым TitleLabel) с size_flags_horizontal=EXPAND.
6. **`tabbed_panel_demo.tscn` + `tabbed_panel_demo.gd`** — простая standalone демо-сцена с 3 dummy-табами для smoke. Не идёт в прод.
7. **Smoke** в Godot — все 12 AC прогоняются. Запись наблюдений в `findings.md` если есть.
8. **Cleanup verification** — grep'ы из AC11/AC12, проход по spec 057 acceptance проверка no regressions.

Размер: spec-M (1.5–2 дня). Главные риски — Godot edge cases при drag handoff (см. §Risks).

## Архитектурное обоснование

### Почему подкласс, не флаг (Q-058-6)

`BasePanel` — общий контракт «окно интерфейса с drag/resize/collapse/lock/persistence», ~420 строк. Добавлять флаг `tabs_enabled` означает:
- Conditional resolve of `_title_label` vs `_tab_bar` в `_resolve_nodes()`.
- Conditional theme application для двух node типов.
- Расширение persistence или ввод нового signal-сurрогата для активного tab.
- ~80% panels не tabbed — мёртвый код в `_ready()` для них.

Подкласс — opt-in feature. `TabbedBasePanel extends BasePanel` инвертирует ответственность: tab-логика живёт там, BasePanel остаётся simple. Стоимость подкласса: один extra .tscn и один extra .gd. Win: testability, separation of concerns, нулевой импакт на existing 5 dev-панелей.

### Почему detached panel — обычная BasePanel (Q-058-7)

T-058-2=A: detached → only origin reattach. Detached panel никогда не принимает другие tabs (ни от origin, ни от других). Значит ему не нужна `PanelTabBar`. Простая `BasePanel` достаточна.

Если в будущем кто-то решит «бросать табы между tabbed-панелями» — это другой спек, и detached panel в нём будет другим типом. Текущая архитектура не блокирует расширение — просто не делает его.

### Почему drag_ended signal в PanelDragHandler (Q-058-8)

Альтернативы рассмотрены:
- **Polling из PanelTabBar** через `_process(delta)` или периодический Timer — race conditions с release event, перерасход CPU.
- **Самостоятельный _input на detached panel** — дублирует логику drag handler, ловит release дважды (handler сам сбрасывает `_is_dragging`), хрупко.
- **Hook в `panel_moved` emit** — `panel_moved` шлётся на каждом frame во время drag; нет естественного «вот теперь конец». Пришлось бы добавлять тот же signal под другим именем.

Прямое расширение PanelDragHandler signalом `drag_ended(release_pos: Vector2)`:
- Параллельно существующим signals (`panel_moved`, `panel_resized`) — естественная ось.
- ~3 строки кода.
- Не аффектит persistence (она не подписана и не нуждается).
- Тестируемо (можно эмулировать LMB-release event и проверить что signal эмитится с правильным позицией).

`begin_drag_at(global_pos)` — публичный API для drag handoff, симметричен. Без него tab-bar не сможет «взять курсор» у нажатой кнопки и передать новой панели без релиза LMB.

### Почему .tscn-children как default declaration (T-058-1=C, .tscn-driven часть)

Альтернатива — runtime-only API — требует владения lifecycle от каждого consumer'а: «сначала add_tab, потом show». .tscn-driven дёшев: автор открывает Godot UI, тянет children в `BodyContainer`, ставит мета. PanelTabBar разбирает.

Hybrid (runtime тоже доступен) нужен для случаев: (1) Spec 059's `LayersPanel` может захотеть вкладывать палитры программно, если их состав зависит от runtime data; (2) UI Catalog / preview tools хотят добавлять tabs на лету. Cost: тривиальный — runtime методы дёшевы поверх .tscn-driven базы.

### Почему synthetic panel_id (T-058-4=C)

Альтернативы:
- **Расширить PanelPersistence новой схемой** (например, секция `<scope>::<parent_id>::tabs` со списком detached): требует правок `panel_persistence.gd`, нового формата, миграции старых layouts.cfg, нового version. Тяжёлое решение для одной фичи.
- **Отдельный сторадж** (например, `user://tabs.cfg`): два файла под одну тему, синхронизация при clear/migrate, два code path.

Synthetic id — `<parent_id>__<tab_id>__detached` — это **нормальный panel_id**. PanelPersistence не знает, что он synthetic — он работает как обычно: section в `layouts.cfg`, position/size/locked/collapsed. Парсер `_compute_section_key()` не различает «настоящих» и synthetic ids.

PanelTabBar — единственный, кто понимает семантику id'а. На load: проверяет ConfigFile напрямую (через `ConfigFile.has_section(scope::synthetic_id)`), если есть — спавнит detached. На reattach: `cfg.erase_section(scope::synthetic_id)`, save. Это 5–10 строк ad-hoc ConfigFile работы в TabBar — гораздо дешевле чем расширение фреймворка.

### `_normalize_anchors_to_top_left` для detached

Detached panel инстанцируется из `base_panel.tscn` (PackedScene `.instantiate()`). При `add_child()` — `_ready()` запускается, `_normalize_anchors_to_top_left()` отрабатывает. Поскольку дефолтные anchors в base_panel.tscn = TOP_LEFT (per spec 057 fix F-057-IMPL-4), normalize будет no-op. Это **good** — мы хотим, чтобы detached panel начинала жизнь в TOP_LEFT с absolute position писаниями.

Subtle: ВРЕМЯ установки position должно быть ПОСЛЕ `add_child` (который вызывает `_ready` который нормализует). Порядок в `_detach_tab_active_drag`:
```
var detached := base_panel_scene.instantiate() as BasePanel
detached.panel_id = StringName(...)
detached.panel_title_key = ...
detached.panel_title_fallback = ...
detached.min_panel_size = ...
detached.set_meta("__origin_panel_id", parent_id)
detached.set_meta("__origin_tab_id", tab_id)
parent_of_tabbed.add_child(detached)        # ← _ready() runs here, normalizes anchors
# Reparent content
body_source.remove_child(content)
detached.get_body_container().add_child(content)
# Now position (after normalize, in TOP_LEFT abs coords)
detached.position = mouse_global - Vector2(40, BasePanel.CORNER_SIZE / 2)
# Handoff drag
detached.start_drag_at(mouse_global)
```

Persistence has already loaded any saved layout for the synthetic id during `_ready()` (in `_setup_persistence`); if file existed, position/size already set per persistence. Our subsequent `position = ...` write **overrides persistence** at detach moment — correct, because if user is mid-drag, the cursor-near placement is what they want, not yesterday's saved position. Persistence's debounce timer (1s) starts on next `panel_moved` emit и saves the user's actual drag-end position.

Actually a subtle wrinkle here: if persistence loaded a position for synthetic id (old saved state) but user just NEW-detached this gesture (тот же tab, но разные detach episodes), persistence shouldn't pre-empt. **Решение**: при создании detached в active-drag — сбрасываем persistence position override:
- After `add_child`, if persistence loaded saved values: it already set position per saved. Our subsequent assignment overrides. Persistence's `_loading` flag is false at this point (it was true ONLY during `load_layout()`). Our write triggers normal `_on_state_changed` debounce → saves new position 1s later. Correct.

OK no issue. Just be aware that the persistence load happens before our position write, и `_loading` is back to false by then.

### `_origin_panel_id`/`_origin_tab_id` через meta vs export

Альтернатива — добавить explicit fields на detached panel (extends BasePanel). Но detached panel — обычная BasePanel, не subclass. Поэтому либо:
(a) Subclass `DetachedPanel extends BasePanel` с этими fields. Лишний класс ради двух StringName.
(b) Meta. Каждая Node умеет `set_meta`/`get_meta`. Без подкласса.

Берём (b). Цена — magic-string ключ `__origin_tab_id`. Документируем в spec.md и в комментарии PanelTabBar.

## Имплементация по шагам

### Step 1 — `panel_drag_handler.gd` extension (T001)

Diff (relative to current 89-line file):
```diff
 class_name PanelDragHandler
 extends Node

+signal drag_ended(release_pos: Vector2)
+
 var _base_panel: BasePanel
 var _drag_handle: Control

 var _is_dragging: bool = false
 var _drag_offset: Vector2 = Vector2.ZERO


+func is_dragging() -> bool:
+    return _is_dragging
+
+
+## Public drag handoff: caller (e.g. PanelTabBar) initiates a drag on this
+## handler's panel without an LMB-press event having been delivered to the
+## handle. Idempotent in a single gesture: if already dragging, returns no-op.
+func begin_drag_at(global_pos: Vector2) -> void:
+    if _is_dragging:
+        return
+    if not _base_panel.is_draggable() or _base_panel.is_locked():
+        return
+    _begin_drag(global_pos)
+
+
 func setup(base_panel: BasePanel, drag_handle: Control) -> void:
     ...

 func _input(event: InputEvent) -> void:
     if not _is_dragging:
         return
     if event is InputEventMouseMotion:
         _do_drag((event as InputEventMouseMotion).global_position)
     elif event is InputEventMouseButton:
         var mb := event as InputEventMouseButton
         if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
             _is_dragging = false
+            drag_ended.emit(mb.global_position)
```

3 small additions: signal declaration, `is_dragging()` getter, `begin_drag_at()` method, emit on release. Total ~12 new lines.

### Step 2 — `base_panel.gd` proxy method (T002)

Add public method:
```gdscript
## Proxy to PanelDragHandler.begin_drag_at — used by PanelTabBar for drag
## handoff during tab tear-off (no LMB-release event in between).
## No-op if drag handler doesn't exist (panel not draggable, header_visible=false).
func start_drag_at(global_pos: Vector2) -> void:
    if _drag_handler != null:
        _drag_handler.begin_drag_at(global_pos)
    else:
        push_warning("[BasePanel] start_drag_at called on '%s' with no drag handler" % String(panel_id))
```

~8 lines added. Place near other public toggle methods (`toggle_lock`/`toggle_collapse`).

### Step 3 — Loc keys (T003)

`data/localization/en.json`:
```diff
+"ui_tabs_all_detached_hint": "(All tabs detached — drag a detached panel back here)",
```

`data/localization/ru.json`:
```diff
+"ui_tabs_all_detached_hint": "(Все табы оторваны — перетащите detached-панель обратно сюда)",
```

Если файлы используют другой формат (например, не плоский JSON а вложенные секции) — добавить в правильное место. Проверить при имплементации.

### Step 4 — `panel_tab_bar.gd` (T004)

Skeleton (full ~250 lines):
```gdscript
class_name PanelTabBar
extends HBoxContainer

const META_ORIGIN_PANEL_ID := "__origin_panel_id"
const META_ORIGIN_TAB_ID := "__origin_tab_id"
const META_TAB_TITLE_KEY := "tab_title_key"
const META_TAB_TITLE_FALLBACK := "tab_title_fallback"
const VERTICAL_DRAG_THRESHOLD := 30.0

var _tabbed_panel: TabbedBasePanel
var _tabs: Array[Dictionary] = []  # see spec §5.3 layout
var _active_tab_id: StringName = &""
var _dragging_tab_id: StringName = &""
var _press_global_pos: Vector2 = Vector2.ZERO
var _floating_panels: Array[BasePanel] = []
var _placeholder_label: Label

# Set by TabbedBasePanel after _ready and before tabs are loaded
func setup(tabbed_panel: TabbedBasePanel) -> void:
    _tabbed_panel = tabbed_panel
    _build_placeholder()
    _discover_and_register_tabs()
    _restore_detached_from_persistence()
    _set_active(_first_attached_tab_id())
    _refresh_placeholder_visibility()

# ... (see tasks.md for the per-method breakdown)
```

Method roster (with task IDs in `tasks.md`):
- `_build_placeholder()` — создаёт скрытый Label с текстом из loc key.
- `_discover_and_register_tabs()` — итерирует BodyContainer.get_children(), регистрирует каждый Control как tab.
- `_restore_detached_from_persistence()` — для каждой детектированной таб читает synthetic key из ConfigFile, если есть — `_detach_tab_silent` (без drag handoff, просто spawn detached).
- `_make_tab_button(tab)` — создаёт Button с UiTheme styling, connects gui_input.
- `_on_tab_button_input(event, tab_id)` — обработка LMB-press (start tracking) + threshold check + click detection.
- `_input(event)` — global motion + release tracking pока `_dragging_tab_id != &""`.
- `_detach_tab_active_drag(tab_id, mouse_global)` — full detach pipeline c handoff drag.
- `_detach_tab_silent(tab_id, restore_layout)` — detach without handoff (used at load time).
- `_on_floating_drag_ended(panel, release_pos)` — connected к detached panel's drag_ended.
- `_reattach(panel)` — reverse of detach + cleanup synthetic section.
- `_set_active(tab_id)` — visibility toggling в BodyContainer + button highlight.
- `_refresh_placeholder_visibility()` — show/hide placeholder в зависимости от attached count.
- `_synthetic_panel_id(tab_id)` — `StringName("%s__%s__detached" % [_tabbed_panel.panel_id, tab_id])`.
- `_layout_section_key(synthetic_id)` — replicates PanelPersistence._compute_section_key logic для нашего synthetic id (нужен scope, который определяется аналогично).
- `_erase_layout_section(section_key)` — load `user://layouts.cfg`, erase section, save.

### Step 5 — `tabbed_base_panel.gd` (T005)

```gdscript
class_name TabbedBasePanel
extends BasePanel

const PANEL_TAB_BAR_SCRIPT := preload("res://scripts/presentation/ui_panels/internal/panel_tab_bar.gd")

var _tab_bar: PanelTabBar


func _ready() -> void:
    super._ready()
    _setup_tab_bar()


func _setup_tab_bar() -> void:
    if _title_label != null:
        _title_label.visible = false  # hide BasePanel's title — tabs are the identity
    
    # PanelTabBar instance lives at the start of HeaderRow with EXPAND
    _tab_bar = PanelTabBar.new()
    _tab_bar.name = "TabBar"
    _tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _tab_bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _header_row.add_child(_tab_bar)
    _header_row.move_child(_tab_bar, 0)  # before LockButton/CollapseButton/RightSpacer
    _tab_bar.setup(self)


# ── Public API ─────────────────────────────────────────────────────

func add_tab(content: Control, tab_id: StringName, title_key: StringName = &"", title_fallback: String = "") -> void:
    if not title_key.is_empty():
        content.set_meta(PanelTabBar.META_TAB_TITLE_KEY, title_key)
    if not title_fallback.is_empty():
        content.set_meta(PanelTabBar.META_TAB_TITLE_FALLBACK, title_fallback)
    content.name = String(tab_id)  # tab_id derives from node name
    _body_container.add_child(content)
    _tab_bar.register_tab(content)


func remove_tab(tab_id: StringName) -> void:
    _tab_bar.unregister_tab(tab_id)


func get_active_tab_id() -> StringName:
    return _tab_bar.get_active_tab_id()
```

`add_tab`/`remove_tab` — тонкие фасады. Реальная работа — в TabBar.

### Step 6 — `tabbed_base_panel.tscn` (T006)

Inherited Scene from `base_panel.tscn`. Editable Children ON.

Изменения:
- Set `script = ExtResource(<tabbed_base_panel.gd>)` на root (через `gd_scene format=3 inherits="..."` + ext_resource).
- TitleLabel.visible = false (override).
- HeaderRow остаётся как есть; PanelTabBar добавляется в `_setup_tab_bar()` runtime, не в .tscn (потому что PanelTabBar — script-only HBoxContainer без своей сцены, простота).

Минимальный текст .tscn:
```
[gd_scene format=3 load_steps=2 inherits="res://scenes/ui/panels/base_panel.tscn"]

[ext_resource type="Script" path="res://scripts/presentation/ui_panels/tabbed_base_panel.gd" id="1_tbp"]

[node name="BasePanel" parent="." instance=ExtResource("1_tbp_unused")]
script = ExtResource("1_tbp")

[node name="TitleLabel" parent="VBoxContainer/HeaderPanel/HeaderRow" index="0"]
visible = false
```

(Конкретный синтаксис подбирается в Godot UI; if Inherited Scene plain не работает с editing visible — fallback: TabbedBasePanel в `_setup_tab_bar()` сам ставит `_title_label.visible = false`, .tscn даже не override'ит. Вариант: создать .tscn вообще без overrides — все правки делает script).

Решающий выбор при имплементации — может .tscn быть пустым inherited (только ext_resource нового скрипта), а вся работа в `_ready`. Это проще, dependency на Inherited Scene + Editable Children сложнее. Беру "пустой inherited" подход.

### Step 7 — Demo сцена (T007)

`scenes/ui/panels/tabbed_panel_demo.tscn` — standalone Control с одним TabbedBasePanel в центре. 3 tabs:
- `Tab A` — Label "I am tab A".
- `Tab B` — VBoxContainer с парой Buttons.
- `Tab C` — Label "Empty tab C".

Используется только для smoke. Возможно живёт как UI Catalog entry в будущем.

`tabbed_panel_demo.gd` — пустой Node script для root, никакой логики. Tabs объявлены целиком через .tscn.

### Step 8 — Smoke + AC прохождение (T010-T013)

Прогон AC1-AC12 из spec.md в Godot. Каждый AC — entry в чек-лист в `tasks.md`. Если что-то fails — finding в `findings.md` + блокер до правки.

## Risks

- **R1 (drag handoff в Godot 4.6).** `begin_drag_at` для нового panel'а — не тестировано в этом проекте раньше. Возможный edge-case: если `_input(event)` PanelDragHandler нового panel'а не получает первое motion event после handoff (потому что mouse-grab был у tab-button до этого момента). Mitigation: при handoff явно вызвать `Input.warp_mouse(...)` НЕ нужно (мышь уже там). Если motion не приходит — в `begin_drag_at` после set `_is_dragging=true` дополнительно делаем `_do_drag(global_pos)` синхронно, чтобы panel «снэплась» к курсору. Тестируется на T010.
- **R2 (`_normalize_anchors_to_top_left` при default base_panel.tscn anchors).** В base_panel.tscn anchors — TOP_LEFT (per spec 057 fix). Так что normalize должен быть no-op для detached panel. Mitigation: подтверждаем в T010, проверяем absolute position writes работают сразу после `add_child`.
- **R3 (порядок _ready в TabbedBasePanel).** `super._ready()` сначала, потом `_setup_tab_bar()`. Внутри `_setup_tab_bar()` — set `_title_label.visible = false` происходит после того как BasePanel уже сделал `_apply_theme()` и текст применил. Порядок не должен иметь значения, но если апnly_theme в lazy-mode что-то делает — surface при имплементации. Mitigation: явный `super._ready()` (per spec 057 trap) и тестирование в T010.
- **R4 (cleanup synthetic section при tree_exiting).** Если detached panel удаляется через `queue_free` (не через reattach) — тогда `_flush_save` в его `tree_exiting` сохраняет synthetic section с актуальной position. Это ОК для случая «scene close с detached в air» (next load восстановит). Но при reattach мы хотим erase secion — это делаем явно ДО `queue_free`. Если порядок нарушится (queue_free до erase) — TabBar после reattach видит synthetic section заново, на следующем reload снова detach. Mitigation: в `_reattach` строго: erase section → reparent content → queue_free panel. Тест на AC8.
- **R5 (collapse + tear-off interaction).** Collapsed tabbed panel — body скрыт, tabs видны (header виден). Должен ли drag tab из collapsed-родителя detach'ить? Семантика мутна. По умолчанию: detach отключён, когда parent.is_collapsed() = true. Mitigation: проверка в `_detach_tab_active_drag`: `if _tabbed_panel.is_collapsed(): return`. Surface при имплементации; в smoke (T010) — попытка detach из collapsed parent должна быть no-op.
- **R6 (lock + tear-off interaction).** Locked tabbed panel — drag/resize заблокированы. Должен ли detach срабатывать? Симметрично: если panel locked, drag tab → не detach, и не click переключение (потому что lock значит «не редактируем»). На пресс LMB на tab-button locked panel'а — switch активного НЕ происходит, drag НЕ срабатывает. Mitigation: проверка `is_locked()` в начале `_on_tab_button_input`. Surface при имплементации; AC из spec не проверяет locked state — finding на будущее или smoke ad-hoc.
- **R7 (Inherited Scene quirks для tabbed_base_panel.tscn).** Если Inherited Scene + Editable Children не позволяют сохранить именно нужный override (TitleLabel.visible) — fallback на pure-script approach. См. Step 6.
- **R8 (Persistence section key collision).** Synthetic id `<parent_id>__<tab_id>__detached` использует `__` как separator. Если кто-то назовёт panel или tab `foo__bar` — secrionkey станет `parent_id__foo__bar__detached`, что валидно. Если tab_id в одной панели коллизионно совпадёт с parent_id другой панели после '__' концатинации — теоретическая коллизия. Vanishingly unlikely в практике (требует конкретной комбинации). Если беспокоит — заменить separator на что-то экзотичнее (тильда `~~` ?). Mitigation: документируем convention в комментарии PanelTabBar (avoid `__` in panel_ids and tab_ids).

## Acceptance verification

После всех T001-T009 запустить smoke по AC1-AC12 из spec.md:
- AC1-AC2 — visibility, click switching.
- AC3-AC4 — tear-off thresholds.
- AC5 — re-attach к origin.
- AC6 — rejection of foreign tab-bar (требует второй TabbedBasePanel в demo сцене для smoke).
- AC7-AC8 — persistence freshness и cleanup.
- AC9 — empty placeholder.
- AC10 — anchors normalization (требует demo сцены с не-default anchors).
- AC11-AC12 — no regressions в BasePanel и существующих panels.

Если хоть один AC fail — блокер mergi 058, спек продолжается, finding в `findings.md`.

После прохождения всех AC — push ветки + PR-creation URL Андрею.
