# Skill offer pool JSON schema (`data/skill_offer_pools/*.json`)

A pool is a list of skill ids that the runtime samples from when a wave's
`skill_offer.pool` references this file. For waves with
`skill_offer.source = "defeated_enemies"`, this same list acts as a whitelist:
only skills from enemies defeated during that wave and present in this pool can
appear. The runtime is `SkillOfferController` (autoload,
`scripts/runtime/skill_offer_controller.gd`).

Filenames are arbitrary; the `id` field inside is what map JSON references.
Files starting with `_` (e.g. this one) are skipped by the loader.

## Top-level fields

```json
{
  "id": "basic",
  "label_key": "skill_offer.pool.basic.name",
  "skills": [
    "ball_throw",
    "berry_throw",
    "honey_cold"
  ],
  "weights": {
    "summon_bee": 0.5
  },
  "min_player_level": 0,
  "tags": ["starter"]
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | StringName key; map JSON's `skill_offer.pool` matches this. Convention: lowercase, snake_case. Empty / missing → file dropped with a warning. |
| `label_key` | string | no | localization key for designer-facing dropdown label. Falls back to `id` when missing. |
| `skills` | array of string | yes | Skill ids resolved through `SkillDatabase.get_skill`. Unknown ids are dropped from the effective pool at runtime with a `warn_once` log. |
| `weights` | dict | no | Per-id relative weight (default 1.0). Sampling uses cumulative weights without normalisation. Set to `0.0` to fully exclude an id from this pool without removing it from `skills`. |
| `min_player_level` | int | no | Reserved for future progression. Not enforced in v1. |
| `tags` | array of string | no | Metadata for designer organisation. Not consumed by runtime in v1. |

## Sampling semantics

1. Filter `skills` by:
   - `SkillDatabase.has_skill(id)` (drop unknowns).
   - If wave's `skill_offer.exclude_owned == true` AND neither `allow_upgrade`
     nor `allow_replace` is set, drop ids the player already owns.
2. Sample up to `count` unique ids by weight without replacement.
3. For each sampled id, build a card with mode resolved against player state:
   - not owned → `add`
   - owned + `allow_upgrade` → `upgrade` (skill `level += 1` on apply)
   - owned + `allow_replace` → `replace` (player picks slot in sub-screen)
   - owned + neither → card dropped
4. If post-filter pool is smaller than `count`, fewer cards are shown. The
   modal sizes to the actual count — never pads with placeholders.

## Pool < count edge case

A pool of 4 ids with `count=3` and 2 already owned (no upgrade/replace)
yields 2 cards. UI handles this; no warning. A pool of 0 ids (everything
filtered out) skips the offer entirely with a `warn` log — wave transition
proceeds as if `skill_offer` was absent.

## Authoring tips

- Keep one starter pool (`basic.json`) and per-act / per-biome pools as the
  game grows. Don't shove all skills into one pool — players see the same
  cards every wave.
- `weights` is the lever for "rare but possible" — drop `summon_bee` to 0.3
  if it's strong; lift `weaken` to 1.5 if testing shows underuse.
- The editor doesn't currently expose `weights`. Edit by hand here.
