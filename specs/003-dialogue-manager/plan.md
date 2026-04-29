# 003-dialogue-manager — plan

## Подход

Engine отделён от View. Engine ничего не знает о панели, RichTextLabel, кнопках. View подписывается на API Engine и отрисовывает. Контент в JSON, никакого hardcode в скриптах.

Селектор реплик — Hades-lite: `tags ∩ event` → `conditions` → `played-set` → `priority desc` → невиденная.

## Файлы, которые добавляются в репу этой фичей

### Engine (`scripts/core/dialogue/`)
- `dialogue_line.gd` — RefCounted data-class. Static `from_dict(d: Dictionary) -> DialogueLine` (валидация + дефолты).
- `dialogue_database.gd` — Node-autoload `DialogueDB`. Сканирует `data/dialogues/`, парсит, держит в памяти словари `lines: Dictionary[StringName, DialogueLine]` и `speakers: Dictionary[StringName, Dictionary]`. Селектор `find_by_event(event, context, played) -> DialogueLine` (статическая логика на данных DB).
- `dialogue_manager.gd` — Node-autoload `DialogueManager`. Очередь, played-set, инстанцирование панели, проигрывание, choice handling, EventBus emit'ы.

### View (`scripts/presentation/` + `scenes/ui/`)
- `scripts/presentation/dialogue_panel.gd`
- `scenes/ui/dialogue_panel.tscn`

### Dev preview (`scripts/presentation/` + `scenes/meta/`)
- `scripts/presentation/dialogue_preview.gd`
- `scenes/meta/dialogue_preview.tscn`

### Content seed (`data/dialogues/`)
- `_speakers.json`
- `respawn_first.json`
- `respawn_choice.json`
- `boss_intro.json`

### Конфиг
- `project.godot` — добавить `DialogueDB` и `DialogueManager` в `[autoload]` в правильном порядке.

### Smoke
- `scripts/main.gd` + `scenes/main.tscn` — временная кнопка «Test dialogue». Удаляется в `005-roguelike-loop` (комментарий в коде с TODO-ссылкой на фичу).

## Контракты, которые этой фичей фиксируются на всю команду

### EventBus (используем существующие)
- `dialogue_started(dialogue_id: StringName)` — emit при старте каждой реплики (не сцены).
- `dialogue_finished(dialogue_id: StringName)` — emit ОДИН раз, при закрытии панели. Аргумент — id **первой** реплики сцены (стартовая точка request/play).

### DialogueManager API
```gdscript
func play(id: StringName) -> bool
func request(event: StringName, context: Dictionary = {}) -> StringName
func is_playing() -> bool
func clear_queue() -> void
```

### DialogueDB API
```gdscript
func get_line(id: StringName) -> DialogueLine    # null если нет
func has_line(id: StringName) -> bool
func get_speaker(id: StringName) -> Dictionary   # пустой если нет
func find_by_event(event: StringName, context: Dictionary, played: Dictionary) -> DialogueLine  # null если ничего не подошло
```

### JSON-схема реплики
```json
{
  "id": "respawn_first",
  "speaker": "narrator",
  "portrait": null,
  "image": null,
  "text": "Again? Already?",
  "text_fx": null,
  "audio_layer": null,
  "audio_clip": null,
  "tags": ["respawn"],
  "priority": 10,
  "conditions": {
    "min_run": 0,
    "max_run": 999,
    "flags_required": [],
    "flags_forbidden": []
  },
  "once_per_run": false,
  "once_per_save": false,
  "next": null,
  "choices": []
}
```

Обязательные поля: `id`, `speaker`, `text`. Остальные — дефолтятся в `from_dict`. `id` уникален по всей базе, дубликат → warn + последний выигрывает.

### JSON-схема `_speakers.json`
```json
{
  "narrator": {
    "display_name": "Narrator",
    "default_portrait": "res://assets/portraits/narrator_neutral.png",
    "default_audio_layer": "sfx"
  },
  "rival": { "...": "..." }
}
```

Если portrait-файл не существует — placeholder (серый квадрат с именем). Не падаем.

### Audio layers
`sfx | ai_voice | human` — соответствует `jam-concept-pitch.md` §«Звук — эскалация подлинности». DialogueManager резолвит layer так: `line.audio_layer ?? speaker.default_audio_layer ?? "sfx"`.

### Choice schema
```json
{ "label": "Уйти молча", "next": "respawn_silent_response" }
```
Максимум 3 на реплику. `next` обязателен (нельзя сделать «выбор → конец»). Чтобы закрыть на choice — указываем next на одно-репличную сцену.

## Точки интеграции

| Из | В | Как |
|---|---|---|
| `EventBus.run_started` | `DialogueManager._on_run_started` | Очистка `_played_per_run`. |
| `DialogueManager.play()` | `AudioDirector.play_dialogue_audio(id, layer)` | На старте каждой реплики. |
| `DialogueManager.play()` | `EventBus.dialogue_started.emit(id)` | На старте каждой реплики. |
| `DialogueManager` (после последней) | `EventBus.dialogue_finished.emit(start_id)` | Один раз, при закрытии. |
| `DialoguePanel` | `GameSpeed.get_value("ui", "dialogue_typewriter_chars_per_sec")` | Скорость typewriter. |
| `DialoguePanel` | `GameSpeed.get_value("ui", "dialogue_auto_advance_after_sec")` | Auto-advance таймер. |

