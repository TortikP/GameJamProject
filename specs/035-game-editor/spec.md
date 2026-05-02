# 035-game-editor — spec

**Owner:** Andrey (driver, full-stack — meta-редактор, autoload, transition overlay, main-menu кнопки).
**Coordination:**
- **Alexey** — owner будущих спек **upgrade screen** и **first-level cutscene**. Эта спека определяет хуки (`EventBus.upgrade_choice_requested`, `EventBus.campaign_cutscene_requested`) и предоставляет stub-ответчиков. Когда Alexey будет делать настоящие сцены — он подменит stub'ы, не трогая CampaignController.
- **Stasyan** — после мержа собирает реальные `data/games/*.game.json` из существующих карт.
- **Egor / Sergey** — coordination не требуется, hex/skill ядро не трогается.

**Status:** Draft. Жду явного go от Andrey'а; имплементацию запускаю в этой же ветке `andrey/game-editor`.

## Цель

Сейчас игра = одна карта (godmode-сцена грузит один `LevelData` через `ActiveLevel`). Это блокирует roguelike-петлю: нет понятия «прогресс по уровням», нет места для прокачки между уровнями, нет визуальной идентичности «метаморфозы» между этапами.

После 035:
- В главном меню под кнопкой **Map Editor** появляется **Game Editor**. Дизайнер собирает «игру» = упорядоченный список уровней (карт из `data/maps/`).
- Игра сохраняется в `data/games/<name>.game.json`.
- Кнопка **Load Game** в главном меню грузит игру с уровня 1.
- При победе на уровне (последний враг последней волны убит → текущий `EventBus.level_completed`) — экран **выбора прокачки** (stub в этой спеке, реальная сцена — отдельная спека) → визуальный переход «метаморфозы» → следующий уровень.
- Первый уровень помечен флагом `is_intro=true` — перед его стартом дёргается хук катсцены (отдельная спека). Если слушатель катсцены не подключен — хук no-op, уровень стартует сразу.
- Финальный уровень: после `level_completed` показывается **You Win** экран (минимальный stub) → главное меню.

«Босс уровня» в этой спеке = «последний враг последней волны». Никаких специальных «boss wave» флагов в `LevelData` не вводится — это полностью покрывается существующим `level_completed`. Если понадобится визуально подсветить boss-волну — это extension в 024-wave-editor, не здесь.

## Что вводится

### 1. `GameData` (новая pure-data сущность)

`scripts/core/maps/game_data.gd`. Сериализуется в JSON, грузится `GameSerializer`'ом.

| Поле | Тип | Описание |
|---|---|---|
| `name` | `String` | Человекочитаемое имя. Файл = `<sanitized_name>.game.json`. |
| `version` | `int` | Schema version. v1 = `1`. |
| `levels` | `Array[Dictionary]` | Упорядоченный список. Каждый: `{map_path: String, display_name: String, cutscene_id: StringName, is_intro: bool}`. |

Жёсткие инварианты `GameData.validate() -> Array[String]` (массив сообщений; пустой = валидно):
- `levels.size() >= 1`. Иначе — отказ записи + load-toast.
- Каждый `map_path` оканчивается на `.json` и существует в `res://data/maps/`. Не существует — drop entry с warn (не валит весь файл).
- Ровно ноль или один уровень с `is_intro=true`. Если два+ — записать первый, остальным сбросить флаг + warn-toast.
- `cutscene_id` пустой (`&""`) разрешён — означает «без катсцены».

Расширение `.game.json` (а не просто `.json`) — отделяет игры от карт в FileDialog'ах и предотвращает случайную загрузку карты как игры.

### 2. Сцена `scenes/dev/game_editor.tscn`

Дерево (упрощённо):
```
GameEditor (Control)
├── Header (HBoxContainer)
│   ├── NameInput (LineEdit — имя игры)
│   └── Spacer + [Save] [Load] [Playtest] [Exit] кнопки
├── LevelList (VBoxContainer внутри ScrollContainer)
│   └── (динамически) LevelRow × N
│       Каждая строка:
│       [#index] [map dropdown ▼] [display_name input] [cutscene_id input] [is_intro ☐] [↑] [↓] [✕]
└── AddLevelButton (внизу списка)
```

Map dropdown — это `OptionButton`, populated один раз при `_ready` из `DirAccess.get_files_at("res://data/maps/")` с фильтром `*.json` (исключая `__playtest__.json` и `__autosave__.json`). Refresh-кнопкой не нагружаем — F5 главного меню перезагрузит editor.

