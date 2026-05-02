# 024-wave-editor — spec

**Owner:** Andrey (driver, full-stack — редактор, runtime, push-out, score, HUD).
**Coordination:** none required (lane fully owned). Stasyan post-merge — playtest, баланс волн, заполнение sample maps. Никита — контент диалогов через сигналы 025.
**Status:** Active — clarify-round пройден, имплементация в этой же сессии.

## Цель

К map-редактору (020) добавить временное измерение: «**волны**». Дизайнер размечает на горизонтальном таймлайне (1 ход = 1 пиксель) якорные точки волн; внутри каждой волны лежит **полный снапшот карты** (пол + объекты + спавнеры) и спавнеры с обратным **таймером** в ходах. В рантайме тот же таймлайн показан игроку в HUD (read-only); карта мутирует от волны к волне; актёры на гексах, ставших непроходимыми, выталкиваются по hex-spiral BFS с цепной логикой; убийство всех живых врагов авто-перепрыгивает к следующей волне, оставшиеся ходы добавляются в счёт.

Тема джема — «метаморфозы». Эта спека — главный технический носитель темы: карта и состав врагов меняются прямо во время боя.

## Scope-граница

**В скоупе:** data-схема волн, таймлайн-виджет (edit + runtime modes), редактор-интеграция (active wave, копирование с предыдущей, insert/delete/special), runtime `WaveController`, push-out + chain-push в `HexGrid`, авто-клир и счёт, HUD score-corner, sample карта.

**Вне скоупа:** см. секцию «Out of scope» внизу. Главные исключения: event-triggered волны (только turn-count + auto-clear), drag-reorder волн, миграция атласов в один (отдельная задача), VFX/SFX мутаций (029).

## Что вводится

### 1. Расширение `LevelData` — поле `waves`

`LevelData.waves: Array[Dictionary]`. Каждая волна:

```gdscript
{
  "index": 0,                # int, 0-based, contiguous
  "is_special": false,       # bool — больший кружок на таймлайне (визуальный тег, без механики в v1)
  "turns_to_next": 5,        # int >= 1 для всех, кроме последней (у последней = 0)
  "floor": [...],            # full snapshot — same shape as legacy LevelData.floor
  "objects": [...],          # full snapshot — same shape as legacy LevelData.objects
  "spawners": [              # full snapshot
    {"coord": Vector2i, "kind": &"enemy", "ref": &"manekin", "timer": 3},
    {"coord": Vector2i, "kind": &"player", "ref": &"", "timer": 1},
    ...
  ],
}
```

**Wave 0 = initial state.** То, что раньше лежало в `LevelData.floor / objects / spawners` на корне, теперь живёт в `waves[0]`. Корневые поля удаляются из новых сейвов; легаси-сейвы при загрузке мигрируют в `waves=[wave0_from_root]` (один-волновый уровень, тождествен старому поведению).

**Семантика snapshot.** Каждая волна — **полная картина мира на момент её старта**. Diff не храним. Аргументы:
- Reorder/insert волн не каскадирует — каждая волна самодостаточна.
- Cumulative-state в редакторе = просто `waves[active]` (рисуй прямо).
- Runtime apply = очистил FloorLayer, набил снапшот. Идемпотентно.
- Цена в JSON: 10 волн × ~50 floor cells × мелкие объекты = ~30 КБ на уровень. Приемлемо.

Чтобы дизайнеру не страдать от ручного копирования каждый раз — есть кнопка **«Copy from previous wave (no spawners)»** (см. секцию Editor).

**Spawner timer.** Поле `timer: int >= 1`. Семантика:
- На старте своей волны спавнер появляется **визуально** на координате с цифрой `timer`.
- В конце каждого мирового хода (`EventBus.world_turn_ended`) `timer--` для всех активных спавнеров.
- Когда `timer` декрементируется с `1 → 0`: на **следующем** ходе (т.е. в момент его конца) актёр инстанциируется на coord, плейсхолдер удаляется. Это совпадает с формулировкой Andrey: «когда остается 1, в следующий ход спаунится враг».
- Если волна меняется до того, как `timer` отщёлкал до 0 — спавнер **discard** (его волна закрылась без него).
- Игрок-спавнер: `kind == &"player"` живёт только в волне 0 (валидация — exactly one across union of waves).

