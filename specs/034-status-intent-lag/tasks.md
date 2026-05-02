# 034 — Tasks

## Implementation

- [ ] **T1** — `scripts/infrastructure/event_bus.gd`:
  add `signal actor_status_added(actor_id: StringName, status_id: StringName)`
  in the Combat section near `actor_died`. Brief doc-comment referencing 034.
- [ ] **T2** — `scripts/core/actors/actor.gd`:
  in `add_status`, after `statuses_changed.emit(actor_id)`, append
  `EventBus.actor_status_added.emit(actor_id, instance.status_id)`. No
  other changes to Actor.
- [ ] **T3** — `scripts/core/statuses/runtimes/slowed_runtime.gd`:
  add `static func on_apply(_actor, instance)` that sets
  `instance.rt_flag = _FLIP_HOLD` (= 1). Update module docstring with
  one paragraph explaining the rt_flag-init reasoning and the collapse
  of 027 §"Open after playtest" #7.
- [ ] **T4** — `scripts/presentation/godmode/godmode_controller.gd`:
  - in `_ready`, near the existing `EventBus.world_turn_ended.connect(...)`
    line (~L174), add
    `EventBus.actor_status_added.connect(_on_actor_status_added)`.
  - add new method `_on_actor_status_added(actor_id, status_id)` per
    plan.md. Place near `_on_actor_died` (~L1023) for locality with
    other actor-event handlers.
- [ ] **T5** — `scripts/presentation/godmode/godmode_controller.gd`:
  swap the raw timer in `_on_world_turn_ended` stun-skip branch (~L1089)
  for `await GameSpeed.wait("arena", "stun_skip_delay", 0.4)`.

## Verification

Manual via godmode (no automated tests in repo).

- [ ] **T6** — Add a debug skill JSON if missing for AC1:
  `data/skills/test_status_root.json` — `rooted(2)` on actor target,
  range 5, tag `debuff`, cooldown 0. Skip if equivalent already exists.
  Same for slowed if needed (`test_status_slow.json` with `slowed(4)`).
  Stunned, feared, enraged should already have test skills from spec
  027 / spec 008 — grep `data/skills/` to verify.
- [ ] **T7** — Run AC1 (rooted): F1 spawn manekin, drag away from player,
  watch it plan move toward player; cast root from player. Manekin's
  telegraph arrow disappears, no move next world turn. Logs show:
  `add_status` → `EnemyAIPlanner.plan` (rooted active, hold).
- [ ] **T8** — Run AC2 (stunned): same setup but stun. Confirm no move,
  no cast, no telegraph next world turn.
- [ ] **T9** — Run AC3 (feared): apply fear, watch behavior_id swap log
  + replan log + telegraph showing kite-step on next world turn (manekin
  moves AWAY from player on first world_turn_ended after apply, not the
  second).
- [ ] **T10** — Run AC4 (enraged): spawn 2 manekins, one of them mid-attack
  on the other. Cast enraged on the attacker with source=player.
  Confirm replan retargets to player on the next world turn.
- [ ] **T11** — Run AC5 (slowed): cast slowed, count moves over d ticks.
  Expect (d/2) moves with apply-turn no-move.
- [ ] **T12** — Run AC6 (re-apply): cast same control status twice on a
  manekin in succession; confirm second apply also fires signal + replan.
- [ ] **T13** — Run AC7 (non-control): cast poisoned / burning / shielded
  on a moving manekin. Manekin still moves on next world turn (no
  regression). Replan log fires but plan output is unchanged.
- [ ] **T14** — Run AC8 (mid-world-turn add, manual): currently no
  enemy-to-enemy status skill exists. Either:
  - skip and verify by code inspection only, or
  - temporarily author a debug skill where one manekin's AI casts
    rooted on another and watch logs for absence of mid-loop replan
    (no `EnemyAIPlanner.plan` log lines between Phase 1 RESOLVE entries).
  Acceptable to skip if no skill in flight does this.
- [ ] **T15** — Run AC10 (telegraph refresh): visually verify telegraph
  hex / arrow updates immediately after cast. Test all of rooted,
  stunned, feared.

## PR

- [ ] **T16** — Push branch `egor/status-intent-lag` (already exists).
  Capture PR-create URL or use the compare URL from CLAUDE jam-instructions.
- [ ] **T17** — PR title: `034 — replan enemy on status apply`.
  PR body: link spec.md, list the verified ACs, note that 027 §"Open
  after playtest" #7 (slowed 1-tick lag) is collapsed by this fix.

## Followup tasks (post-playtest 02.05)

- [x] **F1** — `scripts/core/ai/behavior_database.gd:_build_scenario`:
  drop the empty-rules rejection. Continue parsing if `rules: []`. Only
  reject if rules were declared but every one failed to parse.
- [x] **F2** — `data/ai_behaviors/enraged.json`: change rule condition
  from `{"kind": "always"}` to
  `{"kind": "enemy_in_range", "distance": 1}`. Forces enraged to close
  to melee before swinging, even with a ranged skill in kit.
- [x] **F3** — `scripts/core/actors/actor.gd:tick_statuses_with_ctx`:
  emit `statuses_changed` at end of tick if any decrement happened AND
  `to_remove.is_empty()`. Avoids double-emit on expire turns. Forces
  pill-strip rebuild on plain decrement.

## Followup verification (Egor)

- [ ] **F4** — AC-F1 (feared kites away, no attack).
- [ ] **F5** — AC-F2a (enraged with range-3 skill approaches before
  casting; first cast lands only when adjacent).
- [ ] **F6** — AC-F2b (enraged adjacent → casts immediately).
- [ ] **F7** — AC-F3a/b/c (duration display shows every intermediate
  value; slowed-only stale bug gone).
- [x] **F8** — `scripts/core/ai/policies/policy_kite_specific_actor.gd`:
  swap 1-ring iteration for `HexGrid.reachable_within(my_coord, speed, occupied)`,
  pick coord that maximises distance from source. Strict `>` for BFS-order
  tiebreak (cheapest path among ties). (Bug F4.)
- [x] **F9** — `scripts/core/ai/policies/policy_kite_from_nearest_enemy.gd`:
  same change, score = min-distance to ANY opposing actor. Mirror of F8.
- [ ] **F10** — Manual: AC-F4 (feared manekin with `speed=5` kites 5
  hexes/turn from player).
- [x] **F11** — `scripts/core/abilities/ability_database.gd`: replace
  `_make_status_effect` (singular) with `_make_status_effects` (plural,
  returns Array). Add `_split_top_level_commas` paren-aware splitter.
  Caller in `_make_effects_from_dict` switches to `out.append_array(...)`.
  Backward-compatible (single-status JSONs unchanged).
- [x] **F12** — `data/skills/test_status_multi.json`: minimal test skill
  with `"status_id": "rooted(2), slowed(3)"` for AC-F5a manual run.
- [ ] **F13** — Manual: AC-F5a (cast test_status_multi → both statuses
  on target). AC-F5b (paper_jam still works). AC-F5c (garbled list logs
  bad part, applies good).

## Out

- No automated test files (repo has none).
- No changes to `Actor.add_status` beyond the trailing emit.
- No changes to `EnemyAIPlanner.plan()`.
- No `actor_status_removed` signal.
- No `on_apply` for stunned/rooted/feared/enraged (replan + existing
  swap/early-return covers them).
- No new `condition_specific_actor_in_range` (post-jam — see spec F2 caveat).
