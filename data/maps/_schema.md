# Map JSON schema (`data/maps/*.json`)

Maps are normally drawn in the in-game editor (Map Editor button, or **Ctrl+E**)
and saved to this folder. The format below is what the editor writes; it's also
hand-editable if you want to tweak something quickly without launching the game.

## Top-level fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | yes | Human-readable name. Filename is `<sanitized_name>.json` (lowercase, `[^a-z0-9_-]` → `_`). |
| `version` | int | yes | Schema version. Current = `3` (added wave-level `respawn_player`/`advance_mode`/`music_config` and spawner `amount`/`delay` in 061). |
| `tileset_path` | string | yes | `res://...` path to a `.tres` TileSet. Default: `res://scenes/arena/tilesets/hex_terrain.tres`. |
| `waves` | array | yes | Sequence of waves. Wave 0 = initial state. Last wave's `turns_to_next` must be 0. |
| `dialogue_triggers` | array | optional | Per-level event→dialogue bindings (added in 039). See section below. |
| `music_config` | object | optional | Procedural music config (added in 042). See section below. |

### Migration

`v1` files (root-level `floor`/`objects`/`spawners`, no `waves[]`) are accepted for read and folded into a single-wave layout. `v2` files (`is_special` as bool, no `respawn_player`/`advance_mode`/`music_config`/`amount`/`delay`) are migrated transparently:

- `is_special: true` → `"boss"`, `is_special: false` → `"normal"` (free-form string post-061).
- `respawn_player` defaults to `true` for wave 0 and `false` for the rest.
- `advance_mode` defaults to `"timer"`.
- `music_config` defaults to `{}` (per-wave override; falls back to level-level `music_config`).
- spawner `amount`/`delay` default to `1` (no behavioural change vs v2).

Migration is idempotent. The editor always writes `v3`. Hand-edited `v1`/`v2` files keep working.

## `waves[]` entry

```json
{
  "index": 0,
  "is_special": "normal",
  "turns_to_next": 5,
  "respawn_player": true,
  "advance_mode": "timer",
  "music_config": {},
  "floor":    [ /* same shape as legacy LevelData.floor */ ],
  "objects":  [ /* same shape as legacy LevelData.objects */ ],
  "spawners": [ /* see "spawners[]" section below */ ]
}
```

- `index` — must equal the wave's position in the array (0-based, contiguous). The loader reindexes defensively.
- `is_special` — free-form string visual tag (061). Convention: `"normal"` (default), `"boss"`, `"miniboss_*"`. Anchors with non-`"normal"` value render larger on the timeline. No mechanical effect — runtime-side it's surfaced via `is_wave_special()` (any non-`"normal"` value is special).
- `turns_to_next` — turns from this wave's start until the next wave auto-advances. Must be `>= 1` for every wave except the last; the last wave **must** have `turns_to_next: 0`. Auto-clear (kill all enemies + no pending spawners) advances earlier and credits the unused turns to `RunScore`.
- `respawn_player` (061) — bool. When `true`, the player actor is re-spawned at the wave's player spawner on wave start. Wave 0 implicit `true` (designer can leave it absent on a fresh wave 0). Validation requires that `respawn_player: true` waves have a `kind: "player"` spawner.
- `advance_mode` (061) — `"timer"` (default), `"clear"`, or `"timer_and_clear"`. Controls how `WaveController` ends this wave:
  - `"timer"` — wave ends when `turns_into_wave >= turns_to_next` (existing behaviour).
  - `"clear"` — timer is ignored entirely; wave ends only when the last enemy dies (auto-clear path). Validation WARNs if no enemy spawner exists.
  - `"timer_and_clear"` — timer expiry sets a "waiting for clear" gate; wave ends when the last enemy dies. The HUD draws a `(waiting for clear)` cue near the cursor while the gate is active.
- `music_config` (061) — Dictionary. Per-wave override over the level-level `music_config`. Empty `{}` falls back to level config. Same shape as the level field (see 042 section).
- `floor` / `objects` / `spawners` — full snapshot of the world at this wave's start. No diffs. Reordering or inserting waves does not cascade to neighbours.

## `floor[]` entry (per wave)

```json
{ "coord": [3, 2], "source_id": 0, "atlas_coord": [0, 0] }
```

