# 032-controller-refactor — tasks

**Spec:** [`spec.md`](spec.md). **Plan:** [`plan.md`](plan.md). **Branch:** `andrey/controller-refactor`.

Strategy: extract one module at a time, slim the controller incrementally, test after each extraction in the editor (open godmode, RMB-move, LMB-cast, F1/F2, Esc — full input matrix). Order chosen to minimize cross-references during transition: leaf modules first (no dependencies on other new modules), then ones that depend on them.

Implement-mode discipline: mark `[x]` only when the editor smoke-test for that step passes. Don't push a half-extracted state.

---

## Group A — Scaffolding (no behavior change)

- [ ] **T01** Create empty module skeletons. Each file is a `Node` extending `Node` with stub `_ready` that resolves `_ctrl = get_parent()`. Files:
  - `scripts/presentation/godmode/godmode_setup.gd`
  - `scripts/presentation/godmode/godmode_input.gd`
  - `scripts/presentation/godmode/cast_fsm.gd`
  - `scripts/presentation/godmode/ai_driver.gd`
  - `scripts/presentation/godmode/telegraph_renderer.gd`
  - `scripts/presentation/godmode/hover_dispatcher.gd`
  - `scripts/presentation/godmode/manekin_spawner.gd`
  - `scripts/presentation/godmode/step_animator.gd`
- [ ] **T02** Add 8 child nodes to `scenes/dev/godmode.tscn` under `GodmodeController`, one per script from T01. Verify scene opens in editor without errors.
- [ ] **T03** On `GodmodeController`, add public properties for module accessors (`var setup: Node`, `var input: Node`, …). Resolve them at top of `_ready` via `get_node("GodmodeSetup")` etc. Add a `_resolve_modules()` helper. Smoke: launch godmode, confirm no behavior change. **(depends T01, T02)**
- [ ] **T04** On `GodmodeController`, rename internal fields to drop underscore where they need to become public for sibling reads: `_slot_bar_node` → `slot_bar`, `_inspector` → `inspector`, `_overlay` → `overlay`, `_cast_overlay` → `cast_overlay`, `_queued_level` → `queued_level`, `_tile_object_resolver` → `tile_object_resolver`, `_wave_controller` → `wave_controller`. Update all in-file references. Smoke launch. **(depends T03)**

## Group B — Step animator (smallest, leaf module)

- [ ] **T05** Move `_on_step_started` and the `ActorMotion` const from controller to `step_animator.gd`. Controller's `_ready` still does `grid.actor_step_started.connect(...)` but binds to `step_animator._on_step_started`. Smoke: RMB-move player — sway and step tween both work. **(depends T04)**

## Group C — Manekin spawner (small, depends only on AI replan path)

- [ ] **T06** Move `_spawn_manekin`, `_clear_manekins`, `_on_actor_died`, `_next_manekin_idx`, `MANEKIN_SCENE` const from controller to `manekin_spawner.gd`. Public methods: `spawn()`, `clear_all()`. Internal `_on_actor_died(id)` — same logic, calls `_ctrl.telegraphs.refresh()` (placeholder until T11) — for now call `_ctrl._refresh_telegraphs()` on controller and let T11 redirect. Smoke: F1/F2 in godmode. **(depends T04)**
- [ ] **T07** In `GodmodeInput` (still empty), nothing to do yet, but route F1/F2 through `_ctrl.manekin_spawner.spawn()` / `clear_all()` once `GodmodeInput` owns `_unhandled_input` (T18). For now, controller's `_unhandled_input` calls `_ctrl.manekin_spawner.spawn()` directly. Smoke: F1/F2 still work. **(depends T06)**

## Group D — Telegraph renderer

- [ ] **T08** Move `TELEGRAPH_HEX_SCRIPT`, `INTENT_ARROW_SCRIPT` consts and `_telegraph_hexes`, `_intent_arrows` dicts from controller to `telegraph_renderer.gd`.
- [ ] **T09** Move `_telegraph_tag_for_skill` → `tag_for_skill(skill)` (public). **(depends T08)**
- [ ] **T10** Move `_enemy_attack_damage(enemy)` → `enemy_attack_damage(enemy)` (public). Search repo for external callers; rebind any. **(depends T08)**
- [ ] **T11** Move `_refresh_telegraphs` → `refresh()` and `_clear_all_telegraphs` → `clear()`. Update all controller call sites (`_replan_all_and_refresh`, `_run_enemy_turn`, `_on_actor_died`, `_clear_manekins`-via-spawner) to call `_ctrl.telegraphs.refresh()` / `clear()`. Re-route the placeholder from T06. Smoke: spawn manekin (telegraph appears), cast on player (telegraph clears). **(depends T08, T09, T10)**

## Group E — AI driver

