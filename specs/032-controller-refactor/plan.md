# 032-controller-refactor — plan

**Owner:** Andrey.
**Branch:** `andrey/controller-refactor`.

This is the HOW for `spec.md`. Read the spec first.

---

## Architecture: controller as facade

Single, atomic refactor of `scripts/presentation/godmode/godmode_controller.gd` (1432 lines) into 8 sibling `Node` modules. The controller becomes a thin orchestrator that:

1. Resolves shared scene-tree refs (grid, registry, player, slot_bar, inspector, overlays, PSP).
2. Owns the small selection facade (`_select`, `_inspect_hex`, `_bind_hex_at`, `_deselect_to_player`, `_refresh_overlay`).
3. Owns the SlotBar signal pump (`_on_slot_activated`, `_on_slot_right_clicked`, `_on_inspector_speed_changed`, `_on_actor_died_for_selection`).
4. Owns the right-click ability picker popup (small, ~40 lines).
5. Acts as a registry of child modules — siblings reach each other via `_ctrl.cast_fsm`, `_ctrl.ai`, etc.

**No game logic on the controller.** "Selection facade" and "slot signal pump" are presentation glue, not gameplay rules.

### Module table (final)

| Module | File | Approx lines | Responsibility |
|---|---|---:|---|
| `GodmodeSetup` | `scripts/presentation/godmode/godmode_setup.gd` | 220 | `_ready` setup chain, level loading, player placement, slot seeding, wave controller wiring, post-init signal hookups |
| `GodmodeInput` | `scripts/presentation/godmode/godmode_input.gd` | 160 | `_unhandled_input` switchboard, `_request_move`, `_wait_turn`, dispatches LMB to CastFsm or to selection facade |
| `CastFsm` | `scripts/presentation/godmode/cast_fsm.gd` | 180 | Multi-step player cast collection FSM (state, `start`, `begin_step`, `commit_step`, `commit_cast`, `cancel`, `handle_lmb`, `is_self_step`) |
| `AiDriver` | `scripts/presentation/godmode/ai_driver.gd` | 200 | `_on_world_turn_ended`, `_run_enemy_turn` (Phase 1+2), `_resolve_move_intent`, `_resolve_cast_intent`, `_world_ctx`, `_tick_all_statuses`, `_replan_all_and_refresh`, `is_world_processing()` getter |
| `TelegraphRenderer` | `scripts/presentation/godmode/telegraph_renderer.gd` | 240 | `_telegraph_hexes`, `_intent_arrows` dicts, `refresh()`, `clear()`, `tag_for_skill()`, `enemy_attack_damage()` |
| `HoverDispatcher` | `scripts/presentation/godmode/hover_dispatcher.gd` | 200 | Owns `_process`, `update_castability()` (slot tints + zone preview + hp preview), `refresh_hover_path()`, `refresh_intent_tooltip()` |
| `ManekinSpawner` | `scripts/presentation/godmode/manekin_spawner.gd` | 90 | `spawn()`, `clear_all()`, `_on_actor_died` (live actors hook), manekin index counter |
| `StepAnimator` | `scripts/presentation/godmode/step_animator.gd` | 30 | Connects to `grid.actor_step_started`, runs the position tween + `ActorMotion.apply_step_sway` |

**Slim controller target:** 150 lines. Hard cap 200.

---

## Communication contract

### Pattern: controller as facade, modules read from `_ctrl`

Each module is a `Node` child of `GodmodeController`. In its `_ready` it does:

```gdscript
var _ctrl: Node = null   # GodmodeController — typed loosely to avoid cyclic preload

func _ready() -> void:
	_ctrl = get_parent()
```

All shared refs are public properties on the controller. Modules read them at call time:

```gdscript
# Inside CastFsm.start():
var skill: Skill = _ctrl.slot_bar.get_slot(slot_index) as Skill
if not skill.can_apply(_ctrl.player, ctx): return
```

**Rationale:** avoids 8 modules × 6 NodePaths = 48 path entries to wire in `.tscn`. Controller does node resolution once. `get_parent()` is tree-relative (allowed); `find_child(...)` from autoloads is the anti-pattern (forbidden).

### Cross-module calls

Direct method calls when one module is a known dependency of another:

