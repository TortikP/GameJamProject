# `data/tile_objects/` — JSON schema

> Adressee: Stasyan and any designer adding objects without writing code.
> Loaded by `TileObjectRegistry` (`scripts/core/arena/tile_object_registry.gd`)
> at `HexGrid.initialize()`. Filename **must** be `<id>.json` matching the `id`
> field inside.

---

## Field reference

### Always required

| Field | Type | Notes |
|---|---|---|
| `id` | string | Lowercase, snake_case, unique. Same as filename without `.json`. |
| `level` | int | `-1` LARGE, `0` SMALL, `1` ELEVATION. See "Levels" below. |
| `sprite_path` | string | `res://...` to the sprite. Presentation reads it; core never resolves. Empty string allowed for placeholders. |

### `blocks_movement`, `blocks_abilities_through` — read by registry, partly forced

| Level | `blocks_movement` | `blocks_abilities_through` |
|---|---|---|
| LARGE (-1) | always `true` (forced) | always `true` (forced) |
| SMALL (0) | **honoured** from JSON | always `false` (forced) |
| ELEVATION (1) | always `true` (forced) | always `true` (forced) |

If your JSON disagrees, the registry will warn and force-correct on load. Don't fight the schema — pick the right `level`.

### Destructible (optional component)

Active only when `breakable: true`. Other fields ignored otherwise.

| Field | Type | Default | Notes |
|---|---|---|---|
| `breakable` | bool | `false` | Toggles the component. |
| `hp` | int | `0` | Starting HP. `<=0` instantly destroys. |
| `armor_tags` | string[] | `[]` | Damage tags the object resists/accepts. Empty = anything breaks it. Reuse skill-tag vocabulary (`physical`, `fire`, ...). |

### Behavior triggers (independent flags)

Behavior is a reference to a `data/tile_effects/<id>.json` (the existing tile-effects registry — `damage_zone`, `heal_fountain`, `burning`, ...). Triggers say *when* it fires.

| Field | Type | Default | When it fires | Allowed for |
|---|---|---|---|---|
| `behavior_effect_id` | string | `""` | — | any. Empty = no behavior. |
| `applies_on_enter` | bool | `false` | actor steps onto the tile | SMALL **walkable** only |
| `applies_on_turn_end` | bool | `false` | actor ends a turn standing on it | SMALL **walkable** only |
| `aura_radius` | int | `0` | end of every turn, applies to all actors within R hexes | LARGE / SMALL non-walkable / SMALL walkable. `0` = off, `>=1` = on. |
| `applies_on_attacked` | bool | `false` | object takes damage | any **breakable** object (otherwise pointless — registry warns) |

Forbidden combos are auto-zeroed with a warning at load time:
- ELEVATION cannot have any behavior — all four flags forced to `false`/`0`.
- LARGE / SMALL non-walkable: cannot have `applies_on_enter` / `applies_on_turn_end` (actor cannot stand there). Aura and on_attacked OK.
- Any trigger flag set without `behavior_effect_id` → all triggers zeroed.

### Linger (optional, SMALL walkable only)

After an actor leaves the tile, a tile-effect with `duration > 0` keeps ticking on them for that many turns (DoT). Resolver-driven (follow-up feature `019-tile-object-resolver`); 018 emits `tile_object_actor_exited` and the resolver listens.

| Field | Type | Default | Notes |
|---|---|---|---|
| `linger_effect_id` | string | `""` | Reference to `data/tile_effects/<id>.json` with `duration > 0` — e.g. `"burning"`. Empty = no linger. |

If set on a non-(SMALL walkable) object → registry forces empty + warns. The referenced effect must have `duration > 0` for the linger to be meaningful (registry will warn if not, but loads).

### Synergy tags

| Field | Type | Default | Notes |
|---|---|---|---|
| `tags` | string[] | `[]` | Free-form labels for the modifier engine. Vocabulary: `flammable`, `freezable`, `conductive`, `wood`, `stone`, `metal`, `liquid`, `plant`, `furniture`, `hazard`, `construct`, ... add new ones as needed — they are matched by spell modifiers downstream. |

### On-destroy (only meaningful when `breakable: true` and HP→0)

| Field | Type | Default | Notes |
|---|---|---|---|
| `on_destroy_effect_id` | string | `""` | Tile-effect that lingers on the cell after the object is destroyed (e.g. burning barrel → `damage_zone`). |
| `on_destroy_spawn_object_id` | string | `""` | Tile-object id to replace the destroyed one with (e.g. ice column → water puddle). Both fields can be set together. |

### Audio / visual hints

| Field | Type | Default | Notes |
|---|---|---|---|
| `vfx_destroy` | string | `""` | `res://assets/vfx/...` PackedScene. Played by presentation on destroy. |
| `sfx_destroy` | string | `""` | `res://assets/audio/sfx/...`. Played by presentation on destroy. |

There is no `vfx_idle` / `sfx_idle` — `sprite_path` is the idle visual. Animated objects need a separate feature.

---

## Levels — picking the right one

Use this decision tree:

1. Does an actor ever stand on this tile? **No** → LARGE (`-1`) or ELEVATION (`1`).
   - Is it interactive (has aura, on_attacked, breakable, on-destroy reaction)? **Yes** → LARGE.
   - Is it pure terrain (mountain, cliff, column)? **Yes** → ELEVATION.
2. **Yes**, actor stands on it → SMALL (`0`).
   - Walkable through (lava puddle, swamp, ice patch)? `blocks_movement: false`.
   - Blocks movement (table, barrel, bush)? `blocks_movement: true`.

Rule of thumb: if you find yourself wanting "blocks movement, has aura, has on_enter" — that's not allowed by design. SMALL non-walkable doesn't trigger on_enter (you can't enter). Either make it SMALL walkable, or use aura/on_attacked instead.

---

## Reference samples (live in this directory)

- `mountain.json` — ELEVATION; pure terrain block.
- `boulder.json` — LARGE breakable hp=10, armor_tags=[physical]; blocks movement and abilities, can be destroyed.
- `heal_fountain.json` — LARGE, behavior=`heal_fountain`, `aura_radius: 1`. Heals adjacent actors at turn end.
- `lava_pool.json` — SMALL walkable, behavior=`damage_zone`, `applies_on_enter: true`, `applies_on_turn_end: true`, `linger_effect_id: "burning"`. Hits on entry, ticks while standing, applies `burning` (duration 2) when leaving.
- `wooden_barrel.json` — SMALL non-walkable, breakable hp=2, `on_destroy_effect_id: "damage_zone"`. Bomb barrel — destroying spreads fire.
- `wooden_table.json` — SMALL non-walkable, breakable hp=2, no behavior. Pure cover/blocker.

---

## Don't / common mistakes

- **Don't** invent new top-level fields without first adding them to `TileObject` and the registry. Unknown JSON keys are silently ignored.
- **Don't** put non-tile-effect ids in `behavior_effect_id` / `linger_effect_id`. Both reference `data/tile_effects/`.
- **Don't** set both `on_destroy_effect_id` and `on_destroy_spawn_object_id` to the same target type — they layer (effect on tile + new object on tile). Make sure the combo makes sense.
- **Don't** rename `id` after content references it. Once `lava_pool` is painted on a TileMap, renaming the file to `lava.json` orphans the cells.
- **Don't** put walkable=false SMALL with `applies_on_enter` — it will be force-zeroed on load. Use aura or on_attacked.
