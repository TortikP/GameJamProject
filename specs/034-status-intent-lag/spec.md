# 034 — Status-apply replan

**Owner:** Egor
**Upstream:** 027-status-effects (status runtime), 008-enemy-ai (intent contract).
**Touches:**
- `scripts/infrastructure/event_bus.gd` (new signal)
- `scripts/core/actors/actor.gd` (emit on add_status)
- `scripts/core/statuses/runtimes/slowed_runtime.gd` (rt_flag init)
- `scripts/presentation/godmode/godmode_controller.gd` (replan listener + cosmetic stun-skip timer)

## Problem

Control statuses (rooted, stunned, feared, enraged, slowed) don't take effect
on the turn they're applied. The enemy still moves and/or casts on the
**first** `world_turn_ended` after apply, despite carrying the status with
valid duration. Visible symptom Egor reported: enemy keeps moving on turn-1
of rooted.

### Why

Per-turn loop in `godmode_controller._on_world_turn_ended` (~L1071):

```
_tick_all_statuses()        # decrements duration; on_turn_start runs
_tick_all_skills()
(player stun-skip branch)
_run_enemy_turn():
  Phase 1 RESOLVE: each enemy executes its move_intent_coord / cast_intent
                   set during the PREVIOUS world_turn_ended Phase 2.
  Phase 2 PLAN:    EnemyAIPlanner.plan() — checks is_stunned(), runs
                   override_movement, sets fresh intents for next turn.
```

Player applies status during *their* turn — `Skill.cast` runs synchronously,
`StatusEffect.apply → Actor.add_status → runtime.on_apply` all complete
before `TurnManager.advance()`. By the time we hit `_on_world_turn_ended`,
the status is on the actor — but the actor's intents from last Phase 2
are still set. Phase 1 fires those stale intents.

Phase 2 then correctly accounts for the new status — but the move/cast
already happened.

### Behavior we want (per Egor)

When status changes the actor's available actions, the actor must
**recompute** its plan immediately, not just drop the stale intent. If a
rooted enemy can't move, it should try to cast from where it stands. If
a stunned enemy can do nothing, it skips. If a feared enemy now wants to
kite, it kites. If enraged charges source, it charges.

This is exactly what `EnemyAIPlanner.plan(actor, ctx)` does given current
state — so we re-call it on status apply.

## Fix

### 1. Replan signal

Add `EventBus.actor_status_added(actor_id: StringName, status_id: StringName)`.
`Actor.add_status` emits it after `on_apply` and `statuses_changed`, i.e.
once the status is fully bound into the actor. Symmetric naming with
existing `EventBus.actor_died`.

### 2. Listener in godmode_controller

```gdscript
func _on_actor_status_added(actor_id: StringName, _status_id: StringName) -> void:
    var actor: Actor = registry.get_actor(actor_id)
    if actor == null or actor.team != &"enemy" or not actor.is_alive():
        return
    if _world_processing:
        return  # mid-world-turn add (e.g. enemy A applies status on B during Phase 1)
                # Phase 2 PLAN runs at end of _run_enemy_turn anyway and overwrites
                # all intents — replanning here would be redundant work.
    EnemyAIPlanner.plan(actor, _world_ctx())
    _refresh_telegraphs()
```

