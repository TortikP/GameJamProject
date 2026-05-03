# 051 — Tasks

- [x] T001 — `AudioDirector`: добавить `ABILITIES_SFX_DIR`, `_ability_sfx_cache`, скомпилированные RegEx для `sound_start` / `sound_end`.
- [x] T002 — `AudioDirector._build_ability_sfx_cache()` + `_scan_ability_folder(name)` — листинг папок при `_ready`.
- [x] T003 — `AudioDirector._play_path(path, world_pos)` — общий помощник, использовать в `play_sfx` и `play_ability_sfx`.
- [x] T004 — `AudioDirector.play_ability_sfx(ability_id, phase, world_pos)` — резолв + random pick.
- [x] T005 — `AudioDirector` log line на `_ready`: количество папок в кеше.
- [x] T006 — `FxDirector.play_cast`: переключить вызов на `play_ability_sfx(ability.id, &"start", ...)`.
- [x] T007 — `FxDirector.play_sound_end`: переключить на `play_ability_sfx(ability.id, &"end", ...)`.
- [x] T008 — Обновить header doc-comments в обоих файлах под новый flow.
