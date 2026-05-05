# 053 — Plan

## Touch list

```
EDIT:
  scripts/infrastructure/audio_director.gd   — drop DirAccess scan, lazy probe via ResourceLoader.exists
  scripts/presentation/dialogue_panel.gd     — _try_load_texture: FileAccess.file_exists → ResourceLoader.exists
  project.godot                              — remove CutscenePlayer autoload entry

NEW:
  specs/053-pck-audio-portrait-fix/{spec,plan,tasks}.md
```

## audio_director.gd

### Drop

- `_ability_sfx_re_start`, `_ability_sfx_re_end` (RegEx) — больше не нужны, имена файлов теперь канонические после 052.
- `_build_ability_sfx_cache()`, `_scan_ability_folder(name)` — DirAccess-логика заменяется на лениво-пробирующую.
- `dir.list_dir_begin / get_next / list_dir_end` блок в `_ready`.

### Add

```gdscript
const ABILITY_SFX_VARIATIONS_MAX := 4   # probes _sound_start, _sound_start1..3

# Lazy init: probed on first play_ability_sfx call per ability_id.
# {start: [paths], end: [paths]}; absent ID = not probed yet.
var _ability_sfx_cache: Dictionary = {}


func play_ability_sfx(ability_id: StringName, phase: StringName, world_pos: Variant = null) -> void:
    if ability_id == &"":
        return
    if not _ability_sfx_cache.has(ability_id):
        _ability_sfx_cache[ability_id] = _probe_ability_folder(ability_id)
    var bucket: Dictionary = _ability_sfx_cache[ability_id]
    var paths: Array = bucket.get(phase, [])
    if paths.is_empty():
        return
    var path: String = paths[randi() % paths.size()]
    _play_path(path, world_pos, _resolve_bus("sfx"))


func _probe_ability_folder(ability_id: StringName) -> Dictionary:
    var folder := ABILITIES_SFX_DIR + String(ability_id) + "/"
    var starts: Array[String] = []
    var ends: Array[String] = []
    for ext in ABILITY_SFX_AUDIO_EXTS:
        for i in ABILITY_SFX_VARIATIONS_MAX:
            var suffix := "" if i == 0 else str(i)
            var ps := "%s%s_sound_start%s.%s" % [folder, String(ability_id), suffix, ext]
            if ResourceLoader.exists(ps):
                starts.append(ps)
            var pe := "%s%s_sound_end%s.%s" % [folder, String(ability_id), suffix, ext]
            if ResourceLoader.exists(pe):
                ends.append(pe)
    return { &"start": starts, &"end": ends }
```

`_ready` упрощается до:

```gdscript
func _ready() -> void:
    GameLogger.info("AudioDirector", "ready (ability sfx: lazy probe, max %d variations)" % ABILITY_SFX_VARIATIONS_MAX)
```

### Why convention probing works in .pck where DirAccess didn't

`ResourceLoader.exists("res://path/file.wav")` смотрит remap-таблицу пакета. Импортированный `.wav` имеет запись `res://...wav` → `.godot/imported/...sample`. `exists` возвращает true. То же `load(path)` отдаёт `AudioStreamWAV`. `DirAccess.list_dir` же листит сырую структуру пакета — а в неё импортированные исходники не попадают как файлы своего исходного имени, только как хешированные `.sample` в `.godot/imported/`. Конвенция `<id>_sound_start[N].wav` работает оба раза (editor + .pck) одним кодом.

### Editor compat

Существующий пример `default_melee_damage_sound_start.wav` + `default_melee_damage_sound_start1.wav` — пробируется как i=0 (suffix=""), i=1 (suffix="1"). i=2/i=3 → exists=false → не добавляются. Random pick на касте по-прежнему между двумя.

`stone_move_sound_start` папка с файлом `stone_move_sound_start.wav` (имя совпадает с дирректорией без подсуффикса):
- abilities никто этим id не использует — orphan из 051.
- При пробинге для воображаемой `stone_move_sound_start` ability оно сработало бы — пробуем `stone_move_sound_start_sound_start.wav` (нет) — bucket пустой. Невозможный кейс на практике.

### Order-of-init

AudioDirector в автолоадах #6, AbilityDatabase #14. AbilityDatabase ещё не загружен на момент `AudioDirector._ready`. **Это причина ленивой инициализации**: первый каст происходит после полного автолоад-старта, AbilityDatabase к этому моменту готов; пробинг идёт по реальному ability_id, переданному в `play_ability_sfx`.

## dialogue_panel.gd

```gdscript
# was:
func _try_load_texture(path: String) -> Texture2D:
    if not FileAccess.file_exists(path):
        return null
    return load(path)

# becomes:
func _try_load_texture(path: String) -> Texture2D:
    if not ResourceLoader.exists(path):
        return null
    return load(path) as Texture2D
```

`as Texture2D` — defensive: `load()` для не-Texture2D ресурса даст null cast и ветка `if tex != null` сработает корректно. Сейчас тоже сработало бы (load возвращает Resource), но эксплицитный cast чище.

В редакторе ResourceLoader.exists для существующего .png тоже возвращает true, поэтому регрессии нет.

## project.godot

```
- CutscenePlayer="*res://scripts/presentation/meta/cutscene_player.gd"
```

Сейчас файла нет (удалён в 0666263), запись болтается. Никаких внешних рефов нет (`grep -rn CutscenePlayer scripts/ scenes/` пуст). После удаления `Failed to instantiate an autoload` уйдёт из лога.

## Notes

- Probing 4 вариаций × 3 расширений = 12 `ResourceLoader.exists` calls per ability на первом касте. ResourceLoader.exists — O(1) lookup в hash-table пакета. Стоимость незаметна.
- Кеш стабилен в пределах сессии. Reload происходит только на новый запуск.
- Семантика gate'ов `sound_start` / `sound_end` в JSON остаётся прежней (как 051): пустая строка = no-op гарантированно (early return по ability_id == &""... wait, gate проверяется в FxDirector, не здесь). FxDirector.play_cast / play_sound_end продолжают проверять `ability.sound_start != &""` / `ability.sound_end != &""` перед вызовом, ничего не меняем.
