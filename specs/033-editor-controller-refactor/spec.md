# 033-editor-controller-refactor — spec

**Owner:** TBD (Andrey to claim or delegate).
**Status:** Spec-only. Plan + tasks deferred. Sister spec to `032-controller-refactor` (godmode_controller). Same problem shape, separate PR scope.

## Problem

`scripts/presentation/dev/map_editor_controller.gd` — **1434 lines, 82 functions.** Same "god object" smell as `godmode_controller.gd`. Categories of responsibilities (from a quick `grep ^func`):

- Node resolution + camera (_ready, _resolve, _center_camera).
- Input dispatch (_unhandled_input, _is_drag_paint_mode, _handle_key_event).
- Tool actions (_quick_select, _eyedropper, _perform_undo, _perform_redo).
- Paint primitives (_handle_lmb, _paint_at, _paint_one, _hex_disk, _update_paint_preview, _rect_cells, _finish_rect).
- Placement (_place_floor, _erase_floor, _place_object, _place_spawner).
- Erase (_handle_rmb, _execute_delete, _clear_pending_delete, _remove_object_at, _remove_spawner_at).
- Cell queries (_is_floor_painted, _has_object_at, _has_spawner_at, _spawner_at, _find_player_spawner).
- UX feedback (_emit_occupied_toast, _mark_dirty, _set_clean).
- Autosave / recovery (_do_autosave, _check_autosave_recovery).
- Level apply (_apply_level).
- Panel wiring (_wire_floor_palette, _wire_object_palette, _wire_meta_panel, _wire_tool_panel).
- Panel callbacks (_on_tool_changed, _on_brush_size_changed, _on_floor_tile_picked, _on_erase_picked, _on_tileset_changed, _on_replace_all_requested, _on_object_picked, _on_spawner_picked, _on_name_changed).
- Wave panel integration (~5 methods touching `_wave_panel`).
- More (~30 helpers I didn't enumerate).

## Proposed split

Same Node-child architecture as 032 (modules are children of `MapEditorController` in the editor scene tree, hold their own `@export` NodePath refs, communicate via direct calls or EventBus signals). Target ≤ 300 lines per module.

```
MapEditorController (slim orchestrator, ~150 lines)
├── EditorSetup           — _ready chain, _resolve, _center_camera, _check_autosave_recovery
├── EditorInput           — _unhandled_input, _handle_key_event, drag-mode arbitration
├── PaintEngine           — paint primitives (paint_at, paint_one, hex_disk, rect_cells, finish_rect, paint_preview update)
├── PlacementOps          — place_floor / erase_floor / place_object / place_spawner + their queries
├── ErasePipeline         — _handle_rmb, _execute_delete, pending-delete state, remove ops
├── DirtyAutosave         — _mark_dirty / _set_clean / _do_autosave / recovery toast
├── LevelIo               — _apply_level (load), serialize-on-save handoff to LevelSerializer
├── PanelWiring           — _wire_* + _on_* panel callbacks (palette, tool, meta, tileset, replace-all, name)
└── WaveEditorBridge      — wave_panel sync (_set_active_wave hooks, level.set_active_wave_index)
```

**Communication rules** — same as 032:
- Modules read shared state via `@export` NodePaths resolved in their own `_ready`. No global lookups.
- Cross-module calls only when one is a known dependency (e.g. PaintEngine → DirtyAutosave._mark_dirty).
- EventBus for genuine "this is a meaningful event" signaling that may grow more listeners later (e.g. `level_modified`, `tool_changed`).

## Tileset consolidation overlap

The single tileset target from spec 032 affects this controller too — `_on_tileset_changed` lets the editor swap between `godmode_terrain.tres` and `hex_terrain.tres`. After 032 there's only one tileset → this method becomes a no-op or is removed, and the `_wire_meta_panel` tileset selector can be hidden. **Track in 032's tasks list, not here** — 033 should land AFTER 032's tileset migration so we don't refactor a code path we're about to delete.

## Acceptance criteria

1. `map_editor_controller.gd` ≤ 300 lines, holds only orchestration.
2. Each new module under `scripts/presentation/dev/editor/` ≤ 300 lines.
3. No regression in: paint (single + brush + rect modes), erase, undo/redo, autosave + recovery, level load/save, palette wiring, wave panel integration, tile/object/spawner placement, dirty state.
4. Smoke test: open editor, paint a 5×5 grass arena with a wall, place player + 2 enemies, save, playtest, return to editor — all states preserved.

## Order of operations

1. Land 032 (godmode controller refactor + tileset consolidation).
2. Land 033 (this spec) — uses lessons from 032's split shape, possibly extracts shared helpers.

## Out of scope

- Wave editor internals (`scripts/presentation/dev/wave_panel.gd`) — different file, not bloated.
- New editor features.
- Tool palette UX changes.

## Open questions

- OQ-1: Should PaintEngine and PlacementOps be merged? They're closely coupled — paint always ends up calling place. If kept separate, the boundary is "primitive shape generation" vs "atomic cell write". Probably worth keeping separate for testability, but if PaintEngine ends up being just a thin shape-builder, merge.
- OQ-2: WaveEditorBridge module — is it big enough to justify a Node? Maybe ~50 lines. Could just be a method group on the controller. Decide during plan.md writing.
