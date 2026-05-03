# 045-intro-cutscene — plan

## Файлы

| Файл | Действие |
|---|---|
| `data/maps/office_intro.json` | new — карта office, ~5×5, без волн, player spawn на стуле |
| `data/games/story_campaign.game.json` | edit — prepend office_intro entry, снять is_intro со story_map_01 |
| `data/cutscenes/intro_office.json` | new — конфиг 2-кадровой cutscene-art последовательности |
| `data/dialogues/intro_office_monologue.json` | new — sample 2–3 реплики (placeholder под Никиту) |
| `scripts/presentation/meta/cutscene_player.gd` | new — autoload, fullscreen overlay, 2-кадра + scale + fade |
| `scenes/meta/cutscene_player.tscn` | new — оверлей-сцена (CanvasLayer 30, 2× TextureRect, Skip-label) |
| `scripts/runtime/intro_director.gd` | new — autoload, оркестрирует intro-последовательность |
| `scripts/presentation/godmode/godmode_setup.gd` | edit — `HUD.visible = false` если is_intro |
| `scripts/presentation/godmode/godmode_camera.gd` | edit — guard на zoom/pan если is_intro |
| `scripts/presentation/godmode/godmode_input.gd` | edit — early-return для player-actions если is_intro |
| `project.godot` | edit — +autoloads `CutscenePlayer`, `IntroDirector` (после `CampaignController`) |
| `config/game_speed.cfg` | edit — `meta/cutscene_request_timeout_sec=4.0` (было 0.5) |
| `CLAUDE.md` | edit — claim row для 045 |
| `HANDOFF.md` | edit — секция 21 «intro flow» |

`event_bus.gd`, `level_data.gd`, `game_data.gd`, `campaign_controller.gd`, `level_dialogue_director.gd` — **не трогаем.**

## Архитектура intro-flow

```
                                 ┌──────────────────────────┐
   "Начать забег"  click  ─────► │ MainMenu._on_start       │
                                 │  ActiveGame.load_game()  │
                                 │  change_scene(godmode)   │
                                 └────────────┬─────────────┘
                                              ▼
   ┌────────────────────────────────────────────────────────────┐
   │  godmode.tscn loads — office_intro карта                    │
   │  godmode_setup _ready:                                      │
   │    ├── if ActiveGame.current_is_intro(): HUD.visible=false  │
   │    └── godmode_camera/_input gate themselves on is_intro    │
   └─────────────────────────┬───────────────────────────────────┘
                             ▼
   ┌────────────────────────────────────────────────────────────┐
   │  EventBus.scene_ready("godmode") эмитится                   │
   │   ├── CampaignController._on_scene_ready                    │
   │   │     └── current_cutscene_id == "intro_office" → emit    │
   │   │           campaign_cutscene_requested("intro_office",   │
   │   │                                       on_done_cb)       │
   │   └── IntroDirector._on_scene_ready                         │
   │         └── if current_is_intro(): start _run_sequence()    │
   └─────────────────────────┬───────────────────────────────────┘
                             ▼
   ┌────────────────────────────────────────────────────────────┐
   │  CutscenePlayer._on_cutscene_requested("intro_office", cb)  │
   │   ├── load data/cutscenes/intro_office.json                 │
   │   ├── get_tree().paused = true                              │
   │   ├── spawn cutscene_player.tscn в root                     │
   │   ├── animate: scale + cross-fade (≤3s)                     │
   │   ├── skip handler (Space/click/Enter)                      │
   │   ├── on done: free overlay, paused=false                   │
   │   ├── cb.call() — CampaignController._callback_fired=true   │
   │   └── EventBus.cutscene_finished("intro_office") emit       │
   │       (новый сигнал? нет — IntroDirector ждёт другим путём, │
   │        см. ниже)                                            │
   └─────────────────────────┬───────────────────────────────────┘
                             ▼
   ┌────────────────────────────────────────────────────────────┐
   │  IntroDirector._run_sequence (запущен на scene_ready):      │
   │    1. await CutscenePlayer.cutscene_finished signal         │
   │       (внутренний сигнал на autoload, не EventBus)          │
   │    2. DialogueManager.play("intro_office_monologue")        │
   │       await EventBus.dialogue_finished                      │
   │    3. var south := HexGeometry.south_of(player.coord)       │
   │       grid.move_actor(player_id, south)                     │
   │       await EventBus.actor_moved (player, _, south)         │
   │    4. await get_tree().create_timer(0.3).timeout  # дыхание │
   │    5. EventBus.level_completed.emit(0)                      │
   └─────────────────────────┬───────────────────────────────────┘
                             ▼
   ┌────────────────────────────────────────────────────────────┐
   │  CampaignController._on_level_completed → standard flow     │
   │   ├── play transition shader (level_transition.tscn)        │
   │   ├── ActiveGame.advance() → story_map_01                   │
   │   └── change_scene(godmode) — следующий уровень с is_intro=false
   └────────────────────────────────────────────────────────────┘
```

