# 037 — Player stun immunity (via per-actor status_immunities)

**Owner:** Egor
**Type:** Bugfix + small architectural addition
**Touches:**
- `scripts/core/actors/actor.gd` (new `status_immunities` field + add_status guard)
- `scenes/dev/player.tscn` (set `status_immunities = [&"stunned"]`)

## Problem

`stunned` status applies to the player. Player skips a turn, can't act. This is undesirable per gameplay direction — players shouldn't be locked out of their turn by enemy stuns. (Feared / enraged on player are also questionable but out of scope; this spec fixes stun specifically and lays the rails for the rest.)

## Why a per-actor immunity list (not a hardcoded `if team == "player"`)

Pillar 2 of CLAUDE.md (player–monster symmetry): monsters and player share the same `Actor` contract. A hardcoded "player can't be stunned" branch in `add_status` violates the symmetry: the implicit test "you should be able to take control of any enemy and play it as a character" breaks if half the rules check `team`.

A per-actor `status_immunities: Array[StringName]` is symmetric — both player and any enemy can declare immunities. Stasyan can later add `"immune_to": ["feared"]` to specific enemy JSONs (e.g. a boss immune to control) without touching code. Same field on player.tscn solves the bug.

## Why apply-side refusal (not auto-clear)

- Cheaper: one early-return in `add_status`, no per-tick logic.
- Visibility (pillar 1): the stun icon never appears on the player → the player sees their action choices unimpaired → no confusing "I'm stunned for one frame then not".
- Consistent with existing semantics: `add_status` is fire-and-forget (returns void), callers don't expect a result. Early-return is a no-op from the caller's POV.

Auto-clear was the user's fallback suggestion; it works but adds a tick-time check and a flicker. Apply-side refusal is strictly better here.

## Out of scope

- Status immunities sourced from `data/enemies/<id>.json`. Trivial follow-up (extend `EnemyDataLoader.apply_to_actor` to read `immune_to` field). Skipped here to keep the PR minimal — this PR adds the *mechanism*; data plumbing comes when Stasyan asks for it.
- "Resist" floater / VFX. The bug today is "player gets stunned"; making the refusal visible is a separate UX call.
- Other player immunities (feared, enraged, freeze, etc). Add via the same mechanism by editing player.tscn — no spec needed per immunity, this spec establishes the pattern.

## Acceptance criteria

- [ ] Casting a stun on the player has no effect — no icon, no skipped turn, no `is_stunned() == true`.
- [ ] Casting a stun on an enemy still works as before.
- [ ] `Actor.status_immunities` is an `@export Array[StringName]` defaulting to `[]`.
- [ ] `add_status` returns early (no on_apply, no statuses_changed, no EventBus emit) when the status is in `status_immunities`.
- [ ] A debug log line marks the refusal so Stasyan can spot when balance-tuning that an attack "did nothing" because of immunity.
- [ ] No regression in stun-on-enemy behavior (per spec 027 acceptance).
