# 031 — Tasks

- [x] T01 — `godmode_controller.gd`: add `_tick_all_skills()` helper, mirroring `_tick_all_statuses()`.
- [x] T02 — `godmode_controller.gd`: call `_tick_all_skills()` in `_on_world_turn_ended()` between `_tick_all_statuses()` and the stun-skip branch.
- [x] T03 — `skill.gd`: update docstring lines 8–9 to reflect actual call site.
- [ ] T04 — manual smoke check in godmode (deferred to user — Claude can't run Godot).
- [ ] T05 — push branch, hand PR-creation URL to Egor.

## Phase 2 (playtest follow-up)

- [x] T06 — `godmode_controller.gd`: `_sync_player_skills_from_slots()` helper.
- [x] T07 — call helper at end of `_seed_slots()`.
- [x] T08 — call helper inside `_on_ability_picker_selected()` after `set_slot`.

## Phase 3 (playtest follow-up — UI)

- [x] T09 — `Skill.can_apply`: add `is_ready()` guard.
- [x] T10 — `SlotBar.set_castable`: drop early-return so cd label refreshes per frame.

## Phase 4 (playtest follow-up — semantics)

- [x] T11 — `Skill`: add `_skip_next_tick: bool` field.
- [x] T12 — `Skill.cast`: set flag when `cooldown > 0` and skill went on cd.
- [x] T13 — `Skill.tick_cooldown`: consume flag (return early without decrement) on first tick after cast.
- [x] T14 — docstrings updated to spell out the semantic.
