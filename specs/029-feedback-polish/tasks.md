# 029-feedback-polish — tasks (pass 1)

> All items below shipped on branch `andrey/029-feedback-polish` (PR pending Andrey's review). Spec: `spec.md`. Plan: `plan.md`.

## req-1: no default active ability

- [x] T01a — `GodmodeController._seed_slots`: replace `set_active(0)` with `set_active(-1)` + comment.

## req-2: deselect after successful cast

- [x] T02a — `GodmodeController._commit_cast`: after `Skill.cast(...)` returns true, call `_slot_bar_node.activate(active)` to toggle off + emit `slot_activated(-1)` (already wired to `_on_slot_activated` → updates PSP description).

## req-3: move zone outline (single boundary)

- [x] T03a — `MoveRangeOverlay`: rewrite `show_for` + `_draw` so move range is rendered as a single boundary outline around the whole reachable region (not per-hex). Include actor's own coord in the zone set so the contour closes around them.
- [x] T03b — Replace per-hex `Polygon2D` + `Line2D` allocations with a single `_draw()` pass; drop `_polys` array of nodes.
- [x] T03c — Add `_EDGE_NEIGHBOR_DIRS` constant mapping polygon edge index → `CELL_NEIGHBOR_*` enum, derived from `HexGeometry.flat_top_polygon` vertex order.

## req-4: cast/spell range — per-hex outlines (paint_preview style)

- [x] T04a — `CastRangeOverlay`: rewrite to draw per-hex thin outlines via `_draw()` instead of allocating `Polygon2D` + `Line2D` nodes per hex. Mirror `paint_preview.gd`.
- [x] T04b — Self-confirm step: keep a bolder closed-loop outline + faint fill on the single hex (reads as confirm prompt vs a field of outlines).
- [x] T04c — `MoveRangeOverlay`: switch attack-range layer (active slot's reach) and AoE preview to per-hex thin outlines too — same style as cast range, kept distinct via color (debuff orange vs control purple).

## req-5: mobs use full speed

- [x] T05a — `HexGrid.move_actor_along(id, path)`: walks pre-computed path with per-step occupancy revalidation. Same per-step signal contract as `move_actor` so the controller's tween hook fires identically per hex.
- [x] T05b — `policy_approach_nearest_enemy.pick_step`: return `path[mini(actor.effective_speed(), path.size() - 2)]` with guard for `max_steps <= 0` (already adjacent → hold).
- [x] T05c — `policy_approach_specific_actor.pick_step`: same change.
- [x] T05d — `policy_follow_lowest_hp_ally.pick_step`: same change.
- [x] T05e — `GodmodeController._resolve_move_intent`: re-pathfind with live actor blocks (build `blocked` from `registry.all()`), then call `grid.move_actor_along(...)` instead of `grid.move_actor(...)`.

## req-6: mob-hover tooltip + AoE telegraph shape

- [x] T06a — `TelegraphHex`: add `outline_only: bool` setter that skips fill + damage label and draws a thinner dimmer outline.
- [x] T06b — `GodmodeController._refresh_telegraphs`: collect each enemy intent's `ability.area.get_affected_hexes` into `area_coords` dict, then spawn secondary outline-only `TelegraphHex` for each affected coord NOT already a primary target.
- [x] T06c — `GodmodeController._update_castability`: at end, call `_refresh_intent_tooltip(target_id)`.
- [x] T06d — `GodmodeController._refresh_intent_tooltip(hovered_id)`: state-tracked dispatch (via `_hover_intent_actor_id`) — only re-renders on actor transitions. Title = `"<actor_id> → <skill_id>"`. Body = `SkillFormatter.format_skill(skill)`. Anchor = null (tooltip places near mouse pointer per `tooltip_panel.gd::_place_near`).

## req-7: subtle sway on movement

- [x] T07a — `scripts/infrastructure/actor_motion.gd::apply_step_sway(actor, duration)`: 4 chained SINE quarter-cycles (right → 0 → left → 0) at ±2 px on `Body` child sprite. Static helper, preload-only pattern.
- [x] T07b — `GodmodeController._on_step_started`: call `ActorMotion.apply_step_sway(actor, duration)` parallel to the position tween.
- [x] T07c — `ArenaDemoController._on_step_started`: same call (only PLAYER_ID matches; demo scene doesn't have AI).

## req-8: space background shader

- [x] T08a — `scripts/presentation/space_background.gdshader`: polar-coords sunburst shader with rotating rays, soft wedge edges, radial center fade, slight edge lift.
- [x] T08b — `scenes/presentation/space_background.tscn`: `CanvasLayer` at `layer = -10` with full-screen `ColorRect` + the shader as a `ShaderMaterial`.
- [x] T08c — `scenes/dev/godmode.tscn`: instance `SpaceBackground` as the first child of root `Godmode` Node2D.

## req-9: CRT shader tweaks

- [x] T09a — `crt.gdshader` aperture mask: change `mod(FRAGCOORD.x, 3.0)` → `mod(FRAGCOORD.y, 3.0)`. RGB bands now horizontal.
- [x] T09b — Aperture strength default 0.15 → 0.06.
- [x] T09c — Scanline strength default 0.30 → 0.15.
- [x] T09d — Chromatic aberration default 1.6 → 0.6.
- [x] T09e — Bloom strength default 0.55 → 0.20.
- [x] T09f — Vignette strength default 0.42 → 0.20.
- [x] T09g — Hum strength default 0.04 → 0.015.
- [x] T09h — Boost default 1.5 → 1.1 (compensates for less aggressive dimming chain).
- [x] T09i — `warm_tint` 1.18,1.04,0.78 → 0.85,0.95,1.15 (orange → cool blue).
- [x] T09j — `phosphor_glow` 0.030,0.018,0.008 → 0.008,0.018,0.030 (warm → blue).
- [x] T09k — `warm_strength` 0.28 → 0.18. (Variable name retained to avoid `set_param` call-site sync.)
- [x] T09l — Curvature, contrast: confirm untouched.

## Verify

- [ ] V01 — Smoke test in godmode: open the scene, confirm no slot is pre-selected (Q/W/E/R buttons all dim).
- [ ] V02 — Press Q to select slot 0 (debug_punch), LMB on a manekin → cast resolves, slot deselects automatically. Pressing Q again must rearm.
- [ ] V03 — Without a slot selected, the move zone reads as a single contour (not per-hex fill). Walk around a manekin — contour bends around it.
- [ ] V04 — With a slot selected, attack range shows per-hex thin outlines (orange). Hover an AoE ability over a target — purple per-hex outlines mark the affected zone.
- [ ] V05 — F1 spawn 3 manekins clustered far from player. End turn (SPACE) — manekins should each take their full speed of steps toward player in one phase, not one step at a time.
- [ ] V06 — Hover over a manekin that has a queued cast intent — tooltip shows skill id + body. Hover off — tooltip hides. Move between two manekins — tooltip retitles cleanly.
- [ ] V07 — Watch a manekin step — its sprite sways slightly side-to-side during motion. Health bar above it stays steady.
- [ ] V08 — Background of godmode scene shows a slow rotating sunburst, not flat gray. Center is darker than edges.
- [ ] V09 — F6 to enable CRT — RGB-tinted bands now run horizontally; tint reads cool blue, not warm orange. Curvature still pronounced; other effects subtle.
- [ ] V10 — Editor scenes (map_editor.tscn) still work — they don't use MoveRangeOverlay or CastRangeOverlay so no spillover, but verify nothing broke during the rewrites.

## Out of scope (explicit)

- Kite policies (req-5 carve-out — single-step neighbor scoring stays).
- Active slot perimeter outline (chat-preamble bonus, awaiting go/no-go).
- Hover-path-line preview (chat-preamble bonus).
- Pulsing alpha breathing on move-zone boundary (chat-preamble bonus).
- Audio direction (spec.md OQ-1 — separate question, separate pass).
- Death animations (spec.md Pillar 2 — likely 029a/b).