### 2. Wave timeline widget (reuse: editor + runtime HUD)

`scenes/ui/wave_timeline.tscn` — Control. Один и тот же сценический prefab используется в редакторе и в боевой сцене HUD.

**Геометрия.** Горизонтальный бар. Слева иконка-часы (clock). Дальше шкала, **1 пиксель = 1 ход**. Якорные точки волн нарисованы как круги: regular = маленький ⌀, special = больший ⌀ (per Andrey, A5). Числа `turns_to_next` — между якорями. Длина бара динамическая = `Σ turns_to_next + paddings`.

**Два режима:**

- **`Mode.EDIT`** — в редакторе.
  - Якорь кликабелен: LMB → `anchor_clicked(idx)` (контроллер переключает active wave).
  - Якорь RMB → `anchor_context_requested(idx, screen_pos)` (контроллер показывает popup: Delete / Toggle special).
  - Числа `turns_to_next` между якорями — кликабельные `LineEdit`'ы с numeric validation (min 1).
  - Кнопка **«+ Wave»** на правом конце бара — append.
  - RMB на gap между якорями → `gap_context_requested(after_idx)` (контроллер показывает popup: Insert wave here).
  - Подсветка active wave: контурное обведение якоря.

- **`Mode.RUNTIME`** — в боевом HUD (плейтест + продакшн).
  - Read-only. Никаких эдитов.
  - «Часы»-курсор движется слева направо синхронно с `turns_into_wave`.
  - Якоря пройденных волн — притушены. Текущая — подсветка. Будущие — нормально.
  - Анимация tick на decrement числа `turns_to_next` (мелкий пульс, длительность из `GameSpeed.get_value("ui", "wave_tick_anim_sec")`, дефолт 0.2с).
  - Игрок видит **всё** (числа, таймеры, special-якоря). Per Andrey F2: «пока что всё видно, скрывать будем потом».

**Стилизация.** Только через `UiTheme`. Цвета якорей, рамок, фонов — новые константы в `UiTheme`: `WAVE_ANCHOR_FILL`, `WAVE_ANCHOR_PASSED`, `WAVE_ANCHOR_CURRENT`, `WAVE_ANCHOR_SPECIAL_RADIUS_MULT`, `WAVE_BAR_BG`, etc.

### 3. Editor integration

**Новый узел в `scenes/dev/map_editor.tscn`** — `WavePanel` (вертикальная docked-панель **сверху** канвы, per Andrey E1). Содержит:
- `WaveTimeline` (Mode.EDIT).
- Кнопку **«Copy from previous wave (no spawners)»** — дизейблед на волне 0; на остальных — deep-copy `waves[active-1].floor + .objects` в `waves[active]`, очищает `waves[active].spawners`. Триггерит autosave + dirty.
- Кнопку **«Toggle special»** для active wave (дублирует RMB-context для discoverability).

**`MapEditorController` — новые состояния:**
- `active_wave_index: int = 0`. Все placement/erase/replace-all операции теперь пишут в `_level.waves[active_wave_index]` вместо корневых полей.
- `_repaint_canvas()`: теперь рисует **cumulative state at active wave** = `waves[active_wave_index]` (это и есть полный снапшот).
- Highlight новых-в-этой-волне айтемов: для objects/spawners — субтильное outline-glow поверх обычного спрайта; для floor cells — лёгкий tint overlay. Сравнение: «есть в `waves[active]` и нет в `waves[active-1]`». На волне 0 highlight выключен (всё «новое»).

