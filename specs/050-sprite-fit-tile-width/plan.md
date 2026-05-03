# 050-sprite-fit-tile-width — plan

## Архитектурное решение

### Где живёт fitter

`scripts/infrastructure/sprite_fit.gd` — рядом с `hex_geometry.gd`, `event_bus.gd`, `actor_motion.gd`. Это cross-cutting утилита, не presentation-специфичная (хотя оперирует Sprite2D — это присвоено к infrastructure через прецедент `actor_motion.gd`, который тоже трогает Node2D).

Static-only, без `class_name`, без autoload — следуем pattern `GameLogger` (CLAUDE traps таблица). Consumers preload'ят:

```gdscript
const SpriteFit = preload("res://scripts/infrastructure/sprite_fit.gd")
```

### Math

```
scale_factor = base_scale * tile_width / texture.get_width()
sprite.scale = Vector2(scale_factor, scale_factor)
```

`base_scale=1.0` по умолчанию — для player/enemy/spawner. ObjectsOverlay передаёт свой `sprite_scale` (export var) как base_scale, чтобы старая ручка тюнинга работала как multiplier поверх tile-fit'а.

### Tile width source

128 — hardcoded default в SpriteFit.fit_to_tile_width. Это безопасно потому что:
- CLAUDE.md hard rule #7: единственный TileSet `hex_terrain.tres`, `tile_size = Vector2i(128, 80)`. Менять нельзя без переписывания hex pathfinder'а.
- Player/enemy/spawner НЕ знают про grid в момент `_ready` (грид может ещё не быть приатачен). Жить только с дефолтом — простая надёжная стратегия.
- ObjectsOverlay имеет `@export var grid: HexGrid` — может прочитать `grid.tile_map_layer.tile_set.tile_size.x` в runtime. Делаем helper `_tile_width()` для DRY.

### Когда вызывать fitter

После того как texture присвоен sprite'у. Это критично потому что fitter читает `texture.get_width()`. Порядок:

1. **Player** (player_view.gd._ready): texture зашита в .tscn → texture уже доступна на момент `_ready`. Вызываем сразу.
2. **Enemy** (enemy_view.gd._ready): texture применяется из `hints["sprite"]` ВНУТРИ `_ready`. Fitter ВНУТРИ того же if-блока, после `body.texture = tex`.
3. **ObjectsOverlay** (set_object): texture применяется в `set_object`. Fitter сразу после `sprite.texture = tex`, перед `add_child`.
4. **SpawnerPlaceholder** (_apply_visuals): texture может быть из ENEMY_SPRITES dict, может быть из .tscn fallback'а. Fitter в конце `_apply_visuals` — гарантирует что texture финализирована.

### Что делать если texture null

В `enemy_view.gd` уже есть лог `failed to load sprite '%s'` — fitter не вызывается потому что внутри `else`. Добавим guard в самом fitter'е (defensive):

```gdscript
if sprite == null or sprite.texture == null:
    return
var w := sprite.texture.get_width()
if w <= 0:
    GameLogger.warn("SpriteFit", "texture has zero width: %s" % sprite.name)
    return
```

## Dialogue portrait deep-dive

### Текущий поток

```
DialogueManager.show_line(line)
  → DialogueDB.get_speaker(line.speaker)  → speaker_data dict
  → DialoguePanel.show_line(line, speaker_data)
    → _portrait.texture = _resolve_portrait(line, speaker_data)
        path = line.portrait OR speaker_data.default_portrait OR ""
        if path != "" and FileAccess.file_exists(path) → load(path) returned
        else → _make_placeholder(speaker_id)  # flat colored rect 160×160
```

### Изменения

**`_make_placeholder` теперь:**
1. Пробует cache: `_placeholder_cache["__default__"]` — глобальный default, не per-speaker (нет смысла per-speaker т.к. дефолт один на всех).
2. Если кэша нет — пробует `load("res://assets/portraits/default_portrait.png")` через `_try_load_texture` (он уже умеет проверять `FileAccess.file_exists`).
3. Если default_portrait.png существует → кладёт в кэш как `__default__`, возвращает.
4. Иначе fallback на flat rect (`Image.create(130, 180, ...)`, fill BG_PANEL_2). Тоже кэшируем как `__default__`.

Per-speaker cache key (`_placeholder_cache[speaker_id]`) больше не нужен — все speaker'ы получают один дефолтный файл. Аргумент `speaker_id` в `_make_placeholder` сохраняем для совместимости сигнатуры, но не используем.

