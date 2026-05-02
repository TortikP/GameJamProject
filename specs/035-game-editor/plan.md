# 035-game-editor — plan

**Status:** Draft, парный со spec'ой v1.

## Архитектура одним абзацем

Лёгкий слой поверх 020/024. Никаких изменений ядра боя. Новый pure-data класс `GameData`, новый autoload `ActiveGame` (расширяет паттерн `ActiveLevel`), новый autoload `CampaignController` (тонкий слушатель `level_completed`). Editor-сцена `game_editor.tscn` — UI поверх `LevelData`-файлов из `data/maps/`. Transition overlay — отдельная сцена `level_transition.tscn` с reuse'ом CRT distort шейдера. Stub-ответчик upgrade screen — третий autoload, удаляется одной строкой когда Alexey смержит свою upgrade-спеку.

## Файлы

### Новые

| Путь | Назначение |
|---|---|
| `scripts/core/maps/game_data.gd` | Pure-data `class_name GameData`. Поля + `validate()`. Без зависимостей от Node. |
| `scripts/core/maps/game_serializer.gd` | `class_name GameSerializer`. Static `save(game, path) -> bool` / `load(path) -> GameData`. JSON I/O, читает `FileAccess`. |
| `scripts/infrastructure/active_game.gd` | Autoload. Хранит `_game: GameData` + `current_index`. API: `load_game / current_level / advance / is_last_level / has_active_game / clear`. |
| `scripts/runtime/campaign_controller.gd` | Autoload. `_ready` подписывается на `level_completed` и `scene_ready`. Логика см. spec §4. |
| `scripts/runtime/_dummy_upgrade_stub.gd` | Autoload (временный). Слушает `upgrade_choice_requested`, ждёт `[ui]/upgrade_screen_min_display` сек, отвечает callback'ом + toast. |
| `scenes/dev/game_editor.tscn` | UI редактора. Дерево из spec §2. |
| `scripts/presentation/dev/game_editor_controller.gd` | Контроллер редактора. State, autosave, save/load, F5 не нужен. |
| `scripts/presentation/dev/game_editor_level_row.gd` | Отдельная row-сцена / scene-script для каждого уровня в списке. |
| `scenes/dev/game_editor_level_row.tscn` | Сцена строки списка. |
| `scenes/meta/level_transition.tscn` | CanvasLayer + ColorRect + AnimationPlayer. Шейдер — reuse `010-crt-postfx`'s distort. |
| `scripts/presentation/meta/level_transition.gd` | Логика 4-фазного перехода. `play_out() -> Signal`, `play_in() -> Signal`. |
| `scenes/meta/campaign_end.tscn` | Минимальный экран. Reuse `UiTheme` styles. |
| `scripts/presentation/meta/campaign_end.gd` | Кнопка Main Menu → `EventBus.main_menu_entered.emit()` + change_scene. |
| `data/games/sample.game.json` | Sample игра из 2 уровней. |
| `data/games/_schema.md` | Схема для дизайнеров (Стасян). 1:1 с GameData. |

### Изменяемые (additive)

| Путь | Что меняется |
|---|---|
| `project.godot` | Добавить 3 autoload'а: `ActiveGame`, `CampaignController`, `_DummyUpgradeStub`. Порядок после `ActiveLevel`. |
| `scripts/infrastructure/event_bus.gd` | +5 сигналов из spec §7. |
| `scenes/main_menu.tscn` | +2 кнопки в VBox: `GameEditorButton`, `LoadGameButton`. +`LoadGameFileDialog`. Порядок: после MapEditorButton, перед LoadCustomLevelButton. |
| `scripts/presentation/main_menu.gd` | +2 обработчика, +`ActiveGame.clear()` в `_ready`. Apply theme — добавить новые кнопки в loop. |
| `scripts/presentation/godmode/godmode_controller.gd` | Финальная строка `_ready()`: `EventBus.scene_ready.emit(&"godmode")`. Никаких других правок. |
| `config/game_speed.cfg` | +6 ключей в `[meta]` секцию из spec §8. |

### Не трогаем

- `scripts/core/` (кроме нового `maps/game_data.gd`, `maps/game_serializer.gd`).
- `LevelData`, `LevelLoader`, `LevelSerializer`.
- `WaveController`, любые spell/skill/ability модули.
- 020 map editor — никаких UI-правок.

## Контракты

### `EventBus.scene_ready(scene_kind: StringName)`
Эмитится последней строкой `_ready()` сцены, после её собственной инициализации. В 035 — только godmode. Future-spec'и могут добавить `&"map_editor"`, `&"campaign_end"` etc.

### `EventBus.upgrade_choice_requested(level_score: int, on_done: Callable)`
Слушатель **обязан** позвать `on_done.call()` после своей работы (показал экран — закрыл — позвал). CampaignController ждёт callback или timeout (0.5 сек) и идёт дальше. Stub отвечает через `upgrade_screen_min_display` сек.

### `EventBus.campaign_cutscene_requested(cutscene_id: StringName, on_done: Callable)`
Аналогично. Если `cutscene_id == &""` — CampaignController сам не эмитит, просто сразу пропускает.

### `EventBus.campaign_level_started(index: int, map_path: String)` / `campaign_finished(total_score: int)`
Read-only обзорные сигналы для HUD / score / analytics. Ничего не блокируют.

### `ActiveGame.advance()` инвариант
Всегда вызывается **между** двумя сцен-changesами: текущий level закончен, следующий ещё не загружен. После `advance()` ровно один из `ActiveLevel.has_queued()` или `is_last_level()` — true (зависит от позиции).

