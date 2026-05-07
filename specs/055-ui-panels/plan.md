# 055 — Plan: UI Panels framework

Спек: [`spec.md`](./spec.md). Дизайн-док: [`docs/systems/ui-panels/design.md`](../../docs/systems/ui-panels/design.md).
Все Q (Q1-Q5 из preflight Clarify) резолвлены в spec.md.
Все OI (OI-1..OI-4) — план разрешения внутри Tasks или явный defer.

## Что дальше (TL;DR)

Новая система с нуля. Никакого кода не наследуется от `DraggablePanel.gd` — он удаляется отдельной задачей. Реализация идёт в порядке вертикальных срезов: сначала пустой `BasePanel.tscn` рендерится в каталоге, потом по одной фиче с smoke после каждой.

Шесть фаз (детали в [`tasks.md`](./tasks.md)):

1. **Скелет:** `BasePanel.tscn`, `BasePanel.gd`, ноды HeaderBar/Body/ResizeHandles, экспорты, theme integration. Каталог пустой, одна `FullPanel` рендерится.
2. **Drag.** `panel_drag_handler.gd`. Smoke S002, S003, S017 (drag bounds C2).
3. **Resize.** `panel_resize_handler.gd`. Smoke S004-S006, S015 (viewport resize C3).
4. **Collapse + Lock.** `panel_collapse_handler.gd`, `panel_lock_handler.gd`. Smoke S007-S009, S014.
5. **header_visible cascade.** Расширение API + auto-disable cascade. Добавление `PinnedPanel` в каталог. Smoke S011-S013.
6. **Persistence.** `panel_persistence.gd`, `panel_clamps.gd` (полный C1-C5), debounced save. Smoke S015, S016, S018, S019.
7. **Удаление DraggablePanel** + ловля fallout (map_editor сломается, это ожидаемо).
8. **Каталог: финал.** Все 5 наследников, кнопка в главном меню, Localization keys. Полный smoke S001-S021.

## Архитектурное обоснование

### Inherited Scenes как primary reuse mechanism

Godot-идиоматичный паттерн для «общий wrapper + специфичное содержимое в наследнике». Альтернативы — mixin (текущий джем-код), наследование класса без сцены, или composition через `add_child`. Inherited Scenes выигрывает потому что:

- Структура нод (HeaderBar / Body / ResizeHandles) фиксируется визуально в `BasePanel.tscn`, не строится императивно в `_ready()`. Это даёт one-source-of-truth — хочешь поменять header layout, открываешь .tscn, меняешь, все наследники подхватывают.
- Editable Children в наследнике — стандартный механизм Godot. Контентщик (или dev в Spec 057) открывает `Inherit from base_panel.tscn`, кладёт что нужно в Body, остальное наследуется.
- Скрипт `BasePanel.gd` действует как контракт: что наследник может настраивать (через экспорты), что трогать нельзя (HeaderBar внутренности).

### Composition handlers вместо одного big script

`BasePanel.gd` создаёт child-узлы (`PanelDragHandler`, `PanelResizeHandler`, ...) в `_ready()`, каждый со своей ответственностью. Это **implementation detail**, не публичный API. Зачем не один большой класс на 600 строк:

- **Single responsibility.** Drag-логика, resize-логика, persistence — независимые подсистемы. Изменение одной не должно требовать понимания остальных.
- **Тестируемость.** Если когда-нибудь добавим автотесты на UI (сейчас политика — manual smoke per docs/testing.md), отдельные handlers тестируются изолированно.
- **Будущее расширение.** Spec 060 (UI Catalog) или будущий «pinned snap-to-grid» — это новый handler, не правка существующего класса.
- **Читаемость файлов.** 7 файлов по 50-150 строк лучше одного на 800.

Trade-off: больше навигации между файлами, нужна осторожность с порядком инициализации (handlers должны видеть base_panel ноды). Решается явным `setup(base_panel)` методом в каждом handler'e, вызываемом из `BasePanel._ready()` в фиксированном порядке.

### Почему не Godot Window node

Решение из research-pass, фиксируется здесь:
- `Window` спроектирован под subwindows / native OS windows. Decoration logic (title bar, close button, resize handles) встроены и кастомизация ограничена.
- `gui_embed_subwindows` flag + связанные ограничения дают сложности с Z-order и input routing когда нужно держать панель в основном HUD.
- Наши требования (lock, collapse-в-плашку, persistence в `user://layouts.cfg` per panel — не per window) не маппятся на `Window` API.

`PanelContainer` как root + свой код для всего поведения — даёт полный контроль. Цена — пишем drag/resize сами, но мы это уже частично делали в джеме и code path понятен.

### Почему ResizeHandles как sibling от VBoxContainer внутри PanelContainer

```
PanelContainer
├─ VBoxContainer (header + body, layout-aware)
└─ ResizeHandles (Control, mouse_filter=PASS, abs-positioned overlay)
```

