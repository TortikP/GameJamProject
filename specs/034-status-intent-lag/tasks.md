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

## Out

- No automated test files (repo has none).
- No changes to `Actor.add_status` beyond the trailing emit.
- No changes to `EnemyAIPlanner.plan()`.
- No `actor_status_removed` signal.
- No `on_apply` for stunned/rooted/feared/enraged (replan + existing
  swap/early-return covers them).
