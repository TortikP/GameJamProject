# Spec 061 — Wave data + settings panel + LevelData v3

Specs: [`spec.md`](./spec.md), [`plan.md`](./plan.md), [`tasks.md`](./tasks.md), [`findings.md`](./findings.md), [`design.md`](./design.md).

## Summary

- **LevelData v3.** SCHEMA_VERSION 2→3. `is_special` transitions bool→String (free-form, default `"normal"`); new wave-level fields `respawn_player`, `advance_mode`, `music_config`. Migration in `from_dict()` is forward-only and idempotent. `is_wave_special()` helper added — required because `bool("normal")` is `true` in GDScript, breaking every direct cast.
- **WaveController advance_mode runtime gate.** `"timer"` (default, existing behaviour) / `"clear"` (timer ignored, only auto-clear advances) / `"timer_and_clear"` (timer expiry sets `_waiting_for_clear`, last-enemy death advances). `EventBus.wave_advance_blocked(blocked: bool)` exposes the gate state. `wave_timeline` (RUNTIME) draws an outlined `(waiting for clear)` cue near the cursor when blocked.
- **WaveSettingsPanel** (`scripts/presentation/dev/wave_settings_panel.gd`, `scenes/dev/wave_settings_panel.tscn`). Right-edge panel in level editor. Sections: wave switcher, Level (name mirror + dialogue triggers CRUD ported from deleted `dialogue_trigger_panel.gd`), Wave (is_special/ttn/respawn_player/advance_mode/music_config), Spawners (per-coord edit form for kind/ref/timer; later removed in IMPL-6), Skill Offer (ported from deleted `wave_panel.gd`), wave-scoped triggers mirror.
- **EditorController public API + `WaveEditorOps`.** Wave navigation (set_active_wave, add_wave, copy_wave_from_prev, delete_wave), per-wave/spawner field setters, dialogue trigger CRUD, skill_offer update — all routed through a new RefCounted static-methods module so the controller stays close to its 350-line cap. Trigger CRUD signals connect directly to public API methods (Godot ignores bool returns from `add/update/delete_dialogue_trigger` slots).
- **51 localization keys** (en + ru) — `ui_wavesettings_*`, `ui_trigger_*`, `ui_spawner_form_*`, `ui_wave_waiting_for_clear`. ru translations are working drafts.
- **Schema docs + designer reference.** `data/maps/_schema.md` updated for v3; new `docs/systems/level-editor/dialogue-triggers.md` covers the trigger system end-to-end. `docs/FEATURES.md` seeded with first three reg-entries (`wave-settings-panel`, `dialogue-triggers-editor`, `wave-advance-mode`).

## Diff

12 commits on `andrey/061-wave-data-and-settings`. ~3.9k insertions, ~50 deletions. Net new code: ~700 LOC GDScript + 1 scene + ~50 loc-keys × 2 + ~150 lines markdown + spec/plan/tasks/findings.

## Findings (notable)