## Алгоритм `find_by_event`

```
Input: event, context (run_count, optional flags), played (dict id→true)
1. candidates = [line for line in DB.lines if event in line.tags]
2. candidates = [c for c in candidates
                  if c.conditions.min_run <= context.run_count <= c.conditions.max_run
                  and all(f in context.flags for f in c.conditions.flags_required)
                  and not any(f in context.flags for f in c.conditions.flags_forbidden)]
3. eligible = [c for c in candidates if c.id not in played]
4. if eligible empty:
       repeatable = [c for c in candidates if not c.once_per_save and not c.once_per_run]
       if repeatable: eligible = repeatable
       else: return null
5. max_priority = max(c.priority for c in eligible)
6. top = [c for c in eligible if c.priority == max_priority]
7. return random choice from top
```

## Жизненный цикл сцены

```
DialogueManager.play(id)
  ├─ if is_playing: enqueue(id), return true
  ├─ _scene_start_id = id
  ├─ _show_line(line)
  │    ├─ EventBus.dialogue_started.emit(id)
  │    ├─ AudioDirector.play_dialogue_audio(id, resolved_layer)
  │    ├─ panel.show_line(line, speaker)
  │    └─ await panel.line_ended (signal)
  ├─ if line.choices: await panel.choice_picked → next_id from chosen
  ├─ elif line.next: next_id = line.next
  ├─ else: end_scene
  │    ├─ EventBus.dialogue_finished.emit(_scene_start_id)
  │    ├─ panel.hide()
  │    └─ pop next from queue, recurse
  └─ if next_id: _show_line(DB.get_line(next_id)), loop
```

## Структура `scenes/ui/dialogue_panel.tscn`

```
DialoguePanel (Control, full-rect)
└─ Panel (anchored bottom, height 280px)
    └─ MarginContainer
        └─ HBoxContainer
            ├─ TextureRect#Portrait (160×160)
            ├─ VBoxContainer (expand)
            │   ├─ Label#Name
            │   ├─ RichTextLabel#Text (bbcode, scroll_active=false, fit_content=true)
            │   └─ HBoxContainer#Choices
            └─ TextureRect#Image (200×200, hidden by default)
```

## Риски и mitigation

- **Autoload порядок.** `DialogueManager` зависит от `DialogueDB`. Регистрировать `DialogueDB` строго перед `DialogueManager`. Проверка: `DialogueManager._ready()` падает с `error()` если `DialogueDB` пустой/null.
- **Битый JSON от контентщика.** `JSON.parse_string` ничего не бросает в 4.6 — проверяем результат на `null` + есть ли `error_string`. Битый файл скипается с `GameLogger.warn("DialogueDB", "skip <path>: <reason>")`. Игра жива.
- **Дубликат id.** Логируется warn, последний загруженный побеждает. Никита знает что id должны быть уникальны.
- **Пустая `data/dialogues/`.** На старте `loaded 0 dialogues`. Игра живёт. UI не открывает панель. `request` всегда возвращает `&""`.
- **Speaker без портрета.** Placeholder. Файл-проверка `FileAccess.file_exists`, fallback — серый Texture2D (создаётся в коде на лету один раз).
- **`text_fx`/`image`/`vfx_overlay` в JSON будут писать раньше чем код готов.** Это ОК. Engine их грузит, View игнорирует с одноразовым warn в лог per-feature. Никита знает что они «зарезервированы, ещё не работают».
- **Очередь зависает.** Если `play` зовётся пока `is_playing()`, тестируется руками: 2 быстрых клика на «Test dialogue» — оба должны отыграть последовательно.
- **Choice без next.** Валидация на загрузке: choice без поля `next` → warn + дропаем choice (не реплику целиком).

## Что специально НЕ делаем

- **Класс `class_name DialogueLine`.** RefCounted, обращаемся через preload. Причина — `class_name` глобальный, мы видели коллизию `Logger`. Лучше превентивно избежать.
- **`AnimationPlayer` для текста.** RichTextLabel + `visible_characters` + Tween достаточно. Tween проще отлаживать чем AnimationPlayer.
- **Перегрузка `play(id, speaker, text, ...)`.** Только id. Если нужна динамическая реплика — создаётся в `data/dialogues/` или появляется отдельный API позже.
- **Persistent save played-history.** Когда (если) будет save-система — она будет читать `DialogueManager._played_per_save` и восстанавливать. Это +5 строк, не делаем заранее.

## Что добавляется в `config/game_speed.cfg`

Ничего. `[ui]` секция уже содержит обе нужные настройки (`dialogue_typewriter_chars_per_sec`, `dialogue_auto_advance_after_sec`), они проставлены в bootstrap.
