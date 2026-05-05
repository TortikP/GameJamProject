# Level Editor — Design Document

**Статус:** Draft. Архитектурный документ, предшествующий 6 спекам (0..5). Ревью — по разделам.
**Обсуждали:** Андрей (идея, UX, scope), Никита (конфиг волн, палитры, разбор багов), Claude (раскладка документа).
**Связанное:**
- Соседняя система: [`docs/systems/ui-panels/`](../ui-panels/) — фреймворк панелей. Spec 0 заводит её отдельно от этой папки. Этот документ её *использует*, но не определяет.
- [`planning/plan.md`](../../../planning/plan.md) §1 «Редакторы» — этот рехауль закрывает большинство пунктов оттуда.
- Удалённый предшественник: ветка `andrey/editor-layers` / spec 055. Дропнут целиком — джем-фундамент не выдержал. Часть выводов перенесена в раздел 9.
- Pillars: [`docs/design/PILLARS.md`](../../design/PILLARS.md). Редактор — инструмент, не часть игры, но плохо авторённый контент бьёт по pillar 1 (видимость).

---

## 1. Контекст и зачем

Map Editor сейчас живёт на джем-фундаменте: один `MapEditorController` на 1551 строку, `Mode` enum из 5 состояний с семью `set_mode_*` методами и пятью `_clear_pending_delete()` колл-сайтами, семь панелей которые каждая по-своему собираются из `PanelContainer` + `DraggablePanel.new()` (drag есть, collapse частично ad-hoc, resize нет вообще). Палитры разбросаны: пол внизу, объекты справа, спаунеры внутри объектов вкладкой. При ПКМ-удалении контроллер использует неявную приоритетную цепочку `spawner > object > floor`, которая нигде не отражена в UI.

Что не работает на этом фундаменте:
- Низкий реюз. Каждая новая панель — копипаст структуры. Будущие редакторы (диалогов, скиллов, аспектов) повторят те же 200 строк boilerplate.
- Mode-state размазан между палитрами и контроллером. Каждое нажатие на палитру дёргает свой `set_mode_*`, контроллер хранит дублирующее `_placing_*` поле.
- Валидаций нет. Сохранить можно карту без player spawner'а, со ссылкой на несуществующий tileset, с дублирующимися индексами волн. Узнаёшь это в playtest, когда `WaveController` молча падает.
- Панели толкаются на 1080p. Нет единой истории про collapse/resize, юзер не управляет screen real estate.

Прецедент: spec 055 пытался это починить инкрементно поверх джема. Smoke провалился. Не повторяем — полный re-do, новая ветка, старый `MapEditorController` живёт параллельно до конца Spec 2 и потом удаляется.

**Жёсткий constraint:** существующие файлы карт (`data/maps/*.json`, schema v2) должны продолжать читаться после деплоя всех 6 спеков. Forward-only migration на load — ок. Сломать существующие данные — нет (Никита потеряет работу).

---

## 2. Цели и не-цели

**Цели:**
- Layer-based editor model. Активный слой — single source of truth для LMB/RMB. Никаких implicit priority chains.
- Один input dispatcher в новом контроллере. Mode enum убит. Поведение определяется парой `(active_layer, layer_selection[active_layer])`.
- Validation pipeline: REJECT блокирует save, WARN не блокирует. Перечень авто-проверок — фиксирован, см. §6.
- Расширение wave-данных: `respawn_player`, спаунеры с `amount` и `delay`, `is_special` как enum.
- Чистая граница core / editor-state / presentation. Игровой runtime не знает о слоях, выделениях и режимах.

**Не-цели (явные):**
- Полноценный music editor. Здесь только raw поля `music_config` в LevelData для пробрасывания в файл; редактор — отдельная фича когда соберёмся.
- Layout presets, save/restore раскладок панелей.
- Tab/dock system как в Godot editor. Overkill.
- Миграция in-game UI-панелей (skill HUD, character info) на `ui-panels` фреймворк. Потенциальная side-польза, отдельное решение, не сейчас.
- Layer model для сущностей, которых в `LevelData` сейчас нет (события, нод-граф сетки-карты, итд). Эти концепты появятся отдельными спеками; layer model расширяется добавлением слоя, а не переделкой.
- Keyboard navigation между волнами (отложено по джем-обсуждению).

