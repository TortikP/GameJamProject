# 031 — Tasks

All phases done unless flagged. Smoke tests are user-side — Claude can't
run Godot.

## Phase 1 — Cooldown ticking
- [x] T01 — `godmode_controller.gd`: `_tick_all_skills()` helper.
- [x] T02 — call from `_on_world_turn_ended` between statuses and stun-skip.
- [x] T03 — `skill.gd`: docstring update.
- [ ] T04 — manual smoke: cd>0 enemy skill cycles.

## Phase 2 — Player slot sync
- [x] T05 — `_sync_player_skills_from_slots()` helper.
- [x] T06 — call at end of `_seed_slots`.
- [x] T07 — call inside `_on_ability_picker_selected` after `set_slot`.

## Phase 3 — Slot bar UI reflects cd
- [x] T08 — `Skill.can_apply` adds `is_ready()` check.
- [x] T09 — `SlotBar.set_castable` drops early-return.

## Phase 4 — Off-by-one cooldown
- [x] T10 — `Skill._skip_next_tick` field.
- [x] T11 — `Skill.cast` sets flag when `cooldown > 0`.
- [x] T12 — `Skill.tick_cooldown` consumes flag on first tick after cast.
- [x] T13 — docstrings updated.

## Phase 5 — Freed-ref guard (was 032)
- [x] T14 — Phase-1 loop: `is_instance_valid(actor)` guard.
- [x] T15 — Phase-2 loop: same guard.

## Phase 6 — SelfArea keep caster (was 033)
- [x] T16 — `Ability.cast`: `not (eff_area is SelfArea)` in exclude condition.

## Phase 7 — Per-owner cd (was 034)
- [x] T17 — `Skill.clone_for_owner()`.
- [x] T18 — `Actor.get_skill_by_id()`.
- [x] T19 — `enemy_data_loader`: clone per skill.
- [x] T20 — `_seed_slots`: clone per slot.
- [x] T21 — `_get_or_clone_player_skill` helper + use in picker.
- [x] T22 — `_resolve_cast_intent`: actor-scoped lookup.
- [x] T23 — `enemy_ai_planner._try_fallback_skill`: actor-scoped.
- [x] T24 — `condition_skill_ready`: actor-scoped.

## Phase 8 — ActorTarget self-resolve (was 035)
- [x] T25 — drop unconditional caster rejection.
- [x] T26 — add self-shortcut.
- [x] T27 — docstring update.

## Phase 9 — `get_range_hexes` includes caster
- [x] T28 — seed BFS result with `[caster_coord]` for `range ≥ 1`.

## Phase 10 — `status` → `status_id`
- [x] T29 — `EFFECT_KIND_BY_KEY` / `EFFECT_KEY_ORDER` rename.
- [x] T30 — `_parse_effect_dict` handles new key + warns on legacy.
- [x] T31 — test JSONs updated.

## Phase 11 — Clear active slot on cast
- [x] T32 — `_commit_cast`: `set_active(-1)` after successful cast.

## Phase 12 — Idle preview clears on cast + shows only abilities[0]
- [x] T33 — reorder `_commit_cast`: `set_active(-1)` BEFORE `_refresh_overlay`.
- [x] T34 — `_refresh_overlay`: forward `abilities[0]` only, not the full list.

## Phase 13 — Zone preview tracks current ability
- [x] T35 — `_current_preview_ability()` helper.
- [x] T36 — `_update_castability` zone preview reads from helper (no more union).
- [x] T37 — `_refresh_overlay` reads from same helper (single source of truth, FSM-aware).

## Manual smoke (deferred to user)

- [ ] M1 — Wave with multiple identical enemies: cd is per-actor, not
  shared (Phase 7).
- [ ] M2 — Player can cast `target=actor, range≥1` skill on themselves
  by clicking own hex (Phase 8 + 9).
- [ ] M3 — `honey_cold` applies `slowed` to enemies in zone (Phase 10).
- [ ] M4 — After cast, no slot is highlighted; next LMB moves
  (Phase 11).
- [ ] M5 — Stun-skip doesn't freeze player cooldowns (Phase 1 regression).
