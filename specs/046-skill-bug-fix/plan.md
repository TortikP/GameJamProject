# 046 — Plan

## File-level changes

### `scripts/core/abilities/areas/zone_circle_area.gd`

`resolve()` — branch upfront on `radius < 0`:

```gdscript
var ordered_hexes: Array[Vector2i] = []
if radius < 0:
    ordered_hexes = grid.get_all_walkable_coords()
    if not center in ordered_hexes:
        ordered_hexes.append(center)   # safety: include primary even if non-walkable
else:
    # existing BFS layer-walk, unchanged
    ...
```

The actor-collection pass (lines 45–53) stays the same — it walks
`ordered_hexes` and pulls actors via `grid.get_actor_at` + `registry`.

`get_affected_hexes()` — same branch:

```gdscript
if radius < 0:
    var all_walk: Array[Vector2i] = grid.get_all_walkable_coords()
    if not center in all_walk:
        all_walk.append(center)
    return all_walk
```

(Previous code path uses `grid.reachable_within(center, radius, [])`,
which already returns `[]` for `max_steps <= 0` — that's why the overlay
was empty too. Branch covers both call sites.)

`apply_level(level)` untouched — `radius <= 1` guard already shields
`-1` from scaling.

### `scripts/core/abilities/ability.gd`

In `cast()`, after the `has_create` detection block, compute:

```gdscript
var target_requires_victims: bool = (target is ActorTarget) or (target is ObjectTarget)
```

Update both empty-victim bail-outs (current lines 117 and 138):

```gdscript
if victims.is_empty() and not has_create and target_requires_victims:
    GameLogger.info(...)
    return false
```

`exclude_caster` block (lines 127–137) is unchanged — caster strip still
runs whenever a non-`SelfArea` zone catches a self-target.

No other call sites read these guards.

## Why class-checks instead of a virtual method on `AbilityTarget`

A `requires_victims()` method would be more "object-oriented", but:
- Three out of five concrete targets are stubs or trivial; only
  `ActorTarget` and `ObjectTarget` need to return `true`.
- The check lives in exactly one consumer (`Ability.cast`), so there's
  no reuse benefit.
- Adding a base method means a default has to be picked, and either
  default surprises one subclass.

Direct `is`-checks match how `eff_area is SelfArea` is already used in
the same function (`ability.gd:131`).

## Test data

No new JSON. Existing `data/skills/burning_bear_hellshake.json` already
exercises both fixes (hex r=-1 + zone r=-1) — Phase 1 lights it up,
Phase 2 keeps it working when no actors are in the zone.

Manual playtest checklist in `tasks.md`.

## Risk

- Phase 1: scope is exactly one branch in two methods of one file;
  positive `radius` paths untouched.
- Phase 2: loosens a bail-out for three target types. The bail-out was
  a defensive guard, not a correctness invariant — `Ability.cast` is
  re-entrant-safe for empty victim lists (the per-victim for-loop is a
  no-op, and `EventBus.ability_cast.emit(..., target_ids=[])` was
  always reachable via the `has_create` exemption with no actors hit).
  No new state, no new races.

## Out of scope (recap from spec)

- ChainArea `radius < 0`.
- ZoneArc/Cone/Line stubs.
- New JSON flags on Target/Area.
