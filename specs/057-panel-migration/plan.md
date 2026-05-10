# 057 — Plan: Panel migration to BasePanel

Спек: [`spec.md`](./spec.md). Все Q-057-1..7 резолвлены.

## Что дальше (TL;DR)

Шесть точечных изменений + smoke:

1. **5 .gd файлов панелей** — `extends PanelContainer` → `extends BasePanel`, удалить DraggablePanel preload + `_install_drag()` + `add_theme_stylebox_override("panel", ...)` в `_ready()`. Тело панели строится в `get_body_container()` вместо `self`. Public API не трогаем.
2. **`scenes/dev/dialogue_trigger_panel.tscn`** — пересоздать с нуля как instance от `base_panel.tscn` + ext_resource на свой .gd. Старая 6-строчная сцена удаляется.
3. **`scenes/dev/map_editor.tscn`** — 5 panel nodes конвертируются из `[type="PanelContainer"] script=...` в `[instance=base_panel.tscn] script=...`. Anchor/offset значения сохраняются 1:1, добавляются BasePanel экспорты (`panel_id`, `panel_title_key`, `panel_title_fallback`, `min_panel_size`).
4. **Smoke** в Godot — открыть редактор, проверить parse, drag/resize/collapse/lock/persistence, save/load roundtrip, dialogue trigger CRUD.
5. **Cleanup verification** — grep'ы из AC8 возвращают пусто.

Остальное (исправление content bugs внутри панелей, расширение wave-данных, validation pipeline) — в Specs 060-062. Если по ходу всплывают неожиданности в `BasePanel` framework — спек паузится.

## Архитектурное обоснование

### Почему instance pattern, а не Inherited Scene

В `ui_catalog.tscn` (наш единственный реальный потребитель `BasePanel`) панели уже placement'ятся как `instance=ExtResource("base_panel.tscn")`, а не как Inherited Scene. Это рабочий паттерн: каждый child-node `BasePanel.tscn` доступен через `index="N"` override, для добавления своего контента в `BodyContainer` указывается `parent="X/VBoxContainer/BodyPanel/BodyContainer"`. Editable Children **не нужно** включать — instance автоматически даёт доступ к именованным детям.

Inherited Scene — другой механизм: `[gd_scene inherits="..."]`, требует Editable Children, генерирует другую структуру в .tscn. Для наших целей оба работают, но instance пригодится за консистентность с уже работающим catalog'ом.

Один важный момент: при `instance=base_panel.tscn` мы **меняем root script** через `script = ExtResource(...)`. Это работает, потому что `BasePanel extends Control` — наш subclass `extends BasePanel`, Godot цепляет наш скрипт поверх root'а инстанса, родительский `_ready` отрабатывает корректно, наш `_ready` вызывается после.

### Почему body building остаётся процедурным

4 из 5 панелей сейчас строят свой UI **в коде** в `_build_ui()` — там `VBoxContainer`'ы, `GridContainer`'ы, `Button`'ы, `LineEdit`'ы, добавленные через `add_child()`. Перенос всего этого в .tscn — отдельная большая работа (≈80% времени миграции), не нужная для «починить parse-error». Дешёвое решение: оставить процедурное построение, но менять `add_child(x)` на `get_body_container().add_child(x)` (или сохранять reference на body внутри `_ready`).

Это идиоматично для `BasePanel` — `get_body_container()` явно публичный метод (`base_panel.gd:282`).

### Почему 1:1 layout transfer

Spec 058 будет полностью переделывать редактор — позиции панелей в новом редакторе свои. Spec 059 сжимает 5 панелей в 4 (LayersPanel + WavePanel + ToolPanel + LevelMetaPanel). Любые попытки «перепозиционировать на будущее» в 057 — либо premature (новая раскладка ещё не утверждена), либо угадывание. Дешевле: пользователь видит знакомый редактор, drag'ает куда удобно, BasePanel persistence запоминает.

### Persistence стартует пустым

`BasePanel.persistence_scope_override = &""` (default) → auto-detect scope как `<scene_path>::<panel_id>`. Для всех 5 панелей scope станет `scenes/dev/map_editor.tscn::<panel_id>`. В `user://layouts.cfg` для этих ключей нет записей → `BasePanel` фолбечится на defaults (значения экспортов в .tscn) при первом открытии. Потом — сохраняется.

Семантика "первый раз после миграции" = "новая установка с пустым layouts.cfg". Не нужно migration logic, не нужно seed файла. Просто корректные дефолты в `.tscn`.

## Pattern per panel

