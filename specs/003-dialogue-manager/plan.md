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

### Dev preview (`scripts/presentation/` + `scenes/dev/`)
- `scripts/presentation/dialogue_preview.gd`
- `scenes/dev/dialogue_preview.tscn` (новая папка `scenes/dev/` — конвенция для всех debug-сцен команды).

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
func play(id: StringName, force: bool = false) -> bool
func request(event: StringName, context: Dictionary = {}, force: bool = false) -> StringName
func is_playing() -> bool
func clear_queue() -> void
```

Семантика `force`:
- `force=false` (default): если `is_playing()`, возврат сразу (`false` / `&""`) + warn в лог. Используется для ambient-триггеров — не накапливаем стопку диалогов.
- `force=true`: enqueue. Используется для scripted-моментов (boss intro, end-of-run, ачивка которую нельзя пропустить).

Для `request(..., force=true)` селектор резолвит id **в момент вызова**, и в очередь кладётся уже resolved id. Re-evaluation на dequeue не делаем — состояние тогда непредсказуемо.

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
  "once_per_session": false,
  "next": null,
  "choices": []
}
```

Обязательные поля: `id`, `speaker`, `text`. Остальные — дефолтятся в `from_dict`. `id` уникален по всей базе, дубликат → warn + последний выигрывает.

`once_per_session` означает «один раз за процесс игры», а не «один раз за save» (save-системы у нас нет). Имя такое, чтобы не вводить контентщика в заблуждение.

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
Максимум 3 на реплику. `next: null` (или отсутствие поля) валидно — означает «закончить сцену сразу после этого выбора», панель закроется. Это для естественного «Goodbye»-выбора, который не требует follow-up реплики.

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
Input: event, context (run_count, optional flags), played_run, played_session
1. candidates = [line for line in DB.lines if event in line.tags]
2. candidates = [c for c in candidates
                  if c.conditions.min_run <= context.run_count <= c.conditions.max_run
                  and all(f in context.flags for f in c.conditions.flags_required)
                  and not any(f in context.flags for f in c.conditions.flags_forbidden)]
3. eligible = [c for c in candidates
                 if not (c.once_per_run    and c.id in played_run)
                 and not (c.once_per_session and c.id in played_session)]
4. if eligible empty:
       repeatable = [c for c in candidates if not c.once_per_session and not c.once_per_run]
       if repeatable: eligible = repeatable
       else: return null
5. max_priority = max(c.priority for c in eligible)
6. top = [c for c in eligible if c.priority == max_priority]
7. return random choice from top
```

## Жизненный цикл сцены

```
DialogueManager.play(id, force=false)
  ├─ if not DB.has_line(id): warn, return false
  ├─ if is_playing():
  │    ├─ if force: enqueue(id), return true
  │    └─ else: warn "drop", return false
  ├─ _scene_start_id = id
  ├─ _scene_visited = {}                  # cycle detection per-scene
  ├─ _show_line(line)
  │    ├─ if line.id in _scene_visited: warn "cycle", goto end_scene
  │    ├─ _scene_visited[line.id] = true
  │    ├─ _played_per_run[line.id] = true   if line.once_per_run
  │    ├─ _played_per_session[line.id] = true if line.once_per_session
  │    ├─ EventBus.dialogue_started.emit(line.id)
  │    ├─ AudioDirector.play_dialogue_audio(line.id, resolved_layer)
  │    ├─ panel.show_line(line, speaker)
  │    └─ await panel.line_ended (signal)
  ├─ if line.choices not empty:
  │    ├─ idx = await panel.choice_picked
  │    ├─ next_id = line.choices[idx].next   # may be null → end
  ├─ elif line.next: next_id = line.next
  ├─ else: next_id = null
  ├─ if next_id != null:
  │    ├─ next_line = DB.get_line(next_id)
  │    ├─ if next_line == null: warn "missing next", goto end_scene
  │    └─ goto _show_line(next_line)        # SAME _scene_start_id, SAME _scene_visited
  └─ end_scene:
       ├─ EventBus.dialogue_finished.emit(_scene_start_id)
       ├─ panel.hide()
       ├─ _scene_start_id = null
       └─ if _queue not empty: _show_line(DB.get_line(queue.pop_front()))
```

**Scene atomicity** обеспечивается тем, что (а) `is_playing()` остаётся true всю сцену, не только текущую реплику; (б) `_queue.pop_front()` происходит только в `end_scene`, после `dialogue_finished.emit`. Никакой внешний триггер не может проскочить между choice и его follow-up.

**Cycle detection.** `_scene_visited` чистится в начале каждой сцены (после pop из очереди). В пределах сцены повторный заход на тот же id → warn + end_scene.

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
- **Зацикленные `next`.** Автор может случайно сделать A→B→A. Защита: `_scene_visited` set, повторный заход → warn + end_scene. Игрок видит не более N реплик за сцену, где N = размер цепи.
- **Choice ведёт на несуществующий id.** В lifecycle: `if next_line == null: warn + end_scene`. На загрузке — pre-валидация: для каждого `next` (line + choice) проверяем `has_line`, warn если ссылка битая. Дропать ссылку или нет — не дропаем, content authoring должен видеть warn и фиксить. Runtime устойчив всё равно.
- **Force-флаг злоупотребление.** Если все триггеры идут с `force=true`, скапливается стопка диалогов после боя. Соглашение: `force=true` только для критичных сюжетных моментов (boss intro, end-of-run, ачивка). Ambient — `force=false`. Это контентное правило, не технический guard.
- **Queue зависает.** Если `play` зовётся пока `is_playing()`, тестируется руками: 2 быстрых клика на «Test dialogue» с `force=false` — второй дропается с warn. С `force=true` (вызывается из preview-сцены ради проверки) — оба отыгрывают последовательно.

## Что специально НЕ делаем

- **Класс `class_name DialogueLine`.** RefCounted, обращаемся через preload. Причина — `class_name` глобальный, мы видели коллизию `Logger`. Лучше превентивно избежать.
- **`AnimationPlayer` для текста.** RichTextLabel + `visible_characters` + Tween достаточно. Tween проще отлаживать чем AnimationPlayer.
- **Перегрузка `play(id, speaker, text, ...)`.** Только id + force. Если нужна динамическая реплика — создаётся в `data/dialogues/` или появляется отдельный API позже.
- **Persistent save played-history.** Когда (если) будет save-система — она будет читать `DialogueManager._played_per_session` и восстанавливать. Это +5 строк, не делаем заранее.

## Что добавляется в `config/game_speed.cfg`

Ничего. `[ui]` секция уже содержит обе нужные настройки (`dialogue_typewriter_chars_per_sec`, `dialogue_auto_advance_after_sec`), они проставлены в bootstrap.