Альтернатива — `CanvasLayer` поверх. Sibling проще:
- Не выходит из иерархии панели — Z-order корректный автоматически (handles рисуются после body, но `mouse_filter=PASS` пропускает клики в body).
- Position handles вычисляется относительно `PanelContainer.size` — сигнал `resized` от него триггерит пересчёт.
- Не нужна синхронизация двух сцен (CanvasLayer как отдельная сущность).

Цена — child handles должны иметь `mouse_filter=STOP` индивидуально, root `ResizeHandles` — `PASS`. Это контракт в `panel_resize_handler.gd`, проверяется в `_ready()`.

### Persistence: `ConfigFile` напрямую, без autoload

Альтернатива — autoload `LayoutPersistence` singleton. Не нужен:
- `ConfigFile` open + read/write занимает ~5 строк, не оправдывает singleton.
- Один autoload на каждую систему = autoload-soup. Проект уже имеет `EventBus`, `UiTheme`, `WindowMode`, `Localization`, `GameLogger`, и т.д.
- Тестируемость не страдает — `panel_persistence.gd` это тонкая обёртка над `ConfigFile`, можно вызывать с произвольным path в тестах.

Дебаунс реализован через `Timer` ноду внутри `panel_persistence.gd` (одна на каждую панель). Не глобальный таймер — потому что debounce per-panel, не per-system. Если десять панелей одновременно меняют состояние — десять отдельных дебаунсов, десять отдельных save'ов с разными ключами. Это OK потому что save — write одной секции `ConfigFile`, не перезапись всего файла.

### header_visible cascade — `_effective_*` геттеры

Из spec.md §5.4: при `header_visible=false` принудительно `draggable/resizable/collapsible/lockable = false`. Реализация:

```gdscript
# Внутри BasePanel
var _effective_draggable: bool
var _effective_resizable: bool
# ...

func _ready():
    _compute_effective_flags()
    # handlers читают _effective_*, не сами экспорты

func _compute_effective_flags():
    _effective_draggable  = draggable  and header_visible
    _effective_resizable  = resizable  and header_visible
    _effective_collapsible = collapsible and header_visible
    _effective_lockable   = lockable   and header_visible
```

Публичные геттеры `is_draggable() / is_resizable() / ...` отдают `_effective_*`. Это даёт «код не может думать что drag работает когда header скрыт» — поведение детерминировано из конфигурации.

### Удаление DraggablePanel.gd до миграции потребителей

Это нестандартный ход — обычно удаляешь когда последний потребитель мигрирован. Но Spec 056-057 ещё не написаны, и редактор сознательно лежит до их завершения (см. spec.md §8). Логика:

- Если оставить `DraggablePanel.gd` живым в Spec 055 — оно будет тянуться через 056, 057, и удалится в 058. Прицеп ненужного кода через 3 спека.
- Если удалить в 055 — старые панели сломаются на компиляции (preload путь не существует). Это **правильный сигнал** для Spec 057: «эти 7 файлов нужно переписать, они сейчас не компилируются». Невозможно забыть мигрировать.
- Map editor лежит в любом случае. Сломанные импорты лучше работающих под старым кодом — иначе соблазн «давайте быстренько починим в jam-style» и rehaul стопорится.

Цена — на момент конца Spec 055 проект не запускается чисто (parse error на 7 файлах). Это известный trade-off. **В Tasks включаем явную проверку:** `godot --check-only` должен проходить хотя бы для main_menu + ui_catalog scene path. Остальные могут падать parse-only.

Альтернатива: **закомментировать содержимое старых панелей** оставив stub (`extends PanelContainer`). Чище компилируется, но тогда можно случайно перейти в map editor и увидеть пустое окно. Решение: stub-комментирование сделать в Spec 057 первой задачей перед architecture work, а в Spec 055 — действительно ломающее удаление, чтобы не было соблазна «попробуем редактор пока».

### Theme integration

Не вводим новых StyleBox'ов в `UiTheme`. Используем существующие:
- `BasePanel` корневой `PanelContainer` — стандартный panel stylebox через global theme.
- Возможно (если визуально header не отличается достаточно от body) добавим `theme_type_variation = &"UiPanelHeader"` для HeaderBar и попросим `UiTheme` экспонировать `make_header_stylebox()`. **Решение откладываем до момента визуальной приёмки в Phase 1** — может оказаться что дефолтный contrast уже достаточен.
- `EventBus.ui_theme_reloaded` — `BasePanel._ready()` connect'ится, на signal перепримеряет styleboxes. Паттерн копируем из `floor_palette_panel.gd` (есть в jam-коде, корректный).

## Структура изменений

### Новые файлы

```
specs/055-ui-panels/
  spec.md       (есть)
  plan.md       (этот файл)
  tasks.md      (следом)

scenes/ui/panels/
  base_panel.tscn
  ui_catalog.tscn

scripts/presentation/ui_panels/
  base_panel.gd
  ui_catalog.gd
  internal/
    panel_drag_handler.gd
    panel_resize_handler.gd
    panel_collapse_handler.gd
    panel_lock_handler.gd
    panel_persistence.gd
    panel_clamps.gd

data/localization/  (правка существующих файлов)
  en.json     +ui_main_menu_catalog, +ui_catalog_title, +ui_catalog_back
  ru.json     +ui_main_menu_catalog, +ui_catalog_title, +ui_catalog_back
```

