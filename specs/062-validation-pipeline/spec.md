# 062 — Validation Pipeline

Обсуждали: Андрей (идея), Claude (проработка).

## Что и зачем

Level editor сейчас сохраняет JSON безусловно: `EditorIO.save()` ни разу
не вызывает `LevelData.validate()`. Все 25+ проверок (REJECT и WARN
промешаны строками в `Array[String]`) живут в коде, но дизайнер их не видит
до запуска playtest'а — и часто только по падению или бессмысленному
поведению. Pillar 1 (full information visibility) на этом ломается:
ошибочный конфиг невидим до момента запуска.

062 строит UX-обвязку поверх стабильной schema v3 (закреплена в 061):

1. Refactor `LevelData.validate()` → `Array[ValidationIssue]` со структурным
   `path`, severity-флагом, loc-key'ями и аргументами — чтобы UI мог
   роутить ошибки к нужному полю/панели/гексу.
2. UI-визуализация на четырёх поверхностях: problem list panel, inline
   error labels, tab badges, hex highlight.
3. Save блокируется на REJECT-уровне, автосейв НЕ блокируется (recovery
   path всегда доступен).
4. Backfill локализации всех validation-сообщений — паттерн уже есть в
   `DialogueTrigger.validate()` (lazy `Localization.t/tf` resolver),
   распространяем на `LevelData`.

Не переписываем: `DialogueTrigger.validate()` остаётся как есть (уже
локализовано, уже с WARN-префиксом) — на уровне LevelData wrap'аем его
строки в issue с `path = "level.dialogue_triggers[id=X]"`. Если поедем
сильнее — отдельный chore позже.

## Acceptance criteria

- **AC1.** `LevelData.validate()` возвращает `Array[ValidationIssue]`.
  `game_editor_controller.gd` (единственный внешний consumer) мигрирован.
- **AC2.** Save в level editor блокируется если есть хотя бы один REJECT
  issue. Toast: `«Cannot save: N errors. See Problem List.»` (loc-key).
- **AC3.** Save с только-WARN issue'ями проходит, toast: `«Saved with N
  warnings.»`.
- **AC4.** Autosave (`editor_io.enqueue_autosave`) НИКОГДА не блокируется
  валидацией — пишет state-as-of-fire безусловно.
- **AC5.** Load всегда успешен. Сразу после load issue'и видны в Problem
  List и на UI-поверхностях.
- **AC6.** Любая мутация уровня через EditorController триггерит
  debounced revalidate (200ms). Save attempt и Load — синхронный
  revalidate (instant).
- **AC7.** ProblemListPanel показывает все текущие issues с severity-иконкой
  и человекочитаемым текстом. Клик по строке → jump на нужную волну +
  фокус на поле / подсветка гекса.
- **AC8.** Любая активная волна в WaveSettingsPanel с REJECT issue'ями
  получает красный «●» badge на табе; только-WARN — жёлтый «!» badge.
- **AC9.** Поля с известным structural path получают inline error label
  под собой (красный — REJECT, жёлтый — WARN). Цвета через `UiTheme`.
- **AC10.** Issues с координатным path (`spawners[coord=(2,4)]` и т.п.)
  подсвечивают соответствующие гексы красным полупрозрачным overlay'ем.
  Tooltip на гексе показывает текст issue.
- **AC11.** Все validation-сообщения локализованы. EN+RU loc keys в
  `data/localization/{en,ru}.json` под префиксом `ui_validate_*`. Существующие
  `ui_dialogue_validate_*` и `ui_trigger_validate_*` остаются и подключаются.
- **AC12.** Все три зарезервированных trigger-key'я
  (`ui_trigger_validate_id_empty/id_dup/event_empty` на строках 1078-1080
  обоих json'ов) теперь реально используются в issue'ях.
- **AC13.** Smoke на трёх данных: пустой уровень (REJECT — нет волн),
  валидный уровень с 3 волнами, невалидный story_map с placeholder'ами
  (несколько REJECT + WARN). Проверка что REJECT блокирует save, WARN
  даёт сохранить, ProblemList кликабелен, табы и поля красятся.

## Out of scope

- **Overlay incremental update.** 060 plan R4 пометил как «если тормозит».
  Никто не профайлил на 50+ объектах. Speculative до первого репорта о
  лаге paint'а — спек 062b или дальше. Не делаем.
- **Wave timeline UI badges.** Spec 063 — таймлайн волн целиком, в нём
  badges от 062 переиспользуются естественным образом.
- **Undo/redo.** Spec 064.
- **DialogueTrigger.validate() refactor → structured.** Уже работает,
  локализован, имеет WARN префикс. Wrap его strings в issue на уровне
  LevelData дешевле чем переписывать. Если со временем накопятся новые
  consumer'ы DialogueTrigger.validate() — отдельный спек.
- **Live validate во время typing'а в SpinBox/LineEdit.** Field commit
  (focus loss / Enter) триггерит мутацию → debounce → UI обновляется.
  Per-keystroke не нужен.
- **Validation rules как сами по себе изменения.** Все правила остаются
  ровно те что есть в `LevelData.validate()` сейчас, плюс мы их
  локализуем. Новые правила — другие специ.
- **set_dirty wiring.** На `editor_controller.gd:355` пустой; не трогаем
  (отдельный TODO в tech-debt).
- **Validation в game_editor.** Wire-only (миграция consumer'а под новую
  signature), без UI overhaul — game_editor.tscn не получает Problem
  List и т.п. Хватает существующего toast pattern'а.

## ValidationIssue — schema

```gdscript
class_name ValidationIssue
extends RefCounted

