# Spec 061 — Wave data + settings panel + dialogue triggers (LevelData v3)

**Статус:** Spec фаза. Plan и Tasks — после ревью у Андрея.
**Обсуждали:** Андрей (идея, scope, отвечал на Q1-Q3 + Q-061-1..6 в Clarify), Никита (фидбек по advance_mode и cleanup OQ-2), brain (декомпозиция, surface'инг runtime impact'а на is_special / amount / delay).

---

## 1. Что строим (one-paragraph summary)

Возвращаем wave editing в Level Editor (удалённый в 060) — без полного таймлайна. Минимальный `WaveSwitcher` (список волн + add/copy/delete) + новая `WaveSettingsPanel` с группами `level / wave / spawner / skill_offer / dialogue_triggers / music_config`. Параллельно — bump `LevelData.SCHEMA_VERSION` 2→3 с forward-only миграцией: `is_special: bool → String`, новые `wave.respawn_player`, `wave.advance_mode`, `wave.music_config`, `spawner.amount`, `spawner.delay`. Один runtime-фичур делается «по дороге» — `advance_mode = "timer_and_clear"` (Никитино: следующая волна не начнётся пока есть враги). Spawner `amount`/`delay` — schema-only, runtime warn-once. Dialogue triggers интегрируются в `WaveSettingsPanel` (а не отдельной панелью): wave-scoped — в группе `wave`, level-scoped (включая `level_completed`) — в группе `level`. Полный таймлайн с drag-reorder и validator-бейджами — это Spec 063, не 061.

---

## 2. Проблема

**Что сейчас (после 060):**
- Map Editor умеет редактировать **только wave 0**. Многоволновые карты (Никитины концовочные `story_map_03.json`, etc.) грузятся, показываются в виде wave 0 с warning toast'ом, сохраняются roundtrip — но создавать или модифицировать `wave > 0` через UI невозможно.
- Никита редактирует triggers напрямую в JSON `data/maps/*.json` — `dialogue_trigger_panel.gd` удалён в 060.
- Per-spawner свойства (timer, ref) уже в схеме v2, но UI для их редактирования из 060 wave-scoped не вернулся (он был внутри удалённого `wave_panel.gd`).

**Что хочется:**
- Никита и Стасян должны редактировать многоволновые карты целиком, без касания JSON.
- LevelData schema подготовлена под фичи которые design.md §7 обозначил как нужные (мини-боссы через `is_special` строкой, respawn-контроль, conditional advance, repeat-spawners).
- Один из этих feature'ов реализуется runtime'ом сразу — `advance_mode = "timer_and_clear"` (прямой Никитин запрос, маленький patch в `wave_controller.gd`).
- Dialogue triggers редактируются в естественном контексте — рядом с волной к которой они привязаны.

**Что не входит (см. §4):**
- Wave timeline UI (drag-reorder, badges, inline ttn ±) — Spec 063.
- Validation pipeline (REJECT/WARN автоматизация UI) — Spec 062.
- Runtime для `spawner.amount > 1` или `spawner.delay > 1` — отдельный спек после 062.
- Music editor — design.md §11.
- Exp-bar / level-up via kills — отдельный спек после metaprogression.

---

## 3. Цель

### A. WaveSwitcher (минимальный)