### CutscenePlayer (autoload, fullscreen overlay)

`scripts/presentation/meta/cutscene_player.gd` — `extends Node`, `class_name CutscenePlayer`.

```gdscript
signal cutscene_finished(cutscene_id: StringName)

func _ready() -> void:
    EventBus.campaign_cutscene_requested.connect(_on_cutscene_requested)

func _on_cutscene_requested(id: StringName, on_done: Callable) -> void:
    var data := _load_cutscene(id)  # JSON parse, warn-once on miss
    if data.is_empty():
        on_done.call()
        cutscene_finished.emit(id)
        return
    get_tree().paused = true
    var overlay := preload("res://scenes/meta/cutscene_player.tscn").instantiate()
    overlay.process_mode = Node.PROCESS_MODE_ALWAYS
    get_tree().root.add_child(overlay)
    await _play(overlay, data)
    overlay.queue_free()
    get_tree().paused = false
    on_done.call()
    cutscene_finished.emit(id)

func _play(overlay, data: Dictionary) -> void:
    # Two-frame transition with scale + cross-fade.
    # frames = [{image, hold_sec, scale_from, scale_to, fade_in_sec, fade_out_sec}, ...]
    # tail = {fade_out_sec: 0.6}
    # Skip flag breaks awaits; force-finishes.
    ...
```

### Сцена `cutscene_player.tscn`

```
CutsceneOverlay (CanvasLayer, layer=30, process_mode=ALWAYS)
└── Root (Control, fullscreen, чёрный ColorRect background)
    ├── Frame1 (TextureRect, anchors_preset=15, expand=1, stretch=5)
    ├── Frame2 (TextureRect, anchors_preset=15, expand=1, stretch=5, modulate.a=0)
    └── SkipLabel (Label, anchor top-right, "Space — skip")
```

`Frame1` / `Frame2` — `pivot_offset = size/2` для scale-вокруг-центра.

### IntroDirector (autoload)

`scripts/runtime/intro_director.gd` — `extends Node`.

```gdscript
const PLAYER_ID: StringName = &"player"
const STEP_HEX_OFFSET: Vector2i = Vector2i(0, 1)  # юг для flat-top hex offset coords

func _ready() -> void:
    EventBus.scene_ready.connect(_on_scene_ready)

func _on_scene_ready(scene_kind: StringName) -> void:
    if scene_kind != &"godmode": return
    if not ActiveGame.has_active_game(): return
    if not ActiveGame.current_is_intro(): return
    _run_sequence.call_deferred()

func _run_sequence() -> void:
    # 1. Cutscene art
    await CutscenePlayer.cutscene_finished
    # 2. Dialogue
    DialogueManager.play_dialogue("intro_office_monologue")
    await EventBus.dialogue_finished
    # 3. Step south
    var grid: HexGrid = _find_grid()
    var player: Actor = _find_player(grid)
    if grid != null and player != null:
        var south: Vector2i = player.coord + STEP_HEX_OFFSET
        grid.move_actor(player.id, south)
        await EventBus.actor_moved
    # 4. Breathing room
    await get_tree().create_timer(0.3).timeout
    # 5. Complete
    EventBus.level_completed.emit(0)
```