enum Severity { REJECT, WARN }

var severity: Severity
var path: String          # см. конвенцию ниже
var loc_key: StringName   # &"ui_validate_wave_ttn_too_low"
var loc_args: Array       # для %d/%s в loc-строке
var message_fallback: String  # если loc_key не резолвится
```

### Path конвенция

Всегда строка, корень — `level`. Сегменты разделены `.`. Индексация
массивов — `[N]` (по индексу) или `[id=X]` (по логическому id).
Координаты в hex — `[coord=(x,y)]`.

Примеры:
- `level` — top-level invariant («нет волн», «нет player spawner'а»).
- `level.music_config.bpm` — поле LevelMetaPanel.
- `waves[3].turns_to_next` — поле в WaveSettingsPanel вкладка Wave.
- `waves[3].advance_mode` — то же.
- `waves[3].skill_offer.pool` — секция Skill Offer на вкладке Wave.
- `waves[3].spawners[coord=(2,4)].timer` — конкретный spawner. Hex
  highlight + (если spawners выбран в layer) inline под палитрой.
- `level.dialogue_triggers[id=foo].event` — Dialogue Triggers секция,
  trigger по id.

UI-роутинг по path делает ProblemListPanel при click → emit'ит
`jump_to_path(path)` обратно в EditorController, который раскидывает по
адресатам (`set_active_wave`, `select_trigger`, scroll'ы).

### Loc keys

Префикс — `ui_validate_*` для новых LevelData-issue'ей (для дифференциации
от существующих `ui_dialogue_validate_*` в DialogueTrigger). Ключи
плоские, аргументы через `%d/%s/%f`. Пример:

```json
"ui_validate_wave_ttn_too_low": "Волна %d: turns_to_next должно быть >= 1 (сейчас %d)",
"ui_validate_no_player_spawner": "Не задан Player Spawn ни в одной волне",
"ui_validate_spawner_off_floor": "Волна %d: спавнер %s на неотрисованном тайле %s"
```

Примерное число новых ключей: **~25** (по числу `errors.append`-сайтов в
`level_data.gd::validate()`).

## UI поверхности

### ProblemListPanel

Новая панель в level editor, dock на нижнем краю (под grid'ом) или в
существующем вертикальном split — финальное расположение в Φ-4. Содержит:

- Заголовок: `«Issues: N (X errors, Y warnings)»` — динамически.
- Filter buttons: All / REJECT only / WARN only.
- ItemList: каждая строка — иконка severity + текст issue.
- Click → jump к месту через signal.
- Empty state: `«No issues. Save unblocked.»`.

Скрывается если issues пусто (или collapse к узкой строке «No issues»).

### Inline error labels

Под полями с структурным path. Шаблон: красный/жёлтый Label с текстом
issue.to_human(), `mouse_filter = MOUSE_FILTER_IGNORE`, минимальный
вертикальный inset. Цвета через `UiTheme.VALIDATION_REJECT_FG` / `_WARN_FG`
(новые константы).

Покрытие field commit-trigger'ы (минимально требуемое):
- WaveSettingsPanel вкладка Wave: turns_to_next, advance_mode.
- WaveSettingsPanel вкладка Skill Offer: pool, source, count.
- LevelMetaPanel: bpm (если bpm out of range) — это редкий сценарий, но
  для симметрии оставляем.

Triggers section и spawners section НЕ получают inline labels (их issue'и
ловятся через problem list + hex highlight + tab badge — этого хватает).

### Tab badges

Каждый таб WaveSettingsPanel (Level / Wave / Spawners / Skill Offer /
Dialogue Triggers) — `Button` или `TabBar`-tab. Badge — Label-child с
точкой/восклицательным знаком в верхнем правом углу.

`UiTheme.VALIDATION_BADGE_REJECT` (красный круг) и `_BADGE_WARN` (жёлтый
треугольник). Реализация — helper в новом
`scripts/presentation/dev/editor/validation_decorators.gd`.

### Hex highlight overlay

Новая нода `HexValidationOverlay` в той же иерархии что existing
`spawners_overlay` / `objects_overlay`. Слабая полупрозрачная заливка
шестиугольника, цвет — REJECT/WARN из UiTheme. Tooltip через
`HexTooltip` если есть, иначе fallback canvas-tooltip.

Подписан на `ValidationCoordinator.issues_changed` — на каждый
re-validate перекрашивает свой набор гексов.

## ValidationCoordinator

Нода `scripts/presentation/dev/editor/validation_coordinator.gd`, child
EditorController'а — НЕ autoload (валидация editor-only, не нужна в
runtime-сценах).

API:
```gdscript
class_name ValidationCoordinator extends Node