Reorder via [↑] / [↓] кнопок per-row — без drag-and-drop (mini-spec, экономим). Перемещение свапает `levels[i]` ↔ `levels[i±1]`, индексы `#` пере-нумеруются.

`is_intro` чекбокс с автоматическим эксклюзивным поведением: ставится на одну строку — снимается с остальных.

**Autosave.** Тот же паттерн что в 020: debounced 1.5 сек → `res://data/games/__autosave_game__.json`. На входе в редактор — если autosave существует и mtime ≤ 24h → ConfirmModal «Восстановить?».

### 3. `ActiveGame` (новый autoload)

`scripts/infrastructure/active_game.gd`:

```gdscript
extends Node

var game_path: String = ""
var current_index: int = 0
var _game: GameData = null

func load_game(path: String) -> bool      # читает GameData с диска, current_index=0, queue первый уровень
func has_active_game() -> bool             # _game != null
func current_level() -> Dictionary         # _game.levels[current_index]
func advance() -> void                     # current_index++; queue следующий уровень или campaign_finished
func is_last_level() -> bool
func clear() -> void                       # сброс, при возврате в main menu
```

`load_game(path)` после успешной загрузки сразу вызывает `ActiveLevel.queue(_game.levels[0].map_path)` — godmode стартует первый уровень тем же путём, что и Load Custom Level.

Зарегистрировать в `[autoload]` после `ActiveLevel` (зависит от него).

Очистка в `main_menu._ready()` — добавить `ActiveGame.clear()` рядом с существующими `ActiveLevel.clear()`.

### 4. `CampaignController` (новый autoload-слушатель)

`scripts/runtime/campaign_controller.gd`. Один экземпляр, autoload, никаких сцен-references — работает только через сигналы.

**Поведение:**
- При `EventBus.level_completed(score)`:
  - Если `not ActiveGame.has_active_game()` — игнор (singleplayer-карта, поведение не меняется).
  - Иначе: emit `EventBus.upgrade_choice_requested(score, _on_upgrade_done)`. Слушает один callback. Если за `[meta]/upgrade_choice_timeout_sec` (default 0.5 сек) никто не ответил — считает что слушателя нет, сразу триггерит fallback `_on_upgrade_done()`.
  - `_on_upgrade_done()`: запускает transition overlay (см. §5), `await` его завершения, потом:
    - Если `ActiveGame.is_last_level()` → emit `campaign_finished(RunScore.total)` → change_scene на campaign_end.tscn (см. §6).
    - Иначе → `ActiveGame.advance()`, change_scene godmode (новый уровень загрузится через `ActiveLevel.queued_path`).
