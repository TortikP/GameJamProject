# 037 — Plan

## Step 1. Add `status_immunities` field to Actor

`scripts/core/actors/actor.gd`, in the `@export` block near `team`:

```gdscript
## Status ids this actor refuses to receive. Checked in add_status — listed
## ids never apply (no on_apply, no statuses_changed). Symmetric: player
## sets [&"stunned"] in player.tscn; enemies can opt out of feared/enraged/etc
## via their own scene or (future) JSON data.
@export var status_immunities: Array[StringName] = []
```

Ordering: keep alphabetic with surrounding fields, so place after `speed` / `damage_bonus`. Doesn't matter for behavior, just cleaner diff.

## Step 2. Guard `add_status`

Top of `Actor.add_status`, after the null-check, before mutual-exclusivity logic:

```gdscript
if instance.status_id in status_immunities:
    GameLogger.info("Actor", "%s immune to %s — refused" % [actor_id, instance.status_id])
    return
```

`info` not `warn` — this is expected behavior, not a problem. Stasyan will read it during balance tuning to confirm a control attack is being filtered.

Order matters: do this BEFORE the behavior-override removal block. Otherwise we'd remove an existing `feared` to make room for a `stunned` we're about to refuse — net negative.

## Step 3. Set on player.tscn

```
[node name="Player" type="Node2D"]
script = ExtResource("1_actor")
actor_id = &"player"
max_hp = 50
team = &"player"
speed = 2
status_immunities = Array[StringName]([&"stunned"])
```

`Array[StringName]([...])` is the .tscn syntax for typed arrays in Godot 4.6 — same form as elsewhere in the codebase (e.g. `_BEHAVIOR_OVERRIDE_IDS` initializer style is similar). Verify the editor actually accepts the literal — if Godot serializes differently after first save, accept the editor's version, that's fine.

## Risks

- **Existing applied stuns at the moment of merge.** A player already mid-stun at the time of code load isn't affected — `add_status` runs at apply time, not tick time. If Egor's running a session and applies the patch, an already-stunned player stays stunned until duration expires. Acceptable, no migration needed.
- **Skill cooldown / cost behavior.** A skill that stuns might still consume its cost on the caster (mana/cooldown) even though the stun is refused. That's correct — the cast happened; the target absorbed it via immunity. Same as casting damage on an invulnerable target: cooldown still ticks. Confirms with pillar 1 (visible mechanics): caster sees cooldown go up, target shows no status, → "my stun didn't stick". Clean.
- **Multi-target spells.** A stun-AOE that hits player + enemies: enemies get stunned, player doesn't. Each `add_status` call is per-target, the immunity short-circuits only the player one. No special handling needed.
- **Telegraph / intent display.** Enemy AI may have telegraphed "will stun player". After this fix the telegraph still appears (AI doesn't know about immunities), the cast resolves, the status is refused. Player sees the telegraph + a no-op resolution. Mild inconsistency. Acceptable for jam — fixing requires either teaching planner about immunities or adding a "resisted" UI cue, both bigger than this spec.

## Non-goals

- Don't extend `EnemyDataLoader` to read `immune_to` from JSON. Tempting because this is *exactly* the moment the data hook would be cheap, but: a) we don't need it yet, b) enemy JSONs don't have immunity entries today, c) the @export field can be set per-enemy in their scene if needed via the inspector. Add the JSON path when Stasyan asks for it.
- Don't add EventBus signal for "status refused". Local debug log is enough until we have a UI consumer.
