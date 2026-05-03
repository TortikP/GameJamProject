# 052 — Tasks

- [x] T001 — Rename `angel_divine_word_holy_heal_area_sond.wav` (+ `.import`) → `..._sound_start.wav`. Update `source_file=` inside the `.import`.
- [x] T002 — Rename `angel_scorching_ray_scorching_sound.wav` (+ `.import`) → `..._sound_start.wav`. Update `source_file=`.
- [x] T003 — Rename `bear_paw_suck_self_heal_start_sound.wav` (+ `.import`) → `..._sound_start.wav`. Update `source_file=`.
- [x] T004 — Rename `monkey_business_damage_start_sound.wav` (+ `.import`) → `..._sound_start.wav`. Update `source_file=`.
- [x] T005 — Rename `mushroom_boar_spores_stun_area_sound start.wav` (+ `.import`) → `..._sound_start.wav` (заменить пробел на `_`). Update `source_file=`.
- [x] T006 — Create `default_bus_layout.tres` with Master, Music, SFX (Music/SFX → send to Master, all 0 dB).
- [x] T007 — Add `[audio] buses/default_bus_layout="res://default_bus_layout.tres"` to `project.godot`.
- [x] T008 — Edit `scripts/presentation/settings_panel.gd`: add `_apply_initial_volumes()` called from `_ready` after slider connects, mirroring current slider values into buses.
- [x] T009 — Sanity: `grep -r "sound_start\|sound_end" data/skills/` — все упомянутые `sound_start` имеют матчающийся файл в соответствующей `assets/audio/sfx/abilitys/<id>/`. (Кроме `teapot_low_possibility_invisibility` — out-of-scope.)
