# 052 — Ability SFX Fix + Per-Channel Volume

**Owner:** Egor
**Status:** in-progress

## Problem

После 051 5 ability'шных start-звуков молчат. Пример: `monkey_business_damage` — каст не проигрывается. Причина: файл лежит как
`monkey_business_damage_start_sound.wav` (порядок слов `start_sound`), а резолвер 051 ищет подстроку `sound_start` в имени. Папка не попадает в `_ability_sfx_cache`, `play_ability_sfx` логит `no folder for '<id>'` и молчит.

Полный список misnamed файлов (см. tasks.md T001):

| ability_id | файл сейчас | проблема |
|---|---|---|
| `angel_divine_word_holy_heal_area` | `..._sond.wav` | опечатка `sond` |
| `angel_scorching_ray_scorching` | `..._sound.wav` | без `_start` |
| `bear_paw_suck_self_heal` | `..._start_sound.wav` | развёрнут порядок |
| `monkey_business_damage` | `..._start_sound.wav` | развёрнут порядок |
| `mushroom_boar_spores_stun_area` | `..._sound start.wav` | пробел вместо `_` |

Параллельно: слайдеры Music и SFX в `settings_panel` — no-op'ы. В проекте нет `default_bus_layout.tres`, существует только дефолтная шина Master. `_resolve_bus_indices()` находит только `_master_idx`, `_music_idx` и `_sfx_idx` остаются `-1`. `audio_director._resolve_bus("sfx"/"music")` падает на `&"Master"`. Раздельная регулировка громкости музыки и звуков не работает в принципе.

## Goal

1. Переименовать 5 wav-файлов под канон `<ability_id>_sound_start.wav` (+ `.import` сайдкары) — все start-звуки матчатся существующим regex'ом 051 без изменений в коде резолвера.
2. Добавить bus layout (Master / Music / SFX), чтобы слайдеры в settings заработали раздельно.
3. Применять стартовые значения слайдеров к шинам на `_ready`, чтобы дефолт из .tscn (Music = 60%) реально был громкостью на старте, а не только надписью под бегунком.

## Acceptance criteria

- **AC1.** Каст `monkey_business_damage` проигрывает start-звук. То же для остальных 4 переименованных абилок.
- **AC2.** В логе `AudioDirector: ready (ability sfx folders: N)` число папок выросло на 5 относительно текущего staging (до фикса это число теряет 5 misnamed папок).
- **AC3.** В рантайме `AudioServer.bus_count >= 3`, `get_bus_index("Music")` и `get_bus_index("SFX")` возвращают валидные индексы. Шины посылают сигнал в Master.
- **AC4.** Слайдеры Music и SFX в Settings меняют громкость соответствующих категорий независимо друг от друга. Master продолжает атенуировать всё.
- **AC5.** При запуске игры громкость Music = значению слайдера в .tscn (`0.6` на текущий момент), а не 0 dB.
- **AC6.** Никаких изменений в `audio_director.gd` или `fx_director.gd` (резолвер 051 не трогаем — данные исправляем под код, не наоборот).

## Out of scope

- 36 пустых вызовов `play_sound_end` — Egor подтвердил, что end-звуков не предполагается; silent no-op остаётся как в 051.
- 2 сиротских папки (`move_grass`, `stone_move_sound_start`) — content debt из 051, никто их не использует.
- Отсутствующая папка `teapot_low_possibility_invisibility` — content debt из 051.
- Расширение резолвера на новые шаблоны имён (Egor отверг fallback в clarify-раунде).
- Voice/Dialogue шины (если когда-нибудь понадобятся — отдельно; сейчас `_resolve_bus("voice"/"dialogue")` всё равно падает на Master через существующий код).
- Сериализация настроек громкости между запусками (нет user_prefs.cfg в принципе — пост-jam задача).

## Open questions

— нет.