Базовый паттерн миграции одинаковый для всех 5. Различия — в значениях экспортов и в том, какой именно body building код переписать.

### Общая трансформация .gd

```diff
 # scripts/presentation/dev/<panel>.gd

-extends PanelContainer
+extends BasePanel

-const DraggablePanel = preload("res://scripts/presentation/dev/draggable_panel.gd")
-
 # ... rest of script header ...

 func _ready() -> void:
-    add_theme_stylebox_override("panel", UiTheme.make_panel_stylebox())
-    _build_ui()                  # создавал _title_label + content
-    _install_drag(_title_label)
+    _build_body()                # создаёт ТОЛЬКО content в get_body_container()

-func _install_drag(handle: Control) -> void:
-    var dragger := DraggablePanel.new()
-    add_child(dragger)
-    dragger.setup(self, handle)
-
-var _title_label: Label
```

В `_build_body()`:
- Выкинуть создание собственного `_title_label` (header теперь BasePanel'ный).
- Все `add_child(x)` направлены в `var body := get_body_container(); body.add_child(x)`.
- Если код предполагал `self.size`, `self.position`, `self.add_child` — пройтись и заменить на body-relative или оставить если относится к самой панели как целому.

### Per-panel экспорты в `map_editor.tscn`

Из `scenes/dev/map_editor.tscn` на момент перед миграцией. Anchor/offset сохраняются 1:1.

| Panel | `panel_id` | `panel_title_key` | `panel_title_fallback` | `min_panel_size` | anchor / offset |
|---|---|---|---|---|---|
| FloorPalettePanel | `&"floor_palette"` | `&"ui_floor_palette_title"` | `"Пол"` | `(360, 180)` | anchor `(0.5, 1.0, 0.5, 1.0)`, grow `(2, 0)`, offsets `(-260, -200, 260, -16)` |
| ObjectPalettePanel | `&"object_palette"` | `&"ui_object_palette_title"` | `"Объекты"` | `(280, 240)` | anchor `(1, 0, 1, 1)`, grow `(0, ?)`, offsets `(-336, 160, -16, -240)` |
| ToolPanel | `&"tool"` | `&"ui_tool_panel_title"` | `"Инструменты"` | `(180, 200)` | anchor `(?, 0.5, ?, 0.5)`, grow `(?, 2)`, offsets `(16, -120, 220, 120)` |
| LevelMetaPanel | `&"level_meta"` | `&"ui_level_meta_title"` | `"Уровень"` | `(280, 100)` | anchor `(1, 0, 1, 0)`, grow `(0, ?)`, offsets `(-360, 16, -16, 124)` |
| DialogueTriggerPanel | `&"dialogue_trigger"` | `&"ui_dialogue_trigger_title"` | `"Триггеры диалогов"` | `(220, 200)` | anchor `(0, 1, 0, 1)`, grow `(?, 0)`, offsets `(16, -230, 246, -8)` |

`min_panel_size` подобран так, чтобы:
- Не быть меньше `BasePanel.min_panel_size` дефолта `(120, 88)`.
- Уместить минимально функциональный контент (для палитр — хотя бы одну строку плиток + scroll; для tool — хотя бы 2 кнопки).
- Быть меньше текущего размера панели в map_editor.tscn (чтобы юзер мог реально ужать).

При имплементации проверить что в Godot Inspector `min_panel_size` действительно работает как `custom_minimum_size` на root — это `BasePanel` обязан, проверка часть smoke.

`grow_horizontal/grow_vertical` оставляем 1:1 с текущим .tscn — Godot их интерпретирует относительно anchor preset, не относительно panel logic, миграция нейтральна.

### Per-panel — что переезжает из header в body

Если в `_build_ui()` есть код который добавляет элементы в собственный header-row (рядом с title) — они переезжают в body первой строкой.

Подозрение по коду (требует подтверждения при имплементации):
- **`level_meta_panel`** — может иметь Save/Load/Playtest/Exit кнопки в шапке. Переедут в body как первая строка `HBoxContainer`.
- **`dialogue_trigger_panel`** — есть кнопки CRUD (Add / Delete / Edit) — в body, первая строка.
- **`floor_palette` / `object_palette` / `tool`** — судя по коду, шапка чистая (только `_title_label`), header-row пустой. Confirm при чтении кода в T001-T004.

Если по факту в каком-то теле остался `_title_label` как visual separator — оценить, нужен ли он:
- Header BasePanel'а уже показывает title локализованным. Дублирование избыточно.
- Если нужна группировка («над этой группой кнопок — подзаголовок») — это не title, это section heading, реализуется отдельным `Label` с другим font_size/color (см. `UiTheme.apply_label_kind(label, &"section")` если такое есть; иначе просто Label).

Дефолт: `_title_label` в body удаляется. Если visual loss — finding F-057-3 обновляется конкретикой.

### `dialogue_trigger_panel.tscn` re-create

Текущая сцена (6 строк):
```
[gd_scene load_steps=2 format=3 uid="uid://dialogue_trigger_panel"]
[ext_resource type="Script" path="res://scripts/presentation/dev/dialogue_trigger_panel.gd" id="1_dtp"]
[node name="DialogueTriggerPanel" type="PanelContainer"]
script = ExtResource("1_dtp")
```

Новая (target):
```
[gd_scene load_steps=3 format=3 uid="uid://dialogue_trigger_panel"]
[ext_resource type="PackedScene" path="res://scenes/ui/panels/base_panel.tscn" id="1_bp"]
[ext_resource type="Script" path="res://scripts/presentation/dev/dialogue_trigger_panel.gd" id="2_dtp"]
[node name="DialogueTriggerPanel" instance=ExtResource("1_bp")]
script = ExtResource("2_dtp")
panel_id = &"dialogue_trigger"
panel_title_key = &"ui_dialogue_trigger_title"
panel_title_fallback = "Триггеры диалогов"
min_panel_size = Vector2(220, 200)
```

UID сохраняем (`uid://dialogue_trigger_panel`) — на случай если кто-то ссылается по UID. Способ re-create: создать .tscn в Godot UI как Inherited Scene from `base_panel.tscn`, прикрепить script, выставить экспорты, сохранить, проверить что итоговый текст ≤ 10 строк. Альтернатива: вручную написать .tscn (если структура простая, что подтверждено). Выбор — при имплементации T005.

### Order of operations

1. Сначала меняем `.gd` файлы (T001-T005). После этого `map_editor.tscn` всё ещё показывает старые `[type="PanelContainer"]` ноды — со script, который теперь `extends BasePanel`. Godot скорее всего бросит warning «root must be Control because BasePanel extends Control» — это ок, парс не падает, просто ругается.
2. Потом конвертируем `map_editor.tscn` (T006). Каждая нода становится instance, экспорты выставлены.
3. Потом dialogue_trigger_panel.tscn re-create (T005 содержит и .gd и .tscn — иначе панель не работает).
4. Smoke (T007-T010).

Альтернативный порядок (сцены первыми) сломает каждую панель отдельно при попытке открыть `map_editor.tscn` посередине. Текущий — пошагово, после каждого T возможно открыть сцену и убедиться что прогресс, без полной поломки.

## Risks

- **R1.** `instance=base_panel.tscn` поверх PanelContainer — изменение root type с `PanelContainer` на `Control` (BasePanel extends Control). Layout-side это разный thing: PanelContainer был ContainerNode, BasePanel — Control с собственным Resize/Drag. Дефолтные anchor/offset должны работать и там и там, но если были `mouse_filter` overrides в map_editor.tscn для этих нод — они снесутся при instance замене, и BasePanel свои выставит. Mitigation: проверить `grep mouse_filter scenes/dev/map_editor.tscn` после миграции.
- **R2.** `MapEditorController` хранит `NodePath` к панелям — `floor_palette_path = NodePath("HUD/FloorPalettePanel")` и т.п. Это не сломается, имена нод сохраняются. Но если controller где-то делает `panel.size`, `panel.add_child(...)`, `panel.set_meta(...)` — это могло работать со старым `PanelContainer` иначе. Mitigation: в T006 `grep -n "_floor_palette\|_object_palette\|_tool_panel\|_level_meta\|_dialogue_trigger" scripts/presentation/dev/map_editor_controller.gd | head -50` и пройти каждый callsite.
- **R3.** BasePanel persistence requires `panel_id` non-empty. Если забыть выставить → panel persistence silently skipped (см. base_panel.gd:338). Mitigation: T006 explicit check `panel_id` непустой для всех 5.
- **R4.** Header collapse cascade. У BasePanel `collapsed` скрывает `BodyPanel + ResizeFrame` (см. PanelCollapseHandler). Если внутри body есть EventBus-listeners или Timer'ы, которые крутятся постоянно — они продолжают крутиться даже когда body скрыт. Не баг (это как раз желаемое поведение), но если какая-то панель что-то рисует только когда видна — surface при имплементации.

## Acceptance verification

После всех T001-T006 запустить smoke по AC1-AC8 из spec.md. Если хоть один AC fail — это блокер mergi 057, спек продолжается, finding в `findings.md` (создать на T007 если потребуется).
