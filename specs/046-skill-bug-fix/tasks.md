# 046 — Tasks

## Phase 1 — `zone_circle.radius = -1` = arena-wide

- [x] T1.1 — `zone_circle_area.gd::resolve()`: branch on `radius < 0`
      → use `grid.get_all_walkable_coords()`, ensure `center` included.
- [x] T1.2 — `zone_circle_area.gd::get_affected_hexes()`: same branch
      for the overlay path.
- [ ] T1.3 — Smoke: open `burning_bear_hellshake` skill in godmode,
      cast on a hex far from any actor — every alive enemy on the
      arena takes damage (AC1).
- [ ] T1.4 — Smoke: hover-preview shows the entire walkable arena
      tinted (AC2).
- [ ] T1.5 — Regression: existing radius=2 test
      (`test_combo_hex_circle_damage_status.json`) still hits only the
      2-step BFS layer (AC3).

## Phase 2 — gate empty-victim bail by target type

- [x] T2.1 — `ability.gd::cast()`: compute `target_requires_victims`
      after the `has_create` detection block.
- [x] T2.2 — Update both `if victims.is_empty() ...` bail-outs to
      `and target_requires_victims`.
- [ ] T2.3 — Smoke: `target=self` + `zone_circle` skill cast in an
      empty zone → no error log, cooldown ticks, audio fires (AC4).
- [ ] T2.4 — Smoke: `target=self` + `zone_circle` with one neighbour
      → neighbour takes damage, caster does not (AC5).
- [ ] T2.5 — Smoke: `target=hex` + `zone_circle` on an empty hex →
      cast commits, cooldown ticks (AC6).
- [ ] T2.6 — Regression: `target=actor` + zone with no actor reachable
      still bails (AC7) — confirm via existing actor-target skills.
- [ ] T2.7 — Regression: `paw_suck` still heals player (AC9).

## Wrap-up

- [ ] T3.1 — Single commit per phase, push to
      `egor/skill-bug-fix-046`.
- [ ] T3.2 — Capture PR-creation URL from `git push` stderr; hand to
      Egor.