- При `EventBus.scene_ready` (новый сигнал, эмитится godmode_controller'ом в конце `_ready`):
  - Если активная игра и текущий уровень — intro (`is_intro=true`) и/или `cutscene_id != &""`:
    - emit `EventBus.campaign_cutscene_requested(cutscene_id, _on_cutscene_done)`.
    - Слушателя нет (timeout 0.5 сек) → no-op, уровень стартует.
    - `_on_cutscene_done()` — пока что просто log; будущая катсцена-спека сама управляет паузой ввода через `EventBus.input_locked` (вне скоупа 035).

Stub-ответчик upgrade screen для джема: внутри 035 поставлен временный `_DummyUpgradeStub` Node, тоже autoload. Слушает `upgrade_choice_requested`, ждёт `upgrade_screen_min_display` (уже есть в `[ui]`, default 2.0 сек), показывает toast `"Upgrade placeholder — +1 score"`, прибавляет 1 в `RunScore`, дёргает callback. Этот stub удаляется первой же реальной upgrade-спекой Alexey.

### 5. Transition overlay `scenes/meta/level_transition.tscn`

CanvasLayer + ColorRect на весь экран + skript на нём.

**Эффект «метаморфозы» (короткий, ≤ 2 сек total):**
1. **Phase A — pre-shake** (`[meta]/transition_shake_sec`, default 0.4s): screen shake камеры через `EventBus.camera_shake_requested(intensity, sec)` (сигнал есть, см. event_bus.gd). Intensity = high preset.
2. **Phase B — distort & fade-out** (`[meta]/transition_distort_sec`, default 0.6s): на CanvasLayer'е ColorRect с CRT-distort шейдером (reuse существующий из `010-crt-postfx`, добавить `wave_amplitude` parameter и пульсировать его 0 → 1.0 → 0); параллельно `modulate.a` от 0 до 1 (чёрный fade-out).
3. **Phase C — hold black** (`[meta]/transition_hold_sec`, default 0.15s): кадр чёрного без эффектов — момент «метаморфозы».
4. **Phase D — fade-in** (`[meta]/transition_fade_in_sec`, default 0.6s) — выполняется уже в новой сцене после `change_scene`. CampaignController инстанциирует `level_transition.tscn` в новой сцене с `mode = FADE_IN`.

Total ≤ 1.75s, легко крутить через `game_speed.cfg`. F5 в проде live-reload.

**Никакого дополнительного аудио** в этой спеке — звук метаморфозы идёт отдельно через `AudioDirector.play_event(&"level_transition")`, но определение sfx — забота Andrey'а в polish-фазе (вне 035).

### 6. Стартовый и финальный экраны

- **Главное меню** (`scenes/main_menu.tscn` + `main_menu.gd`):
  - Новые кнопки между **Map Editor** и **Load Custom Level**:
    - **Game Editor** — change_scene → `game_editor.tscn`.
    - **Load Game** — FileDialog с `current_dir = res://data/games/`, filter `*.game.json` → `ActiveGame.load_game(path)` → change_scene godmode.
  - Существующие **Start Run** / **Load Custom Level** не трогаются — sandbox-доступы остаются.
- **`scenes/meta/campaign_end.tscn`** — минимальный экран: заголовок «You Win», `Total score: N` (из `RunScore.total`), кнопка `Main Menu`. Никакого замаха на «credits», это polish.
- **`data/games/sample.game.json`** — ровно одна игра-пример из 2 уровней (`sample.json` дважды), `is_intro` на первом, `cutscene_id` пустой. Чтобы Load Game работал «из коробки» сразу после мержа.

### 7. Новые/расширенные сигналы EventBus

`scripts/infrastructure/event_bus.gd`:

```gdscript
# 035-game-editor
signal scene_ready(scene_kind: StringName)
signal upgrade_choice_requested(level_score: int, on_done: Callable)
signal campaign_cutscene_requested(cutscene_id: StringName, on_done: Callable)
signal campaign_level_started(index: int, map_path: String)
signal campaign_finished(total_score: int)
```

`scene_ready` — эмитится только в `godmode_controller._ready()` финальной строкой, `scene_kind = &"godmode"`. Future-spec'и могут эмитить из других сцен (`&"map_editor"`, etc.).

### 8. game_speed.cfg additions

В существующую `[meta]` секцию:
```
transition_shake_sec=0.4
transition_distort_sec=0.6
transition_hold_sec=0.15
transition_fade_in_sec=0.6
upgrade_choice_timeout_sec=0.5
cutscene_request_timeout_sec=0.5
```

## Acceptance criteria

- **AC-G1 (data class).** `GameData` в `scripts/core/maps/game_data.gd` — pure data + `validate() -> Array[String]`. `GameSerializer.save(game, path) -> bool` и `GameSerializer.load(path) -> GameData`. JSON через `JSON.stringify(d, "\t")`.
- **AC-G2 (editor scene).** `scenes/dev/game_editor.tscn` запускается из главного меню кнопкой **Game Editor**. На пустой игре — одна пустая level-row, имя «untitled». Add Level / Remove / ↑ / ↓ работают и обновляют autosave. Save/Load через FileDialog в `data/games/` с фильтром `*.game.json`.
- **AC-G3 (autoload).** `ActiveGame` зарегистрирован в `project.godot` после `ActiveLevel`. `load_game(path)` грузит GameData, ставит `current_index=0`, дёргает `ActiveLevel.queue(map_path)`. `advance()` инкрементит индекс и queue'ит следующую карту; на последнем уровне — no-op (CampaignController сам решит).
- **AC-G4 (campaign hook).** `CampaignController` автоматически перехватывает `level_completed`, если `ActiveGame.has_active_game()`. Без активной игры — поведение текущей godmode (просто `level_completed` повисает) не меняется.
- **AC-G5 (upgrade stub).** Без реального upgrade screen: после `level_completed` показывается toast `"Upgrade placeholder"`, ждётся `upgrade_screen_min_display` сек, потом transition. Когда Alexey смержит реальную upgrade-спеку — stub удаляется по флагу/одной строке кода в CampaignController, остальной flow не трогается.
- **AC-G6 (transition overlay).** `level_transition.tscn` проигрывает 4-фазный переход с конфигурируемыми длительностями из `[meta]`. Visual: shake → distort+fade-out → hold → fade-in (после change_scene). При F5-reload `game_speed.cfg` следующий transition подхватывает новые длительности. Никакой transition в обычной godmode (без active game).
- **AC-G7 (last level → win).** Когда `ActiveGame.is_last_level()` и `level_completed` — после upgrade и transition летим в `campaign_end.tscn`. Кнопка **Main Menu** возвращает в меню, `ActiveGame.clear()` в `main_menu._ready()`.
- **AC-G8 (intro hook).** Если первый уровень `is_intro=true` или `cutscene_id != &""` — после `scene_ready` дёргается `campaign_cutscene_requested(cutscene_id, callback)`. В 035 нет реального слушателя → timeout 0.5 сек → no-op (уровень играется как обычно). Будущая катсцена-спека подключает слушателя без изменений CampaignController.
- **AC-G9 (sample game).** `data/games/sample.game.json` существует. Load Game → выбор → бой. После победы на 1-м уровне — transition → 2-й уровень. После победы на 2-м — campaign_end. Без падений.
- **AC-G10 (main menu UI).** Главное меню имеет 9 кнопок в порядке: Start Run, Continue (disabled), Godmode, Map Editor, **Game Editor**, **Load Game**, Load Custom Level, Settings, Credits, Quit. Стилизация — `UiTheme.apply_button_styling`. Хоткей не добавляется (полно их уже).
- **AC-G11 (autosave).** Game Editor пишет `data/games/__autosave_game__.json` debounced 1.5 сек после любого изменения. Восстановление — через ConfirmModal на старте редактора если mtime ≤ 24h.
- **AC-G12 (validation).** Save без уровней / с несуществующим map_path / >1 is_intro — отказ записи + toast. Load с битым JSON — отказ + toast, редактор остаётся в текущем состоянии.

## Out of scope (явно)

- **Реальный upgrade screen.** Только хук + stub. Отдельная спека (Alexey).
- **Реальная катсцена.** Только хук. Отдельная спека.
- **Player progress carry-over между уровнями** (HP / spells / modifiers переносятся в следующий уровень). Это — задача upgrade-спеки и `PlayerProgress` autoload'а, который она введёт. В 035 каждый уровень стартует со свежим player'ом из `LevelData.spawners`, `RunScore.total` накапливается через волны (он уже это делает).
- **Drag-and-drop reorder** уровней в редакторе. Только ↑/↓ кнопки.
- **Branching campaigns** (выбор пути после уровня). Только линейный.
- **Boss wave flag** в `LevelData`. Семантика «последняя волна = босс» текущая, переиспользуем.
- **Cutscene playback engine.** Не существует, не вводим. Хук `campaign_cutscene_requested` есть.
- **Per-level рандом-модификаторы / wave-overrides.** Игра — это голый список путей к картам. Карта самодостаточна.
- **Save/resume посередине игры.** Ушёл в меню — кампания сброшена. Continue остаётся disabled.
- **Audio для transition.** SFX-точка обозначена (`AudioDirector.play_event(&"level_transition")`), но привязка звука — polish, не часть этой спеки.
- **Camera shake в первой фазе если камера сцены не поддерживает.** `EventBus.camera_shake_requested` уже есть; godmode_camera умеет реагировать. Если editor-камера или campaign_end не подписаны — игнор.
- **Localization** имени игры / display_name уровней. Plain UTF-8 строки, без `tr()`.
- **Многоязычные катсцены / тексты внутри 035.** Это narrative-владение Никиты и катсцена-спеки.

## Зависимости

- **Upstream:** 020-map-editor (`LevelData`, `ActiveLevel`, `data/maps/`), 024-wave-editor (`level_completed` signal), 010-crt-postfx (distort шейдер reuse), 009-ui-kit (`UiTheme`, `ConfirmModal`, `ToastLayer`, FileDialog паттерн), `RunScore` autoload.
- **Downstream:**
  - **Upgrade screen spec** (Alexey, отдельная) — заменит stub. API через `upgrade_choice_requested(score, on_done)`.
  - **Cutscene spec** (Alexey/Никита, отдельная) — подпишется на `campaign_cutscene_requested`.
  - **Player progress spec** (Alexey, отдельная) — карry-over состояния игрока между уровнями.
  - **PolishVFX spec** (Andrey, polish-фаза) — sfx для transition, тюнинг distort-волны.
- **Coordination:** Alexey — review этой спеки до начала impl, чтобы хуки `upgrade_choice_requested` / `campaign_cutscene_requested` были «удобные» для его будущих сцен. Stasyan — после мержа собирает реальные `data/games/` по сюжету.

## История правок

- 2026-05-03 v1 — first draft (Andrey req).
