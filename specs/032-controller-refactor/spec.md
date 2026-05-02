# 032-controller-refactor — spec

**Owner:** Andrey.
**Status:** In-PR — implementation on `andrey/controller-refactor`. Manual editor validation (T29) pending Andrey before merge.

## Problem

`scripts/presentation/godmode/godmode_controller.gd` — **1420 lines.** It does:

- Scene setup (paint grid, place player, seed slots, wave controller wiring, level loader).
- Selection / inspector binding (`_select`, `_inspect_hex`, `_bind_hex_at`).
- Move-range overlay refresh (`_refresh_overlay`, `_refresh_hover_path`).
- Per-frame castability + AoE preview + hover-tooltip dispatch (`_update_castability`, `_refresh_intent_tooltip`).
- Player input handling (`_unhandled_input`, `_request_move`, `_request_cast_active`, `_wait_turn`, `_handle_cast_lmb`).
- Multi-step cast FSM (`_cast_slot`, `_begin_step`, `_commit_step`, `_commit_cast`, `_cancel_cast`, `_reset_cast_state`, `_is_self_step`).
- Manekin spawn / clear (`_spawn_manekin`, `_clear_manekins`, `_replan_all_and_refresh`, `_on_actor_died`, `_on_actor_died_for_selection`).
- Step animation (`_on_step_started`).
- AI driver (`_on_world_turn_ended`, `_run_enemy_turn`, `_resolve_move_intent`, `_resolve_cast_intent`, `_world_ctx`, `_tick_all_statuses`).
- Telegraph rendering (`_telegraph_tag_for_skill`, `_refresh_telegraphs`, `_clear_all_telegraphs`, `_enemy_attack_damage`).
- Right-click ability picker popup (`_build_ability_picker`, `_on_slot_right_clicked`, `_on_ability_picker_selected`).

For comparison: `scripts/presentation/dev/map_editor_controller.gd` is **1434 lines** with similar shape — same refactor logic likely applies there too, but out of scope here unless cheap.