- [ ] **T12** Move `_world_processing` flag from controller to `ai_driver.gd`. Add public `is_world_processing()` getter. **Update all read sites:** `_request_move`, `_wait_turn`, `_cast_slot` (still on controller for now), `_on_world_turn_ended` body — change `_world_processing` → `_ctrl.ai.is_world_processing()` for reads, keep direct field access only inside AiDriver itself. **(depends T03)**
- [ ] **T13** Move `_world_ctx` → `world_ctx()` (public — used by ManekinSpawner via `_ctrl.ai.world_ctx()`). Move `_tick_all_statuses`. **(depends T12)**
- [ ] **T14** Move `_resolve_move_intent` and `_resolve_cast_intent` (private to AiDriver). **(depends T12)**
- [ ] **T15** Move `_run_enemy_turn` (preserve B-001 `is_instance_valid` guards in both Phase 1 and Phase 2 loops verbatim). **(depends T13, T14)**
- [ ] **T16** Move `_on_world_turn_ended` and `_replan_all_and_refresh` → `replan_all_and_refresh` (public). Update controller's `_ready` signal connect: `EventBus.world_turn_ended.connect(_ctrl.ai._on_world_turn_ended)`. Update ManekinSpawner.spawn to call `_ctrl.ai.replan_all_and_refresh()`. Smoke: end turn — enemies move, telegraphs update; F1 spawn — new enemy plans immediately. **(depends T15, T11)**

## Group F — Cast FSM

- [ ] **T17** Move `_cast_in_progress`, `_cast_skill`, `_cast_step`, `_cast_ctxs` to `cast_fsm.gd`. Add public `is_in_progress()`, `is_self_step()` getters. Update all read sites in controller (`_unhandled_input` Esc/slot/LMB/RMB branches, `_refresh_hover_path`) — change `_cast_in_progress` → `_ctrl.cast_fsm.is_in_progress()`, `_is_self_step()` → `_ctrl.cast_fsm.is_self_step()`. **(depends T03)**
- [ ] **T18** Move `_cast_slot`/`_begin_step`/`_commit_step`/`_commit_cast`/`_cancel_cast`/`_reset_cast_state`/`_handle_cast_lmb` and `_is_self_step` to `cast_fsm.gd`. Rename to public form: `start(slot_index)`, `cancel()`, `handle_lmb()`, `commit_step(coord, target_id)`. Keep `_begin_step`, `_commit_cast`, `_reset_state` private. Update controller call sites: `_cast_slot(active)` → `_ctrl.cast_fsm.start(active)`, `_cancel_cast()` → `_ctrl.cast_fsm.cancel()`, `_handle_cast_lmb()` → `_ctrl.cast_fsm.handle_lmb()`. CastFsm reads `_ctrl.slot_bar`, `_ctrl.player`, `_ctrl.grid`, `_ctrl.registry`, `_ctrl.overlay`, `_ctrl.cast_overlay`. CastFsm calls `_ctrl.refresh_overlay()` on commit/cancel. Smoke: full cast flow — Q to select, LMB on enemy, multi-step skill, Esc cancel mid-cast, RMB cancel. **(depends T17)**

## Group G — Input

- [ ] **T19** Move `_unhandled_input` from controller to `godmode_input.gd`. Update all internal references through `_ctrl.X`. The controller no longer has `_unhandled_input` — Godot routes input to children automatically when they implement it (siblings receive the event before bubbling up). **(depends T18, T16, T07)**
- [ ] **T20** Move `_request_move`, `_wait_turn`, `_request_cast_active` helpers to `godmode_input.gd` (private). `_request_cast_active`'s "select hovered actor / inspect hex" fallthrough calls `_ctrl.select(...)` / `_ctrl.inspect_hex(...)` — controller's selection facade (preserved). Smoke: full input matrix — RMB move, SPACE wait, QWER/1234 select+cast, LMB cast, F1/F2, Esc priorities, dev_open_editor. **(depends T19)**

## Group H — Hover dispatcher

- [ ] **T21** Move `_hover_intent_actor_id` field, `_refresh_hover_path` → `refresh_hover_path(coord)`, `_refresh_intent_tooltip` → `refresh_intent_tooltip(hovered_id)` to `hover_dispatcher.gd`. Reads `_ctrl.player`, `_ctrl.grid`, `_ctrl.registry`, `_ctrl.overlay`, `_ctrl.cast_fsm.is_in_progress()`, `_ctrl.ai.is_world_processing()`. **(depends T17, T12)**
- [ ] **T22** Move `_update_castability` → `update_castability()` (public for completeness — only `_process` calls it) and `_process` from controller to `hover_dispatcher.gd`. Update body to call `refresh_hover_path` and `refresh_intent_tooltip` directly (no `_ctrl.` prefix — siblings of HoverDispatcher itself). Controller's `_process` is removed. Smoke: hover enemy → tooltip appears, hover empty hex within range → path preview, slot tints update on hover. **(depends T21)**

## Group I — Setup orchestration

