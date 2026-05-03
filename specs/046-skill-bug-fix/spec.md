# 046 — Skill bug fix (zone_circle radius=-1, target_self/hex empty-zone gate)

**Owner:** Egor
**Touches:** `scripts/core/abilities/areas/zone_circle_area.gd`,
`scripts/core/abilities/ability.gd`.

Two related bugs in the skill cast pipeline. Single PR.

---

## Phase 1 — `zone_circle.radius = -1` did nothing

### Problem

`burning_bear_hellshake` (`hex r=-1` + `zone_circle r=-1`) was supposed to be
an arena-wide hit. In practice it only damaged whoever stood exactly on the
clicked hex.

Cause: `zone_circle_area.gd:31` does `for _step in radius:`. In GDScript
`for x in -1` iterates 0 times. Net: the BFS layer-walk never expands past
`[center]`, so `ordered_hexes = [center]` and victims = whoever sits on
that one tile.

### Fix

Mirror the convention already established by `HexTarget.range = -1` and
`ActorTarget.range = -1` ("unrestricted" = entire walkable arena):
`grid.get_all_walkable_coords()` exists for exactly this case
(`hex_grid.gd:136`).

In `zone_circle_area.gd`:
- `resolve()`: if `radius < 0`, skip BFS and walk every walkable coord
  to collect actors.
- `get_affected_hexes()`: if `radius < 0`, return
  `grid.get_all_walkable_coords()` (with center prepended if missing) so
  the cast-range overlay paints the whole arena.

`apply_level(level)` is already correct — its `radius <= 1` guard means
infinite radius doesn't get scaled into something worse. No change.

### Acceptance

- AC1: `burning_bear_hellshake` cast on any hex deals damage to every
  alive actor in the arena (excluding caster only when `target=self`,
  unchanged exclusion rule from `ability.gd`).
- AC2: AoE preview overlay for `zone_circle.radius=-1` paints every
  walkable hex.
- AC3: `zone_circle.radius >= 0` paths unchanged (BFS still does the
  layer-walk, scaling still applies).

---

## Phase 2 — `target=self` + zone bailed when nobody else was in radius

### Problem

`Ability.cast` had two `victims.is_empty()` bail-outs (`ability.gd:117`
and `:138`) gated only by the `has_create` exception (041 carve-out for
hex-targeted Create effects). These guards ran regardless of the target
type.

For `target=self` + any non-`SelfArea` zone, the caster gets stripped
from `victims` by the `exclude_caster` block (line 127, by design — zones
shouldn't friendly-fire the caster). If no other actors sit in the zone,
the post-exclusion array is empty and the cast bails. Visible symptom:
self-cast AoE casts produced "no victims after caster exclusion" log
spam, no cooldown ticked, no audio fired.

The same logic was wrong for `target=hex` zones in principle — designer
picks a hex, the cast should commit on that hex regardless of whether
anyone happens to be in the resulting zone (cooldown burns, sound plays,
ground-effect-equivalent semantics — matches the `has_create` carve-out
already there for the same reason).

### Fix

Gate both empty-victim bail-outs on target type. Only `ActorTarget` and
`ObjectTarget` semantically require an actual victim. `SelfTarget`,
`HexTarget`, `DirectionTarget` describe a position/direction; the area
shape on top of them can resolve to zero victims and that's a valid
cast.

```gdscript
var target_requires_victims: bool = (target is ActorTarget) or (target is ObjectTarget)
...
if victims.is_empty() and not has_create and target_requires_victims:
    return false
...
if victims.is_empty() and not has_create and target_requires_victims:
    return false
```

Same `has_create` exception still wins where it applies — both gates
are now conjunctive: bail only if (empty AND not create AND
victim-requiring target type).

`SelfTarget` + `SelfArea` (`paw_suck` etc.) keeps working — that case
never hit the empty-victim path because `SelfArea.resolve` returns
`[caster]` and `exclude_caster=false` (per 031 phase 6's `not (eff_area
is SelfArea)` clause).

### Acceptance

- AC4: `target=self` + `zone_circle` cast with no other actors in the
  zone fires successfully — `EventBus.ability_cast` emits, skill cooldown
  ticks, no error log.
- AC5: `target=self` + `zone_circle` cast with actors in the zone hits
  them and excludes caster (031 phase 6 rule preserved).
- AC6: `target=hex` + `zone_circle` cast on an empty hex with no actors
  in the radius fires successfully (cooldown ticks).
- AC7: `target=actor` + zone with no victims still bails (existing
  designer safety net preserved).
- AC8: `target=hex` + `Create` on empty hex still works (041 path
  unaffected — gated independently via `has_create`).
- AC9: `paw_suck` (target=self + SelfArea + heal) still heals (031
  phase 6 regression check).

---

## Out of scope

- `ChainArea.radius < 0` — not requested. `chain_area.gd:39`'s
  `maxi(1, radius)` makes radius=-1 silently fall back to adjacency;
  separate behaviour, separate fix if ever needed.
- `ZoneArc/Cone/Line` — still P2/P3 stubs (`push_warning` only).
- New `allow_self` / `requires_victims` JSON flags — target type
  already encodes intent.
