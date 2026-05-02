# 033 — SelfArea drops the caster from victims

**Owner:** Egor
**Touches:** `scripts/core/abilities/ability.gd` (one expression + comment)
**Surfaced by:** spec 031 phase-2 playtest — `paw_suck` (target=self,
area=self, effect=heal) failed every cast with log spam
`[Ability] self_heal_medium: no victims after caster exclusion`.

## Problem

`Ability.cast` excludes the caster from the victim list whenever the
ability is self-targeted (`primary == caster`). That rule was written
to prevent a self-cast zone-AoE (e.g. "blast wave around me") from
hitting the caster — sane.

But it fires unconditionally for ANY area when target=self, including
`SelfArea`, which by design returns exactly `[caster]`. So self-target
+ self-area → primary=caster → exclusion strips the only victim →
`victims.is_empty()` → cast returns false → log spam, no heal, skill
goes on cooldown for nothing (well, no — `cast()` returns false so
`Skill.cast` doesn't set cd; but the user-visible bug is "ability does
nothing").

This breaks the entire self-buff/self-heal class — `paw_suck`,
`under_desk_jump` (same shape), and any future self-only ability.

## Fix

Tighten the exclusion condition: skip when the area is `SelfArea`. The
area itself is the right authority on whether the caster belongs in
its victim set — `SelfArea` says "yes, only the caster"; every other
area type says "the zone, minus the caster who fired the spell".

```gdscript
var exclude_caster: bool = (
    primary is Actor
    and (primary as Actor) == caster
    and not (eff_area is SelfArea)
)
```

## Why this over the alternatives

- **Egor's proposed direction** ("`area_self` guarantees only the
  player as target"): SelfArea already does this — it returns exactly
  `[caster]`. The fix has to be in the consumer (Ability.cast) that
  was overriding SelfArea's word. Moving the rule onto SelfArea
  itself (e.g. a virtual `excludes_caster() -> bool`) is conceptually
  cleaner but adds an interface point for one boolean and zero
  current alternative implementations. Reach for it when a second
  area-type wants the same opt-out.
- **Removing the caster-exclusion entirely**: would re-open the
  original problem (self-cast circle blast hits self). Not an option.

## Acceptance

- AC1: `paw_suck` cast on self heals the player by `heal: 14`,
  triggers `EventBus.ability_cast` with caster in `target_ids`, and
  logs `Ability paw_suck → self_heal_medium` (no "no victims" line).
- AC2: a hypothetical `target=self` + `area=zone_circle(r=2)` ability
  still excludes the caster from its own blast (regression check on
  the original rule).
- AC3: `target=actor` + `area=zone_*` cast on an enemy still allows
  the caster to be inside the zone if geometry says so (friendly-fire
  unchanged).

## Out of scope

- New area types or any rebalance of existing self-skills.
- Migrating the rule onto AbilityArea as a virtual method.
