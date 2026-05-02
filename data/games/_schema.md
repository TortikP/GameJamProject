# `data/games/` — schema (035-game-editor v1)

Each `*.game.json` in this folder is a **GameData** — an ordered list of map
files (from `data/maps/`) that play one after another, with an upgrade screen
between levels and a "you win" screen at the end. The Game Editor (main menu →
**Game Editor**) is the canonical authoring tool; this doc exists for hand-edit
and PR review.

File extension **must** be `.game.json` (not just `.json`) — the Load Game
file dialog filters on this and the Game Editor enforces it on save.

## Top-level shape

```json
{
  "name":   "Display name shown in HUD / win screen.",
  "version": 1,
  "levels": [ <LevelEntry>, ... ]
}
```

| Field | Type | Notes |
|---|---|---|
| `name` | string | Free-form. Used as default filename basename (sanitized). |
| `version` | int | Schema version. Currently `1`. Loader warns on mismatch but proceeds. |
| `levels` | array of LevelEntry | Order matters. ≥ 1 entry required. |

## LevelEntry

```json
{
  "map_path":     "res://data/maps/sample.json",
  "display_name": "Awakening",
  "cutscene_id":  "intro_awakening",
  "is_intro":     true
}
```

| Field | Type | Notes |
|---|---|---|
| `map_path` | string (`res://...json`) | Must reference an existing file under `data/maps/`. Loader **drops** entries whose file is missing (warn-toast). |
| `display_name` | string | Optional. Shown in future cutscene title cards / HUD banners. Empty string allowed. |
| `cutscene_id` | string | Optional. If non-empty, `EventBus.campaign_cutscene_requested` fires when this level loads. Listener (a future cutscene-system spec) plays the cutscene; missing listener → silent no-op (timeout 0.5s). Empty string = no cutscene. |
| `is_intro` | bool | At most one level may be `true`. Marks "the first level of a fresh playthrough" — used by future intro logic (e.g. show-once tutorial overlays). The Game Editor enforces exclusivity at edit time; the loader auto-clears extras with warn-toast. |

## Validation

`GameData.validate()` returns a list of messages prefixed with `REJECT:` or
`WARN:`. The Game Editor:

- Refuses to **save** any file with a `REJECT` message.
- Surfaces `WARN` messages as toasts but writes anyway.
- Refuses to **playtest** with `REJECT`.

Reject conditions:
- `levels` is empty (need ≥ 1).
- All entries dropped during validation (every `map_path` missing or invalid).

Warn conditions:
- Empty / `.json`-less / not-found `map_path` → entry dropped.
- Multiple `is_intro=true` → first kept, rest cleared.

## Hand-editing

`name` is set freely; the Game Editor sanitizes it into a basename when saving
to `<name>.game.json`. If you hand-edit and save under a different filename,
that's fine — `ActiveGame.load_game()` doesn't care about filename matching.

`map_path` order is the play order. Reorder by swapping array entries. The
editor's ↑/↓ buttons do this for you.

## Example

See `sample.game.json` next to this file: 2 levels, first is intro with a
cutscene id (the cutscene playback engine doesn't exist in v1 of this spec,
so the id is a no-op until that ships).

## What's NOT here

- **Per-level enemy / loot overrides.** `LevelData` (the map) is self-contained
  and the campaign just references it. Two campaigns can reuse the same map
  with no issues.
- **Branching.** Linear only.
- **Mid-game saves.** Returning to main menu drops campaign progress.
- **Per-game upgrade pools / modifiers.** That's the upgrade-screen spec's
  problem, not GameData's.
