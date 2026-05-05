# 053 — Tasks

- [x] T001 — `audio_director.gd`: drop `_ability_sfx_re_start` / `_ability_sfx_re_end` declarations + RegEx compile in `_ready`.
- [x] T002 — `audio_director.gd`: drop `_build_ability_sfx_cache()` and `_scan_ability_folder()`, remove DirAccess scan call from `_ready`.
- [x] T003 — `audio_director.gd`: add `ABILITY_SFX_VARIATIONS_MAX := 4` const.
- [x] T004 — `audio_director.gd`: rewrite `play_ability_sfx` for lazy init, add `_probe_ability_folder(ability_id)` helper.
- [x] T005 — `audio_director.gd`: simplify `_ready` log to `lazy probe, max N variations`.
- [x] T006 — `audio_director.gd`: update header doc-comment under 047/051 to reflect new mechanism.
- [x] T007 — `dialogue_panel.gd._try_load_texture`: switch `FileAccess.file_exists` → `ResourceLoader.exists`, add `as Texture2D` cast on load.
- [x] T008 — `project.godot`: drop `CutscenePlayer="*res://scripts/presentation/meta/cutscene_player.gd"` line from `[autoload]`.
- [x] T009 — Sanity: `grep -rn "DirAccess" scripts/infrastructure/audio_director.gd` returns 0 hits. `grep -rn "FileAccess.file_exists" scripts/presentation/dialogue_panel.gd` returns 0 hits. `grep -rn "CutscenePlayer" .` returns 0 hits outside `.git`/`specs`.
