# 034 — Plan

## Architecture decision

Replan via EventBus signal on every successful `add_status`. Listener in
godmode_controller calls `EnemyAIPlanner.plan(actor, ctx)` and refreshes
telegraphs. Slowed runtime separately initialises `rt_flag=1` so the
immediate replan sees "held" and doesn't plan a move on apply turn.

No new method on Actor. No new method on StatusRuntime base. No mutation
of intents inside any runtime — `plan()` does the intent reset itself.

## Per-file changes

### `scripts/infrastructure/event_bus.gd`

Add one signal in the "Combat" section, near `actor_died`:

```gdscript
# 034: emitted by Actor.add_status after on_apply + statuses_changed.
# godmode_controller listens to replan affected enemy + refresh telegraphs
# so a freshly-applied control status takes effect on the very next
# world_turn_ended (not the one after).
signal actor_status_added(actor_id: StringName, status_id: StringName)
```

### `scripts/core/actors/actor.gd`

In `add_status`, after the existing `statuses_changed.emit(actor_id)`,
append:

```gdscript
EventBus.actor_status_added.emit(actor_id, instance.status_id)
```

That's the only change. `remove_status` is NOT wired (see spec §"Why this
shape"). No new fields, no new methods.

### `scripts/core/statuses/runtimes/slowed_runtime.gd`

Add `on_apply` that sets the flip-flop to "held" so the immediate replan
plans no move:

```gdscript
const _FLIP_HOLD: int = 1

# 034: rt_flag starts in HELD so the post-apply replan sees override_movement
# returning hold and plans no move on this turn. First tick toggles to 0
# (free) → next Phase 2 plans normally → flip-flop alternation continues.
# Without this, replan on apply would plan a move (rt_flag=0 means defer)
# and the next RESOLVE would move the actor — defeating slowed's first turn.
static func on_apply(_actor: Actor, instance: StatusInstance) -> void:
    if instance == null:
        return
    instance.rt_flag = _FLIP_HOLD
```

Update module docstring:
- Add a sentence noting that on_apply primes rt_flag=1 and that this
  collapses 027 §"Open after playtest" #7 (slowed AI 1-tick lag).

### `scripts/presentation/godmode/godmode_controller.gd`

Two changes.

**1. Subscribe + handler.** In `_ready` (where existing `EventBus.world_turn_ended`
connection lives, ~L174):

```gdscript
EventBus.actor_status_added.connect(_on_actor_status_added)
```

Handler near the other `_on_*` callbacks:

```gdscript
# 034: a freshly-applied status may invalidate the enemy's last-Phase-2 plan
# (e.g. rooted enemy can't move; feared enemy must kite; stunned enemy
# must skip). Replan immediately so the next world_turn_ended RESOLVE uses
# fresh intents reflecting the new constraints. Telegraphs refresh so the
# player sees the updated plan during their turn.
func _on_actor_status_added(actor_id: StringName, _status_id: StringName) -> void:
    var actor: Actor = registry.get_actor(actor_id)
    if actor == null or actor.team != &"enemy" or not actor.is_alive():
        return
    if _world_processing:
        # Mid-world-turn add (enemy A's cast applies status on B during
        # Phase 1 RESOLVE). Phase 2 PLAN runs for everyone at end of
        # _run_enemy_turn and overwrites all intents — replanning here
        # is redundant, and ctx is mid-flux.
        return
    EnemyAIPlanner.plan(actor, _world_ctx())
    _refresh_telegraphs()
```

**2. Cosmetic stun-skip timer.** Around L1089:

```gdscript
# was:
await get_tree().create_timer(GameSpeed.get_value("arena", "stun_skip_delay", 0.4)).timeout
# becomes:
await GameSpeed.wait("arena", "stun_skip_delay", 0.4)
```

## What we deliberately don't change

- **`Actor.add_status`** structurally — only the trailing emit added.
  Re-apply path (`on_remove` of old + `on_apply` of new) still works
  unchanged; the signal fires once at the end with the new status_id.
- **Phase 1 RESOLVE.** Still executes intents blindly; correctness comes
  from the replan having already nulled / re-set those intents.
- **Phase 2 PLAN.** Still runs at end of `_run_enemy_turn`. The replan
  listener does NOT replace it — they're complementary. Phase 2 handles
  status removals and inter-turn state changes; listener handles
  intra-turn additions.
- **`EnemyAIPlanner.plan()`.** No change. All status-aware logic is
  already there.
- **Other control runtimes (stunned/rooted/feared/enraged).** No
  on_apply changes for them — replan + their existing behavior_id swap
  / `is_stunned()` / `override_movement` already produces the right plan.
  Slowed is the only odd one (rt_flag init).

## Risks / what to eyeball

1. **Slowed re-apply with rt_flag preserved or reset?** Re-apply path:
   `add_status` calls `old_rt.on_remove(self, old)` (slowed has no
   `on_remove`, no-op), then `_statuses[id] = new_instance` — the **new**
   instance has fresh `rt_flag=0` from `StatusInstance` default, then
   our new `on_apply` sets it to 1. So re-apply resets to "held" again.
   Means: re-applying slowed mid-flip resets the flip-flop. That's
   defensible (re-apply == fresh effect) but worth noting.
2. **Listener fires during scene init.** Spawning an enemy with a
   pre-applied status would emit the signal before the enemy is fully
   wired. Listener bails on `registry.get_actor() == null` if the actor
   isn't registered yet, or replans normally if it is. Either is fine
   — no current code path applies statuses pre-spawn, but if Stasyan
   wires that into wave data later, the bail path covers it.
3. **Telegraph refresh during cast FSM (mid-step).** Player commits
   step 1 of a multi-ability skill that applies a status; FSM is in
   progress (`_cast_in_progress == true`) but that flag is for input
   gating, not world processing. `_world_processing` is false →
   listener replans → telegraph refreshes. Should be fine — telegraphs
   reflect enemy plans, independent of the player's cast FSM.
4. **`_world_ctx()` is built every replan.** Single Dictionary
   allocation per status apply. Negligible.
5. **`refresh_telegraphs()` work cost.** Iterates all enemies; for
   typical jam scenes (≤10 enemies) trivial. Big AoE that statuses
   many enemies → N refreshes (N status signals). Bounded; fine.

## Sequencing

1. Event signal (T1).
2. Actor emit (T2).
3. Slowed runtime rt_flag init (T3).
4. Controller subscribe + handler + cosmetic timer (T4 + T5).
5. Verify ACs in godmode manually.
6. Push, hand off PR URL.

All edits in one PR `egor/status-intent-lag → staging`.