**Symptoms:**
- Editing one feature (slot deselect on cast) requires reading 200 lines of unrelated context to be sure nothing breaks.
- Bugs from earlier in this session (e.g. `_refresh_intent_tooltip` call landed inside `_refresh_hover_path`'s body during a `str_replace`) are made possible by the file being too long to hold in context.
- Move-range overlay rendering bug Andrey reported on 2026-05-02 — root cause hard to isolate because the controller and the overlay both span hundreds of lines and many state-management paths.

## Proposed split

Each module is a **`Node` child of `GodmodeController`** in the godmode scene tree (not a RefCounted, not an autoload). Reasons: lifecycle managed by the tree, easy to inspect at runtime, signals connect naturally, no `_ready` order surprises if children are listed in the right scene order.

```
GodmodeController (slim orchestrator, ~150 lines target)
├── GodmodeSetup           — _ready setup chain, level loading, player placement, slot seeding
├── GodmodeInput           — _unhandled_input, action dispatch (delegates to siblings)
├── CastFsm                — multi-step cast state machine
├── AiDriver               — _on_world_turn_ended, _run_enemy_turn, resolve helpers
├── TelegraphRenderer      — _refresh_telegraphs, AoE shape outlines, intent arrows
├── HoverDispatcher        — per-frame hover-path, hover-tooltip, AoE preview, castability tints
├── ManekinSpawner         — F1/F2 sandbox spawn + clear
└── StepAnimator           — _on_step_started → position tween + ActorMotion sway
```

Sizes targeted: **150–300 lines each.** If a module hits 400, it's wrong — split further.

**Communication rules (non-negotiable):**
- Modules read shared state (player, grid, registry, slot_bar) from the controller via `@export` NodePath references resolved in their own `_ready`. No global lookups.
- Cross-module signaling goes through EventBus where it crosses a "this is a meaningful event" line (cast started, turn ended). Direct method calls only when one module is a known dependency of another (e.g. CastFsm → TelegraphRenderer.clear() on cast start).
- The controller itself holds NO game logic. It only resolves nodes and bridges the few signals that need cross-tree wiring.

**Modules NOT to extract:**
- `_select` / `_inspect_hex` / `_bind_hex_at` — selection logic is small, lives on controller as the "what is the user pointing at" facade. Inspector is a sibling, not a child.
- `_update_castability` slot-tint loop — moved into HoverDispatcher.

## Tileset consolidation (paired concern)

Currently TWO active tilesets:

| Path | tile_shape | tile_size | Atlases | Used by |
|---|---|---|---|---|
| `scenes/dev/godmode_terrain.tres` | 3 (HEXAGON) | 128×80 | godmode_atlas (forest only) | Procedural godmode sandbox (`_paint_grid`) |
| `scenes/arena/tilesets/hex_terrain.tres` | 2 (HALF_OFFSET_SQUARE) | 128×80 | hex_atlas + godmode_atlas | All editor-built levels (loaded via LevelLoader) |

**Mismatch:** `tile_shape` differs (3 vs 2). Even though both are 128×80 and `tile_offset_axis = 1`, Godot's `get_neighbor_cell` semantics for the `*_SIDE` enums diverge between shapes. This is the prime suspect for the move-range overlay bug — `_EDGE_NEIGHBOR_DIRS` mapping in `move_range_overlay.gd` was derived assuming HEXAGON; on HALF_OFFSET_SQUARE the neighbors returned for the same enum values may be off by one ring or shifted, producing a degenerate boundary contour.

**Goal:** ONE tileset.

**Decision needed (in next chat):** which shape to standardize on?

- **HEXAGON (3)** — the semantically correct shape for a hex game. Forces `hex_terrain.tres` to be re-saved with `tile_shape = 3`. Risk: changes neighbor topology for any custom level — re-validate that pathfinding still produces sane paths. Probably it does, since `_get_walkable_neighbours` already iterates `*_SIDE` enums that are valid for HEXAGON. Need to manually re-test in the editor that adjacency reads correctly.
- **HALF_OFFSET_SQUARE (2)** — keeps `hex_terrain.tres` as-is, forces `godmode_terrain.tres` to migrate. Less migration work for level files. But semantically wrong for a hex game, and the move-overlay bug stays.

Recommendation: **HEXAGON**. Migrate `hex_terrain.tres` and update CLAUDE.md's "Two tilesets exist" rule to "ONE tileset, hex_terrain.tres, tile_shape = HEXAGON".

After migration: `godmode_terrain.tres` is deleted. `_paint_grid` uses `hex_terrain.tres`'s grass tile (atlas 0, source 0, atlas_coord (0,0)) instead of the godmode-only forest atlas. CLAUDE.md "Two tilesets" rule rewritten.

## Acceptance criteria

1. `godmode_controller.gd` ≤ 300 lines, holds only orchestration.
2. Each new module under `scripts/presentation/godmode/` ≤ 300 lines.
3. No regression in: cast FSM, AI multi-step movement (req-5 from 029), slot lifecycle (req-1, req-2 from 029), telegraph rendering with AoE shape (req-6 from 029), sway (req-7), hover-tooltip + hover-path + breathing zone (029 + bonuses).
4. Single tileset in repo (`hex_terrain.tres`, tile_shape = HEXAGON). `godmode_terrain.tres` and the orphaned atlas (if any) deleted.
5. Move-range overlay renders correctly on EVERY level (procedural godmode + every editor-built level). The bug Andrey reported on 2026-05-02 is closed by either (a) the tileset consolidation alone, or (b) a follow-up patch tracked here.

## Open questions (resolved 2026-05-02)

- ~~OQ-1: Is map_editor_controller.gd worth refactoring in the same pass?~~ → **No** (Andrey, 2026-05-02). Don't refactor what works — jam scope. The editor controller stays a god object for the duration of the jam; revisit post-jam if it actually causes problems.
- OQ-2: Should the Node-child modules be reusable across godmode AND arena_demo controllers? Probably not — godmode is a superset of arena_demo's needs and reuse would force premature abstraction. Keep godmode-specific for now; revisit if arena_demo gains the same complexity.
- ~~OQ-3: Tileset migration — atomic single PR, or migrate `_paint_grid` first then delete the old tres in a follow-up?~~ → **Atomic single PR** (Andrey, 2026-05-02). Safer (no half-state where some scenes reference the deleted file). Migration includes: (a) re-save `hex_terrain.tres` with `tile_shape = HEXAGON`, (b) update `_paint_grid` to use it, (c) delete `godmode_terrain.tres` and the orphaned godmode_atlas.png if no other consumers, (d) update CLAUDE.md "Two tilesets exist" rule. All in one PR.

## Out of scope

- Refactoring `move_range_overlay.gd` itself (it's 230 lines, fine).
- Refactoring `cast_range_overlay.gd` (140 lines, fine).
- Splitting EventBus (it's a flat signal hub, that's its job).
- New gameplay features. This is purely structural cleanup.

## Bugs noticed in passing (track here, fix during refactor or separately)

- **B-001 (CLOSED):** `_run_enemy_turn` Phase 2 loop iterated `enemies` array containing freed instances during multi-step movement through damaging tile effects. Already fixed in 029 (commit `749a954`) by `is_instance_valid(actor)` guards in both Phase 1 and Phase 2 loops. Verified to survive the refactor in T15 — guards present in `ai_driver.gd::_run_enemy_turn`.
- **B-002 (OPEN, deferred):** Console warns `GDScript::reload: The function "apply_label_kind()" is a static function but was called from an instance.` Origin: somewhere a consumer calls `UiTheme.apply_label_kind(...)` where `UiTheme` is the autoload INSTANCE rather than the script type. With autoload, both work but Godot 4.6 warns. Cosmetic; address by switching consumer to `const UiTheme = preload(...)` pattern (see CLAUDE.md trap on Logger). Out of scope for 032; track as separate cleanup.
- **B-003 (LIKELY CLOSED, pending validation):** Move-range overlay sometimes doesn't render. The 029 commit `749a954` rewrote `_draw_zone_outline` in `move_range_overlay.gd` to use geometric edge detection (probe `local_to_map(midpoint × 1.4)` instead of the `*_SIDE` enum table), making it shape-agnostic. With 032's tileset consolidation aligning everything on HEXAGON shape, both layers now agree on neighbour topology too. T29 validation in editor confirms — TBD by Andrey.
