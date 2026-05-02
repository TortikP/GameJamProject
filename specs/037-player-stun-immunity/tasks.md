# 037 — Tasks

## T-1. Add `status_immunities` @export to Actor
- [x] File: `scripts/core/actors/actor.gd`.
- [x] Add `@export var status_immunities: Array[StringName] = []` after the existing exports (near `damage_bonus`).
- [x] Doc-comment matches plan.md §1 wording.

## T-2. Guard `add_status` for immunities
- [x] File: `scripts/core/actors/actor.gd`.
- [x] Add early-return guard at the top of `add_status`, right after the null/empty-id check, BEFORE the `_BEHAVIOR_OVERRIDE_IDS` mutual-exclusivity block.
- [x] Use `GameLogger.info` (not warn — expected behavior).

## T-3. Set immunity on player.tscn
- [x] File: `scenes/dev/player.tscn`.
- [x] Add `status_immunities = Array[StringName]([&"stunned"])` on the root `Player` node.
- [x] Format: keep field next to `team` for readability. Editor may rewrite serialization on first save — accept whatever it produces.

## T-4. Smoke
- [ ] **(Egor)** Open godmode. Spawn a manekin/bear with a stunning skill (or `/stun` debug if it exists). Cast at player → confirm no `stunned` icon, no skipped turn.
- [ ] Cast same skill at another enemy (F1 spawned dummy) → enemy gets stunned as before.
- [ ] Quick check: rooted/feared/enraged still work on player (we didn't break anything else).
