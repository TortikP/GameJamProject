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