- **F-061-IMPL-1** — `_wave_dict_from_arr` (level_data.gd:517) and `to_dict` (line 274) had `bool(...)` casts on `is_special` that pre-dated 061. After v3 migration they would have re-corrupted `"normal"` → `true` → `"boss"` on save+reload roundtrip. Stripped both casts; replaced with raw read + post-loop migration normalization. Audit miss from Φ-0; logged Φ-1.
- **F-061-IMPL-2** — `wave_settings_panel.gd` ended at ~1380 LOC (vs 600 soft cap from spec.md F-061-6). Decided **not** to extract: the file is monolithic by architecture (six sections share `_refreshing` guard + helpers), CRUD-form is the only realistic extract candidate (~400 LOC) but the glue would consume most of the win. Will revisit if a second consumer for trigger CRUD appears.
- **F-061-IMPL-3** — `editor_controller.gd` landed at 398 LOC (vs 350 hard cap). Created `WaveEditorOps` (RefCounted, all-static, mirrors `LevelMutations`) and trimmed trampolines, but the wrapper layer + WaveSettingsPanel wiring still pushes 48 over. Accepted to keep stateless static-ops architecture; alternative (Node-child `WaveEditorOps` that knows about panel/overlay refs) was rejected as worse.
- **F-061-IMPL-4** — _Obsoleted by F-061-IMPL-9._ Originally: `_deep_copy_spawners` (`level_data.gd`) was not updated for v3 schema and dropped `amount`/`delay` fields between every `_sync_root_to_active_wave` call. Caught by `tests/test_061_migration.gd` — exactly the bug the auto-test was meant to find. The fix was reverted in IMPL-9 along with the schema fields themselves; the auto-test still validates that `_deep_copy_spawners` round-trips correctly with the v2-shape spawner.
- **F-061-IMPL-5** — `is_special` widget switched from free-form `LineEdit` (per spec §F.2 / design.md D5) to fixed-enum `OptionButton` (`normal/boss/miniboss/elite`). Surfaced during smoke as a UX issue: free-form was never used in any shipping map (audit: only `True/False` values pre-migration → only `"normal"/"boss"` post-migration), and runtime collapses everything via `is_wave_special() -> bool` regardless. Trade-off: extensibility (new tag = code edit) vs daily friction (no typo'd tags, one-click selection). Localization keys `ui_wavesettings_is_special_{normal,boss,miniboss,elite}` added. Legacy free-form values still load — they display as "normal" with a `GameLogger.warn`, save normalizes only if user touches the dropdown.
- **F-061-IMPL-6** — Spawners tab removed from WaveSettings (4 → 3 tabs). The full kind/ref/timer edit form was over-engineered for actual designer flow — only `timer` was used, and editing it via per-spawner CRUD form is friction. Replaced with a single SpinBox `Spawn timer:` in SpawnerPalette (range 0..99, default 1, per-session non-persistent), applied to newly-placed spawners only. Existing spawners on loaded maps keep their original timer untouched. `WaveSettingsPanel.spawner_field_changed` signal removed. Affected files: `wave_settings_panel.gd` (-26 LOC), `editor_controller.gd` (-7 LOC, fixes some of F-061-IMPL-3 over-cap), `spawner_palette.gd` (+18 LOC), `input_dispatcher.gd` (+1 LOC). `spawners_section.gd` deleted (-270 LOC). Stale loc keys (`ui_spawner_form_*`, `ui_wavesettings_tab_spawners`) left in JSON for separate cleanup.
- **F-061-IMPL-7** — Dialogue triggers CRUD removed from Level tab (replaced with read-only preview). Никита authors triggers in tables (his preferred workflow); the editor only needs to show what's already on the map. New LevelSection: `ItemList` of summaries (`id · event → dialogue_id [wave N]`) + 5 read-only detail labels for the selected row. `WaveSettingsPanel.trigger_created/updated/deleted` signals removed. `EditorController.add/update/delete_dialogue_trigger` wrappers removed (no callers left). Affected files: `level_section.gd` (529 → 169 LOC), `wave_settings_panel.gd` (-12 LOC), `editor_controller.gd` (-25 LOC). `WaveEditorOps.add/update/delete_dialogue_trigger` static ops left in place — dormant, available for programmatic use (e.g. Никита's table → JSON converter, or a re-introduced editor in 064). Stale loc keys (`ui_trigger_btn_*`, `ui_trigger_condition_*`, `ui_trigger_validate_*`, `ui_trigger_dialogue_help*`, `ui_trigger_id_help*`, `ui_trigger_event_custom`, `ui_trigger_play_mode_*`) left in JSON for separate cleanup.

