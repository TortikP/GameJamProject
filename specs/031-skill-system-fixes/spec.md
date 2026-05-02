# 031 — Skill system fixes

**Owner:** Egor
**Touches:** `scripts/core/skills/skill.gd`,
`scripts/core/actors/actor.gd`,
`scripts/core/actors/enemy_data_loader.gd`,
`scripts/core/abilities/ability.gd`,
`scripts/core/abilities/ability_database.gd`,
`scripts/core/abilities/targets/actor_target.gd`,
`scripts/core/ai/enemy_ai_planner.gd`,
`scripts/core/ai/conditions/condition_skill_ready.gd`,
`scripts/presentation/godmode/godmode_controller.gd`,
`scripts/presentation/slot_bar.gd`,
`data/skills/test_status_runtime.json`,
`data/skills/test_combo_multikey_effect.json`.

This spec absorbs what was originally split as 031-cooldown,
032-freed-actor, 033-self-area, 034-per-owner-cooldown, and
035-actor-target-allow-self. Single branch, single PR — folder
consolidation per Egor's request to keep spec/branch noise down.
Phases below run roughly in playtest-discovery order. In-code
comments still reference the original spec numbers (032/033/034/035)
for traceability — those are the same fixes, just folded under 031.

---

## Phase 1 — Cooldown ticking was never wired

### Problem
Skills with `cooldown > 0` cast once and stay locked: `is_ready()`
returns `false` permanently after the first cast. Root cause:
`Actor.tick_skills()` is never called from any controller. Cooldown is
set on cast (`skill.gd:97`) and the per-skill `tick_cooldown` helper
exists, but no one drives it.

### Fix
Mirror the status pattern (`_tick_all_statuses` already runs from
`_on_world_turn_ended`). Add `_tick_all_skills()` in
`godmode_controller.gd`, call it immediately after `_tick_all_statuses()`
and **before** the stun-skip branch — so a stunned actor's cooldowns
still tick.

### Acceptance
- AC1: `cooldown=2` cast on turn N is `is_ready()==true` again on turn N+2.
- AC2: stunned actor's cooldown still decrements during stun-skip.
- AC3: dead actors don't tick.
- AC4: `cooldown=0` skills unaffected.

---

## Phase 2 — Player cooldowns weren't ticking

### Problem
Phase-1 fix made enemy cooldowns work but player's still didn't.
Enemies get `_skills` populated by `enemy_data_loader.gd:65`. Player
gets skills via the slot bar — slot bar held the Skill resource but
`player._skills` stayed empty, so `_tick_all_skills(player)` iterated
nothing.

### Fix
New helper `_sync_player_skills_from_slots()` in `godmode_controller.gd`.
Walks slot bar contents, dedupes, calls `player.set_skills(...)`.
Invoked at end of `_seed_slots` and after every RMB slot reassign.

### Acceptance
- AC5: RMB-assigned skill cools down on player too.
- AC6: same skill in two slots ticks once (deduped).
- AC7: dropping a skill from a slot drops it from `player._skills`.

---

## Phase 3 — Slot bar didn't reflect cooldown

### Problem
Two interlocking causes:
1. `Skill.can_apply` delegated only to `abilities[0].can_apply` — never
   checked `is_ready()`. So slot castability was always `true` while
   on cd; slot didn't grey out.