### Правки существующих файлов

**`scenes/main_menu.tscn`** — добавить `UiCatalogButton` (Button) в `VBox` между `CreditsButton` и `QuitButton`. Использовать существующий стиль кнопок.

**`scripts/presentation/main_menu.gd`** — добавить:
```gdscript
@onready var _ui_catalog_btn: Button = $VBox/UiCatalogButton  # ~строка 51
# в _ready после _credits_btn.pressed.connect(_on_credits):
_ui_catalog_btn.pressed.connect(_on_ui_catalog)
# в setup loop, чтобы UiTheme.apply_button_styling зацепил
# (он уже итерируется по всем Button child'ам VBox, дополнительно ничего не нужно)
# новый метод:
func _on_ui_catalog() -> void:
    get_tree().change_scene_to_file("res://scenes/ui/panels/ui_catalog.tscn")
```

### Удаления

**`scripts/presentation/dev/draggable_panel.gd`** — `git rm`. Никаких других изменений в Spec 055. 7 файлов, использующих этот preload, остаются как есть и не компилируются — это известный fallout (см. архитектурное обоснование выше).

## Phase ordering rationale

Почему не «всё-сразу»:

- **Phase 1 (скелет) → Phase 2 (drag) сначала**, потому что drag — самая фундаментальная интеракция, и если она не работает корректно, остальные handlers начнут работать поверх неправильного position state.
- **Resize (Phase 3) до Collapse/Lock (Phase 4)**, потому что resize handles зависят от размера панели и нужно убедиться что они корректно показываются/скрываются ДО того как collapse начинает менять effective размер.
- **header_visible cascade (Phase 5) после basic features**, потому что cascade — это «выключение» уже работающих фич, и проверять его смысл когда есть что выключать.
- **Persistence (Phase 6) последней** из логики, потому что она наблюдает за изменениями через сигналы handler'ов. Хочется чтобы все эти сигналы уже работали корректно, прежде чем подключать save/load.
- **DraggablePanel removal (Phase 7) после Phase 6**, чтобы не сломать всё на полпути и не путаться, что именно сломалось. Также это отделяет «новая система работает» от «старая система удалена» — если что-то всплывёт, изоляция чистая.
- **Каталог финализация (Phase 8) последней**, чтобы все 5 наследников делались на стабильной базе.

Smoke per phase, не накопленный — иначе на финале S021 чек становится регрессом 20+ сценариев одновременно.

## Риски и mitigation

- **R1: Composition handlers — over-engineering.** Если в процессе окажется что 6 файлов overkill, можно слить два-три в один. Решение принимается на ревью plan.md, не в impl. Не идём в Plan B пока не упёрлись.
- **R2: Resize handles bug возвращается.** Spec 055 specifically делает их видимыми в hover (UP-1 default). Если на smoke S004 курсор-сюрпризы воспроизводятся — сразу останавливаемся и пересматриваем размер handle (≥10px было плановой меткой, может оказаться нужно больше).
- **R3: Theme integration внезапно требует правок UiTheme autoload.** Если header не выделяется визуально от body — нужен новый stylebox в UiTheme. Это правка чужого кода, требует обсуждения. Mitigation: Phase 1 включает явный визуальный check «header читается как отдельная зона». Если нет — заводим issue и решаем до Phase 8.
- **R4: Persistence гонки между debounce и scene exit.** Если игрок выходит из каталога раньше чем debounce 0.5s сработал — теряется последнее изменение. Mitigation: на `tree_exiting` принудительный flush save (без debounce). Проверяем в S015.
- **R5: ConfigFile path проблемы на разных OS.** `user://` маппится по-разному. Mitigation: используем `ProjectSettings.globalize_path("user://layouts.cfg")` для логирования + fallback на пустой layout если file corrupted/unreadable.
- **R6: Inherited Scenes сюрпризы при изменении базы.** Если в Spec 057 миграция выявит что нужно поменять структуру `BasePanel.tscn` (например добавить ноду в HeaderBar) — все существующие наследники могут сломаться (Editable Children сохраняет ссылки на старые node paths). Mitigation: фиксируем в spec.md контракт «структура HeaderBar и Body — стабильная, изменения = breaking change для всех наследников и должны быть отдельным mini-spec'ом». Записываем как принцип в design.md update post-Spec-055.

## После завершения Spec 055

- Smoke S001-S021 пройден на ветке `andrey/055-ui-panels`.
- PR в `andrey/level-editor-rehaul` (integration branch). Review pause перед merge.
- На merge — обновление [design.md §3](../../docs/systems/ui-panels/design.md) (z-order persistence перенос в Spec 057), запись в [`DECISIONS.md`](../../docs/design/DECISIONS.md) (Spec 055 как foundation rehaul'а), запись в [`FEATURES.md`](../../docs/FEATURES.md) (новый блок `ui-panels`).
- Spec 056 (level-editor architecture from scratch) разблокирован.