## Sequence на победу не-последнего уровня

```
WaveController         CampaignController     UpgradeStub        TransitionOverlay      ActiveGame
     |                        |                    |                     |                  |
     | level_completed        |                    |                     |                  |
     |----------------------->|                    |                     |                  |
     |                        | upgrade_choice_req |                     |                  |
     |                        |------------------->|                     |                  |
     |                        |                    | wait min_display    |                  |
     |                        |                    |                     |                  |
     |                        |        on_done()   |                     |                  |
     |                        |<-------------------|                     |                  |
     |                        | play_out()         |                     |                  |
     |                        |------------------------------------------>                  |
     |                        |    (shake/distort/fade)                  |                  |
     |                        |<-----------------------------------------|                  |
     |                        | advance()                                                   |
     |                        |------------------------------------------------------------>|
     |                        |   ActiveLevel.queue(next_map_path) внутри advance()         |
     |                        | change_scene godmode                                        |
     |                        |                                                             |
     |                        | (новая сцена, _ready, scene_ready emit)                     |
     |                        | play_in() в новой сцене                                     |
```

## Sequence на победу последнего уровня

Только разница: после play_out() — `change_scene_to_file("res://scenes/meta/campaign_end.tscn")` вместо advance+godmode. `campaign_finished` эмитится перед change_scene.

## Sequence на старте intro-уровня

```
godmode loaded → _ready done → scene_ready(&"godmode") emit
                                       |
                                       v
                              CampaignController
                                       |
                  (active_game and current.is_intro and cutscene_id != &"")
                                       |
                                       v
                          campaign_cutscene_requested
                                       |
                          (нет слушателя в 035 → timeout 0.5s → no-op)
                                       |
                                       v
                           уровень играется как обычно
```

В 035 эта ветка просто молча пропускается. Когда Alexey/Никита запилят катсцену-плеер — он зацепится за `campaign_cutscene_requested`, lock'нет ввод через `EventBus.input_locked.emit(true)` (уже существующий сигнал), отыграет диалог/анимацию, дёрнет callback, и WaveController + игрок начнут как обычно.

## Технические решения и rationale

| Решение | Альтернатива | Почему так |
|---|---|---|
| `CampaignController` как autoload, не сцена-узел | Узел в godmode-сцене | Autoload переживает change_scene; узлу пришлось бы переинициализироваться каждый раз и коннектить сигналы заново. |
| Stub как отдельный autoload (`_DummyUpgradeStub`) | Inline в CampaignController | Легче удалить (одна строка в `project.godot`) когда настоящая сцена готова. CampaignController не должен знать про существование stub'а. |
| Расширение `.game.json`, не `.json` | Один формат для всех файлов | FileDialog-фильтрация без чтения содержимого; визуально ясно что это игра а не карта. |
| Reuse CRT distort шейдера для transition | Свой новый шейдер | 010-crt-postfx уже есть, тюнинг через `wave_amplitude` parameter. -1 файл шейдера. |
| Линейный список + ↑/↓, без drag-and-drop | DnD reorder | Mini-spec, экономим 2-3 часа имплементации DnD'а. Дизайнер с десятью уровнями переживёт. |
| Cutscene-хук как сигнал с callback | Прямой await catscene_player.play() | CampaignController не знает существует ли вообще катсцена-движок. Сигнал + timeout = безопасный fallback. Та же схема, что для upgrade. |
| Игра = только `Array[map_path]` без своих per-level overrides | Per-level enemy lists / loot tables в GameData | Карта самодостаточна (waves, spawners уже в LevelData). Двойная иерархия = двойной редактор. Полностью out of scope. |
| `is_intro` как флаг на уровне, а не отдельное поле в GameData | `intro_cutscene_id: StringName` в GameData root | Гибко: если когда-нибудь захотим катсцены между уровнями — поле `cutscene_id` на каждом уровне уже есть. `is_intro` — семантика «это самый первый старт игры» (для будущей логики типа сброса прогресса). |

## Риски

1. **Player progress carry-over.** Если Alexey не успеет с PlayerProgress autoload'ом до релиза — каждый уровень начинается с дефолтного игрока. Это **не блокер** для 035 (мы про это явно говорим в out_of_scope), но это блокер для «полноценной кампании». Плейтест с stub'ом покажет как «3 одинаковых уровня». Митигация: 035 мержится сам по себе, кампания как «фича включена» появляется после Alexey'я.
2. **Transition выглядит дёшево.** Без качественного звука и без качественного distort'а 4-фазный переход смотрится как «экран потряс и поморгал». Митигация: тюнинг ампли­туд через `game_speed.cfg`, polish-фаза. Если совсем плохо — Andrey добавляет audio cue + усиливает distort параметры.
3. **`scene_ready` сигнал может пересечься с другими `_ready` инициализациями.** Если будущая фича подпишется на `scene_ready` и попробует менять состояние мира, может прилететь до того как все системы готовы. Митигация: сигнал — read-only нотификация. Документировать в comment'е event_bus.gd.
4. **Stub upgrade добавляет 1 score** — если Alexey задержит замену, плейтесты будут показывать «+1 за уровень» что бессмысленно. Митигация: переменная `STUB_SCORE_BONUS = 0` в _dummy_upgrade_stub.gd; легко выкрутить если раздражает.

## Что НЕ делается в этой ветке

- Никакого PlayerProgress / carry-over.
- Никакого реального upgrade UI.
- Никакого реального cutscene playback'а.
- Никакого audio для transition (только точка-вызов в комменте).
- Никаких изменений в map editor, wave editor, godmode_controller (кроме одной строки emit'а).
