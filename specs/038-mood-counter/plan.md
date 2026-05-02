# 038-mood-counter — plan

**Spec:** [`spec.md`](./spec.md) · **Status:** Ready for /implement

## Архитектурный обзор

```
slot_bar (UI, 4 слота)
    │  set_slot / RMB picker
    ▼
godmode_controller.sync_player_skills_from_slots()
    │  player.set_skills(skills)        ← уже есть
    │  MoodTracker.recompute_from_skills(skills)   ← +1 строка
    ▼
MoodTracker (autoload, scripts/core/narrative/)
    │  пересчёт _counts: Dictionary
    │  EventBus.player_mood_changed.emit(counts, dominant)
    ▼
(consumer — Никита, отдельный спек)
```

`MoodTracker` — чистая функция от текущих skills. State хранится только чтобы не пересчитывать на каждый `get_*`. Никаких listener'ов на EventBus, никакой реакции на бой/раны.

## Файлы и оценки

### Новые

| Файл | Что | LoC |
|---|---|---|
| `scripts/core/narrative/mood_tracker.gd` | autoload-класс с `MOODS_SKILL`, `MOOD_CHIMERA`, `recompute_from_skills`, `get_counts`, `get_dominant` | ~50 |
| `specs/038-mood-counter/{spec,plan,tasks}.md` | этот спек | — |

### Изменённые

| Файл | Что | LoC |
|---|---|---|
| `project.godot` | autoload `MoodTracker="*res://scripts/core/narrative/mood_tracker.gd"` после `EnemyAIPlanner` (порядок не критичен — нет cross-autoload зависимостей) | +1 |
| `scripts/infrastructure/event_bus.gd` | `signal player_mood_changed(counts: Dictionary, dominant: StringName)` | +1 |
| `scripts/core/skills/skill_database.gd` | warn на mood вне канона при `_build_skill` | ~6 |
| `scripts/presentation/godmode/godmode_controller.gd` | в `sync_player_skills_from_slots()` после `player.set_skills(skills)` — `MoodTracker.recompute_from_skills(skills)` | +1 |
| `data/skills/*.json` × 52 | mass-replace значений `mood` (см. tasks.md T040) | ~52 строк дифа |
| `CLAUDE.md` | claim 038 в таблице currently-claimed | +1 |

## Контракт MoodTracker (полный код для предсмотра)

```gdscript
# scripts/core/narrative/mood_tracker.gd
extends Node
## MoodTracker — narrative character tracker driven by equipped player skills.
##
## State derived from current Skill list (typically the player's slot-bar dedup'd
## copy via Actor._skills). Recomputed on every set_skills call from
## godmode_controller.sync_player_skills_from_slots; no listeners on its own.
##
## Consumer (DialogueManager line picker) reads via get_dominant() or the
## player_mood_changed signal. Out of scope here — see spec 038.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const MOODS_SKILL: Array[StringName] = [&"neutral", &"tranquility", &"burnout", &"ascended"]
const MOOD_CHIMERA: StringName = &"chimera"

var _counts: Dictionary = {}      # StringName -> int, keys = MOODS_SKILL
var _warned_unknown: Dictionary = {}   # StringName -> true, warn-once dedup


func _ready() -> void:
    _zero_counts()


func recompute_from_skills(skills: Array) -> void:
    _zero_counts()
    for s in skills:
        var sk: Skill = s as Skill
        if sk == null:
            continue
        for m in sk.mood:
            var key: StringName = m
            if MOODS_SKILL.has(key):
                _counts[key] = (_counts[key] as int) + 1
            else:
                _warn_unknown(sk.id, key)
    var dom: StringName = get_dominant()
    GameLogger.info("MoodTracker", "counts=%s dominant=%s" % [_counts, dom])
    EventBus.player_mood_changed.emit(get_counts(), dom)


func get_counts() -> Dictionary:
    return _counts.duplicate()   # defensive copy


func get_dominant() -> StringName:
    var max_v: int = 0
    for m in MOODS_SKILL:
        var v: int = _counts[m]
        if v > max_v:
            max_v = v
    if max_v == 0:
        return &"neutral"
    var winners: Array[StringName] = []
    for m in MOODS_SKILL:
        if (_counts[m] as int) == max_v:
            winners.append(m)
    if winners.size() > 1:
        return MOOD_CHIMERA
    return winners[0]


func _zero_counts() -> void:
    for m in MOODS_SKILL:
        _counts[m] = 0


func _warn_unknown(skill_id: StringName, mood: StringName) -> void:
    var key: StringName = StringName("%s/%s" % [skill_id, mood])
    if _warned_unknown.has(key):
        return
    _warned_unknown[key] = true
    GameLogger.warn("MoodTracker", "skill %s has unknown mood '%s' — skipped" % [skill_id, mood])
```

