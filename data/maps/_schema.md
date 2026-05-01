# Map JSON schema (`data/maps/*.json`)

Maps are normally drawn in the in-game editor (Map Editor button, or **Ctrl+E**)
and saved to this folder. The format below is what the editor writes; it's also
hand-editable if you want to tweak something quickly without launching the game.

## Top-level fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | yes | Human-readable name. Filename is `<sanitized_name>.json` (lowercase, `[^a-z0-9_-]` → `_`). |
| `version` | int | yes | Schema version. Current = `1`. |
| `tileset_path` | string | yes | `res://...` path to a `.tres` TileSet. Default: `res://scenes/dev/godmode_terrain.tres`. |
| `floor` | array | yes | Each painted hex. Empty array = empty map (won't pass validation if you also have a player spawner with no floor under it). |
| `objects` | array | yes (may be empty) | TileObjects (018) placed on the floor. |
| `spawners` | array | yes | Must contain exactly one `player` spawner. |

## `floor[]` entry

```json
{ "coord": [3, 2], "source_id": 0, "atlas_coord": [0, 0] }
```

- `coord` — `[col, row]` in TileMapLayer cell space. `Vector2i` serialized as 2-element array.
- `source_id` — TileSet source index. For `godmode_terrain.tres`: only `0`. For `hex_terrain.tres`: also `0`.
- `atlas_coord` — `[ax, ay]` within the TileSetAtlasSource. Picks which tile graphic.

## `objects[]` entry

```json
{ "coord": [3, 2], "object_id": "lava_pool" }
```

- `coord` — must match a coord that exists in `floor[]`. Out-of-floor objects are dropped at load time with a warning.
- `object_id` — must match a JSON file in `data/tile_objects/` (without `.json`). Unknown ids are dropped with a warning.

Current valid `object_id`s: `boulder`, `heal_fountain`, `lava_pool`, `mountain`, `wooden_barrel`, `wooden_table`.

One object per coord. The editor enforces this; hand edits that break it are caught by `LevelData.validate()` on save/load.

## `spawners[]` entry

```json
{ "coord": [4, 4], "kind": "player", "ref": "" }
{ "coord": [6, 4], "kind": "enemy",  "ref": "manekin" }
```

- `coord` — must match a `floor[]` coord and not collide with another spawner or object.
- `kind` — `"player"` or `"enemy"`. Exactly one `"player"` is required.
- `ref` —
  - For `player`: `""` (empty).
  - For `enemy`: enemy_id matching a JSON file in `data/enemies/` (without `.json`). Currently: `manekin`.

If `kind == "enemy"` and `ref` is unknown, the spawner is skipped at load time.

## Full example

```json
{
  "name": "Tutorial 1",
  "version": 1,
  "tileset_path": "res://scenes/dev/godmode_terrain.tres",
  "floor": [
    { "coord": [0, 0], "source_id": 0, "atlas_coord": [0, 0] },
    { "coord": [1, 0], "source_id": 0, "atlas_coord": [0, 0] },
    { "coord": [2, 0], "source_id": 0, "atlas_coord": [0, 0] }
  ],
  "objects": [
    { "coord": [1, 0], "object_id": "lava_pool" }
  ],
  "spawners": [
    { "coord": [0, 0], "kind": "player", "ref": "" },
    { "coord": [2, 0], "kind": "enemy",  "ref": "manekin" }
  ]
}
```

## Validation errors

`LevelData.validate()` returns a list of error strings; the editor blocks save if non-empty:

- `Object <id> on unpainted tile <coord>` — object's coord is not in `floor[]`.
- `Tile <coord> already occupied` — two objects/spawners on the same hex.
- `Spawner <kind> on unpainted tile <coord>` — spawner's coord is not in `floor[]`.
- `No player spawner — set Player Spawn before saving`.
- `Multiple player spawners (N) — only one allowed`.

## Reserved filenames

The map editor writes two transient files that are gitignored:

- `__autosave__.json` — debounced editor autosave (every 1.5s of activity). Lives between sessions if the editor was closed without explicit save; you'll be offered "Restore?" on next open.
- `__playtest__.json` — written when the editor's **Playtest** button is used. Read by the battle scene through the `ActiveLevel` autoload, then ignored. Don't manually save a real map under either name — the editor will refuse the filename.
