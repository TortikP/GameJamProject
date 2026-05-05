# 051 — Ability SFX Resolver

**Owner:** Egor
**Status:** in-progress

## Problem

С 047 `Ability.sound_start` / `sound_end` дёргают `AudioDirector.play_sfx(id, pos)` через прямой path-конкат `res://assets/audio/sfx/<id>`. Никакой звук абилок не играет: реальные ассеты лежат в `assets/audio/sfx/abilitys/<ability_id>/<filename>.wav`, имена файлов произвольные, ID в JSON не совпадают с путями. В staging уже залит набор из 36 папок со звуками cast-start — диспатч не подключен.

## Goal

`AudioDirector` сам резолвит звук абилки по `ability.id`: берёт папку `assets/audio/sfx/abilitys/<ability_id>/`, ищет файлы с `sound_start` или `sound_end` в имени, проигрывает случайный из подходящих.

## Acceptance criteria

- **AC1.** При касте абилки с `sound_start != ""` и наличии папки `assets/audio/sfx/abilitys/<ability.id>/` с файлом, имя которого содержит `sound_start`, звук играется fire-and-forget на `caster.global_position`.
- **AC2.** То же для `sound_end` после apply_resolved.
- **AC3.** Если папки нет или в ней нет подходящего файла — silent no-op + один warn в лог (без краша).
- **AC4.** Если в папке несколько файлов с `sound_start` (`default_melee_damage` имеет `_sound_start.wav` и `_sound_start1.wav`) — выбирается случайный на каждом касте.
- **AC5.** JSON-поля `sound_start` / `sound_end` сохраняют семантику toggle: `""` = тишина, любое непустое = играть. Конкретное значение игнорируется.
- **AC6.** Существующий `AudioDirector.play_sfx(id, pos)` работает как раньше (UI-клики, `breaking_object`, и т.п.).

## Out of scope

- Переименование/чистка существующих файлов в `assets/audio/sfx/abilitys/` (3 ID без папок: `angel_divine_word_holy_heal_area`, `angel_scorching_ray_scorching`, `teapot_low_possibility_invisibility`; лишние `move_grass.zip`, `stone_move_sound_start` — это контент-долг, не код).
- Звуковой пул (всё ещё spawn-and-free, как в 047).
- Volume/mixing/3D-attenuation тюнинг.
- Отдельные звуки для collision_effect / animation каналов.

## Open questions

— нет.
