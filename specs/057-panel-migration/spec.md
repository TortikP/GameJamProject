# Spec 057 — Panel migration to BasePanel

**Статус:** Spec.
**Тип:** spec-S (1 день).
**Ветка:** `andrey/057-panel-migration` → `staging`.
**Обсуждали:** Андрей (идея, scope, A/B/C развилки), мозг (миграция-план).
**Зависимости:** Spec 055 (`ui-panels` framework, merged как PR #145).
**Используется:** Spec 058 (`level-editor`: architecture from scratch) — нужен рабочий старый редактор для параллельной жизни до Spec 059.
**Дизайн:** [`docs/systems/ui-panels/design.md`](../../docs/systems/ui-panels/design.md) (фреймворк), [`docs/systems/level-editor/design.md`](../../docs/systems/level-editor/design.md) §8 (контекст).

---

## 1. Что строим (one-paragraph summary)

После merge Spec 055 (PR #145) `scripts/presentation/dev/draggable_panel.gd` удалён в Phase 7. Пять dev-панелей (`floor_palette`, `object_palette`, `tool`, `level_meta`, `dialogue_trigger`) до сих пор подгружают его через `preload(...)` и зовут `DraggablePanel.new()` — `scenes/dev/map_editor.tscn` не парсится, редактор недоступен. Спек 057 — точечная pass-through миграция всех 5 панелей с `extends PanelContainer + DraggablePanel mixin` на `extends BasePanel` (Godot Inherited Scene / instance pattern). Public API панелей (signals, методы) сохраняется 1:1 — `MapEditorController` и сцены, использующие эти панели, не трогаем. Никаких UX-изменений внутри тел панелей. Цель — восстановить парсеабельность `map_editor.tscn` и единое поведение drag/resize/collapse/lock/persistence у всех 5 панелей.

## 2. Проблема

`map_editor.tscn` сейчас не открывается из-за пяти `preload("res://scripts/presentation/dev/draggable_panel.gd")` на удалённый файл. Симптом — Godot Parser error при попытке открыть сцену или запустить редактор уровней. Никита (диалоги) и Стасян (тайлы/баланс) не могут авторить контент. Андрей подтвердил: «не боимся слома редактора, в ближайшее время в нём работать не будут» (контекст: spec 058 готовит полный re-do `MapEditorController`'а). Тем не менее, до прихода 058 + 059 параллельная жизнь старого редактора — гарантия, что Никите есть на чём работать, если он понадобится. И сейчас сборка не запускается вовсе.

## 3. Цель

1. **Все 5 панелей** мигрированы на `BasePanel`. После миграции каждая получает встроенные drag, resize (8 handles), collapse, lock, persistence — без своей реализации.
2. **`map_editor.tscn` парсится и открывается** из главного меню. Редактор уровней работает: палитры реагируют на клики, `MapEditorController` принимает все сигналы как раньше, сохранение карт в JSON не сломано.
3. **Public API панелей сохранён 1:1.** Сигналы (`tile_picked`, `tool_changed`, `save_requested` и т.п.) и публичные методы (`setup`, `select_tile`, `bind_level` и т.п.) остаются с теми же именами и сигнатурами. Тела этих методов могут переехать (BodyContainer вместо self), но контракт наружу неизменен.
4. **Унифицированный header.** Title + lock-icon + collapse-icon — без вариаций. Если в текущей панели в шапке что-то нестандартное (например кнопки add/remove в `dialogue_trigger`) — это переезжает в body.
5. **Persistence стартует с чистого листа.** В `user://layouts.cfg` нет записей для секции `scenes/dev/map_editor.tscn::*`. Дефолтные позиции/размеры в новых .tscn-нодах **повторяют текущие 1:1** — при первом открытии после миграции редактор выглядит как до неё. После — `BasePanel` сам ведёт persistence, юзер двигает/ресайзит, всё запоминается.
6. **Удаление мёртвого preload.** Все ссылки на `draggable_panel.gd` исчезают. `grep -rn "DraggablePanel\|draggable_panel" scripts/ scenes/` возвращает пусто.

## 4. Не-цели

- **Объединение палитр гексов и объектов в одну панель** с табами и tear-off — это работа Spec 059 (level-editor: layers + palettes), теперь зафиксированная в [`docs/systems/level-editor/design.md`](../../docs/systems/level-editor/design.md) §8 Spec 1 + OQ-7. Здесь — 5 отдельных панелей в текущих позициях.
- **Редизайн контента панелей.** Палитра гексов остаётся палитрой гексов, инструменты остаются инструментами. Никаких новых кнопок, group/layout reshuffles, спрятанных опций — даже если по ходу видно что «можно лучше».
- **Расширение wave-данных** (`respawn_player`, spawner `amount/delay`, `is_special` enum) — Spec 060.
- **Cleanup `dialogue_triggers.id` vs `dialogue_id`** — Spec 060 (OQ-2 в level-editor design).
- **Validation pipeline** — Spec 061.
- **WavePanel UX timeline** — Spec 062.
- **Миграция `WavePanel`** (`scripts/presentation/dev/wave_panel.gd`). Эта панель уже `extends PanelContainer` без `DraggablePanel` (в коде нет преlloada), парсеабельность не блокирует. Если внутри есть свой ad-hoc drag — finding в §7, мигрируется отдельно вместе со Spec 062 (там она и так переделывается полностью).
- **Расширение `BasePanel` под tabs/tear-off** — нужно для Spec 059, не для 057. См. OQ-7 в level-editor design.
- **Миграция in-game панелей** (skill HUD, character info, popups) — out of scope, отдельные решения после стабилизации редактора.

## 5. Структура изменений (high-level shape)

### 5.1. Pattern для всех 5 панелей

```
было:
  extends PanelContainer
  const DraggablePanel = preload("res://scripts/presentation/dev/draggable_panel.gd")

  func _ready() -> void:
    add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
    _build_ui()                          # создаёт _title_label, content
    _install_drag(_title_label)          # вешает DraggablePanel.new()

  func _install_drag(handle): ...        # удалить
  var _title_label: Label                # удалить (есть у BasePanel)

стало:
  extends BasePanel
  # никаких DraggablePanel.preload

  func _ready() -> void:
    super._ready()                       # неявно вызывается; super не нужен
    _build_body()                        # создаёт ТОЛЬКО content, кладёт в get_body_container()

  # никаких _install_drag, никакого add_theme_stylebox_override("panel", ...)
```

`panel_id` / `panel_title_key` / `panel_title_fallback` / `min_panel_size` — выставляются в `.tscn` через export-параметры BasePanel'а, не в коде. Дефолтные значения для каждой панели зафиксированы в [`plan.md` §Pattern per panel](./plan.md).

### 5.2. .tscn migration pattern

**4 script-only панели** (`floor_palette`, `object_palette`, `tool`, `level_meta`) сейчас живут как `[node type="PanelContainer" parent="HUD"] script = ExtResource(...)` прямо в `map_editor.tscn`. После миграции:
```
[node name="FloorPalettePanel" parent="HUD" instance=ExtResource("base_panel_tscn")]
script = ExtResource("floor_palette_panel_gd")
panel_id = &"floor_palette"
panel_title_key = &"ui_floor_palette_title"
panel_title_fallback = "Пол"
offset_left = ...     # текущие позиции из map_editor.tscn 1:1
offset_top  = ...
offset_right = ...
offset_bottom = ...
min_panel_size = Vector2(<panel-specific>, <panel-specific>)
```

**`dialogue_trigger_panel.tscn`** (отдельный файл) — пересоздаётся с нуля как новая сцена с тем же uid (`uid://dialogue_trigger_panel`), root становится instance от `base_panel.tscn` с прикреплённым `dialogue_trigger_panel.gd`. Старая 6-строчная сцена удаляется в том же коммите. Re-create вместо ручной правки — по решению Андрея (clarify Q-057-2 → B): чище, без скрытых .tscn-артефактов.

### 5.3. Удаление dead code

- `scripts/presentation/dev/draggable_panel.gd` — уже удалён в 055 Phase 7. Доп.действий не нужно, проверка `find scripts/ -name "draggable_panel*"` должна вернуть пусто (подтверждено перед написанием спека).
- `_install_drag()` функции и `_title_label` поля в 5 панелях — удаляются как часть миграции.
- `add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())` в `_ready()` 5 панелей — удаляются (BasePanel сам ставит стайлбокс).

## 6. Acceptance criteria

- **AC1.** `scenes/dev/map_editor.tscn` парсится без ошибок Godot. Открытие из главного меню (Map Editor → Open / New) даёт рабочую сцену.
- **AC2.** Все 5 панелей видны в текущих позициях (1:1 c pre-057 раскладкой). Title bar содержит локализованный title + lock-icon + collapse-icon. Body содержит то же содержимое что было — палитры, кнопки, поля, никаких регрессий контента.
- **AC3.** Drag, resize (за 8 handles), collapse (`−`/`+`), lock (замочек), persistence (закрыл-открыл редактор → панели на тех же местах с теми же размерами) — работают у всех 5 панелей.
- **AC4.** Public API не сломан. `MapEditorController` подключается к сигналам без правок (`tile_picked`, `erase_picked`, `tool_changed`, `brush_size_changed`, `save_requested`, `load_requested`, `playtest_requested`, `exit_requested`, `name_changed`, `object_picked`, `spawner_picked`, `trigger_created`, `trigger_updated`, `trigger_deleted`, `trigger_selected`). Публичные методы (`setup`, `select_tile`, `select_nth`, `select_object`, `select_spawner`, `set_level_name`, `set_dirty`, `bind_level`, `select_trigger`) вызываются и работают.
- **AC5.** Smoke сценарий «новый уровень»: новый level → выбор tile в floor palette → клик по гексу → tile появился → выбор object → клик → object появился → set name → save → JSON файл записан, открывается обратно без потерь.
- **AC6.** Smoke сценарий persistence: drag floor_palette в новое место, resize до min_size, collapse → выйти из редактора → перезайти. Floor palette на новом месте, того же размера, collapsed.
- **AC7.** Smoke сценарий dialogue_triggers (Никитин workflow): загрузить `data/maps/level_*.json` со существующими триггерами → triggers видны в DialogueTriggerPanel → выбрать → отредактировать поле → сохранить → JSON-сравнение `before/after` совпадает кроме изменённого поля.
- **AC8.** `grep -rn "DraggablePanel\|draggable_panel" scripts/ scenes/` возвращает пусто. `grep -rnE "extends PanelContainer" scripts/presentation/dev/(floor_palette|object_palette|tool|level_meta|dialogue_trigger)_panel.gd` возвращает пусто.

## 7. Findings (для других)

- **F-057-1 (для всех):** `scripts/presentation/dev/wave_panel.gd` — `extends PanelContainer`, но **не** использует удалённый `DraggablePanel` (проверено grep'ом). Парсеабельность не блокирует, миграция отложена до Spec 062 где WavePanel переделывается под timeline. Tech-debt запись добавлять не нужно — уже зафиксировано в level-editor design §8 как Spec 5.
- **F-057-2 (для Андрея, Никиты):** Persistence в `user://layouts.cfg` начинается с чистого листа — записи для `scenes/dev/map_editor.tscn::*` не существуют до первого drag/resize/collapse/lock после миграции. Дефолтные позиции в .tscn — это «то, что юзер увидит при первом запуске», а не то, что хранится в layouts.cfg. Семантика отличается от типичной user-config миграции (нет «старых записей, которые надо обновить»).
- **F-057-3 (для Алексея, Андрея):** В коде 5 панелей встречаются паттерны `_build_ui()` с создаванием `_title_label` ВНУТРИ body (не как параметр для `_install_drag`, а как настоящий лейбл в UI). После миграции: BasePanel сам показывает title в header. Если внутри body всё ещё нужен заголовок-лейбл (например `"Tools"` над списком инструментов как visual separator) — это решается отдельно от title в header. Surface при имплементации T003-T005 — нужно ли в каком-то теле дублировать title-как-лейбл, или header-title достаточно. Дефолт: header-title достаточно, body-title удаляется.

## 8. Resolved decisions (Q-057-*)

- **Q-057-1 → A.** Мигрируем все 5 панелей, не только 3 «долгоживущих». Доминанта: ровный результат, и 3 недели до 059 редактор будет в стабильном состоянии. (Альтернатива B — мигрировать только tool/level_meta/dialogue_trigger, оставить парсеры floor_palette/object_palette как stub'ы — экономила ~3-4 часа, отвергнута.)
- **Q-057-2 → B.** `dialogue_trigger_panel.tscn` пересоздаём с нуля. (Альтернатива A — Inherited Scene с Editable Children поверх существующего .tscn — отвергнута: меньше скрытых артефактов в re-create.)
- **Q-057-3 → 1:1 layout transfer.** Текущие offset_left/top/right/bottom из `map_editor.tscn` копируем дословно. Никаких объединений, перестановок. Объединение палитр и tear-off — Spec 059 (см. design level-editor §8).
- **Q-057-4 → resolved by reading code.** Public API определяется напрямую signals + public methods в .gd-файлах — список зафиксирован в AC4. Никитин документ с переменными и работами уже впитан в `docs/systems/level-editor/design.md` §7 (Data model deltas) и относится к Spec 060, не к 057.
- **Q-057-5 → унифицированный header.** Никаких вариаций (search-bar, add-button, dropdown в title-row). Если в текущей панели такие элементы есть — переезжают в body. См. F-057-3 для того, что делать с body-internal title labels.
- **Q-057-6 → per-panel min_panel_size.** Каждая панель проставляет свой `min_panel_size` через export — без общей константы. Конкретные значения зафиксированы в plan.md §Pattern per panel (на основе текущих offset-размеров).
- **Q-057-7 → smoke 7-pointer.** AC1-AC8 покрывают: parse, видимость, drag/resize/collapse/lock, persistence, public API, save/load roundtrip, dialogue triggers roundtrip, dead-code removal.

## 9. Out of scope

- Любые UX-улучшения панелей (даже «мелочи на месте»). Если что-то болит — finding.
- Любые правки `MapEditorController` кроме того, что нужно для AC4 (он не должен правиться ВООБЩЕ — если правится, что-то пошло не по плану).
- Any new loc keys. Все 5 ключей уже существуют (`ui_floor_palette_title`, `ui_object_palette_title`, `ui_tool_panel_title`, `ui_level_meta_title`, `ui_dialogue_trigger_title`).
- Any new BasePanel features. Если по ходу выяснится, что чего-то не хватает в BasePanel — Spec 057 паузится, заводится дочерний спек на ui-panels framework, потом возвращаемся.

## 10. Dependency / sequencing

- Этот спек **не блокирует** Spec 058 концептуально, но блокирует его **физически**: Spec 058 вертикальный срез открывает редактор, а редактор не парсится. Поэтому 057 идёт первым.
- После merge 057 в staging — review pause перед стартом 058 (стандартный workflow). Если 057 откроет неприятные сюрпризы в `BasePanel` (например, baseline persistence не работает на per-scene scope так как ожидалось) — это окно чтобы зарепортить и поправить до 058.