- **AC1.** В `WaveSettingsPanel` есть `WaveSwitcher` — `ItemList` с одной строкой на волну. Формат: `«Wave N · {special} · ttn={value}»` (special пустое для `"normal"`). Pillar 1 — читаемо за 0.3s, шрифты через `UiTheme.FS_*`.
- **AC2.** Клик по строке — `EditorController.set_active_wave(idx)` → `LevelData.set_active_wave_index(idx)` → грид перерисовывается. Layers/Palettes 060 продолжают работать на новой активной волне без изменений.
- **AC3.** Кнопки рядом со списком: `[+ Wave]` (insert после активной), `[Copy from prev]` (insert после активной с deep-copy floor+objects из prev, без spawner'ов — reuse `LevelData.make_wave_copy_no_spawners`), `[Delete]` (удалить активную, активная становится `min(idx, waves.size()-1)`). Кнопки disabled когда нерелевантно (`Delete` disabled при `waves.size() == 1`; `Copy from prev` disabled на wave 0).
- **AC4.** Polished states: при переключении активной волны автосейв триггерится (1.5s debounce, как в 060). При add/copy/delete — autosave немедленно (без debounce).

### B. WaveSettingsPanel — структура групп

- **AC5.** `WaveSettingsPanel extends BasePanel` — отдельная панель в `HUD`, sibling LayersPanel и LevelMetaPanel. Не таб в LayersPanel (Q-061-5: layers и settings — разные оси, смешение запутает).
- **AC6.** Внутри панели — VBox с пятью collapsible-секциями (через UiTheme collapse-кнопку или просто заголовки + body). В порядке сверху вниз:
  1. **Level** — `name` (read-only mirror из LevelMetaPanel), список **level-scoped dialogue_triggers** (CRUD).
  2. **Wave** — поля активной волны: `is_special` (~~LineEdit, free-form~~ → **OptionButton с пресетами `normal/boss/miniboss/elite`** per F-061-IMPL-5), `turns_to_next` (SpinBox), `respawn_player` (CheckBox), `advance_mode` (OptionButton: timer/clear/timer_and_clear).
  3. **Spawners** — список спаунеров активной волны, на клик строки — edit form с `kind`/`ref`/`timer`/`amount`/`delay`. `amount`/`delay` помечены тэгом `(schema-only)` (Q-061-3).
  4. **Skill Offer** — reuse секция из удалённого `wave_panel.gd` (gd-код можно подсмотреть в `673e377^:scripts/presentation/dev/wave_panel.gd:_build_skill_offer_section`). Bind/unbind пер-волне.
  5. **Dialogue Triggers (wave-scoped)** — read-only mirror из level-секции (выше), фильтр `conditions.wave_index == active_wave`. Без CRUD — CRUD только в level-секции, чтобы не плодить точек редактирования.
  6. **Music config** — JSON LineEdit (advanced) для per-wave override. Пустое поле = level fallback. (Q-061-2.)
- **AC7.** Все label'ы и тексты — через локализацию (`Localization.t/tf` / `data/localization/{en,ru}.json`). Никаких inline-строк.
- **AC8.** Панель сохраняет позицию/размер через стандартный `BasePanel` persistence (058). Default позиция — правый край экрана, sibling LayersPanel.

### C. Per-spawner редактирование

- **AC9.** В секции `Spawners` — `ItemList`/VBox с одной строкой на спаунер. Формат: `«{kind} {ref} @ {coord} · t={timer} a={amount} d={delay}»`.
- **AC10.** Клик по строке — открывается edit-form под списком: SpinBox для `timer` (≥1), SpinBox для `amount` (≥1), SpinBox для `delay` (≥1), OptionButton для `ref` (filtered по EnemyDB или фиксированный список — тот же что в SpawnerPalette).
- **AC11.** Изменения апплаятся live — `EditorController.update_spawner(coord, fields)` → автосейв debounced.
- **AC12.** `kind` НЕ редактируется через эту секцию — change kind происходит через delete + paint в SpawnerPalette (consistency с layer model 060).

### D. Dialogue triggers — CRUD в Level-секции, mirror в Wave-секции

- **AC13.** В Level-секции — `ItemList` со всеми триггерами уровня + кнопки `[Add] [Edit] [Duplicate] [Delete]` (как в удалённом `dialogue_trigger_panel.gd`, можно подсмотреть в `673e377^:scripts/presentation/dev/dialogue_trigger_panel.gd`).
- **AC14.** Edit form — collapsible под списком, поля: `id` (LineEdit, помечено «Trigger ID — для логов и once-tracking, уникален в пределах уровня»), `event` (OptionButton с `CURATED_EVENTS` из старой панели + custom LineEdit для event'ов вне списка), `dialogue_id` (filterable OptionButton со списком из `DialogueDB.get_all_ids()`, помечено «Dialogue — что играть»), `play_mode` (CheckBox pair: request/play), `conditions` — chip-list secondary (wave_index, absolute_turn, cleared_in_turns_lt, mood, chance, etc.).
- **AC15.** Подписи к `id` и `dialogue_id` явно объясняют разницу — это резолв OQ-2: оба поля остаются, переименования не делаем (cleanup идёт через UX, не через schema).
- **AC16.** В Wave-секции — read-only список **с теми же триггерами**, отфильтрованных по `conditions.wave_index == active_wave_index`. Клик по строке — переключает фокус в level-секцию на эту запись и открывает edit-form. Цель: контекст «какие триггеры сработают на этой волне» виден без переключения панелей.
- **AC17.** Триггеры с `event = "level_completed"` относятся к level-секции (даже если они «логически про последнюю волну»). Это explicit Андреем: «level_completed логически про финальную волну, но редактируется в group level — одна точка для level-scoped».
- **AC18.** Документация — новый файл `docs/systems/level-editor/dialogue-triggers.md` с разъяснением `id` vs `dialogue_id`, списком CURATED_EVENTS с семантикой, примерами JSON. Plan.md §1 строка `dialogue_triggers — UX и доки [spec-S]` закрывается этим.

### E. LevelData v2 → v3 schema migration

- **AC19.** `LevelData.SCHEMA_VERSION = 3`.
- **AC20.** Wave entry — новые поля + изменения существующих:
  | Field | v2 | v3 | Default | Migration |
  |---|---|---|---|---|
  | `is_special` | bool | String | `"normal"` | `false → "normal"`, `true → "boss"` |
  | `respawn_player` | — | bool | `false` (для wave > 0); wave 0 implicit `true` | добавляется при load если отсутствует |
  | `advance_mode` | — | String | `"timer"` | добавляется при load если отсутствует |
  | `music_config` | — | Dict | `{}` | добавляется при load если отсутствует |
- **AC21.** Spawner entry — новые поля:
  | Field | v2 | v3 | Default | Migration |
  |---|---|---|---|---|
  | `amount` | — | int | `1` | добавляется при load если отсутствует |
  | `delay` | — | int | `1` | добавляется при load если отсутствует |
- **AC22.** Migration policy: forward-only на `LevelData.from_dict()`. Если `version < 3` ИЛИ отсутствует — мигрируем по таблицам выше. Записываем всегда v3. Старые v2 файлы читаются, но после save'а становятся v3.
- **AC23.** Validation:
  - `respawn_player`: если `true` для `wave > 0` — на этой волне должен быть player-spawner (иначе ERR).
  - `advance_mode`: только `"timer" | "clear" | "timer_and_clear"` (ERR если другое).
  - `is_special`: любая строка проходит (free-form per design.md D5).
  - `spawner.amount/delay`: ≥1 (ERR если меньше).

### F. Backward compat — readers с `is_special` как bool

- **AC24.** EventBus сигнал `wave_started(index, is_special: bool)` остаётся `bool` (Q-061-1). В `wave_controller.gd` derive: `var is_special_bool := str(w.get("is_special", "normal")) != "normal"`.
- **AC25.** Helper `LevelData.is_wave_special(idx: int) -> bool` добавляется. Все 5 консьюмеров `is_special` (`wave_timeline`, `tutorial_director`, `skill_offer_controller`, `campaign_controller`, `music_director`) переключаются на helper или продолжают читать через `bool(w.get(...))` **только если поле — bool после миграции**. Прямое чтение `bool(w.get("is_special", false))` ПОСЛЕ миграции даст `bool("normal") = true` — это бага, которая возникнет автоматически. Audit + fix всех мест в этом спеке (см. §5.2).

### G. Conditional auto-advance — runtime для `advance_mode`

- **AC26.** В `wave_controller.gd` — поддержка трёх режимов:
  - `"timer"` (default, обратная совместимость) — текущее поведение, advance после `turns_to_next` декремент'ов.
  - `"clear"` — advance только когда EventBus.wave_cleared (все враги мертвы). `turns_to_next` игнорируется — счётчик ходов всё равно идёт визуально, но не вызывает advance.
  - `"timer_and_clear"` (Никитино) — `turns_to_next` декрементится как обычно. На `turns_to_next == 0` — advance ждёт `wave_cleared`. Если `wave_cleared` пришёл раньше — advance немедленно.
- **AC27.** Pillar 1 (full info visibility) — UI индикатор «застрял пока есть враги». В runtime UI (HUD wave counter — отдельная сцена runtime/) — иконка/цвет когда `advance_mode != "timer"` и условие advance не выполнено. Конкретный визуал — см. §5.2 (сейчас минимальный — текстовый префикс «(waiting for clear)»).
- **AC28.** Если `advance_mode = "clear"` И `waves[N].spawners` не содержит ни одного enemy — это «безвыходная» волна (никогда не advance'нется). Validation WARN при save.
- **AC29.** Если `advance_mode = "timer"` И финальная волна (turns_to_next = 0) — текущее поведение auto-clear не меняется.

### H. Spawner amount/delay — schema-only

- **AC30.** WaveController читает `amount`/`delay` из schema но **не реализует repeat-spawning runtime**. На load level — если хоть один spawner имеет `amount > 1` ИЛИ `delay > 1` — `GameLogger.warn_once("spawner_repeat_not_implemented", "...")`. Поведение спаунера — как при `amount=1` (срабатывает один раз).
- **AC31.** UI редактирует поля и сохраняет в JSON. Контентщикам можно указывать значения и подготовить карты — фактический runtime приедет в follow-up.

### I. EditorController public API расширение

- **AC32.** `EditorController` получает методы:
  - `set_active_wave(idx: int) -> void` — переключение активной волны + перерисовка grid.
  - `add_wave(after_idx: int) -> void` — insert empty wave, become active.
  - `copy_wave_from_prev(after_idx: int) -> void` — insert deep-copy без spawners.
  - `delete_wave(idx: int) -> void` — remove, active = min(idx, waves.size()-1).
  - `update_wave_field(idx: int, field: String, value) -> void` — generic setter для полей wave (used WaveSettingsPanel).
  - `update_spawner(coord: Vector2i, fields: Dictionary) -> void` — обновление полей спаунера.
  - `add_dialogue_trigger(t: Dictionary) -> bool` / `update_dialogue_trigger(old_id, t) -> bool` / `delete_dialogue_trigger(id) -> bool` — CRUD.
- **AC33.** Hard cap `editor_controller.gd` — поднять с 300 до **350** (новые методы wave nav + trigger CRUD прибавляют ~50 строк). Это явное относ. наследства 060'ной 300-строки. Альтернатива — extract'нуть wave nav в отдельный модуль `wave_director.gd` — defer (YAGNI на 1 use-case).

### J. Backward-compatibility smoke

- **AC34.** Все существующие `data/maps/*.json` (включая многоволновые `story_map_*.json`, `sample_*.json`, Никитины черновики) загружаются в новый редактор без ошибок и без неожиданных warning toast'ов (за исключением WARN'ов из `LevelData.validate()` которые там были и до миграции).
- **AC35.** После load → save цикла — JSON остаётся валидным, version=3, поля с дефолтами добавлены, нет потери данных. Diff между «до миграции (v2)» и «после миграции и save (v3)» содержит **только**: bump `version`, конверсию `is_special`, добавление дефолтных полей. Никаких изменений в floor/objects/spawners/dialogue_triggers.
- **AC36.** Runtime: загруженная и пере-сохранённая v3-карта запускается в playtest без регрессий относительно той же карты до миграции (один и тот же seed → один и тот же ход событий). Smoke в `tasks.md`.

---

## 4. Не-цели

Жёстко вне scope этого спека:

- **Wave timeline UI** (drag-reorder, badges, inline ttn ±, активная волна сильно подсвечена, маркеры триггеров на таймлайне) — Spec 063. В 061 — только `ItemList`.
- **Validation pipeline UI** (REJECT/WARN визуализация на полях, save-blocking UI) — Spec 062. В 061 валидация остаётся как в 060: `LevelData.validate()` возвращает массив, save проходит без блокировки (warn'ы логируются).
- **Spawner amount/delay runtime** — schema-only (AC30-31). Real runtime — отдельный спек.
- **Music editor UI** — `music_config` через JSON-LineEdit, без интерпретации полей. Полноценный редактор — design.md §11.
- **Exp-bar / level-up via kills** — обсуждается отдельно. В 061 schema не расширяется под это.
- **Per-wave settings persistence** в layout (058) — стандартный BasePanel persistence работает «из коробки», ничего custom.
- **Tab tear-off для WaveSettingsPanel** — теоретически работает (058 фича на BasePanel), но не AC.
- **Wave reorder через drag** — добавление/удаление позволяет перетасовать через delete+add, но drag-reorder UI — 063.
- **Schema version downgrade** (v3 → v2) — никогда не делаем. Forward-only.
- **Dialogue trigger panel как отдельная BasePanel** — `dialogue_triggers` интегрируются в WaveSettingsPanel группами (AC13-16). Standalone панель — только если будущий use-case потребует, не сейчас.
- **Dialogue trigger reordering** — порядок в JSON-array не имеет семантического значения (runtime ищет по event match), UI его не предоставляет.
- **Wave-level `respawn_player` для wave 0** — неявно `true`, поле в schema добавляется но игнорируется на wave 0 (UI скрывает CheckBox для wave 0).

---

## 5. Структура изменений

### 5.1. Новые файлы

- `scripts/presentation/dev/wave_settings_panel.gd` — `class_name WaveSettingsPanel extends BasePanel`. Сигналы:
  - `wave_switch_requested(idx: int)`
  - `wave_add_requested(after_idx: int)`
  - `wave_copy_requested(after_idx: int)`
  - `wave_delete_requested(idx: int)`
  - `wave_field_changed(idx: int, field: String, value: Variant)`
  - `spawner_field_changed(coord: Vector2i, fields: Dictionary)`
  - `trigger_created(trigger_dict: Dictionary)`
  - `trigger_updated(old_id: StringName, trigger_dict: Dictionary)`
  - `trigger_deleted(trigger_id: StringName)`
  - `skill_offer_changed(idx: int, offer: Variant)` (relay из 040 reuse)
  - `skill_offer_preview_requested(idx: int)` (relay)

  Методы: `bind_level(level: LevelData)`, `set_active_wave(idx: int)`, `select_trigger(id: StringName)`. Soft cap **600 строк** (большая панель, сложный CRUD форм). Если превышает — finding и discussion про extraction (например trigger CRUD → отдельный sub-panel).

- `scenes/dev/wave_settings_panel.tscn` — Inherited Scene от `base_panel.tscn` (058 паттерн). Размер default ~360×600 px. Позиция default — правый край (anchor right, normalized `_normalize_anchors_to_top_left()` обеспечит сохранение).

- `docs/systems/level-editor/dialogue-triggers.md` — UX/контент-доки: что такое trigger, разница `id`/`dialogue_id`, CURATED_EVENTS список с семантикой, примеры JSON, типичные паттерны (intro/outro/wave-taunt/clear-condition/world-turn-pulse).

### 5.2. Изменённые файлы

- `scripts/core/maps/level_data.gd`:
  - `SCHEMA_VERSION = 3`.
  - В `from_dict()`: миграционная ветка после load if `lvl.version < 3` ИЛИ если поля отсутствуют. Конвертит `is_special: bool → String`, добавляет `respawn_player` / `advance_mode` / `wave.music_config` / `spawner.amount` / `spawner.delay` с дефолтами. После миграции `lvl.version = SCHEMA_VERSION`.
  - В `to_dict()`: сериализует все новые поля.
  - В `validate()`: добавляет проверки `respawn_player` для wave > 0, `advance_mode` enum, `spawner.amount/delay >= 1`. WARN на `advance_mode = "clear"` без enemy spawner'ов.
  - Новый helper `func is_wave_special(idx: int) -> bool` (string → bool derive).
  - В `_make_empty_wave` и `make_wave_copy_no_spawners` — defaults для новых полей.
  - В `_wave_dict_from_arr` и `_spawners_arr_to_dicts_with_default_timer` — read новых полей с дефолтами для legacy.

- `scripts/core/dialogue/dialogue_trigger.gd`: без изменений в самой модели. Validate расширяется на новые conditions если они появляются (на текущий момент — нет).

- `scripts/runtime/wave_controller.gd`:
  - Использовать `LevelData.is_wave_special(idx)` вместо прямого `bool(w.get("is_special", false))`. EventBus сигнал остаётся `bool` (Q-061-1).
  - Реализация `advance_mode`:
    - State: `_waiting_for_clear: bool` (true на «timer_and_clear» когда ttn дошёл до 0 но enemies живы; true на «clear» с момента wave_started).
    - На каждом world_turn: ttn--. Если ttn ≤ 0 И mode == "timer" → advance. Если ttn ≤ 0 И mode == "timer_and_clear" → set `_waiting_for_clear = true`, не advance.
    - Подписка на `EventBus.wave_cleared`: если `_waiting_for_clear` или mode == "clear" → advance.
  - Soft cap файла — оставить текущий, расширение ~30 строк.

- `scripts/presentation/ui/wave_timeline.gd`: 4 места читают `is_special` как `bool` (lines 395, 397, 498, 544 в текущем коде). Заменить на `LevelData.is_wave_special(idx)` или прямую проверку `str(...) != "normal"`. Это исправляет багу-в-зародыше (после миграции `bool("normal") = true`).

- `scripts/runtime/skill_offer_controller.gd:158`, `scripts/runtime/tutorial_director.gd:879`, `scripts/runtime/campaign_controller.gd:116`, `scripts/audio/music/music_director.gd:232`: все читают `_is_special: bool` из EventBus сигнала (signature не меняется). Code не трогаем — derive в `wave_controller.gd` обеспечивает корректное значение.

- `scripts/presentation/dev/skill_offer_smoke_controller.gd`: 3 места `"is_special": false` в hard-coded test fixtures (lines 153/189/244). Заменить на `"is_special": "normal"`.

- `scripts/presentation/dev/editor/editor_controller.gd`:
  - Новые публичные методы (см. AC32). Hard cap 300 → 350.
  - `_wire_wave_settings_panel()` — connect signals от WaveSettingsPanel.
  - `bind_level(level)` — кроме layers, теперь `_wave_settings_panel.bind_level(level)`.
  - На `set_active_wave(idx)` — sync `LevelData`, перебиндить overlays, `_wave_settings_panel.set_active_wave(idx)`.

- `scenes/dev/level_editor.tscn`: добавить инстанс `WaveSettingsPanel` в `HUD`. Default position — правый край, default size ~360×600.

- `data/maps/_schema.md` (если существует — иначе создать): обновить описание schema под v3. Включает таблицу полей wave/spawner и migration notes. Если файла нет — создать как часть AC18 docs.

- `data/localization/en.json` + `ru.json`: новые ключи для всех label'ов в WaveSettingsPanel (level/wave/spawner/skill_offer/dialogue_triggers/music_config заголовки + tooltips + button labels). Конкретный список ключей — в plan.md.

### 5.3. Удалённые файлы

Никаких. 060 уже удалил legacy.

### 5.4. Schema deltas (LevelData v3 vs v2)

```diff
 // Wave entry (Dictionary в waves[])
 {
   "index": int,
-  "is_special": bool,                // false | true
+  "is_special": String,              // "normal" | "boss" | "miniboss_*" | <free>
   "turns_to_next": int,
   "floor": [...],
   "objects": [...],
   "spawners": [...],
   "skill_offer": {...},              // optional, 040
+  "respawn_player": bool,            // default false; wave 0 implicit true
+  "advance_mode": String,            // "timer" | "clear" | "timer_and_clear", default "timer"
+  "music_config": Dictionary         // default {}, per-wave override of level music_config
 }

 // Spawner entry
 {
   "coord": [x, y],
   "kind": "player" | "enemy",
   "ref": String,
   "timer": int,                      // ≥1
+  "amount": int,                     // ≥1, default 1 (schema-only in 061 — runtime warn-once)
+  "delay": int                       // ≥1, default 1 (ignored if amount=1)
 }

 // LevelData top-level
 {
   "name": String,
-  "version": 2,
+  "version": 3,
   "tileset_path": String,
   "waves": [...],
   "dialogue_triggers": [...],
   "music_config": Dictionary         // unchanged — level-wide default
 }
```

### 5.5. Public API: `EditorController` — новые методы

```gdscript
# Wave navigation
func set_active_wave(idx: int) -> void
func add_wave(after_idx: int) -> void
func copy_wave_from_prev(after_idx: int) -> void
func delete_wave(idx: int) -> void

# Wave field updates (generic setter — каждый field валидируется)
func update_wave_field(idx: int, field: String, value: Variant) -> void
# Supported field: "is_special", "turns_to_next", "respawn_player",
# "advance_mode", "music_config".

# Spawner field updates
func update_spawner(coord: Vector2i, fields: Dictionary) -> void
# Supported keys in fields: "ref", "timer", "amount", "delay".

# Dialogue triggers CRUD — все возвращают bool (true = applied, false = validation rejected)
func add_dialogue_trigger(t: Dictionary) -> bool
func update_dialogue_trigger(old_id: StringName, t: Dictionary) -> bool
func delete_dialogue_trigger(id: StringName) -> bool
```

---

## 6. Acceptance criteria (consolidated)

AC1-AC36 из §3. Сводка:
- A (WaveSwitcher): AC1-AC4
- B (WaveSettingsPanel): AC5-AC8
- C (Per-spawner): AC9-AC12
- D (Dialogue triggers): AC13-AC18
- E (Schema migration): AC19-AC23
- F (is_special readers): AC24-AC25
- G (advance_mode runtime): AC26-AC29
- H (amount/delay schema-only): AC30-AC31
- I (EditorController API): AC32-AC33
- J (Backward-compat smoke): AC34-AC36

---

## 7. Findings (для других)

- **F-061-1 (для Никиты):** Wave editing вернулся. Многоволновые карты редактируются полностью. Dialogue triggers — в WaveSettingsPanel, секция «Dialogue Triggers (level-scoped)». Wave-scoped тоже редактируются там же (через level-секцию), а в группе `wave` отображаются read-only mirror. Документация семантики `id` vs `dialogue_id` — `docs/systems/level-editor/dialogue-triggers.md`.
- **F-061-2 (для Стасяна):** SCHEMA_VERSION = 3. `is_special` теперь строка (free-form, конвенция: `"normal" | "boss" | "miniboss_*"`, validator не ограничивает). Spawner gains `amount`/`delay` поля (schema-only, runtime warn-once). Wave gains `respawn_player`/`advance_mode`/`music_config`. JSON-схема обновлена в `data/maps/_schema.md`.
- **F-061-3 (для Андрея):** Owner WaveController — Андрей. `advance_mode = "timer_and_clear"` runtime реализован в этом спеке. `advance_mode = "clear"` тоже (как side-effect). Repeat-spawners (`amount > 1`) — НЕ runtime, schema только.
- **F-061-4 (для Алексея):** EventBus сигнал `wave_started(index, is_special: bool)` сохраняет `bool` сигнатуру. WaveController derive'ит из строки. Все 4 рантайм-консьюмера (skill_offer_controller, tutorial_director, campaign_controller, music_director) код не меняют.
- **F-061-5 (для будущего, exp-bar):** Schema 061 НЕ расширяется под exp-bar / level-up via kills. Когда фича придёт в работу — это отдельный спек, возможно с новой v4 миграцией. См. plan.md §2 (metaprogression) и докер-спек для exp-bar (TBD).
- **F-061-6 (потенциальный):** WaveSettingsPanel — большая панель (soft cap 600 строк). Если при имплементации превысит — кандидат на extraction trigger CRUD в отдельный sub-panel. Решать на месте.
- **F-061-7 (для будущего):** `advance_mode = "timer_and_clear"` без enemy spawner'ов на волне = «никогда не advance'нется». Сейчас WARN на save (AC28). Если реальный use-case потребует — пересмотреть (можно сделать ERR).
- **F-061-8 (для будущего, music editor):** `wave.music_config` — пока raw JSON в advanced-поле. Реальный per-wave music editor — design.md §11. Это поле уже там, готово для UI расширения.

---

## 8. Resolved decisions (Q-061-*)

- **Q1 → MVP wave switcher.** ItemList + add/copy/delete. Полный таймлайн — 063. Аргументация: design.md §8 явно отделяет таймлайн в Spec 063, после validation pipeline (062), потому что бейджи читают результат валидатора.
- **Q2 → Auto-upgrade на load.** Forward-only, как уже сделано для v1→v2 в `from_dict()`. Никаких explicit migrate-команд — нет UI, нет rollback.
- **Q3 → Dialogue triggers интегрируются в WaveSettingsPanel.** Полный CRUD — в level-секции. Wave-секция — read-only mirror с фильтром по `wave_index`. `level_completed` — в level-секции, по подтверждению Андрея «логически про финальную волну, но одна точка для level-scoped». Старая standalone панель НЕ восстанавливается.
- **Q-061-1 → `is_special` в schema String, EventBus остаётся bool.** Helper `LevelData.is_wave_special(idx)` для derive. Минимальный runtime touch. Альтернатива (b) — менять сигнал на String — отвергнута: 5 консьюмеров без реальной потребности в строке (никто не дифференцирует boss vs miniboss runtime'ом сейчас).
- **Q-061-2 → `music_config` per-wave override + level fallback.** Non-breaking. UI прячет per-wave под advanced JSON. Альтернатива (b) удаление level-level — отвергнута как breaking. Альтернатива (c) ошибка в design.md — отвергнута, design.md §7 явно описывает per-wave.
- **Q-061-3 → Spawner amount/delay schema-only.** Runtime warn-once. Альтернатива (b) полный runtime — defer, scope 061 уже жирный, runtime — отдельный спек после 062. UI помечает поля тэгом `(schema-only)` для прозрачности.
- **Q-061-4 → `advance_mode` runtime в 061.** Никитина опция = `"timer_and_clear"`. Schema enum трёх значений: `"timer" | "clear" | "timer_and_clear"`. Runtime изменение в `wave_controller.gd` ~30 строк. Делаем сразу, потому что: (1) Никита просит прямо, (2) маленькая правка, (3) частично решает геймдиз-проблему «бесплатного скилла за убегание». Pillar 1 — UI индикатор «застрял пока есть враги» в runtime HUD (AC27).
- **Q-061-5 → Standalone WaveSettingsPanel.** Не таб в LayersPanel. Layers и settings — концептуально разные оси (что я рисую vs параметры волны/спаунера/уровня). Смешение запутает. Альтернатива (b) таб — отвергнута; (c) inline в LayersPanel — отвергнута.
- **Q-061-6 → exp-bar НЕ в scope.** Никаких спекулятивных полей в schema 061. Если фича придёт — отдельный спек, возможно v4 миграция. Поле `wave.skill_offer.source = "defeated_enemies"` уже в схеме (040) и частично reflects идею.

---

## 9. Out of scope

- **Wave timeline UI** — Spec 063 (drag-reorder, badges от validator'а, inline `turns_to_next` ±, активная волна сильно подсвечена, маркеры триггеров на таймлайне).
- **Validation pipeline UI** — Spec 062 (REJECT/WARN визуализация на полях, save-blocking).
- **Spawner amount/delay runtime** — отдельный спек после 062.
- **Music editor UI** — design.md §11.
- **Exp-bar / level-up via kills** — отдельный спек после metaprogression.
- **Standalone dialogue_trigger panel restoration** — replaced groups в WaveSettingsPanel.
- **Wave reorder через drag** — 063.
- **Tab tear-off для WaveSettingsPanel** — не AC. Если работает as-is из 058 — bonus.
- **Schema downgrade v3 → v2** — никогда.
- **Расширение CURATED_EVENTS** — существующий список (8 events) сохраняется. Новые events — отдельная задача когда понадобятся.

---

## 10. Dependency / sequencing

- **Зависит от Spec 060** (level editor layers + palettes) — мерджнут в staging до старта 061. ✅ (PR #150 merged 2026-05-09)
- **Не зависит** от других in-progress спеков.
- **Разблокирует Spec 062** (validation pipeline) — 062 строит UI поверх стабильной schema v3 + warn'ы которые 061 добавил.
- **Разблокирует Spec 063** (wave timeline UI) — 063 заменяет MVP `ItemList` switcher на полноценный таймлайн с реакцией на validator-бейджи.
- **Внутри 061 — последовательность реализации** в `tasks.md` (составляется на Plan фазе). Большие группы:
  1. LevelData v3 + миграция + validate. Изолированный, тестируется автономно.
  2. is_special readers audit + fix (wave_timeline + skill_offer_smoke + LevelData helper).
  3. wave_controller.gd advance_mode runtime.
  4. WaveSettingsPanel — skeleton scene + groups level/wave (без spawner/triggers).
  5. WaveSettingsPanel — spawner section.
  6. WaveSettingsPanel — skill_offer section (port из удалённого wave_panel.gd).
  7. WaveSettingsPanel — dialogue triggers CRUD (level-секция).
  8. WaveSettingsPanel — wave-секция dialogue triggers mirror.
  9. EditorController public API + wiring.
  10. level_editor.tscn integration.
  11. Loc-keys batch.
  12. Backward-compat smoke (AC34-36).
  13. Docs (`docs/systems/level-editor/dialogue-triggers.md`, `data/maps/_schema.md` update).

- **Между 061 и 062 — review pause**. Spec 062 не стартует автоматически после merge 061; решает Андрей.

- **Параллельная жизнь** — нет. После 060 single-source level editing уже единственный путь. 061 расширяет тот же редактор.
