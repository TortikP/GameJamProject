# 029-feedback-polish — plan (pass 1)

> Spec: `spec.md`. Tasks: `tasks.md`.
> This plan covers the FIRST UX-improvement pass — the items Andrey shipped to Claude on Saturday morning. Subsequent passes will append their own plan-N.md or land as new specs (029a/b per OQ-3 in the spec).

## Scope of pass 1

Nine concrete UX changes (req-1..9 from the chat brief), all touching presentation. Two of them (req-5, sway helper) reach into core/infrastructure but the surface is small and additive — no public API breaks.

## Architecture decisions

### req-1, req-2 — slot lifecycle
- Single source of truth: `SlotBar.set_active(int)` — already supports `-1`. No new state, no new signal. `_seed_slots` stops pre-selecting; `_commit_cast` calls `activate(active)` (toggles off) after a successful `Skill.cast`.
- Failed casts (range/cooldown/no target) DO NOT deselect — player keeps the slot armed to retry, matching every roguelike RPG convention.

### req-3, req-4 — overlay redraw
- Rewrote `MoveRangeOverlay` and `CastRangeOverlay` from per-hex Polygon2D + Line2D node spawning to a single `_draw()` pass per overlay. Mirrors `scripts/presentation/dev/paint_preview.gd` (reused by spec 023 — the editor's brush preview).
- Move zone is the EXCEPTION: drawn as a single boundary contour (per-cell, draw edge IFF the neighbor on the other side is NOT in the zone). All other range layers (attack-range, AoE preview, cast-step) use per-hex thin outlines.
- Public method surface preserved (`setup`, `show_for`, `clear`, `show_zone_preview`, `show_range_for_ability`, `show_self_confirm`, `hide_range`) so godmode_controller wiring is untouched.
- Edge-to-neighbor-direction mapping (`_EDGE_NEIGHBOR_DIRS`) is a constant in `move_range_overlay.gd` derived from `HexGeometry.flat_top_polygon`'s vertex order. If the polygon order ever changes, this map must update — kept as one literal array, three lines to update.

### req-5 — AI uses full speed
- Movement policies (`approach_nearest_enemy`, `approach_specific_actor`, `follow_lowest_hp_ally`) now return a destination up to `actor.effective_speed()` hexes deep along the path, capped to never step ONTO the target's own hex. Returns `(-1,-1)` when `max_steps <= 0` (already adjacent).
- Kite policies (`kite_from_nearest_enemy`, `kite_specific_actor`) untouched. They use single-step neighbor scoring; multi-step kiting needs different math (best-N-step path search, not extending the existing logic). Out of scope for this pass.
- New plumbing in `HexGrid`: `move_actor_along(id, path)` walks a pre-computed path with per-step occupancy revalidation. Can't reuse `move_actor` because it re-pathfinds via `find_path` (no occupancy check) — for multi-step routes that could path through other live enemies.
- `_resolve_move_intent` now re-pathfinds with live actor blocks, then calls `move_actor_along`. Plan was made earlier this turn; other enemies have shifted since.

### req-6 — mob hover + AoE telegraph
- Hover tooltip: `_update_castability` already runs every `_process` and reads `coord_under_mouse`. Added `_refresh_intent_tooltip(hovered_id)` at the end. State-tracked via `_hover_intent_actor_id` so `show_tooltip` only fires on actor transitions.
- Tooltip body: `SkillFormatter.format_skill` — same helper PSP/inspector use. Single source of truth for skill rendering text.
- AoE shape: `_refresh_telegraphs` collects each intent's `ability.area.get_affected_hexes` and spawns secondary outline-only `TelegraphHex` for each affected coord not already a primary target. New `outline_only: bool` on `TelegraphHex` skips fill + damage label, draws thinner dimmer outline.

### req-7 — sway animation
- New static helper: `scripts/infrastructure/actor_motion.gd::apply_step_sway(actor, duration)`. Same preload pattern as `game_logger.gd` / `hex_geometry.gd` (no `class_name`, no autoload, explicit preload at consumers).
- Targets the convention-named `Body` Sprite2D child (player.tscn + manekin.tscn both have one). Fails silent if the convention isn't met — sway is purely cosmetic.
- Applied to `Body` (sprite child), NOT the actor Node2D, so `HealthBar` and `StatusIconStrip` (also actor children) stay anchored. No coupling with the actor's own position tween.
- Animation: 4 chained SINE quarter-cycles (right → 0 → left → 0). Synthesized via tween chain — no `tween_method` overhead.

### req-8 — space background shader
- New shader `scripts/presentation/space_background.gdshader` + scene `scenes/presentation/space_background.tscn` (CanvasLayer at layer=-10, full-screen ColorRect with the shader).
- Polar coordinates around screen center; rays = softened sin wave across angular position drifting in TIME. Radial fade darkens center (so the hex grid sits over the calmest area) and lifts edges (so rays sweep into vignette).
- Layer = -10 ensures it renders behind the world (default canvas layer is 0). HUD CanvasLayers (positive layer) stay on top.

### req-9 — CRT tweaks
- Defaults pass on `crt.gdshader`. No new uniforms, no removed uniforms.
- Aperture mask rotated from `mod(FRAGCOORD.x, 3.0)` to `mod(FRAGCOORD.y, 3.0)` → RGB-tinted bands run horizontally instead of vertically.
- All effect strengths dampened. `boost` reduced to compensate (less dimming → less recovery needed).
- `warm_tint` and `phosphor_glow` flipped from warm orange to cool blue. Variable names retained (`warm_*`) to avoid touching `CrtPostFx.set_param` call-sites — names are now misleading but the `set_param` API takes uniform names dynamically; renaming forces a sync edit nowhere else needs.
- Curvature and contrast untouched per Andrey's brief ("кроме выпуклости").

## Risk / out-of-scope

- Kite policies (req-5 carve-out) — should AI kiters also use full speed? Probably yes, but the math differs (multi-step retreat, not single-best-step). Not in this pass.
- Move-zone boundary detection assumes polygon vertex order from `HexGeometry.flat_top_polygon` is stable. If 022's hex shape rework re-shuffles vertices, `_EDGE_NEIGHBOR_DIRS` in `move_range_overlay.gd` needs sync.
- `move_actor_along` does NOT support entering a tile that triggers a state change preventing further movement (e.g. portal teleport). Existing `move_actor` doesn't either — same shape, parity for jam.
- `Body` node convention (req-7) is informal. New actor scenes that don't have a Sprite2D named `Body` will silently skip sway. Not enforced — just convention.

## Bonuses included

Three suggestions floated in the chat preamble — Andrey approved all three:

- **B1** active-slot perimeter outline: 2px FOCUS-yellow border swap on the slot's `normal` + `hover` styleboxes when active. Cached per-button at init (StyleBoxFlat instances are not shared per UiTheme convention), rebuilt on theme reload. Existing modulate-tint and scale-pop kept.
- **B2** hover-path-line preview: thin team-colored polyline through hex centers from heroine to the hovered hex, with a small disc at the destination. Path computed via `find_path_around` with live actor blocks (same set as zone occupied list — paths and boundary stay visually consistent). Capped to `effective_speed`. Cleared during cast FSM, AI turn, stun, or when hover is on player / unwalkable / occupied tile.
- **B3** breathing alpha on move-zone boundary: sine across `BREATH_PERIOD_S` (1.6 s), centered at high mid-alpha so the contour is always clearly visible. Implementation: `_process` advances phase + queue_redraws while a zone is shown.
