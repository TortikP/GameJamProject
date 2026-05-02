# 031 — Plan

## Files

1. `scripts/presentation/godmode/godmode_controller.gd`
   - New private helper `_tick_all_skills()` (clone of `_tick_all_statuses`,
     no ctx — `Actor.tick_skills(by)` takes only an int).
   - One call site: `_on_world_turn_ended()`, on the line after
     `_tick_all_statuses()` (line 885 today).

2. `scripts/core/skills/skill.gd`
   - Docstring lines 8–9 only. Replace the "clarified once TurnManager
     integrates" hedge with the actual contract: ticked once per round
     by `godmode_controller._on_world_turn_ended` for every live actor.

## Order constraint

`_tick_all_skills()` must run **before** the `player.is_stunned()` branch
(godmode_controller.gd:890). Otherwise a stunned player's cooldowns freeze
for the duration of the stun — the bug we're fixing in a different shape.

## Order with statuses

Run `_tick_all_skills()` after `_tick_all_statuses()`. Reason: a DoT can
kill an actor mid-status-tick; ticking skills second means we re-check
`is_alive()` after that kill (free guard, identical to status helper's
own loop). No mechanical impact, just consistent.

## No new tests

Smoke check in godmode is enough for jam scope. AC1/AC2 are observable
in 30s of play with any cooldown skill.

## Links

- HANDOFF.md — no relevant section (cooldown ticking was never specced;
  this is the spec).
- spec 007, 021, 026 — Skill class evolution. None mention who calls
  `tick_cooldown`. This spec closes that gap.