**Spawner timer input.** При placement спавнера — рядом с курсором появляется numeric LineEdit, дефолт `1`, фокус сразу. Enter / клик-вне → коммит. При выделении уже-стоящего спавнера (LMB по нему в IDLE) — тот же LineEdit над спавнером. Per Andrey E6 — «лучший вариант», я взял inline-edit (не popup, не side-panel) — видно сразу что и где, без перекрытия канвы. Per Andrey E8 — «лучше числами» — это и есть числа, прямой ввод.

**Wave operations:**
- **+ Wave** (правый край бара): append с дефолтами `is_special=false, turns_to_next=5`. Новая волна получает deep-copy `floor + objects` от предыдущей (как «Copy from previous»), spawners пустые. Active wave переключается на новую.
- **Insert wave**: RMB на gap → ConfirmModal не нужен, инсерт прямой. Новая волна вставляется после `gap_after_idx`, индексы последующих волн +1. Floor+objects copy-from-prev, spawners пустые.
- **Delete wave**: RMB на якоре → context → Delete → **`ConfirmModal.ask("Удалить волну N?", danger=true)`** (per Andrey E4). Wave 0 нельзя удалить (single source of initial state) — RMB-context не показывает Delete на ней.
- **Toggle special**: RMB на якоре → context → Toggle special → flip `is_special`. Тривиально.
- **Edit `turns_to_next`**: клик на число между якорями → LineEdit → enter. Min 1, max — без cap (10 — мягкое практическое ограничение per A5, но enforce'ить не будем).
- **Reorder drag-drop**: **out_of_scope** (per Andrey E4 не упомянул, и это foot-gun: меняет каскад state'ов, требует переоценки чьей-то работы). Делается через insert + delete вручную.

### 4. Runtime: `WaveController`

Новый узел `scripts/runtime/wave_controller.gd` (создаём папку `scripts/runtime/` — её ещё нет в репе) + `scenes/runtime/wave_controller.tscn`. Инстанциируется в боевой сцене `scenes/dev/godmode.tscn` как ребёнок root.

Состояние:
```gdscript
var _level: LevelData
var _current_wave_index: int = -1   # -1 = не стартовали ещё
var _turns_into_wave: int = 0
var _pending_spawners: Array[Dictionary] = []  # копии записей waves[idx].spawners — кроме player'а — с decrementing timer
```

API:
```gdscript
func start_level(level: LevelData) -> void
func _on_world_turn_ended(turn: int) -> void
func _on_actor_died(actor: Actor) -> void
func _advance_wave() -> void
func _apply_wave_snapshot(wave_index: int) -> void
func _spawn_from_pending(spawner_dict: Dictionary) -> void
func _check_auto_clear() -> void
```

Sequence:
- `start_level(level)`: cache, `_current_wave_index = 0`, `_apply_wave_snapshot(0)`.
- `_apply_wave_snapshot(idx)`:
  1. Diff old vs new floor: erase missing tiles → push-out их residents. Set new tiles.
  2. Diff old vs new objects: remove gone, add new. Push-out residents с гексов, где новый объект непроходим.
  3. Очистить `_pending_spawners`. Проинстанциировать плейсхолдеры для `waves[idx].spawners` (кроме `player` — он уже на сцене с волны 0). Скопировать записи в `_pending_spawners`.
  4. `_turns_into_wave = 0`.
  5. Emit `EventBus.wave_started(idx, waves[idx].is_special)`.
- `_on_world_turn_ended(turn)`:
  1. `_turns_into_wave += 1`.
  2. Для каждого pending — `timer -= 1`. Если `timer == 0` → `_spawn_from_pending(...)` (создаёт actor, удаляет плейсхолдер, удаляет из `_pending_spawners`). Emit `EventBus.actor_spawned(actor)` *(если ещё не существует — добавить)*.
  3. Если `_turns_into_wave == waves[_current_wave_index].turns_to_next` → `_advance_wave()`.
- `_on_actor_died(actor)` → `call_deferred("_check_auto_clear")` (ждём конец фрейма, чтобы все смерти в этом тике осели).
- `_check_auto_clear()`: если `living_enemies_count() == 0 AND _pending_spawners.is_empty()` → unused = `waves[idx].turns_to_next - _turns_into_wave`; `RunScore.add(unused)`; `EventBus.wave_cleared(idx, unused)`; `_advance_wave()`.
- `_advance_wave()`: `_current_wave_index += 1`. Если за пределами `_level.waves.size()` → `EventBus.level_completed(RunScore.total)` (волн больше нет, уровень завершён). Иначе → `_apply_wave_snapshot(new_idx)`.

**Атомарность транзишна.** `_apply_wave_snapshot` — один логический тик. Игроку input блокируется на `GameSpeed.wait("battle", "wave_transition_sec")` (дефолт 0.15 сек) — даёт визуальной системе показать смену.

### 5. Push-out: `HexGrid`-расширение

Метод (additive, не ломает 002):
```gdscript
func find_passable_for_displacement(from: Vector2i, exclude: Array[Vector2i] = []) -> Vector2i:
    # BFS по hex-neighbours от `from`. Skip blocked (impassable terrain или non-walkable object).
    # Skip `exclude` (для chain-push: не лезть на занятые этой же транзакцией клетки).
    # Tie-break: BFS expand-order детерминированный (clockwise from north — текущая convention в HexGrid).
    # Bounded radius: const MAX_DISPLACEMENT_RADIUS = 30.
    # Return Vector2i.MAX как sentinel при no-result.
```

Wrapper:
```gdscript
func displace_actor(actor: Actor, exclude: Array[Vector2i] = []) -> bool:
    # 1. target = find_passable_for_displacement(actor.coord, exclude)
    # 2. if target == sentinel → actor.kill_with_reason("crushed"); return true.
    # 3. if target занят другим актёром B:
    #    chain — recursively displace_actor(B, exclude + [actor.coord, target])
    #    после успешного chain'a — actor → target.
    # 4. move_actor(actor, target)
    # 5. TileObjectResolver.on_actor_entered (existing hook) — фактически вызывается из move_actor если уже есть; иначе явно вызвать.
```

**Chain-push защита от oscillation.** `exclude` в рекурсии аккумулирует все исходные клетки цепи + промежуточные target'ы. Гарантирует, что A → B → ... никогда не вернётся к A.

**Damage-on-land** (Andrey C4 — «сразу»): TileObjectResolver уже подписан на `actor_moved`/entered. Если резолвер для landing-tile наносит damage — нанесёт сразу. Если механика «entered» сейчас триггерится только через `grid.move_actor` (а не через push) — добавить тот же call после displacement. Проверить при имплементации.

### 6. Score: `RunScore` autoload + HUD widget

**`scripts/infrastructure/run_score.gd`** (новый autoload):
```gdscript
extends Node
signal score_changed(total: int, delta: int)
var total: int = 0

func add(delta: int) -> void:
    if delta == 0: return
    total += delta
    score_changed.emit(total, delta)

func reset() -> void:
    total = 0
    score_changed.emit(total, 0)

func _ready() -> void:
    EventBus.run_started.connect(reset)
```

Зарегистрировать в `[autoload]` после `EventBus`, до `AudioDirector` (порядок не критичен, но стабильность ради).

**HUD виджет** `scenes/ui/score_corner.tscn` + `scripts/presentation/ui/score_corner.gd`:
- Label в **верхнем правом углу** боевого HUD CanvasLayer (per Andrey D1 «в углу»).
- Подписан на `RunScore.score_changed`. Текст = `str(total)`.
- На increment — punch tween (scale 1.0 → 1.2 → 1.0 за `GameSpeed.get_value("ui", "score_punch_sec")`, дефолт 0.25).
- Шрифт: `UiTheme.FS_NUM_HUGE`. Outline через `UiTheme.apply_world_text_outline` (хотя HUD — но всё равно поверх боевой сцены).

### 7. EventBus additions

- `world_turn_ended(turn: int)` — **уже есть** (verified в `scripts/infrastructure/event_bus.gd:53`). Используем существующий.
- `wave_started(index: int, is_special: bool)` — **новый**.
- `wave_cleared(index: int, unused_turns: int)` — **новый**, только auto-clear path.
- `level_completed(total_score: int)` — **новый**, последняя волна закрылась.
- `actor_spawned(actor: Actor)` — проверить, есть ли уже; добавить если нет.

## Acceptance criteria

- **AC-W1 (data class).** `LevelData.waves: Array[Dictionary]` добавлено. Schema per «1. Расширение `LevelData`». `LevelSerializer` пишет waves-формат всегда.
- **AC-W2 (legacy migration).** Загрузка JSON без поля `waves`, но с легаси `floor/objects/spawners` на корне → пакуется в `waves=[wave0]` с `is_special=false, turns_to_next=0`. Уровень играется как однополосный (поведение тождественно до 024). Существующая `data/maps/sample.json` грузится без правок.
- **AC-W3 (validate).** `LevelData.validate()` проверяет: `waves[].index` contiguous from 0; ровно 1 player-спавнер по union всех `waves[].spawners`; все coord ∈ floor этой же волны; `turns_to_next ≥ 1` для всех кроме последней; все `spawner.timer ≥ 1`. WARN-only: `spawner.timer > waves[i].turns_to_next` (никогда не сработает в этой волне).
- **AC-W4 (timeline widget).** `scenes/ui/wave_timeline.tscn` рендерит бар с якорями и числами, 1 turn = 1 px. `Mode.EDIT` и `Mode.RUNTIME` оба работают, переключаются `@export var mode`.
- **AC-W5 (editor active wave).** В MapEditor бар сверху над канвой. LMB на якоре → `active_wave_index` меняется → канва перерисовывается на снапшот этой волны. Все placement-операции пишут в `waves[active_wave_index]`. Highlight новых-в-этой-волне айтемов работает (objects/spawners — outline-glow; floor cells — tint overlay).
- **AC-W6 (wave operations).** + Wave / Insert (RMB на gap) / Delete (RMB на якоре + ConfirmModal danger / Wave 0 нельзя удалить) / Toggle special (RMB) / Edit `turns_to_next` (LineEdit на числе) — все работают, все триггерят autosave.
- **AC-W7 (copy-from-prev).** Кнопка «Copy from previous wave (no spawners)» в WavePanel: deep-copy `waves[active-1].floor + .objects` в `waves[active]`, spawners очищены. Дизейблед на волне 0.
- **AC-W8 (spawner timer in editor).** При placement или selection спавнера — inline numeric LineEdit рядом со спавнером, дефолт 1. Запись в `spawner.timer`. Цифра рендерится поверх плейсхолдера через `UiTheme.FS_NUM_OVERHEAD` + outline.
- **AC-W9 (runtime apply).** WaveController при `start_level` → `_apply_wave_snapshot(0)`. Каждое продвижение волны → новый снапшот применяется (FloorLayer set_cell-batch, objects diff, spawners → плейсхолдеры + pending). Push-out на newly-impassable hexes (см. AC-W11).
- **AC-W10 (countdown & spawn).** `EventBus.world_turn_ended` → `_turns_into_wave++` + decrement всех pending timers. Когда `timer` декрементируется с 1 на 0, на **следующем** срабатывании `world_turn_ended` (т.е. в его обработчике) actor инстанциируется. Плейсхолдер удаляется. Pending — discard'ится при смене волны.
- **AC-W11 (push-out + chain).** `HexGrid.find_passable_for_displacement(from, exclude)` — BFS hex-spiral, deterministic neighbour order, `MAX_DISPLACEMENT_RADIUS = 30`, sentinel при no-result. `HexGrid.displace_actor(actor, exclude)` — chain-push рекурсивно с накоплением `exclude`. No-target → `actor.kill_with_reason("crushed")`. Same algorithm для player и enemy.
- **AC-W12 (auto-clear).** На `EventBus.actor_died` — deferred check. Если `living_enemies == 0 AND _pending_spawners.is_empty()` → `unused = turns_to_next - turns_into_wave`; `RunScore.add(unused)`; emit `wave_cleared(idx, unused)`; `_advance_wave()`. Holds across waves: enemy из волны 1 жив → блокирует auto-clear волны 2.
- **AC-W13 (level_completed).** `_advance_wave()` за пределы массива волн → `EventBus.level_completed(RunScore.total)`. Ничего больше WaveController не делает (роутинг к меню — на уровне сценического контроллера, out_of_scope здесь).
- **AC-W14 (HUD timeline).** Тот же `WaveTimeline` (`Mode.RUNTIME`) в HUD `scenes/dev/godmode.tscn`. Часы-курсор движется. Tick анимация на decrement.
- **AC-W15 (HUD score corner).** `RunScore` autoload зарегистрирован. `scenes/ui/score_corner.tscn` в HUD top-right. Punch tween на increment.
- **AC-W16 (atomicity & timing).** Wave transition использует `GameSpeed.wait("battle", "wave_transition_sec")` (дефолт 0.15). Player input блокируется на этот период.
- **AC-W17 (special waves).** `is_special: bool` per wave рендерится как **больший якорь** на таймлайне (`WAVE_ANCHOR_SPECIAL_RADIUS_MULT` × normal radius). Только визуал в v1.
- **AC-W18 (sample level).** `data/maps/sample_waves.json` — 3-волновый демо: волна 0 (player + 1 manekin с timer=2, turns_to_next=5); волна 1 (новый manekin с timer=3, стена ломается = удаление wall-объекта на coord X, turns_to_next=6); волна 2 (пропасть появляется под одним из гексов где может стоять player в зависимости от его движения = floor cell erased + push-out demo, turns_to_next=0).
- **AC-W19 (smoke).** Загрузить sample_waves.json через Load Custom Level → бой запускается → волна 0 видна на таймлайне → manekin появляется на ходу 2 → если убить его до хода 5 → score += оставшиеся ходы → волна 1 стартует → стена удаляется → новый manekin на ходу 3 (от старта волны 1) → итд.

## Open questions — RESOLVED в clarify-round

- **OQ-1 (триггеры).** Только turn-count + auto-clear. Event-triggered волны — out_of_scope. *(Andrey G1.)*
- **OQ-2 (spawner timer reference).** Relative to wave start. *(Andrey A2.)*
- **OQ-3 (wave 0 = initial).** Yes. Корневые legacy-поля → `waves[0]`. *(Andrey A3.)*
- **OQ-4 (snapshot vs diff).** Snapshot per wave. *(Andrey B2 + моё обоснование.)*
- **OQ-5 (objects in-place transform).** Нет. Только delete + add new. Wall→rubble = удалить wall + добавить rubble. *(Andrey B3.)*
- **OQ-6 (copy-from-prev).** Кнопка нужна. Floor + objects copy, spawners очищены. *(Andrey B4.)*
- **OQ-7 (push-out algorithm).** BFS spiral, дальше при отсутствии, chain-push, damage on land immediate. *(Andrey C1-C5.)*
- **OQ-8 (score formula).** `+= unused_turns` за уровень. В углу HUD. *(Andrey D1, D3, D6.)*
- **OQ-9 (pending spawners on auto-jump).** Discard. *(Andrey не дал прямого ответа — D4 «не понял» — по умолчанию discard, обоснование: их волна закончилась без них; альтернатива в OQ-10.)*
- **OQ-10 (mutations on auto-jump).** Применяются полным снапшотом в момент старта новой волны. *(Andrey D5.)*
- **OQ-11 (special wave mechanics).** Только визуал v1. Семантика — позже, через контент. *(Andrey A5.)*

## Open questions — остались на post-merge

- **OQ-12 (chain damage order).** Если A push'ит B на лаву, B push'ит C с обрыва — порядок damage'ов? Пропоз: сначала **все displacement'ы выполняются** (move_actor batch), потом **все on_entered хуки** срабатывают по порядку move'ов. Так A не успевает «уронить» B заранее, если B сам push'ит C дальше. Уточнить на плейтесте.
- **OQ-13 (multi-atlas cleanup).** Andrey-B1 предложил «снести остальные атласы». Это отдельная задача — миграция всех существующих карт + смена палитры в редакторе. **Out_of_scope** для 024. Создать ли отдельную спеку (027? 028?) — обсудим после мержа.

## Out of scope

- **Event-triggered волны** (boss-killed → wave). Только turn-count и auto-clear.
- **Drag-reorder волн.** Делается через insert + delete + ручной перерисов снапшотов.
- **Per-spawner overrides** кроме `timer` (HP, skills, level). Если понадобится — отдельной спекой.
- **Visual VFX мутаций** (wall-break particles, pit-open animation). 029-feedback-polish.
- **Wave preview / scrub** в редакторе с симуляцией будущего. Слишком тяжело для джема.
- **Multi-atlas cleanup → один атлас** (Andrey B1). Отдельная спека.
- **Score persistence** (high-score table, лидерборд). Только текущий run.
- **Объекты-трансформы in-place** (wall → rubble на той же клетке, без delete-add). Делается дизайнером как delete + add new.
- **Мутации floor с per-cell миксом тайлсетов** (часть пола в waves[1] из одного атласа, часть из другого). Все cells одной волны живут в `waves[i].floor`, который ссылается на единый `tileset_path` уровня (legacy поле LevelData).
- **Wave-specific музыка / SFX** (особый звук для special wave). 029.
- **Восстановление actor'а на старую клетку** если в следующей волне она снова стала проходимой. Нет такой механики; pushed actor остаётся там, куда упал.
- **Авто-pause на wave_started для cinematic** (типа intro special wave). Если понадобится — через 025-level-dialogues и его pause-modal.

## Зависимости

- **Upstream (must merge first):**
  - 020-map-editor — base canvas, palettes, save/load, autosave, ConfirmModal — всё переиспользуем.
  - 002-hex-grid — `HexGrid` extends здесь (additive `find_passable_for_displacement` + `displace_actor`). Owner Egor — additive методы, его review нужен.
  - 018-tile-objects — wave snapshots содержат tile_object refs, регистр читаем read-only.
  - 003-dialogue-manager — не блокирующая зависимость; 025-level-dialogues потребит наши сигналы.
  - 009-ui-kit — UiTheme constants новые (`WAVE_*`).
- **Downstream (consumers):**
  - 025-level-dialogues — потребляет `wave_started`, `wave_cleared`, `level_completed` для триггеров.
  - 029-feedback-polish — VFX/SFX wave start, push-out, score increment.
  - Future roguelike-loop — потребляет `level_completed(total_score)` для перехода к мета-экранам.
- **Coordination:** Egor (HexGrid additive review) — единственный внешний touchpoint. Stasyan — после мержа делает контентные карты + sample_waves.json правит.

## Возможное разбиение (если время поджимает)

Если в имплементации станет видно, что одна спека поддерживать тяжело — можно расщепить на:
- **024-wave-editor** — data + editor (P1, P5, P7 из tasks).
- **024a-wave-runtime** — WaveController + push-out + score + HUD (P2, P3, P4, P6).

Решение — после первого имплементационного дня, не сейчас.

## История правок

- 2026-05-02 v1 — RESERVED stub: набросок `phases: Array[Dictionary]` с `trigger.kind ∈ {turn, delay, event}`, additive фазы, открытые OQ.
- 2026-05-02 v2 — clarify-round с Andrey, **полный rewrite**. Тема — «волны» вместо «фаз». Добавлены: snapshot-per-wave модель, спавнер-таймеры (relative + reverse-countdown), push-out + chain-push, auto-clear → score, special waves (visual), copy-from-prev workflow. Папка переименована `phase-timer-bar` → `wave-editor`. Сценарий «фаза удаляет объекты» закрыт через snapshot-семантику. Owner — Andrey solo, координация только с Egor по HexGrid additive методам.
