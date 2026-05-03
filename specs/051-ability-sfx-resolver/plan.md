# 051 — Plan

## Touch list

```
NEW:
  specs/051-ability-sfx-resolver/{spec,plan,tasks}.md

EDIT:
  scripts/infrastructure/audio_director.gd   — +cache, +regexes, +play_ability_sfx, +_play_path helper
  scripts/presentation/fx_director.gd        — switch play_cast / play_sound_end to play_ability_sfx
```

## API

### `AudioDirector` (additions)

```gdscript
const ABILITIES_SFX_DIR := "res://assets/audio/sfx/abilitys/"

# StringName ability_id -> { &"start": Array[String], &"end": Array[String] }
var _ability_sfx_cache: Dictionary

func play_ability_sfx(ability_id: StringName, phase: StringName, world_pos: Variant = null) -> void
# phase ∈ { &"start", &"end" }; пустой ability_id = no-op.
```

Существующий `play_sfx(id, pos)` рефакторится поверх общего `_play_path(path, pos)` — поведение не меняется, дублирование исчезает.

### Resolver flow

1. На `_ready` сканируется `ABILITIES_SFX_DIR`, для каждой подпапки строится bucket `{start: [...], end: [...]}` по regex-матчу `sound_start` / `sound_end` на basename файлов с расширениями `.wav` / `.ogg` / `.mp3`. Кеш живёт всё время.
2. `play_ability_sfx(ability_id, phase, pos)` смотрит кеш; пустой bucket → warn + return; иначе `paths[randi() % paths.size()]` → `_play_path`.

### `FxDirector` diff

```gdscript
# play_cast — было:
if ability.sound_start != &"":
    AudioDirector.play_sfx(ability.sound_start, caster.global_position)
# стало:
if ability.sound_start != &"":
    AudioDirector.play_ability_sfx(ability.id, &"start", caster.global_position)

# play_sound_end — было:
AudioDirector.play_sfx(ability.sound_end, world_pos)
# стало:
AudioDirector.play_ability_sfx(ability.id, &"end", world_pos)
```

JSON-поля `sound_start` / `sound_end` остаются gate-флагами — их value игнорируется.

## Notes

- `DirAccess.list_dir_begin()` в Godot 4 по умолчанию пропускает скрытые и `.import` сайдкары. Доп-фильтр по расширению — на всякий случай.
- Regex используется через `RegEx.compile("sound_start")` / `"sound_end"`. Substring-match — паттерн "только либо `sound_start`, либо `sound_end` в имени" по решению Egor.
- Кеш строится один раз. Если в build-е звуки в `.pck` — `DirAccess.open("res://...")` работает (тот же приём в `FxDirector._load_fx_registry`).
- `world_pos` Vector2 → `AudioStreamPlayer2D`; null → `AudioStreamPlayer` (сохранение текущего поведения `play_sfx`).
