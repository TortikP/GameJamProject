# 035 — ActorTarget should accept the caster

**Owner:** Egor
**Touches:** `scripts/core/abilities/targets/actor_target.gd` (one file)
**Surfaced by:** spec 031 playtest — abilities with `target.kind=actor`
couldn't be cast on the player (heals, buffs, self-targeted utility).

## Symptom

Any skill with `target.kind=actor` rejects the caster as a target. Even
when the caster's actor_id is supplied via `ctx["target_id"]`, `resolve`
returns `null` → cast fails silently before reaching the area/effect
chain.

## Root cause

`actor_target.gd:28-29` had a hard-coded:

```gdscript
if actor == caster:
    return null
```

…directly contradicting the file's own docstring at lines 9-11:

```
range:
  -1  = unrestricted (any alive actor)
   0  = self only
   1+ = within N path-steps of caster
```

`range = 0` ("self only") was never reachable — the only candidate
within 0 path steps is the caster, but the caster gets nulled out
unconditionally one block above the range check.

## Fix

Drop the unconditional reject. Add an explicit self-shortcut that
returns the caster before the path/range code runs (path lookups on
`coord → coord` are implementation-defined in `find_path`; we don't
want to depend on what they return).

```gdscript
if actor == caster:
    return actor   # any range >= 0 satisfies distance-to-self = 0
if range >= 0:
    # ... existing path-steps check (unchanged, never sees caster) ...
```

Update the docstring to match: range entries now say "(including caster)"
where applicable, and the closing line drops "never returns caster".

## Why no `allow_self: bool` flag

A boolean would add a new authoring axis with one more thing for
designers to remember. The existing `range` already encodes intent:

- `range=0` → only caster.
- `range>=1` → caster *and* anyone in range; the player who clicks an
  enemy still hits the enemy, the player who clicks themselves still
  hits themselves. Symmetric.

If a future skill explicitly *forbids* self-target despite `range>0`
(rare), add the flag then.

## Acceptance

- AC1: a `target=actor, range=0` ability resolves to caster when
  `ctx["target_id"]` is the caster's id.
- AC2: a `target=actor, range=1` heal cast on self lands on caster
  (was previously a silent no-op).
- AC3: enemies can still be targeted at any non-zero range exactly as
  before — no regression on attack-shaped skills.
- AC4: `target=actor, range=-1` accepts caster (matches updated docstring).

## Out of scope

- New skill data wiring `range=0` for self-buff variants — existing
  self-buffs use `target=self, area=self`. This fix unblocks
  `target=actor` shaped self-buffs only when designers want them.

## Tasks

- [x] T01 — drop unconditional caster rejection in `resolve`.
- [x] T02 — add self-shortcut.
- [x] T03 — update docstring (range table + return contract).
- [ ] T04 — manual smoke (defer to user — no current shipped skill
      uses this shape; verifies negative space).