signal issues_changed(issues: Array[ValidationIssue])

func setup(level_provider: Callable) -> void  # () -> LevelData
func request_revalidate() -> void              # debounced 200ms
func revalidate_now() -> Array[ValidationIssue]  # synchronous
func get_current_issues() -> Array[ValidationIssue]
func has_blocking_issues() -> bool
func issues_for_path_prefix(prefix: String) -> Array[ValidationIssue]
```

EditorController после каждой мутации (paint/erase/cascade/wave_field/
add_wave/copy/delete + dialogue trigger CRUD из 061) дёргает
`request_revalidate()`. На save attempt — `revalidate_now()` для
актуальности. На load — `revalidate_now()`.

Subscribers (`connect("issues_changed", ...)`):
- ProblemListPanel
- WaveSettingsPanel (для tab badges + inline labels)
- HexValidationOverlay
- LevelMetaPanel (если есть level-level issue, например bpm)

## Save/load flow change

`EditorController._on_save()`:
```
issues = _validation.revalidate_now()
if has_blocking_issues:
    toast(loc(ui_validate_save_blocked, [count]))
    return  # save aborted
ok = _io.save(_level)
if ok:
    if warns_count > 0:
        toast(loc(ui_validate_save_with_warns, [warns_count]), success)
    else:
        toast("Saved", success)
```

`EditorIO.save()` сам валидацию НЕ делает — это контроллер-уровень
поведение. EditorIO остаётся «тупой» writer.

`EditorIO.enqueue_autosave()` тоже не валидирует — autosave всегда пишет.

`EditorController._on_load()`: после `_io.load_from(...)` дёргает
`_validation.revalidate_now()` чтобы UI сразу показал состояние файла.

## Risks / open

- **R1.** Path синтаксис может оказаться недостаточно богат для будущих
  правил. Стартуем с минимально нужного, расширяем по мере появления
  новых issue-сайтов. Если path не парсится по conventions — issue
  показывается в problem list, но без inline/badge/highlight (graceful
  degradation). Mitigation: ProblemListPanel остаётся single source of
  truth, UI fanout — best-effort.
- **R2.** Localization autoload может не быть в headless-режиме (GUT).
  Используем тот же pattern что в `DialogueTrigger._t/_tf` — lazy
  resolver через `Engine.get_main_loop()`, fallback на
  `message_fallback`. Без него GUT-тест на validate() упадёт.
- **R3.** ValidationCoordinator subscribes via signal — если subscriber
  не disconnected перед freeing, висячий callable. Standard pattern:
  disconnect в `_exit_tree()` каждой панели/overlay'я.
- **R4.** Issue count может стать большим на сильно битом story_map
  (десятки issues) — ProblemListPanel должен скроллиться, не растягивать
  layout. ItemList родной godot-control с встроенным scroll, проблем
  быть не должно.
- **R5.** Inline label может сильно толкать layout вниз если issue
  длинная. Ограничиваем `clip_text` или `autowrap_mode = WORD`. Финал
  — в Φ-5 при первом смоке.

## Связанные документы

- `specs/061-wave-data-and-settings/spec.md` — schema v3 + текущие WARN
  правила, на которые 062 наклеивает UI.
- `specs/060-level-editor-layers/plan.md` (R4) — пометка про overlay
  incremental update как 062+.
- `scripts/core/maps/level_data.gd:144` — текущий validate().
- `scripts/core/dialogue/dialogue_trigger.gd:38` — образец локализации
  через lazy resolver.
- `data/localization/{en,ru}.json:1078-1080` — зарезервированные trigger
  keys.
- CLAUDE.md «Hard rules / Архитектура» — UiTheme константы для цветов,
  EventBus для cross-system (мы в пределах одного flow editor'а, чистого
  EventBus тут нет — internal signal на ValidationCoordinator достаточно).

## Phase split

После approve спека — переход к plan.md (8 фаз) и tasks.md без
human-review pause (по запросу Андрея).