2. `SlotBar.set_castable` had an early-return guard that fired when
   castability was unchanged. Since castability never flipped during
   cd (always `true` per #1), the guard skipped per-frame
   `_refresh_visual` calls — including the cd-label redraw — so
   labels froze on their first paint.

### Fix
- `Skill.can_apply`: `is_ready()` added to the chain.
- `SlotBar.set_castable`: drop the early-return.

### Acceptance
- AC8: slot dims the moment its skill goes on cd.
- AC9: cd label counts down each round (4 → 3 → 2 → 1 → cleared).
- AC10: pressing a hotkey while on cd does nothing — no FSM enter.

---

## Phase 4 — Cooldown counted off-by-one

### Problem
`cooldown=N` in JSON gave `N-1` rounds of skip. `cooldown=1` was
castable on the very next round, contradicting design intent.

Cause: `TurnManager.advance()` emits `world_turn_ended` synchronously
inside the same call that closes the cast turn, so the very next tick
after `Skill.cast` lands inside the cast turn itself.

### Fix
`Skill._skip_next_tick: bool`. Set on `cast()` whenever `cooldown > 0`.
`tick_cooldown` consumes the flag (clears, returns without decrementing)
on its next invocation.

Chosen over `_cd_remaining = cooldown + 1` so the displayed cd
(read directly by slot_bar / status_panel / formatter) matches the
design value at all times — no wrong number flashing during the
`ability_cast_delay` await window.

### Acceptance
- AC11: `cooldown=1` skill cast on turn N is on cd for turns N and N+1; ready on N+2.
- AC12: `cooldown=N` (N≥1) gives exactly N rounds of unavailability.
- AC13: `cooldown=0` skill stays ready (no behaviour change).

---

## Phase 5 — Enemy turn crashed on freed actor refs (was 032)

### Problem
Mid-`_run_enemy_turn`, Godot threw *"Left operand of 'is' is a previously
freed instance."* at `godmode_controller.gd:943`.

`_run_enemy_turn` snapshots `enemies` at function start. During Phase-1
resolve, an enemy's cast / DoT / counter-status can kill another enemy
in the same wave: `Actor.take_damage` → `died` → `_on_actor_died` →
`registry.unregister + queue_free`. At the next `await`-yield the node
is actually freed; on the next loop iteration the `is Actor` check
errors on the freed reference. Existing `registry.get_actor(...) == null`
guard was correct in intent but ran *after* the dereference.

### Fix
`is_instance_valid(actor)` as the first check in both Phase-1 and Phase-2
loops, before any `is` / member access.

### Acceptance
- AC14: in a wave with ≥2 enemies + AoE/chain skills, no
  "previously freed instance" errors during enemy turn.
- AC15: enemies dying mid-Phase-1 are silently skipped.

---

## Phase 6 — SelfArea dropped the caster from victims (was 033)

### Problem
`paw_suck` (target=self, area=self, effect=heal) failed every cast
with `[Ability] self_heal_medium: no victims after caster exclusion`.
`Ability.cast` excluded the caster whenever `primary == caster`. That
rule was correct for self-cast zone-AoE, but `SelfArea` returns exactly
`[caster]` — stripping caster left the array empty.

### Fix
Tighten the condition: also require `not (eff_area is SelfArea)`.
`SelfArea` is the only area type that semantically includes the caster;
zones still filter the caster out as before.

### Acceptance
- AC16: `paw_suck` heals the player.
- AC17: hypothetical `target=self` + `area=zone_circle` still excludes caster.
- AC18: `target=actor` + zone unchanged (friendly-fire preserved).

---

## Phase 7 — Cooldowns shared between owners (was 034)

### Problem
`Skill` is a Godot `Resource`. `SkillDatabase.get_skill(id)` returns one
shared instance. Every cd-touching path was hitting the shared resource:

- `enemy_data_loader.gd:60-62`: assigned the DB skill directly to
  `actor._skills` — two enemies of the same kind shared cd state.
- `_seed_slots` / `_on_ability_picker_selected`: put the DB instance
  into the slot bar; `_sync_player_skills_from_slots` mirrored it onto
  `player._skills` — same object as the enemies own.
- `_resolve_cast_intent` (1012) and `_try_fallback_skill` (251): both
  did `SkillDatabase.get_skill(id).cast(...)` — wrote cd directly to DB.
- `condition_skill_ready` (16): read `is_ready()` off the DB instance.
  Original docstring already flagged this as a future concern.

Net: `_cd_remaining` was global per id; `tick_skills` also
double-decremented when N owners pointed at the same Skill.

### Fix — per-owner duplicates
- `Skill.clone_for_owner()` — `duplicate()` (shallow, since Ability has
  no per-cast persistent state) + reset `_cd_remaining` and
  `_skip_next_tick`.
- `Actor.get_skill_by_id(id)` — id-keyed lookup over `_skills`.
- `enemy_data_loader`, godmode `_seed_slots`: clone per skill.
- `_on_ability_picker_selected`: get-or-clone helper — reuse player's
  existing duplicate of an id (so two slots holding the same skill
  share one cd).
- `_resolve_cast_intent`, `_try_fallback_skill`,
  `condition_skill_ready`: read via `actor.get_skill_by_id`.

Read-only DB lookups (telegraph tag, predicted_damage_to) left alone.

### Acceptance
- AC19: three identical enemies — casting on enemy A doesn't put B and C on cd.
- AC20: player and enemy with same skill have independent cd.
- AC21: per-round tick decrements each owner once, not N times for N owners.
- AC22: two slots with same skill — one cd, both slots share countdown.

---

## Phase 8 — ActorTarget rejected the caster on resolve (was 035)

### Problem
`actor_target.gd:28-29` had unconditional `if actor == caster: return null`,
contradicting the file's own docstring: `range = 0 = self only`. Net
result: `range=0` was unreachable, target=actor heals/buffs aimed at
caster silently no-op'd.

### Fix
Drop the unconditional reject. Add explicit self-shortcut before the
range check (`find_path(c, c)` is implementation-defined).

Designers control self-targetability via `range`:
- `range=0` → only caster.
- `range≥1` → caster and others in range.
- `range=-1` → any actor including caster.

No new `allow_self` flag — `range` already encodes intent.

### Acceptance
- AC23: `target=actor, range=0` resolves to caster.
- AC24: `target=actor, range=1` cast on self lands on caster.
- AC25: enemies still targetable at non-zero range as before.

---

## Phase 9 — `get_range_hexes` excluded caster (continuation of phase 8)

### Problem
Phase 8 fixed `ActorTarget.resolve` but the bug persisted: player still
couldn't click on themselves. `resolve` never ran — the FSM rejected
the click first.

`_handle_cast_lmb` (godmode_controller.gd:558) validates clicks via
`coord in valid_hexes` where `valid_hexes = ab.target.get_range_hexes(...)`.
For `range ≥ 1`, ActorTarget's BFS started at `caster_coord` but only
appended **neighbours**, never the caster's own hex. Caster's hex
wasn't in `valid_hexes` → click on self silently rejected before
`resolve` even ran.

### Fix
Seed the BFS result with `[caster_coord]` for `range ≥ 1`. `range=0`
already returned `[caster_coord]`; `range=-1` returns all walkable
(includes caster's hex). Now consistent across all ranges.

### Acceptance
- AC26: with `target=actor, range≥1`, clicking on the caster's own hex
  during the cast FSM commits the cast on self.
- AC27: cast-range overlay paints the caster's hex as valid.

---

## Phase 10 — Status effect parser used wrong key (`status` vs `status_id`)

### Problem
Shipping skill JSON (`honey_cold.json`, `paper_jam.json`, `weaken.json`,
…) uses `"status_id"` as the key for status-effect strings:
```
{"status_id": "slowed(3)"}
```
But `ability_database.gd` (T-026 era) read `"status"`. Status effects
on those skills were silently dropped at parse time — honey_cold did no
slow, paper_jam no root, weaken no debuff.

### Fix
Rename in `ability_database.gd`:
- `EFFECT_KIND_BY_KEY["status"]` → `["status_id"]`.
- `EFFECT_KEY_ORDER` entry `"status"` → `"status_id"`.
- `_parse_effect_dict`: handle `key == "status_id"`; explicit warning
  on the legacy `"status"` key (was silently ignored).
- Skip `"status_id"` in the broadcast-`Object.set` loop so it doesn't
  accidentally land on a sibling effect.

Two test fixtures (`test_status_runtime.json`,
`test_combo_multikey_effect.json`) updated to the new key.

### Acceptance
- AC28: casting `honey_cold` applies the `slowed` status to victims.
- AC29: legacy `"status"` key produces a parse warning naming the
  ability id and the new key.

---

## Phase 11 — Active slot stayed selected after cast

### Problem
After committing a cast, the slot bar's active slot remained
highlighted. Next click was a re-cast attempt — but the slot was now
on cd (greyed). Confusing UX, two clicks needed to do anything.

### Fix
After successful cast in `_commit_cast`, `_slot_bar_node.set_active(-1)`
to clear active selection. Failed casts keep the active slot
(intentional — let the player adjust target without re-pressing the
hotkey).

### Acceptance
- AC30: after a successful cast, no slot is highlighted; next LMB is a
  plain move.
- AC31: a cast that bails leaves the active slot intact.

---

## Phase 12 — Idle range/area preview lingered + mixed all abilities

### Problem
Two related but independent bugs in the same overlay path:

1. **Range/area paint persisted past the cast.** After
   `_commit_cast`, the move-range overlay (`_overlay`) kept showing the
   slot's range and didn't clear until the start of the next round
   (when something else triggered `_refresh_overlay`). Cause: the order
   inside `_commit_cast` was `_refresh_overlay()` *before*
   `set_active(-1)` from phase 11 — so refresh saw the still-active
   slot and re-painted; the post-deselect state never re-rendered.

2. **Idle preview mixed every ability of the skill.**
   `_refresh_overlay` iterated `sk.abilities` and forwarded all of them
   to `_overlay.show_for(player, registry, ability_items)`. For
   multi-ability skills (e.g. damage + self-heal vampirism), the
   overlay painted the union of every ability's range/area
   simultaneously — meaningless since each ability resolves with its
   own ctx at its own FSM step. The player saw a noisy mash-up that
   didn't match where their first click would land.

### Fix
1. Move the `set_active(-1)` call to *before* `_refresh_overlay()` in
   `_commit_cast`. Refresh now sees `active = -1`, paints empty.
2. `_refresh_overlay` forwards only `abilities[0]` — the step the FSM
   resolves first when the player clicks. Subsequent ability previews
   are already handled correctly by `_cast_overlay.show_range_for_ability`
   inside `_begin_step`, called once per FSM step.

### Acceptance
- AC32: after a successful cast, the range/area overlay disappears
  immediately (same frame as the slot deselect).
- AC33: with a slot active, the overlay paints only `abilities[0]`'s
  range and area — not a mash-up.
- AC34: during the FSM, each step's overlay paint matches that step's
  ability (regression check on existing `_cast_overlay` path).

---

## Phase 13 — Zone preview painted the union of every ability

### Problem
Phase 12 fixed `_refresh_overlay` (target-range paint via
`MoveRangeOverlay.show_for`), but the **zone-area preview** —
`MoveRangeOverlay.show_zone_preview`, painted every frame from
`_update_castability` — still iterated *all* of the active skill's
abilities and merged their `area.get_affected_hexes` into one
dedup'd dictionary. The painted blob was always the union, which is
visually dominated by the largest-radius ability. paper_jam (3
abilities with radii 1/1/2) always showed the 2-radius blob,
regardless of which step the FSM was on.

Additionally, during the FSM the zone preview should follow the
*current step's* ability (the one the next click will resolve), not
abilities[0] frozen at slot-activate time.

### Fix
New helper `_current_preview_ability() -> Ability`:
- During FSM cast: `_cast_skill.abilities[_cast_step]`.
- Idle, slot active: `active_skill.abilities[0]`.
- No active slot: `null`.

Both `_refresh_overlay` (target-range paint) and `_update_castability`
(zone-area paint) read from this single helper — guaranteed in sync,
no chance of one path showing step N while the other shows step 0.

### Acceptance
- AC35: paper_jam slot active — zone preview shows the abilities[0]
  area (radius=1), not the radius=2 from abilities[2].
- AC36: during paper_jam FSM, each step paints its own ability's area
  (radius 1, then 1, then 2) as the player advances.
- AC37: target-range and zone-area previews always describe the same
  ability; impossible to see a mismatch.

---

## Phase 14 — Cast-range hexes painted over zone area (post-merge regression)

### Problem
After merging staging (which brought 029 polish — refactor of
`MoveRangeOverlay` to a unified `_draw()`-based architecture), the
target-range overlay (`CastRangeOverlay`, z=4) rendered ABOVE the
zone-area preview (`MoveRangeOverlay`, z=2). User-visible: when
multi-ability skills entered FSM step 2+, the orange "you can click
here" hexes covered the pink "this is the affected area" hexes.

Cause: pre-029, `MoveRangeOverlay.show_zone_preview` used individual
`Polygon2D` children with explicit `z=4` per the `_add_hex(... 4 ...)`
parameter — equal-z to `CastRangeOverlay`'s polys, with render order
falling out of insertion order (zone repainted every frame, ended up
on top — accidentally correct). The 029 refactor merged all
`MoveRangeOverlay` painting into one `_draw()` at the node's
`z_index = 2`, which placed everything below `CastRangeOverlay`'s
z=4. The semantic "area > target range" stacking inverted as a
side-effect.

### Fix
Set `MoveRangeOverlay.z_index = 5`. The unified `_draw()` output
(zone outline + attack range + hover path + zone preview) all moves
above `CastRangeOverlay`'s z=4 polys. Internal stacking inside
`MoveRangeOverlay._draw()` is preserved by call order
(`draw_zone_outline` first, then attack-range outlines, then zone
preview last → on top within the same z).

Other z=5 users (spawner_placeholder runtime, delete_highlight /
paint_preview editor-only) audited — spawner_placeholder coexists
rarely (player rarely stands on a spawner mid-cast), the others are
editor-only.

### Acceptance
- AC38: during FSM step 2+ of paper_jam, the pink area zone is fully
  visible on top of the cast-range (orange) outlines.
- AC39: idle slot preview still renders correctly (no FSM, no
  CastRangeOverlay; only MoveRangeOverlay paints — stack order moot).
- AC40: regression check on move-zone outline / attack-range / hover
  path — internal draw order preserved (still drawn in `_draw()` in
  the same sequence).

---

## Out of scope (across all phases)

- Per-caster turn-end ticking (round-based is correct for current TurnManager).
- Ability-level cooldowns (Ability has none today).
- Cooldown reset on death / scene reload / meta-screens.
- Migrating Skill from Resource to per-owner data class (Phase-7 dance
  is a 72h-jam-grade workaround).
- New `allow_self` flag on ActorTarget (Phase 8 — `range` already encodes it).
- Sharing cd between actors of the same kind (rejected; playtest report
  explicitly asked for per-actor cd).
