# 052 — Plan

## Files touched

- `scripts/presentation/dialogue_panel.gd` — единственный затронутый файл. Добавляем константы, поле, EventBus listener, новую ветку в `_resolve_portrait`.

Никаких новых файлов / scenes / autoloads / data. Никаких изменений в `MoodTracker` / `EventBus` / `_speakers.json`.

## Implementation sketch

В голове файла, после `enum State`:

```gdscript
const PLAYER_SPEAKER: StringName = &"heroine"

# Mood → portrait file. Тематический маппинг (см. spec §"Маппинг").
# neutral / chimera отсутствуют намеренно — fall through к default_portrait.
const MOOD_PORTRAIT: Dictionary = {
    &"tranquility": "res://assets/portraits/aspect_forest.png",
    &"burnout":     "res://assets/portraits/aspect_fire.png",
    &"ascended":    "res://assets/portraits/aspect_heaven.png",
}

var _dominant_mood: StringName = &"neutral"
```

В `_ready` — после существующих connect'ов:

```gdscript
EventBus.player_mood_changed.connect(_on_player_mood_changed)
# Sync с MoodTracker'ом, если он уже эмитнул до нашего connect'а
# (порядок autoload'ов в project.godot зависит от .gd позиций).
var mt: Node = get_node_or_null("/root/MoodTracker")
if mt != null and mt.has_method("get_dominant"):
    _dominant_mood = mt.get_dominant()
```

Новый handler:

```gdscript
func _on_player_mood_changed(_counts: Dictionary, dominant: StringName) -> void:
    _dominant_mood = dominant
```

`_resolve_portrait` переписать в priority-chain виде:

```gdscript
func _resolve_portrait(line: Object, speaker_data: Dictionary) -> Texture2D:
    # 1. Explicit per-line override wins.
    if line.portrait != "":
        var line_tex: Texture2D = _try_load_texture(line.portrait)
        if line_tex != null:
            return line_tex
    # 2. Mood-driven heroine portrait (spec 052).
    if line.speaker == PLAYER_SPEAKER:
        var mood_path: String = MOOD_PORTRAIT.get(_dominant_mood, "")
        if mood_path != "":
            var mood_tex: Texture2D = _try_load_texture(mood_path)
            if mood_tex != null:
                return mood_tex
    # 3. Speaker default.
    var default_path: String = speaker_data.get("default_portrait", "")
    if default_path != "":
        var def_tex: Texture2D = _try_load_texture(default_path)
        if def_tex != null:
            return def_tex
    # 4. Placeholder.
    return _make_placeholder(str(line.speaker))
```

`line.speaker` — `StringName` (см. `dialogue_line.gd:12`), `PLAYER_SPEAKER` тоже `StringName` — сравниваем напрямую, без `String(...)` обёртки.

## Why dialogue_panel.gd, not somewhere else

- `MoodTracker` в `scripts/core/narrative/` — core не должен знать про текстуры (CLAUDE.md hard rule 1).
- `UiTheme` — общий стиль / цвета / шрифты. Mapping mood→portrait — узкая presentation-логика на одного consumer'а; не оправдано.
- `dialogue_panel.gd` уже владеет резолвом портрета (`_resolve_portrait`, `_make_placeholder`). Mood-step встаёт ровно туда же, локально.

## Risks / sentinels

- **MoodTracker autoload отсутствует** (например, в test-сцене без `Main`). EventBus.player_mood_changed остаётся декларированным сигналом — connect не падает. `_dominant_mood = &"neutral"` (initial) → шаг 2 для heroine не находит маппинг (`neutral` не в `MOOD_PORTRAIT`) → fall through. Покрыто AC-D1.
- **Mood-файл физически отсутствует.** `_try_load_texture` использует `FileAccess.file_exists` + `load`, на missing возвращает null без warn-spam'а. Шаг 2 пропускается → fall through. Покрыто AC-7.
- **Live-смена mood во время реплики.** Сознательно не обновляем `_portrait.texture` в `_on_player_mood_changed`. Текущая реплика держит свой портрет до конца, следующая берёт новый mood. Проще state-machine, нет flash'а во время typewriter'а. Покрыто AC-D2.
- **Recompute → emit при идентичных counts** (spec 038 "сигнал летит всегда"). Handler — простой ассайн, идемпотентен, лишних эффектов нет.