**Размер flat rect** меняется с 160×160 на 130×180 для соответствия новому min-size слота — иначе при отсутствии файла плейсхолдер растянется/сожмётся через `expand_mode=1` + `stretch_mode=6` (KEEP_ASPECT_CENTERED).

### TextureRect геометрия

Portrait в .tscn:
```
custom_minimum_size = Vector2(160, 160)
expand_mode = 1                # ignore_size, expand to fill
stretch_mode = 6                # keep_aspect_centered
```

Меняем только `custom_minimum_size = Vector2(130, 180)`. expand_mode + stretch_mode оставляем — они корректно отрабатывают любой aspect ratio: картинка вписывается в bounding box с сохранением aspect, центрируется. С default_portrait.png (130×180) и слотом (130×180) — pixel-perfect, без масштабирования.

### Speakers JSON неизменно

`data/dialogues/_speakers.json` ссылается на несуществующие per-speaker портреты (heroine_neutral.png и т.д.) — оставляем как есть. Когда Катя пришлёт реальные портреты — кладутся в `assets/portraits/` под этими именами и подхватываются автоматически (приоритет per-speaker > default).

## .png.import sidecar

Шаблон по `assets/sprites/bush.png.import`. Нужно:
- Уникальный `uid` (формат `uid://<13-char base32>`).
- Корректный `source_file = "res://assets/portraits/default_portrait.png"`.
- `path` и `dest_files` ссылаются на `.godot/imported/default_portrait.png-<32hex>.ctex`. Hash в имени — Godot хеширует path при импорте; можно поставить любой 32-hex placeholder (Godot регенерирует на первом import'е).
- Все остальные параметры — дефолтные значения как в bush.png.import.

При первом открытии проекта в редакторе Godot увидит .import, не найдёт .ctex (он в .godot/imported/ который gitignore'ится), импортирует заново и обновит .ctex путь и hash. UID при этом сохраняется (Godot уважает существующий uid в .import).

## Файлы

| Файл | Действие | Размер |
|---|---|---|
| `scripts/infrastructure/sprite_fit.gd` | NEW | ~25 строк |
| `scripts/presentation/godmode/player_view.gd` | NEW | ~15 строк |
| `scripts/presentation/godmode/enemy_view.gd` | MOD | +2 строки |
| `scripts/presentation/dev/objects_overlay.gd` | MOD | +6 строк (fitter + helper) |
| `scripts/presentation/runtime/spawner_placeholder.gd` | MOD | +2 строки |
| `scripts/presentation/dialogue_panel.gd` | MOD | ~10 строк (rewrite _make_placeholder) |
| `scenes/dev/player.tscn` | MOD | -1 line (drop scale), 1 ext_resource swap |
| `scenes/dev/enemy.tscn` | MOD | -1 line (drop redundant scale=1,1) |
| `scenes/runtime/spawner_placeholder.tscn` | MOD | -1 line (drop scale=0.09) |
| `scenes/ui/dialogue_panel.tscn` | MOD | min_size 160→130, 160→180 |
| `assets/portraits/default_portrait.png` | NEW | binary, 130×180 (~8KB) |
| `assets/portraits/default_portrait.png.import` | NEW | INI, ~25 строк |
| `specs/050-sprite-fit-tile-width/spec.md` | NEW | this spec |
| `specs/050-sprite-fit-tile-width/plan.md` | NEW | this plan |
| `specs/050-sprite-fit-tile-width/tasks.md` | NEW | task list |

Total: 6 new files, 7 modified, ~80 lines of code added/changed.

## Smoke-тесты после имплементации

1. **Player size:** F2 reset godmode → player Body визуально 128px wide (≈ ширина одного hex'а).
2. **Enemy variety:** Spawn manekin (F1), bear, angel — все ≈ 128px wide, разной высоты пропорционально.
3. **Tile object:** Map editor → painted tree, mountain, crystal — ≈ 128px wide.
4. **Spawner:** Запустить волну с маникен'ом за 3 хода — призрак 128px wide, label с цифрой над ним читается.
5. **Dialogue default:** Запустить intro_office_monologue (или любой dialogue без default_portrait файла) — слева 130×180 слот с acpest-картинкой.
6. **Dialogue with file:** Если потом Катя пришлёт `heroine_neutral.png` 130×180 → подхватывается автоматически, default не используется.

## Откат

Если что-то ломается на финальной полировке — `git revert` коммита целиком возвращает все .tscn хардкоды и старый _make_placeholder. Никаких миграций данных, никаких EventBus сигналов — feature чисто косметическая.