- `coord` — `[col, row]` in TileMapLayer cell space. `Vector2i` serialized as 2-element array.
- `source_id` — TileSet source index. For `hex_terrain.tres`: `0` (godmode_atlas: Katya's grass tile, the default) or `1` (hex_atlas placeholder palette: grass/wall/swamp/acid/fountain). It's the only tileset shipped post-032.
- `atlas_coord` — `[ax, ay]` within the TileSetAtlasSource. Picks which tile graphic.

## `objects[]` entry (per wave)

```json
{ "coord": [3, 2], "object_id": "lava_pool" }
```

- `coord` — must match a coord that exists in the same wave's `floor[]`. Out-of-floor objects are dropped at load time with a warning.
- `object_id` — must match a JSON file in `data/tile_objects/` (without `.json`). Unknown ids are dropped with a warning.

Current valid `object_id`s: `boulder`, `heal_fountain`, `lava_pool`, `mountain`, `wooden_barrel`, `wooden_table`.

One object per coord per wave. The editor enforces this; hand edits that break it are caught by `LevelData.validate()` on save/load.

## `spawners[]` entry (per wave)

```json
{ "coord": [4, 4], "kind": "player", "ref": "",        "timer": 1, "amount": 1, "delay": 1 }
{ "coord": [6, 4], "kind": "enemy",  "ref": "manekin", "timer": 3, "amount": 1, "delay": 1 }
```

- `coord` — must match the same wave's `floor[]` coord and not collide with another spawner or object.
- `kind` — `"player"` or `"enemy"`. **Exactly one `"player"` is required across the union of all waves.**
- `ref` —
  - For `player`: `""` (empty).
  - For `enemy`: enemy_id matching a JSON file in `data/enemies/` (without `.json`). Currently: `manekin`.
- `timer` — integer `>= 1`. Counted **down** at the end of each `world_turn_ended` from the wave's start. When the timer ticks from 1→0, the actor instantiates on the next world-turn end and the placeholder disappears. Pending spawners are discarded if the wave changes before they fire.
- `amount` (061) — integer `>= 1`. **Schema-only in 061** — the editor stores it; runtime currently treats every spawner as `amount = 1`. Reserved for "spawn N enemies in a row from this spawner". Designer-facing UI tags the field `(schema-only)` when `> 1` so the editor doesn't lie about effect.
- `delay` (061) — integer `>= 1`. **Schema-only in 061** — also reserved. Future use: cooldown between successive spawns when `amount > 1`. Schema field exists so v3 maps don't need re-migration when runtime support lands.

If `kind == "enemy"` and `ref` is unknown, the spawner is skipped at load time.

## Full example (3-wave level)

```json
{
  "name": "Tutorial Waves",
  "version": 2,
  "tileset_path": "res://scenes/arena/tilesets/hex_terrain.tres",
  "waves": [
    {
      "index": 0,
      "is_special": false,
      "turns_to_next": 5,
      "floor": [
        { "coord": [0, 0], "source_id": 0, "atlas_coord": [0, 0] },
        { "coord": [1, 0], "source_id": 0, "atlas_coord": [0, 0] },
        { "coord": [2, 0], "source_id": 0, "atlas_coord": [0, 0] }
      ],
      "objects": [],
      "spawners": [
        { "coord": [0, 0], "kind": "player", "ref": "",        "timer": 1 },
        { "coord": [2, 0], "kind": "enemy",  "ref": "manekin", "timer": 2 }
      ]
    },
    {
      "index": 1,
      "is_special": true,
      "turns_to_next": 6,
      "floor": [
        { "coord": [0, 0], "source_id": 0, "atlas_coord": [0, 0] },
        { "coord": [1, 0], "source_id": 0, "atlas_coord": [0, 0] },
        { "coord": [2, 0], "source_id": 0, "atlas_coord": [0, 0] }
      ],
      "objects": [],
      "spawners": [
        { "coord": [2, 0], "kind": "enemy", "ref": "manekin", "timer": 3 }
      ]
    },
    {
      "index": 2,
      "is_special": false,
      "turns_to_next": 0,
      "floor": [
        { "coord": [0, 0], "source_id": 0, "atlas_coord": [0, 0] },
        { "coord": [2, 0], "source_id": 0, "atlas_coord": [0, 0] }
      ],
      "objects": [],
      "spawners": []
    }
  ]
}
```

## Validation errors

`LevelData.validate()` returns a list of error strings; the editor blocks save if any non-`WARN:` entries are present:

- `Wave N has index M (expected N)` — file has non-contiguous wave indices. Editor reindexes on load defensively, so this should only fire on hand-edits.
- `Wave N turns_to_next must be >= 1 (got M)` — non-final waves need a positive turn budget.
- `Last wave (N) turns_to_next must be 0 (got M)` — the final wave is closed by `level_completed`, not by a timer.
- `Wave N: object <id> on unpainted tile <coord>` — object's coord is not in this wave's `floor[]`.
- `Wave N: tile <coord> already occupied` — two objects/spawners on the same hex within one wave.
- `Wave N: spawner <kind> on unpainted tile <coord>` — spawner's coord is not in this wave's `floor[]`.
- `Wave N: spawner timer must be >= 1 (got M)`.
- `WARN: Wave N: spawner timer (M) > turns_to_next (K) — won't trigger` — non-blocking; designer may have meant it (the spawner is intentionally inert in this wave).
- `No player spawner — set Player Spawn in some wave before saving`.
- `Multiple player spawners (N) across waves — only one allowed total`.

## Reserved filenames

The map editor writes two transient files that are gitignored:

- `__autosave__.json` — debounced editor autosave (every 1.5s of activity). Lives between sessions if the editor was closed without explicit save; you'll be offered "Restore?" on next open.
- `__playtest__.json` — written when the editor's **Playtest** button is used. Read by the battle scene through the `ActiveLevel` autoload, then ignored. Don't manually save a real map under either name — the editor will refuse the filename.

## dialogue_triggers (added in 039)

Optional. Array of trigger dictionaries. Defaults to `[]` for legacy files.

```json
{
  "id": "lvl2_intro",
  "event": "level_started",
  "dialogue_id": "boss_intro",
  "play_mode": "play",
  "conditions": {
    "wave_index": 0,
    "absolute_turn": 40,
    "cleared_in_turns_lt": 4,
    "mood_required": ["burnout"],
    "chance": 1.0,
    "once_per_run": true,
    "once_per_session": false
  }
}
```

All conditions are optional and AND-combined. Curated events:
`level_started`, `wave_about_to_start`, `wave_started`, `wave_cleared`,
`world_turn_ended`, `skill_offer_about_to_open`, `skill_offer_closed`,
`level_completed`. Open vocabulary — any `EventBus.<signal_name>` is accepted
at runtime (warn-once if signal not found, remaining triggers still work).

`play_mode`: `"play"` forces a specific dialogue id; `"request"` runs the
selector in DialogueManager (picks by tag/conditions/played-set).

## waves[i].skill_offer (added in 040)

Optional. When present on a wave, the runtime opens a Hades-style "pick a
skill" modal **after that wave clears** (all enemies dead, no pending
spawners) and **before the next wave's snapshot applies**. Absent / null →
no offer, transition is silent.