`EnemyAIPlanner.plan()` already does what we want:
- resets `cast_intent = null` and `move_intent_coord = (-1,-1)` at start, so stale intents die unconditionally
- early-returns on `is_stunned()` (stunned actor's intents stay null → skip)
- runs `override_movement` for every active status (rooted/slowed return hold sentinel → no move plan)
- enriches ctx with `behavior_target_id` from feared/enraged source
- iterates scenario rules with the current `behavior_id` (fear/rage scenario already swapped in by the runtime's `on_apply`)

So the listener is one-line plumbing — all logic is already in plan().

### 3. Slowed flip-flop init

Slowed's `rt_flag` defaults to 0 (free) on a fresh `StatusInstance`. With the
replan happening immediately on apply, the planner sees `rt_flag=0` and
plans a normal move — meaning the apply turn would still end up with the
actor moving on the next RESOLVE. To preserve "first turn slowed = no
move", `slowed_runtime.on_apply` sets `instance.rt_flag = 1` (held).

Trace with d=4:

| step                      | rt_flag | dur | action |
|---------------------------|---------|-----|--------|
| apply (end of player turn)| 1 (set in on_apply) | 4 | replan: held, intent=null |
| W1 tick                   | 1→0     | 4→3 | Phase 1: nothing. Phase 2: free, plan move |
| W2 tick                   | 0→1     | 3→2 | Phase 1: W1 plan executes. **MOVES**. Phase 2: held |
| W3 tick                   | 1→0     | 2→1 | Phase 1: nothing. Phase 2: free, plan move |
| W4 tick                   | 0→1     | 1→0 (REMOVED) | Phase 1: W3 plan executes. **MOVES**. Phase 2: free (no slowed) |
| W5 tick                   | —       | —   | normal |

Net: slowed(d=4) → 2 movements at W2, W4. Apply turn (W1 RESOLVE) holds. ✓
This collapses 027 §"Open after playtest" #7.

### 4. Cosmetic stun-skip timer

`godmode_controller.gd:1089`:

```gdscript
# was:
await get_tree().create_timer(GameSpeed.get_value("arena", "stun_skip_delay", 0.4)).timeout
# becomes:
await GameSpeed.wait("arena", "stun_skip_delay", 0.4)
```

Same value, project-canonical helper. Per Egor's instruction, kept in this
PR.

## Why this shape (vs alternatives considered)

- **Replan at apply, not at every status_changed.** Removal (expire) is
  already handled correctly by Phase 2 PLAN at end of every world turn.
  Replanning on remove would actually break duration semantics — e.g.
  rooted(d=2) tick removes status on W2, replan would fire a move on W2
  RESOLVE, costing one rooted turn.
- **EventBus signal, not direct call from `Actor.add_status` to
  `EnemyAIPlanner`.** CLAUDE.md hard rule: cross-system communication
  goes through EventBus. Actor staying ignorant of AI is exactly the
  layering this rule protects.
- **Listener in godmode_controller, not in EnemyAIPlanner autoload.**
  Replanning needs `_refresh_telegraphs()` (presentation) and `_world_ctx`
  / `registry` / `grid` (controller-owned). Listener belongs where those
  live. EnemyAIPlanner stays a pure plan(actor, ctx) function.
- **No on_apply intent-clear hook.** `plan()` already nulls intents on
  entry. Adding a separate clear is redundant with the replan.

## Acceptance

- **AC1** — rooted-on-enemy: cast `rooted(d=2)` on a manekin moving toward
  the player. On the **next** `world_turn_ended`, manekin does not change
  hex. If manekin has a damage skill in melee range AND adjacent to player,
  it casts (rooted lets you swing in place). Otherwise no cast (skip).
  After d turns, expires; manekin resumes moving.
- **AC2** — stunned-on-enemy: cast `stunned(d=2)` on a manekin with a
  planned cast telegraphed at the player. On next `world_turn_ended`:
  telegraph cleared, no move, no cast. Repeats for d turns then expires.
- **AC3** — feared-on-enemy: cast `feared(d=3, source=player)` on a manekin
  that just planned `attack player`. Replan picks fear scenario
  (`policy_kite_specific_actor`). On next `world_turn_ended`: manekin moves
  AWAY from player, no attack. Until expire / source death.
- **AC4** — enraged-on-enemy with two-target test: spawn manekins A and B.
  A had planned `attack B`. Player casts `enraged(d=3)` on A with
  `source=player`. Replan picks enraged scenario. On next `world_turn_ended`:
  A moves toward player (or attacks if in range), ignores B. Until expire.
- **AC5** — slowed flip-flop preserved: cast `slowed(d=4)` on a manekin
  that just planned a move. On next `world_turn_ended`: manekin does not
  move (replan with `rt_flag=1` plans nothing). Subsequent ticks alternate
  per the table above. Expected total movements during d=4: 2.
- **AC6** — re-apply: re-applying any control status before expire fires
  the replan again with the refreshed instance (rt_flag back to its apply
  value for slowed; behavior_id stays / re-swapped for feared/enraged).
  Manekin's intents recomputed under current state.
- **AC7** — non-control statuses unchanged: cast `poisoned`, `burning`,
  `shielded`, `strong`, `weak`. Replan still fires (same listener), but
  plan() makes the same decision because none of these affect plan logic.
  No visible behavior regression. (Cost: one wasted plan per non-control
  apply — bounded, fine for jam.)
- **AC8** — replan skipped during world processing: enemy A's cast applies
  status on enemy B during Phase 1 RESOLVE (`_world_processing == true`).
  Listener bails. Phase 2 PLAN handles B normally. Verified by setting up
  an enemy with a status-applying skill targeting another enemy and
  watching logs (no extra "plan" log line during the resolve loop).
- **AC9** — player not affected: applying any status to player does not
  trigger replan (listener bails on `team != &"enemy"`). Player has no
  plan to refresh anyway.
- **AC10** — telegraph refresh: after applying any status to an enemy
  during the player's turn, the enemy's telegraph (cast or movement
  arrow) updates immediately to reflect the new plan. Verified visually
  in godmode.
- **AC11** — cosmetic: stun-skip uses `GameSpeed.wait("arena",
  "stun_skip_delay", 0.4)`. Same delay, same behavior.

## Out of scope

- **Replan on status remove.** See "Why this shape" above.
- **Batched telegraph refresh.** AoE that statuses N enemies fires N
  signals → N replans → N refreshes. Bounded cost, fine for jam. If a
  spike shows up at high enemy counts, defer the refresh to next process
  frame — separate task.
- **Stun(d=1) corner case.** Tick decrements 1→0 immediately, status
  removed before RESOLVE. Effectively no-op. Designer-side issue (use
  d≥2). Documented in 027; not enforced here.
- **Phase ordering (RESOLVE-first vs PLAN-first).** Status quo correct
  for 1-turn-ahead telegraph UX.
- **`actor_status_removed` EventBus signal.** Could be added later if a
  consumer needs it. Not used by this fix.
- **Player's own intent fields.** Player input is realtime, no intent
  buffer. Player stun/root handled at input-time elsewhere.
- **028 / 030 spec numbers** stay unallocated (gap).

## Risks

- If a future status's `on_apply` transitively calls `add_status` (e.g. a
  status that grafts another status onto the carrier), the EventBus
  signal fires twice and replan runs twice in one frame. Plan() is
  idempotent given fixed state — second replan computes the same intent.
  Wasted CPU only. None of the current 11 statuses do this.
- `_world_processing` guard is critical. Without it, an enemy applying a
  status on another enemy during Phase 1 RESOLVE would replan the target
  mid-loop, then Phase 2 PLAN would replan again, then Phase 1 RESOLVE
  for that target… wait no, Phase 1 already happened for that target.
  Still, guard avoids the redundant replan. If the guard ever silently
  flips false during world processing, replan storms become possible.
  Single owner of the flag (godmode_controller), low risk.

## Followup fixes (post-playtest 02.05)

First playtest of the replan-on-status-add fix surfaced three more bugs
that were latent before 034 (or before, but masked). Fixed in the same PR.

### F1 — feared scenario silently degraded to default_melee

**Symptom:** feared enemy chases and attacks the source instead of fleeing.

**Cause:** `BehaviorDatabase._build_scenario` rejected scenarios with empty
`rules` arrays (`"rules" must be non-empty array`). `feared.json` is
empty-rules-by-design (027 spec: feared не атакует). Loader returns null →
`EnemyAIPlanner.plan` falls back to `default_melee` → enemy approaches and
attacks. 027 AC-X8 was specced but never functional.

**Fix:** allow empty rules. Only reject if rules were *declared* but every
one failed to parse. `scripts/core/ai/behavior_database.gd:_build_scenario`.

**Touches:** `scripts/core/ai/behavior_database.gd`.

### F2 — enraged enemy uses ranged attack from distance

**Symptom:** enraged manekin (only skill: paper_jam, range 3) fires
paper_jam at the source from up to 3 hexes away, instead of charging in
to melee.

**Cause:** `data/ai_behaviors/enraged.json` rule has
`condition: {"kind": "always"}`. The rule fires regardless of distance;
`_target_in_skill_range` then accepts any skill whose range covers the
source, including ranged ones. No distance gate.

**Fix (option A from chat):** change condition to
`{"kind": "enemy_in_range", "distance": 1}`. Rule only fires when an
opposing actor is at distance 1; movement_policy `approach_specific_actor`
closes the distance until the gate opens. **Caveat:** the condition
checks any opposing-team actor at d=1, not specifically the source. If a
non-player neutral is at d=1 but the source player isn't, the rule still
fires and casts at the player from distance via the `specific_actor`
selector. Acceptable for jam scope (no neutrals on current maps); the
strict fix would be a `condition_specific_actor_in_range` class — out
of scope here, noted for post-jam.

**Touches:** `data/ai_behaviors/enraged.json`.

### F3 — duration display jumps 3 → 1, statuses with no expire never redraw

**Symptom (from screenshots 02.05):** paper_jam applies rooted(2) +
slowed(3); on the next world turn the slowed pill still shows "3", on
the turn after it jumps straight to "1". Enemies that received only
slowed (radius-2 ring, no rooted) keep showing "3" the whole time.

**Cause:** `Actor.tick_statuses_with_ctx` decrements `inst.duration` but
only calls `remove_status` (which emits `statuses_changed`) when a status
expires. Plain decrement → no signal → `StatusIconStrip` rebuild never
fires → display is stuck at the value from the last `add_status` /
`remove_status` event.

**Fix:** at end of `tick_statuses_with_ctx`, emit `statuses_changed` once
if any decrement happened AND no `to_remove` covered it (avoid
double-emit on expire turns). UI now refreshes every tick.

**Touches:** `scripts/core/actors/actor.gd`.

### Followup-fix acceptance

- **AC-F1**: Apply `feared(d=3)` to a manekin adjacent to the player
  (using `test_status_fear`). On next world turn the manekin steps AWAY
  from the player; no cast intent, no telegraph. Repeats until expire,
  then default behavior resumes. (Was: chased + attacked.)
- **AC-F2a**: Apply `enraged(d=3)` to a manekin at distance 3 from
  player (only skill: paper_jam, range 3). Manekin steps toward player
  on next world turn; does not cast paper_jam. Continues approaching
  each turn until adjacent, then casts paper_jam. (Was: cast paper_jam
  immediately from d=3.)
- **AC-F2b**: Apply `enraged(d=3)` to a manekin adjacent to player.
  Manekin casts paper_jam on next world turn. (Sanity-check: gate still
  opens at d=1.)
- **AC-F3a**: Cast `paper_jam` (rooted(2) + slowed(3) AoE). On the next
  world turn each affected enemy shows duration `1` for rooted and `2`
  for slowed (intermediate value visible). Turn after: rooted gone,
  slowed shows `1`.
- **AC-F3b**: Slowed-only enemy (outside root radius) shows `3 → 2 → 1`
  across consecutive world turns, then disappears.
- **AC-F3c**: No double-rebuild of pill strip on expire turns (manual:
  inspect logs / expect no flicker).

### F4 — kite policies ignored actor.effective_speed()

**Symptom:** feared enemy with `speed=5` kites only 1 hex per turn.
The status reads as "barely working" — manekin runs, but slowly.

**Cause:** `PolicyKiteSpecificActor.pick_step` (and `PolicyKiteFromNearestEnemy.pick_step`)
iterate only the 6 immediate neighbours of the actor's current coord and
pick the best one. `actor.effective_speed()` is never read. Mismatch with
the approach policies, which were updated in 029/req-5 to walk up to
`effective_speed` along the shortest path.

**Fix:** use `HexGrid.reachable_within(my_coord, effective_speed, occupied)`
to enumerate every coord reachable within the speed budget; pick the one
that maximises distance from source (kite_specific) or from the nearest
opposing actor (kite_from_nearest). BFS yields candidates ring-by-ring,
so strict `>` comparison naturally takes the cheapest path among ties.
Resolver's existing `find_path_around` then walks the shortest path to
the chosen destination.

**Touches:** `scripts/core/ai/policies/policy_kite_specific_actor.gd`,
`scripts/core/ai/policies/policy_kite_from_nearest_enemy.gd`.

**AC-F4**: Spawn a manekin with `speed=5`, apply `feared(d=3, source=player)`.
On next world turn, manekin moves 5 hexes away from player (capped by
arena bounds / walls). No cast.

### F5 — multi-status syntax in JSON

**Need:** one effect dict applies several statuses in one go, instead of
splitting them across multiple ability stages or one effect-key per
status. Designer-side ergonomics — collapses paper_jam-style stacks.

**Format:**
```json
"effects": [{"status_id": "rooted(2), slowed(3)"}]
```

Backward-compatible — single-status legacy `"burning(2, 3, 1)"` has zero
top-level commas, splits to one element, parses as before.

**Implementation:** `AbilityDatabase._make_status_effect` (singular)
becomes `_make_status_effects` (plural, returns Array). New helper
`_split_top_level_commas(s)` does paren-depth-aware splitting so commas
inside `(2, 3, 1)` aren't mistaken for status separators. Each part
runs through the existing `_parse_status_string` + arity check; bad
parts log + drop, good parts append to the effect list.

**Touches:** `scripts/core/abilities/ability_database.gd`,
`data/skills/test_status_multi.json` (new — uses `"rooted(2), slowed(3)"`
in one effect for AC-F5 verification).

**AC-F5a**: Cast `test_status_multi` on a manekin. Manekin gains both
rooted and slowed, with correct durations (2 and 3). Both pills visible.
**AC-F5b**: Existing single-status JSONs (`paper_jam`, `ball_throw`,
`spores`, `curse`, `honey_cold`, `staple_shot`) parse and apply
unchanged.
**AC-F5c**: Malformed entry in the list (e.g. `"rooted(2), garbage(x)"`)
logs a warn for the bad part and applies the good one anyway.