| Caller | Callee | Method | When |
|---|---|---|---|
| `CastFsm.start()` | `MoveRangeOverlay` (via `_ctrl.overlay`) | `clear()` | Hide attack-range paint before cast-overlay paints |
| `CastFsm.commit_cast()` | controller | `refresh_overlay()` | Restore move-range after FSM exits |
| `CastFsm.cancel_cast()` | controller | `refresh_overlay()` | Same |
| `ManekinSpawner.spawn()` | `AiDriver` | `replan_all_and_refresh()` | New manekin → re-plan all enemies + refresh telegraphs |
| `ManekinSpawner.clear_all()` | `TelegraphRenderer` | `clear()` | Wipe telegraphs after enemies removed |
| `ManekinSpawner.clear_all()` | controller | `deselect_to_player()` | Reset selection after clear |
| `AiDriver._run_enemy_turn()` | `TelegraphRenderer` | `clear()`, `refresh()` | Bracket Phase 1+2 visuals |
| `GodmodeInput._unhandled_input` | `CastFsm` | `cancel()`, `handle_lmb()`, `is_in_progress()` | LMB/RMB/Esc dispatch during FSM |
| `HoverDispatcher._refresh_hover_path` | `CastFsm` | `is_in_progress()` | Skip path preview during FSM |
| `HoverDispatcher._update_castability` | `AiDriver` | `is_world_processing()` | Tooltip stays correct during AI turn |

### EventBus

**Zero new signals.** Existing signals consumed by modules:
- `world_turn_ended` → `AiDriver._on_world_turn_ended`
- `actor_died` → controller `_on_actor_died_for_selection`
- `ui_theme_reloaded` → already wired in MoveRangeOverlay (untouched)
- `run_started` → emitted once from `GodmodeSetup` (no new listeners here)
- Existing `tile_object_*` signals — `TileObjectResolver` is unchanged, lives as a child of the controller as before