```json
{
  "skill_offer": {
    "pool": "basic",
    "source": "pool",
    "count": 3,
    "allow_upgrade": true,
    "allow_replace": true,
    "force_replace": false,
    "allow_skip": false,
    "exclude_owned": false
  }
}
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `pool` | string | required | id of a JSON file in `data/skill_offer_pools/` (without `.json`). |
| `source` | string | `"pool"` | `"pool"` samples the configured pool directly. `"defeated_enemies"` samples only skills owned by enemies killed in this wave, then filters them through `pool` as a whitelist. |
| `count` | int | 3 | how many cards to show. Pool may yield fewer if filters cut deeper than expected. |
| `allow_upgrade` | bool | true | a card for an already-owned skill becomes "upgrade level → N+1" instead of being dropped. |
| `allow_replace` | bool | true | when slots are full, card can offer to replace a chosen slot. Triggers a sub-screen with slot picker. |
| `force_replace` | bool | false | when true, new-skill cards use replace mode even if an empty slot exists. Story campaign uses this to make every offer a deliberate slot swap. |
| `allow_skip` | bool | false | shows a Skip button. `mode=&"skipped"` on the closed signal. |
| `exclude_owned` | bool | false | filters owned skill ids from the pool entirely (regardless of allow_upgrade/replace). |

**Last wave.** Putting `skill_offer` on the final wave is allowed — the modal
opens before `level_completed`. Useful for "boss reward" framing.

**Turn runout.** v1 only fires offers when the wave clears via kill-all
(emits `wave_cleared`). If the player exhausts `turns_to_next` with enemies
still alive, the next wave applies without an offer. Designers wanting a
guaranteed offer should keep waves short enough that clear-by-kill is the
expected path.

**Pool file format** — see `data/skill_offer_pools/_schema.md`.

---

## `music_config` (042 — proc-music, optional)

Per-level procedural music configuration. All fields optional. Absent = defaults.

```json
{
  "music_config": {
    "preset":     "tense_arena",
    "seed":       1234,
    "bpm":        96,
    "base_state": "calm",
    "stings": {
      "wave_clear": "blip_up",
      "victory":    "fanfare",
      "defeat":     "descending"
    },
    "lead_density_calm":   0.3,
    "lead_density_battle": 0.7,
    "pad_gain_db":   0,
    "drums_gain_db": 0,
    "muted": false
  }
}
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `preset` | StringName | — | id from `data/music/presets.json`. Other fields below override. |
| `seed` | int | `hash(level.name) & 0x7fffffff` | RNG seed for procedural patterns. |
| `bpm` | float | 96 | clamped 40..200. |
| `base_state` | string | "calm" | "calm" or "battle". |
| `stings` | dict | — | sting id per event (`wave_clear`, `victory`, `defeat`). |
| `lead_density_calm` | float | 0.3 | 0..1. |
| `lead_density_battle` | float | 0.7 | 0..1. |
| `pad_gain_db` | float | 0 | dB offset. |
| `drums_gain_db` | float | 0 | dB offset. |
| `muted` | bool | false | silences music for this level. |

Resolution order: hardcoded defaults → preset → explicit fields.
See `data/music/presets.json` for named presets. Use Music Lab
(`scenes/dev/music_lab.tscn`, F6) for A/B tuning + Copy JSON.