- **F-061-IMPL-9** — `spawner.amount`/`spawner.delay` schema fields removed by user request. Originally landed as schema-only fields with runtime warn-once and `(schema-only)` UI tag (Q-061-3 in spec); user clarified the feature was never asked for and the runtime never used the values. Schema stays at v3 — no version bump because the fields were additive (legacy v2/v3 maps that happen to have them serialized still load; the values are silently ignored on load and not re-serialized on save, so `amount`/`delay` keys naturally disappear from JSON on next save). Affected files: `level_data.gd` (-2 consts, -8 LOC migration loop, -7 LOC validate, -7 LOC `_deep_copy_spawners`, -2 LOC `_spawners_to_arr`, -2 LOC `_spawners_arr_to_dicts_with_default_timer`), `wave_editor_ops.gd` (-4 LOC `update_spawner` match arms), `tests/test_061_migration.gd` (-5 LOC invariant assertions), `data/maps/_schema.md` (schema table + spawner shape + migration bullets cleaned), `docs/FEATURES.md` (note adjusted), 061 `spec.md` / `plan.md` / `tasks.md` (refs stripped or marked Removed). Stale loc keys `ui_spawner_form_amount{,_schema_only}`, `ui_spawner_form_delay` removed; `ui_trigger_*` and `ui_wavesettings_tab_spawners` keys still pending cleanup chore.

- **F-061-IMPL-10** — Two changes in one finding:
  1. **`advance_mode = "timer_and_clear"` removed.** User clarified the mode was anti-fun: in the fast-player case it forces idle waiting on a cleared map; in the slow-player case it's equivalent to plain `clear`. Net distinguishing case (1) is strictly worse. `VALID_ADVANCE_MODES = ["timer", "clear"]` now. Migration converts legacy `"timer_and_clear"` waves to `"clear"` (closer in intent — "don't advance until enemies are dead"). `wave_controller` match-block reduced to two arms; `WaveSettingsPanel` OptionButton dropped to two items; loc key `ui_wavesettings_advance_timer_and_clear` removed.
  2. **Spawner timer instant-fire bug fixed.** With `timer=1` on a freshly-loaded level, the spawner fired before the player's first turn. Root cause: `godmode_setup._emit_initial_turn` synthesizes a `world_turn_ended` emit on level setup (so HUD shows "turn 1" immediately), and in editor playtest mode it can race `start_level` and arrive AFTER spawners are installed — eating the first tick. Fixed by snapshotting `TurnManager.current()` into `_wave_start_turn` at `_start_wave` and filtering emits where `turn == _wave_start_turn` in `_on_world_turn_ended`. Real player ticks always arrive on a higher turn (`TurnManager.advance()` increments before emitting), so this is a clean discriminator. Also handles wave-internal advances correctly (each new wave snapshots its own start turn).

  Affected files: `level_data.gd` (-1 LOC enum + migration arm `timer_and_clear → clear`), `wave_controller.gd` (-12 LOC `timer_and_clear` branch removed; +5 LOC `_wave_start_turn` snapshot + filter; doc comment for `_waiting_for_clear` simplified), `wave_section.gd` (-2 LOC OptionButton item), `localization/{en,ru}.json` (-1 key each), 061 `spec.md` (out-of-scope bullet added).

## Manual smoke checklist (for reviewer)

Φ-0..Φ-3 + Φ-9..Φ-11 are code-only and don't require manual smoke beyond the section below. Φ-12 backward-compat is the critical batch — Python dry-run already passed (commit `290c100`); Godot smoke is needed for the save+reload roundtrip.

### Auto-tests added (`tests/`)

Two non-UI smokes are now automated. Run before manual pass:

- `godot --headless --script tests/test_061_migration.gd` — exercises Φ-12 data-integrity invariants on every `data/maps/*.json` (load → migrate → JSON-roundtrip → assert idempotent + per-wave shape + `validate()` clean). Mirrors the editor save+reload path 1:1.
- `python3 tests/check_localization_keys.py` — verifies every `ui_*` key referenced in code is present and non-empty in both `en.json` and `ru.json`. Caught two 061-introduced misses (`ui_wave_panel_skill_offer{,_preview}` — fixed); 10 pre-existing misses recorded in `tests/localization_baseline.txt` and tracked as F-061-3 in `docs/tech-debt.md`.

Both should print `OK` and exit 0 on this branch. See `tests/README.md` for the convention.

### Φ-12 — backward-compat (UI-side, manual)

Data-integrity covered by `test_061_migration.gd`. What still needs eyeballs:

