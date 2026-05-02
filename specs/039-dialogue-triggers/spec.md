# 039-dialogue-triggers — spec

**Owner:** Andrey (driver, full-stack — schema, runtime director, editor UI, sample content).
**Coordination:**
- **Egor** (038-mood-counter) — readonly read из `MoodTracker.get_dominant()` для condition `mood_required`. Additive, без правок его файлов. Если 038 не смержен на момент имплементации — condition сохраняется в JSON, но игнорируется в рантайме (warn-once).
- **Nikita** (`nikita/localization`) — все text-поля в диалогах уже loc-keys. 039 не определяет loc-pipeline; просто читает `dialogue_id` и пинает `DialogueManager.request/play`. Как `tr()` ляжет — Никитина параллельная работа.
- **Alexey** (003-dialogue-manager engine) — owner движка. 039 — чистый consumer: `DialogueManager.play(id)` / `request(event, ctx)` уже работают, ничего в engine не правим.
**Status:** Draft — clarify-round пройден с Andrey (per-level only, нет global pool, нет отдельного окна, dialogue_preview остаётся viewer'ом).

## Цель

Дизайнер на уровне привязывает существующие диалоги (`dialogue_id` из `data/dialogues/*.json`) к событиям этого уровня — старт/конец волны, конкретный ход, быстрый клир, открытие/закрытие skill-offer'а (040), и любые сигналы EventBus которые мы захотим добавить позже. Привязка живёт в `LevelData.dialogue_triggers[]`, редактируется в map editor рядом с волнами, отображается маркерами на WaveTimeline. Дублирование между уровнями — ручное (и осознанное; джемная экономия > DRY).

## Scope-граница

**В скоупе:**
- Schema `LevelData.dialogue_triggers[]` + валидация.
- Runtime `LevelDialogueDirector` autoload — на `level_started` коннектится к указанным сигналам, фильтрует по conditions, дёргает `DialogueManager.request` или `DialogueManager.play`.
- Editor UI — sidebar `DialogueTriggerPanel` (sibling существующего WavePanel) + маркеры триггеров на WaveTimeline в `Mode.EDIT`.
- Открытый event-словарь — runtime коннектится **по имени** к любому `EventBus.<signal_name>`. Editor предлагает curated dropdown для UX, но JSON принимает любой `StringName`.
- Conditions: `wave_index`, `absolute_turn` (для `world_turn_ended`), `cleared_in_turns_lt`, `mood_required`, `once_per_run`, `once_per_session`, `chance` (0.0-1.0).
- Sample-уровень `data/maps/sample_dialogues.json` — демонстрация 4-5 типовых триггеров.

**Вне скоупа:** см. секцию «Out of scope» внизу. Главные исключения: автоторинг текста/структуры диалогов, отдельное окно «dialogue editor», global pool вне LevelData, кастомный graph-editor для choice trees.

## Что вводится

### 1. Расширение `LevelData` — поле `dialogue_triggers`

`LevelData.dialogue_triggers: Array[Dictionary]`. Каждый триггер:

```gdscript
{
  "id": "lvl2_wave1_intro",     # StringName, unique within this level (для editor reference + once-tracking)
  "event": "wave_started",       # StringName — имя сигнала EventBus или synthesized event
  "dialogue_id": "boss_intro",   # StringName — ключ в DialogueDB
  "play_mode": "request",        # "request" | "play" — request фильтрует пул по тегу=dialogue_id, play форсит конкретный id
  "conditions": {                # все опциональные, AND-семантика; пустой словарь = всегда true
    "wave_index": 1,             # int — для wave_started/wave_cleared/wave_about_to_start: сработать только если args matches
    "absolute_turn": 40,         # int — для world_turn_ended: сработать только на этом ходу
    "cleared_in_turns_lt": 4,    # int — для wave_cleared: сработать только если unused_turns >= (turns_to_next - lt)
    "mood_required": ["burnout"],# Array[StringName] — MoodTracker.get_dominant() ∈ this list
    "chance": 1.0,               # float [0.0..1.0] — randf() < chance
    "once_per_run": true,        # bool — не стрелять второй раз в этом ране
    "once_per_session": false,   # bool — не стрелять второй раз за процесс
  },
}
```

**Семантика `play_mode`:**
- `"request"` — `DialogueManager.request(event=dialogue_id, ctx)` — селектор отбирает по tag=dialogue_id, отрабатывает priority/conditions/played-set из 003. Универсальный путь.
- `"play"` — `DialogueManager.play(dialogue_id)` — форс конкретного id, минует селектор. Для строго детерминированных кат-сцен типа `level_started`.

**Once-tracking** — `LevelDialogueDirector` ведёт свой набор `_fired_per_run: {trigger_id: true}` и `_fired_per_session: {trigger_id: true}`. Сбрасываются на `EventBus.run_started` / процесс-старт соответственно. Это **дополнительно** к played-set самого DialogueManager (тот трекает `dialogue_id`; 039 трекает `trigger_id`). Триггер с `once_per_run=true` и `dialogue_id=X` сработает один раз; повторный диалог X через другой триггер пройдёт, если у DialogueLine `once_per_run` не стоит.

### 2. Curated event vocabulary (редактор предлагает в dropdown)

Восемь событий первого класса. Каждое мапится 1:1 на `EventBus.<signal>`, с одним synthesized:

| event (StringName)               | EventBus signal                      | conditions, имеющие смысл            |
|----------------------------------|--------------------------------------|--------------------------------------|
| `level_started`                  | `battle_started(arena_id)`           | `chance`, `once_*`                   |
| `wave_about_to_start`            | **synthesized** (см. ниже)           | `wave_index`, `chance`, `once_*`, `mood_required` |
| `wave_started`                   | `wave_started(index, is_special)`    | `wave_index`, `chance`, `once_*`, `mood_required` |
| `wave_cleared`                   | `wave_cleared(index, unused_turns)`  | `wave_index`, `cleared_in_turns_lt`, `chance`, `once_*`, `mood_required` |
| `world_turn`                     | `world_turn_ended(turn)`             | `absolute_turn`, `chance`, `once_*`  |
| `skill_offer_about_to_open`      | `skill_offer_about_to_open(...)` (040) | `wave_index`, `chance`, `once_*`, `mood_required` |
| `skill_offer_closed`             | `skill_offer_closed(...)` (040)      | `wave_index`, `chance`, `once_*`, `mood_required` |
| `level_completed`                | `level_completed(total_score)`       | `chance`, `once_*`                   |

**Synthesized `wave_about_to_start`** — emitted by `WaveController` за один кадр **до** применения снапшота новой волны (между `wave_cleared` старой и `_apply_wave_snapshot(new_idx)`). Добавляется минимальной правкой в `wave_controller.gd` (см. plan.md). Без неё нельзя поставить «реплика перед началом волны 2» — `wave_started` уже идёт после применения снапшота.

**Открытый словарь.** JSON принимает любую `StringName` в `event`. На `level_started` Director пытается подключиться к `EventBus.<event>`; если такого сигнала нет — warn-once, триггер мёртв, остальные продолжают работать. Добавление нового события в код = добавить сигнал в `EventBus`, опционально включить его в curated dropdown в `DialogueTriggerPanel`. JSON-схему править не надо.

### 3. Conditions: семантика и точность

- **`wave_index`**: триггер сработает только если args сигнала содержит этот index. Для `wave_started(idx, is_special)` — `idx == wave_index`. Для `world_turn_ended(turn)` — `turn` сравнивается не с wave_index, а через `absolute_turn`. Если condition не применима к событию — warn-once при загрузке.
- **`absolute_turn`**: для `world_turn` — exact match (`turn == absolute_turn`). Для пощёлкать на ходу 40 уровня — ставится с этим событием.
- **`cleared_in_turns_lt: N`**: для `wave_cleared(idx, unused_turns)` — сработать если `unused_turns >= (waves[idx].turns_to_next - N)`. Т.е. «клир быстрее чем за N ходов». Computed в Director (требует доступ к `LevelData` — у Director он есть, см. plan.md).
- **`mood_required`**: dominant из `MoodTracker.get_dominant()` ∈ list. Если 038 не смержен — warn-once + игнор condition (триггер всё равно может сработать, condition просто пропускается).
- **`chance: 0.0..1.0`**: `randf() < chance`. Default 1.0.
- **`once_per_run` / `once_per_session`**: см. once-tracking в §1.

AND-семантика: все указанные conditions должны выполниться. Отсутствующие = «не проверяется».

### 4. Editor UI — `DialogueTriggerPanel`

**Где живёт.** Новый сиблинг WavePanel в `scenes/dev/map_editor.tscn`, под HUD CanvasLayer. По умолчанию слева снизу (рядом с FloorPalette). Сворачиваемая панель (header + collapsed/expanded state, `UiTheme.make_panel_stylebox()`).

**Содержимое panel:**
- Header: «Dialogue triggers» + счётчик (`5 triggers`).
- Список существующих триггеров активного уровня: `id  ·  event  ·  dialogue_id  ·  conditions-summary`. Клик по строке — выбрать, ESC — снять выделение. Подсветка соответствующего маркера на WaveTimeline.
- Кнопки: `+ Add trigger`, `Edit`, `Duplicate`, `Delete` (последние три disabled без выделения). Delete — через ConfirmModal.
- Edit/Add — открывает inline-form внизу панели (не отдельное окно):
  - `id` (LineEdit, validate unique within level)
  - `event` (OptionButton с curated списком + последний пункт «Custom...» открывающий LineEdit)
  - `dialogue_id` (OptionButton с filter — список из `DialogueDB.get_all_ids()`, искомость по substring)
  - `play_mode` (CheckBox: request/play radio)
  - Conditions section — все opt-in: чекбокс «Use condition X» + value editor рядом
  - Buttons: Save / Cancel

**Маркеры на WaveTimeline.** Расширяем `wave_timeline.gd` в режиме `Mode.EDIT`:
- Маркер триггера = маленькая иконка 💬 (или цвет-точка из `UiTheme.DIALOGUE_TRIGGER_MARKER`) над якорем волны или в gap'е, в зависимости от события:
  - `level_started`, `level_completed` — на крайних якорях (волна 0 / последняя).
  - `wave_about_to_start`, `wave_started`, `wave_cleared`, `skill_offer_*` — на якоре волны с указанным `wave_index`. Множественные триггеры на одной волне — стек по вертикали.
  - `world_turn` с `absolute_turn=N` — на координате X = `PADDING_LEFT + N * PIXELS_PER_TURN` (между якорями).
  - События без index/turn — на крайнем правом краю (`Misc` slot).
- Hover — tooltip с «id · event · dialogue_id · conditions-summary».
- Click — emit `trigger_marker_clicked(trigger_id)` → `DialogueTriggerPanel` выделяет соответствующую строку.

Editor controller — wire новой панели и проброс кликов из таймлайна (см. plan.md). +~50 строк в `map_editor_controller.gd`, не трогаем существующую логику.

### 5. Runtime — `LevelDialogueDirector` (autoload)

`scripts/runtime/level_dialogue_director.gd`. Регистрируется в `project.godot` после `DialogueDB`/`DialogueManager`/`MoodTracker`.

**Lifecycle:**
- На `EventBus.run_started` → clear `_fired_per_run`.
- На `EventBus.battle_started(arena_id)` → подгружает `LevelData` через `ActiveLevel.current_level()` (или эквивалент — см. plan.md), читает `dialogue_triggers[]`, для каждого уникального `event` коннектит handler к `EventBus.<event>` с bound trigger list. Сохраняет список connections для отвязки.
- На `EventBus.battle_ended` (или эквивалент перехода в меню) → отвязывает все connections.

**Resolve flow при срабатывании сигнала:**
1. Получаем сигнал — например `wave_started(idx, is_special)`.
2. Берём bound triggers для event=`wave_started`.
3. Для каждого триггера: проверяем conditions против args сигнала + global state (mood, fired sets).
4. Если condition прошёл и `play_mode=play` → `DialogueManager.play(dialogue_id)`. Если `request` → `DialogueManager.request(dialogue_id, ctx)`.
5. Если manager вернул false / `&""` (already playing, drop) — log + не помечаем fired. На следующем event попробуем снова.
6. Если успех — пометить `_fired_per_run[trigger_id]=true` если `once_per_run`, аналогично session.

Ordering при множественных matched triggers на одном событии: сортировка по позиции в JSON-массиве (детерминизм), seq fire через `await DialogueManager.dialogue_finished` если несколько форс-`play`. Для `request` — manager сам drop-pingует если уже играет, поэтому второй request на том же event просто потеряется — это **OK** (per-event один диалог, дизайнер сам не ставит два конфликтующих).

### 6. Sample content

`data/maps/sample_dialogues.json` — production-grade пример:
- Wave 0: trigger `id=intro`, `event=level_started`, `dialogue_id=boss_intro`, `play_mode=play`, `once_per_run=true`.
- Wave 1: trigger `id=wave1_taunt`, `event=wave_about_to_start`, `wave_index=1`, `dialogue_id=boss_taunt`.
- Wave 1: trigger `id=quick_clear`, `event=wave_cleared`, `wave_index=1`, `cleared_in_turns_lt=3`, `dialogue_id=boss_tired`.
- Mid-level: trigger `id=tick40`, `event=world_turn`, `absolute_turn=40`, `dialogue_id=narrator_ambient`, `once_per_run=true`.
- Wave 2 (final): trigger `id=outro`, `event=level_completed`, `dialogue_id=boss_player_wins`, `play_mode=play`.

Использует существующий контент в `data/dialogues/` — ничего нового Никите не пишем для smoke.

## Acceptance criteria

### Schema & data

- **AC-D1 (data class).** `LevelData.dialogue_triggers: Array[Dictionary]` добавлено. Schema per §1. `LevelSerializer` пишет/читает поле всегда, дефолт — пустой массив.
- **AC-D2 (legacy migration).** Загрузка JSON без `dialogue_triggers` → пустой массив. Существующие `data/maps/*.json` грузятся без правок и валидируются.
- **AC-D3 (validate).** `LevelData.validate()` проверяет:
  - `id` уникален в пределах массива → ERR при дубликатах.
  - `event: StringName, не пустой` → ERR.
  - `dialogue_id` существует в DialogueDB → WARN (не ERR — Никитин контент может появиться позже).
  - `play_mode ∈ {"request", "play"}` → ERR при ином.
  - `chance ∈ [0.0, 1.0]` → ERR при выходе.
  - `wave_index ∈ [0, waves.size())` если задан → WARN.
  - `absolute_turn >= 0` если задан → ERR.
  - Применимость condition к event (например `cleared_in_turns_lt` без `event=wave_cleared`) → WARN.

### Runtime — Director

- **AC-D4 (lifecycle).** На `battle_started` Director загружает текущий уровень, коннектит handler'ы по уникальным `event` строкам. На `battle_ended` — отвязывает. Повторный `battle_started` без `battle_ended` (re-entry) → отвязать предыдущие сначала.
- **AC-D5 (curated events работают).** Все 8 первоклассных событий триггерятся корректно при минимальных smoke-сценариях (см. AC-D14).
- **AC-D6 (open vocabulary).** JSON с `event="some_other_signal"` где `EventBus.some_other_signal` существует — Director подключается. Если сигнала нет — warn-once, остальные триггеры работают.
- **AC-D7 (conditions: wave_index).** `wave_started(2)` фильтрует только триггеры с `wave_index=2` или без него.
- **AC-D8 (conditions: absolute_turn).** `world_turn_ended(40)` файрит только `absolute_turn=40` триггеры (или без условия). На ходу 41 — не файрит.
- **AC-D9 (conditions: cleared_in_turns_lt).** Wave с `turns_to_next=8`, кларится за 5 ходов (`unused_turns=3`). Триггер `cleared_in_turns_lt=4` сработает (`unused_turns=3 ≥ 8-4=4` — нет; ИСПРАВЛЕНИЕ: 3 < 4 → не сработает). Кларит за 3 хода (`unused_turns=5`): `5 ≥ 4` → сработает. Test pass обоих.
- **AC-D10 (conditions: mood).** `mood_required=["burnout"]`, `MoodTracker.get_dominant()=="burnout"` → fire. `=="ascended"` → не fire.
- **AC-D11 (once tracking).** Триггер с `once_per_run=true` срабатывает один раз. После `EventBus.run_started` снова доступен.
- **AC-D12 (chance).** `chance=0.0` — никогда не срабатывает. `chance=1.0` — всегда. `chance=0.5` — стохастика, не тестируем point-wise.
- **AC-D13 (DialogueManager уже играет).** Триггер с `play_mode=play` пытается дёрнуть `play(id)` пока другой диалог играет → `DialogueManager` дропнет с warn (per 003). Trigger **не** помечается fired — следующий event-fire снова попробует.
- **AC-D14 (synthesized wave_about_to_start).** `WaveController` эмитит новый сигнал `EventBus.wave_about_to_start(idx)` за фрейм **до** `_apply_wave_snapshot(idx)`. Триггер на этом event срабатывает между концом старой волны и стартом новой. Smoke: реплика проигрывается, потом снапшот применяется, потом `wave_started`.

### Editor UI

- **AC-D15 (panel сидит в редакторе).** `DialogueTriggerPanel` инстанцирован в `scenes/dev/map_editor.tscn`, виден при открытии редактора, не ломает раскладку существующих панелей.
- **AC-D16 (CRUD).** Add/Edit/Duplicate/Delete всё работает. Save валидирует id-uniqueness, mismatch event/condition выдаёт inline error без потери данных формы. Delete через ConfirmModal.
- **AC-D17 (event dropdown).** OptionButton содержит 8 curated событий + «Custom...» опция → LineEdit. Выбор curated → LineEdit prefilled и read-only. «Custom» → LineEdit editable.
- **AC-D18 (dialogue_id picker).** OptionButton/LineEdit с фильтром по substring. Список — `DialogueDB.get_all_ids()`. Если DB пустая — placeholder «(no dialogues loaded)».
- **AC-D19 (timeline markers EDIT).** Маркеры рендерятся на WaveTimeline в `Mode.EDIT` согласно §4. Hover-tooltip показывает summary. Click → выделение в panel.
- **AC-D20 (timeline markers RUNTIME).** В `Mode.RUNTIME` маркеры **не показываются** (HUD-clean — игроку не подсказываем когда диалог выпадет). [Andrey может перевернуть в clarify, OQ-1.]
- **AC-D21 (autosave/dirty).** CRUD триггеров → `_mark_dirty` → autosave. Без правок к существующему `_mark_dirty` пути.

### Integration

- **AC-D22 (DialogueManager без правок).** В `scripts/presentation/dialogue_manager.gd` ничего не меняем. Director — pure consumer.
- **AC-D23 (mood без блокировки).** Если `MoodTracker` autoload отсутствует (038 не смержен) — Director логирует warn-once и игнорирует `mood_required` conditions. Триггеры без mood работают как обычно.
- **AC-D24 (sample smoke).** `data/maps/sample_dialogues.json` загружается через Load Custom Level → бой запускается → все 5 триггеров отрабатывают в правильных точках при detailed smoke run.

## Open questions

- **OQ-1 (markers in HUD).** Показывать ли маркеры триггеров в `Mode.RUNTIME` для отладки, или строго HUD-clean (см. AC-D20)? Default: HUD-clean. Можно вынести в dev-toggle.
- **OQ-2 (level_completed синхронность).** `level_completed` стреляет когда WaveController вышел за пределы массива волн. Если на нём висит `play_mode=play`-trigger — где играть, пока сцена ещё на месте или после ее unload? Пропоз: до unload (`await dialogue_finished` в роутере перехода). Уточнить когда сценический роутер появится.
- **OQ-3 (chained triggers).** Два триггера на одном событии, оба `play_mode=play` — играются последовательно через `await dialogue_finished`. Разумный ли это default или нужен явный `chain: bool` в схеме? Default — да, последовательно. Кейсы где это плохо — пока не вижу.
- **OQ-4 (conditions composability).** Сейчас все conditions — AND. Если нужен OR (`mood ∈ X OR cleared_in_turns_lt`) — дублируется триггер с одинаковым `dialogue_id`. Этого достаточно для джема. Сложные деревья — out_of_scope.

## Out of scope

- **Автоторинг диалогов.** Текст/структура — JSON-руками (Никита) и loc-keys (Sheets). 039 — только биндинги.
- **Отдельное окно «dialogue editor».** Все вопросы биндинга решаются sidebar'ом в map editor.
- **Global trigger pool** (`data/dialogue_triggers.json` независимо от уровня). Решение Andrey — дублируем между уровнями руками.
- **Graph editor для choice trees.** Choices — JSON в `data/dialogues/*.json`, как сейчас.
- **Автогенерация loc-keys из триггеров.** Никаких StringName→key autogen — text живёт в JSON диалогов, биндинги ссылаются на dialogue_id, никаких inline-строк.
- **Run-flag store** (`flags_required` / `flags_forbidden` в conditions DialogueLine — out_of_scope per 003). 039 наследует это ограничение — `mood_required` достаточно.
- **VFX/SFX подсветка триггера на маркере timeline.** UI-polish — отдельным PR при наличии времени.
- **Множественные одновременные диалоги.** Manager — single-scene, drop при playing. Не пытаемся обходить.
- **`skill_offer_*` события без 040.** Если 040 не смержен на момент имплементации — JSON принимает эти `event`, runtime warn-once «signal not found», триггеры мёртвы. Ничего не ломается.

## Зависимости

**Upstream (must merge first):**
- 003-dialogue-manager — `DialogueManager.play/request` API, `DialogueDB.get_all_ids()`, `EventBus.dialogue_finished`. Уже шипнут.
- 024-wave-editor — `WaveTimeline` Mode.EDIT, WavePanel sibling pattern. Уже шипнут.
- 020-map-editor — base canvas, autosave, ConfirmModal, dirty pipeline. Уже шипнут.

**Soft (degrade gracefully if absent):**
- 038-mood-counter — `MoodTracker.get_dominant()`, `EventBus.player_mood_changed`. Если absent — warn-once, `mood_required` игнорируется.
- 040-wave-skill-choice — emits `skill_offer_about_to_open/closed`. Если absent — соответствующие триггеры мёртвы, остальные работают.
- `nikita/localization` — резолв `tr()` для loc keys в DialogueLine. 039 не зависит — мы дёргаем DialogueManager, а как он рендерит текст — его проблема.

**Downstream (consumers):**
- 040 — будет ссылаться на event vocabulary, описанный здесь.

**Coordination:** Минимальная. Ребята-owner'ы (Alexey/003, Egor/038, Nikita/loc) — ничего не ревьюят, у них только additive consumer.

## Размер

Средняя. Riskpoints:
- WaveTimeline в `Mode.EDIT` — code touch для маркеров. Контролируем тем что не правим `Mode.RUNTIME` рендер.
- `LevelDialogueDirector` lifecycle (особенно reload current level mid-run) — закрываем тестом AC-D4.
- Synthesized `wave_about_to_start` — 5-строчная правка `wave_controller.gd`. Egor-coordinated, additive (новый сигнал + emit), его ревью не блокирующее но желательное.

## История правок

- 2026-05-03 v1 — Andrey clarify: per-level only, нет global pool, нет отдельного окна, dialogue_preview.tscn остаётся viewer'ом, дублируем триггеры между уровнями руками. Локализация text-полей — Никитина параллельная работа, не блокирует.
