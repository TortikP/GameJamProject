# 034 — Plan + Tasks

## Files

- `scripts/core/skills/skill.gd` — `clone_for_owner()` method.
- `scripts/core/actors/actor.gd` — `get_skill_by_id(id)` helper.
- `scripts/core/actors/enemy_data_loader.gd` — clone per skill.
- `scripts/presentation/godmode/godmode_controller.gd` — clone in
  `_seed_slots`, get-or-clone helper for picker, actor-scoped lookup
  in `_resolve_cast_intent`.
- `scripts/core/ai/enemy_ai_planner.gd` — actor-scoped lookup in
  `_try_fallback_skill`.
- `scripts/core/ai/conditions/condition_skill_ready.gd` — actor-scoped.

Total: 6 files, no new imports.

## Why shallow `duplicate()` and not deep

`Skill.abilities: Array[Ability]` — Abilities have no per-cast
persistent state across the public boundary. `last_target_ids` is read
synchronously immediately after `Ability.cast` inside `Skill.cast`,
single-threaded execution → no race. Sharing the Ability array between
all clones is correct (and saves memory on enemy waves).

If a future Ability subclass introduces stateful per-instance behaviour
that survives a single cast, switch this to `duplicate(true)` and
audit the new state.

## Tasks

- [x] T01 — `Skill.clone_for_owner()`.
- [x] T02 — `Actor.get_skill_by_id()`.
- [x] T03 — `enemy_data_loader`: clone per skill.
- [x] T04 — godmode `_seed_slots`: clone per slot.
- [x] T05 — godmode `_get_or_clone_player_skill` helper + use in picker.
- [x] T06 — godmode `_resolve_cast_intent`: actor-scoped lookup.
- [x] T07 — `enemy_ai_planner._try_fallback_skill`: actor-scoped.
- [x] T08 — `condition_skill_ready`: actor-scoped.
- [ ] T09 — manual smoke: 3-bee wave, watch sting cooldowns; player
      vs enemy with shared `tusk_attack`; two slots on same id.