## SkillDatabase валидация

В `_build_skill` после парсинга `mood`:

```gdscript
const _VALID_MOODS: Array[StringName] = [&"neutral", &"tranquility", &"burnout", &"ascended"]
# (chimera intentionally excluded — meta-only, see spec 038)

for m in skill.mood:
    if not _VALID_MOODS.has(m):
        GameLogger.warn("SkillDatabase", "skill %s: unknown mood '%s'" % [skill.id, m])
```

Дублируется с `MoodTracker._warn_unknown` намеренно: SkillDatabase ловит при загрузке (видно сразу при старте), MoodTracker — на runtime, если кто-то добавит skill через код. Стоимость — 6 LoC, выгода — fail-fast.

Ссылка на `MoodTracker.MOODS_SKILL` через autoload работала бы, но создаёт скрытую autoload-зависимость; локальная константа в skill_database.gd проще и не требует загрузочного порядка.

## Order of autoload

`project.godot` сейчас:

```
EventBus, RunScore, GameSpeed, UiTheme, AudioDirector, DialogueDB, DialogueManager,
TurnManager, StatusRegistry, AbilityDatabase, SkillDatabase, BehaviorDatabase,
EnemyAIPlanner, CrtPostFx, ActiveLevel
```

Вставить `MoodTracker` сразу после `SkillDatabase` (логически связан, перед EnemyAIPlanner — чтобы быть готовым к моменту первого `set_skills`). EventBus идёт первым, так что emit отрабатывает с любого момента.

## JSON-миграция: точные маппинги

Один sed-проход на репе. **Только в `data/skills/`**, чтобы не задеть случайные совпадения слов в коде/доках.

```bash
cd data/skills
for f in *.json; do
    sed -i \
        -e 's/"friendly"/"tranquility"/g' \
        -e 's/"toxic"/"burnout"/g' \
        -e 's/"apathetic"/"ascended"/g' \
        "$f"
done
```

`"neutral"` не трогаем (одно вхождение, остаётся как есть).

После: `git diff --stat data/skills/` ≈ 46 файлов изменены (6 файлов имеют только `neutral` или multiline mood, и они not affected — sed безопасен на строковых литералах в одинарных кавычках в нашем JSON-формате).

Грепы для AC-2:
```bash
grep -l '"friendly"\|"toxic"\|"apathetic"' data/skills/*.json   # должно быть пусто
grep -l '"tranquility"\|"burnout"\|"ascended"\|"neutral"' data/skills/*.json | wc -l   # должно быть 52
```

## Риски и митигации

| Риск | Митигация |
|---|---|
| sed зацепит `"friendly"` где-то вне поля `mood` в JSON | Поле `mood` — единственный массив строк в skill.json кроме `behaviour_tags`. `behaviour_tags` использует другой словарь (`melee`/`ranged`/`damage`/`heal`/...) — пересечений нет. Грепом валидируется (см. AC-2). |
| Никита параллельно правит skill JSON'ы со старыми именами | Координация словесная: после мерджа этого PR — все новые скиллы пишутся в новом словаре. Warn в SkillDatabase ловит забытые. |
| Тест/dev-скиллы (`test_*.json`) тоже мигрируют | Намеренно — единый словарь по всему репо. |
| `recompute_from_skills` вызывается до того, как `MoodTracker._ready()` отработал | autoload `_ready` гарантирован до первого frame'а; `sync_player_skills_from_slots` вызывается из `GodmodeSetup._ready()` — node-level, после autoload'ов. Безопасно. |
| Двойной emit при одной смене слота | `_on_ability_picker_selected` зовёт `sync_player_skills_from_slots` ровно раз → один recompute → один emit. ОК. |

## Что не делаем (по CLAUDE.md «don't»)

- Не делаем `MoodTracker.MOODS_SKILL` ссылкой из SkillDatabase (autoload coupling «на будущее» — лишняя связность).
- Не выносим словарь mood в `mood_constants.gd` отдельно — это +файл ради двух констант.
- Не добавляем `reset()` / persistence API — no consumer.
- Не делаем `Array[Skill]` параметр (CLAUDE.md trap по типизованным массивам с пользовательскими классами через Variant-границу — `Actor.get_skills()` уже плоский Array по той же причине).