Reason: this is structural cleanup, not a behavior change. Adding signals without a clear cross-system need is the abstraction-for-future-trap (PROJECT_INSTRUCTIONS §Don'ts).

---

## Public surface of GodmodeController (after refactor)

**Properties** (read by modules):
```gdscript
var grid: HexGrid
var registry: ActorRegistry
var player: Actor
var slot_bar: Node                  # was _slot_bar_node; renamed (drop underscore — public)
var inspector: Node                 # was _inspector
var overlay: Node                   # was _overlay (MoveRangeOverlay)
var cast_overlay: Node              # was _cast_overlay (CastRangeOverlay)
var queued_level: LevelData = null  # was _queued_level

# Module accessors (set by GodmodeSetup, in _ready order)
var setup: Node                     # GodmodeSetup
var input: Node                     # GodmodeInput
var cast_fsm: Node                  # CastFsm
var ai: Node                        # AiDriver
var telegraphs: Node                # TelegraphRenderer
var hover: Node                     # HoverDispatcher
var manekin_spawner: Node           # ManekinSpawner
var step_animator: Node             # StepAnimator
var tile_object_resolver: TileObjectResolver
var wave_controller: WaveController = null
```

**Public methods** (selection facade — kept on controller):
```gdscript
func select(actor: Actor) -> void
func deselect_to_player() -> void
func inspect_hex(coord: Vector2i) -> void
func bind_hex_at(coord: Vector2i) -> void
func refresh_overlay() -> void
func get_player_status_panel() -> Node
```

Underscore-prefix is dropped on these because they're now genuinely public (called by sibling modules). Underscore retained for internal handlers (`_on_slot_activated`, `_on_inspector_speed_changed`, `_on_actor_died_for_selection`, `_on_ability_picker_selected`, `_build_ability_picker`).

---

## Module API contracts

Compact form: `module.method(args) → return`. All `_ctrl` reads are implicit.

### `GodmodeSetup` (orchestrates `_ready` for the controller)

```gdscript
func run() -> void   # Called by controller in its _ready, AFTER node resolution
```

Body order — copies the existing controller `_ready` 1:1 with renames:
1. Resolve grid TileMapLayer/VFXOverlay if missing.
2. Wire `grid.actor_step_started` → `_ctrl.step_animator._on_step_started`.
3. `_try_load_queued_level()` or fallback paint+initialize+place_player.
4. Wire `tile_object_resolver`.
5. `_seed_slots.call_deferred()`.
6. Connect SlotBar signals → controller handlers, build ability picker.
7. Resolve inspector/overlay/cast_overlay; call `setup(grid)` on each.
8. `TurnManager.reset()`, emit initial turn (deferred), select player (deferred).
9. `EventBus.run_started.emit()`.
10. Wire `EventBus.world_turn_ended` → `_ctrl.ai._on_world_turn_ended`.
11. Wire `EventBus.actor_died` → `_ctrl._on_actor_died_for_selection`.
12. Bind PSP to player.
13. Spin up `WaveController` if `queued_level != null`.

Helper methods (all private to setup):
- `_try_load_queued_level() -> bool`
- `_paint_grid() -> void`
- `_place_player() -> void`
- `_seed_slots() -> void`
- `_emit_initial_turn() -> void`
- `_select_deferred() -> void`

### `GodmodeInput`

```gdscript
func _unhandled_input(event: InputEvent) -> void
```

Internal helpers (extracted from current controller):
- `_request_move() -> void`
- `_wait_turn() -> void`
- `_request_cast_active() -> void`  — handles "LMB with no active FSM": tries cast or falls through to selection

LMB priority (FSM-aware, copied from current behavior):
1. `_ctrl.cast_fsm.is_in_progress()` → `_ctrl.cast_fsm.handle_lmb()`
2. SlotBar has active slot + can_apply → `_ctrl.cast_fsm.start(active_idx)` then `_ctrl.cast_fsm.handle_lmb()` (entry-click commits step 0)
3. Hovering an actor → `_ctrl.select(actor)`
4. Hovering walkable hex → `_ctrl.inspect_hex(coord)`

RMB:
1. `_ctrl.cast_fsm.is_in_progress()` → `_ctrl.cast_fsm.cancel()`
2. else → `_request_move()`

Esc priority (unchanged from current — ported verbatim):
1. cast in progress → cancel
2. active slot → toggle off
3. selection != player → deselect
4. else → open pause menu (or last-resort deselect)

### `CastFsm`

State (private): `_in_progress: bool`, `_skill: Skill`, `_step: int`, `_ctxs: Array[Dictionary]`.

Public:
```gdscript
func is_in_progress() -> bool
func is_self_step() -> bool
func start(slot_index: int) -> void   # was _cast_slot
func handle_lmb() -> void              # was _handle_cast_lmb
func commit_step(coord: Vector2i, target_id: StringName) -> void
func cancel() -> void                  # was _cancel_cast
```

Private:
- `_begin_step()`
- `_commit_cast()`  — `await GameSpeed.wait("godmode", "ability_cast_delay")` + `TurnManager.advance()` after `Skill.cast`
- `_reset_state()`

### `AiDriver`

State: `_world_processing: bool`, telegraph dicts moved to `TelegraphRenderer`.

Public:
```gdscript
func is_world_processing() -> bool
func replan_all_and_refresh() -> void   # called by ManekinSpawner
func world_ctx() -> Dictionary           # called by ManekinSpawner
```

Internal (move from controller verbatim with `_ctrl.` prefixes):
- `_on_world_turn_ended(turn: int)`
- `_run_enemy_turn()` (Phase 1+2 with B-001 `is_instance_valid` guards already in place — keep them)
- `_tick_all_statuses()`
- `_resolve_move_intent(enemy: Actor)`
- `_resolve_cast_intent(enemy: Actor)`

### `TelegraphRenderer`

State: `_telegraph_hexes: Dictionary`, `_intent_arrows: Dictionary`.

Public:
```gdscript
func refresh() -> void                   # was _refresh_telegraphs
func clear() -> void                     # was _clear_all_telegraphs
func tag_for_skill(skill: Skill) -> StringName   # was _telegraph_tag_for_skill
func enemy_attack_damage(enemy: Actor) -> int    # was _enemy_attack_damage
```

`refresh()` walks `_ctrl.registry.all()`, builds aggregates, mounts `TELEGRAPH_HEX_SCRIPT`/`INTENT_ARROW_SCRIPT` instances under `_ctrl.grid` (parent unchanged from current).

### `HoverDispatcher`

State: `_hover_intent_actor_id: StringName`.

```gdscript
func _process(_delta: float) -> void   # → update_castability()

func update_castability() -> void              # was _update_castability
func refresh_hover_path(coord: Vector2i) -> void  # was _refresh_hover_path
func refresh_intent_tooltip(hovered_id: StringName) -> void  # was _refresh_intent_tooltip
```

Per-frame work in `update_castability` (verbatim move): slot tints, hp-bar damage preview, zone AoE preview push to overlay, then calls `refresh_hover_path` and `refresh_intent_tooltip` at the end.

Reads `_ctrl.cast_fsm.is_in_progress()` and `_ctrl.ai.is_world_processing()` for skip conditions.

### `ManekinSpawner`

State: `_next_idx: int = 1`.

```gdscript
func spawn() -> void          # was _spawn_manekin
func clear_all() -> void      # was _clear_manekins
```

Private: `_on_actor_died(id)` — when enemy dies, clear from grid/registry, queue_free, refresh telegraphs via `_ctrl.telegraphs.refresh()`.

### `StepAnimator`

Single handler:
```gdscript
func _on_step_started(actor_id: StringName, _from: Vector2i, to: Vector2i) -> void
```

Body: `create_tween().tween_property(actor, "position", pos, duration)` + `ActorMotion.apply_step_sway`. Connected by `GodmodeSetup.run()` to `grid.actor_step_started`.

---

## Scene tree changes

`scenes/dev/godmode.tscn` — append 8 child nodes under `GodmodeController`:

```
GodmodeController
├── GodmodeSetup           type=Node, script=godmode_setup.gd
├── GodmodeInput           type=Node, script=godmode_input.gd
├── CastFsm                type=Node, script=cast_fsm.gd
├── AiDriver               type=Node, script=ai_driver.gd
├── TelegraphRenderer      type=Node, script=telegraph_renderer.gd
├── HoverDispatcher        type=Node, script=hover_dispatcher.gd
├── ManekinSpawner         type=Node, script=manekin_spawner.gd
└── StepAnimator           type=Node, script=step_animator.gd
```

Order matters for `_ready` only if siblings cross-call during it. Our pattern: each child caches `_ctrl = get_parent()` in `_ready` but does NO cross-sibling calls yet. The controller's `_ready` runs LAST (children before parent), so by the time the controller calls `setup.run()`, all siblings exist. `setup.run()` connects signals — at that point all sibling refs are valid.

`TileObjectResolver` continues to be created at runtime in `setup.run()` (unchanged from current).

`WaveController` continues to be created at runtime in `setup.run()` if a queued level is loaded (unchanged).

---

## Tileset consolidation

Per spec §"Tileset consolidation" + OQ-3: atomic single PR.

### Files

| Action | File | Change |
|---|---|---|
| Edit | `scenes/arena/tilesets/hex_terrain.tres` | `tile_shape = 2` → `tile_shape = 3` |
| Edit | `scripts/presentation/godmode/godmode_setup.gd` (was on controller) | Drop `GODMODE_TERRAIN`; load `hex_terrain.tres`; `_paint_grid` uses source 0 atlas (0,0) (grass) |
| Edit | `scripts/presentation/dev/map_editor_controller.gd` | `GODMODE_TERRAIN` const + path → `HEX_TERRAIN` pointing at hex_terrain.tres |
| Edit | `scripts/core/maps/level_data.gd` | `DEFAULT_TILESET_PATH` → `res://scenes/arena/tilesets/hex_terrain.tres` |
| Edit | `scripts/presentation/dev/floor_palette_panel.gd` | Drop "Godmode Terrain" entry; rename remaining to "Hex Terrain" |
| Edit | `data/maps/sample.json` | `tileset_path` → hex_terrain |
| Edit | `data/maps/sample_waves.json` | `tileset_path` → hex_terrain |
| Edit | `data/maps/_schema.md` | Replace godmode_terrain mentions; update default note |
| Edit | `CLAUDE.md` rule #7 | Rewrite "Two tilesets" → "ONE tileset, hex_terrain.tres, tile_shape = HEXAGON" |
| Delete | `scenes/dev/godmode_terrain.tres` | After all consumers updated |

`scenes/dev/godmode_atlas.png` is **NOT deleted** — it's still consumed by `hex_terrain.tres` source 1 (forest tile, atlas (0,0)).

### Validation procedure (informs AC-5)

After tileset edits applied:
1. Open Godot editor → import. Verify hex_terrain.tres opens without errors.
2. Run godmode (procedural sandbox, no queued level). Player spawns, can move, move-range overlay renders. **Check from B-003.**
3. Open map_editor → load `data/maps/sample.json`. Tileset auto-loads (now hex_terrain). Verify floor cells render and editor canvas works.
4. From map_editor → Playtest sample.json. Move-range overlay renders correctly on the loaded level.
5. Repeat (4) with `sample_waves.json`.

If overlay still misbehaves on any of (2), (3), (4) → root-cause investigation tracked as B-003 follow-up. Refactor still merges; tileset consolidation is independently valuable.

### Risk: changing `tile_shape` may shift cell coords

`local_to_map(pixel) → cell` returns different cells for HEXAGON vs HALF_OFFSET_SQUARE at the same pixel position because the hex packing density differs. Cells stored in JSON (integer Vector2i) don't change, but the screen positions cells map to do. Existing levels (sample.json, sample_waves.json) were authored with HALF_OFFSET_SQUARE — after the shape change, the cells still occupy the same `Vector2i` keys but render at different pixel positions. Pathfinding via `*_SIDE` enum constants returns different neighbours per shape — `hex_grid.gd` lines 147-152 + 558-563 + `arena_demo_controller.gd` 35-40 use these enums.

**Mitigation:** the validation procedure above includes a Playtest of each sample map — pathing breakage shows up immediately as enemies walking the wrong way or unreachable tiles. If broken: revert tile_shape to 2, file as B-004, ship the controller-refactor part of the PR alone (still net-positive — the refactor reasoning doesn't depend on tileset consolidation).

---

## Bugs B-001..B-003 reconciliation

| Bug | Status | Action this spec |
|---|---|---|
| B-001 | Already fixed in 029 (commit 749a954, Phase 1+2 `is_instance_valid` guards) | Verify guards survive the move from controller → AiDriver. No code change. Update spec.md to mark B-001 closed. |
| B-002 | Open. `UiTheme.apply_label_kind` called via instance triggers Godot 4.6 static-call warning. | Out of scope here — fix lives in whichever consumer invokes it. Track in HANDOFF.md follow-up note. Don't bundle. |
| B-003 | Likely fixed in 029 by geometric edge detection in `_draw_zone_outline` | Validate via the tileset validation procedure above. If still broken → B-003 follow-up after merge. |

---

## File-by-file diff summary

```
NEW (8 module scripts):
  scripts/presentation/godmode/godmode_setup.gd
  scripts/presentation/godmode/godmode_input.gd
  scripts/presentation/godmode/cast_fsm.gd
  scripts/presentation/godmode/ai_driver.gd
  scripts/presentation/godmode/telegraph_renderer.gd
  scripts/presentation/godmode/hover_dispatcher.gd
  scripts/presentation/godmode/manekin_spawner.gd
  scripts/presentation/godmode/step_animator.gd

REWRITTEN (slim version):
  scripts/presentation/godmode/godmode_controller.gd  — 1432 → ~150 lines

EDITED:
  scenes/dev/godmode.tscn                             — +8 child nodes under controller
  scenes/arena/tilesets/hex_terrain.tres              — tile_shape 2 → 3
  scripts/presentation/dev/map_editor_controller.gd   — GODMODE_TERRAIN → HEX_TERRAIN
  scripts/presentation/dev/floor_palette_panel.gd    — drop godmode entry
  scripts/core/maps/level_data.gd                     — DEFAULT_TILESET_PATH update
  data/maps/sample.json                               — tileset_path update
  data/maps/sample_waves.json                         — tileset_path update
  data/maps/_schema.md                                — godmode_terrain mentions replaced
  CLAUDE.md                                           — rule #7 rewritten
  HANDOFF.md                                          — append §current-state note about consolidated tileset, mention B-002 follow-up

DELETED:
  scenes/dev/godmode_terrain.tres
```

---

## Risk: regressions

The refactor is a 1:1 code move with renames. Highest-risk surfaces:

1. **`_ready` ordering.** Controller's `_ready` body was 140 lines of carefully sequenced setup. Moving it into `GodmodeSetup.run()` and calling that from the controller's `_ready` at the right point keeps order intact.
2. **`call_deferred` chains.** `_seed_slots`, `_emit_initial_turn`, `_select_deferred`, `bind_level`, `start_level` are all deferred. Each must remain deferred (not collapse into immediate calls during the move).
3. **`_world_processing` flag.** Currently a controller field, soon on AiDriver. Read sites: `_request_move`, `_wait_turn`, `_cast_slot`, `_on_world_turn_ended` (all input gates). Each becomes `_ctrl.ai.is_world_processing()`.
4. **`_cast_in_progress`** similarly migrates to CastFsm. Read sites: `_unhandled_input` (Esc, slot keys, RMB, LMB), `_refresh_hover_path`. Each becomes `_ctrl.cast_fsm.is_in_progress()`.
5. **`grid._moving`** — direct read of HexGrid's underscore-prefixed flag, used as input gate. Out of scope to fix here (touches HexGrid public API which is Egor's territory). Keep the read as-is.

Mitigation: tasks include manual smoke list (T28) covering the full input matrix, plus the tileset validation procedure.

---

## Out of scope (echoes spec, just for the impl branch)

- `map_editor_controller.gd` refactor (OQ-1: deferred post-jam).
- `move_range_overlay.gd` rework (already correct via 029 geometric path).
- `cast_range_overlay.gd` rework.
- B-002 fix.
- New EventBus signals.
- Reusing modules across godmode + arena_demo (OQ-2).
- Touching HexGrid public API (Egor's module).
