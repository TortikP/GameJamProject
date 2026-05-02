# 031 — Skill cooldown fix

**Owner:** Egor
**Touches:** `scripts/presentation/godmode/godmode_controller.gd`, `scripts/core/skills/skill.gd` (docstring only)

## Problem

Skills with `cooldown > 0` cast once and stay locked: `is_ready()` returns
`false` permanently after the first cast.

Root cause: `Actor.tick_skills()` is never called from any controller.
Cooldown is set on cast (`skill.gd:97`) and the per-skill `tick_cooldown`
helper exists, but no one drives it.

Statuses already use the right hook — `godmode_controller._on_world_turn_ended`
→ `_tick_all_statuses` (`godmode_controller.gd:885, 903–912`). Skills need
the symmetric hook.

## Fix

Mirror the status pattern. Add `_tick_all_skills()` in
`godmode_controller.gd`, call it from `_on_world_turn_ended` immediately
after `_tick_all_statuses()` and **before** the stun-skip branch — so a
stunned actor's cooldowns still tick.

Update the misleading docstring in `skill.gd:8–9` ("end of caster's turn —
clarified once TurnManager integrates") to match reality: ticked once per
round for all live actors at start of `_on_world_turn_ended`.

## Acceptance

- AC1: a skill with `cooldown=2` cast on turn N is `is_ready()==true` again
  on turn N+2 (verified manually in godmode F8 / arena).
- AC2: a stunned actor's cooldown still decrements while the stun-skip
  auto-advance fires.
- AC3: dead actors don't tick (skipped by `is_alive()` guard, mirroring
  statuses).
- AC4: no behavioural change to skills with `cooldown=0`.

## Out of scope

- Per-caster turn-end ticking (rejected — current TurnManager is round-based,
  one tick per `world_turn_ended` is correct).
- Ability-level cooldowns (Ability has none today; if added later it gets
  its own hook).
- Cooldown reset semantics (death, scene reload, meta-screens) — not part
  of this bug.

## Phase 2 — playtest follow-up: player cooldowns also broken

After phase-1 merge, playtest showed enemy cooldowns ticking but the
player's never decrementing. Same root cause shape, different surface:

- Enemies get their `_skills` populated by `enemy_data_loader.gd:65`
  (`actor.set_skills(skills)`).
- The player gets skills via the slot bar (`_seed_slots` for initial
  Q/W/E/R, `_on_ability_picker_selected` for RMB reassignment). Both
  paths put the Skill resource into `_slot_bar_node._slots` only —
  `player._skills` stays empty.
- `_tick_all_skills` calls `player.tick_skills(1)` → iterates an empty
  `_skills` Array → no-op. The Skill resource that the player actually
  casts (held by slot bar) never gets ticked.

### Phase 2 fix

New helper `_sync_player_skills_from_slots()` in `godmode_controller.gd`:
walks the slot bar, dedupes, calls `player.set_skills(...)`. Invoked
after both seed and RMB assignment. Slot bar remains the UI source of
truth; `Actor._skills` mirrors it for the tick path.

### Phase 2 acceptance

- AC5: after RMB-assigning a `cooldown>0` skill to a slot, casting and
  waiting `cooldown` rounds re-enables the slot.
- AC6: same skill in two slots ticks once (deduped), not twice.
- AC7: removing a skill from a slot (RMB → reassign to something else)
  drops it from `player._skills` — no zombie cooldowns ticking on
  resources nobody can cast.