- [ ] **T23** Move `_paint_grid`, `_try_load_queued_level`, `_place_player`, `_seed_slots`, `_emit_initial_turn`, `_select_deferred` to `godmode_setup.gd`. Public entry: `run()`. **(depends T22, T16, T11, T05)**
- [ ] **T24** Move the body of controller's `_ready` (everything AFTER node resolution and `_resolve_modules()`) into `GodmodeSetup.run()`. Replace controller's `_ready` body with: (a) resolve nodes (grid/registry/player/slot_bar/inspector/overlay/cast_overlay/PSP via @export NodePath), (b) `_resolve_modules()`, (c) `setup.run()`. Setup's `run()` does steps 1-13 from `plan.md §GodmodeSetup`. Smoke: full godmode launch (procedural sandbox) and full launch with a queued level (Playtest from map_editor of `data/maps/sample.json`). **(depends T23)**
- [ ] **T25** Verify slim controller reaches target. `wc -l scripts/presentation/godmode/godmode_controller.gd` ≤ 200. Each new module ≤ 300. If any over: split further before continuing. **(depends T24)**

## Group J — Tileset consolidation

- [ ] **T26** Edit `scenes/arena/tilesets/hex_terrain.tres`: change `tile_shape = 2` → `tile_shape = 3`. Verify the file opens in Godot import without errors (run `find . -name "*.import"` style check is not available — open editor manually).
- [ ] **T27** Update tileset references in 4 .gd files + 2 JSON + schema + CLAUDE.md (per `plan.md §Tileset consolidation` table). Specifically:
  - `scripts/presentation/godmode/godmode_setup.gd` (the relocated `_paint_grid` and tileset assignment) — drop `GODMODE_TERRAIN`, use `hex_terrain.tres`, `_paint_grid` source 0 atlas (0,0) (grass).
  - `scripts/presentation/dev/map_editor_controller.gd` — `GODMODE_TERRAIN` const + `GODMODE_TERRAIN_PATH` → `HEX_TERRAIN` / `HEX_TERRAIN_PATH` pointing to hex_terrain.tres.
  - `scripts/presentation/dev/floor_palette_panel.gd` — drop the `{"label": "Godmode Terrain", ...}` entry; rename remaining "Hex Terrain".
  - `scripts/core/maps/level_data.gd` — `DEFAULT_TILESET_PATH` → hex_terrain path.
  - `data/maps/sample.json`, `data/maps/sample_waves.json` — `tileset_path` → hex_terrain.
  - `data/maps/_schema.md` — replace 3 mentions of `godmode_terrain.tres` with `hex_terrain.tres`.
  - `CLAUDE.md` rule #7 — rewrite as "ONE tileset, hex_terrain.tres, tile_shape = HEXAGON". **(depends T26)**
- [ ] **T28** Delete `scenes/dev/godmode_terrain.tres`. Do NOT delete `scenes/dev/godmode_atlas.png` — still used by hex_terrain source 1 (forest). Verify with `grep -rn "godmode_terrain" .` returning zero hits in scripts/data/scenes (only mentions allowed: in spec.md, plan.md, this tasks.md, CLAUDE.md old-rule context if any). **(depends T27)**
- [ ] **T29** Manual validation in Godot editor (procedure from `plan.md §Validation procedure`):
  1. Procedural godmode sandbox: launch, move, observe move-range overlay (B-003 check).
  2. Map editor: open, load `sample.json`, verify floor renders.
  3. Map editor → Playtest sample.json: move, observe overlay.
  4. Repeat (3) with `sample_waves.json` (loads waves too — verify enemies spawn).
  Document outcome inline in PR description: "(2)✓ (3)✓ (4)✓ B-003 closed by tileset consolidation" — or note which step failed. **(depends T28)**

## Group K — Bookkeeping

- [ ] **T30** Update `specs/032-controller-refactor/spec.md`:
  - Mark B-001 closed (already fixed in 029, verified during T15).
  - Update B-003 status based on T29 outcome.
  - Add `**Status: shipped**` header line (or `Status: in-PR` until merged).
- [ ] **T31** Append a HANDOFF.md note in §18 (Текущее состояние): "032-controller-refactor merged — godmode_controller split into 8 sibling modules (~150 lines each), single tileset (hex_terrain.tres, HEXAGON shape). B-003 [closed/pending]. B-002 (UiTheme static-call warning) tracked as separate cleanup." **(depends T29)**
- [ ] **T32** Update CLAUDE.md ownership table: append row `032-controller-refactor (godmode module split, tileset consolidation) | Andrey`. **(depends T31)**

## Group L — Push & PR

- [ ] **T33** Final smoke test before push: full input matrix on procedural godmode + sample.json Playtest + sample_waves.json Playtest. All work, no console errors. Frame rate matches baseline (no per-frame regressions from the move).
- [ ] **T34** Stage, commit (multi-commit OK — group by phase), `git push -u origin andrey/controller-refactor`. Capture the PR-creation URL from stderr and surface to Andrey. **(depends T33)**

---

## Acceptance criteria check (from spec.md)

| AC | Verified by |
|---|---|
| 1. controller ≤ 300 lines, only orchestration | T25 |
| 2. each module ≤ 300 lines | T25 |
| 3. no regression: cast FSM, AI multi-step, slot lifecycle, telegraph + AoE shape, sway, hover | T20 + T22 + T29 + T33 |
| 4. single tileset, godmode_terrain.tres + orphans deleted | T28 |
| 5. move-range overlay correct on every level | T29 |
