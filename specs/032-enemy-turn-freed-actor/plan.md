# 032 — Plan

Single file, two identical edits.

## File: `scripts/presentation/godmode/godmode_controller.gd`

### Edit 1 — Phase 1 loop (current line 942)

```diff
 for actor in enemies:
+    if not is_instance_valid(actor):
+        continue   # 032: freed mid-Phase-1 (killed by another enemy's cast/DoT)
     if not (actor is Actor):
         continue
     var enemy: Actor = actor
     if not enemy.is_alive() or registry.get_actor(enemy.actor_id) == null:
         continue
```

### Edit 2 — Phase 2 loop (current line 956)

Same pattern. By Phase 2 the array has the same staleness problem (in
fact more — a full Phase 1 worth of casts may have killed entries).

## Why not refactor the snapshot

A cleaner fix is to store `actor_id` strings instead of refs, then
`registry.get_actor(id)` per iteration — never holds stale refs. But:
- two snapshot sites (collector loop + both iter loops) to rewrite,
- forces an API shape choice on Phase 2 planner ctx,
- 72h jam, smoke-test of 031 is blocked now.

`is_instance_valid` is the minimum-surface unblock. Refactor — separate
PR if it ever gets prioritised.

## Tests

Manual: same wave that crashed (image 2 — bee + chickens, player with
tusk_attack/paw_suck). After fix, full wave plays without stopping the
debugger.
