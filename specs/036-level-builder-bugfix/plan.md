# 036 — Plan

## Architecture target

**One scene** — `scenes/dev/enemy.tscn`. Generic. Texture loaded at runtime from `enemy_data_id` → `data/enemies/<id>.json` → `sprite` field.

**One preloaded `PackedScene`** in `level_loader.gd`. No id-keyed dict.

**One source of truth** for "what enemies exist" — `data/enemies/*.json`. Editor and runtime both list / consume from it.

## Step-by-step

### 1. Extend `EnemyDataLoader.apply_to_actor` to also resolve sprite

`scripts/core/actors/enemy_data_loader.gd` currently writes `max_hp / team / speed / behavior_id / skills` onto the actor. Add: if `data.has("sprite")`, hand the path back to the caller so the view can apply it.

Two options:
- **A.** Add `sprite_path` field on `Actor` (or a `ViewConfig` struct) and have the view read it after `super._ready()`.
- **B.** Return a small `Dictionary` from `apply_to_actor` with the bits the view needs (sprite path, healthbar offset later, etc.) and let the view apply them.

Pick **B** — keeps `Actor` (core) free of presentation-only fields. Matches CLAUDE.md hard-rule #1 ("scripts/core/ knows nothing about specific textures, audio files, or scenes").

Signature change:

```gdscript
# Returns dict with view hints, or empty dict on failure.
# Keys: "sprite" (String, res:// path), maybe more later.
static func apply_to_actor(actor: Actor, enemy_id: StringName) -> Dictionary
```

Existing callers (`manekin_view.gd`) currently use the bool return for fallback logic. Rewrite as `not view_hints.is_empty()` or just check `actor.max_hp > 0` after the call.

Sprite path in JSON is repo-relative (`assets/sprites/enemies/bear.png`). Prefix `res://` when handing back, or document the contract — pick prefixing, less foot-gun.

### 2. Make `manekin_view.gd` apply sprite from view hints

Currently `_ready()` calls `_EnemyDataLoader.apply_to_actor(self, enemy_data_id)` and that's it. Body texture comes from the scene. Change:

```gdscript
var hints: Dictionary = _EnemyDataLoader.apply_to_actor(self, enemy_data_id)
if hints.has("sprite"):
    var tex: Texture2D = load(hints["sprite"]) as Texture2D
    if tex != null:
        var body := get_node_or_null("Body") as Sprite2D
        if body != null:
            body.texture = tex
```

Rename file → `enemy_view.gd`. The `manekin_view` name is a fossil from when manekin was the only enemy.

### 3. Create `scenes/dev/enemy.tscn`

Strip texture from existing `manekin.tscn`. Body still has a `Sprite2D` node — just no `texture` set in the .tscn (leaves it null until `_ready()` writes one). Keep `HealthBar` and `StatusIconStrip`. Set `enemy_data_id` to `&""` (no default — must be set per-spawn).

Set `team = &"enemy"` on the root.

### 4. Spawn-time `enemy_data_id` injection

`level_loader.gd` already has the `enemy_id` at spawn. After `scene.instantiate()`, set `enemy.enemy_data_id = enemy_id` BEFORE `add_child` so `_ready()` picks it up.

```gdscript
var enemy: Actor = ENEMY_SCENE.instantiate() as Actor
enemy.enemy_data_id = enemy_id     # set before _ready
enemy.actor_id = StringName("%s_%03d" % [enemy_id, idx_for_id])
enemy.position = grid.tile_map_layer.map_to_local(coord)
actors_node.add_child(enemy)       # _ready runs here, loads JSON, applies sprite
```

### 5. Collapse `ENEMY_SCENES` to one preload

`scripts/core/maps/level_loader.gd`:

```gdscript
const ENEMY_SCENE: PackedScene = preload("res://scenes/dev/enemy.tscn")
```

Drop `MANEKIN_SCENE`, `BUSH_SCENE`, `ENEMY_SCENES`. Both `spawn_enemy_at` and `_spawn_enemy` use `ENEMY_SCENE` directly.

The "unknown enemy_id" warn becomes "missing JSON" — and that's already handled in `EnemyDataLoader.apply_to_actor` (warns + returns empty dict). Caller (`level_loader`) checks empty hints, treats as failure, queue_frees the partially-spawned actor and returns null. That's stricter than today (today we silently succeed on unknown), so it's a net win.

Actually — better: validate JSON presence upfront in `level_loader._spawn_enemy` before instantiation, with a single `FileAccess.file_exists()` check. Avoids creating-then-destroying nodes.

### 6. Delete `manekin.tscn`, `bush.tscn`

Grep first: `manekin.tscn` may be referenced from godmode test sandboxes (`scenes/dev/godmode.tscn`?). If yes, those refs need to swap to `enemy.tscn` + set `enemy_data_id` in the inspector.

### 7. Validate sprite paths in JSONs

All 12 JSONs already have `"sprite": "assets/sprites/enemies/<id>.png"`. Quick script-free check: paths exist on disk. If any mismatch (e.g. `bush.json` says `assets/sprites/enemies/bush.png` but that file is `assets/sprites/bush.png`), pick one location and align.

Looking at current state: `assets/sprites/enemies/` has all 12 sprites. `assets/sprites/` (root) has duplicates of `bush.png` / `manekin.png` / `player.png`. Move JSONs to point at `enemies/` subfolder consistently and delete the root duplicates (or leave them — `player.png` may be referenced by player.tscn).

### 8. Sprite import status

`assets/sprites/enemies/*.png` have **no `.import` files** in the working tree (check: `ls assets/sprites/enemies/*.import` is empty). Godot generates these on editor open. If runtime tries `load("res://assets/sprites/enemies/bear.png")` and there's no `.import`, it fails silently (returns null).

Verify locally: open Godot once, let it import, commit `.import` files. If they're already in `.gitignore`, fine — each dev gets them on first open. Document in HANDOFF if not already.

## Risks

- **Existing levels.** Levels saved before this PR have `enemy_id`s like `&"manekin"` / `&"bush"`. New code resolves both via JSON which still exists → still works. No migration needed.
- **Per-enemy view differences.** Current `manekin.tscn` has a `StatusIconStrip` child; `bush.tscn` doesn't. Going generic means everyone gets the strip (or no one does). Pick: everyone gets it. Bush is a non-acting enemy; an empty strip is invisible.
- **Healthbar offset differences.** `bush.tscn` y_offset = -51, `manekin.tscn` y_offset = -48. Negligible. Use -50 in generic scene; if a designer complains, add `healthbar_y_offset` to JSON. Don't preempt.
- **Texture filter.** `bush.tscn` sets `texture_filter = 1` (nearest) on `Body`, `manekin.tscn` doesn't. Pick nearest in generic scene — sprites are pixel art, don't blur on scale.

## Non-goals

- No EnemyRegistry singleton autoload. Tempting but unnecessary — `data/enemies/` directory IS the registry. Both call sites (editor + loader) read it directly. Adding a singleton is the kind of "for the future" abstraction CLAUDE.md tells us not to add.
- No `BUSH_SCENE` / `MANEKIN_SCENE` rescue behavior for backward compat. The scenes are deleted in this PR, full stop.
