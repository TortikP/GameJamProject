# 053 — PCK Audio + Portrait Fix

**Owner:** Egor
**Status:** in-progress

## Problem

В web-билде и Windows desktop-билде:
1. Не играют звуки абилок (лог: `[INFO][AudioDirector] ready (ability sfx folders: 0)` — кеш пустой; `[WARN][AudioDirector] play_ability_sfx: no folder for 'monkey_business_damage'` на каждый каст).
2. Не отображаются портреты в диалоговой панели (placeholder-цветной прямоугольник вместо `default_portrait.png`).

В редакторе обе системы работают.

### Root cause

**Audio (051 regression в .pck):** `_build_ability_sfx_cache()` ходит по `res://assets/audio/sfx/abilitys/` через `DirAccess.list_dir_begin()` + `current_is_dir()`. В экспортированном `.pck` импортированные аудиоресурсы хранятся не как `.wav` в исходных директориях, а как `.sample` под хешированными путями в `.godot/imported/`. `DirAccess.open` отрабатывает, но `current_is_dir()` возвращает false для всех вариантов — субдиректории не enumerated. Итог: `_ability_sfx_cache` пуст, каждый каст падает в `bucket == null` → silent + warn. Допущение в plan 051 («DirAccess.open в .pck работает») оказалось неверным для импорта-производных ресурсов.

**Portraits (049 bug в .pck):** `dialogue_panel._try_load_texture(path)` проверяет наличие текстуры через `FileAccess.file_exists(path)`. В `.pck` исходный `.png` не упаковывается — пакуется импортированный `.ctex` по хешированному пути. `FileAccess.file_exists` смотрит сырое содержимое пакета, импортированные ремапы не учитывает → возвращает false для каждого `res://assets/portraits/*.png`. `_resolve_portrait` фоллбекается на `_make_placeholder`, который тоже использует тот же `_try_load_texture` для дефолтного портрета → fail → flat colored rect. `enemy_details_panel._refresh_portrait` уже использует `ResourceLoader.exists` (049/T013) — там OK, проблема локальна dialogue_panel'у.

**Дроп-by:** автолоад `CutscenePlayer` в `project.godot` указывает на `scripts/presentation/meta/cutscene_player.gd`, удалённый в коммите `0666263`. Никто на него не ссылается (`grep -rn CutscenePlayer scripts/ scenes/` пуст). Фейлит автолоад-инициализацию в каждом запуске (редактор и .pck одинаково).

## Goal

1. **Audio.** Заменить filesystem-scan через DirAccess на конвенционное пробирование через `ResourceLoader.exists()` — то же, что `_resolve_dialogue_audio_path` уже делает для voice-клипов. Кеш строится лениво по первому касту абилки.
2. **Portraits.** Заменить `FileAccess.file_exists(path)` на `ResourceLoader.exists(path)` в `dialogue_panel._try_load_texture` (локальный фикс, никаких сайт-эффектов).
3. **Cleanup.** Убрать мёртвый автолоад `CutscenePlayer` из `project.godot`.

## Acceptance criteria

- **AC1.** В web-билде каст `monkey_business_damage` (и любой другой абилки с непустым `sound_start` и существующим файлом `<id>_sound_start.wav` в `assets/audio/sfx/abilitys/<id>/`) проигрывает звук.
- **AC2.** В логе .pck-билда нет `[WARN][AudioDirector] play_ability_sfx: no folder for '<id>'` для абилок, чьи папки физически существуют. (Допускается warn для `teapot_low_possibility_invisibility` — папки нет на диске.)
- **AC3.** В редакторе поведение не меняется. Звуки играют как раньше; `default_melee_damage` всё так же случайно выбирает между `_sound_start.wav` и `_sound_start1.wav`.
- **AC4.** В web-билде в диалоговой панели портреты грузятся: `default_portrait.png` (отшипнутый файл) виден когда у спикера нет per-line override и нет персонального портрета.
- **AC5.** В логе .pck-билда нет `Failed to instantiate an autoload, can't load from path: res://scripts/presentation/meta/cutscene_player.gd`.
- **AC6.** Поведение в редакторе для всех трёх изменений — идентично текущему staging (никаких визуальных регрессий, никаких новых warn'ов кроме AC5).

## Out of scope

- `config/game_speed.cfg` не пакуется в .pck (нет в репозитории `export_presets.cfg` с `*.cfg` в filter). Решает тот, кто экспортит — Андрей. См. findings ниже.
- Отсутствующие портреты `narrator_neutral.png` / `rival_neutral.png` / `heroine_neutral.png` / `merchant_neutral.png` — content-debt, лежит на Кате.
- Статус `invisible` не зарегистрирован в StatusRegistry, но упомянут в `data/skills/teapot_low_possibility.json` — отдельный баг.
- Запаздывание AbilityDatabase относительно AudioDirector в порядке автолоадов (AudioDirector грузится 6-м, AbilityDatabase — 14-м). Не пересортировываем — ленивая инициализация кеша на первом касте обходит проблему без перестановки.

## Findings (out of scope, surface for owner)

- **F-053-1** (Andrey): `export_presets.cfg` отсутствует в репозитории. Каждый, кто экспортирует, использует свои локальные пресеты — фильтры могут расходиться. Минимум `*.cfg` в "Filters to export non-resource files/folders" нужен для `config/game_speed.cfg`. Возможно стоит коммитнуть базовый `export_presets.cfg` (без `export_credentials.cfg`, который и так в .gitignore).
- **F-053-2** (Katya / Andrey): 4 portrait'а из `data/dialogues/_speakers.json` отсутствуют на диске. Сейчас все спикеры в диалоге показывают `default_portrait.png`.
- **F-053-3** (Sergey / кто-нибудь): `invisible` status в JSON, но не в StatusRegistry. Каст `teapot_low_possibility` валится с warn'ом «unknown status_id 'invisible'».

## Open questions

— нет.
