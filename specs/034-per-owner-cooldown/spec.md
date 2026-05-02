# 034 — Per-owner skill cooldown isolation

**Owner:** Egor
**Touches:** `scripts/core/skills/skill.gd`, `scripts/core/actors/actor.gd`,
`scripts/core/actors/enemy_data_loader.gd`,
`scripts/presentation/godmode/godmode_controller.gd`,
`scripts/core/ai/enemy_ai_planner.gd`,
`scripts/core/ai/conditions/condition_skill_ready.gd`
**Surfaced by:** spec 031 playtest with multiple enemies sharing a skill,
and player + enemies sharing the same skill_id.

## Symptom

Cooldowns appear shared across every owner of a given skill_id:

- Three bees on screen, one casts `sting` (cooldown=1) → all three are
  on cooldown next round.
- Player casts `paw_suck` → if any enemy also has `paw_suck`, theirs
  is on cooldown too. Reverse holds.
- Per-round tick decrements once per actor that has the skill, so
  cooldowns expire faster than designed when N>1 owners are in play.

## Root cause

`Skill` is a Godot `Resource`. `SkillDatabase.get_skill(id)` returns one
shared instance from `_by_id`. `_cd_remaining` and `_skip_next_tick` live
on that single instance. Every code path that touches cooldown was
hitting the shared resource:

- **Enemy load:** `enemy_data_loader.gd:60-62` —
  `actor.set_skills([SkillDatabase.get_skill(...), ...])`. Two enemies
  of the same kind point at the same Skill object.
- **Player slots:** `_seed_slots` and `_on_ability_picker_selected` put
  the DB instance into the slot bar, then `_sync_player_skills_from_slots`
  mirrors it onto `player._skills`. Same object as the enemies own.
- **AI cast resolve** (`godmode_controller._resolve_cast_intent:1012`,
  `enemy_ai_planner._try_fallback_skill:251`): both did
  `SkillDatabase.get_skill(intent.skill_id).cast(...)` — writing
  cooldown state directly onto the DB instance.
- **AI ready check** (`condition_skill_ready.gd:16`): read `is_ready()`
  off the DB instance. Original docstring already flagged this:
  *"If/when actors get their own cooldown state, this condition needs
  to look up via actor.get_skills() instead."*

Net: `Skill._cd_remaining` is global per id, not per actor. `tick_skills`
on Actor A and Actor B both decrement the same field, so cooldowns
double-tick when N owners exist.

## Fix

Per-owner duplicates. The DB stays the read-only source of truth for
static skill data; each Actor gets a runtime copy with its own cd state.

1. **`Skill.clone_for_owner()`** — `duplicate()` (shallow, since `Ability`
   has no per-cast persistent state) + reset `_cd_remaining = 0` and
   `_skip_next_tick = false`. Use whenever an actor takes ownership.
2. **`Actor.get_skill_by_id(id)`** — id-keyed lookup over `_skills`.
   Used by every "is this actor's named skill ready" / "cast this
   actor's named skill" path.
3. **enemy_data_loader** — `clone_for_owner()` per skill before
   `actor.set_skills(...)`.
4. **godmode `_seed_slots`** — `clone_for_owner()` per slot.
5. **godmode `_on_ability_picker_selected`** — `_get_or_clone_player_skill`
   helper: reuse the player's existing duplicate of this id if present
   (so two slots holding the same skill share one cd — same spell, one
   cooldown), else mint a fresh clone from DB.
6. **godmode `_resolve_cast_intent`** — read via
   `enemy.get_skill_by_id(intent.skill_id)`, not DB.
7. **enemy_ai_planner `_try_fallback_skill`** — same.
8. **condition_skill_ready** — same.

Read-only DB lookups (telegraph tag classification, predicted_damage_to)
left alone — those don't mutate cd state.

## Acceptance

- AC1: with three identical enemies on screen, casting on enemy A puts
  *only* A on cooldown; B and C remain ready.
- AC2: player and enemy can independently use the same skill without
  affecting each other's cd.
- AC3: per-round tick decrements each owner's cd by 1 (not by N for an
  N-owner skill).
- AC4: dropping a slot's skill removes its duplicate from `player._skills`
  (existing phase-2 behaviour, regression check).
- AC5: assigning the same skill to two slots reuses the player's
  existing duplicate — one cd, both slots count it down together
  (single dedupe entry in `player._skills`).

## Out of scope

- Migrating Skill from Resource to per-owner data class (would remove
  the duplicate dance entirely; bigger refactor).
- Persisting cd across scene reload (currently each `_seed_slots`
  re-clones from DB → fresh state, which is the intended jam-scope
  behaviour for now).
- Sharing cd between actors of the same kind (was a possible design
  intent but the playtest report explicitly asks for per-actor cd).
