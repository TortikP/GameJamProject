# 033 — Plan

Single file, single expression edit.

## File: `scripts/core/abilities/ability.gd`

Lines 110-113. Replace the current `exclude_caster` boolean with a
three-clause version that adds `not (eff_area is SelfArea)`. Update
the comment block above to spell out both clauses (a) self-targeted
and (b) area is a real zone.

No new imports — `SelfArea` is `class_name`-registered.

## Tasks

- [x] T01 — edit `Ability.cast` exclusion condition.
- [x] T02 — update comment.
- [ ] T03 — manual smoke: paw_suck heals player; verify zone-from-self
      ability (none in current data set, would need a custom test
      skill — skipped, AC1 + AC3 cover real shipped cases).
