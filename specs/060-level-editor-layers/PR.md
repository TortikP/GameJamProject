# Spec 060 — Level Editor: layers + palettes + delete legacy

Specs: [`spec.md`](./specs/060-level-editor-layers/spec.md), [`plan.md`](./specs/060-level-editor-layers/plan.md), [`tasks.md`](./specs/060-level-editor-layers/tasks.md), [`findings.md`](./specs/060-level-editor-layers/findings.md).

## Summary

- **Three-layer editor.** `LayersPanel` migrated from flat `BasePanel` to `TabbedBasePanel`; tabs are Hexes / Spawners / Objects with separate palettes. Each layer has its own selection, paint, and erase paths.
- **Q / W / E** picks layer directly; **Tab** cycles forward; **1..9** quick-selects items in the active palette; **Shift+RMB** cascades (erases tile + objects + spawners on a coord, no undo); **F1 / ?** opens a help modal listing every shortcut.
- **EditorController** is now a thin orchestrator; data I/O moved to `EditorIO`, the cold-start flow into `EditorStartup`, data-mutation primitives into `LevelMutations`. All four files stay under their per-file caps.
- **Game Editor handoff** restored: `Edit` from `game_editor.tscn` opens the new editor with the queued map; `Exit` returns to Game Editor instead of main menu when applicable. **Playtest** writes `__playtest__.json`, hands to godmode, and returns via Pause → Back to Editor.
- **Autosave** with 1.5s debounce; on relaunch within 24h, ConfirmModal asks whether to restore. Multi-wave maps loaded into the single-wave editor emit a warn toast (full wave editor is spec 061).
- **Legacy MapEditor deleted** atomically — 12 files (`map_editor.tscn` + 11 `.gd` panels/helpers totaling ~3.2k LOC), plus 70 orphan loc-keys and the `MapEditorButton` from main menu. Single button now: **Level Editor**.
- **`hex_grid.gd` binding fixed** (closes F-059-IMPL-4): `@export var tile_map_layer` → `@onready var tile_map_layer = $Terrain`. The 6-line workaround in `EditorController._ready` is gone.

## Diff

47 files, ~5.1k insertions, ~6.3k deletions. Net **−1213 LOC** despite four new palettes / overlays / VFX / startup-flow files.

## Findings (notable)

- **F-060-IMPL-1** — `panel_tab_bar.gd._set_active` `by_user` table: plan's mapping for lines 329 / 387 didn't match code locations. Resolved by spec's stated principle ("only on user click") — only line 242 (the click site) emits `by_user=true`. Detach / reattach / unregister side-effects do not. Doesn't affect 060 (LayersPanel doesn't use tear-off), but sets a precedent. **Andrey: confirm interpretation.**
- **F-060-IMPL-2** — Φ-6 cap pressure: extracted to **two** new sibling files (`level_mutations.gd` 45 lines, `editor_startup.gd` 87 lines) instead of pushing into `EditorIO` per T-060-43, because plan §Φ-2 explicitly excluded modal interaction from IO. Controller fits at 263/300 with margin. Two-helper extraction is the trade-off — alternative would be a single `editor_lifecycle.gd` collapse if you prefer.

## Manual smoke checklist (for reviewer)

These are the specs's own AC checklist (spec.md §7), one per acceptance criterion. None ran in CI — Godot is required.

### Φ-1..2 baseline
- [ ] `tabbed_panel_demo.tscn`: clicking tabs fires `active_tab_changed`; initial setup does not. (T-060-5)
- [ ] 059 cycle still works: paint → save → exit → load → paint visible. (T-060-13)

### Φ-3..4 layers + palettes
- [ ] Three tabs render; Hexes works as 059. (T-060-21)
- [ ] Spawners shows Player + 12 enemies; Objects shows 8 tile objects. ButtonGroup highlights single selection. First 9 buttons in each palette show digit overlay. (T-060-25)

### Φ-5 keyboard + cascade
- [ ] Q / W / E / Tab switch tabs (UI synced); 1-9 selects in active palette; Esc cancels drag; F1 opens help; Shift+RMB cascade. Q in level-name LineEdit types 'q' (no tab switch). (T-060-32)

### Φ-6 mutations + handoff
- [ ] Paint / erase work on all three layers. Cascade. Save / Load. (T-060-44)
- [ ] Game Editor → Edit (any map) → editor opens with the queued map → Exit returns to Game Editor.
- [ ] Playtest → ESC → Pause → Back to Editor returns to editor with same edits.
- [ ] Close without save → reopen → ConfirmModal → Restore loads `__autosave__.json`.

### Φ-7 VFX + help
- [ ] Erase any layer → 150ms red flash on coord. (T-060-47)
- [ ] F1 opens help with shortcut table. Esc / F1 close it.

### Φ-8 cross-refs
- [ ] Game Editor `Edit` opens `level_editor.tscn` (not legacy). Pause `Back to Editor` opens `level_editor.tscn`. (T-060-51)

### Φ-9 scene fixes
- [ ] No `tile_map_layer is null` errors on `level_editor.tscn` or `godmode.tscn` open. (T-060-55)
- [ ] Paint object → visible on overlay; ConfirmModal accessible. (T-060-57)

### Φ-10 deletion
- [ ] `grep -rln "map_editor" --include="*.gd" --include="*.tscn" .` returns nothing outside `docs/specs/`. (Verified by Claude during implementation.)
- [ ] Main menu shows single "Level Editor" button. Project compiles in Godot. (T-060-62)

### Φ-11 loc
- [ ] Switch ru ↔ en. All labels read in both languages (no raw keys). Help modal renders in both. Multi-wave warning toast in both. (T-060-67)

### Φ-12 final
- [ ] Big smoke per spec.md §7 complete (T-060-68).

## File caps

| File | Cap | Actual |
|---|---|---|
| `editor_controller.gd` | 300 (AC33) | 263 |
| `editor_io.gd` | 200 (AC34) | 174 |
| `input_dispatcher.gd` | 220 (AC35) | 213 |
| `layers_model.gd` | 120 (AC36) | 72 |

All within budget. Companion files: `editor_startup.gd` 87, `level_mutations.gd` 45, `palette_helpers.gd` 29, `delete_flash.gd` 40, `editor_help_modal.gd` 59, `spawner_palette.gd` 97, `object_palette.gd` 73, `layers_panel.gd` 77, `hex_tile_palette.gd` 122.

## Open questions

1. **F-060-IMPL-1** — leave `by_user=false` on detach / reattach / unregister, or flip to true? (Doesn't affect 060 behaviorally; sets precedent for future tear-off consumers.)
2. **F-060-IMPL-2** — keep two extracted files (`level_mutations.gd` + `editor_startup.gd`), or collapse into a single `editor_lifecycle.gd`?