- [ ] `data/maps/1.json` opens in editor without errors in console; switcher shows the right number of waves; save → JSON on disk is human-readable and not byte-identical churn. (UI part of T-061-74)
- [ ] `data/maps/sample_skill_offer.json`: wave 2's `is_special` field shows `"boss"` in the wave-section UI (post-migration display). Skill_offer per-wave UI works on switching. (UI part of T-061-75)
- [ ] `data/maps/story_map_03.json`: switcher works across multi-wave; triggers (if any) appear in Level section + wave-mirror. (UI part of T-061-76)
- [ ] Playtest each v2 map after save-as-v3 — same behaviour vs v2 (one seed → identical event order). **Auto-tests can't verify runtime behaviour.** (T-061-77)

### Φ-3 — runtime advance_mode

- [ ] Author a wave with `advance_mode: "clear"` and an enemy spawner. Playtest. Don't kill the enemy → wave does not advance. Kill it → advances. (T-061-26)
- [ ] Same with `"timer_and_clear"`. Wait until timer expires → `(waiting for clear)` label appears below the wave cursor → kill enemy → advances.

### Φ-4..Φ-8 — panel UX

- [ ] Open level editor (Ctrl+E). Right-side `Wave Settings` panel renders with all six sections. (T-061-69)
- [ ] Switcher: + Wave appends, Copy from prev clones (no spawners), Delete removes selected (≥2 waves required). (T-061-71)
- [ ] Wave 0: respawn_player row hidden. Wave 1+: visible, default off. (T-061-41)
- [ ] Trigger CRUD: Add → form → Save → row appears. Empty id → red error under form. Duplicate id → error.

### Φ-11 — localization (UI-side, manual)

Key-presence covered by `check_localization_keys.py`. What still needs eyeballs:

- [ ] Switch ru ↔ en via the in-game toggle. All Wave Settings labels render in both languages without overflow or layout breakage. (T-061-73)

## File caps

| File | Cap | Actual | Note |
|---|---|---|---|
| `editor_controller.gd` | 350 (AC33; bumped from 300) | 398 | F-061-IMPL-3 — 48 over; static-ops architecture preserved |
| `wave_settings_panel.gd` | 600 (soft, F-061-6) | 1380 | F-061-IMPL-2 — extraction deferred |
| `wave_editor_ops.gd` (new) | n/a | 204 | RefCounted static-methods module |
| `level_data.gd` | n/a | 708 (was 588) | +130 for v3 schema + migration |
| `wave_controller.gd` | n/a | 565 (was 539) | +26 for advance_mode gate |

## Breaking notes

- **Schema bump.** Files saved by editor are now v3. v1 / v2 are read-compatible (forward migration). External tools that hand-write maps need to either (a) keep emitting v2 and let the loader migrate, or (b) emit v3 directly per the updated `_schema.md`.
- **`is_special` type change.** Any consumer doing `bool(w.get("is_special", false))` is broken post-migration. Audited the codebase — three call sites fixed in commit `dbb8da3`. New code should use `_level.is_wave_special(idx)`.
- **Deprecated panels removed during 060 stay removed.** `wave_panel.gd` and `dialogue_trigger_panel.gd` content was ported into `wave_settings_panel.gd`; signals named differently (`wave_field_changed` vs `turns_to_next_changed`, etc.).

## Open questions

1. **F-061-IMPL-2** — keep `wave_settings_panel.gd` monolithic at ~1380 LOC, or extract trigger CRUD to its own panel/section script for the next pass? Argues for extraction: easier to test isolated. Argues against: glue cost vs the monolithic refresh-guard pattern.
2. **F-061-IMPL-3** — accept 398 LOC in `editor_controller.gd` (current state) or escalate `WaveEditorOps` to a stateful Node-child that owns panel/overlay refs and pushes the controller back under cap? Cap is documented "hard" but plan AC33 itself acknowledged the YAGNI.
3. **Music config UX** — currently a single-line raw-JSON `LineEdit`. Workable for designers comfortable with JSON, but Egor & Stasyan may prefer structured form fields. Defer to 062 polish.
