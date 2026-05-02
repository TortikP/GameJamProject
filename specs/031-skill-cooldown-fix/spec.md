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

## Phase 3 — playtest follow-up: slot bar doesn't reflect cooldown

Even with phase-2 fix in, the slot bar didn't visually update during
cooldown — the numeric label froze on its first painted value, and the
slot stayed bright (looked castable) while actually on cooldown.

Two interlocking causes:

1. `Skill.can_apply` delegated to `abilities[0].can_apply` only, never
   checked `is_ready()`. So castability was always `true` while on cd.
2. `SlotBar.set_castable` had an early-return guard ("avoid redundant
   modulate writes") that fired when castability was unchanged. Since
   castability never flipped during cd (always `true` per #1), the
   guard skipped every per-frame refresh — including the cd-label
   redraw inside `_refresh_visual`.

### Phase 3 fix

- `Skill.can_apply`: add `is_ready()` to the chain. UI now greys out
  slots on cd; click attempts are rejected pre-FSM (also fixes the
  separate annoyance of casting starting the FSM only to fail at
  `Skill.cast`).
- `SlotBar.set_castable`: drop the early-return. 4 slots × ~60fps
  modulate writes is nothing.

### Phase 3 acceptance

- AC8: slot dims (TEXT_DIM) the moment its skill goes on cd.
- AC9: cd label counts down each round (4 → 3 → 2 → 1 → cleared).
- AC10: pressing a hotkey while on cd does nothing — no FSM enter,
  no log spam.

## Phase 4 — playtest follow-up: cooldown counts off by one

`cooldown=N` in JSON gave `N-1` rounds of skip — a `cooldown=1` skill
was castable on the very next round, contradicting the design intent
("cooldown of 1 means I sit out one round").

Cause: `TurnManager.advance()` emits `world_turn_ended` synchronously
inside the same call that closes the cast turn. `_on_world_turn_ended`
runs `_tick_all_skills` immediately. So the very next tick after
`Skill.cast` lands inside the cast turn itself, eating one of the
intended skip rounds.

### Phase 4 fix

Add `_skip_next_tick: bool` on `Skill`. Set on `cast()` whenever
`cooldown > 0`. `tick_cooldown` consumes the flag (clears it, returns
without decrementing) on its next invocation. After that the field is
back to default `false` and ticks normally.

Why a flag and not `_cd_remaining = cooldown + 1`: `_cd_remaining` is
read directly by the slot bar / status panel / formatter. With +1
the user would briefly see the wrong number during the
`ability_cast_delay` await window before the absorbing tick fires.
The flag keeps `_cd_remaining` in sync with the displayed value at
all times.

### Phase 4 acceptance

- AC11: `cooldown=1` skill cast on turn N is on cd for turn N and
  turn N+1; ready on turn N+2 (one round of actual skip).
- AC12: `cooldown=N` (any N≥1) gives exactly N rounds of unavailability.
- AC13: `cooldown=0` skill cast does NOT set the skip flag and stays
  ready (no behaviour change vs phase 1).