---

## 3. Архитектура верхнего уровня

Три слоя зависимостей, строго в одну сторону: presentation → editor-state → core.

**core** — `scripts/core/maps/level_data.gd`. Чистая структура данных. Никакой осведомлённости о редакторе, слоях, выделениях, валидации. Расширяется в Spec 3 (новые поля в схеме). Игровой runtime читает только это.

**editor-state** — новые файлы в `scripts/presentation/dev/`. Несмотря на каталог, это не презентация в смысле «рисует на экране» — это *редакторское состояние*. Сюда живёт:
- Layer model: `_active_layer`, `_layer_selections: Dictionary[StringName, Variant]`.
- Selection state каждого слоя.
- Validation cache (пересчитывается на изменение, см. §6).
- Undo/redo (`LevelHistory` уже есть, переезжает сюда).

Почему presentation, не core: концепция «активного слоя» — чисто редакторская. Игре всё равно, в каком слое юзер «нарисовал» объект — в `LevelData` лежит уже разложенное по полям. Если когда-нибудь runtime AI/balancing захочет читать layer info («спавнить только на гексах слоя hexes») — пересмотрим, но сейчас YAGNI ([OQ-5](#10-открытые-вопросы)).

**presentation** — UI компоненты в `scripts/presentation/dev/`. Используют `ui-panels` (Spec 0) как базу. Подключаются к editor-state только через сигналы EventBus или прямые `signal` на самих панелях. Никакой панели не разрешено напрямую читать или писать в `LevelData` — только через editor-state посредников.

```
┌─ presentation ─────────────────────────────────────┐
│  LayersPanel  WavePanel  ToolPanel  LevelMetaPanel │
│       │           │           │            │       │
│       └─── signals ───────────┴────────────┘       │
└──────────────────┬─────────────────────────────────┘
                   ▼
┌─ editor-state ─────────────────────────────────────┐
│  EditorController (новый, ~300 строк цель)         │
│  + active_layer, layer_selections                  │
│  + InputDispatcher                                 │
│  + LevelValidator                                  │
│  + LevelHistory (undo/redo)                        │
└──────────────────┬─────────────────────────────────┘
                   ▼
┌─ core ─────────────────────────────────────────────┐
│  LevelData (расширяется в Spec 3)                  │
└────────────────────────────────────────────────────┘
```

---

## 4. Layer model

Три слоя. Жёстко зашитое количество, не plugin-механика — введение нового слоя требует осознанного редизайна, не конфигурации.

| Slug | Что лежит | Источник палитры |
|---|---|---|
| `hexes` | Тайлы пола | `hex_terrain.tres` (обе source) + Erase как палитра-item |
| `spawners` | Player + враги | `data/enemies/*.json` + Player (singleton) |
| `objects` | Mirые объекты | `TileObjectRegistry`, без разделения Obstacles/Interactive (объединение из джем-палитры) |

**Active layer как single source of truth.** `_active_layer: StringName` хранится в EditorController. Переключение:
- `Q` → hexes, `W` → spawners, `E` → objects (прямой выбор)
- `Tab` → циклически вправо
- Клик по табу `LayersPanel` (ui-panels: tab-bar в шапке)

**Per-layer selection.** Каждый слой держит свой текущий выбор. Структура:
```
_layer_selections: Dictionary[StringName, Variant] = {
    &"hexes":    {source_id: int, atlas_coord: Vector2i} | &"erase",
    &"spawners": {kind: StringName, ref: StringName},
    &"objects":  {object_id: StringName},
}
```
Переключение слоя восстанавливает его предыдущий выбор. Палитра показывает selection активного слоя; селекшен в неактивных табах не «рисуется» (но сохраняется в state).

**LMB на гексе** диспатчится по active layer:
- `hexes` + selection != erase → ставит тайл
- `hexes` + selection == erase → стирает тайл
- `spawners` → ставит спаунер (player → удаляет старого player'а, спаунер uniqueness)
- `objects` → ставит объект

**RMB на гексе** удаляет с *активного* слоя на этом coord. Никакого priority chain. Если на active layer на coord ничего нет — silent no-op (без toast). Drag-RMB — продолжающееся удаление по hover пути.

**Shift+RMB** — отдельная операция, вне layer dispatch. Cascade: удаляет всё с гекса (tile + objects + spawners) одной транзакцией для undo/redo. Это «силовое» действие, явно отличается шорткатом от обычного RMB.

**Erase в hexes — палитра-item, не отдельный mode.** Это упрощение от 055: там Erase был отдельным state'ом с собственным `Mode.ERASING_FLOOR`. Здесь — обычный selection в палитре hexes, рядом с другими тайлами. Радио-группа гарантирует single-active.

**Объекты и спаунеры в воздухе** — допустимо. Объекты — потому что Андрей так задумал ([§9 D-?](#9-decisions-унаследованные-из-предшественников)). Спаунеры в воздухе — для спавна врагов за пределами карты, тоже задумано. Валидация на это даёт WARN, не REJECT (см. §6).

---

## 5. Input dispatcher

Один новый класс/модуль в EditorController, явно отделённый от палитр и от panel logic. Ответственность — **только** интерпретация мышиных и клавиатурных событий в операции над `LevelData`.

```
EditorController._input(event):
    if InputDispatcher.handle(event, _active_layer, _layer_selections):
        _refresh_overlays()
        _enqueue_autosave()
        _enqueue_validation()
```

`InputDispatcher` — внутри методы:
- `handle_lmb_press(coord)` — старт drag-paint state, первый paint.
- `handle_lmb_drag(coord)` — продолжение paint, anti-dup на одной координате.
- `handle_lmb_release()` — завершение transaction для undo/redo.
- `handle_rmb_press(coord, modifiers)` — single delete или cascade (Shift) или старт drag-erase.
- `handle_rmb_drag(coord)` — продолжение drag-erase.
- `handle_key(keycode)` — Q/W/E/Tab/1-9.

Drag-state хранится явно: `enum DragState { NONE, PAINTING, ERASING }`. Переходы:
- LMB press → PAINTING
- RMB press без Shift → ERASING
- LMB/RMB release → NONE
- Esc → NONE + сброс preview

Это **не** Mode enum. Mode-state в 055 описывал «что юзер собирается делать в принципе»; DragState описывает «прямо сейчас тащим мышью». Принципиальная разница: DragState всегда NONE между мышиными жестами, в отличие от Mode который висел до явного `set_mode_*`.

**Quick-select 1-9:** `handle_key(KEY_1..KEY_9)` → выбирает N-ый item в палитре активного слоя. Палитра рисует подпись цифры в углу видимых кнопок (только в активном слое — другой таб не показывает цифры, чтобы не путать).

---

## 6. Validation contract

Раздельная подсистема. Класс `LevelValidator` в editor-state. Stateless: вход — `LevelData`, выход — `ValidationResult`.

```
class ValidationResult:
    errors:   Array[ValidationIssue]   # REJECT
    warnings: Array[ValidationIssue]   # WARN

class ValidationIssue:
    severity:    StringName     # &"error" | &"warning"
    rule_id:     StringName     # для localization key и для подсветки
    message_key: String         # ключ из data/localization/{en,ru}.json
    location:    Variant        # Vector2i (coord) | int (wave_idx) | Dictionary | null
```

**REJECT vs WARN:**
- **REJECT** — блокирует save и playtest. Модал «Cannot save — N errors», список кликабельных entries, клик центрирует камеру + подсвечивает локацию.
- **WARN** — toast при save «Saved with N warnings», save проходит, playtest стартует. Список доступен через кнопку «Show warnings» на LevelMetaPanel.

**Авто-проверки** (фиксированный список):

| Rule ID | Severity | Триггер |
|---|---|---|
| `player_spawner_required` | REJECT | Wave 0 ИЛИ wave с `respawn_player=true` без player-спаунера |
| `valid_wave_index_sequence` | REJECT | Индексы должны быть `0,1,...,N-1` без пропусков |
| `no_duplicate_wave_index` | REJECT | Два wave entry с одинаковым index |
| `valid_dialogue_wave_ref` | REJECT | `dialogue_triggers.conditions.wave_index` ссылается на несуществующую волну |
| `valid_turns_to_next` | REJECT | non-final wave: `turns_to_next > 0`. Final wave: `turns_to_next == 0`. |
| `valid_tileset_path` | REJECT | `tileset_path` существует на диске |
| `object_on_floor` | WARN | Объект на гексе без тайла. Допустимо (объект «в воздухе»), но подозрительно. |
| `spawner_on_floor` | WARN | Спаунер на гексе без тайла. Допустимо (спавн за картой), но подозрительно. |
| `empty_wave` | WARN | Wave без enemy-спаунеров (player-only) |

**Live validation:** EventBus сигнал `level_data_changed` (который уже есть на autosave) триггерит пересчёт с дебаунсом 0.2s. Результат кэшируется в editor-state. Подсветка проблемных мест на канвасе (красный outline на спаунере без тайла, etc.) обновляется по этому же сигналу.

Финальные severity для `object_on_floor` и `spawner_on_floor` — есть [OQ-3](#10-открытые-вопросы), Андрей подтвердил оба как WARN, фиксируем.

---

## 7. Data model deltas (LevelData)

SCHEMA_VERSION bump 2 → 3. Forward-only migration на `from_dict()`.

**Wave entry.** Существующее остаётся, добавляется два поля:

| Field | Status | Default | Замечание |
|---|---|---|---|
| `index` | exists | — | |
| `is_special` | **changes** `bool → String` | `"normal"` | Free-form string. Migration: `false → "normal"`, `true → "boss"`. Конвенция: `"normal"`, `"boss"`, `"miniboss_*"`. Валидация **не** ограничивает значения — любая строка проходит, чтобы не блокировать плейтест-итерации с новыми типами. Long-term возможно станет computed-from-reward, см. [Q-11](../../design/OPEN-QUESTIONS.md#q-11-тип-волны-определяется-наградой-за-неё). |
| `turns_to_next` | exists | `0` (final) / `5` (non-final) | |
| `floor`, `objects`, `spawners` | exists | `[]` | |
| `respawn_player` | **new** | `false` | Wave 0 — implicit `true` (всегда спавнит player'а). Для wave > 0: если `true` — на этой волне player ставится заново на свой спаунер; если `false` — player остаётся где был. Если `true` — валидация требует player-спаунер на этой волне. |
| `music_config` | **new** | `{}` | Raw passthrough для будущего music editor'а. UI редактора показывает как «advanced JSON» поле без интерпретации. |

**Spawner entry.** Существующее остаётся, добавляется два поля:

| Field | Status | Default | Замечание |
|---|---|---|---|
| `coord`, `kind`, `ref` | exists | — | |
| `timer` | exists | `1` | Задержка до первого спавна (в ходах). |
| `amount` | **new** | `1` | Сколько раз спаунер срабатывает. `1` = текущее поведение. |
| `delay` | **new** | `1` | Задержка между срабатываниями. Игнорируется при `amount=1`. |

**dialogue_triggers cleanup.** Из конфига Никиты: «по ощущениям `id` и `dialogue_id` отвечают за одно и то же». Резолвится в Spec 3 — нужно посмотреть текущий код `DialogueTriggerPanel` и `DialogueManager`, понять кто из них реально читается, нормализовать. Возможно одно из полей deprecated. См. [OQ-2](#10-открытые-вопросы).

**Migration policy.** На `LevelData.from_dict()`:
- `version < 3` ИЛИ отсутствует:
  - `is_special: bool → String` (`false → "normal"`, `true → "boss"`)
  - `respawn_player`: добавить со значением `false` (wave 0 имплицитно как был)
  - `music_config`: добавить `{}`
  - Spawners: `amount=1`, `delay=1` если отсутствуют
- Записываем всегда v3. Старые v2 файлы читаются, но не пишутся обратно.

Все Никитины черновики и `data/maps/*.json` после деплоя Spec 3 должны открываться без ошибок. Это smoke-критерий приёмки Spec 3.

---

## 8. Slicing на 6 спеков

| # | Spec | Что внутри | Зависит от |
|---|---|---|---|
| **0** | `ui-panels`: универсальные окна интерфейса | Container + drag (existing mixin → промоушен) + collapse-в-плашку (свёрнутая = заголовок + `[+]`) + resize (D-вариант, 8 видимых handles, ≥10px зона захвата, cursor change только над handle, фикс 055-бага). Живёт в `docs/systems/ui-panels/`. Reusable, потенциально для in-game UI позже. | — |
| **1** | `level-editor`: architecture from scratch | Layer model, InputDispatcher, новый EditorController (~300 строк цель), тонкий вертикальный срез: палитра hexes → клик → тайл лежит в LevelData. Без объектов, без спаунеров, без валидаций, без волн. Старый `MapEditorController` параллельно живёт. | Spec 0 |
| **2** | `level-editor`: layers + palettes (полная миграция) | Объекты и спаунеры подключаются. Q/W/E/Tab, 1-9, HELP modal, delete_flash. Удаление старого `MapEditorController` и `floor_palette_panel` / `object_palette_panel`. | Spec 1 |
| **3** | `level-editor`: wave data + settings panel | Расширение `LevelData` (см. §7), wave settings UI с группами (level / wave / spawner / skill_offer / dialogue_triggers / music_config). dialogue_triggers cleanup (OQ-2). | Spec 1 (panel host) |
| **4** | `level-editor`: validation pipeline | `LevelValidator`, REJECT/WARN модель, авто-проверки (§6), UI подсветка. | Spec 3 (data model должна быть стабильна) |
| **5** | `level-editor`: WavePanel UX (timeline) | Timeline похожий на runtime UI, tooltip с содержимым волны, drag-reorder, badges (статус-цвет читается из validator'а), inline `turns_to_next` с ±, активная волна сильно подсвечена. Андрей прорабатывает дизайн сам, как доберётся. | Spec 4 (badges читают результат) |

**Порядок.** Строго последовательно: 0 → 1 → 2 → 3 → 4 → 5. Никаких параллельных спеков. Каждый стартует только после merge предыдущего в staging и подтверждения Андрея. Это дороже по календарю, но дешевле по rework: если Spec 1 при имплементации обнажит проблему в дизайне — Specs 2/3 не идут в холостую.

**Между специами — review pause** per [`docs/workflow.md`](../../workflow.md). Spec не заводится автоматически по завершении предыдущего; решает Андрей.

**Где `MapEditorController` удаляется.** В Spec 2, явной задачей. До этого — параллельная жизнь. Constraint: на любой момент времени между Spec 1 и Spec 2 должен быть рабочий редактор (старый или новый, любой), чтобы Никита мог продолжать авторство.

---

## 9. Decisions (унаследованные от предшественников)

**D1. Resize нужен.** В spec 055 был выпилен после первого smoke из-за бага: невидимые HSIZE/VSIZE handles на краях панели → cursor surprises при наведении на края → accidental resize'ы во время быстрой работы. Это не «resize не нужен» — это «реализация была сломана». Решение для Spec 0: resize обязателен, 8 handles, видимые в hover (минимум — точечные индикаторы в углах + полоски на краях), зона захвата ≥10px, cursor change только над handle. Детали — в Spec 0.

**D2. Mode enum выпилен в пользу layer model.** Mode-based UI создавал implicit priority chain (`spawner > object > floor`) при удалении, который не виден из UI — юзер не знал, что именно удалится при ПКМ. Layer model делает это явным: что подсвечено в палитре активного слоя — то и редактируется/удаляется. Цена: per-layer selection state (см. §4), но это явное состояние, а не размазанное.

**D3. 2-step ПКМ удаление выпилено.** В джем-версии было: первый ПКМ ставит маркер, второй на ту же клетку — удаляет. Маркер не имел таймаута, не очищался при undo, при load level, при focus loss. Никита терял работу. Replacement: single-RMB + drag-RMB + Shift-RMB cascade (см. §4). Жесты различаются явно, ничего не «висит».

**D4. Layer state в presentation, не в core.** Concept «активного слоя» — чисто редакторский. Игровой runtime читает только `LevelData`. Если runtime AI/balancing когда-нибудь захочет layer info — пересмотрим. Сейчас YAGNI.

**D5. `is_special` переходит из bool в free-form string.** Расширение в сторону мини-боссов (Марк обсуждал) и других типов, которые ещё не придуманы. Изначально предполагался строгий enum, но Андрей: «нам нужна максимально гибкая система для плейтестов и итераций, ничего не проибываем» — поэтому валидация не ограничивает значения. Конвенция (не enforce'ится): `"normal"`, `"boss"`, `"miniboss_*"`. Долгосрочно тип волны может стать computed-from-reward — см. [Q-11](../../design/OPEN-QUESTIONS.md#q-11-тип-волны-определяется-наградой-за-неё).

---

## 10. Открытые вопросы

Это не блокеры на старт Spec 0/1, но должны быть закрыты до соответствующего спека.

- **OQ-1 (Spec 3): `is_special` enum — какие значения?** **Закрыто для целей рехауля:** free-form string, валидация не ограничивает. Migration `false → "normal"`, `true → "boss"`. Конвенция-не-обязательно: `"miniboss_*"`. Долгосрочный вопрос «должен ли тип волны определяться наградой за неё, а не задаваться явно» вынесен в [Q-11](../../design/OPEN-QUESTIONS.md#q-11-тип-волны-определяется-наградой-за-неё) — решается по итогам плейтестов с разными наградными конфигами, не сейчас.
- **OQ-2 (Spec 3): `dialogue_triggers.id` vs `dialogue_triggers.dialogue_id`.** Никита: «отвечают за одно и то же». Надо посмотреть текущий код `DialogueManager` и `DialogueTriggerPanel`, понять кто реально читается, что deprecated. Резолвится в Spec 3.
- **OQ-3 (Spec 4): severity для object/spawner на пустом гексе.** Андрей подтвердил оба как WARN. **Закрыто, ссылка для прослеживаемости.**
- **OQ-4 (Spec 3): `waves.timer` (Никитин) vs `waves.turns_to_next` (текущий).** Никита подразумевает `timer` как опциональный bool «есть ли таймер до следующей волны вообще»; если `false` — `turns_to_next` игнорируется. Если `true` — текущая семантика. Это новое поле или семантика `turns_to_next == 0` уже это покрывает на non-final волне? Уточнить с Алексеем (owner `WaveController`).
- **OQ-5 (после Spec 4): когда переcмотреть «layer state в presentation».** Если runtime AI/balancing/save-system захочет читать layer info. Сейчас не блокер, фиксируем как trigger-condition.
- **OQ-6 (вне рехауля): миграция in-game UI на ui-panels.** Skill HUD, character info, поп-апы выбора скилла — потенциально мигрируют после Spec 0. Отдельное решение, не сейчас.

---

## 11. Не-цели (явный список)

Перечисление того, чего этот рехауль **не** делает, чтобы scope creep можно было остановить ссылкой:

- Layout presets, save/restore раскладок панелей — отложено до запроса.
- Music editor — отдельная фича. Здесь только raw `music_config` поле в `LevelData`.
- Tab/dock system как в Godot editor — overkill для нашего масштаба.
- Keyboard navigation между волнами — отложено по джем-обсуждению.
- Layer model для будущих сущностей (события, нод-граф сетки-карты) — расширение, не текущий scope.
- Миграция in-game UI на ui-panels — потенциальная side-польза, отдельное решение после Spec 0.
- Auto-arrange / auto-layout панелей при изменении viewport — нет. Юзер сам.
- Multi-select / box-select на канвасе — нет в этих 6 спеках. Заведём отдельно если Никита/Стасян попросят.
