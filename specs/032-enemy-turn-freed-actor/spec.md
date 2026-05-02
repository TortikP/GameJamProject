# 032 — Enemy turn crashes on freed actor reference

**Owner:** Egor
**Touches:** `scripts/presentation/godmode/godmode_controller.gd` (only)
**Surfaced by:** spec 031 playtest (cooldowns now tick → real combat → kills mid-turn → bug becomes reachable on every wave).

## Symptom

Mid-`_run_enemy_turn`, Godot throws:

> Left operand of 'is' is a previously freed instance.

Stack: `godmode_controller.gd:943` (the `if not (actor is Actor)` check
inside Phase 1's `for actor in enemies:` loop).

## Root cause

`_run_enemy_turn` (godmode_controller.gd:933-964) snapshots `enemies` at
function start, then iterates twice (Phase 1: resolve, Phase 2: plan).
During Phase 1, an enemy's cast / DoT / counter-status can kill another
enemy in the same wave. Death path:

`Actor.take_damage` → `died` signal → `_on_actor_died` (line 834) →
`registry.unregister` + `actor.queue_free()` → at next `await`-yield the
node is actually freed → on the next loop iteration `actor` is a freed
reference. The `is` operator on a freed ObjectReference is a hard error
in Godot 4.

The existing `registry.get_actor(...) == null` guard (lines 946, 960) is
correct in intent but runs **after** the dereference, not before.

## Fix

Add `is_instance_valid(actor)` as the first check in both Phase 1
(line 942) and Phase 2 (line 956) loops — runs before `is`, before any
member access. Existing post-cast guards stay (they cover the "killed by
this iteration's own cast" case).

## Acceptance

- AC1: in a wave with ≥2 enemies + AoE / chain-damage skills, no
  "previously freed instance" errors during enemy turn.
- AC2: enemies dying mid-Phase-1 are silently skipped — neither their
  remaining Phase-1 actions nor their Phase-2 planning runs.
- AC3: surviving enemies still plan + cast normally on the same turn.

## Out of scope

- Refactoring `enemies` snapshot to use ids instead of refs (would be
  cleaner long-term but invasive — `is_instance_valid` is the 1-line
  jam-grade fix).
- Other potential freed-ref hot spots in the controller (none identified
  by `grep -n "for .* in registry\|for .* in .*enemies"` outside this
  function).