(Точная сигнатура `move_actor` / получение grid и player — уточню по месту в коде; есть пример в `IntroDirector` или `manekin_spawner.gd`.)

### Locks при is_intro

Все три гейта читают `ActiveGame.current_is_intro()`. Гейты:

- `godmode_setup.gd._ready` (после resolve HUD-нода): `if ActiveGame.current_is_intro(): _hud.visible = false`. Восстанавливать не нужно — следующий уровень это другая загрузка scene'а, всё с нуля.
- `godmode_camera.gd._unhandled_input` — на самом верху функции:
  ```
  if ActiveGame.has_active_game() and ActiveGame.current_is_intro():
      return
  ```
- `godmode_input.gd._unhandled_input` — той же проверкой в начале (после уже существующего `is_alive` гарда).

### JSON-формат `data/cutscenes/intro_office.json`

```json
{
  "id": "intro_office",
  "frames": [
    {
      "image": "res://assets/sprites/cutscenes/cutscene_2.png",
      "hold_sec": 0.4,
      "scale_from": 1.0,
      "scale_to": 0.7,
      "duration": 1.2,
      "fade_in_sec": 0.0,
      "cross_fade_to_next_sec": 0.6
    },
    {
      "image": "res://assets/sprites/cutscenes/cutscene_1.png",
      "hold_sec": 0.4,
      "scale_from": 0.7,
      "scale_to": 0.6,
      "duration": 0.8,
      "fade_out_sec": 0.6
    }
  ]
}
```

(Generic поля задельем под будущие cutscene'ы, но НЕ строим под это редактор — JSON руками.)

### `data/dialogues/intro_office_monologue.json`

Placeholder. Sample структуры — см. существующие диалоги в `data/dialogues/` (Никита заполнит).

## game_speed.cfg — добавляемые ключи

```ini
[meta]
# existing: rewind_effect_duration=0.8, boss_intro_duration=3.0
cutscene_request_timeout_sec=4.0    # было 0.5 (default) — поднимаем под cutscene-art
```

(Было обещано 15.0 в первой редакции спека, но т.к. cutscene-art ≤ 3s,
4.0 достаточно. Skip всегда уменьшит время.)

## Граничные случаи / риски

- **Race-условие scene_ready ↔ campaign_cutscene_requested.**
  CampaignController._on_scene_ready и IntroDirector._on_scene_ready оба
  слушают `scene_ready`. Порядок autoloads важен: `CampaignController`
  раньше → IntroDirector видит `current_is_intro()=true` корректно.
  CutscenePlayer слушает `campaign_cutscene_requested` — этот сигнал
  эмитится из CampaignController.
  IntroDirector зовёт `_run_sequence.call_deferred()` чтобы дать
  CutscenePlayer'у успеть подключиться. Затем `await CutscenePlayer.cutscene_finished`
  ждёт реальный сигнал.
- **CutscenePlayer не услышан → CampaignController таймаут 4s, on_done сам отстреливает.**
  Тогда `cutscene_finished` сигнал НЕ эмитится — IntroDirector подвиснет.
  *Защита:* в IntroDirector делаем `await` с таймаутом через `create_timer` race.
  Альтернатива: CutscenePlayer тоже подписан на `campaign_cutscene_requested`,
  и эмитит `cutscene_finished` всегда (даже если JSON отсутствует) —
  гарантия в коде, не в порядке загрузки.
- **Игрок жмёт ESC → pause-меню → quit-to-menu.**
  При выходе в menu — `ActiveGame.clear()` (см. main_menu.gd `_ready`),
  is_intro reset'ится. При повторном "Start Run" intro проигрывается заново.
- **Скип на cutscene_art ДО того как CutscenePlayer успел инстанцировать overlay.**
  Игнор: `_unhandled_input` в overlay'е, овелрей ещё не в дереве — никаких событий.
  Скип становится возможным с момента, когда overlay добавлен в root (≤16ms после signal'а).

## Ownership / CLAUDE.md

```
| 045-intro-cutscene (CutscenePlayer + IntroDirector autoloads, intro flow) | Andrey |
```
